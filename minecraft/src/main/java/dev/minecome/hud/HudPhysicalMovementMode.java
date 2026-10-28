package dev.minecome.hud;

import java.util.List;
import java.util.Properties;

/** Separate live movement profile; existing UI and scripted ground profiles stay unchanged. */
public final class HudPhysicalMovementMode {
    private HudPhysicalMovementMode(){}
    public static boolean fixture(Properties p){return Boolean.parseBoolean(p.getProperty("minecome.hudPhysicalMovementFixture"));}
    public static boolean wide(Properties p){
        String value=p.getProperty("minecome.hudWideWalking","false");
        if(!value.equals("true")&&!value.equals("false"))throw new IllegalArgumentException("Wide walking option must be true or false");
        return value.equals("true");
    }
    public static boolean walkingAimed(Properties p){
        String value=p.getProperty("minecome.hudWalkingAimed","false");
        if(!value.equals("true") && !value.equals("false"))throw new IllegalArgumentException("Walking aimed option must be true or false");
        return value.equals("true");
    }
    public static boolean require(Properties p){
        boolean live=Boolean.parseBoolean(p.getProperty("minecome.hudPhysicalMovement")),fixture=fixture(p);
        if(wide(p)&&!live&&!fixture)throw new IllegalArgumentException("Wide walking requires explicit physical live or fixture mode");
        boolean combined=walkingAimed(p);
        if(combined){
            if(!live || fixture || !HudMovementSession.selected(p).extended() || Boolean.parseBoolean(p.getProperty("minecome.hudWalkingAimedFixture")))
                throw new IllegalArgumentException("Combined live aiming requires only extended physical walking");
            for(String required:List.of("hudStoneBridge","hudStoneLive","hudAimedStoneBridge"))
                if(!Boolean.parseBoolean(p.getProperty("minecome."+required)))throw new IllegalArgumentException("Walking aimed profile requires "+required);
            if(p.getProperty("minecome.tokenFile","").isBlank())throw new IllegalArgumentException("Walking aimed profile requires its relay token");
        }
        String aimed=p.getProperty("minecome.hudWalkingAimedFixture","false");
        if(!aimed.equals("true") && !aimed.equals("false"))throw new IllegalArgumentException("Walking aimed fixture option must be true or false");
        if(aimed.equals("true") && (!fixture || live || !HudMovementSession.selected(p).extended()))
            throw new IllegalArgumentException("Walking aimed blocks require the standalone extended physical fixture");
        if(wide(p)&&fixture&&(!HudMovementSession.selected(p).extended()||aimed.equals("true")))
            throw new IllegalArgumentException("Wide crossing fixture requires extended walking without aimed blocks");
        if(HudMovementSession.selected(p).extended() && !live && !fixture)
            throw new IllegalArgumentException("Extended movement requires its physical live or fixture profile");
        if(!live && !fixture)return false;
        if(live && fixture)throw new IllegalArgumentException("Physical movement live and scripted fixture profiles are exclusive");
        for(String required:fixture?List.of("hudStreamLab","hudStreamStandalone"):List.of("hudStreamLab","hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation"))
            if(!Boolean.parseBoolean(p.getProperty("minecome."+required)))throw new IllegalArgumentException("Physical HUD movement requires "+required);
        for(String conflict:fixture?List.of("hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation"):List.of("hudStreamStandalone"))
            if(Boolean.parseBoolean(p.getProperty("minecome."+conflict)))throw new IllegalArgumentException("Physical HUD movement conflicts with "+conflict);
        for(String conflict:List.of("hudGroundMovementFixture","hudGroundMovementCoupled",
                "hudStreamInputFixture","hudStreamInputPointerFixture","hudStreamInputDelayFixture","hudStreamBackgroundTrial",
                "hudStreamOffscreenTrial","hudStoneBridge","hudStoneFixture","hudStoneLive","hudAimedStoneBridge",
                "groundMovementLab","externalInputLab","externalInputFixture","aimedStoneLab","aimedBridgeLab",
                "hudAimedBridgeLab","hudExportLab","interactiveStoneLab","smokeWorld","dynamicBridgeSmoke"))
            if(Boolean.parseBoolean(p.getProperty("minecome."+conflict)) && !(combined && List.of("hudStoneBridge","hudStoneLive","hudAimedStoneBridge").contains(conflict)))throw new IllegalArgumentException("Physical HUD movement conflicts with "+conflict);
        for(String path:List.of("groundPatchFile","movementTraceFile","hudHostViewFile"))
            if(p.getProperty("minecome."+path,"").isBlank())throw new IllegalArgumentException("Physical HUD movement requires "+path);
        return true;
    }
}
