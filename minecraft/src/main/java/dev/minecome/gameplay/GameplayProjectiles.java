package dev.minecome.gameplay;

import com.google.gson.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.entity.damage.DamageSource;
import net.minecraft.entity.projectile.PersistentProjectileEntity;
import net.minecraft.item.Items;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.hit.*;
import net.minecraft.util.math.*;
import net.minecraft.world.RaycastContext;
import net.minecraft.world.World;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;

/** Native swept segments gate the real vanilla arrow tick; damage remains vanilla.
 * Pinned Yarn1.21.1+build.3 tick uses pos→pos+velocity before drag/gravity, then
 * raycast/getEntityCollision/hitOrDeflect. Native contacts join those exact calls.
 * Source: runtime/evidence/projectile-impact-source-20261109/.
 */
public final class GameplayProjectiles {
    private static volatile GameplayProjectiles active;
    private static final class Track {
        final PersistentProjectileEntity arrow;final UUID owner;final String id;final long created=System.nanoTime();
        final List<GameplayProjectileInterpolation.Sample> confirmed=new ArrayList<>();
        int segment;boolean embedded,finished,applied;GameplayProjectileProtocol.Reply trace;Vec3d from,to;GameplayActorEntity actor;
        Track(PersistentProjectileEntity arrow){this.arrow=arrow;owner=arrow.getOwner().getUuid();id=arrow.getUuid().toString().replace("-","");confirmed.add(new GameplayProjectileInterpolation.Sample(0,created,presentationPoint(arrow.getPos())));}
    }
    private record Pending(GameplayProjectileProtocol.Request request,Track track,long at){}
    private record Pose(Vec3d position,Vec3d velocity,float yaw,float pitch,int shake,boolean ground,boolean removed,boolean finished,List<GameplayProjectileInterpolation.Sample> confirmed){}
    private record Visual(PersistentProjectileEntity arrow,GameplayProjectileInterpolation playback){}
    public record RenderPosition(Vec3d position,boolean visible,boolean intermediate){}
    private final GameplayCombat combat;private final HudInputProtocol.Identity identity;private final String worldId;private volatile GroundSurface surface;
    private final Path hostFile,guestFile,temporary;private final boolean enabled;
    private final Map<UUID,Track> tracks=new LinkedHashMap<>(); // Server thread only.
    private volatile Map<UUID,Pose> poses=Map.of();
    private final Map<UUID,Visual> visuals=new HashMap<>(); // Client/render thread only; exact entity generation.
    private volatile boolean resetVisuals;
    private final AtomicReference<Pending> pending=new AtomicReference<>();private final AtomicReference<GameplayProjectileProtocol.Reply> delivered=new AtomicReference<>();
    private volatile GameplayProjectileProtocol.Reply lastReply,lastImpact,lastScenery;private volatile boolean closed,workerClosed,serverClosed,ready;
    private Object clientWorld,clientPlayer;private volatile MinecraftServer server;private ServerPlayerEntity player;
    private long sequence,published,readSequence;private String readText;private volatile long traces,clear,scenery,actorHits,impacts,rejected,waitTicks,prequeuedSegments,mirroredTicks,removedOnStop,renderedIntermediateSamples;
    private volatile double damage,minecraftDamage;private volatile String failure;
    public GameplayProjectiles(GameplayCombat combat,HudInputProtocol.Identity identity,GameplayWorld save,GroundSurface surface,Path directory,boolean standalone)throws IOException{
        this.combat=combat;this.identity=identity;this.worldId=save.id().toString();this.surface=surface;
        enabled=!standalone||GameplayMode.projectileFixtureEnabled(System.getProperties());
        hostFile=directory.resolve("host-projectiles.json");guestFile=directory.resolve("projectiles.json");temporary=directory.resolve("projectiles.json.tmp");
        if(enabled){if(active!=null&&!active.closed)throw new IOException("Projectile controller already owned");
            if(Files.exists(hostFile)||Files.exists(guestFile)||Files.exists(temporary))throw new IOException("Projectile transport already exists");active=this;}
    }
    public void client(MinecraftClient c,boolean admitted){
        if(!enabled)return;if(clientWorld==null){clientWorld=c.world;clientPlayer=c.player;server=c.getServer();}
        if(c.world!=clientWorld||c.player!=clientPlayer||c.getServer()!=server)throw new IllegalStateException("Projectile client owner changed");
        if(resetVisuals){visuals.clear();resetVisuals=false;}
        visuals.entrySet().removeIf(entry->entry.getValue().arrow().isRemoved()||entry.getValue().arrow().getWorld()!=clientWorld||entry.getValue().arrow().getOwner()!=clientPlayer);
        ready=admitted&&!closed&&failure==null;
    }
    public static boolean readyForDraw(MinecraftClient c){var s=active;return s!=null&&s.enabled&&s.ready&&!s.closed&&s.clientWorld==c.world&&s.clientPlayer==c.player&&s.server==c.getServer();}
    public void terrain(GroundSurface next){surface=next;}
    public void observe(MinecraftServer source,ServerPlayerEntity owner){
        if(!enabled||closed||server==null)return; // Client admission may not have published its owner yet.
        if(!source.isOnThread()||source!=server||owner.getWorld()!=source.getOverworld()||player!=null&&player!=owner)throw new IllegalStateException("Projectile server owner changed");player=owner;
        var task=pending.get();var reply=delivered.get();
        if(task!=null&&reply!=null&&reply.seq()==task.request().seq()&&task.request().operation().equals("impact")){
            verifyReply(task,reply);if(reply.result().equals("rejected"))rejected++;else{impacts++;damage+=Math.max(0,reply.before()-reply.after());}
            task.track().finished=true;lastReply=lastImpact=reply;delivered.compareAndSet(reply,null);pending.compareAndSet(task,null);
        }
        if(task!=null&&System.nanoTime()-task.at()>1_500_000_000L)fail("Native projectile reply expired; no replay");
        tracks.entrySet().removeIf(entry->entry.getValue().arrow.isRemoved()&&(pending.get()==null||pending.get().track()!=entry.getValue()));publishPoses();
    }
    private void publishPoses(){var next=new HashMap<UUID,Pose>();for(var t:tracks.values()){var a=t.arrow;next.put(a.getUuid(),new Pose(a.getPos(),a.getVelocity(),a.getYaw(),a.getPitch(),a.shake,t.embedded,a.isRemoved(),t.finished,List.copyOf(t.confirmed)));}poses=Map.copyOf(next);}
    /** The world renderer uses this translation without changing the client or server entity. */
    public static RenderPosition renderPosition(PersistentProjectileEntity arrow){
        var s=active;var c=MinecraftClient.getInstance();
        if(s==null||s.closed||!c.isOnThread()||c.world!=s.clientWorld||c.player!=s.clientPlayer||c.getServer()!=s.server||arrow.getWorld()!=c.world||arrow.getOwner()!=c.player)return null;
        var visual=s.visuals.get(arrow.getUuid());var pose=s.poses.get(arrow.getUuid());
        if(s.resetVisuals){s.visuals.clear();s.resetVisuals=false;visual=null;}
        if(pose==null)return visual==null?null:new RenderPosition(arrow.getPos(),false,false);
        if(visual==null||visual.arrow()!=arrow){visual=new Visual(arrow,new GameplayProjectileInterpolation());s.visuals.put(arrow.getUuid(),visual);}
        if(pose.ground()||pose.removed()||pose.finished()){visual.playback().clear();return new RenderPosition(pose.position(),!pose.removed()&&!pose.finished(),false);}
        var frame=visual.playback().frame(pose.confirmed(),System.nanoTime());
        var p=frame.point();return new RenderPosition(new Vec3d(p.x(),p.y(),p.z()),true,frame.intermediate());
    }
    public static void rendered(PersistentProjectileEntity arrow,RenderPosition position){var s=active;if(s==null||s.closed||position==null||!position.intermediate())return;var visual=s.visuals.get(arrow.getUuid());if(visual!=null&&visual.arrow()==arrow)s.renderedIntermediateSamples++;}
    public static boolean beforeTick(PersistentProjectileEntity arrow,boolean inGround){
        var s=active;if(s==null||!s.enabled||s.closed)return false;
        try{return arrow.getWorld().isClient?s.clientTick(arrow):s.serverTick(arrow,inGround);}catch(Exception e){s.fail(e.toString());if(!arrow.getWorld().isClient&&s.owned(arrow))arrow.discard();return true;}
    }
    private boolean owned(PersistentProjectileEntity arrow){return server!=null&&server.isOnThread()&&player!=null&&arrow.getWorld()==server.getOverworld()&&arrow.getOwner()==player;}
    // SpectralArrowEntity also delegates its tick to this same vanilla base; the
    // exact bow weapon/owner gate admits it without admitting tridents/crossbows.
    private boolean eligible(PersistentProjectileEntity arrow){return owned(arrow)&&arrow.getWeaponStack()!=null&&arrow.getWeaponStack().isOf(Items.BOW);}
    private boolean clientTick(PersistentProjectileEntity arrow){
        var c=MinecraftClient.getInstance();if(!c.isOnThread()||c.world!=clientWorld||c.player!=clientPlayer||arrow.getWorld()!=clientWorld||arrow.getOwner()!=clientPlayer)return false;
        var pose=poses.get(arrow.getUuid());if(pose==null)return false;
        // The integrated server is authoritative while a native segment is in flight.
        // Rendering interpolates these actual server positions; client prediction
        // cannot move an arrow through a wall while waiting for the native result.
        arrow.lastRenderX=arrow.getX();arrow.lastRenderY=arrow.getY();arrow.lastRenderZ=arrow.getZ();arrow.prevYaw=arrow.getYaw();arrow.prevPitch=arrow.getPitch();
        arrow.setPosition(pose.position());arrow.setVelocity(pose.velocity());arrow.setYaw(pose.yaw());arrow.setPitch(pose.pitch());arrow.shake=pose.shake();
        if(pose.removed())arrow.discard();mirroredTicks++;return true;
    }
    private boolean serverTick(PersistentProjectileEntity arrow,boolean inGround){
        if(!eligible(arrow))return false;
        var track=tracks.get(arrow.getUuid());
        if(track==null){
            if(inGround)return false; // Existing saved embedded arrows retain vanilla lifetime/pickup.
            if(tracks.size()>=64||tracks.values().stream().filter(t->!t.embedded&&!t.finished).count()>=16)throw new IllegalStateException("Native projectile ownership capacity exceeded");
            if(arrow.getPierceLevel()!=0||arrow.isNoClip())throw new IllegalStateException("Only ordinary nonpiercing bow arrows are supported");
            track=new Track(arrow);tracks.put(arrow.getUuid(),track);publishPoses();
        }
        if(track.arrow!=arrow||!track.owner.equals(player.getUuid()))throw new IllegalStateException("Projectile entity generation changed");
        if(inGround){track.embedded=true;return false;}
        if(track.finished)return true;
        if(!flightReady(track))return true;
        var task=pending.get();
        if(task!=null){
            if(task.track()!=track||!task.request().operation().equals("trace")){waitTicks++;return true;}
            var reply=delivered.get();if(reply==null||reply.seq()!=task.request().seq()){waitTicks++;return true;}
            verifyReply(task,reply);lastReply=reply;delivered.compareAndSet(reply,null);pending.compareAndSet(task,null);
            if(reply.result().equals("rejected")){track.finished=true;arrow.discard();rejected++;return true;}
            if(arrow.getPos().squaredDistanceTo(track.from)>1e-12||arrow.getPos().add(arrow.getVelocity()).squaredDistanceTo(track.to)>1e-12)throw new IllegalStateException("Pending projectile trajectory changed");
            track.trace=reply;track.applied=false;
            if(reply.result().equals("actor"))track.actor=combat.projectileActor(reply.actor());
            traces++;if(reply.result().equals("clear"))clear++;
            return false;
        }
        queueTrace(track);waitTicks++;return true;
    }
    private boolean flightReady(Track track){
        if(!ready||!player.isAlive()||server.getPlayerManager().getPlayer(player.getUuid())!=player)throw new IllegalStateException("Projectile authority unavailable");
        if(System.nanoTime()-track.created>10_000_000_000L){track.finished=true;track.arrow.discard();rejected++;return false;}
        return true;
    }
    private void queueTrace(Track track){
        if(pending.get()!=null)throw new IllegalStateException("Projectile request already in flight");
        var from=track.arrow.getPos();var to=from.add(track.arrow.getVelocity());double distance=from.distanceTo(to);
        if(!finite(from)||!finite(to)||distance<.00001||distance>4)throw new IllegalStateException("Projectile segment outside supported bounds");
        track.from=from;track.to=to;track.trace=null;track.actor=null;
        var request=new GameplayProjectileProtocol.Request(++sequence,System.currentTimeMillis(),"trace",track.id,++track.segment,nativePoint(from),nativePoint(to),0,0);
        pending.set(new Pending(request,track,System.nanoTime()));
    }
    private void verifyReply(Pending task,GameplayProjectileProtocol.Reply reply){
        var request=task.request();long now=System.currentTimeMillis();
        if(reply.seq()!=request.seq()||reply.requestUtc()!=request.utc()||!reply.operation().equals(request.operation())||!reply.projectile().equals(request.projectile())||reply.segment()!=request.segment()||
            reply.utc()>now+50||now-reply.utc()>300||reply.utc()<request.utc()-50)throw new IllegalStateException("Projectile receipt identity or freshness differs");
        if(!request.operation().equals("trace")){if(!reply.result().equals("rejected")&&reply.token()!=request.token())throw new IllegalStateException("Projectile impact actor changed");return;}
        if(reply.result().equals("rejected"))return;
        var contact=minecraftPoint(reply.contact());var delta=task.track().to.subtract(task.track().from);double t=contact.subtract(task.track().from).dotProduct(delta)/delta.lengthSquared();
        if(t<-.001||t>1.001||contact.squaredDistanceTo(task.track().from.add(delta.multiply(MathHelper.clamp(t,0,1))))>.01)throw new IllegalStateException("Native projectile contact left its segment");
    }
    public static BlockHitResult blockHit(PersistentProjectileEntity arrow,World world,RaycastContext context){
        var vanilla=world.raycast(context);var s=active;if(s==null||world.isClient||s.closed)return vanilla;
        var t=s.tracks.get(arrow.getUuid());if(t==null||t.arrow!=arrow||t.trace==null||!t.trace.result().equals("scenery"))return vanilla;
        var contact=s.minecraftPoint(t.trace.contact());if(vanilla.getType()!=HitResult.Type.MISS&&context.getStart().squaredDistanceTo(vanilla.getPos())<=context.getStart().squaredDistanceTo(contact))return vanilla;
        var n=t.trace.normal();var normal=new Vec3d(n.x(),n.z(),-n.y());
        return new BlockHitResult(contact,Direction.getFacing(normal.x,normal.y,normal.z),BlockPos.ofFloored(contact),false);
    }
    public static boolean allowEntity(PersistentProjectileEntity arrow,Entity candidate){
        if(!(candidate instanceof GameplayActorEntity actor))return true;var s=active;if(s==null||s.closed||arrow.getWorld().isClient)return true;
        var t=s.tracks.get(arrow.getUuid());return t==null||t.arrow!=arrow||t.trace==null?false:t.trace.result().equals("actor")&&t.actor==actor;
    }
    public static EntityHitResult entityHit(PersistentProjectileEntity arrow,Vec3d start,Vec3d end,EntityHitResult vanilla){
        var s=active;if(s==null||s.closed||arrow.getWorld().isClient)return vanilla;var t=s.tracks.get(arrow.getUuid());if(t==null||t.arrow!=arrow||t.trace==null)return vanilla;
        if(vanilla!=null&&vanilla.getEntity() instanceof GameplayActorEntity)vanilla=null;
        if(!t.trace.result().equals("actor"))return vanilla;var contact=s.minecraftPoint(t.trace.contact());
        if(start.squaredDistanceTo(contact)>start.squaredDistanceTo(end)+1e-6)return vanilla;
        if(vanilla!=null&&start.squaredDistanceTo(vanilla.getPos())<start.squaredDistanceTo(contact))return vanilla;
        return new EntityHitResult(t.actor,contact);
    }
    public static void onBlockHit(PersistentProjectileEntity arrow,BlockHitResult hit){var s=active;if(s==null||s.closed||arrow.getWorld().isClient)return;var t=s.tracks.get(arrow.getUuid());if(t!=null&&t.arrow==arrow&&t.trace!=null&&t.trace.result().equals("scenery")&&s.minecraftPoint(t.trace.contact()).squaredDistanceTo(hit.getPos())<1e-10){s.scenery++;s.lastScenery=t.trace;}}
    public static void afterTick(PersistentProjectileEntity arrow,boolean inGround){
        var s=active;if(s==null||s.closed||arrow.getWorld().isClient)return;
        try{
            var t=s.tracks.get(arrow.getUuid());if(t==null||t.arrow!=arrow)return;
            t.embedded=inGround;boolean confirmedClear=t.trace!=null&&t.trace.result().equals("clear");
            if(t.trace!=null&&t.trace.result().equals("actor")&&!t.applied&&!inGround){t.finished=true;arrow.discard();s.rejected++;}
            t.trace=null;
            if(confirmedClear&&!inGround&&!t.finished&&!arrow.isRemoved()){
                t.confirmed.add(new GameplayProjectileInterpolation.Sample(t.segment,System.nanoTime(),presentationPoint(arrow.getPos())));
                if(t.confirmed.size()>8)t.confirmed.removeFirst();
            }
            // Only the completed vanilla tick supplies this segment's position and
            // velocity. Queue it now so transport can run between server ticks.
            // Multiple arrows keep the existing scheduler and its single-flight slot.
            if(confirmedClear&&!inGround&&!t.finished&&!arrow.isRemoved()&&s.eligible(arrow)&&t.owner.equals(s.player.getUuid())&&s.pending.get()==null&&
                s.tracks.values().stream().filter(other->!other.embedded&&!other.finished&&!other.arrow.isRemoved()).count()==1&&s.flightReady(t)){
                s.queueTrace(t);s.prequeuedSegments++;
            }
            s.publishPoses();
        }catch(Exception e){s.fail(e.toString());if(s.owned(arrow))arrow.discard();}
    }
    public boolean accepts(GameplayActorEntity target,DamageSource source,float amount){
        if(!enabled||closed||!(source.getSource() instanceof PersistentProjectileEntity arrow)||!owned(arrow)||source.getAttacker()!=player)return false;
        var t=tracks.get(arrow.getUuid());return t!=null&&t.arrow==arrow&&!t.applied&&t.actor==target&&t.trace!=null&&t.trace.result().equals("actor")&&pending.get()==null&&
            System.currentTimeMillis()-t.trace.utc()<=300&&Float.isFinite(amount)&&amount>0&&amount<=1000;
    }
    public void applied(GameplayActorEntity target,DamageSource source,float amount){
        if(!accepts(target,source,amount))throw new IllegalStateException("Projectile damage escaped its native contact");
        var arrow=(PersistentProjectileEntity)source.getSource();var t=tracks.get(arrow.getUuid());t.applied=true;actorHits++;minecraftDamage+=amount;
        var request=new GameplayProjectileProtocol.Request(++sequence,System.currentTimeMillis(),"impact",t.id,t.segment,nativePoint(t.from),nativePoint(t.to),target.token(),amount);
        pending.set(new Pending(request,t,System.nanoTime()));
    }
    public boolean retains(int token){var task=pending.get();if(task!=null&&task.request().token()==token)return true;return tracks.values().stream().anyMatch(t->t.trace!=null&&t.trace.token()==token);}
    public void filesStep()throws IOException{
        if(!enabled||closed)return;var task=pending.get();if(task==null)return;
        if(published!=task.request().seq()){
            Files.writeString(temporary,GameplayProjectileProtocol.request(task.request(),identity,worldId,surface).toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
            try{Files.move(temporary,guestFile,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);published=task.request().seq();}
            catch(FileSystemException busy){return;} // Original immutable UTC/deadline remain unchanged.
        }
        var text=GameplayCombatSnapshot.read(hostFile);if(text==null||text.equals(readText))return;
        var reply=GameplayProjectileProtocol.parse(text,identity,worldId,surface);
        if(reply.seq()<readSequence||reply.seq()==readSequence&&!text.equals(readText)||reply.seq()>task.request().seq())throw new IOException("Projectile receipt replay/future");
        readText=text;readSequence=reply.seq();if(reply.seq()==task.request().seq())delivered.set(reply);
    }
    public void filesClosed(){if(!enabled){workerClosed=true;return;}try{Files.deleteIfExists(temporary);}catch(IOException e){fail(e.toString());}workerClosed=true;}
    public void closeServer(){if(!enabled){serverClosed=true;return;}for(var t:tracks.values())if(!t.embedded&&!t.arrow.isRemoved()){t.arrow.discard();removedOnStop++;}tracks.clear();poses=Map.of();serverClosed=true;}
    public void close(){closed=true;ready=false;visuals.clear();pending.set(null);delivered.set(null);if(active==this)active=null;if(server==null)serverClosed=true;}
    public void respawn(){if(!enabled)return;closeServer();resetVisuals=true;serverClosed=false;player=null;clientPlayer=null;clientWorld=null;ready=false;pending.set(null);delivered.set(null);}
    public JsonObject evidence(){var j=new JsonObject();j.addProperty("enabled",enabled);j.addProperty("traces",traces);j.addProperty("clear_segments",clear);j.addProperty("scenery_hits",scenery);j.addProperty("actor_hits",actorHits);j.addProperty("impacts",impacts);j.addProperty("damage",minecraftDamage);j.addProperty("native_damage",damage);j.addProperty("rejected",rejected);j.addProperty("wait_ticks",waitTicks);j.addProperty("prequeued_segments",prequeuedSegments);j.addProperty("client_mirror_ticks",mirroredTicks);j.addProperty("pending",pending.get()!=null);j.addProperty("cleanup_complete",!enabled||closed&&workerClosed&&serverClosed);j.addProperty("removed_on_stop",removedOnStop);if(failure!=null)j.addProperty("failure",failure);
        j.addProperty("rendered_intermediate_samples",renderedIntermediateSamples);
        if(lastReply!=null)j.add("last_reply",replyEvidence(lastReply));if(lastImpact!=null)j.add("last_impact",replyEvidence(lastImpact));if(lastScenery!=null)j.add("last_scenery",replyEvidence(lastScenery));return j;}
    private static JsonObject replyEvidence(GameplayProjectileProtocol.Reply r){var value=new JsonObject();value.addProperty("seq",r.seq());value.addProperty("operation",r.operation());value.addProperty("projectile",r.projectile());value.addProperty("segment",r.segment());value.addProperty("result",r.result());value.addProperty("reason",r.reason());value.addProperty("actor_token",r.token());value.addProperty("before",r.before());value.addProperty("after",r.after());value.add("contact",point(r.contact()));value.add("normal",point(r.normal()));return value;}
    private static JsonObject point(GameplayCombatProtocol.Point p){var j=new JsonObject();j.addProperty("x",p.x());j.addProperty("y",p.y());j.addProperty("z",p.z());return j;}
    private GameplayCombatProtocol.Point nativePoint(Vec3d p){return GameplayCombatProtocol.toHost(new GameplayCombatProtocol.Point(p.x,p.y,p.z),surface);}
    private Vec3d minecraftPoint(GameplayCombatProtocol.Point p){var v=GameplayCombatProtocol.toMinecraft(p,surface);return new Vec3d(v.x(),v.y(),v.z());}
    private static boolean finite(Vec3d p){return Double.isFinite(p.x)&&Double.isFinite(p.y)&&Double.isFinite(p.z);}
    private static GameplayProjectileInterpolation.Point presentationPoint(Vec3d p){return new GameplayProjectileInterpolation.Point(p.x,p.y,p.z);}
    private void fail(String reason){failure=reason;ready=false;combat.projectileFailure(reason);}
}
