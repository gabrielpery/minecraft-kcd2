package dev.minecome.gameplay;

import com.google.gson.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.*;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.entity.damage.DamageSource;
import net.minecraft.entity.TntEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.entity.projectile.PersistentProjectileEntity;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.Hand;
import net.minecraft.util.hit.HitResult;
import net.minecraft.util.math.*;
import net.minecraft.world.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Real vanilla primary melee and reciprocal native melee damage. The host
 * snapshot creates unsaved invisible LivingEntity targets, never copied NPC AI.
 * All entity calls stay on the client/integrated server threads; the daemon only
 * moves bounded immutable JSON. Bow trajectories use a separate native contract.
 */
public final class GameplayCombat implements GameplayActorEntity.DamageSink {
    private record Plan(long id,int token,int entityId,GameplayBlocks.Aim aim,int slot,String weapon,long at){}
    private record Selection(GameplayActorEntity entity,Vec3d point,double distance,long sourceSeq){}
    private record Accepted(long planId,int token,long sourceSeq,Vec3d point){}
    private record Hit(long seq,long sourceSeq,int token,float damage,String weapon,Vec3d origin,Vec3d target){}
    private record Rejection(String reason,long planId,int token,long utc,long planAgeMs,long aimAgeMs,long hostAgeMs,long hostSequence,int proxies,Vec3d rayOrigin,Vec3d rayDirection,double obstruction,Box targetBox,boolean intersects){}
    private final HudInputProtocol.Identity identity;private final GameplayWorld save;private volatile GroundSurface surface;private final Path hostFile,guestFile,temporary;private final boolean standalone;
    private final AtomicReference<Plan> intent=new AtomicReference<>();private final AtomicReference<Hit> outgoing=new AtomicReference<>();private final AtomicReference<String> failure=new AtomicReference<>();
    private final Map<Integer,GameplayActorEntity> proxies=new HashMap<>();
    private final GameplayProjectiles projectiles;
    private final GameplayBlasts blasts;
    /** Written only by the server's synchronous damage call, never the file/client threads. */
    private Accepted accepted;
    private volatile GameplayCombatProtocol.Snapshot snapshot;
    private volatile MinecraftServer server;private volatile UUID playerId;private Object clientWorld,clientPlayer;private volatile ServerPlayerEntity serverPlayer;
    private volatile boolean closing,workerClosed,serverClosed,ready;private boolean enabled,leftConsumed;private GameplayBlocks.Aim aim;private double blockingDistance=-1;
    private volatile long admitted,handled,dispatched,hostAck,hurtAck,hits,hurts,serverRespawns,clientRespawns,serverRejected;private long planSeq;private final AtomicInteger rejected=new AtomicInteger();private int attacks;
    private volatile Rejection lastRejection;
    private volatile int proxyCount;private volatile double serverDamage,playerDamage;private volatile long lastHostAt;
    public GameplayCombat(HudInputProtocol.Identity identity,GameplayWorld save,GroundSurface surface,Path directory,boolean standalone)throws IOException{
        this.identity=identity;this.save=save;this.surface=surface;this.standalone=standalone;
        save.verifyOwnership();var path=directory.toRealPath();hostFile=path.resolve("host-combat.json");guestFile=path.resolve("combat.json");temporary=path.resolve("combat.json.tmp");
        if(Files.exists(guestFile,LinkOption.NOFOLLOW_LINKS)||Files.exists(temporary,LinkOption.NOFOLLOW_LINKS))throw new IOException("Combat publication already exists");
        projectiles=new GameplayProjectiles(this,identity,save,surface,path,standalone);
        blasts=new GameplayBlasts(this,identity,save,surface,path,standalone);
        var worker=new Thread(this::files,"MineComeCombatFiles");worker.setDaemon(true);worker.start();
    }
    public List<GameplayCombatProtocol.Actor> knownActors(){var s=snapshot;return s==null?List.of():s.actors();}
    public void terrain(GroundSurface next){
        var before=surface;
        if(!closing&&next==before)return;
        if(closing||next==null||!before.run().equals(next.run())||!before.sha256().equals(next.sha256())||before.centerX()!=next.centerX()||before.centerY()!=next.centerY()||before.centerZ()!=next.centerZ()||
                !(before instanceof GameplayTerrain old)||!(next instanceof GameplayTerrain grown)||(grown!=old&&!grown.isSuccessorOf(old)))throw new IllegalArgumentException("Combat terrain identity/coverage changed");
        surface=next;projectiles.terrain(next);blasts.terrain(next);
    }
    public boolean ready(){return ready&&!closing&&failure.get()==null;}
    public void tick(MinecraftClient c,boolean allow,GameplayBlocks.Aim ray,double blockDistance){
        if(closing)return;check();if(c.player==null||c.world==null||c.getServer()==null||c.interactionManager==null)return;
        if(clientPlayer==null){if(!c.isOnThread()||!c.isIntegratedServerRunning()||c.world.getRegistryKey()!=World.OVERWORLD)throw new IllegalStateException("Combat requires owned integrated overworld");clientWorld=c.world;clientPlayer=c.player;playerId=c.player.getUuid();server=c.getServer();}
        requireClient(c);long now=System.nanoTime();var s=snapshot;
        if(lastHostAt>0&&now-lastHostAt>2_000_000_000L)throw new IllegalStateException("Combat host snapshot expired");
        ready=serverPlayer!=null&&s!=null&&s.fresh(System.currentTimeMillis());enabled=allow&&ready&&c.player.isAlive()&&c.currentScreen==null&&c.getOverlay()==null&&!c.isPaused();
        projectiles.client(c,ready());
        blasts.client(c,ready());
        aim=ray;blockingDistance=blockDistance;
        if(!enabled){suspend(c);return;}
        var p=intent.get();if(p!=null){
            if(handled==p.id()){intent.compareAndSet(p,null);dispatched=0;}
            else if(now-p.at()>750_000_000L){reject("packet_not_processed",p);intent.compareAndSet(p,null);dispatched=0;rejected.incrementAndGet();}
        }
    }
    /** A primary actor hit consumes only its own down/up pair, leaving block mining untouched. */
    public boolean event(MinecraftClient c,HudInputProtocol.Event event){
        if(event.code()!=0||(event.kind()!=7&&event.kind()!=8))return false;
        if(event.kind()==8){boolean consumed=leftConsumed;leftConsumed=false;return consumed;}
        if(!enabled||!ready()||c.player==null||c.world==null||c.interactionManager==null||c.currentScreen!=null||c.getOverlay()!=null||c.isPaused())return false;
        requireClient(c);
        var selected=select(c.world,c.player,aim,blockingDistance);if(selected==null)return false;
        leftConsumed=true;
        if(intent.get()!=null||outgoing.get()!=null){rejected.incrementAndGet();return true;}
        var p=new Plan(++planSeq,selected.entity().token(),selected.entity().getId(),aim,c.player.getInventory().selectedSlot,Registries.ITEM.getId(c.player.getMainHandStack().getItem()).toString(),System.nanoTime());
        intent.set(p);dispatched=p.id();
        // Normal vanilla attack packet immediately after client selection. The
        // server's synchronous damage gate below performs every authority check;
        // no additional round trip consumes the original native aim's lifetime.
        c.interactionManager.attackEntity(c.player,selected.entity());c.player.swingHand(Hand.MAIN_HAND);attacks++;return true;
    }
    public double aimedTargetDistance(MinecraftClient c,GameplayBlocks.Aim ray){if(c.world==null||c.player==null)return -1;var s=select(c.world,c.player,ray,-1);return s==null?-1:s.distance();}
    private Selection select(World world,PlayerEntity player,GameplayBlocks.Aim ray,double blockDistance){
        var s=snapshot;if(s==null||!s.fresh(System.currentTimeMillis())||ray==null||!ray.obstructionKnown()||!ray.fresh(System.currentTimeMillis(),System.nanoTime())||ray.origin().distanceTo(player.getEyePos())>.35)return null;
        double range=Math.min(ray.range(),player.getEntityInteractionRange());var end=ray.origin().add(ray.direction().multiply(range));
        double limit=blockDistance>=0?Math.min(range,blockDistance):range;
        var worldHit=world.raycast(new RaycastContext(ray.origin(),end,RaycastContext.ShapeType.OUTLINE,RaycastContext.FluidHandling.NONE,player));
        if(worldHit.getType()==HitResult.Type.BLOCK)limit=Math.min(limit,worldHit.getPos().distanceTo(ray.origin()));
        Selection best=null;
        for(var entity:world.getEntitiesByClass(GameplayActorEntity.class,new Box(ray.origin(),end).expand(4),e->!e.isRemoved())){
            var actor=find(s,entity.token());if(actor==null||!actor.alive())continue;
            Vec3d expected=position(actor);if(entity.getPos().squaredDistanceTo(expected)>.09)continue;
            var hit=entity.getBoundingBox().raycast(ray.origin(),end);if(hit.isEmpty())continue;double distance=hit.get().distanceTo(ray.origin());
            if(distance>=limit-.001||ray.obstructionDistance()>=0&&ray.obstructionDistance()<distance-.08)continue;
            // Third-person camera must see the actual contact point as well.
            var sight=world.raycast(new RaycastContext(ray.cameraOrigin(),hit.get(),RaycastContext.ShapeType.OUTLINE,RaycastContext.FluidHandling.NONE,player));
            if(sight.getType()==HitResult.Type.BLOCK&&sight.getPos().distanceTo(hit.get())>.05)continue;
            if(best==null||distance<best.distance())best=new Selection(entity,hit.get(),distance,s.seq());
        }
        return best;
    }
    public void observe(MinecraftServer source){
        if(server==null||playerId==null)return;
        try{
            if(source!=server||!source.isOnThread()||!save.saveName().equals(source.getSaveProperties().getLevelName()))throw new IllegalStateException("Combat server ownership changed");
            if(closing){projectiles.closeServer();blasts.closeServer();removeAll();serverClosed=true;return;}
            check();var player=source.getPlayerManager().getPlayer(playerId);if(player==null||player.getServerWorld()!=source.getOverworld())throw new IllegalStateException("Combat player/world unavailable");
            if(serverPlayer==null)serverPlayer=player;if(serverPlayer!=player)throw new IllegalStateException("Unreconciled combat player replacement");
            projectiles.observe(source,player);
            blasts.observe(source,player);
            var s=snapshot;if(s==null||!s.fresh(System.currentTimeMillis())){removeAll();admitted=0;return;}
            if(s.hitAck()<hostAck||s.hitAck()>hits)throw new IllegalStateException("Combat hit acknowledgment replay/future");
            var out=outgoing.get();if(out!=null&&s.hitAck()==out.seq()){outgoing.compareAndSet(out,null);hostAck=s.hitAck();}
            else if(s.hitAck()!=hostAck)throw new IllegalStateException("Combat hit acknowledgment identity differs");
            var tokens=new HashSet<Integer>();
            for(var a:s.actors()){
                // Retain a dead attacker's adapter until its already-observed
                // native hit is acknowledged, including simultaneous trades.
                if(!a.alive()&&s.hurts().stream().noneMatch(h->h.seq()>hurtAck&&h.attackerToken()==a.token()))continue;Vec3d point=position(a);
                if(point.distanceTo(player.getPos())>64||!surface.containsFeet(point.x,point.z,.001))continue;
                tokens.add(a.token());var proxy=proxies.get(a.token());if(proxy==null){proxy=new GameplayActorEntity(GameplayActorEntity.TYPE,source.getOverworld());proxy.bind(a.token(),a.width(),a.height(),this);proxy.refreshPositionAndAngles(point.x,point.y,point.z,0,0);if(!source.getOverworld().spawnEntity(proxy))throw new IllegalStateException("Combat proxy spawn refused");proxies.put(a.token(),proxy);}
                else{proxy.bind(a.token(),a.width(),a.height(),this);proxy.setPosition(point);}
            }
            for(var token:new ArrayList<>(proxies.keySet()))if(!tokens.contains(token)&&!projectiles.retains(token)&&!blasts.retains(token)){proxies.remove(token).discard();}proxyCount=proxies.size();
            for(var hurt:s.hurts()){
                if(hurt.seq()<=hurtAck)continue;if(hurt.seq()!=hurtAck+1)throw new IllegalStateException("Combat incoming damage gap");
                var attacker=proxies.get(hurt.attackerToken());if(attacker==null||attacker.getPos().distanceTo(player.getPos())>8)throw new IllegalStateException("Unowned/distant native melee attacker");
                float before=player.getHealth();player.damage(source.getOverworld().getDamageSources().mobAttack(attacker),hurt.damage());playerDamage+=Math.max(0,before-player.getHealth());hurtAck=hurt.seq();hurts++;
            }
        }catch(Exception e){failure.compareAndSet(null,e.toString());removeAll();}
    }
    @Override public boolean accepts(GameplayActorEntity target,DamageSource source,float amount){
        accepted=null;
        if(source.getSource() instanceof PersistentProjectileEntity)return projectiles.accepts(target,source,amount);
        if(source.getSource() instanceof TntEntity)return blasts.accepts(target,source,amount);
        var p=intent.get();var s=snapshot;
        if(server==null||!server.isOnThread()||p==null||source.getAttacker()!=serverPlayer||source.getSource()!=serverPlayer||target.token()!=p.token())return false;
        if(closing||failure.get()!=null)return reject("controller_unavailable",p);
        if(serverPlayer==null||!serverPlayer.isAlive()||server.getPlayerManager().getPlayer(playerId)!=serverPlayer||serverPlayer.getWorld()!=server.getOverworld())return reject("player_unavailable",p);
        if(serverPlayer.currentScreenHandler!=serverPlayer.playerScreenHandler)return reject("screen_open",p);
        if(dispatched!=p.id()||target!=proxies.get(p.token())||target.getId()!=p.entityId())return reject("target_or_dispatch_changed",p);
        if(outgoing.get()!=null)return reject("hit_ack_pending",p);
        if(s==null||!s.fresh(System.currentTimeMillis()))return reject("host_snapshot_expired",p);
        if(System.nanoTime()-p.at()>750_000_000L)return reject("plan_expired",p);
        if(!sameStack(serverPlayer,p))return reject("held_stack_changed",p);
        if(!p.aim().fresh(System.currentTimeMillis(),System.nanoTime()))return reject("aim_expired",p);
        if(!p.aim().obstructionKnown())return reject("native_obstruction_unknown",p);
        if(p.aim().origin().distanceTo(serverPlayer.getEyePos())>.35)return reject("eye_position_changed",p);
        var selected=select(server.getOverworld(),serverPlayer,p.aim(),-1);
        if(selected==null)return reject("ray_target_rejected",p);
        if(selected.entity()!=target)return reject("nearest_actor_changed",p);
        admitted=p.id();
        accepted=new Accepted(p.id(),target.token(),selected.sourceSeq(),selected.point());
        return true;
    }
    @Override public void applied(GameplayActorEntity target,DamageSource source,float amount){
        if(source.getSource() instanceof PersistentProjectileEntity){projectiles.applied(target,source,amount);return;}
        if(source.getSource() instanceof TntEntity){blasts.applied(target,source,amount);return;}
        var p=intent.get();var selected=accepted;
        if(p==null||selected==null||selected.planId()!=p.id()||selected.token()!=target.token()||target!=proxies.get(selected.token())||!Float.isFinite(amount)||amount<=0||amount>1000||outgoing.get()!=null)throw new IllegalStateException("Combat damage publication ownership changed");
        // Forward the exact snapshot/contact accepted by vanilla damage on the
        // server, not the earlier client-click sample. Never retimestamp it.
        outgoing.set(new Hit(++hits,selected.sourceSeq(),target.token(),amount,p.weapon(),nativePoint(p.aim().origin()),nativePoint(selected.point())));serverDamage+=amount;
    }
    @Override public void attempted(GameplayActorEntity target,DamageSource source,boolean wasAccepted){
        accepted=null;var p=intent.get();
        if(p!=null&&target.token()==p.token()&&dispatched==p.id()&&source.getAttacker()==serverPlayer&&source.getSource()==serverPlayer){
            if(!wasAccepted){var diagnostic=lastRejection;if(diagnostic==null||diagnostic.planId()!=p.id())reject("vanilla_damage_rejected",p);serverRejected++;rejected.incrementAndGet();}
            handled=p.id();
        }
    }
    private boolean reject(String reason,Plan p){
        long utc=System.currentTimeMillis();var s=snapshot;
        var target=server!=null&&server.isOnThread()?proxies.get(p.token()):null;var box=target==null?null:target.getBoundingBox();
        boolean intersects=box!=null&&box.raycast(p.aim().origin(),p.aim().origin().add(p.aim().direction().multiply(p.aim().range()))).isPresent();
        lastRejection=new Rejection(reason,p.id(),p.token(),utc,(System.nanoTime()-p.at())/1_000_000L,utc-p.aim().capturedUtcMs(),s==null?-1:utc-s.utc(),s==null?0:s.seq(),proxyCount,p.aim().origin(),p.aim().direction(),p.aim().obstructionDistance(),box,intersects);
        return false;
    }
    private Vec3d position(GameplayCombatProtocol.Actor a){var p=GameplayCombatProtocol.toMinecraft(new GameplayCombatProtocol.Point(a.x(),a.y(),a.z()),surface);return new Vec3d(p.x(),p.y(),p.z());}
    GameplayActorEntity projectileActor(GameplayCombatProtocol.Actor actor){
        if(closing||server==null||!server.isOnThread()||actor==null||!actor.alive())throw new IllegalStateException("Native projectile actor unavailable");
        var point=position(actor);var proxy=proxies.get(actor.token());
        if(proxy==null){proxy=new GameplayActorEntity(GameplayActorEntity.TYPE,server.getOverworld());proxy.bind(actor.token(),actor.width(),actor.height(),this);proxy.refreshPositionAndAngles(point.x,point.y,point.z,0,0);
            if(!server.getOverworld().spawnEntity(proxy))throw new IllegalStateException("Native projectile proxy spawn refused");proxies.put(actor.token(),proxy);
        }else{proxy.bind(actor.token(),actor.width(),actor.height(),this);proxy.setPosition(point);}proxyCount=proxies.size();return proxy;
    }
    void projectileFailure(String reason){failure.compareAndSet(null,reason);}
    private Vec3d nativePoint(Vec3d p){var point=GameplayCombatProtocol.toHost(new GameplayCombatProtocol.Point(p.x,p.y,p.z),surface);return new Vec3d(point.x(),point.y(),point.z());}
    private static GameplayCombatProtocol.Actor find(GameplayCombatProtocol.Snapshot s,int token){for(var a:s.actors())if(a.token()==token)return a;return null;}
    private static boolean sameStack(PlayerEntity player,Plan p){return player.getInventory().selectedSlot==p.slot()&&Registries.ITEM.getId(player.getMainHandStack().getItem()).toString().equals(p.weapon());}
    private void requireClient(MinecraftClient c){if(!c.isOnThread()||c.world!=clientWorld||c.player!=clientPlayer||c.getServer()!=server)throw new IllegalStateException("Combat client ownership changed");}
    private void check(){if(failure.get()!=null)throw new IllegalStateException(failure.get());}
    private void removeAll(){accepted=null;proxies.values().forEach(GameplayActorEntity::discard);proxies.clear();proxyCount=0;}
    public void suspend(MinecraftClient c){enabled=false;leftConsumed=false;intent.set(null);admitted=dispatched=0;}
    public void serverRespawn(ServerPlayerEntity oldPlayer,ServerPlayerEntity next){
        if(server==null)return;
        if(closing||!server.isOnThread()||oldPlayer==null||oldPlayer!=serverPlayer||next==null||next==oldPlayer||oldPlayer.isAlive()||!next.isAlive()||
                !oldPlayer.getUuid().equals(playerId)||!next.getUuid().equals(playerId)||oldPlayer.getServer()!=server||next.getServer()!=server||
                oldPlayer.getWorld()!=server.getOverworld()||next.getWorld()!=server.getOverworld()||oldPlayer.networkHandler!=next.networkHandler||serverRespawns!=clientRespawns)
            throw new IllegalStateException("Combat server respawn ownership changed");
        projectiles.respawn();intent.set(null);admitted=dispatched=0;serverPlayer=next;serverRespawns++;
    }
    public void clientRespawn(MinecraftClient c,ClientPlayerEntity oldPlayer){
        if(clientPlayer==null)return;
        if(closing||!c.isOnThread()||oldPlayer==null||clientPlayer!=oldPlayer||c.player==null||oldPlayer==c.player||oldPlayer.isAlive()||!c.player.isAlive()||
                c.world!=clientWorld||oldPlayer.getWorld()!=clientWorld||c.player.getWorld()!=clientWorld||c.getServer()!=server||!c.isIntegratedServerRunning()||
                !oldPlayer.getUuid().equals(playerId)||!c.player.getUuid().equals(playerId)||serverRespawns!=clientRespawns+1)
            throw new IllegalStateException("Combat client respawn ownership changed");
        suspend(c);clientPlayer=c.player;clientRespawns=serverRespawns;
    }
    public void close(MinecraftClient c){if(closing)return;suspend(c);projectiles.close();blasts.close();closing=true;if(server==null)serverClosed=true;else server.execute(()->{projectiles.closeServer();blasts.closeServer();removeAll();serverClosed=true;});}
    public boolean cleanupComplete(){return closing&&serverClosed&&workerClosed;}
    public JsonObject evidence(MinecraftClient c){
        var j=new JsonObject();j.addProperty("enabled",true);j.addProperty("standalone",standalone);j.addProperty("ready",ready());j.addProperty("proxy_count",proxyCount);j.addProperty("attacks_dispatched",attacks);j.addProperty("outgoing_hits",hits);j.addProperty("hit_ack",hostAck);j.addProperty("hurt_ack",hurtAck);j.addProperty("incoming_hurts",hurts);j.addProperty("server_applied_damage",serverDamage);j.addProperty("player_damage_applied",playerDamage);j.addProperty("rejected",rejected.get());j.addProperty("server_rejected",serverRejected);j.addProperty("pending",intent.get()!=null||outgoing.get()!=null);j.addProperty("cleanup_complete",cleanupComplete());j.addProperty("controls_released",!leftConsumed);j.addProperty("server_respawns",serverRespawns);j.addProperty("client_respawns",clientRespawns);j.addProperty("host_sequence",snapshot==null?0:snapshot.seq());
        j.add("projectiles",projectiles.evidence());
        j.add("blasts",blasts.evidence());
        var r=lastRejection;if(r!=null){var d=new JsonObject();d.addProperty("reason",r.reason());d.addProperty("plan_id",r.planId());d.addProperty("token",r.token());d.addProperty("utc_ms",r.utc());d.addProperty("plan_age_ms",r.planAgeMs());d.addProperty("aim_age_ms",r.aimAgeMs());d.addProperty("host_age_ms",r.hostAgeMs());d.addProperty("host_sequence",r.hostSequence());d.addProperty("proxy_count",r.proxies());d.add("ray_origin",point(r.rayOrigin()));d.add("ray_direction",point(r.rayDirection()));d.addProperty("native_obstruction_distance",r.obstruction());d.addProperty("ray_intersects_target",r.intersects());
            if(r.targetBox()!=null){var b=r.targetBox();var bounds=new JsonObject();bounds.add("min",point(new Vec3d(b.minX,b.minY,b.minZ)));bounds.add("max",point(new Vec3d(b.maxX,b.maxY,b.maxZ)));d.add("target_box",bounds);}j.add("last_rejection",d);}
        if(failure.get()!=null)j.addProperty("failure",failure.get());return j;
    }
    private void files(){
        long sequence=0,lastSeq=0,lastUtc=0;String lastText=null;
        try{
            while(!closing){
                projectiles.filesStep();
                blasts.filesStep();
                String text=GameplayCombatSnapshot.read(hostFile);
                if(text!=null){
                    if(!text.equals(lastText)){
                        var next=GameplayCombatProtocol.parse(text,identity,save.id().toString(),surface);
                        if(next.seq()<=lastSeq||next.utc()<lastUtc||next.utc()>System.currentTimeMillis()+50)throw new IOException("Combat snapshot replay/clock");
                        snapshot=next;lastSeq=next.seq();lastUtc=next.utc();lastText=text;lastHostAt=System.nanoTime();
                    }
                }
                var j=GameplayCombatProtocol.identity(identity,save.id().toString(),surface,"minecome_gameplay_combat_guest_v1");j.addProperty("seq",++sequence);j.addProperty("utc_ms",System.currentTimeMillis());j.addProperty("hurt_ack",hurtAck);
                var h=outgoing.get();if(h==null)j.add("hit",JsonNull.INSTANCE);else{var v=new JsonObject();v.addProperty("seq",h.seq());v.addProperty("source_seq",h.sourceSeq());v.addProperty("token",h.token());v.addProperty("damage_mc",h.damage());v.addProperty("damage_fraction",h.damage()/20.0);v.addProperty("weapon",h.weapon());v.add("origin",point(h.origin()));v.add("target",point(h.target()));j.add("hit",v);}
                Files.writeString(temporary,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
                try{Files.move(temporary,guestFile,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}catch(AccessDeniedException busy){/* Retry next bounded publication; keep immutable hit pending. */}
                Thread.sleep(20);
            }
        }catch(Exception e){if(!closing)failure.compareAndSet(null,e.toString());}
        finally{projectiles.filesClosed();blasts.filesClosed();try{Files.deleteIfExists(temporary);}catch(IOException e){failure.compareAndSet(null,e.toString());}workerClosed=true;}
    }
    private static JsonObject point(Vec3d p){var j=new JsonObject();j.addProperty("x",p.x);j.addProperty("y",p.y);j.addProperty("z",p.z);return j;}
}
