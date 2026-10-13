package dev.minecome.hud;

/** Profile admission only; no Minecraft bootstrap or game calls. */
public final class HudAimedStoneModeTests {
    private static int checks;
    private static void accepted(boolean aimed, boolean bridge, boolean live, boolean fixture, boolean input, boolean inputFixture) {
        HudAimedStoneMode.require(aimed, bridge, live, fixture, input, inputFixture); checks++;
    }
    private static void refused(boolean bridge, boolean live, boolean fixture, boolean input, boolean inputFixture) {
        try { HudAimedStoneMode.require(true, bridge, live, fixture, input, inputFixture); }
        catch (IllegalArgumentException expected) { checks++; return; }
        throw new AssertionError("Unsafe or ambiguous aimed HUD profile admitted");
    }
    public static void main(String[] args) {
        accepted(true, true, true, false, true, false);
        accepted(false, false, false, false, false, false);
        // Existing standalone and live profiles remain the old mode's concern.
        accepted(false, true, false, true, true, true);
        accepted(false, true, true, false, true, false);
        refused(false, true, false, true, false);
        refused(true, false, false, true, false);
        refused(true, true, true, true, false);
        refused(true, true, false, false, false);
        refused(true, true, false, true, true);
        System.out.println("HudAimedStoneModeTests: " + checks + " checks passed.");
    }
}
