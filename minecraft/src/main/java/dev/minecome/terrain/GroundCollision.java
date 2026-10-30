package dev.minecome.terrain;

import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.shape.VoxelShape;
import net.minecraft.util.shape.VoxelShapes;
import net.minecraft.world.BlockView;

/** Shapes are built on each owning game thread, then published as immutable world-scoped maps. */
public final class GroundCollision {
    private record Installation(BlockView world,String run,String sha256,Map<Long,VoxelShape> shapes,AtomicLong queries) {}
    private static volatile Installation client,server;
    private GroundCollision() {}
    public static void install(BlockView world,GroundPatch patch,boolean serverSide) {
        var installation=prepare(world,patch);
        if(serverSide)server=installation;else client=installation;
    }
    /** A composite surface is published only after its complete map is built; it cannot replace an owner. */
    public static void install(BlockView world,GroundSurface surface,boolean serverSide) {
        if(surface instanceof GroundPatch patch){install(world,patch,serverSide);return;}
        if(!(surface instanceof GroundCorridor))throw new IllegalArgumentException("Unsupported collision surface");
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
        if(!GroundExpansion.isTransition(expected,next))throw new IllegalArgumentException("Only the verified additive terrain successor is supported");
        var own=serverSide?server:client;
        if(own==null || own.world()!=world || !own.run().equals(expected.run()) || !own.sha256().equals(expected.sha256()))return false;
        var replacement=prepare(world,next);
        // Preserve lifetime query counters across generations so admission cannot
        // erase proof that the original collision map was actually consumed.
        replacement=new Installation(replacement.world(),replacement.run(),replacement.sha256(),replacement.shapes(),own.queries());
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
        return new Installation(world,patch.run(),patch.sha256(),Map.copyOf(shapes),new AtomicLong());
    }
    public static VoxelShape merge(BlockView world,BlockPos pos,VoxelShape original) {
        Installation own=client;
        if(own==null || own.world()!=world)own=server;
        if(own==null || own.world()!=world)return original;
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
        return own!=null && own.world()==world && own.run().equals(patch.run()) && own.sha256().equals(patch.sha256());
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
