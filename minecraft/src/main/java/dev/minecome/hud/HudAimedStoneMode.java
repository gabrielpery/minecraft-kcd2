package dev.minecome.hud;

/** The optional aimed adapter cannot be mistaken for the verified fixed-cell fixture. */
final class HudAimedStoneMode {
    static void require(boolean aimed, boolean bridge, boolean live, boolean fixture, boolean input, boolean inputFixture) {
        if (aimed && (!bridge || !live || fixture || !input || inputFixture))
            throw new IllegalArgumentException("Aimed HUD bridge requires live stone input and excludes fixtures");
    }
}
