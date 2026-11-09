package dev.minecome.gameplay;

import java.util.*;
import java.util.function.Predicate;
import static dev.minecome.gameplay.GameplayCombatProtocol.Point;

/** Pinned Explosion.getExposure lattice, preserving its double loop order and offsets. */
public final class GameplayBlastExposure {
    private GameplayBlastExposure(){}
    public static List<Point> samples(double minX,double minY,double minZ,double maxX,double maxY,double maxZ){
        double w=maxX-minX,h=maxY-minY,d=maxZ-minZ;
        if(!Double.isFinite(minX+minY+minZ+maxX+maxY+maxZ)||w<=0||h<=0||d<=0||w>4||h>8||d>4)throw new IllegalArgumentException("Blast actor bounds");
        double dx=1/(w*2+1),dy=1/(h*2+1),dz=1/(d*2+1),ox=(1-Math.floor(1/dx)*dx)/2,oz=(1-Math.floor(1/dz)*dz)/2;
        var result=new ArrayList<Point>();
        for(double x=0;x<=1;x+=dx)for(double y=0;y<=1;y+=dy)for(double z=0;z<=1;z+=dz){
            if(result.size()>=128)throw new IllegalArgumentException("Blast actor exposure capacity exceeded");
            result.add(new Point(minX+x*w+ox,minY+y*h,minZ+z*d+oz));
        }
        return List.copyOf(result);
    }
    public static float combine(List<Point> samples,String nativeMask,Predicate<Point> minecraftClear){
        if(samples.isEmpty()||samples.size()>128||nativeMask==null||nativeMask.length()!=samples.size()||!nativeMask.matches("[01]+"))throw new IllegalArgumentException("Blast exposure mask differs from vanilla lattice");
        int visible=0;for(int i=0;i<samples.size();i++)if(nativeMask.charAt(i)=='1'&&minecraftClear.test(samples.get(i)))visible++;
        return (float)visible/(float)samples.size();
    }
}
