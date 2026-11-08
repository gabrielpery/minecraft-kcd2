package dev.minecome.terrain;

import com.google.gson.JsonObject;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.hud.HudMovementViewReader;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.entity.Entity;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.math.*;
import net.minecraft.world.*;
import java.io.IOException;
import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.atomic.*;

/** Ongoing vanilla movement on ephemeral host collision; inventory/mode/player state stay vanilla. */
public final class GameplayMovement {
    private record Observation(Object world,Object player,long seq,long at,long utc,GameplayBoundary.Motion motion,float yaw,float pitch,boolean grounded,boolean flying,boolean falling,float fallDistance,boolean alive){}
    private record RespawnStep(long epoch,GameplayBoundary.Motion from,GameplayBoundary.Motion target,long at){}
    private final GameplayWorld save;private volatile GroundSurface surface,serverSurface;
    private final GameplayTerrainBinding binding;private final GameplayTerrainBinding.Position resume;
    private final HudInputProtocol.Identity identity;private final HudMovementViewReader views;
    private final GameplayMotionFiles files;private final GameplayMovementKeys keys;
    private final boolean flight=Boolean.getBoolean("minecome.gameplayFlight");
    private GameplayBoundary boundary;private final boolean fixture;
    private final GameplayTerrainAdmission growth;
    private GameplayTerrainAdmission.Pending admission;
    private volatile GameplayTerrainAdmission.Pending serverAdmission;
    private boolean admissionSubmitted;private long admissionAt,admissions;
    private final AtomicReference<Observation> observation=new AtomicReference<>(),lastGrounded=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicLong clientQueries=new AtomicLong(),serverQueries=new AtomicLong();
    private final AtomicBoolean serverInstalled=new AtomicBoolean(),serverReleased=new AtomicBoolean(),teleported=new AtomicBoolean();
    private final long born=System.nanoTime();
    private volatile MinecraftServer server;private volatile Object serverWorld,serverPlayer;
    private Object clientWorld,clientPlayer;private volatile UUID playerId;
    private volatile boolean closing,ready;private boolean clientInstalled,clientReleased,teleportRequested,authority,controlsOwned;
    private long setupAt,stableAt,sequence,events,heldTicks,boundaryPauses;private double clientWalk,serverWalk;
    private long sourcePauses,heldSourcePauses;private JsonObject lastSourcePause,lastHeldSourcePause;
    private long clientFlightTicks,serverFlightTicks;private double maxClientAltitude,maxServerAltitude;
    private volatile boolean resumeFallRestored,resumeFallLanded;
    private volatile float resumeFallDistanceMax,resumeFallLandingHealth;
    private volatile int resumeFallLandingAge;
    private GameplayBoundary.Motion anchor;private String paused="starting";
    private Observation lastAlive;private volatile Observation deathAnchor;
    private volatile RespawnStep respawnStep;
    private volatile long lifecycleEpoch,serverRespawns,clientRespawns;
    private final AtomicLong deathAcknowledged=new AtomicLong(),respawnAcknowledged=new AtomicLong();
    private GameplayBlocks blocks;
    public void blockController(GameplayBlocks controller){if(clientWorld!=null||serverInstalled.get())throw new IllegalStateException("Block controller must precede world load");blocks=controller;}
    public GameplayMovement(Path root,GameplayWorld save,Path groundFile,boolean fixture,HudInputProtocol.Identity identity,Path evidenceDirectory)throws IOException{
        this.save=save;this.fixture=fixture;this.identity=identity;keys=new GameplayMovementKeys(flight);binding=GameplayTerrainBinding.open(save,groundFile,fixture,Boolean.getBoolean("minecome.gameplayBlocks"),Boolean.getBoolean("minecome.gameplayExplore"),flight);surface=binding.currentSurface();serverSurface=surface;resume=binding.resume();
        boundary=new GameplayBoundary(surface);views=new HudMovementViewReader(evidenceDirectory.resolve("host-view.json"),root.resolve("runtime/evidence"),identity,surface.run(),surface.sha256(),fixture);
        files=new GameplayMotionFiles(root,evidenceDirectory,binding);views.start();files.start();
        growth=binding.coverage()==null?null:new GameplayTerrainAdmission(evidenceDirectory,binding.coverage(),identity,save.id().toString());
    }
    public GroundSurface surface(){return surface;}
    public boolean ready(){return ready&&!closing;}
    public long respawnEpoch(){return lifecycleEpoch;}
    public boolean deathPending(){return deathAnchor!=null&&respawnStep==null;}
    public boolean respawnPending(){return respawnStep!=null;}
    public boolean nativeRespawnRequired(){return !fixture;}
    public Vec3d respawnFromHost(){var step=respawnStep;var dead=deathAnchor;return step!=null?nativeVector(step.from()):dead==null?null:nativeVector(dead.motion());}
    public Vec3d respawnTargetHost(){var step=respawnStep;return step==null?null:nativeVector(step.target());}
    /** Acknowledgments are admitted by the coordinator's exact run/world/epoch/from/target checks. */
    public void acknowledgeDeath(long epoch){
        if(epoch<=0||epoch!=lifecycleEpoch||deathAnchor==null)throw new IllegalStateException("Unexpected death acknowledgment");
        deathAcknowledged.set(epoch);
    }
    public void acknowledgeRespawn(long epoch){
        var step=respawnStep;
        if(step==null||epoch!=step.epoch()||deathAcknowledged.get()!=epoch||clientRespawns!=serverRespawns)
            throw new IllegalStateException("Unexpected respawn acknowledgment");
        respawnAcknowledged.set(epoch);
    }
    /** Trusted AFTER_RESPAWN admission, after the coordinator selects a safe captured destination.
     * Does not move the player, change survival state or reinstall collision. */
    public void serverRespawn(ServerPlayerEntity oldPlayer,ServerPlayerEntity newPlayer,long epoch){
        if(server==null||!server.isOnThread()||closing||!ready||oldPlayer!=serverPlayer||oldPlayer==newPlayer||oldPlayer==null||newPlayer==null||
                oldPlayer.isAlive()||!newPlayer.isAlive()||oldPlayer.getServer()!=server||newPlayer.getServer()!=server||
                oldPlayer.getWorld()!=serverWorld||newPlayer.getWorld()!=serverWorld||!oldPlayer.getUuid().equals(playerId)||!newPlayer.getUuid().equals(playerId)||
                oldPlayer.networkHandler!=newPlayer.networkHandler||deathAnchor==null||deathAnchor.player()!=oldPlayer||epoch!=lifecycleEpoch||epoch<=0||
                respawnStep!=null||serverRespawns!=clientRespawns||serverAdmission!=null||admission!=null||
                !GroundCollision.matches((BlockView)serverWorld,serverSurface,true))throw new IllegalStateException("Gameplay server respawn ownership changed");
        var target=motion(newPlayer);
        double floor=blocks==null?serverSurface.groundForFeet(target.x(),target.z(),.3):blocks.groundForFeet((BlockView)serverWorld,target.x(),target.y(),target.z(),.3);
        if(!serverSurface.containsFeet(target.x(),target.z(),.31)||!Double.isFinite(floor)||target.y()<floor-.00001||target.y()>floor+.2||
                !newPlayer.getServerWorld().isSpaceEmpty(newPlayer,newPlayer.getBoundingBox()))throw new IllegalStateException("Respawn destination is outside clear captured ground");
        respawnStep=new RespawnStep(epoch,deathAnchor.motion(),target,System.nanoTime());
        observation.set(null);lastGrounded.set(null);lastAlive=null;serverPlayer=newPlayer;serverRespawns++;
    }
    /** Called before ordinary client ticks, paired with the explicit server replacement. */
    public void clientRespawn(MinecraftClient client,ClientPlayerEntity oldPlayer,long epoch){
        var step=respawnStep;
        if(!client.isOnThread()||closing||!ready||oldPlayer!=clientPlayer||oldPlayer==client.player||oldPlayer==null||oldPlayer.isAlive()||
                client.player==null||!client.player.isAlive()||client.world!=clientWorld||client.getServer()!=server||!client.isIntegratedServerRunning()||
                oldPlayer.getWorld()!=clientWorld||client.player.getWorld()!=clientWorld||!oldPlayer.getUuid().equals(playerId)||!client.player.getUuid().equals(playerId)||
                step==null||epoch!=step.epoch()||serverRespawns!=clientRespawns+1||!GroundCollision.matches(client.world,surface,false))
            throw new IllegalStateException("Gameplay client respawn ownership changed");
        suspend(client);clientPlayer=client.player;clientRespawns=serverRespawns;paused="respawn_pending";
    }
    private void check(){if(views.failure()!=null)failure.compareAndSet(null,views.failure());if(files.failure()!=null)failure.compareAndSet(null,files.failure());if(growth!=null&&growth.failure()!=null)failure.compareAndSet(null,growth.failure());if(failure.get()!=null)throw new IllegalStateException(failure.get());}
    public boolean terrainTransition(){return admission!=null;}
    public void authority(MinecraftClient client,long now,boolean fresh){
        authority=fresh&&ready()&&client.player!=null&&client.player.isAlive()&&deathAnchor==null&&respawnStep==null&&client.currentScreen==null&&client.getOverlay()==null&&!client.isPaused();keys.authority(now,authority);if(!authority){release(client);stopFlightDrift(client);}
    }
    public void event(MinecraftClient client,HudInputProtocol.Event event,long now){
        if(!flight&&(event.code()==0x10||event.code()==0x11))return;
        if(keys.event(event.kind(),event.code(),now,authority&&ready()))events++;
    }
    public void suspend(MinecraftClient client){authority=false;keys.suspend();release(client);stopFlightDrift(client);}
    public void beforeTick(MinecraftClient client,long now){
        if(closing)return;check();if(clientWorld==null)return;requireClient(client);
        if(!client.player.isAlive()||deathAnchor!=null||respawnStep!=null){paused=respawnStep!=null?"respawn_pending":"dead";suspend(client);if(blocks!=null)blocks.suspend(client);return;}
        if(admission!=null){paused="terrain_admission";suspend(client);if(blocks!=null)blocks.suspend(client);return;}
        if(!ready()||!authority||client.currentScreen!=null||client.getOverlay()!=null||client.isPaused()){suspend(client);return;}
        var view=views.current(System.currentTimeMillis(),now);var reading=readObservation();var observed=fresh(reading);
        if(view==null||observed==null){recordSourcePause(now,view==null,observed==null,reading);paused="source_stale";suspend(client);return;}
        client.player.setYaw(view.view().yaw());client.player.setPitch(view.view().pitch());
        if(client.player.isFallFlying()||client.player.getAbilities().flying&&(!flight||!creativeFlight(client.player))){paused="flight_not_connected";suspend(client);return;}
        keys.tick(now);
        var motion=motion(client.player);
        int forward=(keys.down('W',now)?1:0)-(keys.down('S',now)?1:0),side=(keys.down('A',now)?1:0)-(keys.down('D',now)?1:0);
        boolean flying=flight&&creativeFlight(client.player),jump=keys.down(0x20,now),sneak=flight&&keys.down(0x10,now),sprint=flight&&keys.down(0x11,now);
        boolean allowed=flying?boundary.allowsFlight(motion,forward,side,(jump?1:0)-(sneak?1:0),view.view().yaw(),client.player.getAbilities().getFlySpeed(),sprint||client.player.isSprinting()):boundary.allows(motion,forward,side,jump,view.view().yaw(),client.player.getMovementSpeed()*1.3+.00001);
        if((flying||!keys.neutral(now))&&!allowed){
            boundaryPauses++;paused="terrain_frontier";suspend(client);return;
        }
        paused="none";controlsOwned=true;
        client.options.forwardKey.setPressed(keys.down('W',now));client.options.backKey.setPressed(keys.down('S',now));
        client.options.leftKey.setPressed(keys.down('A',now));client.options.rightKey.setPressed(keys.down('D',now));client.options.jumpKey.setPressed(jump);
        if(flight){client.options.sneakKey.setPressed(sneak);client.options.sprintKey.setPressed(sprint);}
        if(!keys.neutral(now))heldTicks++;
    }
    public void afterTick(MinecraftClient client,long now){
        if(closing)return;check();
        if(clientWorld==null){
            if(client.world==null||client.player==null||client.getServer()==null)return;
            if(client.world.getRegistryKey()!=World.OVERWORLD||!client.isIntegratedServerRunning())throw new IllegalStateException("Gameplay terrain requires owned overworld");
            clientWorld=client.world;clientPlayer=client.player;playerId=client.player.getUuid();setupAt=now;
            if(server!=null&&server!=client.getServer())throw new IllegalStateException("Gameplay server changed");server=client.getServer();
        }
        requireClient(client);
        if(!clientInstalled){
            release(client);if(!serverInstalled.get())return;
            if(!GroundCollision.available(false)||!allAir(client.world))throw new IllegalStateException("Gameplay collision cells already occupied");
            GroundCollision.install(client.world,surface,false);clientInstalled=true;
        }
        if(!teleportRequested){
            teleportRequested=true;server.execute(()->{
                try{
                    if(closing)return;var p=server.getPlayerManager().getPlayer(playerId);requireServer(server,p);
                    if(resume!=null&&resume.flying()&&!creativeFlight(p))throw new IllegalStateException("Aerial checkpoint differs from saved vanilla Creative flight abilities");
                    if(resume!=null&&resume.falling()&&(p.getAbilities().flying||p.isFallFlying()||p.hasVehicle()))throw new IllegalStateException("Falling checkpoint differs from saved vanilla abilities");
                    var v=views.current(System.currentTimeMillis(),System.nanoTime());float yaw=resume!=null?resume.yaw():v==null?p.getYaw():v.view().yaw();
                    float pitch=resume!=null?resume.pitch():v==null?p.getPitch():v.view().pitch();
                    double x=resume==null?0:resume.x(),y=resume==null?surface.groundForFeet(0,0,.3)+.05:resume.y(),z=resume==null?0:resume.z();
                    p.teleport(server.getOverworld(),x,y,z,yaw,pitch);p.setVelocity(Vec3d.ZERO);p.fallDistance=resume!=null&&resume.falling()?resume.fallDistance():0;
                    if(resume!=null&&resume.falling()){resumeFallDistanceMax=p.fallDistance;resumeFallRestored=true;}teleported.set(true);
                }catch(Exception e){failure.set("Gameplay attachment: "+e);}
            });return;
        }
        var o=fresh(readObservation());var current=motion(client.player);
        if(!ready){
            boolean aerial=resume!=null&&resume.flying();
            boolean deadAttached=!client.player.isAlive()&&o!=null&&!o.alive()&&surface.containsFeet(current.x(),current.z(),.31)&&client.world.isSpaceEmpty(client.player,client.player.getBoundingBox());
            boolean stable=teleported.get()&&o!=null&&(deadAttached||(aerial?creativeFlight(client.player)&&o.flying()&&Math.abs(current.vy())<.01&&Math.abs(current.vx())<.01&&Math.abs(current.vz())<.01:grounded(current,(BlockView)clientWorld)&&o.grounded()))&&distance(current,o.motion())<.01&&views.current(System.currentTimeMillis(),now)!=null;
            if(!stable)stableAt=0;else if(stableAt==0)stableAt=now;else if(now-stableAt>=250_000_000L){
                // Publish the anchor before the volatile ready flag exposes it to
                // the integrated server's flight observations and pose writer.
                anchor=o.motion();ready=true;var proof=evidence(client);proof.addProperty("ready",true);files.ready(proof);
            }
            if(now-setupAt>12_000_000_000L)throw new IllegalStateException("Gameplay attachment did not settle");return;
        }
        if(!GroundCollision.matches(client.world,surface,false)||!allAir(client.world))throw new IllegalStateException("Gameplay terrain ownership changed");
        if(!client.player.isAlive()||deathAnchor!=null||respawnStep!=null){suspend(client);return;}
        if(growth!=null)admitTerrain(client,now);
        if(flight&&creativeFlight(client.player)){clientFlightTicks++;maxClientAltitude=Math.max(maxClientAltitude,current.y()-anchor.y());}
        if(o!=null){clientWalk=Math.max(clientWalk,Math.hypot(current.x()-anchor.x(),current.z()-anchor.z()));serverWalk=Math.max(serverWalk,Math.hypot(o.motion().x()-anchor.x(),o.motion().z()-anchor.z()));}
    }
    /** May run before the client joins, preventing a saved player falling before collision appears. */
    public void observe(MinecraftServer source){
        if(closing)return;
        try{
            if(!save.saveName().equals(source.getSaveProperties().getLevelName()))return;
            if(server==null)server=source;if(server!=source)throw new IllegalStateException("Gameplay server identity changed");
            if(!serverInstalled.get()){
                if(!GroundCollision.available(true)||!allAir(source.getOverworld(),serverSurface))throw new IllegalStateException("Gameplay server collision cells occupied");
                serverWorld=source.getOverworld();GroundCollision.install(source.getOverworld(),serverSurface,true);serverInstalled.set(true);
            }
            if(playerId==null)return;var p=source.getPlayerManager().getPlayer(playerId);requireServer(source,p);
            if(!teleported.get())return;
            var m=motion(p);var o=new Observation(p.getWorld(),p,++sequence,System.nanoTime(),System.currentTimeMillis(),m,p.getYaw(),p.getPitch(),grounded(m,(BlockView)serverWorld),flight&&creativeFlight(p),flight&&falling(p),p.fallDistance,p.isAlive());observation.set(o);
            if(!o.alive()&&deathAnchor==null){
                if(respawnStep!=null)throw new IllegalStateException("Player died during respawn relocation");
                var previous=lastAlive;
                if(previous==null){if(ready||!serverSurface.containsFeet(m.x(),m.z(),.31))throw new IllegalStateException("Death has no owned pose");previous=o;}
                if(++lifecycleEpoch>10_000_000)throw new IllegalStateException("Respawn epoch exhausted");deathAnchor=previous;
            }
            var transition=respawnStep;
            if(transition!=null){
                if(!o.alive()||System.nanoTime()-transition.at()>10_000_000_000L)throw new IllegalStateException("Respawn acknowledgment deadline");
                if(respawnAcknowledged.get()==transition.epoch()&&clientRespawns==serverRespawns){respawnStep=null;deathAnchor=null;lastAlive=o;}
            }
            if(o.alive()&&deathAnchor==null&&respawnStep==null)lastAlive=o;
            if(resumeFallRestored&&!resumeFallLanded){
                resumeFallDistanceMax=Math.max(resumeFallDistanceMax,p.fallDistance);
                if(o.grounded()){resumeFallLandingHealth=p.getHealth();resumeFallLandingAge=p.age;resumeFallLanded=true;}
            }
            if(ready&&o.flying()){serverFlightTicks++;maxServerAltitude=Math.max(maxServerAltitude,m.y()-anchor.y());}
            if(o.alive()&&o.grounded()&&serverSurface.containsFeet(m.x(),m.z(),.31))lastGrounded.set(o);
            if(ready&&!closing)publish(o);
        }catch(Exception e){failure.compareAndSet(null,"Gameplay server observation: "+e);}
    }
    private void publish(Observation o){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_pose_v1");j.addProperty("run",identity.run());j.addProperty("world_id",save.id().toString());
        j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("patch_run",surface.run());j.addProperty("patch_sha256",surface.sha256());
        j.addProperty("seq",o.seq());j.addProperty("utc_ms",o.utc());j.addProperty("source_ms",(o.at()-born)/1_000_000);
        GameplayBoundary.Motion published=o.motion();var transition=respawnStep;var dead=deathAnchor;
        if(transition!=null&&deathAcknowledged.get()==transition.epoch()){
            j.addProperty("lifecycle","respawn");j.addProperty("respawn_epoch",transition.epoch());j.add("respawn_from",nativePosition(transition.from()));published=transition.target();
        }else if(dead!=null){j.addProperty("lifecycle","dead");j.addProperty("respawn_epoch",lifecycleEpoch);published=dead.motion();}
        if(Boolean.getBoolean("minecome.gameplayWorldBlocks")){
            j.addProperty("perspective_request",dev.minecome.hud.GameplaySession.requestedPerspective());
            if(blocks==null)throw new IllegalStateException("WorldBlocks camera collision owner missing");
            j.add("camera_collision",blocks.cameraCollision(server,(ServerPlayerEntity)serverPlayer).json(serverSurface));
        }
        j.add("position",nativePosition(published));files.pose(j);
    }
    private Vec3d nativeVector(GameplayBoundary.Motion motion){return new Vec3d(surface.centerX()+motion.x(),surface.centerY()-motion.z(),surface.centerZ()+motion.y()-GroundPatch.ANCHOR_Y);}
    private JsonObject nativePosition(GameplayBoundary.Motion motion){var v=nativeVector(motion);var p=new JsonObject();p.addProperty("x",v.x);p.addProperty("y",v.y);p.addProperty("z",v.z);return p;}
    private GameplayObservationLease.Reading<Observation> readObservation(){return GameplayObservationLease.read(observation::get,Observation::at,System::nanoTime);}
    private Observation fresh(GameplayObservationLease.Reading<Observation> reading){var o=reading.observation();return reading.fresh()&&o.world()==serverWorld&&o.player()==serverPlayer?o:null;}
    private void recordSourcePause(long tickAt,boolean viewRejected,boolean serverRejected,GameplayObservationLease.Reading<Observation> reading){
        sourcePauses++;boolean held=keys.heldInput();if(held)heldSourcePauses++;
        var j=new JsonObject();j.addProperty("utc_ms",System.currentTimeMillis());j.addProperty("tick_monotonic_ns",tickAt);
        j.addProperty("held_input",held);j.addProperty("view_rejected",viewRejected);j.addProperty("server_rejected",serverRejected);
        j.addProperty("server_checked_at_ns",reading.checkedAt());j.addProperty("server_max_age_ms",GameplayObservationLease.MAX_AGE_NS/1_000_000);
        var o=reading.observation();j.addProperty("server_sample_present",o!=null);
        if(o!=null){j.addProperty("server_sequence",o.seq());j.addProperty("server_age_ms",(reading.checkedAt()-o.at())/1_000_000.0);j.addProperty("server_identity_matches",o.world()==serverWorld&&o.player()==serverPlayer);}
        // The rejection flags above retain the exact decision; reader diagnostics
        // are a subsequent snapshot and may already show a newer native sample.
        j.add("view_reader",views.diagnostics(System.currentTimeMillis(),System.nanoTime()));
        lastSourcePause=j;if(held)lastHeldSourcePause=j;
    }
    private void requireClient(MinecraftClient c){if(c.world!=clientWorld||c.player!=clientPlayer||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Gameplay client world/player changed");}
    private void requireServer(MinecraftServer s,ServerPlayerEntity p){
        if(s!=server||p==null||p.getWorld()!=serverWorld||!GroundCollision.matches(s.getOverworld(),serverSurface,true))throw new IllegalStateException("Gameplay server/player ownership changed");
        if(serverPlayer==null)serverPlayer=p;else if(serverPlayer!=p)throw new IllegalStateException("Gameplay server player changed");
    }
    private static GameplayBoundary.Motion motion(Entity e){var p=e.getPos();var v=e.getVelocity();return new GameplayBoundary.Motion(p.x,p.y,p.z,v.x,v.y,v.z,e.isOnGround());}
    private static boolean creativeFlight(net.minecraft.entity.player.PlayerEntity p){return p.isCreative()&&p.getAbilities().allowFlying&&p.getAbilities().flying&&!p.isFallFlying()&&!p.hasVehicle();}
    private static boolean falling(net.minecraft.entity.player.PlayerEntity p){return !p.isOnGround()&&!p.getAbilities().flying&&!p.isFallFlying()&&!p.hasVehicle()&&!p.isSpectator()&&p.isAlive();}
    /** A UI/lease handoff cancels flight inertia, never position or vanilla abilities. */
    private void stopFlightDrift(MinecraftClient c){if(flight&&c.player!=null&&c.player==clientPlayer&&creativeFlight(c.player))c.player.setVelocity(Vec3d.ZERO);}
    private boolean grounded(GameplayBoundary.Motion m,BlockView world){var s=world==serverWorld?serverSurface:surface;return m.ground()&&s.containsFeet(m.x(),m.z(),.3)&&Math.abs(m.y()-(blocks==null?s.groundForFeet(m.x(),m.z(),.3):blocks.groundForFeet(world,m.x(),m.y(),m.z(),.3)))<.15;}
    private static double distance(GameplayBoundary.Motion a,GameplayBoundary.Motion b){return Math.sqrt(Math.pow(a.x()-b.x(),2)+Math.pow(a.y()-b.y(),2)+Math.pow(a.z()-b.z(),2));}
    private boolean allAir(BlockView w){return allAir(w,w==serverWorld?serverSurface:surface);}
    private boolean allAir(BlockView w,GroundSurface s){for(var c:s.cells()){var p=new BlockPos(c.x(),c.y(),c.z());if(blocks!=null?!blocks.terrainCellAllowed(w,p,w==serverWorld):!w.getBlockState(p).isAir())return false;}return true;}
    /** Each world installs only on its owning thread; controls wait for both and durable storage. */
    private void admitTerrain(MinecraftClient client,long now){
        if(admission==null){
            var candidate=growth.pending();if(candidate==null)return;
            if(candidate.expected()!=surface||!(surface instanceof GameplayTerrain))throw new IllegalStateException("Terrain predecessor changed");
            if(blocks!=null&&blocks.evidence(client).get("pending").getAsBoolean())return;
            suspend(client);if(blocks!=null)blocks.suspend(client);admission=candidate;admissionAt=now;admissionSubmitted=false;
            server.execute(()->{try{
                if(closing)return;var p=server.getPlayerManager().getPlayer(playerId);requireServer(server,p);
                if(serverSurface!=candidate.expected()||!allAir(server.getOverworld(),candidate.next()))throw new IllegalStateException("New server terrain occupied or predecessor changed");
                for(var cell:candidate.next().cells())if(!server.getOverworld().isChunkLoaded(new BlockPos(cell.x(),cell.y(),cell.z())))throw new IllegalStateException("Terrain chunk not loaded");
                if(!GroundCollision.replace(server.getOverworld(),candidate.expected(),candidate.next(),true))throw new IllegalStateException("Server terrain handoff failed");
                serverSurface=candidate.next();serverAdmission=candidate;
            }catch(Exception e){failure.compareAndSet(null,"Terrain server handoff: "+e);}});
        }
        if(now-admissionAt>5_000_000_000L)throw new IllegalStateException("Terrain handoff deadline");
        if(!admissionSubmitted&&serverAdmission==admission){
            if(!allAir(client.world,admission.next())||!GroundCollision.replace(client.world,admission.expected(),admission.next(),false))throw new IllegalStateException("Client terrain handoff failed");
            surface=admission.next();boundary=new GameplayBoundary(surface);if(blocks!=null)blocks.terrain(surface);
            growth.applied(admission);admissionSubmitted=true;
        }
        if(admissionSubmitted&&growth.persistedGeneration()==admission.next().generation()){
            admissions++;admission=null;serverAdmission=null;admissionSubmitted=false;paused="none";
        }
    }
    private void release(MinecraftClient c){if(!controlsOwned)return;c.options.forwardKey.setPressed(false);c.options.backKey.setPressed(false);c.options.leftKey.setPressed(false);c.options.rightKey.setPressed(false);c.options.jumpKey.setPressed(false);if(flight){c.options.sneakKey.setPressed(false);c.options.sprintKey.setPressed(false);}controlsOwned=false;}
    public void close(MinecraftClient client){
        if(closing)return;closing=true;authority=false;keys.close();release(client);stopFlightDrift(client);views.close();if(growth!=null)growth.close();
        clientQueries.accumulateAndGet(GroundCollision.queries(false),Math::max);serverQueries.accumulateAndGet(GroundCollision.queries(true),Math::max);
        clientReleased=!clientInstalled||GroundCollision.clear((BlockView)clientWorld,surface.run(),surface.sha256(),false);
        if(!serverInstalled.get()){serverReleased.set(true);files.close(null);}
        else server.execute(()->{
            GameplayTerrainBinding.Position position=null;
            try{
                // Capture final abilities on their owning thread. A mode-change
                // packet can precede the next periodic observation by one tick.
                if(ready&&failure.get()==null&&deathAnchor==null&&respawnStep==null){
                    var p=server.getPlayerManager().getPlayer(playerId);requireServer(server,p);var m=motion(p);
                    var current=new Observation(p.getWorld(),p,++sequence,System.nanoTime(),System.currentTimeMillis(),m,p.getYaw(),p.getPitch(),grounded(m,(BlockView)serverWorld),flight&&creativeFlight(p),flight&&falling(p),p.fallDistance,p.isAlive());observation.set(current);
                    var stable=lastGrounded.get();
                    if(current.grounded())stable=current;
                    else if(flight&&(current.flying()||current.falling())&&serverSurface.containsFeet(m.x(),m.z(),.31)&&m.y()>=serverSurface.groundForFeet(m.x(),m.z(),.3)&&m.y()<=GameplayBoundary.FLIGHT_MAX_Y)stable=current;
                    if(stable!=null&&System.nanoTime()-stable.at()<=250_000_000L)position=new GameplayTerrainBinding.Position(stable.motion().x(),stable.motion().y(),stable.motion().z(),stable.yaw(),stable.pitch(),stable.flying()&&!stable.grounded(),stable.falling()&&!stable.grounded(),stable.falling()&&!stable.grounded()?stable.fallDistance():0);
                }
            }catch(Exception e){failure.compareAndSet(null,"Gameplay final checkpoint: "+e);}
            finally{
                serverQueries.accumulateAndGet(GroundCollision.queries(true),Math::max);
                // Keep the captured floor until vanilla saves and closes the world.
                // Clearing here lets players and drops fall during writer shutdown.
                files.close(failure.get()==null?position:null);
            }
        });
    }
    /** Fabric SERVER_STOPPED runs at MinecraftServer.shutdown TAIL, after final save/world close. */
    public void serverStopped(MinecraftServer source){
        if(source!=server||!serverInstalled.get())return;
        if(!source.isOnThread())throw new IllegalStateException("Gameplay collision disposal requires its server thread");
        if(serverReleased.get())return;
        serverQueries.accumulateAndGet(GroundCollision.queries(true),Math::max);
        if(!GroundCollision.clear((BlockView)serverWorld,serverSurface.run(),serverSurface.sha256(),true))failure.compareAndSet(null,"Gameplay server collision cleanup mismatch");
        else serverReleased.set(true);
    }
    /** Session failures must not replace the last good persistent checkpoint. */
    public void abort(MinecraftClient client,String reason){failure.compareAndSet(null,reason);close(client);}
    /** Writers and controls have drained; vanilla disconnect can now save the supported world. */
    public boolean shutdownPrepared(){return closing&&!controlsOwned&&clientReleased&&files.finished()&&files.failure()==null&&(growth==null||growth.finished()&&growth.failure()==null);}
    public boolean cleanupComplete(){return shutdownPrepared()&&serverReleased.get();}
    public JsonObject evidence(MinecraftClient client){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_movement_v1");j.addProperty("run",identity.run());j.addProperty("world_id",save.id().toString());
        j.addProperty("patch_run",surface.run());j.addProperty("patch_sha256",surface.sha256());j.addProperty("fixture",fixture);j.addProperty("ready",ready);j.addProperty("first_attachment",resume==null);j.addProperty("resume_position_restored",resume!=null&&teleported.get());
        j.addProperty("movement_events",events);j.addProperty("held_ticks",heldTicks);j.addProperty("client_walk",clientWalk);j.addProperty("server_walk",serverWalk);j.addProperty("boundary_pauses",boundaryPauses);j.addProperty("paused",paused);
        j.addProperty("respawn_epoch",lifecycleEpoch);j.addProperty("death_pending",deathPending());j.addProperty("respawn_pending",respawnPending());j.addProperty("server_respawns",serverRespawns);j.addProperty("client_respawns",clientRespawns);j.addProperty("death_acknowledged",deathAcknowledged.get());j.addProperty("respawn_acknowledged",respawnAcknowledged.get());
        j.addProperty("source_pauses",sourcePauses);j.addProperty("held_source_pauses",heldSourcePauses);if(lastSourcePause!=null)j.add("last_source_pause",lastSourcePause.deepCopy());if(lastHeldSourcePause!=null)j.add("last_held_source_pause",lastHeldSourcePause.deepCopy());
        j.addProperty("flight_enabled",flight);j.addProperty("client_flying",client.player!=null&&client.player==clientPlayer&&creativeFlight(client.player));j.addProperty("server_flying",observation.get()!=null&&observation.get().flying());j.addProperty("client_flight_ticks",clientFlightTicks);j.addProperty("server_flight_ticks",serverFlightTicks);j.addProperty("max_client_altitude",maxClientAltitude);j.addProperty("max_server_altitude",maxServerAltitude);
        if(resume!=null&&resume.falling()){j.addProperty("resume_fall_restored",resumeFallRestored);j.addProperty("resume_fall_distance_max",resumeFallDistanceMax);j.addProperty("resume_fall_landed",resumeFallLanded);j.addProperty("resume_fall_landing_health",resumeFallLandingHealth);j.addProperty("resume_fall_landing_age",resumeFallLandingAge);}
        j.addProperty("client_queries",Math.max(clientQueries.get(),GroundCollision.queries(false)));j.addProperty("server_queries",Math.max(serverQueries.get(),GroundCollision.queries(true)));j.addProperty("pose_writes",files.writes());j.addProperty("server_observations",sequence);
        if(anchor!=null)j.add("initial_position",positionJson(anchor));
        if(client.player!=null&&client.player==clientPlayer)j.add("client_position",positionJson(motion(client.player)));
        var observed=observation.get();if(observed!=null)j.add("server_position",positionJson(observed.motion()));
        var checkpoint=binding.resume();j.addProperty("resume_checkpoint_present",checkpoint!=null);
        if(checkpoint!=null){var p=new JsonObject();p.addProperty("x",checkpoint.x());p.addProperty("y",checkpoint.y());p.addProperty("z",checkpoint.z());p.addProperty("flying",checkpoint.flying());p.addProperty("falling",checkpoint.falling());p.addProperty("fall_distance",checkpoint.fallDistance());j.add("resume_checkpoint",p);}
        j.addProperty("controls_released",!controlsOwned);j.addProperty("client_collision_released",clientReleased);j.addProperty("server_collision_released",serverReleased.get());j.addProperty("shutdown_prepared",shutdownPrepared());j.addProperty("cleanup_complete",cleanupComplete());
        j.addProperty("failure",failure.get()!=null?failure.get():files.failure());j.addProperty("blocks_written",0);
        if(surface instanceof GameplayTerrain terrain){j.addProperty("terrain_generation",terrain.generation());j.addProperty("terrain_tiles",terrain.tileCount());j.addProperty("terrain_digest",terrain.digest());j.addProperty("terrain_client_generation",terrain.generation());j.addProperty("terrain_server_generation",((GameplayTerrain)serverSurface).generation());j.addProperty("terrain_admissions",admissions);j.addProperty("terrain_failure",growth.failure());j.addProperty("terrain_transition",admission!=null);}
        j.addProperty("terrain_cells_valid",clientWorld!=null&&allAir((BlockView)clientWorld));
        boolean air=clientWorld!=null;if(air)for(var c:surface.cells())if(!((BlockView)clientWorld).getBlockState(new BlockPos(c.x(),c.y(),c.z())).isAir()){air=false;break;}
        j.addProperty("ground_cells_air",air);return j;
    }
    private static JsonObject positionJson(GameplayBoundary.Motion m){var p=new JsonObject();p.addProperty("x",m.x());p.addProperty("y",m.y());p.addProperty("z",m.z());return p;}
}
