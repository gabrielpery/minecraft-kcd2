package dev.minecome.terrain;

import com.google.gson.JsonObject;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.hud.HudMovementViewReader;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.math.*;
import net.minecraft.world.*;
import java.io.IOException;
import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.atomic.*;

/** Ongoing vanilla walking on ephemeral host collision; inventory/mode/player state stay vanilla. */
public final class GameplayMovement {
    private record Observation(Object world,Object player,long seq,long at,long utc,GameplayBoundary.Motion motion,float yaw,float pitch,boolean grounded){}
    private final GameplayWorld save;private volatile GroundSurface surface,serverSurface;
    private final GameplayTerrainBinding binding;private final GameplayTerrainBinding.Position resume;
    private final HudInputProtocol.Identity identity;private final HudMovementViewReader views;
    private final GameplayMotionFiles files;private final GameplayMovementKeys keys=new GameplayMovementKeys();
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
    private GameplayBoundary.Motion anchor;private String paused="starting";
    private GameplayBlocks blocks;
    public void blockController(GameplayBlocks controller){if(clientWorld!=null||serverInstalled.get())throw new IllegalStateException("Block controller must precede world load");blocks=controller;}
    public GameplayMovement(Path root,GameplayWorld save,Path groundFile,boolean fixture,HudInputProtocol.Identity identity,Path evidenceDirectory)throws IOException{
        this.save=save;this.fixture=fixture;this.identity=identity;binding=GameplayTerrainBinding.open(save,groundFile,fixture,Boolean.getBoolean("minecome.gameplayBlocks"),Boolean.getBoolean("minecome.gameplayExplore"));surface=binding.currentSurface();serverSurface=surface;resume=binding.resume();
        boundary=new GameplayBoundary(surface);views=new HudMovementViewReader(evidenceDirectory.resolve("host-view.json"),root.resolve("runtime/evidence"),identity,surface.run(),surface.sha256(),fixture);
        files=new GameplayMotionFiles(root,evidenceDirectory,binding);views.start();files.start();
        growth=binding.coverage()==null?null:new GameplayTerrainAdmission(evidenceDirectory,binding.coverage(),identity,save.id().toString());
    }
    public GroundSurface surface(){return surface;}
    public boolean ready(){return ready&&!closing;}
    private void check(){if(views.failure()!=null)failure.compareAndSet(null,views.failure());if(files.failure()!=null)failure.compareAndSet(null,files.failure());if(growth!=null&&growth.failure()!=null)failure.compareAndSet(null,growth.failure());if(failure.get()!=null)throw new IllegalStateException(failure.get());}
    public boolean terrainTransition(){return admission!=null;}
    public void authority(MinecraftClient client,long now,boolean fresh){
        authority=fresh&&ready()&&client.currentScreen==null&&client.getOverlay()==null&&!client.isPaused();keys.authority(now,authority);if(!authority)release(client);
    }
    public void event(MinecraftClient client,HudInputProtocol.Event event,long now){
        if(keys.event(event.kind(),event.code(),now,authority&&ready()))events++;
    }
    public void suspend(MinecraftClient client){authority=false;keys.suspend();release(client);}
    public void beforeTick(MinecraftClient client,long now){
        if(closing)return;check();if(clientWorld==null)return;requireClient(client);
        if(admission!=null){paused="terrain_admission";release(client);if(blocks!=null)blocks.suspend(client);return;}
        if(!ready()||!authority||client.currentScreen!=null||client.getOverlay()!=null||client.isPaused()){suspend(client);return;}
        var view=views.current(System.currentTimeMillis(),now);var observed=fresh(now);
        if(view==null||observed==null){paused="source_stale";suspend(client);return;}
        client.player.setYaw(view.view().yaw());client.player.setPitch(view.view().pitch());
        // Preserve vanilla abilities. Actual Creative/Elytra flight will acquire its
        // own terrain/vertical admission policy; this entry is walking only.
        if(client.player.getAbilities().flying||client.player.isFallFlying()){paused="flight_not_connected";suspend(client);return;}
        var motion=motion(client.player);
        int forward=(keys.down('W',now)?1:0)-(keys.down('S',now)?1:0),side=(keys.down('A',now)?1:0)-(keys.down('D',now)?1:0);
        if(!keys.neutral(now)&&!boundary.allows(motion,forward,side,keys.down(0x20,now),view.view().yaw(),client.player.getMovementSpeed()*1.3+.00001)){
            boundaryPauses++;paused="terrain_frontier";suspend(client);return;
        }
        paused="none";controlsOwned=true;
        client.options.forwardKey.setPressed(keys.down('W',now));client.options.backKey.setPressed(keys.down('S',now));
        client.options.leftKey.setPressed(keys.down('A',now));client.options.rightKey.setPressed(keys.down('D',now));client.options.jumpKey.setPressed(keys.down(0x20,now));
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
                    var v=views.current(System.currentTimeMillis(),System.nanoTime());float yaw=resume!=null?resume.yaw():v==null?p.getYaw():v.view().yaw();
                    float pitch=resume!=null?resume.pitch():v==null?p.getPitch():v.view().pitch();
                    double x=resume==null?0:resume.x(),y=resume==null?surface.groundForFeet(0,0,.3)+.05:resume.y(),z=resume==null?0:resume.z();
                    p.teleport(server.getOverworld(),x,y,z,yaw,pitch);p.setVelocity(Vec3d.ZERO);p.fallDistance=0;teleported.set(true);
                }catch(Exception e){failure.set("Gameplay attachment: "+e);}
            });return;
        }
        var o=fresh(now);var current=motion(client.player);
        if(!ready){
            boolean stable=teleported.get()&&o!=null&&grounded(current,(BlockView)clientWorld)&&o.grounded()&&distance(current,o.motion())<.01&&views.current(System.currentTimeMillis(),now)!=null;
            if(!stable)stableAt=0;else if(stableAt==0)stableAt=now;else if(now-stableAt>=250_000_000L){
                ready=true;anchor=o.motion();var proof=evidence(client);proof.addProperty("ready",true);files.ready(proof);
            }
            if(now-setupAt>12_000_000_000L)throw new IllegalStateException("Gameplay attachment did not settle");return;
        }
        if(!GroundCollision.matches(client.world,surface,false)||!allAir(client.world))throw new IllegalStateException("Gameplay terrain ownership changed");
        if(growth!=null)admitTerrain(client,now);
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
            var m=motion(p);var o=new Observation(p.getWorld(),p,++sequence,System.nanoTime(),System.currentTimeMillis(),m,p.getYaw(),p.getPitch(),grounded(m,(BlockView)serverWorld));observation.set(o);
            if(o.grounded()&&serverSurface.containsFeet(m.x(),m.z(),.31))lastGrounded.set(o);
            if(ready&&!closing)publish(o);
        }catch(Exception e){failure.compareAndSet(null,"Gameplay server observation: "+e);}
    }
    private void publish(Observation o){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_pose_v1");j.addProperty("run",identity.run());j.addProperty("world_id",save.id().toString());
        j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("patch_run",surface.run());j.addProperty("patch_sha256",surface.sha256());
        j.addProperty("seq",o.seq());j.addProperty("utc_ms",o.utc());j.addProperty("source_ms",(o.at()-born)/1_000_000);
        var p=new JsonObject();p.addProperty("x",surface.centerX()+o.motion().x());p.addProperty("y",surface.centerY()-o.motion().z());p.addProperty("z",surface.centerZ()+o.motion().y()-GroundPatch.ANCHOR_Y);j.add("position",p);files.pose(j);
    }
    private Observation fresh(long now){var o=observation.get();return o!=null&&o.world()==serverWorld&&o.player()==serverPlayer&&now>=o.at()&&now-o.at()<=250_000_000L?o:null;}
    private void requireClient(MinecraftClient c){if(c.world!=clientWorld||c.player!=clientPlayer||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Gameplay client world/player changed");}
    private void requireServer(MinecraftServer s,ServerPlayerEntity p){
        if(s!=server||p==null||p.getWorld()!=serverWorld||!GroundCollision.matches(s.getOverworld(),serverSurface,true))throw new IllegalStateException("Gameplay server/player ownership changed");
        if(serverPlayer==null)serverPlayer=p;else if(serverPlayer!=p)throw new IllegalStateException("Gameplay server player changed");
    }
    private static GameplayBoundary.Motion motion(Entity e){var p=e.getPos();var v=e.getVelocity();return new GameplayBoundary.Motion(p.x,p.y,p.z,v.x,v.y,v.z,e.isOnGround());}
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
            release(client);if(blocks!=null)blocks.suspend(client);admission=candidate;admissionAt=now;admissionSubmitted=false;
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
    private void release(MinecraftClient c){if(!controlsOwned)return;c.options.forwardKey.setPressed(false);c.options.backKey.setPressed(false);c.options.leftKey.setPressed(false);c.options.rightKey.setPressed(false);c.options.jumpKey.setPressed(false);controlsOwned=false;}
    public void close(MinecraftClient client){
        if(closing)return;closing=true;authority=false;keys.close();release(client);views.close();if(growth!=null)growth.close();
        clientQueries.accumulateAndGet(GroundCollision.queries(false),Math::max);serverQueries.accumulateAndGet(GroundCollision.queries(true),Math::max);
        clientReleased=!clientInstalled||GroundCollision.clear((BlockView)clientWorld,surface.run(),surface.sha256(),false);
        var stable=lastGrounded.get();GameplayTerrainBinding.Position position=null;
        if(ready&&failure.get()==null&&stable!=null&&System.nanoTime()-stable.at()<=250_000_000L)position=new GameplayTerrainBinding.Position(stable.motion().x(),stable.motion().y(),stable.motion().z(),stable.yaw(),stable.pitch());
        files.close(position);
        if(!serverInstalled.get())serverReleased.set(true);
        else server.execute(()->{serverQueries.accumulateAndGet(GroundCollision.queries(true),Math::max);if(!GroundCollision.clear((BlockView)serverWorld,serverSurface.run(),serverSurface.sha256(),true))failure.compareAndSet(null,"Gameplay server collision cleanup mismatch");else serverReleased.set(true);});
    }
    /** Session failures must not replace the last good persistent checkpoint. */
    public void abort(MinecraftClient client,String reason){failure.compareAndSet(null,reason);close(client);}
    public boolean cleanupComplete(){return closing&&clientReleased&&serverReleased.get()&&files.finished()&&files.failure()==null&&(growth==null||growth.finished()&&growth.failure()==null);}
    public JsonObject evidence(MinecraftClient client){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_movement_v1");j.addProperty("run",identity.run());j.addProperty("world_id",save.id().toString());
        j.addProperty("patch_run",surface.run());j.addProperty("patch_sha256",surface.sha256());j.addProperty("fixture",fixture);j.addProperty("ready",ready);j.addProperty("first_attachment",resume==null);j.addProperty("resume_position_restored",resume!=null&&teleported.get());
        j.addProperty("movement_events",events);j.addProperty("held_ticks",heldTicks);j.addProperty("client_walk",clientWalk);j.addProperty("server_walk",serverWalk);j.addProperty("boundary_pauses",boundaryPauses);j.addProperty("paused",paused);
        j.addProperty("client_queries",Math.max(clientQueries.get(),GroundCollision.queries(false)));j.addProperty("server_queries",Math.max(serverQueries.get(),GroundCollision.queries(true)));j.addProperty("pose_writes",files.writes());j.addProperty("server_observations",sequence);
        if(anchor!=null)j.add("initial_position",positionJson(anchor));
        if(client.player!=null&&client.player==clientPlayer)j.add("client_position",positionJson(motion(client.player)));
        var observed=observation.get();if(observed!=null)j.add("server_position",positionJson(observed.motion()));
        var checkpoint=binding.resume();j.addProperty("resume_checkpoint_present",checkpoint!=null);
        if(checkpoint!=null){var p=new JsonObject();p.addProperty("x",checkpoint.x());p.addProperty("y",checkpoint.y());p.addProperty("z",checkpoint.z());j.add("resume_checkpoint",p);}
        j.addProperty("controls_released",!controlsOwned);j.addProperty("client_collision_released",clientReleased);j.addProperty("server_collision_released",serverReleased.get());j.addProperty("cleanup_complete",cleanupComplete());
        j.addProperty("failure",failure.get()!=null?failure.get():files.failure());j.addProperty("blocks_written",0);
        if(surface instanceof GameplayTerrain terrain){j.addProperty("terrain_generation",terrain.generation());j.addProperty("terrain_tiles",terrain.tileCount());j.addProperty("terrain_digest",terrain.digest());j.addProperty("terrain_client_generation",terrain.generation());j.addProperty("terrain_server_generation",((GameplayTerrain)serverSurface).generation());j.addProperty("terrain_admissions",admissions);j.addProperty("terrain_failure",growth.failure());j.addProperty("terrain_transition",admission!=null);}
        j.addProperty("terrain_cells_valid",clientWorld!=null&&allAir((BlockView)clientWorld));
        boolean air=clientWorld!=null;if(air)for(var c:surface.cells())if(!((BlockView)clientWorld).getBlockState(new BlockPos(c.x(),c.y(),c.z())).isAir()){air=false;break;}
        j.addProperty("ground_cells_air",air);return j;
    }
    private static JsonObject positionJson(GameplayBoundary.Motion m){var p=new JsonObject();p.addProperty("x",m.x());p.addProperty("y",m.y());p.addProperty("z",m.z());return p;}
}
