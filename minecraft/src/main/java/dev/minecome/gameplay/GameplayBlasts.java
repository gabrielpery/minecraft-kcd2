package dev.minecome.gameplay;

import com.google.gson.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.GroundSurface;
import dev.minecome.terrain.mixin.TntBlastInvoker;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.entity.TntEntity;
import net.minecraft.entity.damage.DamageSource;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.hit.HitResult;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.RaycastContext;
import net.minecraft.world.explosion.Explosion;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;

/** Pauses only the already-computed vanilla detonation tail for native scenery/actor admission. */
public final class GameplayBlasts {
    private static volatile GameplayBlasts active;
    private static final class Track {
        final TntEntity tnt;final String id,owner;final Vec3d center;final long utc=System.currentTimeMillis(),at=System.nanoTime();
        final Map<Integer,Bound> actors=new LinkedHashMap<>();final Map<Integer,Float> damage=new LinkedHashMap<>();
        long prepareSeq;boolean detonated,finished;
        Track(TntEntity tnt,UUID owner){this.tnt=tnt;this.id=compact(tnt.getUuid());this.owner=compact(owner);center=new Vec3d(tnt.getX(),tnt.getBodyY(.0625),tnt.getZ());}
    }
    private record Bound(GameplayActorEntity proxy,float exposure){}
    private record Pending(GameplayBlastProtocol.Request request,Track track,long at){}
    private record Receipt(String explosion,long prepareSeq,int token,float damage,String result,String reason,Double before,Double after){}
    private record Proof(String explosion,long prepareSeq,boolean prepared,boolean committed,int targets){}
    private final GameplayCombat combat;private final HudInputProtocol.Identity identity;private final String worldId;private volatile GroundSurface surface;
    private final Path hostFile,guestFile,temporary;private final boolean enabled;
    private final Map<UUID,Track> tracks=new LinkedHashMap<>(); // Server thread only.
    private final Set<UUID> failedSources=new HashSet<>(); // Sources stay frozen even if admission fails before Track creation.
    private final AtomicReference<Pending> pending=new AtomicReference<>();private final AtomicReference<GameplayBlastProtocol.Reply> delivered=new AtomicReference<>();
    private volatile Set<UUID> held=Set.of();private volatile List<Receipt> receipts=List.of();private volatile List<Proof> proofs=List.of();
    private volatile MinecraftServer server;private ServerPlayerEntity player;private volatile Object clientWorld;private volatile UUID playerId;private Track applying;
    private volatile boolean ready,closed,workerClosed,serverClosed,ownershipStopped;private volatile String failure;
    private long sequence,published,readSequence;private String readText;private volatile long prepared,committed,rejected,blockedTargets;private volatile double damageMc,nativeDamage;
    public GameplayBlasts(GameplayCombat combat,HudInputProtocol.Identity identity,GameplayWorld save,GroundSurface surface,Path directory,boolean standalone)throws IOException{
        this.combat=combat;this.identity=identity;worldId=save.id().toString();this.surface=surface;enabled=!standalone;
        hostFile=directory.resolve("host-blasts.json");guestFile=directory.resolve("blasts.json");temporary=directory.resolve("blasts.json.tmp");
        if(enabled){if(active!=null&&!active.closed)throw new IOException("Blast controller already owned");if(Files.exists(hostFile)||Files.exists(guestFile)||Files.exists(temporary))throw new IOException("Blast transport already exists");active=this;}
    }
    public void client(MinecraftClient client,boolean admitted){
        if(!enabled)return;if(clientWorld==null){clientWorld=client.world;playerId=client.player.getUuid();server=client.getServer();}
        if(client.world!=clientWorld||client.getServer()!=server||!client.player.getUuid().equals(playerId))throw new IllegalStateException("Blast client owner changed");ready=admitted&&!closed&&failure==null;
    }
    public void terrain(GroundSurface next){surface=next;}
    /** TNT has performed its actual gravity/movement and decremented the fuse, but has not discarded/exploded. */
    public static boolean prepare(TntEntity tnt){
        var s=active;if(s==null||!s.enabled||s.closed||tnt.getWorld().isClient)return false;
        UUID owner=GameplayTnt.explosionOwner(tnt);
        // Vanilla does not persist TNT causingEntity. A tag grants lifetime
        // ownership, never permission to invent native attacker attribution.
        if(owner==null||s.player==null||tnt.getOwner()!=s.player||!owner.equals(s.player.getUuid()))return false;
        try{
            s.requireServer(tnt);if(!s.ready||tnt.isRemoved()||tnt.getFuse()>0)throw new IllegalStateException("Blast source not ready at detonation tail");
            var old=s.tracks.get(tnt.getUuid());if(old!=null){if(old.tnt!=tnt||old.detonated)throw new IllegalStateException("Blast source replay");return true;}
            if(s.tracks.values().stream().filter(t->!t.finished).count()>=16)throw new IllegalStateException("Blast pending source capacity exceeded");
            var track=new Track(tnt,owner);s.tracks.put(tnt.getUuid(),track);s.publishHeld();s.queueNext();return true;
        }catch(Exception e){s.failedSources.add(tnt.getUuid());s.publishHeld();s.fail(e.toString());return true;}
    }
    public static boolean holdTick(TntEntity tnt){var s=active;return s!=null&&s.held.contains(tnt.getUuid())&&(tnt.getWorld().isClient?tnt.getWorld()==s.clientWorld:s.server!=null&&tnt.getWorld()==s.server.getOverworld());}
    private void requireServer(TntEntity tnt){if(server==null||!server.isOnThread()||player==null||tnt.getWorld()!=server.getOverworld()||server.getPlayerManager().getPlayer(playerId)!=player)throw new IllegalStateException("Blast server/world owner changed");}
    private void publishHeld(){var ids=new HashSet<>(failedSources);for(var t:tracks.values())if(!t.detonated&&!t.finished)ids.add(t.tnt.getUuid());held=Set.copyOf(ids);}
    private void queueNext(){
        if(pending.get()!=null||closed||failure!=null)return;
        for(var track:tracks.values())if(!track.finished&&!track.detonated&&track.prepareSeq==0){
            if(System.currentTimeMillis()-track.utc>500)throw new IllegalStateException("Queued blast source expired; no retimestamp");
            var request=new GameplayBlastProtocol.Request(++sequence,track.utc,"prepare",track.id,track.owner,0,nativePoint(track.center),List.of());track.prepareSeq=request.seq();pending.set(new Pending(request,track,System.nanoTime()));return;
        }
    }
    public void observe(MinecraftServer source,ServerPlayerEntity owner){
        if(!enabled||closed||server==null)return;
        if(source!=server||!source.isOnThread()||owner.getWorld()!=source.getOverworld()||!owner.getUuid().equals(playerId))throw new IllegalStateException("Blast server owner changed");player=owner;
        try{
            var task=pending.get();var reply=delivered.get();
            if(task!=null&&reply!=null&&reply.seq()==task.request().seq()){
                verify(task,reply);delivered.compareAndSet(reply,null);pending.compareAndSet(task,null);
                if(reply.result().equals("rejected")){rejected++;throw new IllegalStateException("Native blast rejected: "+reply.reason());}
                if(task.request().operation().equals("prepare"))detonate(task.track(),reply);
                else complete(task,reply);
            }else if(task!=null&&System.nanoTime()-task.at()>1_500_000_000L)throw new IllegalStateException("Native blast reply expired; no replay");
            tracks.entrySet().removeIf(entry->entry.getValue().finished);publishHeld();queueNext();
        }catch(Exception e){fail(e.toString());}
    }
    private void verify(Pending task,GameplayBlastProtocol.Reply reply){
        var request=task.request();long now=System.currentTimeMillis();
        if(reply.seq()!=request.seq()||reply.requestUtc()!=request.utc()||!reply.operation().equals(request.operation())||!reply.explosion().equals(request.explosion())||!reply.owner().equals(request.owner())||reply.utc()>now+50||now-reply.utc()>300||reply.utc()<request.utc()-50||distanceSquared(reply.center(),request.center())>1e-10||
            !reply.result().equals("rejected")&&reply.prepareSeq()!=(request.operation().equals("prepare")?request.seq():request.prepareSeq()))throw new IllegalStateException("Blast receipt source/identity/freshness differs");
    }
    private void detonate(Track track,GameplayBlastProtocol.Reply reply){
        requireServer(track.tnt);UUID owner=GameplayTnt.explosionOwner(track.tnt);
        if(!ready||owner==null||!compact(owner).equals(track.owner)||track.tnt.getOwner()!=player||track.tnt.isRemoved()||track.tnt.getFuse()>0||new Vec3d(track.tnt.getX(),track.tnt.getBodyY(.0625),track.tnt.getZ()).squaredDistanceTo(track.center)>1e-12)throw new IllegalStateException("Prepared blast source changed");
        for(var grant:reply.actors()){
            var proxy=combat.projectileActor(grant.actor());var b=proxy.getBoundingBox();
            var samples=GameplayBlastExposure.samples(b.minX,b.minY,b.minZ,b.maxX,b.maxY,b.maxZ);
            float exposure=GameplayBlastExposure.combine(samples,grant.exposure(),p->{var point=new Vec3d(p.x(),p.y(),p.z());return proxy.getWorld().raycast(new RaycastContext(point,track.center,RaycastContext.ShapeType.COLLIDER,RaycastContext.FluidHandling.NONE,proxy)).getType()==HitResult.Type.MISS;});
            if(proxy.getPos().squaredDistanceTo(track.center)>64.000001)throw new IllegalStateException("Native blast actor outside vanilla radius");
            if(exposure==0)blockedTargets++;track.actors.put(proxy.token(),new Bound(proxy,exposure));
        }
        prepared++;proof(track,false);applying=track;
        try{track.detonated=true;track.tnt.discard();((TntBlastInvoker)track.tnt).minecome$explode();}
        finally{applying=null;publishHeld();}
        var targets=new ArrayList<GameplayBlastProtocol.Target>();track.damage.forEach((token,damage)->targets.add(new GameplayBlastProtocol.Target(token,damage)));
        var request=new GameplayBlastProtocol.Request(++sequence,System.currentTimeMillis(),"commit",track.id,track.owner,track.prepareSeq,nativePoint(track.center),targets);
        if(pending.get()!=null)throw new IllegalStateException("Blast commit slot already occupied");pending.set(new Pending(request,track,System.nanoTime()));
    }
    public static Float exposure(Vec3d center,Entity entity){
        var s=active;if(s==null||s.applying==null||!(entity instanceof GameplayActorEntity actor)||s.server==null||!s.server.isOnThread()||entity.getWorld()!=s.server.getOverworld()||center.squaredDistanceTo(s.applying.center)>1e-12)return null;
        var bound=s.applying.actors.get(actor.token());return bound!=null&&bound.proxy()==actor?bound.exposure():0f;
    }
    public static boolean shouldDamage(Explosion explosion,Entity entity,boolean vanilla){
        if(!vanilla||!(entity instanceof GameplayActorEntity))return vanilla;var s=active;
        if(s==null||s.applying==null||explosion.getEntity()!=s.applying.tnt)return vanilla;
        var exposure=exposure(explosion.getPosition(),entity);return exposure!=null&&exposure>0;
    }
    public boolean accepts(GameplayActorEntity target,DamageSource source,float amount){
        var t=applying;if(!enabled||closed||t==null||server==null||!server.isOnThread()||source.getSource()!=t.tnt||target.getWorld()!=server.getOverworld()||!Float.isFinite(amount)||amount<=0||amount>1000)return false;
        var bound=t.actors.get(target.token());return bound!=null&&bound.proxy()==target&&bound.exposure()>0&&!t.damage.containsKey(target.token());
    }
    public void applied(GameplayActorEntity target,DamageSource source,float amount){
        if(!accepts(target,source,amount))throw new IllegalStateException("Blast damage escaped its exact native preparation");applying.damage.put(target.token(),amount);damageMc+=amount;
    }
    public boolean retains(int token){return tracks.values().stream().anyMatch(t->!t.finished&&t.actors.containsKey(token));}
    private void complete(Pending task,GameplayBlastProtocol.Reply reply){
        var requested=new HashMap<Integer,Float>();for(var target:task.request().targets())requested.put(target.token(),target.damage());
        if(reply.outcomes().size()!=requested.size())throw new IllegalStateException("Blast outcome target count differs");
        var next=new ArrayList<>(receipts);
        for(var outcome:reply.outcomes()){
            Float damage=requested.remove(outcome.token());if(damage==null)throw new IllegalStateException("Blast outcome target identity differs");
            if(outcome.result().equals("rejected"))rejected++;else nativeDamage+=Math.max(0,outcome.before()-outcome.after());
            next.add(new Receipt(task.track().id,task.track().prepareSeq,outcome.token(),damage,outcome.result(),outcome.reason(),outcome.before(),outcome.after()));
        }
        if(next.size()>32)next=new ArrayList<>(next.subList(next.size()-32,next.size()));receipts=List.copyOf(next);task.track().finished=true;committed++;proof(task.track(),true);
    }
    private void proof(Track track,boolean commit){var next=new ArrayList<>(proofs);next.removeIf(p->p.explosion().equals(track.id));next.add(new Proof(track.id,track.prepareSeq,true,commit,track.damage.size()));if(next.size()>32)next.removeFirst();proofs=List.copyOf(next);}
    public void filesStep()throws IOException{
        if(!enabled||closed)return;var task=pending.get();if(task==null)return;
        if(published!=task.request().seq()){
            Files.writeString(temporary,GameplayBlastProtocol.request(task.request(),identity,worldId,surface).toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
            try{Files.move(temporary,guestFile,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);published=task.request().seq();}catch(FileSystemException busy){return;}
        }
        var text=GameplayCombatSnapshot.read(hostFile);if(text==null||text.equals(readText))return;var reply=GameplayBlastProtocol.parse(text,identity,worldId,surface);
        if(reply.seq()<readSequence||reply.seq()==readSequence&&!text.equals(readText)||reply.seq()>task.request().seq())throw new IOException("Blast receipt replay/future");
        readText=text;readSequence=reply.seq();if(reply.seq()==task.request().seq())delivered.set(reply);
    }
    public void close(){closed=true;ready=false;pending.set(null);delivered.set(null);if(server==null){serverClosed=true;if(active==this)active=null;}}
    public void closeServer(){if(server!=null&&!server.isOnThread())throw new IllegalStateException("Blast close requires owning server thread");tracks.clear();failedSources.clear();applying=null;serverClosed=true;releaseStopped();}
    /** Client marks TNT ownership closed before releasing this controller's held-fuse tombstone. */
    public static void ownershipStopped(UUID world){var s=active;if(s!=null&&s.worldId.equals(world.toString())){s.ownershipStopped=true;s.releaseStopped();}}
    private void releaseStopped(){if(closed&&serverClosed&&ownershipStopped){held=Set.of();if(active==this)active=null;}}
    public void filesClosed(){try{Files.deleteIfExists(temporary);}catch(IOException e){fail(e.toString());}workerClosed=true;}
    private void fail(String reason){failure=reason;ready=false;combat.projectileFailure(reason);}
    public JsonObject evidence(){
        var j=new JsonObject();j.addProperty("enabled",enabled);j.addProperty("prepared",prepared);j.addProperty("committed",committed);j.addProperty("pending",pending.get()!=null||!held.isEmpty());j.addProperty("damage_mc",damageMc);j.addProperty("native_damage",nativeDamage);j.addProperty("blocked_targets",blockedTargets);j.addProperty("rejected",rejected);j.addProperty("cleanup_complete",!enabled||closed&&serverClosed&&workerClosed);if(failure!=null)j.addProperty("failure",failure);
        var rs=new JsonArray();for(var r:receipts){var v=new JsonObject();v.addProperty("explosion",r.explosion());v.addProperty("prepare_seq",r.prepareSeq());v.addProperty("actor_token",r.token());v.addProperty("damage_mc",r.damage());v.addProperty("damage_fraction",r.damage()/20d);v.addProperty("result",r.result());v.addProperty("reason",r.reason());v.addProperty("before",r.before());v.addProperty("after",r.after());rs.add(v);}j.add("receipts",rs);
        var ps=new JsonArray();for(var p:proofs){var v=new JsonObject();v.addProperty("explosion",p.explosion());v.addProperty("prepare_seq",p.prepareSeq());v.addProperty("prepared",p.prepared());v.addProperty("committed",p.committed());v.addProperty("targets",p.targets());ps.add(v);}j.add("explosions",ps);return j;
    }
    private GameplayCombatProtocol.Point nativePoint(Vec3d p){return GameplayCombatProtocol.toHost(new GameplayCombatProtocol.Point(p.x,p.y,p.z),surface);}
    private static double distanceSquared(GameplayCombatProtocol.Point a,GameplayCombatProtocol.Point b){double x=a.x()-b.x(),y=a.y()-b.y(),z=a.z()-b.z();return x*x+y*y+z*z;}
    private static String compact(UUID id){return id.toString().replace("-","");}
}
