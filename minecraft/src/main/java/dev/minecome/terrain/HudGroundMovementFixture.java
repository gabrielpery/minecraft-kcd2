package dev.minecome.terrain;

import com.google.gson.JsonObject;
import dev.minecome.hud.HudGroundMovementMode;
import dev.minecome.hud.HudPhysicalMovementMode;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Box;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.BlockView;
import net.minecraft.world.CollisionView;
import net.minecraft.world.World;
import net.minecraft.world.gen.chunk.FlatChunkGenerator;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.EnumMap;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

/** Scripted vanilla movement in the owned HUD world. Optional bounded trace; no KCD calls. */
public final class HudGroundMovementFixture {
    private static final double SPAWN_X=.5,SPAWN_Z=.5;
    private record ServerSample(Object world,Object player,long sequence,long at,GroundMovementSequence.Motion motion) {}
    private final GroundPatch patch;
    private final String save,hudRun;
    private final HudGroundMovementMode.Mode mode;
    private final Path traceFile;
    private MovementTraceSink trace;
    private String traceResult="not_started";
    private final AtomicLong corrections=new AtomicLong();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicReference<ServerSample> sample=new AtomicReference<>();
    private final AtomicBoolean serverPrepared=new AtomicBoolean(),serverInstalled=new AtomicBoolean(),serverReleased=new AtomicBoolean();
    private final EnumMap<GroundMovementSequence.Phase,Long> captures=new EnumMap<>(GroundMovementSequence.Phase.class);
    private Object clientWorld,clientPlayer,serverWorld,serverPlayer;
    private MinecraftServer server;
    private UUID playerId;
    private GroundMovementSequence sequence;
    private GroundMovementSequence.Motion clientMotion;
    private GroundMovementSequence.Held held=GroundMovementSequence.Held.NONE;
    private long setupAt,lastTickAt,inputLeaseUntil,settledCorrections,clientQueries,serverQueries,serverSequence;
    private boolean firstTraceSamplePending;
    private boolean setupRequested,clientInstalled,teleportRequested,passed,clientReleased,controlsOwned;
    private volatile boolean closing;

