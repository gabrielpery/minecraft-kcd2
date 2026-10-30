package dev.minecome.hud;

import java.util.List;
import java.util.Properties;

/** Separate live movement profile; existing UI and scripted ground profiles stay unchanged. */
public final class HudPhysicalMovementMode {
    private HudPhysicalMovementMode(){}
    public static boolean fixture(Properties p){return Boolean.parseBoolean(p.getProperty("minecome.hudPhysicalMovementFixture"));}
    public static boolean lateCutoffFixture(Properties p){
        String value=p.getProperty("minecome.hudWalkingLateCutoffFixture","false");
        if(!value.equals("true")&&!value.equals("false"))throw new IllegalArgumentException("Late cutoff fixture option must be true or false");
        return value.equals("true");
    }
    public static boolean facingFixture(Properties p){
        String value=p.getProperty("minecome.hudFacingSeedFixture","false");
        if(!value.equals("true")&&!value.equals("false"))throw new IllegalArgumentException("Facing seed fixture option must be true or false");
        return value.equals("true");
    }
    public static boolean wide(Properties p){
        String value=p.getProperty("minecome.hudWideWalking","false");
        if(!value.equals("true")&&!value.equals("false"))throw new IllegalArgumentException("Wide walking option must be true or false");
        return value.equals("true");
    }
    public static boolean corridor(Properties p){
        String value=p.getProperty("minecome.hudCorridorWalking","false");
        if(!value.equals("true")&&!value.equals("false"))throw new IllegalArgumentException("Corridor walking option must be true or false");
        return value.equals("true");
    }
    public static boolean walkingAimed(Properties p){
        String value=p.getProperty("minecome.hudWalkingAimed","false");
        if(!value.equals("true") && !value.equals("false"))throw new IllegalArgumentException("Walking aimed option must be true or false");
        return value.equals("true");
    }
    static double fixtureYaw(Properties p){
        boolean corridor=corridor(p);
        double yaw=Double.parseDouble(p.getProperty("minecome.hudPhysicalFixtureYaw",corridor?"-90":"0"));
        if(!Double.isFinite(yaw)||yaw < -180||yaw > 180)throw new IllegalArgumentException("Fixture yaw outside finite180 degrees");
        if(corridor&&yaw!= -90)throw new IllegalArgumentException("Corridor crossing fixture requires yaw minus90");
        if(Boolean.parseBoolean(p.getProperty("minecome.hudWalkingAimedFixture"))&&
                (!HudMovementSession.selected(p).extended()||yaw!=(corridor?-90:0)))
            throw new IllegalArgumentException("Walking/aimed fixture requires extended movement and its selected area's heading");
        return yaw;
    }
    public static boolean require(Properties p){
        boolean live=Boolean.parseBoolean(p.getProperty("minecome.hudPhysicalMovement")),fixture=fixture(p);
        if(corridor(p)){
            if((!live&&!fixture)||!HudMovementSession.selected(p).extended())throw new IllegalArgumentException("Corridor walking requires extended physical live or fixture movement");
            for(String conflict:List.of("hudWideWalking","hudFacingSeedFixture",
                    "hudGroundMovementFixture","hudGroundMovementCoupled","hudGroundCorridorFixture","hudGroundCorridorCoupled","hudGroundCorridorWalkOnly"))
                if(Boolean.parseBoolean(p.getProperty("minecome."+conflict)))throw new IllegalArgumentException("Corridor physical walking conflicts with "+conflict);
        }
        if(wide(p)&&!live&&!fixture && HudGroundMovementMode.mode(p)!=HudGroundMovementMode.Mode.COUPLED)
            throw new IllegalArgumentException("Wide walking requires explicit physical movement or authenticated scripted HUD coupling");
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
        if(lateCutoffFixture(p) && (!fixture || live || !corridor(p) || !aimed.equals("true") || !HudMovementSession.selected(p).extended()))
            throw new IllegalArgumentException("Late cutoff requires the standalone extended corridor aimed fixture");
        if(facingFixture(p) && (!fixture || live || !wide(p) || !aimed.equals("true")))
            throw new IllegalArgumentException("Facing seed fixture requires wide standalone aimed walking");
        if(wide(p)&&fixture&&!HudMovementSession.selected(p).extended())
            throw new IllegalArgumentException("Wide crossing fixture requires extended walking");
        if(HudMovementSession.selected(p).extended() && !live && !fixture)
            throw new IllegalArgumentException("Extended movement requires its physical live or fixture profile");
        if(!live && !fixture)return false;
        if(live && fixture)throw new IllegalArgumentException("Physical movement live and scripted fixture profiles are exclusive");
        for(String required:fixture?List.of("hudStreamLab","hudStreamStandalone"):List.of("hudStreamLab","hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation"))
            if(!Boolean.parseBoolean(p.getProperty("minecome."+required)))throw new IllegalArgumentException("Physical HUD movement requires "+required);
        for(String conflict:fixture?List.of("hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation"):List.of("hudStreamStandalone"))
            if(Boolean.parseBoolean(p.getProperty("minecome."+conflict)))throw new IllegalArgumentException("Physical HUD movement conflicts with "+conflict);
        for(String conflict:List.of("hudGroundMovementFixture","hudGroundMovementCoupled","hudGroundCorridorFixture","hudGroundCorridorCoupled","hudGroundCorridorWalkOnly",
                "hudStreamInputFixture","hudStreamInputPointerFixture","hudStreamInputDelayFixture","hudStreamBackgroundTrial",
                "hudStreamOffscreenTrial","hudStoneBridge","hudStoneFixture","hudStoneLive","hudAimedStoneBridge",
                "groundMovementLab","externalInputLab","externalInputFixture","aimedStoneLab","aimedBridgeLab",
                "hudAimedBridgeLab","hudExportLab","interactiveStoneLab","smokeWorld","dynamicBridgeSmoke"))
            if(Boolean.parseBoolean(p.getProperty("minecome."+conflict)) && !(combined && List.of("hudStoneBridge","hudStoneLive","hudAimedStoneBridge").contains(conflict)))throw new IllegalArgumentException("Physical HUD movement conflicts with "+conflict);
        for(String path:List.of("groundPatchFile","movementTraceFile","hudHostViewFile"))
            if(p.getProperty("minecome."+path,"").isBlank())throw new IllegalArgumentException("Physical HUD movement requires "+path);
        if(fixture)fixtureYaw(p);
        return true;
    }
}
