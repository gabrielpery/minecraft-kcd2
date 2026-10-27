package dev.minecome.terrain;

import java.util.TreeSet;

/** A conservative input gate, never a movement integrator or position writer. */
final class HudMovementBoundary {
    // Inspected pinned Yarn1.21.1 LivingEntity.travel/getMovementSpeed and
    // Entity.movementInputToVelocity: acceleration precedes movement; stored
    // velocity has already had 0.6f*0.91f ground or 0.91f air drag applied.
    // Round upwards so the envelope also covers float/trigonometric rounding.
    static final double GROUND_DRAG=.546001,AIR_DRAG=.910001;
    static final double FOOT=.29,PAD=.02,RADIUS=1.75,MIN_Y=-1.45,MAX_Y=1.45;
    record Decision(boolean allow,String reason,boolean flat,double minGround,double maxGround,double reach) {}
    private record Rect(double minX,double maxX,double minZ,double maxZ) {}
    private record Heights(double min,double max) {}
    private final GroundPatch patch;
    private final MovementTraceSink.Motion anchor;

    HudMovementBoundary(GroundPatch patch,MovementTraceSink.Motion anchor){this.patch=patch;this.anchor=anchor;}

    Decision check(MovementTraceSink.Motion m,int forward,int sideways,boolean jump,double yaw,
                   double acceleration,double jumpVelocity,boolean sprintJump){
        if(!Double.isFinite(yaw) || !Double.isFinite(acceleration) || acceleration<=0 || acceleration>.25 ||
                !Double.isFinite(jumpVelocity) || jumpVelocity<0 || jumpVelocity>.6 ||
                Math.abs(forward)>1 || Math.abs(sideways)>1)return reject("unsupported_movement_parameters");
        double length=Math.max(1,Math.hypot(forward,sideways)),angle=Math.toRadians(yaw);
        double ax=(sideways*Math.cos(angle)-forward*Math.sin(angle))*acceleration/length;
        double az=(forward*Math.cos(angle)+sideways*Math.sin(angle))*acceleration/length;
        // LivingEntity.jump adds this impulse when sprinting. Reserve it even
        // for a possible same-tick sprint transition before vanilla polls W.
        double kx=0,kz=0;
        if(jump && m.onGround() && sprintJump){kx=-Math.sin(angle)*.200001;kz=Math.cos(angle)*.200001;}
        boolean jumping=jump && m.onGround();
        double peak=m.y()+rise(jumping?Math.max(m.vy(),jumpVelocity):m.vy());
        Rect ground=rectangle(m,ax,az,kx,kz,1/(1-GROUND_DRAG));
        Heights flatHeights=heights(ground);
        boolean flat=m.onGround() && !jumping && m.vy()<=0 && flatHeights!=null &&
                Math.abs(flatHeights.min()-m.y())<1e-6 && Math.abs(flatHeights.max()-m.y())<1e-6;
        // Over any change in support, allow an arbitrarily long airborne coast.
        // This is deliberately more conservative than predicting a landing.
        // A flat supported corridor can use the exact, shorter ground coast.
        double factor=flat?1/(1-GROUND_DRAG):1+(m.onGround()&&!jumping?GROUND_DRAG:AIR_DRAG)/(1-AIR_DRAG);
        Rect corridor=flat?ground:rectangle(m,ax,az,kx,kz,factor);
        Heights heights=flat?flatHeights:heights(corridor);
        if(heights==null)return reject("sampled_footprint_braking_clearance");
        double bottom=Math.min(m.y(),heights.min()),top=Math.max(peak,heights.max());
        if(bottom-anchor.y()<MIN_Y)return reject("downhill_braking_clearance",flat,heights,0);
        if(top-anchor.y()>MAX_Y)return reject("vertical_braking_clearance",flat,heights,0);
        double dx=Math.max(Math.abs(corridor.minX()-anchor.x()),Math.abs(corridor.maxX()-anchor.x()));
        double dz=Math.max(Math.abs(corridor.minZ()-anchor.z()),Math.abs(corridor.maxZ()-anchor.z()));
        double dy=Math.max(Math.abs(bottom-anchor.y()),Math.abs(top-anchor.y()));
        double reach=Math.sqrt(dx*dx+dy*dy+dz*dz);
        if(reach>RADIUS)return reject("sphere_braking_clearance",flat,heights,reach);
        return new Decision(true,"clear",flat,heights.min(),heights.max(),reach);
    }
    private static Rect rectangle(MovementTraceSink.Motion m,double ax,double az,double kx,double kz,double factor){
        // Include no acceleration through full next-tick acceleration and both
        // axis orders: clipping against a slab can remove either component.
        // Acceleration and a possible jump impulse are separate intervals;
        // summing their maxima first could cancel opposite directions and
        // underestimate a smaller actual input's resulting displacement.
        double x0=m.x()+(m.vx()+Math.min(0,ax)+Math.min(0,kx))*factor;
        double x1=m.x()+(m.vx()+Math.max(0,ax)+Math.max(0,kx))*factor;
        double z0=m.z()+(m.vz()+Math.min(0,az)+Math.min(0,kz))*factor;
        double z1=m.z()+(m.vz()+Math.max(0,az)+Math.max(0,kz))*factor;
        return new Rect(Math.min(m.x(),Math.min(x0,x1))-PAD,Math.max(m.x(),Math.max(x0,x1))+PAD,
                Math.min(m.z(),Math.min(z0,z1))-PAD,Math.max(m.z(),Math.max(z0,z1))+PAD);
    }
    private Heights heights(Rect r){
        if(!patch.containsFeet(r.minX(),r.minZ(),.4) || !patch.containsFeet(r.maxX(),r.maxZ(),.4))return null;
        var xs=new TreeSet<Double>();var zs=new TreeSet<Double>();
        xs.add(r.minX());xs.add(r.maxX());zs.add(r.minZ());zs.add(r.maxZ());
        // groundForFeet is piecewise constant. Evaluate both sides and the
        // exact value at every support transition; endpoint-only checks miss
        // a lower strip between two safe endpoints.
        for(var slab:patch.slabs()){
            transition(xs,slab.minX()-FOOT,r.minX(),r.maxX());transition(xs,slab.maxX()+FOOT,r.minX(),r.maxX());
            transition(zs,slab.minZ()-FOOT,r.minZ(),r.maxZ());transition(zs,slab.maxZ()+FOOT,r.minZ(),r.maxZ());
        }
        double min=Double.POSITIVE_INFINITY,max=Double.NEGATIVE_INFINITY;
        for(double x:xs)for(double z:zs){double height=patch.groundForFeet(x,z,FOOT);min=Math.min(min,height);max=Math.max(max,height);}
        return new Heights(min,max);
    }
    private static void transition(TreeSet<Double> values,double point,double min,double max){
        for(double p:new double[]{point-1e-7,point,point+1e-7})if(p>min && p<max)values.add(p);
    }
    // Pinned vanilla gravity/vertical drag, used only as an upper-height bound.
    // Real jumping, collision, position and velocity remain entirely vanilla.
    private static double rise(double velocity){
        double height=0;
        for(int i=0;i<32 && velocity>0;i++){height+=velocity;velocity=(velocity-.08)*.98000002;}
        return height;
    }
    private static Decision reject(String reason){return new Decision(false,reason,false,Double.NaN,Double.NaN,0);}
    private static Decision reject(String reason,boolean flat,Heights h,double reach){return new Decision(false,reason,flat,h.min(),h.max(),reach);}
}
