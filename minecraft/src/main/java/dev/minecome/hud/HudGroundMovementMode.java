package dev.minecome.hud;

import java.util.List;
import java.util.Properties;

/** Separate scripted fixture; never an alternate route into the live input profile. */
public final class HudGroundMovementMode {
    private HudGroundMovementMode() {}
    public static boolean require(Properties properties) {
        if (!Boolean.parseBoolean(properties.getProperty("minecome.hudGroundMovementFixture"))) return false;
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
            throw new IllegalArgumentException("HUD ground fixture requires its synthetic patch file");
        return true;
    }
}
