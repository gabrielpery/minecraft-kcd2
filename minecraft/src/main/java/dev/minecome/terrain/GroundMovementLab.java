package dev.minecome.terrain;

import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.minecraft.client.MinecraftClient;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.registry.entry.RegistryEntryList;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.Difficulty;
import net.minecraft.world.GameMode;
import net.minecraft.world.GameRules;
import net.minecraft.world.biome.BiomeKeys;
import net.minecraft.world.gen.GeneratorOptions;
import net.minecraft.world.gen.WorldPresets;
import net.minecraft.world.gen.chunk.FlatChunkGenerator;
import net.minecraft.world.gen.chunk.FlatChunkGeneratorConfig;
import net.minecraft.world.level.LevelInfo;
import net.minecraft.resource.DataConfiguration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Static sampled-heightfield collision/input probe. No transport, host movement writes or physics replacement. */
public final class GroundMovementLab {
    private static final Logger LOG=LoggerFactory.getLogger("MineComeGroundMovement");
    private static final double SPAWN_X=0.5,SPAWN_Z=0.5;
    private static volatile GroundMovementLab active;
    private final GroundPatch patch;
    private final String traceFile=System.getProperty("minecome.movementTraceFile");
    private MovementTraceSink trace;
    private boolean firstTraceSamplePending;
    private final long initializedAt=System.nanoTime();
    private final AtomicLong corrections=new AtomicLong();
    private final AtomicBoolean serverReadPending=new AtomicBoolean();
    private final AtomicReference<ServerSample> serverSample=new AtomicReference<>();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicBoolean serverInstalled=new AtomicBoolean();
    private final AtomicBoolean serverPrepared=new AtomicBoolean();
    private final AtomicReference<Object> serverWorldIdentity=new AtomicReference<>();
    private record ServerSample(Object world,long sequence,long receivedAt,GroundMovementSequence.Motion motion,boolean originalAir) {}
    private Object labWorld;
    private Object ownedServer;
    private String saveName;
    private GroundMovementSequence sequence;
    private long worldStartedAt,teleportAt,lastTickAt,inputLeaseUntil,serverSequence;
    private int ticks;
    private boolean started,installRequested,teleportRequested,passLogged,stopping,waitingForFinalTrace;
    private GroundMovementSequence.Motion clientMotion;
    private GroundMovementSequence.Held held=GroundMovementSequence.Held.NONE;
    private Boolean previousPauseOnLostFocus;
    private GroundMovementLab(GroundPatch patch){this.patch=patch;}

