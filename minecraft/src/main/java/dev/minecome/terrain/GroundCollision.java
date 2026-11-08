package dev.minecome.terrain;

import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Box;
import net.minecraft.util.math.Vec3d;
import net.minecraft.util.function.BooleanBiFunction;
import net.minecraft.entity.ItemEntity;
import net.minecraft.entity.MovementType;
import net.minecraft.block.ShapeContext;
import net.minecraft.server.world.ServerWorld;
import net.minecraft.util.shape.VoxelShape;
import net.minecraft.util.shape.VoxelShapes;
import net.minecraft.world.BlockView;

/** Shapes are built on each owning game thread, then published as immutable world-scoped maps. */
public final class GroundCollision {
    private record Installation(BlockView world,String run,String sha256,GroundSurface surface,Map<Long,VoxelShape> shapes,AtomicLong queries,AtomicLong itemRecoveries) {}
    private static volatile Installation client,server;
    private static final ThreadLocal<Installation> recoveringItem=new ThreadLocal<>();
    private GroundCollision() {}
    public static void install(BlockView world,GroundPatch patch,boolean serverSide) {
        var installation=prepare(world,patch);
        if(serverSide)server=installation;else client=installation;
    }
    /** A composite surface is published only after its complete map is built; it cannot replace an owner. */
    public static void install(BlockView world,GroundSurface surface,boolean serverSide) {
        if(surface instanceof GroundPatch patch){install(world,patch,serverSide);return;}
        if(!(surface instanceof GroundCorridor)&&!(surface instanceof GameplayTerrain))throw new IllegalArgumentException("Unsupported collision surface");
        var installation=prepare(world,surface);
        synchronized(GroundCollision.class){
            if((serverSide?server:client)!=null)throw new IllegalStateException("Existing collision installation preserved");
            if(serverSide)server=installation;else client=installation;
        }
    }
    /** Called on the owning world thread after controls are released for the handoff.
     * A stale owner cannot publish; old geometry is retained exactly by the verified plan.
     */
    public static synchronized boolean replace(BlockView world,GroundSurface expected,GroundSurface next,boolean serverSide) {
        Objects.requireNonNull(world);Objects.requireNonNull(expected);Objects.requireNonNull(next);
        boolean gameplay=expected instanceof GameplayTerrain before&&next instanceof GameplayTerrain after&&after.isSuccessorOf(before);
        if(!gameplay&&!GroundExpansion.isTransition(expected,next))throw new IllegalArgumentException("Only the verified additive terrain successor is supported");
        var own=serverSide?server:client;
        if(own==null || own.world()!=world || !own.run().equals(expected.run()) || !own.sha256().equals(expected.sha256()) || gameplay&&own.surface()!=expected)return false;
        var replacement=prepare(world,next);
        // Preserve lifetime query counters across generations so admission cannot
        // erase proof that the original collision map was actually consumed.
        replacement=new Installation(replacement.world(),replacement.run(),replacement.sha256(),replacement.surface(),replacement.shapes(),own.queries(),own.itemRecoveries());
        if(serverSide)server=replacement;else client=replacement;
        return true;
    }
    private static Installation prepare(BlockView world,GroundSurface patch){
        Objects.requireNonNull(world);Objects.requireNonNull(patch);
        Map<Long,VoxelShape> shapes=new HashMap<>();
        for(var cell:patch.cells()) {
            long key=BlockPos.asLong(cell.x(),cell.y(),cell.z());
            var slab=VoxelShapes.cuboid(0,cell.minY(),0,1,cell.maxY(),1);
            shapes.merge(key,slab,VoxelShapes::union);
        }
        return new Installation(world,patch.run(),patch.sha256(),patch,Map.copyOf(shapes),new AtomicLong(),new AtomicLong());
    }
    /** Minimal bounded upward recovery for a dropped item embedded by fractional
     * terrain. A newly mined stack may spawn anywhere inside its integer block,
     * including wholly below the thin slab; old nonintersecting items are untouched.
     * This geometry query does not move entities or call world APIs.
     */
    public static double itemLift(BlockView world,Box box,boolean newlySpawned){
        var own=server;
        if(own==null||own.world()!=world||box==null)return 0;
        if(!Double.isFinite(box.minX)||!Double.isFinite(box.minY)||!Double.isFinite(box.minZ)||
           !Double.isFinite(box.maxX)||!Double.isFinite(box.maxY)||!Double.isFinite(box.maxZ))return 0;
        double width=box.maxX-box.minX,height=box.maxY-box.minY,depth=box.maxZ-box.minZ;
        if(width<=0||width>.5||height<=0||height>.5||depth<=0||depth>.5)return 0;
        double x=(box.minX+box.maxX)/2,z=(box.minZ+box.maxZ)/2,radius=Math.max(width,depth)/2;
        if(!own.surface().containsFeet(x,z,radius))return 0;
        double floor=own.surface().groundForFeet(x,z,radius),lift=floor-box.minY;
        if(!Double.isFinite(floor)||lift<=.000001||lift>.999)return 0;
        boolean intersects=false;
        for(var slab:own.surface().slabs())if(box.maxX>slab.minX()&&box.minX<slab.maxX()&&box.maxZ>slab.minZ()&&box.minZ<slab.maxZ()&&
                box.maxY>slab.minY()&&box.minY<slab.maxY()){intersects=true;break;}
        if(!intersects&&(!newlySpawned||box.minY<Math.floor(floor)||box.maxY<=Math.floor(floor)))return 0;
        return lift+.00001;
    }
    /** Server-authoritative collision recovery; vanilla retains item identity,
     * stack, gravity, velocity, pickup delay and inventory transfer.
     * Inspected Yarn1.21.1 ItemEntity.tick sets noClip from isSpaceEmpty, then
     * pushOutOfBlocks consults real block states (Air for our injected terrain).
     * Recover before that path using Entity.move, not a teleport/spawn replacement.
     */
    public static void recoverItem(ItemEntity item){
        if(!(item.getWorld() instanceof ServerWorld world)||!world.getServer().isOnThread()||item.isRemoved())return;
        var own=server;if(own==null||own.world()!=world)return;
        var box=item.getBoundingBox();double lift=itemLift(world,box,item.getItemAge()>=0&&item.getItemAge()<=1);
        if(lift==0)return;
        var destination=box.offset(0,lift,0);var swept=box.stretch(0,lift,0);
        if(!world.isSpaceEmpty(item,destination))return;
        // Direct block-state shape calls intentionally exclude our spliterator
        // wrapper. Refuse any real block obstruction throughout the upward sweep.
        var sweptShape=VoxelShapes.cuboid(swept);var context=ShapeContext.of(item);
        for(int x=(int)Math.floor(swept.minX);x<(int)Math.ceil(swept.maxX);x++)
            for(int z=(int)Math.floor(swept.minZ);z<(int)Math.ceil(swept.maxZ);z++)
                for(int y=(int)Math.floor(swept.minY);y<(int)Math.ceil(swept.maxY);y++){
                    var pos=new BlockPos(x,y,z);if(!world.isChunkLoaded(pos))return;
                    var shape=world.getBlockState(pos).getCollisionShape(world,pos,context);
                    if(!shape.isEmpty()&&VoxelShapes.matchesAnywhere(shape.offset(x,y,z),sweptShape,BooleanBiFunction.AND))return;
                }
        if(recoveringItem.get()!=null)return;
        double before=item.getY();boolean oldNoClip=item.noClip;
        // A fresh drop wholly below the thin slab would otherwise hit its
        // underside. Exclude only this installation during this bounded move;
        // vanilla real-block collisions remain active and were checked above.
        try{recoveringItem.set(own);item.noClip=false;item.move(MovementType.SELF,new Vec3d(0,lift,0));}
        finally{item.noClip=oldNoClip;recoveringItem.remove();}
        if(item.getY()>=before+lift-.000001)own.itemRecoveries().incrementAndGet();
    }
    public static long itemRecoveries(boolean serverSide){var own=serverSide?server:client;return own==null?0:own.itemRecoveries().get();}
    public static VoxelShape merge(BlockView world,BlockPos pos,VoxelShape original) {
        Installation own=client;
        if(own==null || own.world()!=world)own=server;
        if(own==null || own.world()!=world)return original;
        if(recoveringItem.get()==own)return original;
        VoxelShape slab=own.shapes().get(pos.asLong());
        if(slab==null)return original;
        own.queries().incrementAndGet();
        return original.isEmpty()?slab:VoxelShapes.union(original,slab);
    }
    public static boolean installed(BlockView world,boolean serverSide) {
        var own=serverSide?server:client;return own!=null && own.world()==world;
    }
    public static boolean matches(BlockView world,GroundPatch patch,boolean serverSide) {
        return matches(world,(GroundSurface)patch,serverSide);
    }
    public static boolean matches(BlockView world,GroundSurface patch,boolean serverSide) {
        var own=serverSide?server:client;
        return own!=null && own.world()==world && own.run().equals(patch.run()) && own.sha256().equals(patch.sha256()) && (!(patch instanceof GameplayTerrain)||own.surface()==patch);
    }
    public static long queries(boolean serverSide){var own=serverSide?server:client;return own==null?0:own.queries().get();}
    public static boolean available(boolean serverSide){return (serverSide?server:client)==null;}
    /** A fixture may release only the installation it created, on that world's owning thread. */
    public static boolean clear(BlockView world,String run,boolean serverSide) {
        var own=serverSide?server:client;
        if(own==null || own.world()!=world || !own.run().equals(run))return false;
        if(serverSide)server=null;else client=null;
        return true;
    }
    /** Exact composite owner release, including its immutable manifest digest. */
    public static synchronized boolean clear(BlockView world,String run,String sha256,boolean serverSide) {
        var own=serverSide?server:client;
        if(own==null||own.world()!=world||!own.run().equals(run)||!own.sha256().equals(sha256))return false;
        if(serverSide)server=null;else client=null;
        return true;
    }
    public static void clear(){client=null;server=null;}
}
