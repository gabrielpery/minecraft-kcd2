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
    private static Properties extension(){
        var p=fixture();p.remove("minecome.hudGroundMovementFixture");p.setProperty("minecome.hudGroundExtensionFixture","true");return p;
    }
    private static Properties extensionCoupled(){
        var p=coupled();p.remove("minecome.hudGroundMovementCoupled");p.setProperty("minecome.hudGroundExtensionCoupled","true");return p;
    }
    private static Properties corridorCoupled(){
        var p=coupled();p.remove("minecome.hudGroundMovementCoupled");p.setProperty("minecome.hudGroundCorridorCoupled","true");return p;
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
        check(HudGroundMovementMode.mode(corridorCoupled())==HudGroundMovementMode.Mode.CORRIDOR_COUPLED,"Coupled corridor requires its distinct opt-in");
        check(HudGroundMovementMode.Mode.CORRIDOR_COUPLED.corridor()&&HudGroundMovementMode.Mode.CORRIDOR_COUPLED.coupled(),"Coupled corridor selects composite surface and trace together");
        check(!HudGroundMovementMode.require(corridorCoupled()),"Coupled corridor does not claim a standalone-only fixture");
        check(!HudGroundMovementMode.corridorWalkOnly(corridorCoupled()),"Full corridor remains the default diagnostic");
        var walkOnly=corridorCoupled();walkOnly.setProperty("minecome.hudGroundCorridorWalkOnly","true");
        check(HudGroundMovementMode.corridorWalkOnly(walkOnly)&&HudGroundMovementMode.mode(walkOnly)==HudGroundMovementMode.Mode.CORRIDOR_COUPLED,
                "Walk-only is an explicit coupled-corridor variant");
        for(var p:List.of(new Properties(),fixture(),coupled(),corridor())){
            p.setProperty("minecome.hudGroundCorridorWalkOnly","true");reject(p,"walk-only without coupled corridor");
        }
        for(String value:List.of("TRUE","yes","1","")){
            var p=corridorCoupled();p.setProperty("minecome.hudGroundCorridorWalkOnly",value);reject(p,"malformed walk-only selector "+value);
        }
        for(String key:List.of("hudStreamLab","hudStreamStandalone","groundPatchFile","movementTraceFile")){
            var p=corridorCoupled();p.remove("minecome."+key);reject(p,"coupled corridor missing "+key);
        }
        for(String key:List.of("hudGroundMovementFixture","hudGroundMovementCoupled","hudGroundCorridorFixture","hudWideWalking","hudStreamInput",
                "hudPhysicalMovement","hudPhysicalMovementFixture","hudPhysicalMovementExtended","hudWalkingAimed","hudWalkingAimedFixture","hudFacingSeedFixture")){
            var p=corridorCoupled();p.setProperty("minecome."+key,"true");reject(p,"coupled corridor conflict "+key);
        }
        for(String value:List.of("TRUE","yes","1","")){
            var p=corridorCoupled();p.setProperty("minecome.hudGroundCorridorCoupled",value);reject(p,"malformed coupled corridor selector "+value);
        }
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
        check(HudGroundMovementMode.mode(extension())==HudGroundMovementMode.Mode.EXTENSION,"Extension has a distinct standalone mode");
        check(HudGroundMovementMode.Mode.EXTENSION.corridor()&&!HudGroundMovementMode.Mode.EXTENSION.coupled(),"Extension uses composite ground without native trace authority");
        check(!HudGroundMovementMode.require(extension()),"Extension cannot claim the legacy fixture");
        for(String key:List.of("hudStreamLab","hudStreamStandalone","groundPatchFile")){
            var p=extension();p.remove("minecome."+key);reject(p,"extension missing "+key);
        }
        for(String key:List.of("hudGroundMovementFixture","hudGroundMovementCoupled","hudGroundCorridorFixture","hudGroundCorridorCoupled","hudGroundCorridorWalkOnly","hudWideWalking","hudStreamInput","hudPhysicalMovement","hudPhysicalMovementFixture","hudPhysicalMovementExtended","hudWalkingAimed","hudWalkingAimedFixture","hudFacingSeedFixture","hudCorridorWalking")){
            var p=extension();p.setProperty("minecome."+key,"true");reject(p,"extension conflict "+key);
        }
        for(String value:List.of("TRUE","yes","1","")){
            var p=extension();p.setProperty("minecome.hudGroundExtensionFixture",value);reject(p,"malformed extension selector "+value);
        }
        var extensionTrace=extension();extensionTrace.setProperty("minecome.movementTraceFile","trace.ndjson");reject(extensionTrace,"extension cannot send follower trace");
        check(HudGroundMovementMode.mode(extensionCoupled())==HudGroundMovementMode.Mode.EXTENSION_COUPLED,"Coupled extension has its explicit mode");
        check(HudGroundMovementMode.Mode.EXTENSION_COUPLED.extension()&&HudGroundMovementMode.Mode.EXTENSION_COUPLED.coupled(),"Coupled extension selects plan and trace together");
        for(String key:List.of("hudStreamLab","hudStreamStandalone","groundPatchFile","movementTraceFile")){
            var p=extensionCoupled();p.remove("minecome."+key);reject(p,"coupled extension missing "+key);
        }
        for(String key:List.of("hudGroundMovementFixture","hudGroundMovementCoupled","hudGroundCorridorFixture","hudGroundCorridorCoupled","hudGroundExtensionFixture","hudGroundCorridorWalkOnly","hudWideWalking","hudStreamInput","hudPhysicalMovement","hudPhysicalMovementFixture","hudPhysicalMovementExtended","hudWalkingAimed","hudWalkingAimedFixture","hudFacingSeedFixture","hudCorridorWalking")){
            var p=extensionCoupled();p.setProperty("minecome."+key,"true");reject(p,"coupled extension conflict "+key);
        }
        for(String value:List.of("TRUE","yes","1","")){
            var p=extensionCoupled();p.setProperty("minecome.hudGroundExtensionCoupled",value);reject(p,"malformed coupled extension selector "+value);
        }
        check(!HudGroundMovementMode.extensionDelayFixture(new Properties()),"Delay fixture is inactive by default");
        for(var p:List.of(extension(),extensionCoupled())){
            p.setProperty("minecome.hudGroundExtensionDelayFixture","true");
            check(HudGroundMovementMode.extensionDelayFixture(p),"Explicit extension mode allows controlled handoff delay");
            p.setProperty("minecome.hudGroundExtensionDelayFixture","false");
            check(!HudGroundMovementMode.extensionDelayFixture(p),"Extension delay can remain explicitly disabled");
        }
        for(var p:List.of(new Properties(),fixture(),coupled(),corridor(),corridorCoupled())){
            p.setProperty("minecome.hudGroundExtensionDelayFixture","true");reject(p,"delay cannot alter another profile");
        }
        for(String value:List.of("TRUE","yes","1","")){
            var p=extension();p.setProperty("minecome.hudGroundExtensionDelayFixture",value);reject(p,"malformed extension delay "+value);
        }
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
            var liveCorridor=corridorCoupled();liveCorridor.setProperty("minecome."+mode,"true");reject(liveCorridor,"coupled corridor conflict "+mode);
        }
        String hudRun="a".repeat(32),patchRun="b".repeat(32),save="MineCome-HudStream-ab32daa1-3972-4454-be0e-6d010ac2fd60";
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.FIXTURE,hudRun,hudRun,"standalone_fixture",save);checks++;
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.COUPLED,hudRun,patchRun,"live_kcd_ground_patch",save);checks++;
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.CORRIDOR,hudRun,patchRun,"live_kcd_ground_corridor",save);checks++;
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.CORRIDOR,hudRun,patchRun,"standalone_corridor_fixture",save);checks++;
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.CORRIDOR_COUPLED,hudRun,patchRun,"live_kcd_ground_corridor",save);checks++;
        for(String source:List.of("standalone_corridor_fixture","live_kcd_ground_patch","standalone_fixture","hud_corridor_coupled"))
            rejectPatch(HudGroundMovementMode.Mode.CORRIDOR_COUPLED,hudRun,patchRun,source,save);
        rejectPatch(HudGroundMovementMode.Mode.CORRIDOR_COUPLED,hudRun,"bad run","live_kcd_ground_corridor",save);
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.EXTENSION_COUPLED,hudRun,patchRun,"live_kcd_ground_corridor",save);checks++;
        rejectPatch(HudGroundMovementMode.Mode.EXTENSION_COUPLED,hudRun,patchRun,"standalone_corridor_fixture",save);
        rejectPatch(HudGroundMovementMode.Mode.EXTENSION_COUPLED,hudRun,patchRun,"live_kcd_ground_patch",save);
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.EXTENSION,hudRun,patchRun,"live_kcd_ground_corridor",save);checks++;
        HudGroundMovementMode.requirePatch(HudGroundMovementMode.Mode.EXTENSION,hudRun,patchRun,"standalone_corridor_fixture",save);checks++;
        rejectPatch(HudGroundMovementMode.Mode.EXTENSION,hudRun,patchRun,"standalone_fixture",save);
        rejectPatch(HudGroundMovementMode.Mode.EXTENSION,hudRun,patchRun,"live_kcd_ground_patch",save);
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