    public static void initialize() {
        if(!Boolean.getBoolean("minecome.groundMovementLab"))return;
        if(active!=null)throw new IllegalStateException("Ground movement lab already initialized");
        String file=System.getProperty("minecome.groundPatchFile");
        try {
            if(file==null || file.isBlank())throw new IllegalArgumentException("minecome.groundPatchFile is required");
            var lab=new GroundMovementLab(GroundPatch.read(Path.of(file)));active=lab;
            LOG.info("GROUND_MOVEMENT_PATCH run={} sourceKind={} sha256={} points=25 slabs=16 thickness=0.5 approximateHeightfield=true fullCollisionExportVerified=false",
                    lab.patch.run(),lab.patch.sourceKind(),lab.patch.sha256());
            ClientTickEvents.START_CLIENT_TICK.register(lab::beforeTick);
            ClientTickEvents.END_CLIENT_TICK.register(lab::afterTick);
            ClientLifecycleEvents.CLIENT_STOPPING.register(client->{lab.finishTrace("stopped","STOPPED","Minecraft stopping");lab.release(client);if(lab.previousPauseOnLostFocus!=null)client.options.pauseOnLostFocus=lab.previousPauseOnLostFocus;GroundCollision.clear();active=null;});
        }catch(Exception e) {
            LOG.error("GROUND_MOVEMENT_LAB_FAIL: patch initialization failed: {}",e.getMessage());
            ClientTickEvents.END_CLIENT_TICK.register(client->client.scheduleStop());
        }
    }
    /** Called at RETURN of the real vanilla correction handler; counts packets, never changes them. */
    public static void positionCorrection(){var lab=active;if(lab!=null)lab.corrections.incrementAndGet();}
    private void beforeTick(MinecraftClient client) {
        if(stopping){release(client);return;}
        long now=System.nanoTime();
        if(now-initializedAt>=120_000_000_000L){fail(client,"Global startup/runtime deadline120s reached");return;}
        if(!started && client.currentScreen!=null && client.getOverlay()==null)create(client);
        if(!started || client.world==null || client.player==null || !client.isIntegratedServerRunning()) {
            release(client);
            if(labWorld!=null)fail(client,"Owned singleplayer connection/world ended");
            return;
        }
        if(!owned(client)){fail(client,"World identity changed; refusing other saves/dimensions");return;}
        if(labWorld==null){labWorld=client.world;ownedServer=client.getServer();worldStartedAt=now;}
        if(now-worldStartedAt>=40_000_000_000L) {
            if(!passLogged)fail(client,"World runtime40s ended without complete movement proof");
            else {LOG.info("Ground movement lab bounded40s runtime complete; scheduling normal save/shutdown");stopping=true;release(client);client.scheduleStop();}
            return;
        }
        String serverError=serverFailure.get();
        if(serverError!=null){fail(client,serverError);return;}
        if(!installRequested){install(client,now);return;}
        if(!serverInstalled.get()) {
            release(client);
            if(serverPrepared.get() && !teleportRequested) {
                if(!allProxyCellsAir(client.world)){fail(client,"Vanilla blocks overlap client proxy cells");return;}
                GroundCollision.install(client.world,patch,false);
                teleportRequested=true;teleportAt=now;requestTeleport(client);
            } else if(now-teleportAt>6_000_000_000L)fail(client,"Server collision installation/teleport did not complete");
            return;
        }
        requestServerSample(client);
        var sample=serverSample.get();
        if(sample==null || sample.world()!=serverWorldIdentity.get() || now-sample.receivedAt()>500_000_000L) {
            release(client);
            if(now-teleportAt>8_000_000_000L)fail(client,"No fresh authoritative server observation");
            return;
        }
        if(sequence==null) {
            // Wait for the normal server teleport packet to reach the client; never copy positions each tick.
            double spawnY=patch.heightAt(SPAWN_X,SPAWN_Z)+0.05;
            if(client.player.getPos().squaredDistanceTo(SPAWN_X,spawnY,SPAWN_Z)>1 || client.player.getY()<52 ||
                    client.currentScreen!=null || client.getOverlay()!=null) {
                release(client);if(now-teleportAt>20_000_000_000L)fail(client,"Initial vanilla teleport/loading handoff did not reach client");return;
            }
            if(!allProxyCellsAir(client.world)){fail(client,"Vanilla blocks overlap sampled proxy cells");return;}
            clientMotion=motion(client.player,hasGround(client.world,client.player));
            sequence=new GroundMovementSequence(patch,now);lastTickAt=now;
            if(traceFile!=null) {
                try {openTrace(client,now);}
                catch(Exception e){fail(client,"Movement trace initialization failed: "+e.getMessage());return;}
            }
            LOG.info("GROUND_MOVEMENT_LAB_READY save={} run={} sourceKind={} spawn={} serverInstalled=true clientInstalled=true originalProxyCellsAir=true serverFlightValidationAllowed=true playerFlightAbility=false approximateHeightfield=true",
                    saveName,patch.run(),patch.sourceKind(),client.player.getPos());
        }
        if(client.currentScreen!=null || client.isPaused()){fail(client,"Menu/pause opened during bounded movement probe; preserving normal UI");return;}
        if(lastTickAt!=0 && now-lastTickAt>250_000_000L && (held.forward() || held.jump())) {
            fail(client,"Held-input lease expired after client tick stall");return;
        }
        lastTickAt=now;
        held=sequence.update(now,clientMotion,sample.motion(),corrections.get());
        if(sequence.phase()==GroundMovementSequence.Phase.FAILED){fail(client,sequence.failure());return;}
        inputLeaseUntil=now+150_000_000L;
        apply(client,held);
        if(sequence.phase()==GroundMovementSequence.Phase.PASSED && !passLogged) {
            release(client);
            if(trace!=null) {
                boolean written;
                try {written=writeTrace(now,sample,true);}
                catch(Exception e){fail(client,"Movement trace final sample failed: "+e.getMessage());return;}
                if(!written) {
                    if(!waitingForFinalTrace)LOG.info("Ground movement proof complete; keys released while awaiting fresh advancing final authoritative trace sample within existing deadlines");
                    waitingForFinalTrace=true;return;
                }
                if(!finishTrace("passed","PASSED","Actual client and server walk/air/landing proof complete")) {
                    fail(client,"Movement trace termination failed");return;
                }
            }
            passLogged=true;release(client);
            LOG.info("GROUND_MOVEMENT_LAB_PASS run={} save={} sourceKind={} clientWalk={} serverWalk={} clientAir={} serverAir={} clientLand={} serverLand={} clientProxyQueries={} serverProxyQueries={} correctionPackets={} client={} server={} approximateHeightfield=true fullCollisionExportVerified=false kcdMovementApplied=false",
                    patch.run(),saveName,patch.sourceKind(),sequence.clientWalk(),sequence.serverWalk(),sequence.clientAir(),sequence.serverAir(),
                    sequence.clientLand(),sequence.serverLand(),GroundCollision.queries(false),GroundCollision.queries(true),corrections.get(),clientMotion,sample.motion());
        }
    }
    private void afterTick(MinecraftClient client) {
        if(stopping || labWorld==null || !owned(client))return;
        long now=System.nanoTime();
        if((held.forward() || held.jump()) && now>inputLeaseUntil){fail(client,"Held-input lease expired during vanilla tick");return;}
        clientMotion=motion(client.player,hasGround(client.world,client.player));
        var sample=serverSample.get();
        if(trace!=null && !trace.closed() && sequence!=null && sample!=null && sample.world()==serverWorldIdentity.get() &&
                (firstTraceSamplePending || sequence.phase()==GroundMovementSequence.Phase.WALKING ||
                        sequence.phase()==GroundMovementSequence.Phase.RESTING || sequence.phase()==GroundMovementSequence.Phase.JUMPING ||
                        sequence.phase()==GroundMovementSequence.Phase.LANDING)) {
            try {writeTrace(now,sample,firstTraceSamplePending);}
            catch(Exception e){fail(client,"Movement trace write failed: "+e.getMessage());return;}
        }
        if(sequence!=null && (++ticks%10==0 || sequence.phase()==GroundMovementSequence.Phase.WALKING ||
                sequence.phase()==GroundMovementSequence.Phase.JUMPING || sequence.phase()==GroundMovementSequence.Phase.LANDING))
            LOG.info("GROUND_MOVEMENT_SAMPLE phase={} client={} server={} serverSequence={} serverAgeMillis={} correctionPackets={} clientProxyQueries={} serverProxyQueries={}",
                    sequence.phase(),clientMotion,sample==null?null:sample.motion(),sample==null?0:sample.sequence(),
                    sample==null?-1:(now-sample.receivedAt())/1_000_000,corrections.get(),GroundCollision.queries(false),GroundCollision.queries(true));
    }
    private void create(MinecraftClient client) {
        started=true;
        if(client.world!=null || client.isIntegratedServerRunning()){fail(client,"Refusing an already open world");return;}
        previousPauseOnLostFocus=client.options.pauseOnLostFocus;client.options.pauseOnLostFocus=false;
        saveName="MineCome-Ground-"+UUID.randomUUID();
        var save=client.runDirectory.toPath().resolve("saves").resolve(saveName).normalize();
        if(Files.exists(save)){fail(client,"Refusing existing lab save: "+save);return;}
        GameRules rules=new GameRules();rules.get(GameRules.DO_MOB_SPAWNING).set(false,null);
        rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0,null);rules.get(GameRules.SPAWN_RADIUS).set(0,null);
        LevelInfo info=new LevelInfo(saveName,GameMode.ADVENTURE,false,Difficulty.PEACEFUL,true,rules,DataConfiguration.SAFE_MODE);
        LOG.info("Ground movement lab creating NEW isolated empty-flat Adventure world: {}",save);
        client.createIntegratedServerLoader().createAndStart(saveName,info,new GeneratorOptions(42,false,false),registries->{
            var biome=registries.get(RegistryKeys.BIOME).getEntry(BiomeKeys.THE_VOID).orElseThrow();
            var config=new FlatChunkGeneratorConfig(Optional.of(RegistryEntryList.of()),biome,List.of());
            config.updateLayerBlocks();
            return registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder()
                    .with(registries,new FlatChunkGenerator(config));
        },client.currentScreen);
    }
    private boolean owned(MinecraftClient client) {
        return !stopping && saveName!=null && client.world!=null && client.player!=null && client.getServer()!=null &&
                client.isIntegratedServerRunning() && (ownedServer==null || ownedServer==client.getServer()) &&
                (labWorld==null || labWorld==client.world) && client.world.getRegistryKey()==net.minecraft.world.World.OVERWORLD;
    }
    private void install(MinecraftClient client,long now) {
        installRequested=true;teleportAt=now;release(client);
        var server=client.getServer();var playerId=client.player.getUuid();
        server.execute(()->{
            try {
                var world=server.getOverworld();var player=server.getPlayerManager().getPlayer(playerId);
                if(!saveName.equals(server.getSaveProperties().getLevelName()) || player==null || player.getWorld()!=world)
                    throw new IllegalStateException("Owned server/player identity unavailable during installation");
                if(!(world.getChunkManager().getChunkGenerator() instanceof FlatChunkGenerator generator) ||
                        !generator.getConfig().getLayerBlocks().isEmpty())throw new IllegalStateException("Lab generator is not empty flat");
                if(!allProxyCellsAir(world))throw new IllegalStateException("Server has vanilla blocks in proxy cells");
                GroundCollision.install(world,patch,true);
                // Vanilla's anti-floating test reads literal air blocks, which deliberately remain air here.
                // Only this new lab server allows that validation; Adventure abilities stay non-flying.
                server.setFlightEnabled(true);
                if(player.getAbilities().allowFlying || player.getAbilities().flying)throw new IllegalStateException("Lab player unexpectedly has flight ability");
                serverWorldIdentity.set(world);serverPrepared.set(true);
                LOG.info("Ground proxy prepared on actual server: run={} originalProxyCellsAir=true",patch.run());
            }catch(Exception e){serverFailure.set("Server ground setup failed: "+e.getMessage());}
        });
    }
    private void requestTeleport(MinecraftClient client) {
        var server=client.getServer();var playerId=client.player.getUuid();
        server.execute(()->{
            try {
                var world=server.getOverworld();var player=server.getPlayerManager().getPlayer(playerId);
                if(server!=ownedServer || world!=serverWorldIdentity.get() || player==null || player.getWorld()!=world ||
                        !saveName.equals(server.getSaveProperties().getLevelName()) || !GroundCollision.installed(world,true))
                    throw new IllegalStateException("Owned server identity changed before teleport");
                player.teleport(world,SPAWN_X,patch.heightAt(SPAWN_X,SPAWN_Z)+0.05,SPAWN_Z,90,0);
                player.setVelocity(Vec3d.ZERO);player.fallDistance=0;
                serverInstalled.set(true);
                LOG.info("Ground proxy installed on both game threads before vanilla teleport: run={} position={}",patch.run(),player.getPos());
            }catch(Exception e){serverFailure.set("Server teleport failed: "+e.getMessage());}
        });
    }
    private void requestServerSample(MinecraftClient client) {
        if(!serverReadPending.compareAndSet(false,true))return;
        var server=client.getServer();var playerId=client.player.getUuid();long number=++serverSequence;
        server.execute(()->{
            try {
                var world=server.getOverworld();var player=server.getPlayerManager().getPlayer(playerId);
                if(server!=ownedServer || world!=serverWorldIdentity.get() || player==null || player.getWorld()!=world ||
                        !saveName.equals(server.getSaveProperties().getLevelName()) || !GroundCollision.installed(world,true))
                    throw new IllegalStateException("Server player/collision world changed");
                boolean originalAir=allProxyCellsAir(world);
                if(!originalAir)throw new IllegalStateException("Vanilla blocks appeared in server proxy cells");
                var motion=motion(player,hasGround(world,player));
                serverSample.set(new ServerSample(world,number,System.nanoTime(),motion,originalAir));
            }catch(Exception e){serverFailure.set("Server observation failed: "+e.getMessage());}
            finally {serverReadPending.set(false);}
        });
    }
    private boolean allProxyCellsAir(net.minecraft.world.BlockView world) {
        for(var cell:patch.cells())if(!world.getBlockState(new BlockPos(cell.x(),cell.y(),cell.z())).isAir())return false;
        return true;
    }
    private static boolean hasGround(net.minecraft.world.CollisionView world,net.minecraft.entity.Entity player) {
        var box=player.getBoundingBox();
        var below=new net.minecraft.util.math.Box(box.minX+0.001,box.minY-0.06,box.minZ+0.001,box.maxX-0.001,box.minY+0.001,box.maxZ-0.001);
        for(var shape:world.getBlockCollisions(player,below))if(!shape.isEmpty())return true;
        return false;
    }
    private static GroundMovementSequence.Motion motion(net.minecraft.entity.Entity player,boolean support) {
        var p=player.getPos();var v=player.getVelocity();
        return new GroundMovementSequence.Motion(p.x,p.y,p.z,v.x,v.y,v.z,player.isOnGround(),support);
    }
    private void apply(MinecraftClient client,GroundMovementSequence.Held input) {
        client.options.forwardKey.setPressed(input.forward());client.options.jumpKey.setPressed(input.jump());
        client.options.backKey.setPressed(false);client.options.leftKey.setPressed(false);client.options.rightKey.setPressed(false);
        client.options.sneakKey.setPressed(false);client.options.sprintKey.setPressed(false);
    }
    private void release(MinecraftClient client){held=GroundMovementSequence.Held.NONE;inputLeaseUntil=0;apply(client,held);}
    private void openTrace(MinecraftClient client,long now) throws java.io.IOException {
        Path run=client.runDirectory.toPath().toAbsolutePath().normalize();
        Path minecraft=run.getParent(),project=minecraft==null?null:minecraft.getParent();
        if(project==null || !Files.isRegularFile(project.resolve("AGENTS.md")) ||
                !Files.isRegularFile(project.resolve("minecraft/build.gradle")))
            throw new java.io.IOException("Trace output requires the owned MineCome workspace run directory");
        String world=saveName.substring("MineCome-Ground-".length());
        var context=new MovementTraceSink.Context(patch.run(),patch.sha256(),patch.sourceKind(),saveName,world,
                patch.centerX(),patch.centerY(),patch.centerZ());
        trace=MovementTraceSink.open(Path.of(traceFile),project.resolve("runtime/evidence"),context,now,System.currentTimeMillis());
        firstTraceSamplePending=true;
        LOG.info("GROUND_MOVEMENT_TRACE_BEGIN file={} run={} patchSha256={} world={} recordsMax=200 bytesMax=65536 sourceKind={}; fileIPC prototype only",
                trace.path(),patch.run(),patch.sha256(),world,patch.sourceKind());
    }
    private boolean writeTrace(long now,ServerSample sample,boolean force) throws java.io.IOException {
        if(trace==null || trace.closed() || sample.world()!=serverWorldIdentity.get())return false;
        var c=clientMotion;var s=sample.motion();
        // Timestamp after capturing the immutable server sample, avoiding a callback race that
        // would otherwise make a just-received observation appear newer than this tick's start.
        boolean written=trace.sample(System.nanoTime(),System.currentTimeMillis(),sequence.phase().name(),
                new MovementTraceSink.Motion(c.x(),c.y(),c.z(),c.vx(),c.vy(),c.vz(),c.onGround(),c.proxySupport()),
                new MovementTraceSink.Motion(s.x(),s.y(),s.z(),s.vx(),s.vy(),s.vz(),s.onGround(),s.proxySupport()),
                sample.sequence(),sample.receivedAt(),force);
        if(written)firstTraceSamplePending=false;
        return written;
    }
    private boolean finishTrace(String result,String phase,String reason) {
        if(trace==null || trace.closed())return true;
        try {
            trace.finish(System.currentTimeMillis(),result,phase,reason);
            LOG.info("GROUND_MOVEMENT_TRACE_END result={} records={} bytes={} file={}",result,trace.records(),trace.byteCount(),trace.path());
            return true;
        }catch(Exception e){LOG.error("GROUND_MOVEMENT_TRACE_FAIL: {}",e.getMessage());return false;}
    }
    private void fail(MinecraftClient client,String reason) {
        if(stopping)return;
        if(sequence!=null)sequence.fail(reason);
        LOG.error("GROUND_MOVEMENT_LAB_FAIL run={} sourceKind={} reason={} phase={} client={} server={} correctionPackets={} approximateHeightfield=true fullCollisionExportVerified=false",
                patch.run(),patch.sourceKind(),reason,sequence==null?"startup":sequence.phase(),clientMotion,serverSample.get(),corrections.get());
        finishTrace("failed","FAILED",reason);
        stopping=true;release(client);client.scheduleStop();
    }
}
