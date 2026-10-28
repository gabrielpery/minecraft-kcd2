package dev.minecome.hud;

import dev.minecome.protocol.AimGeometry;
import dev.minecome.protocol.Protocol.Vec3;

/** Pure immutable-anchor checks; freshness and neutral controls remain caller requirements. */
final class HudWalkingAimGate {
    static final long ACTIVE_NS=12_000_000_000L,DRAIN_NS=3_000_000_000L;
    private HudWalkingAimGate(){}
    static boolean cutoff(long began,long now){return began>=0 && (now<began || now-began>=ACTIVE_NS);}
    static boolean aligned(AimGeometry.Alignment alignment,Vec3 initialFeet,Vec3 initialHostPlayer,
                           Vec3 hostPlayer,Vec3 hostCamera,Vec3 guestFeet,Vec3 guestEye){
        if(alignment==null || !finite(initialFeet) || !finite(initialHostPlayer) || !finite(hostPlayer)
                || !finite(hostCamera) || !finite(guestFeet) || !finite(guestEye))return false;
        var mappedFeet=new Vec3(initialFeet.x()+hostPlayer.x()-initialHostPlayer.x(),
                initialFeet.y()+hostPlayer.z()-initialHostPlayer.z(),initialFeet.z()-(hostPlayer.y()-initialHostPlayer.y()));
        return distance(mappedFeet,guestFeet)<=.05 && distance(alignment.toMinecraft(hostCamera),guestEye)<=.25;
    }
    private static boolean finite(Vec3 p){return p!=null && Double.isFinite(p.x()) && Double.isFinite(p.y()) && Double.isFinite(p.z());}
    private static double distance(Vec3 a,Vec3 b){return Math.sqrt(Math.pow(a.x()-b.x(),2)+Math.pow(a.y()-b.y(),2)+Math.pow(a.z()-b.z(),2));}
}
