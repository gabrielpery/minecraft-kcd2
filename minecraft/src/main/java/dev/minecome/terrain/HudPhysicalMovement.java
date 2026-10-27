package dev.minecome.terrain;

import com.google.gson.JsonObject;
import dev.minecome.hud.*;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.entity.attribute.EntityAttributes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.math.*;
import net.minecraft.world.*;
import net.minecraft.world.gen.chunk.FlatChunkGenerator;
import java.io.IOException;
import java.nio.file.*;
import java.util.UUID;
import java.util.concurrent.atomic.*;

/** Live v2 input in the owned HUD world. The file trace has no authority to call KCD. */
public final class HudPhysicalMovement {
    private record Observation(Object world,Object player,long sequence,long at,MovementTraceSink.Motion motion){}
    private final GroundPatch patch;
    private final String save;
    private final HudInputProtocol.Identity identity;
    private final boolean fixture;
    private final Path traceFile,viewFile;
    private final HudMovementKeys keys=new HudMovementKeys();
    private final HudMovementCompletion completion=new HudMovementCompletion();
    private final AtomicReference<Observation> observed=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicLong corrections=new AtomicLong();
    private final AtomicBoolean prepared=new AtomicBoolean(),installed=new AtomicBoolean(),serverReleased=new AtomicBoolean();
    private MinecraftServer server;
    private Object clientWorld,clientPlayer,serverWorld,serverPlayer;
    private UUID playerId;
    private HudMovementViewReader views;
    private MovementTraceSink trace;
    private MovementTraceSink.Motion clientMotion,anchor;
    private Path evidenceRoot;
    private String traceResult="not_started";
    private JsonObject viewFailure;
    private HudMovementBoundary boundary;
    private HudMovementBoundary.Decision boundaryStop;
    private long setupAt,stableAt,sequence,baselineCorrections,authorityUntil,endedAt,durationMs,events,heldTicks;
    private long firstView,lastView,viewUpdates;
    private long boundaryPauses,boundaryResumptions;
    private boolean boundaryAwaitingResume;
    private double clientWalk,serverWalk;
    private boolean setup,clientInstalled,teleported,ready,completed,controlsOwned,clientReleased,clientAir,serverAir,clientLand,serverLand,readyPublished;
    private volatile boolean closing;

