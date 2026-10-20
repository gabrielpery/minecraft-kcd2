package dev.minecome.hud;

import java.util.List;
import java.util.Properties;

/** Separate live movement profile; existing UI and scripted ground profiles stay unchanged. */
public final class HudPhysicalMovementMode {
    private HudPhysicalMovementMode(){}
    public static boolean require(Properties p){
        if(!Boolean.parseBoolean(p.getProperty("minecome.hudPhysicalMovement")))return false;
        for(String required:List.of("hudStreamLab","hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation"))
            if(!Boolean.parseBoolean(p.getProperty("minecome."+required)))throw new IllegalArgumentException("Physical HUD movement requires "+required);
        for(String conflict:List.of("hudStreamStandalone","hudGroundMovementFixture","hudGroundMovementCoupled",
                "hudStreamInputFixture","hudStreamInputPointerFixture","hudStreamInputDelayFixture","hudStreamBackgroundTrial",
                "hudStreamOffscreenTrial","hudStoneBridge","hudStoneFixture","hudStoneLive","hudAimedStoneBridge",
                "groundMovementLab","externalInputLab","externalInputFixture","aimedStoneLab","aimedBridgeLab",
                "hudAimedBridgeLab","hudExportLab","interactiveStoneLab","smokeWorld","dynamicBridgeSmoke"))
            if(Boolean.parseBoolean(p.getProperty("minecome."+conflict)))throw new IllegalArgumentException("Physical HUD movement conflicts with "+conflict);
        for(String path:List.of("groundPatchFile","movementTraceFile","hudHostViewFile"))
            if(p.getProperty("minecome."+path,"").isBlank())throw new IllegalArgumentException("Physical HUD movement requires "+path);
        return true;
    }
}
