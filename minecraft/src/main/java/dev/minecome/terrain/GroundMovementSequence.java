package dev.minecome.terrain;

/** Decisions from actual observations, not a replacement movement or collision simulation. */
final class GroundMovementSequence {
    enum Phase { SETTLING,WALKING,RESTING,JUMPING,LANDING,RETURNING,RETURN_REST,PASSED,FAILED }
    record Motion(double x,double y,double z,double vx,double vy,double vz,boolean onGround,boolean proxySupport) {
        boolean finite(){return Double.isFinite(x+y+z+vx+vy+vz);}
        double horizontalSpeed(){return Math.hypot(vx,vz);}
        double distance(Motion from){return Math.hypot(x-from.x(),z-from.z());}
    }
    record Held(boolean forward,boolean jump,boolean backward) {
        Held(boolean forward,boolean jump){this(forward,jump,false);}
        static final Held NONE=new Held(false,false);
    }
    private final GroundSurface patch;
    private final boolean walkOnly;
    private final long startedAt;
    private Phase phase=Phase.SETTLING;
    private long stableSince=-1,phaseAt,correctionBaseline;
    private int walkTicks,jumpTicks,returnTicks;
    private Motion clientStart,serverStart,clientJump,serverJump;
    private boolean clientAir,serverAir,clientLand,serverLand;
    private double clientWalk,serverWalk;
    private double clientMaxX=.5,serverMaxX=.5,clientReturnDistance,serverReturnDistance,maxClientServerDistance;
    private String failure="";
    GroundMovementSequence(GroundSurface patch,long now){this(patch,now,false);}
    GroundMovementSequence(GroundSurface patch,long now,boolean walkOnly){
        if(walkOnly&&!patch.corridor())throw new IllegalArgumentException("Walk-only sequence requires an explicit corridor");
        this.patch=patch;this.walkOnly=walkOnly;startedAt=now;phaseAt=now;
    }
    Phase phase(){return phase;}
    String failure(){return failure;}
    double clientWalk(){return clientWalk;}
    double serverWalk(){return serverWalk;}
    boolean clientAir(){return clientAir;}
    boolean serverAir(){return serverAir;}
    boolean clientLand(){return clientLand;}
    boolean serverLand(){return serverLand;}
    double clientMaxX(){return clientMaxX;}
    double serverMaxX(){return serverMaxX;}
    double clientReturnDistance(){return clientReturnDistance;}
    double serverReturnDistance(){return serverReturnDistance;}
    double maxClientServerDistance(){return maxClientServerDistance;}
    void fail(String reason){if(phase!=Phase.PASSED && phase!=Phase.FAILED){phase=Phase.FAILED;failure=reason;}}
    Held update(long now,Motion client,Motion server,long corrections) {
        if(phase==Phase.FAILED || phase==Phase.PASSED)return Held.NONE;
        if(!client.finite() || !server.finite()){fail("Non-finite motion observation");return Held.NONE;}
        if(!safe(client) || !safe(server)){fail("Player approaching/outside bounded patch coverage");return Held.NONE;}
        if(patch.corridor()){
            clientMaxX=Math.max(clientMaxX,client.x());serverMaxX=Math.max(serverMaxX,server.x());
            maxClientServerDistance=Math.max(maxClientServerDistance,Math.hypot(client.distance(server),client.y()-server.y()));
            if(maxClientServerDistance>1){fail("Corridor client/server movement disagreement");return Held.NONE;}
        }
        if(now-startedAt>20_000_000_000L){fail("Movement sequence exceeded20s deadline");return Held.NONE;}
        if(phase!=Phase.SETTLING && corrections!=correctionBaseline){fail("Server position correction after stable-ground handoff");return Held.NONE;}
        boolean grounded=grounded(client) && grounded(server);
        switch(phase) {
            case SETTLING -> {
                if(!grounded){stableSince=-1;return Held.NONE;}
                if(stableSince<0)stableSince=now;
                if(now-stableSince>=2_000_000_000L) {
                    clientStart=client;serverStart=server;correctionBaseline=corrections;
                    phase=Phase.WALKING;phaseAt=now;walkTicks=1;return new Held(true,false);
                }
            }
            case WALKING -> {
                clientWalk=Math.max(clientWalk,client.distance(clientStart));serverWalk=Math.max(serverWalk,server.distance(serverStart));
                if(patch.corridor()){
                    if(client.x()<5.5 || server.x()<5.5){
                        if(walkTicks++<60)return new Held(true,false);
                        fail("Corridor walk did not cross the original edge on both threads");return Held.NONE;
                    }
                }else if(patch.wide()){
                    // Stop on actual distance in both worlds. A finite tick cap
                    // prevents held input from extending an obstructed crossing.
                    if(Math.min(clientWalk,serverWalk)<2.5){
                        if(walkTicks++<20)return new Held(true,false);
                        fail("Wide vanilla walk did not reach both observed targets");return Held.NONE;
                    }
                }else if(walkTicks++<6)return new Held(true,false);
                phase=Phase.RESTING;phaseAt=now;stableSince=-1;
            }
            case RESTING -> {
                clientWalk=Math.max(clientWalk,client.distance(clientStart));serverWalk=Math.max(serverWalk,server.distance(serverStart));
                if(!grounded || client.horizontalSpeed()>0.015 || server.horizontalSpeed()>0.015){stableSince=-1;return Held.NONE;}
                if(stableSince<0)stableSince=now;
                if(now-phaseAt>=1_000_000_000L && now-stableSince>=500_000_000L) {
                    double minimumWalk=patch.corridor()?5:patch.wide()?2.5:.3;
                    if(clientWalk<minimumWalk || serverWalk<minimumWalk){fail("Vanilla walk not confirmed on both client and server");return Held.NONE;}
                    if(walkOnly)return beginReturn(now);
                    clientJump=client;serverJump=server;phase=Phase.JUMPING;phaseAt=now;jumpTicks=1;
                    return new Held(false,true);
                }
            }
            case JUMPING,LANDING -> {
                clientAir|=!client.onGround() && client.y()>clientJump.y()+0.15;
                serverAir|=!server.onGround() && server.y()>serverJump.y()+0.15;
                clientLand|=clientAir && grounded(client);
                serverLand|=serverAir && grounded(server);
                if(phase==Phase.JUMPING && jumpTicks++<2)return new Held(false,true);
                phase=Phase.LANDING;
                if(clientAir && serverAir && clientLand && serverLand && grounded) {
                    if(stableSince<0)stableSince=now;
                    if(now-stableSince>=500_000_000L){
                        if(patch.corridor()){
                            return beginReturn(now);
                        }
                        phase=Phase.PASSED;
                    }
                } else stableSince=-1;
                if(now-phaseAt>8_000_000_000L)fail("Vanilla grounded-airborne-landing sequence not confirmed on both threads");
            }
            case RETURNING -> {
                clientReturnDistance=client.distance(clientStart);serverReturnDistance=server.distance(serverStart);
                if(client.x()>clientStart.x()+.4 || server.x()>serverStart.x()+.4){
                    if(returnTicks++<60)return new Held(false,false,true);
                    fail("Corridor return did not reach both observed starting areas");return Held.NONE;
                }
                phase=Phase.RETURN_REST;phaseAt=now;stableSince=-1;
            }
            case RETURN_REST -> {
                clientReturnDistance=client.distance(clientStart);serverReturnDistance=server.distance(serverStart);
                if(!grounded || client.horizontalSpeed()>.015 || server.horizontalSpeed()>.015){stableSince=-1;return Held.NONE;}
                if(clientReturnDistance>.75 || serverReturnDistance>.75){fail("Corridor return settled outside the starting area");return Held.NONE;}
                if(stableSince<0)stableSince=now;
                if(now-stableSince>=500_000_000L)phase=Phase.PASSED;
            }
            default -> {}
        }
        return Held.NONE;
    }
    private Held beginReturn(long now){
        phase=Phase.RETURNING;phaseAt=now;stableSince=-1;returnTicks=1;
        return new Held(false,false,true);
    }
    private boolean grounded(Motion motion) {
        return motion.onGround() && motion.proxySupport() && Math.abs(motion.y()-patch.groundForFeet(motion.x(),motion.z(),0.3))<0.15;
    }
    private boolean safe(Motion motion) {
        return patch.containsFeet(motion.x(),motion.z(),0.5) &&
                patch.containsFeet(motion.x()+motion.vx()*2,motion.z()+motion.vz()*2,0.4) &&
                motion.y()>=52 && motion.y()<=76;
    }
}
