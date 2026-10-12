package dev.minecome.hud;

/** One opt-in owner per process; the proven snapshot mode keeps its existing implementation. */
public final class HudRenderHooks {
    private HudRenderHooks() {}
    public static boolean suppressWorld() { return HudExportLab.suppressWorld() || HudStreamLab.suppressWorld(); }
    public static boolean transparentFrame() { return HudExportLab.transparentFrame() || HudStreamLab.transparentFrame(); }
    public static void beforeGuiClear() { HudExportLab.beforeGuiClear(); HudStreamLab.beforeGuiClear(); }
    public static void afterRender() { HudExportLab.afterRender(); HudStreamLab.afterRender(); }
}
