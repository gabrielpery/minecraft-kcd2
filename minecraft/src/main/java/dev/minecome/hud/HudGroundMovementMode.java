package dev.minecome.hud;

import java.util.List;
import java.util.Properties;
import java.util.UUID;

/** Scripted movement with a standalone HUD receiver; never a live input/composition route. */
public final class HudGroundMovementMode {
    public enum Mode { NONE,FIXTURE,COUPLED,CORRIDOR,CORRIDOR_COUPLED;
        public boolean corridor(){return this==CORRIDOR || this==CORRIDOR_COUPLED;}
        public boolean coupled(){return this==COUPLED || this==CORRIDOR_COUPLED;}
    }
    private HudGroundMovementMode() {}
    public static boolean require(Properties properties) {
        return mode(properties)==Mode.FIXTURE;
    }
    public static boolean corridorWalkOnly(Properties properties){
        mode(properties);
        return Boolean.parseBoolean(properties.getProperty("minecome.hudGroundCorridorWalkOnly","false"));
    }
    public static Mode mode(Properties properties) {
        boolean fixture=Boolean.parseBoolean(properties.getProperty("minecome.hudGroundMovementFixture"));
        boolean coupled=Boolean.parseBoolean(properties.getProperty("minecome.hudGroundMovementCoupled"));
        String corridorValue=properties.getProperty("minecome.hudGroundCorridorFixture","false");
        if(!corridorValue.equals("true")&&!corridorValue.equals("false"))throw new IllegalArgumentException("Explicit corridor selector must be true or false");
        boolean corridor=corridorValue.equals("true");
        String corridorCoupledValue=properties.getProperty("minecome.hudGroundCorridorCoupled","false");
        if(!corridorCoupledValue.equals("true")&&!corridorCoupledValue.equals("false"))throw new IllegalArgumentException("Explicit coupled corridor selector must be true or false");
        boolean corridorCoupled=corridorCoupledValue.equals("true");
        String walkOnlyValue=properties.getProperty("minecome.hudGroundCorridorWalkOnly","false");
        if(!walkOnlyValue.equals("true")&&!walkOnlyValue.equals("false"))throw new IllegalArgumentException("Explicit corridor walk-only selector must be true or false");
        if(walkOnlyValue.equals("true")&&!corridorCoupled)throw new IllegalArgumentException("Corridor walk-only requires the explicit coupled corridor mode");
        if(!fixture && !coupled && !corridor && !corridorCoupled)return Mode.NONE;
        if((fixture?1:0)+(coupled?1:0)+(corridor?1:0)+(corridorCoupled?1:0)!=1)throw new IllegalArgumentException("HUD ground modes are exclusive");
        if(HudPhysicalMovementMode.wide(properties) && !coupled)
            throw new IllegalArgumentException("Wide scripted ground movement requires the authenticated coupled profile");
        if (!Boolean.parseBoolean(properties.getProperty("minecome.hudStreamLab")) ||
                !Boolean.parseBoolean(properties.getProperty("minecome.hudStreamStandalone")))
            throw new IllegalArgumentException("HUD ground movement requires the explicit standalone HUD stream");
        for (String mode : List.of("hudStreamInput", "hudStreamInputFixture", "hudStreamLiveMouse",
                "hudStreamInputPointerFixture", "hudStreamInputDelayFixture", "hudStreamBackgroundTrial",
                "hudStreamOffscreenPresentation", "hudStreamOffscreenTrial", "hudStoneBridge",
                "hudStoneFixture", "hudStoneLive", "hudAimedStoneBridge", "groundMovementLab",
                "externalInputLab", "externalInputFixture", "aimedStoneLab", "aimedBridgeLab",
                "hudAimedBridgeLab", "hudExportLab", "interactiveStoneLab", "smokeWorld", "dynamicBridgeSmoke",
                "hudPhysicalMovement", "hudPhysicalMovementFixture", "hudPhysicalMovementExtended", "hudWalkingAimed", "hudWalkingAimedFixture", "hudFacingSeedFixture")) {
            if (Boolean.parseBoolean(properties.getProperty("minecome." + mode)))
                throw new IllegalArgumentException("HUD ground fixture cannot combine with " + mode);
        }
        if (properties.getProperty("minecome.groundPatchFile", "").isBlank())
            throw new IllegalArgumentException("HUD ground movement requires its patch file");
        if((coupled||corridorCoupled) && properties.getProperty("minecome.movementTraceFile","").isBlank())
            throw new IllegalArgumentException("HUD coupled movement requires its new movement trace file");
        if((fixture||corridor) && !properties.getProperty("minecome.movementTraceFile","").isBlank())
            throw new IllegalArgumentException("HUD ground fixture cannot emit a follower trace");
        return corridorCoupled?Mode.CORRIDOR_COUPLED:corridor?Mode.CORRIDOR:coupled?Mode.COUPLED:Mode.FIXTURE;
    }
    /** A live label is checked here; exact engine capture authentication belongs to the controller. */
    public static void requirePatch(Mode mode,String hudRun,String patchRun,String sourceKind,String save) {
        String prefix="MineCome-HudStream-";
        if(mode==null || mode==Mode.NONE || hudRun==null || !hudRun.matches("[0-9a-f]{32}") ||
                save==null || !save.startsWith(prefix))
            throw new IllegalArgumentException("HUD ground movement requires its new owned HUD identity");
        String world=save.substring(prefix.length());
        if(!world.equals(UUID.fromString(world).toString()))
            throw new IllegalArgumentException("HUD ground save UUID must be canonical");
        if(mode==Mode.FIXTURE && (!"standalone_fixture".equals(sourceKind) || !hudRun.equals(patchRun)))
            throw new IllegalArgumentException("HUD ground fixture requires its same-run synthetic patch");
        if(mode==Mode.COUPLED && !"live_kcd_ground_patch".equals(sourceKind))
            throw new IllegalArgumentException("HUD coupled movement requires a captured live ground patch");
        if(mode==Mode.CORRIDOR && (patchRun==null || !patchRun.matches("[A-Za-z0-9_-]{1,128}") ||
                !List.of("standalone_corridor_fixture","live_kcd_ground_corridor").contains(sourceKind)))
            throw new IllegalArgumentException("HUD corridor requires its explicit composite surface identity");
        if(mode==Mode.CORRIDOR_COUPLED && (patchRun==null || !patchRun.matches("[A-Za-z0-9_-]{1,128}") ||
                !"live_kcd_ground_corridor".equals(sourceKind)))
            throw new IllegalArgumentException("Coupled HUD corridor requires an authenticated captured live corridor");
    }
}
