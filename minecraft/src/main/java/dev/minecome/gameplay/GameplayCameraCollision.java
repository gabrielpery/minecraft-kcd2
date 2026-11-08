package dev.minecome.gameplay;

import com.google.gson.JsonObject;
import dev.minecome.terrain.GroundPatch;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Box;
import net.minecraft.util.shape.VoxelShape;
import java.util.*;

/** Immutable, bounded camera geometry produced on the owning server thread.
 * Pinned Yarn 1.21.1 Camera.clipToSpace uses VISUAL / getCameraCollisionShape,
 * with eight rays offset by 0.1m. Inspected bytecode is recorded under
 * runtime/evidence/camera-collision-source-20261108. These are those actual voxel
 * boxes, not full-cell/player collision approximations. Native code applies the
 * camera clearance and clips its current look ray against the committed set. */
public final class GameplayCameraCollision {
    public static final int MAX_BOXES=512,HEX_CHARS_PER_BOX=24;
    private static final double GRID=16,GRID_EPSILON=1e-7;
    private static final char[] HEX="0123456789abcdef".toCharArray();
    public record Snapshot(long generation,boolean complete,String boxes) {
        public Snapshot {
            if(generation<1||generation>10_000_000||boxes==null||boxes.length()>MAX_BOXES*HEX_CHARS_PER_BOX||
                    boxes.length()%HEX_CHARS_PER_BOX!=0||!boxes.matches("[0-9a-f]*")||(!complete&&!boxes.isEmpty()))
                throw new IllegalArgumentException("Invalid camera collision snapshot");
        }
        public JsonObject json(GroundSurface surface){
            var j=new JsonObject();j.addProperty("generation",generation);j.addProperty("complete",complete);j.addProperty("boxes",boxes);
            // MC (x,y,z) becomes native (origin.x+x, origin.y-z, origin.z+y).
            var origin=new JsonObject();origin.addProperty("x",surface.centerX());origin.addProperty("y",surface.centerY());
            origin.addProperty("z",surface.centerZ()-GroundPatch.ANCHOR_Y);j.add("origin",origin);return j;
        }
    }
    private record QuantizedBox(int x0,int y0,int z0,int x1,int y1,int z1) implements Comparable<QuantizedBox> {
        @Override public int compareTo(QuantizedBox b){
            int value=Integer.compare(x0,b.x0);if(value!=0)return value;value=Integer.compare(y0,b.y0);if(value!=0)return value;
            value=Integer.compare(z0,b.z0);if(value!=0)return value;value=Integer.compare(x1,b.x1);if(value!=0)return value;
            value=Integer.compare(y1,b.y1);return value!=0?value:Integer.compare(z1,b.z1);
        }
        void append(StringBuilder out){for(int n:new int[]{x0,y0,z0,x1,y1,z1}){int bits=n&0xffff;for(int shift=12;shift>=0;shift-=4)out.append(HEX[(bits>>>shift)&15]);}}
    }
    private Snapshot latest;
    /** The caller must supply only current, server-confirmed owned states.
     * Any incomplete/unsupported set collapses the native orbit, never truncates
     * obstacles. Recomputing shapes also catches context-dependent changes that
     * do not replace the immutable ledger map. Unchanged bytes reuse a snapshot. */
    public Snapshot capture(Map<BlockPos,VoxelShape> shapes){
        if(shapes==null||shapes.size()>GameplayBlocksLedger.MAX_BLOCKS)return unavailable();
        try{
            var boxes=new TreeSet<QuantizedBox>();
            for(var entry:shapes.entrySet()){
                if(entry.getKey()==null||entry.getValue()==null)return unavailable();
                for(var box:entry.getValue().getBoundingBoxes()){
                    boxes.add(quantize(box.offset(entry.getKey())));
                    if(boxes.size()>MAX_BOXES)return unavailable();
                }
            }
            var encoded=new StringBuilder(boxes.size()*HEX_CHARS_PER_BOX);for(var box:boxes)box.append(encoded);
            return publish(true,encoded.toString());
        }catch(IllegalArgumentException invalid){return unavailable();}
    }
    public Snapshot unavailable(){return publish(false,"");}
    private Snapshot publish(boolean complete,String boxes){
        if(latest!=null&&latest.complete()==complete&&latest.boxes().equals(boxes))return latest;
        latest=new Snapshot(latest==null?1:latest.generation()+1,complete,boxes);return latest;
    }
    private static QuantizedBox quantize(Box box){
        int x0=coordinate(box.minX),y0=coordinate(box.minY),z0=coordinate(box.minZ),x1=coordinate(box.maxX),y1=coordinate(box.maxY),z1=coordinate(box.maxZ);
        if(x0>=x1||y0>=y1||z0>=z1||x1-x0>32||y1-y0>32||z1-z0>32)throw new IllegalArgumentException("Empty or oversized camera box");return new QuantizedBox(x0,y0,z0,x1,y1,z1);
    }
    private static int coordinate(double value){
        double scaled=value*GRID,rounded=Math.rint(scaled);
        if(!Double.isFinite(scaled)||Math.abs(scaled-rounded)>GRID_EPSILON||rounded<Short.MIN_VALUE||rounded>Short.MAX_VALUE)
            throw new IllegalArgumentException("Camera shape outside exact signed-sixteenth grid");
        return (int)rounded;
    }
}
