package dev.minecome.hud;

import dev.minecome.protocol.AimGeometry;
import dev.minecome.protocol.Protocol.Vec3;
import java.util.Properties;

public final class HudWalkingAimGateTests {
    private static int checks;
    private static void check(boolean v,String why){checks++;if(!v)throw new AssertionError(why);}
    private static Vec3 v(double x,double y,double z){return new Vec3(x,y,z);}
    public static void main(String[] args){
        var feet=v(0,64,0);var eye=v(0,65.62,0);var hostFeet=v(100,200,50);var hostEye=v(100,200,51.7);
        var a=new AimGeometry.Alignment(eye,hostEye,1);
        check(HudWalkingAimGate.aligned(a,feet,hostFeet,hostFeet,hostEye,feet,eye),"Different fixed eye heights retain separate feet anchors");
        check(HudWalkingAimGate.aligned(a,feet,hostFeet,v(100.4,199.6,49.9),v(100.4,199.6,51.6),v(.4,63.9,.4),v(.4,65.52,.4)),"Moving down a slope preserves the immutable axis transform");
        check(!HudWalkingAimGate.aligned(a,feet,hostFeet,hostFeet,hostEye,v(.06,64,0),eye),"Delayed host feet refuse a click even if the camera matches");
        check(!HudWalkingAimGate.aligned(a,feet,hostFeet,hostFeet,hostEye,feet,v(0,65.871,0)),"Camera mismatch cannot borrow the feet allowance");
        try{v(Double.NaN,200,50);throw new AssertionError("Nonfinite wire pose");}catch(IllegalArgumentException expected){checks++;}
        check(!HudWalkingAimGate.aligned(a,feet,hostFeet,hostFeet,null,feet,eye),"Missing pose cannot grant aiming");
        check(!HudWalkingAimGate.cutoff(-1,100_000_000_000L),"Unstarted movement sentinel cannot close the bootstrap gate");
        check(HudWalkingAimGate.cutoff(0,HudWalkingAimGate.ACTIVE_NS),"Monotonic epoch zero is a valid started time");
        check(!HudWalkingAimGate.cutoff(100,100+HudWalkingAimGate.ACTIVE_NS-1),"Final instant before cutoff allowed by time only");
        check(HudWalkingAimGate.cutoff(100,100+HudWalkingAimGate.ACTIVE_NS),"Exactly twelve seconds stops new actions");
        check(HudWalkingAimGate.cutoff(100,99),"Clock reversal cannot renew aiming");
        var p=new Properties();
        for(String key:new String[]{"hudWalkingAimed","hudPhysicalMovement","hudPhysicalMovementExtended","hudStreamLab","hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation","hudStoneBridge","hudStoneLive","hudAimedStoneBridge"})p.setProperty("minecome."+key,"true");
        for(String key:new String[]{"groundPatchFile","movementTraceFile","hudHostViewFile","tokenFile"})p.setProperty("minecome."+key,"owned-file");
        check(HudPhysicalMovementMode.require(p),"Explicit combined live profile accepted");
        var corridor=(Properties)p.clone();corridor.setProperty("minecome.hudCorridorWalking","true");
        check(HudPhysicalMovementMode.require(corridor),"Explicit corridor admits the complete live walking/aimed profile");
        for(String key:new String[]{"hudPhysicalMovementExtended","hudStoneLive","hudAimedStoneBridge","tokenFile"}){
            var broken=(Properties)corridor.clone();broken.remove("minecome."+key);
            try{HudPhysicalMovementMode.require(broken);throw new AssertionError("Missing corridor aimed requirement "+key);}catch(IllegalArgumentException expected){checks++;}
        }
        for(String key:new String[]{"hudWideWalking","hudFacingSeedFixture","hudGroundCorridorCoupled"}){
            var broken=(Properties)corridor.clone();broken.setProperty("minecome."+key,"true");
            try{HudPhysicalMovementMode.require(broken);throw new AssertionError("Mixed corridor aimed profile "+key);}catch(IllegalArgumentException expected){checks++;}
        }
        for(String key:new String[]{"hudPhysicalMovement","hudPhysicalMovementExtended","hudStreamInput","hudStoneBridge","hudStoneLive","hudAimedStoneBridge","tokenFile"}){
            var broken=new Properties();broken.putAll(p);broken.remove("minecome."+key);
            try{HudPhysicalMovementMode.require(broken);throw new AssertionError("Missing profile requirement "+key);}catch(IllegalArgumentException expected){checks++;}
        }
        for(String key:new String[]{"hudPhysicalMovementFixture","hudWalkingAimedFixture","hudStreamStandalone","hudStoneFixture","hudStreamInputFixture"}){
            var broken=new Properties();broken.putAll(p);broken.setProperty("minecome."+key,"true");
            try{HudPhysicalMovementMode.require(broken);throw new AssertionError("Mixed profile "+key);}catch(IllegalArgumentException expected){checks++;}
        }
        System.out.println("HudWalkingAimGateTests: "+checks+" checks passed; no games");
    }
}
