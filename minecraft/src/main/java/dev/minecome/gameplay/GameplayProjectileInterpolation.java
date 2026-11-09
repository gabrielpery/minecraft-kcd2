package dev.minecome.gameplay;

import java.util.ArrayDeque;
import java.util.List;

/** Presentation only: playback stays on consecutive confirmed segments. No velocity extrapolation. */
public final class GameplayProjectileInterpolation {
    private static final long MIN_SEGMENT_NS=16_000_000L,MAX_PLAYBACK_NS=100_000_000L,MAX_CONFIRMATION_GAP_NS=300_000_000L;
    public record Point(double x,double y,double z){
        public Point{if(!Double.isFinite(x)||!Double.isFinite(y)||!Double.isFinite(z))throw new IllegalArgumentException("Nonfinite projectile presentation");}
        double distanceSquared(Point b){double dx=x-b.x,dy=y-b.y,dz=z-b.z;return dx*dx+dy*dy+dz*dz;}
        Point lerp(Point b,double t){return new Point(x+(b.x-x)*t,y+(b.y-y)*t,z+(b.z-z)*t);}
    }
    public record Sample(int segment,long at,Point point){}
    public record Frame(Point point,boolean intermediate){}
    private record Segment(Point from,Point to,long start,long end){}
    private final ArrayDeque<Segment> playback=new ArrayDeque<>();
    private Sample latest;private Point held;private long lastNow;

    public Frame frame(List<Sample> confirmed,long now){
        if(confirmed.isEmpty())throw new IllegalArgumentException("Missing confirmed projectile position");
        var newest=confirmed.getLast();
        if(latest==null||now<lastNow||newest.segment()<latest.segment())return reset(newest,now);
        lastNow=now;advance(now);
        if(newest.segment()==latest.segment()){
            if(!newest.equals(latest))return reset(newest,now);
            return current(now);
        }
        for(var sample:confirmed){
            if(sample.segment()<=latest.segment())continue;
            long gap=sample.at()-latest.at();double distance=sample.point().distanceSquared(latest.point());
            if(sample.segment()!=latest.segment()+1||gap<=0||gap>MAX_CONFIRMATION_GAP_NS||distance>16.00000001)return reset(newest,now);
            if(distance>1e-16){
                long start=playback.isEmpty()?now:Math.max(now,playback.getLast().end());
                long end=start+Math.max(MIN_SEGMENT_NS,Math.min(MAX_PLAYBACK_NS,gap));
                if(end-now>MAX_PLAYBACK_NS)return reset(newest,now);
                playback.addLast(new Segment(latest.point(),sample.point(),start,end));
            }
            latest=sample;
        }
        return current(now);
    }
    public void clear(){latest=null;held=null;playback.clear();lastNow=0;}
    private Frame reset(Sample sample,long now){playback.clear();latest=sample;held=sample.point();lastNow=now;return new Frame(held,false);}
    private void advance(long now){while(!playback.isEmpty()&&now>=playback.getFirst().end())held=playback.removeFirst().to();}
    private Frame current(long now){
        if(playback.isEmpty())return new Frame(held,false);
        var s=playback.getFirst();double t=Math.max(0,Math.min(1,(double)(now-s.start())/(s.end()-s.start())));
        return new Frame(s.from().lerp(s.to(),t),t>0&&t<1);
    }
}
