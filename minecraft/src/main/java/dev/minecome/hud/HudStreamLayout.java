package dev.minecome.hud;

/** Capture geometry and vanilla GUI scale are independent of the host compositor fit. */
public record HudStreamLayout(int width,int height,int guiScale) {
    public HudStreamLayout {
        HudPixels.byteSize(width,height);
        // Match Window.calculateScaleFactor's minimum usable 320 x 240 GUI canvas.
        if(guiScale<1 || guiScale>4 || width/guiScale<320 || height/guiScale<240)
            throw new IllegalArgumentException("HUD stream requires GUI scale1..4 and at least320x240 logical pixels");
    }
    public static HudStreamLayout configured(){
        return new HudStreamLayout(Integer.getInteger("minecome.hudStreamWidth",1280),Integer.getInteger("minecome.hudStreamHeight",720),Integer.getInteger("minecome.hudStreamGuiScale",2));
    }
}