    public HudPhysicalMovement(Path patchFile,Path traceFile,Path viewFile,String save,HudInputProtocol.Identity identity)throws IOException{
        this(patchFile,traceFile,viewFile,save,identity,false);
    }
    /** Fixture mode is explicit and emits a trace the live follower must reject. */
    public HudPhysicalMovement(Path patchFile,Path traceFile,Path viewFile,String save,HudInputProtocol.Identity identity,boolean fixture)throws IOException{
        patch=GroundPatch.read(patchFile);this.traceFile=traceFile;this.viewFile=viewFile;this.save=save;this.identity=identity;this.fixture=fixture;
        if(!patch.sourceKind().equals(fixture?"standalone_ground_fixture":"live_kcd_ground_patch") || patch.run().equals(identity.run()) ||
                !patch.run().matches("[0-9a-f]{32}") || !save.equals("MineCome-HudStream-"+UUID.fromString(save.substring("MineCome-HudStream-".length()))) ||
                !traceFile.isAbsolute() || !viewFile.isAbsolute())
            throw new IllegalArgumentException("Physical HUD requires matching patch provenance, owned save and absolute evidence files");
    }
    public void positionCorrection(){corrections.incrementAndGet();}
    public boolean completed(){return completed;}
    public boolean inputReady(long now){return ready && !closing && (completed || (views!=null && views.current(System.currentTimeMillis(),now)!=null));}
    public void authority(MinecraftClient client,long now,boolean fresh){
        boolean allowed=fresh && inputReady(now) && client.currentScreen==null && client.getOverlay()==null && !client.isPaused();
        keys.authority(now,allowed);authorityUntil=allowed?now+HudMovementKeys.HOLD_LEASE_NS:0;
        if(!allowed)release(client);
    }
    public void suspend(MinecraftClient client){keys.suspend();authorityUntil=0;release(client);}
    /** One-time actual world readiness; the stream mapping can exist before terrain settles. */
    public void publishReady(Path directory,long now)throws IOException{
        if(readyPublished || !inputReady(now) || completed)return;
        var sample=freshObservation(System.nanoTime());var view=views.current(System.currentTimeMillis(),System.nanoTime());
        if(sample==null || view==null || !grounded(sample.motion()) || !grounded(clientMotion) ||
                distance(clientMotion,sample.motion())>.01)return;
        Path parent=directory.toRealPath();
        if(!parent.startsWith(evidenceRoot.toRealPath()))throw new IOException("Physical readiness outside evidence");
        var e=new JsonObject();e.addProperty("schema",1);e.addProperty("kind",fixture?"minecome_hud_physical_fixture_ready_v1":"minecome_hud_physical_ready_v1");e.addProperty("ready",true);
        e.addProperty("scripted_input",fixture);
        e.addProperty("run",identity.run());e.addProperty("save",save);e.addProperty("patch_run",patch.run());e.addProperty("patch_sha256",patch.sha256());
        e.addProperty("target_pid",identity.targetPid());e.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));
        e.addProperty("utc_ms",System.currentTimeMillis());e.addProperty("view_seq",view.view().sequence());
        var a=new JsonObject();a.addProperty("x",sample.motion().x());a.addProperty("y",sample.motion().y());a.addProperty("z",sample.motion().z());e.add("anchor_mc",a);
        Path temp=parent.resolve("physical-ready.json.tmp"),target=parent.resolve("physical-ready.json");
        if(Files.exists(target,LinkOption.NOFOLLOW_LINKS))throw new IOException("Physical readiness already exists");
        Files.writeString(temp,e.toString(),StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
        Files.move(temp,target,StandardCopyOption.ATOMIC_MOVE);readyPublished=true;
    }
    public void event(MinecraftClient client,HudInputProtocol.Event event,long now)throws IOException{
        boolean allowed=now<authorityUntil && inputReady(now) && client.currentScreen==null && client.getOverlay()==null;
        if(keys.event(event.kind(),event.code(),now,allowed)){
            events++;
            if(trace==null)startTrace(client,now);
        }
    }
    /** KeyBinding state is applied immediately before vanilla polls it. */
    public void beforeTick(MinecraftClient client,long now){
        if(closing)return;
        checkFailure();
        if(clientWorld==null)return;
        requireClient(client);
        if(!ready || completed){release(client);return;}
        var view=views.current(System.currentTimeMillis(),now);
        if(view==null || now>=authorityUntil || client.currentScreen!=null || client.getOverlay()!=null || client.isPaused()){
            suspend(client);return;
        }
        client.player.setYaw(view.view().yaw());client.player.setPitch(view.view().pitch());
        if(lastView!=view.view().sequence()){lastView=view.view().sequence();viewUpdates++;if(firstView==0)firstView=lastView;}
        keys.expire(now);
        if(keys.ended()){release(client);return;}
        var motion=motion(client.player,hasGround(client.world,client.player));
        if(boundary!=null && !keys.neutral(now)){
            int forward=(keys.down(0x57,now)?1:0)-(keys.down(0x53,now)?1:0);
            int sideways=(keys.down(0x41,now)?1:0)-(keys.down(0x44,now)?1:0);
            var decision=boundary.check(motion,forward,sideways,keys.down(0x20,now),view.view().yaw(),
                    accelerationBound(client),jumpVelocity(client),client.player.isSprinting() || forward>0);
            if(!decision.allow()){
                boundaryStop=decision;boundaryPauses++;boundaryAwaitingResume=true;
                keys.suppressAtBoundary();release(client);return;
            }
            if(boundaryAwaitingResume){boundaryResumptions++;boundaryAwaitingResume=false;}
        }
        apply(client,now);
    }
    public void afterTick(MinecraftClient client,long now)throws IOException{
        if(closing)return;
        checkFailure();
        if(clientWorld==null){
            if(client.world==null || client.player==null || client.getServer()==null || !client.isIntegratedServerRunning())
                throw new IllegalStateException("Physical HUD requires owned integrated world");
            clientWorld=client.world;clientPlayer=client.player;server=client.getServer();playerId=client.player.getUuid();
            Path run=client.runDirectory.toPath().toAbsolutePath().normalize(),project=run.getParent().getParent();
            if(!Files.isRegularFile(project.resolve("AGENTS.md")) || !Files.isRegularFile(project.resolve("minecraft/build.gradle")))
                throw new IOException("Physical HUD requires owned workspace run directory");
            evidenceRoot=project.resolve("runtime/evidence");
            views=new HudMovementViewReader(viewFile,evidenceRoot,identity,patch.run(),patch.sha256(),fixture);views.start();
        }
        requireClient(client);
        if(!setup){setup=true;setupAt=now;release(client);prepareServer();return;}
        if(!installed.get()){
            release(client);
            if(prepared.get() && !teleported){
                if(!allAir(client.world) || !GroundCollision.available(false))throw new IllegalStateException("Physical HUD client collision ownership changed");
                var view=views.current(System.currentTimeMillis(),now);
                if(view!=null){
                    GroundCollision.install(client.world,patch,false);clientInstalled=true;teleported=true;
                    float yaw=view.view().yaw(),pitch=view.view().pitch();
                    server.execute(()->{
                        try{var entity=server.getPlayerManager().getPlayer(playerId);requireServer(server,entity);
                            entity.teleport(server.getOverworld(),0,patch.groundForFeet(0,0,.3)+.05,0,yaw,pitch);
                            entity.setVelocity(Vec3d.ZERO);entity.fallDistance=0;installed.set(true);
                        }catch(Exception e){failure.set("Physical HUD teleport: "+e.getMessage());}
                    });
                }
            }
            if(now-setupAt>8_000_000_000L)throw new IllegalStateException("Physical HUD install/view deadline");
            return;
        }
        var sample=freshObservation(System.nanoTime());
        if(sample==null){
            release(client);
            if(ready || now-setupAt>8_000_000_000L)throw new IllegalStateException("Physical HUD server observation stale");
            return;
        }
        if(!ready && (client.player.getAbilities().allowFlying || client.player.getPos().squaredDistanceTo(0,patch.groundForFeet(0,0,.3),0)>1)){
            release(client);if(now-setupAt>8_000_000_000L)throw new IllegalStateException("Physical HUD teleport/abilities handoff deadline");return;
        }
        if(!GroundCollision.installed(client.world,false) || !allAir(client.world) ||
                client.player.getAbilities().flying || client.player.getAbilities().allowFlying)
            throw new IllegalStateException("Physical HUD client collision/abilities contract changed");
        clientMotion=motion(client.player,hasGround(client.world,client.player));
        if(!ready){
            release(client);
            boolean stable=grounded(clientMotion) && grounded(sample.motion()) && distance(clientMotion,sample.motion())<.01 &&
                    Math.abs(sample.motion().x())<.001 && Math.abs(sample.motion().z())<.001 &&
                    Math.abs(clientMotion.vy())<.1 && client.currentScreen==null && client.getOverlay()==null;
            if(!stable)stableAt=0;
            else if(stableAt==0)stableAt=now;
            else if(now-stableAt>=250_000_000L){
                var view=views.current(System.currentTimeMillis(),System.nanoTime());
                if(view!=null){
                    var initial=new HudMovementBoundary(patch,sample.motion()).check(clientMotion,1,0,false,view.view().yaw(),
                            accelerationBound(client),jumpVelocity(client),false);
                    if(!initial.allow())throw new IllegalStateException("Physical HUD sampled ground has insufficient forward braking clearance: "+initial.reason()+"; use a more level starting patch or turn before starting the bounded lab");
                    ready=true;baselineCorrections=corrections.get();
                }
            }
            if(now-setupAt>8_000_000_000L && !ready)throw new IllegalStateException("Physical HUD settling deadline");
            return;
        }
        if(completed || trace==null)return;
        if(corrections.get()!=baselineCorrections)throw new IllegalStateException("Physical HUD post-settle correction");
        if(views.current(System.currentTimeMillis(),System.nanoTime())==null){
            // Recheck once without I/O or waiting: a new immutable sample may
            // have arrived between the first check and diagnostic collection.
            var inspection=views.inspect(System.currentTimeMillis(),System.nanoTime());
            if(inspection.current()==null){
                viewFailure=inspection.diagnostics();
                throw new IllegalStateException("Physical HUD camera lease expired");
            }
        }
        var sm=sample.motion();
        if(!patch.containsFeet(clientMotion.x(),clientMotion.z(),.31) || !patch.containsFeet(sm.x(),sm.z(),.31) ||
                distance(clientMotion,anchor)>1.8 || distance(sm,anchor)>1.8 ||
                clientMotion.y()-anchor.y()< -1.5 || sm.y()-anchor.y()< -1.5 ||
                clientMotion.y()-anchor.y()>1.5 || sm.y()-anchor.y()>1.5)
            throw new IllegalStateException("Physical HUD displacement/coverage bound");
        clientWalk=Math.max(clientWalk,Math.hypot(clientMotion.x()-anchor.x(),clientMotion.z()-anchor.z()));
        serverWalk=Math.max(serverWalk,Math.hypot(sm.x()-anchor.x(),sm.z()-anchor.z()));
        if(!clientMotion.onGround())clientAir=true;else if(clientAir)clientLand=true;
        if(!sm.onGround())serverAir=true;else if(serverAir)serverLand=true;
        keys.expire(now);
        if(keys.ended()){
            release(client);if(endedAt==0)endedAt=now;
            if(now-keys.startedAt()>HudMovementKeys.ACTIVE_NS+HudMovementKeys.SETTLE_NS || now-endedAt>HudMovementKeys.SETTLE_NS)
                throw new IllegalStateException("Physical HUD final settling deadline");
            boolean settled=grounded(clientMotion) && grounded(sm) && distance(clientMotion,sm)<.1 &&
                    Math.hypot(clientMotion.vx(),clientMotion.vz())<.03 && Math.hypot(sm.vx(),sm.vz())<.03;
            var result=completion.update(now,settled,clientWalk,serverWalk);
            // The server can still be one packet behind at the first slow
            // client tick. Wait for the same complete resting interval before
            // either passing or rejecting its final displacement proof.
            if(result==HudMovementCompletion.Result.INSUFFICIENT_WALK)
                throw new IllegalStateException("Physical HUD ended without client/server walking proof");
            if(result==HudMovementCompletion.Result.PASSED && writeTrace(sample,"PASSED",true)){
                trace.finish(System.currentTimeMillis(),"passed","PASSED","Physical HUD input produced bounded vanilla walking on client and server");
                traceResult="passed";durationMs=(now-keys.startedAt())/1_000_000;completed=true;views.close();
            }else writeTrace(sample,settled?"RESTING":"LANDING",false);
        }else writeTrace(sample,!clientMotion.onGround()?"JUMPING":keys.neutral(now)?"RESTING":"WALKING",false);
    }
    private void startTrace(MinecraftClient client,long now)throws IOException{
        var sample=freshObservation(System.nanoTime());
        if(sample==null || !grounded(clientMotion) || !grounded(sample.motion()) || distance(clientMotion,sample.motion())>.01 ||
                Math.abs(sample.motion().x())>.001 || Math.abs(sample.motion().z())>.001)
            throw new IllegalStateException("Physical HUD first edge lacks exact settled anchor");
        anchor=sample.motion();
        boundary=new HudMovementBoundary(patch,anchor);
        String world=save.substring("MineCome-HudStream-".length());
        var context=new MovementTraceSink.Context(patch.run(),patch.sha256(),patch.sourceKind(),save,world,
                patch.centerX(),patch.centerY(),patch.centerZ(),fixture?MovementTraceSink.Profile.HUD_PHYSICAL_FIXTURE:MovementTraceSink.Profile.HUD_PHYSICAL,anchor.x(),anchor.y(),anchor.z());
        trace=MovementTraceSink.open(traceFile,evidenceRoot,context,now,System.currentTimeMillis());traceResult="pending";
        if(!writeTrace(sample,"SETTLING",true))throw new IllegalStateException("Physical HUD initial trace sample rejected");
    }
    private boolean writeTrace(Observation sample,String phase,boolean force)throws IOException{
        // On a slab descent the client may already have landed while the fresh
        // server sample still has its previous onGround flag without support.
        phase=HudMovementPhase.forAuthoritativeGround(phase,grounded(sample.motion()));
        return trace.sample(System.nanoTime(),System.currentTimeMillis(),phase,clientMotion,sample.motion(),sample.sequence(),sample.at(),force);
    }
    private void prepareServer(){
        server.execute(()->{
            try{
                var world=server.getOverworld();var entity=server.getPlayerManager().getPlayer(playerId);
                if(!save.equals(server.getSaveProperties().getLevelName()) || entity==null || entity.getWorld()!=world ||
                        !(world.getChunkManager().getChunkGenerator() instanceof FlatChunkGenerator generator) ||
                        !generator.getConfig().getLayerBlocks().isEmpty() || !allAir(world) || !GroundCollision.available(true))
                    throw new IllegalStateException("Physical HUD server is not owned empty flat world");
                serverWorld=world;serverPlayer=entity;GroundCollision.install(world,patch,true);
                // Inspected Yarn1.21.1: tickMovement gates double-jump on allowFlying;
                // server sendAbilitiesUpdate publishes the authoritative S2C abilities.
                entity.getAbilities().flying=false;entity.getAbilities().allowFlying=false;entity.sendAbilitiesUpdate();
                server.setFlightEnabled(true);prepared.set(true);
            }catch(Exception e){failure.set("Physical HUD setup: "+e.getMessage());}
        });
    }
    public void observe(MinecraftServer source){
        if(!installed.get() || closing)return;
        try{
            var entity=source.getPlayerManager().getPlayer(playerId);requireServer(source,entity);
            if(!allAir(source.getOverworld()) || entity.getAbilities().flying || entity.getAbilities().allowFlying)
                throw new IllegalStateException("Physical HUD server collision/abilities contract changed");
            observed.set(new Observation(entity.getWorld(),entity,++sequence,System.nanoTime(),motion(entity,hasGround(source.getOverworld(),entity))));
        }catch(Exception e){failure.set("Physical HUD observation: "+e.getMessage());}
    }
    private Observation freshObservation(long now){
        var value=observed.get();
        return value!=null && value.world()==serverWorld && value.player()==serverPlayer && now>=value.at() && now-value.at()<=250_000_000L?value:null;
    }
    private void requireClient(MinecraftClient c){
        if(c.world!=clientWorld || c.player!=clientPlayer || c.getServer()!=server || !c.isIntegratedServerRunning() || c.world.getRegistryKey()!=World.OVERWORLD)
            throw new IllegalStateException("Physical HUD client world/player changed");
    }
    private void requireServer(MinecraftServer source,ServerPlayerEntity player){
        if(source!=server || source.getOverworld()!=serverWorld || player==null || player!=serverPlayer || player.getWorld()!=serverWorld ||
                !save.equals(source.getSaveProperties().getLevelName()) || !GroundCollision.installed(source.getOverworld(),true))
            throw new IllegalStateException("Physical HUD server world/player changed");
    }
    private void checkFailure(){if(failure.get()!=null)throw new IllegalStateException(failure.get());if(views!=null && views.failure()!=null)throw new IllegalStateException(views.failure());}
    public void abort(MinecraftClient client,String reason){terminate("failed","FAILED",reason);close(client);}
    public void close(MinecraftClient client){
        if(closing)return;closing=true;keys.close();authorityUntil=0;if(controlsOwned)release(client);
        terminate("stopped","STOPPED","Physical HUD closed before completion");if(views!=null)views.close();
        clientReleased=!clientInstalled || GroundCollision.clear((BlockView)clientWorld,patch.run(),false);
        if(server==null)serverReleased.set(true);
        else server.execute(()->{
            if(serverWorld!=null && !GroundCollision.clear((BlockView)serverWorld,patch.run(),true)){failure.set("Physical HUD cleanup ownership mismatch");return;}
            serverReleased.set(true);
        });
    }
    public boolean cleanupComplete(){return closing && clientReleased && serverReleased.get();}
    private void terminate(String result,String phase,String reason){
        if(trace==null || trace.closed())return;
        try{trace.finish(System.currentTimeMillis(),result,phase,reason);traceResult=result;}
        catch(Exception e){traceResult="failed";failure.compareAndSet(null,e.toString());}
    }
    public JsonObject evidence(MinecraftClient client){
        var e=new JsonObject();e.addProperty("schema",1);e.addProperty("kind","minecome_hud_physical_movement_v1");
        e.addProperty("run",identity.run());e.addProperty("save",save);e.addProperty("patch_run",patch.run());e.addProperty("patch_sha256",patch.sha256());
        e.addProperty("ground_source_kind",patch.sourceKind());e.addProperty("input_source",fixture?"scripted_hud_physical_controller_fixture":"hud_input_v2");e.addProperty("scripted_input",fixture);e.addProperty("physical_input_verified",false);
        e.addProperty("started",keys.started());e.addProperty("completed",completed);e.addProperty("movement_events_applied",events);e.addProperty("held_ticks",heldTicks);
        e.addProperty("client_walk",clientWalk);e.addProperty("server_walk",serverWalk);e.addProperty("client_air",clientAir);e.addProperty("server_air",serverAir);
        e.addProperty("client_land",clientLand);e.addProperty("server_land",serverLand);e.addProperty("duration_ms",durationMs);
        e.addProperty("trace_file",traceFile.toString());e.addProperty("trace_records",trace==null?0:trace.records());e.addProperty("trace_closed",trace!=null&&trace.closed());e.addProperty("trace_result",traceResult);
        var a=new JsonObject();if(anchor!=null){a.addProperty("x",anchor.x());a.addProperty("y",anchor.y());a.addProperty("z",anchor.z());}e.add("anchor_mc",a);
        e.addProperty("view_first_sequence",firstView);e.addProperty("view_last_sequence",lastView);e.addProperty("view_updates",viewUpdates);
        if(views!=null)e.add("view_reader",views.diagnostics(System.currentTimeMillis(),System.nanoTime()));
        if(viewFailure!=null)e.add("view_failure",viewFailure.deepCopy());
        if(boundaryStop!=null){
            var stop=new JsonObject();stop.addProperty("reason",boundaryStop.reason());stop.addProperty("flat_support",boundaryStop.flat());
            if(Double.isFinite(boundaryStop.minGround()))stop.addProperty("minimum_ground",boundaryStop.minGround());
            if(Double.isFinite(boundaryStop.maxGround()))stop.addProperty("maximum_ground",boundaryStop.maxGround());
            stop.addProperty("predicted_reach",boundaryStop.reach());e.add("boundary_stop",stop);
        }
        e.addProperty("boundary_pauses",boundaryPauses);e.addProperty("boundary_resumptions",boundaryResumptions);
        e.addProperty("boundary_awaiting_fresh_press",boundaryAwaitingResume);
        e.addProperty("post_settle_corrections",corrections.get()-baselineCorrections);e.addProperty("client_proxy_released",clientReleased);e.addProperty("server_proxy_released",serverReleased.get());
        e.addProperty("controls_released",!client.options.forwardKey.isPressed()&&!client.options.backKey.isPressed()&&!client.options.leftKey.isPressed()&&!client.options.rightKey.isPressed()&&!client.options.jumpKey.isPressed());
        return e;
    }
    private void apply(MinecraftClient c,long now){
        controlsOwned=true;
        c.options.forwardKey.setPressed(keys.down(0x57,now));c.options.backKey.setPressed(keys.down(0x53,now));
        c.options.leftKey.setPressed(keys.down(0x41,now));c.options.rightKey.setPressed(keys.down(0x44,now));c.options.jumpKey.setPressed(keys.down(0x20,now));
        c.options.sneakKey.setPressed(false);c.options.sprintKey.setPressed(false);if(!keys.neutral(now))heldTicks++;
    }
    private void release(MinecraftClient c){
        controlsOwned=true;c.options.forwardKey.setPressed(false);c.options.backKey.setPressed(false);c.options.leftKey.setPressed(false);c.options.rightKey.setPressed(false);
        c.options.jumpKey.setPressed(false);c.options.sneakKey.setPressed(false);c.options.sprintKey.setPressed(false);
    }
    private boolean grounded(MovementTraceSink.Motion m){return m.onGround()&&m.proxySupport()&&Math.abs(m.y()-patch.groundForFeet(m.x(),m.z(),.3))<.15;}
    private boolean allAir(BlockView world){for(var cell:patch.cells())if(!world.getBlockState(new BlockPos(cell.x(),cell.y(),cell.z())).isAir())return false;return true;}
    private static boolean hasGround(CollisionView world,Entity player){
        var b=player.getBoundingBox();var below=new Box(b.minX+.001,b.minY-.06,b.minZ+.001,b.maxX-.001,b.minY+.001,b.maxZ-.001);
        for(var shape:world.getBlockCollisions(player,below))if(!shape.isEmpty())return true;return false;
    }
    private static MovementTraceSink.Motion motion(Entity entity,boolean support){
        var p=entity.getPos();var v=entity.getVelocity();return new MovementTraceSink.Motion(p.x,p.y,p.z,v.x,v.y,v.z,entity.isOnGround(),support);
    }
    private static double distance(MovementTraceSink.Motion a,MovementTraceSink.Motion b){return Math.sqrt(Math.pow(a.x()-b.x(),2)+Math.pow(a.y()-b.y(),2)+Math.pow(a.z()-b.z(),2));}
    private static double accelerationBound(MinecraftClient client){
        // Reserve the vanilla 30% sprint transition even if it occurs after
        // this callback. The actual key polling and movement stay vanilla.
        if(!client.player.getStatusEffects().isEmpty())throw new IllegalStateException("Physical HUD movement effects unsupported");
        return client.player.getMovementSpeed()*1.3+.00001;
    }
    private static double jumpVelocity(MinecraftClient client){
        return client.player.getAttributeValue(EntityAttributes.GENERIC_JUMP_STRENGTH)+.00001;
    }
}
