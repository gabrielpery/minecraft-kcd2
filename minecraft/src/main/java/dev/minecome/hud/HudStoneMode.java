package dev.minecome.hud;

/** Explicit opt-ins prevent standalone block requests from becoming live input. */
final class HudStoneMode {
    private HudStoneMode() {}

    static void require(boolean bridge, boolean fixture, boolean live, boolean input,
                        boolean inputFixture, boolean offscreen, boolean offscreenTrial,
                        boolean pointerFixture, boolean delayFixture, boolean backgroundTrial,
                        boolean liveMouse) {
        if (!bridge && !fixture && !live) return;
        if (!bridge || fixture == live || !input || !offscreen || pointerFixture || delayFixture || backgroundTrial)
            throw new IllegalArgumentException("Combined stone mode requires one exclusive fixture/live profile");
        if (fixture && (!inputFixture || !offscreenTrial || liveMouse))
            throw new IllegalArgumentException("Stone fixture requires its offscreen standalone input profile");
        if (live && (inputFixture || offscreenTrial || !liveMouse))
            throw new IllegalArgumentException("Live stone bridge requires offscreen non-fixture mouse input");
    }
}
