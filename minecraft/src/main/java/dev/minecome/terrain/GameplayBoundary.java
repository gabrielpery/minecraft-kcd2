package dev.minecome.terrain;

/** Vanilla braking-envelope admission over actual sampled coverage, without lab anchor limits. */
final class GameplayBoundary {
    record Motion(double x,double y,double z,double vx,double vy,double vz,boolean ground){}
    private final GroundSurface surface;
    GameplayBoundary(GroundSurface surface){this.surface=surface;}
    boolean allows(Motion m,int forward,int side,boolean jump,double yaw,double acceleration){
        if(!Double.isFinite(acceleration)||acceleration<=0||acceleration>.25)return false;
        double a=Math.toRadians(yaw),length=Math.max(1,Math.hypot(forward,side));
        double ax=(side*Math.cos(a)-forward*Math.sin(a))*acceleration/length;
        double az=(forward*Math.cos(a)+side*Math.sin(a))*acceleration/length;
        // The long air coast bounds downhill transitions and a possible sprint jump.
        double factor=1/(1-.910001),kx=jump?-.200001*Math.sin(a):0,kz=jump?.200001*Math.cos(a):0;
        double minX=Math.min(m.x(),m.x()+(m.vx()+Math.min(0,ax)+Math.min(0,kx))*factor)-.02;
        double maxX=Math.max(m.x(),m.x()+(m.vx()+Math.max(0,ax)+Math.max(0,kx))*factor)+.02;
        double minZ=Math.min(m.z(),m.z()+(m.vz()+Math.min(0,az)+Math.min(0,kz))*factor)-.02;
        double maxZ=Math.max(m.z(),m.z()+(m.vz()+Math.max(0,az)+Math.max(0,kz))*factor)+.02;
        if(surface instanceof GameplayTerrain terrain)return terrain.containsRectangle(minX-.31,minZ-.31,maxX+.31,maxZ+.31);
        return surface.containsFeet(minX,minZ,.31)&&surface.containsFeet(maxX,maxZ,.31);
    }
}
