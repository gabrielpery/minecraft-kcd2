package dev.minecome.hud;

import com.google.gson.JsonObject;

/** Capture scheduling only; rendering and all freshness/ownership gates stay independent. */
final class HudCaptureCadence {
    static final long DEFAULT_INTERVAL_NS=50_000_000L;
    private static final class Samples {
        long frames,intervals,totalNs,maxNs;
        JsonObject json(){
            var value=new JsonObject();value.addProperty("captured_frames",frames);value.addProperty("continuous_intervals",intervals);
            value.addProperty("mean_interval_ms",intervals==0?0:totalNs/(double)intervals/1_000_000);
            value.addProperty("max_interval_ms",maxNs/1_000_000.0);return value;
        }
    }
    private final Samples hotbar=new Samples(),inventory=new Samples();
    private boolean seen,lastInventory;
    private long lastAt;
    static boolean renderDriven(boolean input,boolean mouse,boolean offscreen,boolean capApplied,boolean inventory){
        return input && mouse && offscreen && capApplied && inventory;
    }
    static boolean due(long now,long lastCapture,boolean renderDriven){
        return renderDriven || now-lastCapture>=DEFAULT_INTERVAL_NS;
    }
    void captured(boolean inventoryScreen,long now){
        Samples samples=inventoryScreen?inventory:hotbar;samples.frames++;
        if(seen && lastInventory==inventoryScreen){
            long gap=now-lastAt;
            if(gap>=0){samples.intervals++;samples.totalNs+=gap;samples.maxNs=Math.max(samples.maxNs,gap);}
        }
        seen=true;lastInventory=inventoryScreen;lastAt=now;
    }
    JsonObject diagnostics(){
        var value=new JsonObject();value.addProperty("default_minimum_interval_ms",DEFAULT_INTERVAL_NS/1_000_000);
        value.addProperty("interval_semantics","successful capture enqueue times; adjacent same-screen captures only; not display or input latency");
        value.add("hotbar",hotbar.json());value.add("inventory",inventory.json());return value;
    }
}
