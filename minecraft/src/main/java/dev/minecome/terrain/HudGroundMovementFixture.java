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
    private record ServerSample(Object world,Object player,long sequence,long at,String surfaceHash,GroundMovementSequence.Motion motion) {}
    private volatile GroundSurface patch,serverSurface;
    private final GroundExpansion expansion;
    private final long extensionDelayNs;
    private final AtomicBoolean extensionServerInstalled=new AtomicBoolean();
    private boolean extensionRequested,extensionClientInstalled,extensionComplete;
    private long extensionRequestedAt,extensionWaitNs,handoffTraceSamples,transitionHudFrames,extensionCrossingHudFrames;
    private static final double EXTENSION_TRIGGER_X=4.5;
    private final String save,hudRun;
    private final HudGroundMovementMode.Mode mode;
    private final boolean walkOnly;
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
    private final GroundCorridorSync corridorSync=new GroundCorridorSync();
    private GroundMovementSequence.Motion clientMotion;
    private GroundMovementSequence.Held held=GroundMovementSequence.Held.NONE;
    private long setupAt,lastTickAt,inputLeaseUntil,settledCorrections,clientQueries,serverQueries,serverSequence;
    private boolean firstTraceSamplePending;
    private boolean setupRequested,clientInstalled,teleportRequested,passed,clientReleased,controlsOwned;
    private boolean clientAirAtCleanup,serverAirAtCleanup;
    private long crossingHudFrames,returnHudFrames;
    private volatile boolean closing;

    public HudGroundMovementFixture(Path file,String run,String save) throws IOException {
        this(file,run,save,HudGroundMovementMode.Mode.FIXTURE,null);
    }
    public HudGroundMovementFixture(Path file,String run,String save,HudGroundMovementMode.Mode mode,Path traceFile) throws IOException {
        boolean wide=HudPhysicalMovementMode.wide(System.getProperties());
        if(wide && mode!=HudGroundMovementMode.Mode.COUPLED)throw new IllegalArgumentException("Wide HUD ground requires explicit coupled movement");
        expansion=mode.extension()?GroundExpansion.read(file):null;
        patch=expansion!=null?expansion.initial():mode.corridor()?GroundCorridor.read(file):GroundPatch.read(file,wide);
        serverSurface=patch;
        extensionDelayNs=HudGroundMovementMode.extensionDelayFixture(System.getProperties())?600_000_000L:0;
        this.save=save;this.hudRun=run;this.mode=mode;this.traceFile=traceFile;
        walkOnly=expansion!=null || HudGroundMovementMode.corridorWalkOnly(System.getProperties());
        if(walkOnly&&mode!=HudGroundMovementMode.Mode.CORRIDOR_COUPLED&&expansion==null)throw new IllegalArgumentException("Walk-only fixture requires coupled corridor mode");
        HudGroundMovementMode.requirePatch(mode,run,patch.run(),patch.sourceKind(),save);
        if(mode.coupled()!=(traceFile!=null) || (traceFile!=null && !traceFile.isAbsolute()))
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
    public void captureMetadata(JsonObject meta){
        if(!patch.corridor() || clientMotion==null)return;
        var observed=sample.get();if(observed==null)return;
        meta.addProperty("ground_surface_sha256",patch.sha256());
        if(expansion!=null)meta.addProperty("ground_extension_waiting",extensionRequested&&!extensionComplete);
        meta.addProperty("ground_client_x",clientMotion.x());meta.addProperty("ground_server_x",observed.motion().x());
    }
    public void captured(JsonObject meta){
        String phase=meta.get("ground_movement_phase").getAsString();captured(phase);
        if(!patch.corridor() || !meta.has("ground_surface_sha256"))return;
        if(!patch.sha256().equals(meta.get("ground_surface_sha256").getAsString()) &&
                !(expansion!=null && expansion.initial().sha256().equals(meta.get("ground_surface_sha256").getAsString())))
            throw new IllegalStateException("Corridor capture changed surface identity");
        double cx=meta.get("ground_client_x").getAsDouble(),sx=meta.get("ground_server_x").getAsDouble();
        if(!Double.isFinite(cx)||!Double.isFinite(sx))throw new IllegalStateException("Invalid captured corridor positions");
        if(cx>4.3 && sx>4.3)crossingHudFrames++;
        if(expansion!=null){
            if(meta.has("ground_extension_waiting")&&meta.get("ground_extension_waiting").getAsBoolean())transitionHudFrames++;
            if(expansion.expanded().sha256().equals(meta.get("ground_surface_sha256").getAsString())&&cx>8.3&&sx>8.3)extensionCrossingHudFrames++;
        }
        if(phase.equals("RETURNING"))returnHudFrames++;
    }
    public void beforeTick(MinecraftClient client,long now) {
        if(closing)return;
        checkFailure();
        if(clientWorld==null)return;
        requireOwned(client);
        if(lastTickAt!=0 && now-lastTickAt>250_000_000L && (held.forward()||held.backward()||held.jump()))
            throw new IllegalStateException("HUD movement held-input lease expired after client stall");
        if(patch.corridor() && corridorSync.dropExpiredInput(now,lastTickAt,inputLeaseUntil,
                held.forward()||held.backward()||held.jump())){
            // Discard the expired synthetic hold before vanilla runs. Only the
            // normal afterTick fresh-observation path may grant a new hold.
            release(client);return;
        }
        if(inputLeaseUntil!=0 && now>inputLeaseUntil && (held.forward()||held.backward()||held.jump()))
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
        if((held.forward()||held.backward()||held.jump()) && now>inputLeaseUntil)
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
        if(patch.corridor() && !GroundCollision.matches(client.world,patch,false))
            throw new IllegalStateException("Corridor client surface identity changed");
        clientMotion=motion(client.player,hasGround(client.world,client.player));
        if(sequence==null){
            if(client.currentScreen!=null || client.getOverlay()!=null ||
                    client.player.getPos().squaredDistanceTo(SPAWN_X,patch.heightAt(SPAWN_X,SPAWN_Z)+.05,SPAWN_Z)>1){
                release(client);
                if(now-setupAt>8_000_000_000L)throw new IllegalStateException("HUD movement initial teleport handoff deadline");
                return;
            }
            sequence=new GroundMovementSequence(patch,now,walkOnly,expansion);
            if(mode.coupled())openTrace(client,now);
        }
        if(passed){release(client);return;}
        if(client.currentScreen!=null || client.getOverlay()!=null || client.isPaused())
            throw new IllegalStateException("HUD movement interrupted by menu/overlay/pause");
        if(patch.corridor()){
            try{
                if(corridorSync.pause(now,observed.sequence(),clientMotion,observed.motion())){
                    // Several client ticks can execute before the next integrated
                    // server tick. Release ordinary keys, never copy or alter a pose.
                    release(client);lastTickAt=now;
                    // Key backpressure does not suspend authoritative observation.
                    // The sink still rejects stale, repeated or premature samples.
                    if((mode==HudGroundMovementMode.Mode.CORRIDOR_COUPLED || mode==HudGroundMovementMode.Mode.EXTENSION_COUPLED) && trace!=null &&
                            (firstTraceSamplePending || sequence.phase()!=GroundMovementSequence.Phase.SETTLING))
                        writeTrace(observed,firstTraceSamplePending);
                    return;
                }
            }catch(IllegalStateException e){sequence.fail(e.getMessage());throw e;}
        }
        if(expansion!=null && extensionHandoff(client,observed,now)){
            lastTickAt=now;
            // Releasing controls does not release KCD's short observation lease.
            // Publish only fresh advancing server observations while waiting.
            if(trace!=null && writeTrace(observed,false))handoffTraceSamples++;
            return;
        }
        var previous=sequence.phase();
        held=sequence.update(now,clientMotion,observed.motion(),corrections.get());
        if(previous==GroundMovementSequence.Phase.SETTLING && sequence.phase()!=previous)settledCorrections=corrections.get();
        if(sequence.phase()==GroundMovementSequence.Phase.FAILED)throw new IllegalStateException(sequence.failure());
        lastTickAt=now;inputLeaseUntil=now+150_000_000L;
        if(sequence.phase()==GroundMovementSequence.Phase.PASSED){
            release(client);
            if(captures.getOrDefault(GroundMovementSequence.Phase.WALKING,0L)==0 ||
                    (!walkOnly&&captures.getOrDefault(GroundMovementSequence.Phase.JUMPING,0L)+captures.getOrDefault(GroundMovementSequence.Phase.LANDING,0L)==0))
                throw new IllegalStateException("HUD was not captured during the required movement phases");
            if(walkOnly&&(sequence.clientAir()||sequence.serverAir()||sequence.clientLand()||sequence.serverLand()||
                    captures.getOrDefault(GroundMovementSequence.Phase.JUMPING,0L)+captures.getOrDefault(GroundMovementSequence.Phase.LANDING,0L)!=0))
                throw new IllegalStateException("Walk-only corridor unexpectedly entered a jump/landing phase");
            if(patch.corridor() && (crossingHudFrames==0 || returnHudFrames==0))
                throw new IllegalStateException("HUD was not captured beyond the original edge and during the return");
            if(expansion!=null && (!extensionComplete || transitionHudFrames==0 || extensionCrossingHudFrames==0))
                throw new IllegalStateException("Extension was not installed and captured before crossing/return");
            if(trace!=null){
                // The final phase can wait for the next advancing server sample,
                // but never reuse a previous sample or extend the HUD deadline.
                if(corrections.get()!=settledCorrections || !grounded(clientMotion) || !grounded(observed.motion()))
                    throw new IllegalStateException("HUD movement final trace lost its grounded correction-free proof");
                if(!writeTrace(observed,true))return;
                trace.finish(System.currentTimeMillis(),"passed","PASSED",walkOnly?"Actual HUD-world client and server corridor walk/return proof complete":"Actual HUD-world client and server walk/air/landing proof complete");
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
    /** Publish each immutable map on its owning game thread; never teleport at a tile boundary. */
    private boolean extensionHandoff(MinecraftClient client,ServerSample observed,long now){
        if(extensionComplete)return false;
        if(!extensionRequested){
            if(sequence.phase()!=GroundMovementSequence.Phase.WALKING ||
                    Math.min(clientMotion.x(),observed.motion().x())<EXTENSION_TRIGGER_X)return false;
            extensionRequested=true;extensionRequestedAt=now;
            release(client);
            server.execute(()->{
                try{
                    if(closing)return;
                    var entity=server.getPlayerManager().getPlayer(playerId);requireServer(server,entity);
                    var pos=entity.getPos();
                    if(!expansion.initial().containsFeet(pos.x,pos.z,.5) || !allProxyCellsAir(server.getOverworld(),expansion.expanded()))
                        throw new IllegalStateException("Extension server footprint/air check failed");
                    if(!GroundCollision.replace(server.getOverworld(),serverSurface,expansion.expanded(),true))
                        throw new IllegalStateException("Extension server collision owner changed");
                    serverSurface=expansion.expanded();extensionServerInstalled.set(true);
                }catch(Exception e){serverFailure.set("HUD terrain extension: "+e.getMessage());}
            });
            return true;
        }
        release(client);
        if(now<extensionRequestedAt || now-extensionRequestedAt>2_000_000_000L)
            throw new IllegalStateException("Extension client/server handoff exceeded2s");
        if(now-extensionRequestedAt<extensionDelayNs || !extensionServerInstalled.get() || !observed.surfaceHash().equals(expansion.expanded().sha256()) || transitionHudFrames==0)return true;
        if(!extensionClientInstalled){
            if(!expansion.initial().containsFeet(clientMotion.x(),clientMotion.z(),.5) || !allProxyCellsAir(client.world,expansion.expanded()))
                throw new IllegalStateException("Extension client footprint/air check failed");
            if(!GroundCollision.replace(client.world,patch,expansion.expanded(),false))
                throw new IllegalStateException("Extension client collision owner changed");
            patch=expansion.expanded();extensionClientInstalled=true;
            sequence.acceptExpansion(patch);
        }
        extensionWaitNs=now-extensionRequestedAt;extensionComplete=true;return false;
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
                entity.teleport(server.getOverworld(),SPAWN_X,patch.heightAt(SPAWN_X,SPAWN_Z)+.05,SPAWN_Z,patch.corridor()?-90:90,0);
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
            sample.set(new ServerSample(entity.getWorld(),entity,++serverSequence,System.nanoTime(),serverSurface.sha256(),motion(entity,hasGround(source.getOverworld(),entity))));
        }catch(Exception e){serverFailure.set("HUD ground observation: "+e.getMessage());}
    }
    private void requireServer(MinecraftServer source,net.minecraft.server.network.ServerPlayerEntity entity){
        if(source!=server || source.getOverworld()!=serverWorld || entity==null || entity!=serverPlayer ||
                entity.getWorld()!=serverWorld || !save.equals(source.getSaveProperties().getLevelName()) ||
                !GroundCollision.installed(source.getOverworld(),true))
            throw new IllegalStateException("HUD movement server/world/player identity changed");
        if(patch.corridor() && !GroundCollision.matches(source.getOverworld(),serverSurface,true))
            throw new IllegalStateException("Corridor server surface identity changed");
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
            clientAirAtCleanup=allProxyCellsAir((BlockView)clientWorld);
            clientReleased=clearSurface((BlockView)clientWorld,false);
        }else clientReleased=true;
        if(server!=null){
            server.execute(()->{
                if(serverWorld!=null){
                    serverQueries=GroundCollision.queries(true);
                    serverAirAtCleanup=allProxyCellsAir((BlockView)serverWorld);
                    if(!clearSurface((BlockView)serverWorld,true)){
                        serverFailure.set("HUD server collision release identity mismatch");return;
                    }
                }
                serverReleased.set(true);
            });
        }else serverReleased.set(true);
    }
    public JsonObject evidence(MinecraftClient client){
        var e=new JsonObject();e.addProperty("schema",1);e.addProperty("kind",
                mode==HudGroundMovementMode.Mode.EXTENSION_COUPLED?"minecome_hud_ground_extension_coupled_v1":
                expansion!=null?"minecome_hud_ground_extension_fixture_v1":
                walkOnly?"minecome_hud_ground_corridor_walk_coupled_v1":
                        mode==HudGroundMovementMode.Mode.CORRIDOR_COUPLED?"minecome_hud_ground_corridor_coupled_v1":
                        mode==HudGroundMovementMode.Mode.CORRIDOR?"minecome_hud_ground_corridor_fixture_v1":
                        mode==HudGroundMovementMode.Mode.COUPLED?"minecome_hud_ground_movement_coupled_v1":"minecome_hud_ground_movement_fixture_v1");
        e.addProperty("save",save);e.addProperty("patch_run",patch.run());e.addProperty("patch_sha256",patch.sha256());
        if(mode.coupled()){
            e.addProperty("hud_run",hudRun);e.addProperty("trace_file",trace==null?traceFile.toString():trace.path().toString());
            e.addProperty("trace_records",trace==null?0:trace.records());e.addProperty("trace_closed",trace!=null&&trace.closed());
            e.addProperty("trace_result",traceResult);
        }
        e.addProperty("ground_source_kind",patch.sourceKind());e.addProperty("synthetic_input",true);e.addProperty("kcd_calls",false);
        e.addProperty("kcd_movement_applied",false);e.addProperty("physical_input_verified",false);e.addProperty("phase",phase());
        e.addProperty("client_walk",sequence==null?0:sequence.clientWalk());e.addProperty("server_walk",sequence==null?0:sequence.serverWalk());
        if(expansion!=null){e.add("extension",extensionEvidence());}
        else if(patch.corridor()){
            var corridor=(GroundCorridor)patch;var proof=new JsonObject();
            var anchor=new JsonObject();anchor.addProperty("x",patch.centerX());anchor.addProperty("y",patch.centerY());anchor.addProperty("z",patch.centerZ());proof.add("anchor",anchor);
            var hashes=new com.google.gson.JsonArray();for(String hash:corridor.tileHashes())hashes.add(hash);proof.add("tile_sha256",hashes);
            var bounds=new JsonObject();bounds.addProperty("min_x",corridor.minX());bounds.addProperty("max_x",corridor.maxX());bounds.addProperty("min_z",corridor.minZ());bounds.addProperty("max_z",corridor.maxZ());proof.add("bounds",bounds);
            proof.addProperty("original_edge_x",4);proof.addProperty("crossing_target_x",5.5);
            proof.addProperty("client_max_x",sequence==null?0:sequence.clientMaxX());proof.addProperty("server_max_x",sequence==null?0:sequence.serverMaxX());
            proof.addProperty("crossed_original_edge",sequence!=null&&sequence.clientMaxX()>=5.5&&sequence.serverMaxX()>=5.5);
            proof.addProperty("client_return_distance",sequence==null?0:sequence.clientReturnDistance());proof.addProperty("server_return_distance",sequence==null?0:sequence.serverReturnDistance());
            proof.addProperty("returned_to_start",passed&&sequence.clientReturnDistance()<=.75&&sequence.serverReturnDistance()<=.75);
            proof.addProperty("max_client_server_distance",Math.max(corridorSync.maxDistance(),sequence==null?0:sequence.maxClientServerDistance()));
            proof.addProperty("synchronization_paused_ticks",corridorSync.pausedTicks());proof.addProperty("reused_server_snapshot_ticks",corridorSync.sameSnapshotTicks());
            proof.addProperty("expired_input_releases",corridorSync.expiredInputReleases());
            proof.addProperty("crossing_hud_frames",crossingHudFrames);proof.addProperty("return_hud_frames",returnHudFrames);
            proof.addProperty("client_vanilla_cells_air",clientAirAtCleanup);proof.addProperty("server_vanilla_cells_air",serverAirAtCleanup);
            proof.addProperty("slab_count",patch.slabs().size());proof.addProperty("collision_cell_count",patch.cells().size());
            e.add("corridor",proof);
        }else if(patch.wide()){
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
    private JsonObject extensionEvidence(){
        var e=new JsonObject();
        e.addProperty("plan_sha256",expansion.sha256());e.addProperty("initial_sha256",expansion.initial().sha256());
        e.addProperty("expanded_sha256",expansion.expanded().sha256());
        var anchor=new JsonObject();anchor.addProperty("x",patch.centerX());anchor.addProperty("y",patch.centerY());anchor.addProperty("z",patch.centerZ());e.add("anchor",anchor);
        var hashes=new com.google.gson.JsonArray();for(String hash:expansion.tileHashes())hashes.add(hash);e.add("tile_sha256",hashes);
        e.addProperty("initial_max_x",8);e.addProperty("expanded_max_x",12);e.addProperty("trigger_x",EXTENSION_TRIGGER_X);
        e.addProperty("client_installed",extensionClientInstalled);e.addProperty("server_installed",extensionServerInstalled.get());
        e.addProperty("handoff_delay_fixture",extensionDelayNs!=0);e.addProperty("minimum_handoff_wait_ms",extensionDelayNs/1_000_000L);
        e.addProperty("handoff_wait_ms",extensionWaitNs/1_000_000.0);e.addProperty("handoff_trace_samples",handoffTraceSamples);
        e.addProperty("handoff_complete",extensionComplete);e.addProperty("coordinate_origin_preserved",true);
        e.addProperty("client_max_x",sequence==null?0:sequence.clientMaxX());e.addProperty("server_max_x",sequence==null?0:sequence.serverMaxX());
        e.addProperty("client_return_distance",sequence==null?0:sequence.clientReturnDistance());e.addProperty("server_return_distance",sequence==null?0:sequence.serverReturnDistance());
        e.addProperty("transition_hud_frames",transitionHudFrames);e.addProperty("crossing_hud_frames",extensionCrossingHudFrames);e.addProperty("return_hud_frames",returnHudFrames);
        e.addProperty("client_vanilla_cells_air",clientAirAtCleanup);e.addProperty("server_vanilla_cells_air",serverAirAtCleanup);
        e.addProperty("max_client_server_distance",Math.max(corridorSync.maxDistance(),sequence==null?0:sequence.maxClientServerDistance()));
        e.addProperty("slab_count",patch.slabs().size());e.addProperty("collision_cell_count",patch.cells().size());
        return e;
    }
    private void openTrace(MinecraftClient client,long now) throws IOException {
        Path run=client.runDirectory.toPath().toAbsolutePath().normalize();
        Path minecraft=run.getParent(),project=minecraft==null?null:minecraft.getParent();
        if(project==null || !Files.isRegularFile(project.resolve("AGENTS.md")) ||
                !Files.isRegularFile(project.resolve("minecraft/build.gradle")))
            throw new IOException("HUD movement trace requires the owned workspace run directory");
        String world=save.substring("MineCome-HudStream-".length());
        var traceSurface=expansion==null?patch:expansion.expanded();
        var context=new MovementTraceSink.Context(traceSurface.run(),traceSurface.sha256(),traceSurface.sourceKind(),save,world,
                patch.centerX(),patch.centerY(),patch.centerZ(),expansion!=null?MovementTraceSink.Profile.HUD_EXTENSION_WALK_COUPLED:walkOnly?MovementTraceSink.Profile.HUD_CORRIDOR_WALK_COUPLED:
                        patch.corridor()?MovementTraceSink.Profile.HUD_CORRIDOR_COUPLED:MovementTraceSink.Profile.HUD_COUPLED,
                0,64,0,patch.wide()&&!patch.corridor());
        trace=MovementTraceSink.open(traceFile,project.resolve("runtime/evidence"),context,now,System.currentTimeMillis());
        traceResult="pending";firstTraceSamplePending=true;
    }
    private boolean writeTrace(ServerSample observed,boolean force) throws IOException {
        var c=clientMotion;var s=observed.motion();
        // Timestamp only after selecting the immutable authoritative observation.
        boolean written=trace.sample(System.nanoTime(),System.currentTimeMillis(),sequence.phase().name(),
                new MovementTraceSink.Motion(c.x(),c.y(),c.z(),c.vx(),c.vy(),c.vz(),c.onGround(),c.proxySupport(),patch.wide()&&!patch.corridor(),patch.corridor()&&expansion==null,expansion!=null),
                new MovementTraceSink.Motion(s.x(),s.y(),s.z(),s.vx(),s.vy(),s.vz(),s.onGround(),s.proxySupport(),patch.wide()&&!patch.corridor(),patch.corridor()&&expansion==null,expansion!=null),
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
    private boolean allProxyCellsAir(BlockView world){return allProxyCellsAir(world,world==serverWorld?serverSurface:patch);}
    private static boolean allProxyCellsAir(BlockView world,GroundSurface surface){for(var c:surface.cells())if(!world.getBlockState(new BlockPos(c.x(),c.y(),c.z())).isAir())return false;return true;}
    private boolean clearSurface(BlockView world,boolean serverSide){
        var own=serverSide?serverSurface:patch;
        return own.corridor()?GroundCollision.clear(world,own.run(),own.sha256(),serverSide):GroundCollision.clear(world,own.run(),serverSide);
    }
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
        client.options.backKey.setPressed(input.backward());client.options.leftKey.setPressed(false);client.options.rightKey.setPressed(false);
        client.options.sneakKey.setPressed(false);client.options.sprintKey.setPressed(false);
    }
    private void release(MinecraftClient client){held=GroundMovementSequence.Held.NONE;inputLeaseUntil=0;apply(client,held);}
}
