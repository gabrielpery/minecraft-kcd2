package dev.minecome.hud;

import java.util.List;
import java.util.Properties;
import java.util.UUID;

/** Scripted movement with a standalone HUD receiver; never a live input/composition route. */
public final class HudGroundMovementMode {
    public enum Mode { NONE,FIXTURE,COUPLED }
    private HudGroundMovementMode() {}
    public static boolean require(Properties properties) {
        return mode(properties)==Mode.FIXTURE;
    }
    public static Mode mode(Properties properties) {
        boolean fixture=Boolean.parseBoolean(properties.getProperty("minecome.hudGroundMovementFixture"));
        boolean coupled=Boolean.parseBoolean(properties.getProperty("minecome.hudGroundMovementCoupled"));
        if(!fixture && !coupled)return Mode.NONE;
        if(fixture && coupled)throw new IllegalArgumentException("HUD ground fixture and coupled modes are exclusive");
        if (!Boolean.parseBoolean(properties.getProperty("minecome.hudStreamLab")) ||
                !Boolean.parseBoolean(properties.getProperty("minecome.hudStreamStandalone")))
            throw new IllegalArgumentException("HUD ground movement requires the explicit standalone HUD stream");
        for (String mode : List.of("hudStreamInput", "hudStreamInputFixture", "hudStreamLiveMouse",
                "hudStreamInputPointerFixture", "hudStreamInputDelayFixture", "hudStreamBackgroundTrial",
                "hudStreamOffscreenPresentation", "hudStreamOffscreenTrial", "hudStoneBridge",
                "hudStoneFixture", "hudStoneLive", "hudAimedStoneBridge", "groundMovementLab",
                "externalInputLab", "externalInputFixture", "aimedStoneLab", "aimedBridgeLab",
                "hudAimedBridgeLab", "hudExportLab", "interactiveStoneLab", "smokeWorld", "dynamicBridgeSmoke")) {
            if (Boolean.parseBoolean(properties.getProperty("minecome." + mode)))
                throw new IllegalArgumentException("HUD ground fixture cannot combine with " + mode);
        }
        if (properties.getProperty("minecome.groundPatchFile", "").isBlank())
            throw new IllegalArgumentException("HUD ground movement requires its patch file");
        if(coupled && properties.getProperty("minecome.movementTraceFile","").isBlank())
            throw new IllegalArgumentException("HUD coupled movement requires its new movement trace file");
        if(fixture && !properties.getProperty("minecome.movementTraceFile","").isBlank())
            throw new IllegalArgumentException("HUD ground fixture cannot emit a follower trace");
        return coupled?Mode.COUPLED:Mode.FIXTURE;
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
    }
}
