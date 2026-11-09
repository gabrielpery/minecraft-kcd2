package dev.minecome.gameplay;

import com.google.gson.JsonObject;
import dev.minecome.terrain.GroundCollision;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.TntEntity;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.world.ServerWorld;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Box;
import net.minecraft.util.TypeFilter;
import net.minecraft.world.World;
import net.minecraft.world.explosion.Explosion;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Owns real vanilla TNT entities; fuse, physics, explosion power, drops and damage stay vanilla.
 * Hooks inspected in pinned Yarn1.21.1 TntBlock/TntEntity/Explosion/AbstractBlock.
 * The persisted tag freezes a fuse whenever its exact gameplay world is detached.
 */
public final class GameplayTnt {
    private static volatile GameplayTnt active;
    private static final class Entry {
        final TntEntity entity;final UUID originalOwner;boolean ground=true,paused;
        Entry(TntEntity entity,UUID originalOwner){this.entity=entity;this.originalOwner=originalOwner;}
    }
    private final GameplayBlocks blocks;private final GameplayWorld save;private final boolean enabled;
    private volatile GroundSurface surface;private volatile MinecraftServer server;private volatile ServerWorld world;
    private Object clientWorld;private UUID playerId;private volatile Set<UUID> visible=Set.of(),known=Set.of(),suspended=Set.of();
    private volatile Box captureBounds;private volatile long nextResumeScan;
    private final Map<UUID,Entry> entities=new LinkedHashMap<>(); // Server thread only.
    private volatile boolean closing,serverClosed;private volatile String failure;
    private volatile long primed,chainPrimed,explosions,resumed,ownerlessResumed,frozenOnStop,groundRecoveries,affectedOwnedBlocks;
    public GameplayTnt(GameplayBlocks blocks,GameplayWorld save,GroundSurface surface){
        this.blocks=blocks;this.save=save;this.surface=surface;enabled=blocks.worldBlocksEnabled();captureBounds=bounds(surface);
        if(enabled){if(active!=null&&!active.closing)throw new IllegalStateException("TNT controller already owned");active=this;}
    }
    public void client(MinecraftClient client){
        if(!enabled||closing)return;
        if(!client.isOnThread()||client.world==null||client.player==null||client.getServer()==null)throw new IllegalStateException("TNT client unavailable");
        if(clientWorld==null){clientWorld=client.world;playerId=client.player.getUuid();}
        if(client.world!=clientWorld||!client.player.getUuid().equals(playerId)||server!=null&&client.getServer()!=server)throw new IllegalStateException("TNT client owner changed");
    }
    public void terrain(GroundSurface next){surface=next;captureBounds=bounds(next);nextResumeScan=0;}
    public void observe(MinecraftServer source){
        if(!enabled){if(closing)serverClosed=true;return;}
        if(!source.isOnThread()||!source.getSaveProperties().getLevelName().equals(save.saveName())||server!=null&&server!=source)throw new IllegalStateException("TNT server owner changed");
        server=source;world=source.getOverworld();var owner=blocks.tntPlayerId();
        if(owner==null){if(closing){visible=Set.of();serverClosed=true;}return;}
        // A bounded spatial/type query is needed only for saved/chunk-loaded TNT;
        // new priming is admitted synchronously by the vanilla spawn hook.
        long now=System.nanoTime();var saved=new ArrayList<TntEntity>();
        if(now>=nextResumeScan){nextResumeScan=now+1_000_000_000L;world.collectEntitiesByType(TypeFilter.instanceOf(TntEntity.class),captureBounds,
            tnt->!tnt.isRemoved()&&hasOwnershipTag(tnt)&&!entities.containsKey(tnt.getUuid()),saved,GameplayTntOwnership.MAX_ACTIVE+1);}
        for(var tnt:saved){
            var tag=tagOwner(tnt);if(tag==null){fail("Malformed or contradictory TNT ownership tags");continue;}
            if(!tag.world().equals(save.id())||!tag.player().equals(owner))continue;
            if(!entities.containsKey(tnt.getUuid())){
                if(liveCount()>=GameplayTntOwnership.MAX_ACTIVE){fail("TNT saved entity capacity exceeded");break;}
                if(tnt.getOwner()!=null&&!tnt.getOwner().getUuid().equals(tag.player())){fail("TNT saved causing entity differs from ownership");break;}
                if(!covered(tnt))continue; // Paused safely until its captured coverage is admitted.
                entities.put(tnt.getUuid(),new Entry(tnt,tag.player()));resumed++;if(tnt.getOwner()==null)ownerlessResumed++;
            }
        }
        entities.entrySet().removeIf(entry->entry.getValue().entity.isRemoved());
        known=Set.copyOf(entities.keySet());
        boolean collisionReady=GroundCollision.matches(world,surface,true);var paused=new HashSet<UUID>();
        for(var entry:entities.values())if(!collisionReady||!covered(entry.entity))paused.add(entry.entity.getUuid());
        suspended=Set.copyOf(paused);
        if(closing){for(var entry:entities.values())if(!entry.paused){entry.paused=true;frozenOnStop++;}visible=Set.of();serverClosed=true;}
        else if(failure==null&&GroundCollision.matches(world,surface,true))visible=Set.copyOf(entities.keySet());
        else visible=Set.of();
    }
    public boolean canPrime(){return enabled&&!closing&&failure==null&&visible.size()<GameplayTntOwnership.MAX_ACTIVE;}
    public boolean primedAt(World world,BlockPos position,long after){
        if(!ownsWorld(world))return false;
        var receipt=lastPrime;return receipt!=null&&receipt.position().equals(position)&&receipt.at()>=after;
    }
    private record Prime(BlockPos position,long at){}
    private Prime lastPrime;
    /** Called before vanilla ignition mutates a block or consumes the held item. */
    public static boolean denyPrime(World source,BlockPos position,net.minecraft.entity.LivingEntity igniter){
        var s=active;if(s==null)return false;
        if(source.isClient)return source==s.clientWorld&&s.blocks.tntClientOwned(position)&&!s.canPrime();
        return s.blocks.tntOwnedCell(source,position)&&(!s.ownsWorld(source)||s.closing||s.failure!=null||s.liveCount()>=GameplayTntOwnership.MAX_ACTIVE||
            !GroundCollision.matches(source,s.surface,true)||s.blocks.tntIgniter(source,position,igniter)==null);
    }
    /** Wrapped at the actual vanilla spawn call, while the original TNT block is still ledger-owned. */
    public static boolean spawn(World source,BlockPos position,TntEntity tnt,Explosion chain,BooleanSupplier original){
        var s=active;if(source.isClient||s==null||!s.blocks.tntOwnedCell(source,position))return original.getAsBoolean();
        if(!s.ownsWorld(source)||s.closing||s.failure!=null||!GroundCollision.matches(source,s.surface,true)||!s.covered(tnt))return false;
        UUID owner;
        if(chain!=null){var parent=s.explosionEntry(source,chain);if(parent==null)return original.getAsBoolean();owner=parent.originalOwner;}
        else{owner=s.blocks.tntIgniter(source,position,tnt.getOwner());if(owner==null)return false;}
        if(s.liveCount()>=GameplayTntOwnership.MAX_ACTIVE){s.fail("TNT priming capacity exceeded");return false;}
        String tag=GameplayTntOwnership.tag(s.save.id(),owner);if(!tnt.addCommandTag(tag)){s.fail("TNT ownership tag refused");return false;}
        if(!original.getAsBoolean()){tnt.removeCommandTag(tag);return false;}
        s.entities.put(tnt.getUuid(),new Entry(tnt,owner));s.primed++;if(chain!=null)s.chainPrimed++;
        s.lastPrime=new Prime(position.toImmutable(),System.nanoTime());s.known=Set.copyOf(s.entities.keySet());s.visible=s.known;return true;
    }
    /** Tagged saved entities pause before their first vanilla tick, including before session attach. */
    public static boolean beforeTick(TntEntity tnt){
        var s=active;
        if(tnt.getWorld().isClient){return s!=null&&s.clientWorld==tnt.getWorld()&&s.known.contains(tnt.getUuid())&&(s.closing||s.failure!=null||s.suspended.contains(tnt.getUuid()));}
        var tag=tagOwner(tnt);if(tag==null)return hasOwnershipTag(tnt);
        if(s==null||s.closing||s.failure!=null||!s.ownsWorld(tnt.getWorld())||!tag.world().equals(s.save.id())||!tag.player().equals(s.blocks.tntPlayerId()))return true;
        var entry=s.entities.get(tnt.getUuid());if(entry==null||entry.entity!=tnt)return true;
        if(!s.covered(tnt)||!GroundCollision.matches(tnt.getWorld(),s.surface,true)){s.suspend(tnt.getUuid(),true);return true;}
        s.suspend(tnt.getUuid(),false);
        try{if(entry.ground){s.recoverGround(entry);entry.ground=false;}return false;}
        catch(Exception error){s.fail(error.toString());return true;}
    }
    private void recoverGround(Entry entry){
        var tnt=entry.entity;var box=tnt.getBoundingBox();double radius=Math.max(box.getLengthX(),box.getLengthZ())/2;
        double floor=surface.groundForFeet(tnt.getX(),tnt.getZ(),radius),lift=floor-box.minY;
        if(!Double.isFinite(floor)||lift<=.000001||lift>.999)return;
        // Vanilla priming uses the integer block's bottom. A fractional native
        // surface may intersect it; move only this fresh entity to the same floor,
        // without modifying its velocity/fuse or passing through any real block.
        var destination=box.offset(0,lift+.00001,0);if(!world.isSpaceEmpty(tnt,destination))return;
        var swept=box.stretch(0,lift+.00001,0);var context=net.minecraft.block.ShapeContext.of(tnt);
        for(var pos:BlockPos.iterate((int)Math.floor(swept.minX),(int)Math.floor(swept.minY),(int)Math.floor(swept.minZ),(int)Math.floor(swept.maxX),(int)Math.floor(swept.maxY),(int)Math.floor(swept.maxZ))){
            if(!world.isChunkLoaded(pos))return;var shape=world.getBlockState(pos).getCollisionShape(world,pos,context);
            for(var obstacle:shape.getBoundingBoxes())if(obstacle.offset(pos).intersects(swept))return;
        }
        tnt.setPosition(tnt.getX(),tnt.getY()+lift+.00001,tnt.getZ());groundRecoveries++;
    }
    /** affectWorld follows vanilla entity damage. Filter before onExploded removes or chain-primes blocks. */
    public static void beforeAffectWorld(World source,Explosion explosion){
        var s=active;if(s==null||source.isClient||!s.ownsWorld(source))return;
        boolean admitted=s.explosionEntry(source,explosion)!=null;
        int chainSlots=GameplayTntOwnership.MAX_ACTIVE-s.liveCount();
        var affected=explosion.getAffectedBlocks();
        GameplayTntOwnership.filterAffected(affected,admitted,chainSlots,
            position->s.blocks.tntOwnedCell(source,position,false),position->source.getBlockState(position).isOf(Blocks.TNT));
        if(admitted){s.explosions++;s.affectedOwnedBlocks+=affected.size();}
    }
    private Entry explosionEntry(World source,Explosion explosion){
        if(!ownsWorld(source)||!(explosion.getEntity() instanceof TntEntity tnt)||tnt.getWorld()!=source)return null;
        // TntEntity.tick deliberately discards itself immediately BEFORE explode().
        var entry=entities.get(tnt.getUuid());return entry!=null&&entry.entity==tnt?entry:null;
    }
    public static UUID explosionOwner(TntEntity tnt){
        var s=active;if(s==null||s.closing||s.failure!=null||!s.ownsWorld(tnt.getWorld()))return null;
        var entry=s.entities.get(tnt.getUuid());var owner=tagOwner(tnt);
        return entry!=null&&entry.entity==tnt&&owner!=null&&owner.world().equals(s.save.id())&&owner.player().equals(entry.originalOwner)?entry.originalOwner:null;
    }
    public static boolean renderAllowed(TntEntity tnt){
        var s=active;var c=MinecraftClient.getInstance();return s!=null&&!s.closing&&s.failure==null&&c.isOnThread()&&c.world==s.clientWorld&&tnt.getWorld()==c.world&&
            c.getServer()==s.server&&c.player!=null&&c.player.getUuid().equals(s.playerId)&&!tnt.isRemoved()&&s.visible.contains(tnt.getUuid());
    }
    private boolean ownsWorld(World source){return enabled&&server!=null&&server.isOnThread()&&world==source&&source instanceof ServerWorld;}
    private boolean covered(TntEntity tnt){var box=tnt.getBoundingBox();return surface.containsFeet(tnt.getX(),tnt.getZ(),Math.max(box.getLengthX(),box.getLengthZ())/2)&&Double.isFinite(tnt.getY());}
    private int liveCount(){return (int)entities.values().stream().filter(e->!e.entity.isRemoved()).count();}
    private void suspend(UUID id,boolean value){if(suspended.contains(id)==value)return;var next=new HashSet<>(suspended);if(value)next.add(id);else next.remove(id);suspended=Set.copyOf(next);}
    private static GameplayTntOwnership.Owner tagOwner(TntEntity tnt){return GameplayTntOwnership.owner(tnt.getCommandTags());}
    private static boolean hasOwnershipTag(TntEntity tnt){return tnt.getCommandTags().stream().anyMatch(GameplayTntOwnership::managed);}
    private static Box bounds(GroundSurface surface){
        if(surface.cells().isEmpty())return new Box(-.5,-2048,-.5,.5,2048,.5);
        int minX=Integer.MAX_VALUE,minZ=Integer.MAX_VALUE,maxX=Integer.MIN_VALUE,maxZ=Integer.MIN_VALUE;
        for(var cell:surface.cells()){minX=Math.min(minX,cell.x());minZ=Math.min(minZ,cell.z());maxX=Math.max(maxX,cell.x()+1);maxZ=Math.max(maxZ,cell.z()+1);}
        return new Box(minX,-2048,minZ,maxX,2048,maxZ);
    }
    private void fail(String reason){failure=reason;visible=Set.of();}
    public String failure(){return failure;}
    public void close(){closing=true;GameplayBlasts.ownershipStopped(save.id());if(server==null){visible=Set.of();serverClosed=true;}}
    public boolean cleanupComplete(){return closing&&serverClosed;}
    public JsonObject evidence(){var j=new JsonObject();j.addProperty("enabled",enabled);j.addProperty("primed",primed);j.addProperty("chain_primed",chainPrimed);j.addProperty("explosions",explosions);j.addProperty("active",visible.size());j.addProperty("paused_fuses",suspended.size());j.addProperty("resumed",resumed);j.addProperty("ownerless_resumed",ownerlessResumed);j.addProperty("frozen_on_stop",frozenOnStop);j.addProperty("ground_recoveries",groundRecoveries);j.addProperty("affected_owned_blocks",affectedOwnedBlocks);j.addProperty("cleanup_complete",cleanupComplete());j.addProperty("failure",failure);return j;}
}
