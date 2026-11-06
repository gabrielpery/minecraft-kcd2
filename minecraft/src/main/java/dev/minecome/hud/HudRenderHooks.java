package dev.minecome.hud;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.Camera;

/** One opt-in owner per process; the proven snapshot mode keeps its existing implementation. */
public final class HudRenderHooks {
    private HudRenderHooks() {}
    public static boolean suppressWorld() { return HudExportLab.suppressWorld() || HudStreamLab.suppressWorld() || GameplaySession.suppressWorld(); }
    public static boolean suppressHand() {
        if(HudExportLab.suppressWorld()||HudStreamLab.suppressWorld())return true;
        if(!GameplaySession.suppressWorld())return false;
        var client=MinecraftClient.getInstance();
        return !GameplaySession.handsEnabled()||client.currentScreen!=null||client.getOverlay()!=null||!client.options.getPerspective().isFirstPerson();
    }
    public static void beforeHand(Camera camera,float tickDelta) {
        if(!GameplaySession.handsEnabled())return;
        GameplaySession.beforeHandClear();
        if(GameplaySession.handsEnabled()&&GameplaySession.transparentFrame())GameplayHandRenderState.begin(camera,tickDelta);
    }
    public static void handRenderStarted() { if(GameplaySession.handsEnabled())GameplaySession.handRenderStarted(); }
    public static void handRenderCompleted() { if(GameplaySession.handsEnabled())GameplaySession.handRenderCompleted(); }
    public static void afterHand() { GameplayHandRenderState.end(); }
    public static boolean transparentFrame() { return HudExportLab.transparentFrame() || HudStreamLab.transparentFrame() || GameplaySession.transparentFrame(); }
    public static void beforeGuiClear() { HudExportLab.beforeGuiClear(); HudStreamLab.beforeGuiClear(); GameplaySession.beforeGuiClear(); }
    public static void afterRender() { HudExportLab.afterRender(); HudStreamLab.afterRender(); GameplaySession.afterRender(); }
}
