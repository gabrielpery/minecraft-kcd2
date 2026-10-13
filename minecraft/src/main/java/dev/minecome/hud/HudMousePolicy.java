package dev.minecome.hud;

/** Explicit guest mouse modes; enabling a fixture never enables physical host input. */
final class HudMousePolicy {
    private HudMousePolicy(){}
    static boolean enabled(boolean input,boolean fixture,boolean liveMouse){
        if(fixture && !input)throw new IllegalArgumentException("Mouse fixture requires input mode");
        if(liveMouse && (!input || fixture))throw new IllegalArgumentException("Live mouse requires non-fixture input mode");
        return input && (fixture || liveMouse);
    }
}
