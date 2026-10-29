package dev.minecome.hud;

import java.util.List;
import java.util.Properties;

/** The new synthetic fixture cannot select a live or existing input/stone route. */
public final class HudGroundMovementModeTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static Properties fixture(){
        var p=new Properties();p.setProperty("minecome.hudGroundMovementFixture","true");
        p.setProperty("minecome.hudStreamLab","true");p.setProperty("minecome.hudStreamStandalone","true");
        p.setProperty("minecome.groundPatchFile","synthetic-ground.json");return p;
    }
    private static Properties coupled(){
        var p=fixture();p.remove("minecome.hudGroundMovementFixture");
        p.setProperty("minecome.hudGroundMovementCoupled","true");
        p.setProperty("minecome.movementTraceFile","new-trace.ndjson");return p;
    }
    private static Properties corridor(){
        var p=fixture();p.remove("minecome.hudGroundMovementFixture");p.setProperty("minecome.hudGroundCorridorFixture","true");return p;
    }
    private static void reject(Properties p,String message){
        try{HudGroundMovementMode.require(p);throw new AssertionError("Accepted "+message);}catch(IllegalArgumentException expected){checks++;}
    }
    private static void rejectPatch(HudGroundMovementMode.Mode mode,String hudRun,String patchRun,String source,String save){
        try{HudGroundMovementMode.requirePatch(mode,hudRun,patchRun,source,save);throw new AssertionError("Invalid patch admitted");}
        catch(IllegalArgumentException expected){checks++;}
    }
    public static void main(String[] args){
        check(!HudGroundMovementMode.require(new Properties()),"Legacy defaults remain inactive");
        check(HudGroundMovementMode.require(fixture()),"Explicit standalone fixture admitted");
        check(HudGroundMovementMode.mode(coupled())==HudGroundMovementMode.Mode.COUPLED,"Explicit coupled mode selected separately");
        check(!HudGroundMovementMode.require(coupled()),"Coupled mode does not claim synthetic fixture");
        check(HudGroundMovementMode.mode(corridor())==HudGroundMovementMode.Mode.CORRIDOR,"Corridor has a distinct standalone mode");
        check(!HudGroundMovementMode.require(corridor()),"Corridor cannot claim the legacy synthetic fixture");
        for(String key:List.of("hudStreamLab","hudStreamStandalone","groundPatchFile")){
            var p=corridor();p.remove("minecome."+key);reject(p,"corridor missing "+key);
        }
        for(String key:List.of("hudGroundMovementFixture","hudGroundMovementCoupled","hudWideWalking","hudStreamInput",
                "hudPhysicalMovement","hudPhysicalMovementFixture","hudWalkingAimed","hudWalkingAimedFixture","hudFacingSeedFixture")){
            var p=corridor();p.setProperty("minecome."+key,"true");reject(p,"corridor conflict "+key);
        }
        for(String value:List.of("TRUE","yes","1","")){
            var p=corridor();p.setProperty("minecome.hudGroundCorridorFixture",value);reject(p,"malformed corridor selector "+value);
        }
        var corridorTrace=corridor();corridorTrace.setProperty("minecome.movementTraceFile","trace.ndjson");reject(corridorTrace,"corridor cannot send live follower trace");
        var wide=coupled();wide.setProperty("minecome.hudWideWalking","true");
        check(HudGroundMovementMode.mode(wide)==HudGroundMovementMode.Mode.COUPLED,"Wide opt-in retains authenticated scripted coupled identity");
        check(!HudPhysicalMovementMode.require(wide),"Wide coupled does not claim physical input");
        var wideFixture=fixture();wideFixture.setProperty("minecome.hudWideWalking","true");reject(wideFixture,"wide legacy synthetic ground fixture");
        var mixed=(Properties)wide.clone();mixed.setProperty("minecome.hudPhysicalMovement","true");reject(mixed,"coupled mixed physical mode");
        mixed=(Properties)wide.clone();mixed.setProperty("minecome.hudPhysicalMovementExtended","true");reject(mixed,"coupled mixed extended physical clock");
        var malformed=(Properties)wide.clone();malformed.setProperty("minecome.hudWideWalking","yes");reject(malformed,"malformed wide selector");
        for(String required:List.of("hudStreamLab","hudStreamStandalone","groundPatchFile")){
            var p=fixture();p.remove("minecome."+required);reject(p,"missing "+required);
        }
        var blank=fixture();blank.setProperty("minecome.groundPatchFile"," ");reject(blank,"blank patch");
        var both=coupled();both.setProperty("minecome.hudGroundMovementFixture","true");reject(both,"both movement modes");
        for(String required:List.of("hudStreamLab","hudStreamStandalone","groundPatchFile","movementTraceFile")){
            var p=coupled();p.remove("minecome."+required);reject(p,"coupled missing "+required);
        }
        var missingTrace=coupled();missingTrace.setProperty("minecome.movementTraceFile"," ");reject(missingTrace,"blank trace");
        var fixtureTrace=fixture();fixtureTrace.setProperty("minecome.movementTraceFile","trace.ndjson");reject(fixtureTrace,"synthetic fixture follower trace");
        for(String mode:List.of("hudStreamInput","hudStreamInputFixture","hudStreamLiveMouse","hudStreamInputPointerFixture",
                "hudStreamInputDelayFixture","hudStreamBackgroundTrial","hudStreamOffscreenPresentation","hudStreamOffscreenTrial",
                "hudStoneBridge","hudStoneFixture","hudStoneLive","hudAimedStoneBridge","groundMovementLab","externalInputLab",
                "externalInputFixture","aimedStoneLab","aimedBridgeLab","hudAimedBridgeLab","hudExportLab","interactiveStoneLab",
                "smokeWorld","dynamicBridgeSmoke")){
            var p=fixture();p.setProperty("minecome."+mode,"true");reject(p,mode);
            p.setProperty("minecome.hudGroundMovementFixture","false");
            check(!HudGroundMovementMode.require(p),"Existing mode not modified: "+mode);
            var live=coupled();live.setProperty("minecome."+mode,"true");reject(live,"coupled conflict "+mode);
        }
        String hudRun="a".repeat(32),patchRun="b".repeat(32),save="MineCome-HudStream-ab32daa1-3972-4454-be0e-6d010ac2fd60";
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.FIXTURE,hudRun,hudRun,"standalone_fixture",save);checks++;
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.COUPLED,hudRun,patchRun,"live_kcd_ground_patch",save);checks++;
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.CORRIDOR,hudRun,patchRun,"live_kcd_ground_corridor",save);checks++;
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.CORRIDOR,hudRun,patchRun,"standalone_corridor_fixture",save);checks++;
        rejectPatch(HudGroundMovementMode.Mode.CORRIDOR,hudRun,patchRun,"live_kcd_ground_patch",save);
        rejectPatch(HudGroundMovementMode.Mode.CORRIDOR,hudRun,patchRun,"standalone_fixture",save);
        rejectPatch(HudGroundMovementMode.Mode.COUPLED,hudRun,patchRun,"live_kcd_ground_corridor",save);
        rejectPatch(HudGroundMovementMode.Mode.FIXTURE,hudRun,hudRun,"standalone_corridor_fixture",save);
        rejectPatch(HudGroundMovementMode.Mode.FIXTURE,hudRun,patchRun,"standalone_fixture",save);
        rejectPatch(HudGroundMovementMode.Mode.FIXTURE,hudRun,hudRun,"live_kcd_ground_patch",save);
        rejectPatch(HudGroundMovementMode.Mode.COUPLED,hudRun,patchRun,"standalone_fixture",save);
        rejectPatch(HudGroundMovementMode.Mode.COUPLED,hudRun,patchRun,"unknown",save);
        rejectPatch(HudGroundMovementMode.Mode.NONE,hudRun,patchRun,"live_kcd_ground_patch",save);
        rejectPatch(HudGroundMovementMode.Mode.COUPLED,"wrong-run",patchRun,"live_kcd_ground_patch",save);
        rejectPatch(HudGroundMovementMode.Mode.COUPLED,hudRun,patchRun,"live_kcd_ground_patch",save.toUpperCase());
        rejectPatch(HudGroundMovementMode.Mode.COUPLED,hudRun,patchRun,"live_kcd_ground_patch",save.replace("HudStream","Ground"));
        rejectPatch(HudGroundMovementMode.Mode.COUPLED,hudRun,patchRun,"live_kcd_ground_patch","MineCome-HudStream-1-1-1-1-1");
        System.out.println("HUD_GROUND_MOVEMENT_MODE_TESTS_PASS checks="+checks);
    }
}