    public HudGroundMovementFixture(Path file,String run,String save) throws IOException {
        this(file,run,save,HudGroundMovementMode.Mode.FIXTURE,null);
    }
    public HudGroundMovementFixture(Path file,String run,String save,HudGroundMovementMode.Mode mode,Path traceFile) throws IOException {
        boolean wide=HudPhysicalMovementMode.wide(System.getProperties());
        if(wide && mode!=HudGroundMovementMode.Mode.COUPLED)throw new IllegalArgumentException("Wide HUD ground requires explicit coupled movement");
        patch=GroundPatch.read(file,wide);this.save=save;this.hudRun=run;this.mode=mode;this.traceFile=traceFile;
        HudGroundMovementMode.requirePatch(mode,run,patch.run(),patch.sourceKind(),save);
        if((mode==HudGroundMovementMode.Mode.COUPLED)!=(traceFile!=null) || (traceFile!=null && !traceFile.isAbsolute()))
            throw new IllegalArgumentException("Only coupled HUD movement requires an absolute fresh trace path");
    }
    public void positionCorrection(){corrections.incrementAndGet();}
    public boolean passed(){return passed;}
    public String phase(){return sequence==null?"INSTALLING":sequence.phase().name();}
    public void captured(String phase) {
        if(phase.equals("INSTALLING"))return;
        var value=GroundMovementSequence.Phase.valueOf(phase);
        captures.merge(value,1L,Long::sum);
    }
    public void beforeTick(MinecraftClient client,long now) {
        if(closing)return;
        checkFailure();
        if(clientWorld==null)return;
        requireOwned(client);
        if(lastTickAt!=0 && now-lastTickAt>250_000_000L && (held.forward()||held.jump()))
            throw new IllegalStateException("HUD movement held-input lease expired after client stall");
        if(inputLeaseUntil!=0 && now>inputLeaseUntil && (held.forward()||held.jump()))
            throw new IllegalStateException("HUD movement input lease expired before vanilla tick");
        if(sequence==null || passed){release(client);return;}
        if(client.currentScreen!=null || client.getOverlay()!=null || client.isPaused())
            throw new IllegalStateException("HUD movement interrupted by menu/overlay/pause");
        apply(client,held);
    }
    public void afterTick(MinecraftClient client,long now) throws IOException {
        checkFailure();
        if(closing)return;
        if(clientWorld==null){
            if(client.world==null || client.player==null || client.getServer()==null || !client.isIntegratedServerRunning())
                throw new IllegalStateException("HUD movement requires the owned integrated world");
            clientWorld=client.world;clientPlayer=client.player;server=client.getServer();playerId=client.player.getUuid();
        }
        requireOwned(client);
        if(!setupRequested){setupRequested=true;setupAt=now;release(client);prepareServer();return;}
        if(!serverInstalled.get()){
            release(client);
            if(serverPrepared.get() && !teleportRequested){
                if(!allProxyCellsAir(client.world))throw new IllegalStateException("HUD ground client proxy cells are not air");
                if(!GroundCollision.available(false))throw new IllegalStateException("Existing client collision installation preserved");
                GroundCollision.install(client.world,patch,false);clientInstalled=true;teleportRequested=true;
                teleportServer();
            }
            if(now-setupAt>6_000_000_000L)throw new IllegalStateException("HUD ground installation/teleport deadline");
            return;
        }
        if((held.forward()||held.jump()) && now>inputLeaseUntil)
            throw new IllegalStateException("HUD movement held-input lease expired during vanilla tick");
        var observed=sample.get();long observedNow=System.nanoTime();
        if(observed==null || observed.world()!=serverWorld || observed.player()!=serverPlayer ||
                observedNow<observed.at() || observedNow-observed.at()>250_000_000L){
            release(client);
            if(sequence!=null || now-setupAt>8_000_000_000L)
                throw new IllegalStateException("HUD movement lacks a fresh matching server observation");
            return;
        }
        if(!GroundCollision.installed(client.world,false) || !allProxyCellsAir(client.world) || client.player.getAbilities().flying)
            throw new IllegalStateException("HUD client ground ownership/air/non-flying contract changed");
        clientMotion=motion(client.player,hasGround(client.world,client.player));
        if(sequence==null){
            if(client.currentScreen!=null || client.getOverlay()!=null ||
                    client.player.getPos().squaredDistanceTo(SPAWN_X,patch.heightAt(SPAWN_X,SPAWN_Z)+.05,SPAWN_Z)>1){
                release(client);
                if(now-setupAt>8_000_000_000L)throw new IllegalStateException("HUD movement initial teleport handoff deadline");
                return;
            }
            sequence=new GroundMovementSequence(patch,now);
            if(mode==HudGroundMovementMode.Mode.COUPLED)openTrace(client,now);
        }
        if(passed){release(client);return;}
        if(client.currentScreen!=null || client.getOverlay()!=null || client.isPaused())
            throw new IllegalStateException("HUD movement interrupted by menu/overlay/pause");
        var previous=sequence.phase();
        held=sequence.update(now,clientMotion,observed.motion(),corrections.get());
        if(previous==GroundMovementSequence.Phase.SETTLING && sequence.phase()!=previous)settledCorrections=corrections.get();
        if(sequence.phase()==GroundMovementSequence.Phase.FAILED)throw new IllegalStateException(sequence.failure());
        lastTickAt=now;inputLeaseUntil=now+150_000_000L;
        if(sequence.phase()==GroundMovementSequence.Phase.PASSED){
            release(client);
            if(captures.getOrDefault(GroundMovementSequence.Phase.WALKING,0L)==0 ||
                    captures.getOrDefault(GroundMovementSequence.Phase.JUMPING,0L)+captures.getOrDefault(GroundMovementSequence.Phase.LANDING,0L)==0)
                throw new IllegalStateException("HUD was not captured during both walking and jump/landing");
            if(trace!=null){
                // The final phase can wait for the next advancing server sample,
                // but never reuse a previous sample or extend the HUD deadline.
                if(corrections.get()!=settledCorrections || !grounded(clientMotion) || !grounded(observed.motion()))
                    throw new IllegalStateException("HUD movement final trace lost its grounded correction-free proof");
                if(!writeTrace(observed,true))return;
                trace.finish(System.currentTimeMillis(),"passed","PASSED","Actual HUD-world client and server walk/air/landing proof complete");
                traceResult="passed";
            }
            // Ending here keeps the later20s UI sequence outside the KCD follower.
            passed=true;
        }else {
            if(trace!=null && (firstTraceSamplePending || sequence.phase()!=GroundMovementSequence.Phase.SETTLING))
                writeTrace(observed,firstTraceSamplePending);
            apply(client,held);
        }
    }
    private void prepareServer(){
        server.execute(()->{
            try{
                var world=server.getOverworld();var entity=server.getPlayerManager().getPlayer(playerId);
                if(!save.equals(server.getSaveProperties().getLevelName()) || entity==null || entity.getWorld()!=world ||
                        !(world.getChunkManager().getChunkGenerator() instanceof FlatChunkGenerator generator) ||
                        !generator.getConfig().getLayerBlocks().isEmpty() || !allProxyCellsAir(world))
                    throw new IllegalStateException("HUD server is not the exact empty-flat fixture");
                if(!GroundCollision.available(true))throw new IllegalStateException("Existing server collision installation preserved");
                serverWorld=world;serverPlayer=entity;
                GroundCollision.install(world,patch,true);
                // The collision proxy leaves literal air; allow vanilla's air-block validation only in this new server.
                // Creative is retained for the real HUD inventory packets, but actual flying is never enabled.
                if(entity.getAbilities().flying)throw new IllegalStateException("HUD fixture server player is flying");
                server.setFlightEnabled(true);serverPrepared.set(true);
            }catch(Exception e){serverFailure.set("HUD ground setup: "+e.getMessage());}
        });
    }
    private void teleportServer(){
        server.execute(()->{
            try{
                var entity=server.getPlayerManager().getPlayer(playerId);
                requireServer(server,entity);
                entity.teleport(server.getOverworld(),SPAWN_X,patch.heightAt(SPAWN_X,SPAWN_Z)+.05,SPAWN_Z,90,0);
                entity.setVelocity(Vec3d.ZERO);entity.fallDistance=0;serverInstalled.set(true);
            }catch(Exception e){serverFailure.set("HUD ground teleport: "+e.getMessage());}
        });
    }
    /** Called only from the existing HUD END_SERVER_TICK callback. */
    public void observe(MinecraftServer source){
        if(!serverInstalled.get() || closing)return;
        try{
            var entity=source.getPlayerManager().getPlayer(playerId);requireServer(source,entity);
            if(!allProxyCellsAir(source.getOverworld()) || entity.getAbilities().flying)
                throw new IllegalStateException("HUD server ground air/non-flying contract changed");
            sample.set(new ServerSample(entity.getWorld(),entity,++serverSequence,System.nanoTime(),motion(entity,hasGround(source.getOverworld(),entity))));
        }catch(Exception e){serverFailure.set("HUD ground observation: "+e.getMessage());}
    }
    private void requireServer(MinecraftServer source,net.minecraft.server.network.ServerPlayerEntity entity){
        if(source!=server || source.getOverworld()!=serverWorld || entity==null || entity!=serverPlayer ||
                entity.getWorld()!=serverWorld || !save.equals(source.getSaveProperties().getLevelName()) ||
                !GroundCollision.installed(source.getOverworld(),true))
            throw new IllegalStateException("HUD movement server/world/player identity changed");
    }
    private void requireOwned(MinecraftClient client){
        if(client.world!=clientWorld || client.player!=clientPlayer || client.getServer()!=server ||
                !client.isIntegratedServerRunning() || client.world.getRegistryKey()!=World.OVERWORLD)
            throw new IllegalStateException("HUD movement client/world/player identity changed");
    }
    private void checkFailure(){String error=serverFailure.get();if(error!=null)throw new IllegalStateException(error);}
    /** No waits on either game thread. The unchanged HUD deadline bounds acknowledgement. */
    public boolean finish(MinecraftClient client){
        close(client);checkFailure();return clientReleased && serverReleased.get();
    }
    public void abort(MinecraftClient client,String reason){
        terminateTrace("failed","FAILED",reason);close(client);
    }
    public void close(MinecraftClient client){
        if(closing)return;closing=true;
        // KeyBinding state belongs to the client, not its current player. A
        // disconnect/replacement must release our synthetic holds as well.
        if(controlsOwned)release(client);
        terminateTrace("stopped","STOPPED","HUD movement closed before explicit trace completion");
        if(clientInstalled){
            clientQueries=GroundCollision.queries(false);
            clientReleased=GroundCollision.clear((BlockView)clientWorld,patch.run(),false);
        }else clientReleased=true;
        if(server!=null){
            server.execute(()->{
                if(serverWorld!=null){
                    serverQueries=GroundCollision.queries(true);
                    if(!GroundCollision.clear((BlockView)serverWorld,patch.run(),true)){
                        serverFailure.set("HUD server collision release identity mismatch");return;
                    }
                }
                serverReleased.set(true);
            });
        }else serverReleased.set(true);
    }
    public JsonObject evidence(MinecraftClient client){
        var e=new JsonObject();e.addProperty("schema",1);e.addProperty("kind",
                mode==HudGroundMovementMode.Mode.COUPLED?"minecome_hud_ground_movement_coupled_v1":"minecome_hud_ground_movement_fixture_v1");
        e.addProperty("save",save);e.addProperty("patch_run",patch.run());e.addProperty("patch_sha256",patch.sha256());
        if(mode==HudGroundMovementMode.Mode.COUPLED){
            e.addProperty("hud_run",hudRun);e.addProperty("trace_file",trace==null?traceFile.toString():trace.path().toString());
            e.addProperty("trace_records",trace==null?0:trace.records());e.addProperty("trace_closed",trace!=null&&trace.closed());
            e.addProperty("trace_result",traceResult);
        }
        e.addProperty("ground_source_kind",patch.sourceKind());e.addProperty("synthetic_input",true);e.addProperty("kcd_calls",false);
        e.addProperty("kcd_movement_applied",false);e.addProperty("physical_input_verified",false);e.addProperty("phase",phase());
        e.addProperty("client_walk",sequence==null?0:sequence.clientWalk());e.addProperty("server_walk",sequence==null?0:sequence.serverWalk());
        if(patch.wide()){
            e.addProperty("walking_area","wide");
            e.addProperty("wide_boundary_crossed",sequence!=null&&sequence.clientWalk()>2&&sequence.serverWalk()>2);
            e.addProperty("client_max_horizontal_excursion",sequence==null?0:sequence.clientWalk());
            e.addProperty("server_max_horizontal_excursion",sequence==null?0:sequence.serverWalk());
        }
        e.addProperty("client_air",sequence!=null&&sequence.clientAir());e.addProperty("server_air",sequence!=null&&sequence.serverAir());
        e.addProperty("client_land",sequence!=null&&sequence.clientLand());e.addProperty("server_land",sequence!=null&&sequence.serverLand());
        e.addProperty("client_proxy_queries",clientQueries);e.addProperty("server_proxy_queries",serverQueries);
        e.addProperty("post_settle_corrections",corrections.get()-settledCorrections);
        e.addProperty("client_proxy_released",clientReleased);e.addProperty("server_proxy_released",serverReleased.get());
        e.addProperty("controls_released",!client.options.forwardKey.isPressed()&&!client.options.jumpKey.isPressed()&&
                !client.options.backKey.isPressed()&&!client.options.leftKey.isPressed()&&!client.options.rightKey.isPressed()&&
                !client.options.sneakKey.isPressed()&&!client.options.sprintKey.isPressed());
        e.addProperty("approximate_heightfield",true);e.addProperty("full_collision_export_verified",false);
        var frames=new JsonObject();
        for(var phase:GroundMovementSequence.Phase.values())frames.addProperty(phase.name(),captures.getOrDefault(phase,0L));
        e.add("frame_captures",frames);
        if(clientMotion!=null)e.add("client_motion",motionJson(clientMotion));
        var observed=sample.get();if(observed!=null)e.add("server_motion",motionJson(observed.motion()));
        return e;
    }
    private void openTrace(MinecraftClient client,long now) throws IOException {
        Path run=client.runDirectory.toPath().toAbsolutePath().normalize();
        Path minecraft=run.getParent(),project=minecraft==null?null:minecraft.getParent();
        if(project==null || !Files.isRegularFile(project.resolve("AGENTS.md")) ||
                !Files.isRegularFile(project.resolve("minecraft/build.gradle")))
            throw new IOException("HUD movement trace requires the owned workspace run directory");
        String world=save.substring("MineCome-HudStream-".length());
        var context=new MovementTraceSink.Context(patch.run(),patch.sha256(),patch.sourceKind(),save,world,
                patch.centerX(),patch.centerY(),patch.centerZ(),MovementTraceSink.Profile.HUD_COUPLED,0,64,0,patch.wide());
        trace=MovementTraceSink.open(traceFile,project.resolve("runtime/evidence"),context,now,System.currentTimeMillis());
        traceResult="pending";firstTraceSamplePending=true;
    }
    private boolean writeTrace(ServerSample observed,boolean force) throws IOException {
        var c=clientMotion;var s=observed.motion();
        // Timestamp only after selecting the immutable authoritative observation.
        boolean written=trace.sample(System.nanoTime(),System.currentTimeMillis(),sequence.phase().name(),
                new MovementTraceSink.Motion(c.x(),c.y(),c.z(),c.vx(),c.vy(),c.vz(),c.onGround(),c.proxySupport(),patch.wide()),
                new MovementTraceSink.Motion(s.x(),s.y(),s.z(),s.vx(),s.vy(),s.vz(),s.onGround(),s.proxySupport(),patch.wide()),
                observed.sequence(),observed.at(),force);
        if(written)firstTraceSamplePending=false;
        return written;
    }
    private void terminateTrace(String result,String phase,String reason){
        if(trace==null || trace.closed())return;
        try{trace.finish(System.currentTimeMillis(),result,phase,reason);traceResult=result;}
        catch(IOException|RuntimeException e){traceResult="failed";serverFailure.compareAndSet(null,"HUD movement trace termination: "+e.getMessage());}
    }
    private boolean grounded(GroundMovementSequence.Motion motion){
        return motion.onGround() && motion.proxySupport() &&
                Math.abs(motion.y()-patch.groundForFeet(motion.x(),motion.z(),.3))<.15;
    }
    private static JsonObject motionJson(GroundMovementSequence.Motion m){
        var e=new JsonObject();e.addProperty("x",m.x());e.addProperty("y",m.y());e.addProperty("z",m.z());
        e.addProperty("on_ground",m.onGround());e.addProperty("proxy_support",m.proxySupport());return e;
    }
    private boolean allProxyCellsAir(BlockView world){for(var c:patch.cells())if(!world.getBlockState(new BlockPos(c.x(),c.y(),c.z())).isAir())return false;return true;}
    private static boolean hasGround(CollisionView world,Entity player){
        var b=player.getBoundingBox();var below=new Box(b.minX+.001,b.minY-.06,b.minZ+.001,b.maxX-.001,b.minY+.001,b.maxZ-.001);
        for(var shape:world.getBlockCollisions(player,below))if(!shape.isEmpty())return true;return false;
    }
    private static GroundMovementSequence.Motion motion(Entity player,boolean support){
        var p=player.getPos();var v=player.getVelocity();return new GroundMovementSequence.Motion(p.x,p.y,p.z,v.x,v.y,v.z,player.isOnGround(),support);
    }
    private void apply(MinecraftClient client,GroundMovementSequence.Held input){
        controlsOwned=true;
        client.options.forwardKey.setPressed(input.forward());client.options.jumpKey.setPressed(input.jump());
        client.options.backKey.setPressed(false);client.options.leftKey.setPressed(false);client.options.rightKey.setPressed(false);
        client.options.sneakKey.setPressed(false);client.options.sprintKey.setPressed(false);
    }
    private void release(MinecraftClient client){held=GroundMovementSequence.Held.NONE;inputLeaseUntil=0;apply(client,held);}
}
