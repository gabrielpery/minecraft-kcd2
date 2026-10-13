package dev.minecome.protocol;

import java.util.*;
import dev.minecome.protocol.Protocol.Vec3;
import dev.minecome.protocol.Protocol.Quaternion;

/** Pure display-island geometry. It grants no gameplay, calibration or wire capability. */
public final class AimGeometry {
    public static final int MAX_OWNED_CELLS=16;
    public static final double MAX_COORDINATE=10_000_000, MAX_RAY_RANGE=32;
    private AimGeometry() {}
    public enum Face { DOWN, UP, NORTH, SOUTH, WEST, EAST, INSIDE }
    public record Alignment(Vec3 minecraftAnchor,Vec3 kcdAnchor,double blocksPerUnit) {
        public Alignment {position(minecraftAnchor);position(kcdAnchor);positive(blocksPerUnit);}
        public Vec3 toKcd(Vec3 p) {
            position(p);return position(new Vec3(kcdAnchor.x()+(p.x()-minecraftAnchor.x())/blocksPerUnit,
                    kcdAnchor.y()-(p.z()-minecraftAnchor.z())/blocksPerUnit,kcdAnchor.z()+(p.y()-minecraftAnchor.y())/blocksPerUnit));
        }
        public Vec3 toMinecraft(Vec3 p) {
            position(p);return position(new Vec3(minecraftAnchor.x()+(p.x()-kcdAnchor.x())*blocksPerUnit,
                    minecraftAnchor.y()+(p.z()-kcdAnchor.z())*blocksPerUnit,minecraftAnchor.z()-(p.y()-kcdAnchor.y())*blocksPerUnit));
        }
        public Ray toMinecraft(Ray ray) {
            var d=ray.direction();return new Ray(toMinecraft(ray.origin()),new Vec3(d.x(),d.z(),-d.y()),ray.range()*blocksPerUnit);
        }
        public Ray toKcd(Ray ray) {
            var d=ray.direction();return new Ray(toKcd(ray.origin()),new Vec3(d.x(),-d.z(),d.y()),ray.range()/blocksPerUnit);
        }
    }
    public record Ray(Vec3 origin,Vec3 direction,double range) {
        public Ray {
            position(origin);Objects.requireNonNull(direction);positive(range);
            double norm=dot(direction,direction);
            if(!Double.isFinite(norm)||Math.abs(norm-1)>1e-9||range>MAX_RAY_RANGE)throw new IllegalArgumentException("Non-unit/bounded aim ray");
            position(add(origin,direction,range));
        }
    }
    public record Bounds(Vec3 minimum,Vec3 maximum) {
        public Bounds {position(minimum);position(maximum);if(minimum.x()>=maximum.x()||minimum.y()>=maximum.y()||minimum.z()>=maximum.z())throw new IllegalArgumentException("Empty aim bounds");}
    }
    public record Cell(int x,int y,int z) {
        public Bounds bounds(){return new Bounds(new Vec3(x,y,z),new Vec3((double)x+1,(double)y+1,(double)z+1));}
    }
    public record Hit(double distance,Vec3 point,Face face) {public boolean inside(){return face==Face.INSIDE;}}
    public record Pick(Cell cell,Hit hit) {}
    /** Wire camera-local forward is -Z; no yaw/pitch or FOV approximation. */
    public static Vec3 forward(Quaternion q) {
        Objects.requireNonNull(q);
        var f=new Vec3(-2*(q.x()*q.z()+q.w()*q.y()),-2*(q.y()*q.z()-q.w()*q.x()),-(1-2*(q.x()*q.x()+q.y()*q.y())));
        double n=Math.sqrt(dot(f,f));if(!Double.isFinite(n)||n<1e-8)throw new IllegalArgumentException("Invalid camera forward");
        return new Vec3(f.x()/n,f.y()/n,f.z()/n);
    }
    /** Reference cube intersection, not a replacement for Minecraft OUTLINE raycast. */
    public static Optional<Hit> intersect(Ray ray,Bounds box) {
        Objects.requireNonNull(ray);Objects.requireNonNull(box);
        double[] origin=axes(ray.origin()),direction=axes(ray.direction()),lo=axes(box.minimum()),hi=axes(box.maximum());
        Face[] lower={Face.WEST,Face.DOWN,Face.NORTH},upper={Face.EAST,Face.UP,Face.SOUTH};
        double near=Double.NEGATIVE_INFINITY,far=ray.range();Face face=Face.INSIDE;
        for(int axis=0;axis<3;axis++){
            if(direction[axis]==0){if(origin[axis]<lo[axis]||origin[axis]>hi[axis])return Optional.empty();continue;}
            double a=(lo[axis]-origin[axis])/direction[axis],b=(hi[axis]-origin[axis])/direction[axis];Face side=lower[axis];
            if(a>b){double temp=a;a=b;b=temp;side=upper[axis];}
            if(a>near){near=a;face=side;}
            far=Math.min(far,b);if(near>far)return Optional.empty();
        }
        if(far<0||near>ray.range())return Optional.empty();
        double distance=Math.max(0,near);
        return Optional.of(new Hit(distance,add(ray.origin(),ray.direction(),distance),near<0?Face.INSIDE:face));
    }
    /** Deterministic bounded reference selection; equal-distance cells sort XYZ. */
    public static Optional<Pick> nearestOwned(Ray ray,List<Cell> cells) {
        Objects.requireNonNull(ray);Objects.requireNonNull(cells);
        if(cells.size()>MAX_OWNED_CELLS)throw new IllegalArgumentException("Owned aim-cell bound exceeded");
        var unique=new HashSet<Cell>();Pick nearest=null;
        for(var cell:cells){
            if(!unique.add(Objects.requireNonNull(cell)))throw new IllegalArgumentException("Duplicate owned aim cell");
            var hit=intersect(ray,cell.bounds());if(hit.isEmpty())continue;
            var candidate=new Pick(cell,hit.get());
            if(nearest==null||compare(candidate,nearest)<0)nearest=candidate;
        }
        return Optional.ofNullable(nearest);
    }
    private static int compare(Pick a,Pick b){int c=Double.compare(a.hit.distance,b.hit.distance);if(c==0)c=Integer.compare(a.cell.x,b.cell.x);if(c==0)c=Integer.compare(a.cell.y,b.cell.y);if(c==0)c=Integer.compare(a.cell.z,b.cell.z);return c;}
    private static double[] axes(Vec3 p){return new double[]{p.x(),p.y(),p.z()};}
    private static double dot(Vec3 a,Vec3 b){return a.x()*b.x()+a.y()*b.y()+a.z()*b.z();}
    private static Vec3 add(Vec3 p,Vec3 d,double t){return new Vec3(p.x()+d.x()*t,p.y()+d.y()*t,p.z()+d.z()*t);}
    private static void positive(double value){if(!Double.isFinite(value)||value<=0)throw new IllegalArgumentException("Expected positive finite geometry value");}
    private static Vec3 position(Vec3 p){Objects.requireNonNull(p);if(Math.abs(p.x())>MAX_COORDINATE||Math.abs(p.y())>MAX_COORDINATE||Math.abs(p.z())>MAX_COORDINATE)throw new IllegalArgumentException("Aim position out of bounds");return p;}
}
