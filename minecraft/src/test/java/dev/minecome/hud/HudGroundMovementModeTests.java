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
    private static void reject(Properties p,String message){
        try{HudGroundMovementMode.require(p);throw new AssertionError("Accepted "+message);}catch(IllegalArgumentException expected){checks++;}
    }
    public static void main(String[] args){
        check(!HudGroundMovementMode.require(new Properties()),"Legacy defaults remain inactive");
        check(HudGroundMovementMode.require(fixture()),"Explicit standalone fixture admitted");
        for(String required:List.of("hudStreamLab","hudStreamStandalone","groundPatchFile")){
            var p=fixture();p.remove("minecome."+required);reject(p,"missing "+required);
        }
        var blank=fixture();blank.setProperty("minecome.groundPatchFile"," ");reject(blank,"blank patch");
        for(String mode:List.of("hudStreamInput","hudStreamInputFixture","hudStreamLiveMouse","hudStreamInputPointerFixture",
                "hudStreamInputDelayFixture","hudStreamBackgroundTrial","hudStreamOffscreenPresentation","hudStreamOffscreenTrial",
                "hudStoneBridge","hudStoneFixture","hudStoneLive","hudAimedStoneBridge","groundMovementLab","externalInputLab",
                "externalInputFixture","aimedStoneLab","aimedBridgeLab","hudAimedBridgeLab","hudExportLab","interactiveStoneLab",
                "smokeWorld","dynamicBridgeSmoke")){
            var p=fixture();p.setProperty("minecome."+mode,"true");reject(p,mode);
            p.setProperty("minecome.hudGroundMovementFixture","false");
            check(!HudGroundMovementMode.require(p),"Existing mode not modified: "+mode);
        }
        System.out.println("HUD_GROUND_MOVEMENT_MODE_TESTS_PASS checks="+checks);
    }
}
