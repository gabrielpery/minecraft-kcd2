package dev.minecome.hud;

/** Prioritize a newly verified native camera without accelerating duplicate HUD captures. */
final class GameplayCaptureCadence {
    private long lastCaptureAt,lastCameraUtc;
    private boolean captured;

    boolean ready(long nanos,long verifiedCameraUtc){
        if(!captured)return true;
        if(nanos<lastCaptureAt)return false;
        long interval=verifiedCameraUtc>0&&verifiedCameraUtc>lastCameraUtc?25_000_000L:50_000_000L;
        return nanos-lastCaptureAt>=interval;
    }
    /** Call only when a real GPU readback was enqueued; a busy PBO does not consume the opportunity. */
    void captured(long nanos,long verifiedCameraUtc){
        lastCaptureAt=nanos;lastCameraUtc=Math.max(lastCameraUtc,verifiedCameraUtc);captured=true;
    }
}
