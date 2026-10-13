package dev.minecome.hud;

/** Regression for 30 FPS render/50 ms capture aliasing; no game or GPU needed. */
public final class HudCaptureCadenceTests {
    private static int checks;
    private static void check(boolean value,String reason){checks++;if(!value)throw new AssertionError(reason);}
    private static int frames(boolean fast,long step){
        long last=1_000_000_000L;int frames=0;
        for(int frame=1;frame<=30;frame++){
            long now=1_000_000_000L+frame*step;
            if(HudCaptureCadence.due(now,last,fast)){frames++;last=now;}
        }
        return frames;
    }
    public static void main(String[] args){
        for(int flags=0;flags<32;flags++){
            boolean fast=HudCaptureCadence.renderDriven((flags&1)!=0,(flags&2)!=0,(flags&4)!=0,(flags&8)!=0,(flags&16)!=0);
            check(fast==(flags==31),"Only capped offscreen input with mouse and inventory uses every render");
        }
        check(frames(false,33_333_333L)==15,"Existing hotbar captures alternate30 FPS renders");
        check(frames(true,33_333_333L)==30,"Inventory captures all30 FPS renders even below rounded frame interval");
        check(frames(true,34_000_000L)==30,"Inventory does not accumulate timer rounding drift");
        check(!HudCaptureCadence.due(49_999_999L,0,false),"Legacy timer retains lower bound");
        check(HudCaptureCadence.due(50_000_000L,0,false),"Legacy timer includes boundary");
        check(HudCaptureCadence.due(5_000_000_000L,0,true),"Pause resumes with a single current-frame capture");
        var cadence=new HudCaptureCadence();
        cadence.captured(false,0);cadence.captured(false,66_000_000L);
        cadence.captured(true,100_000_000L);cadence.captured(true,133_000_000L);cadence.captured(true,167_000_000L);
        cadence.captured(false,200_000_000L);cadence.captured(true,233_000_000L);
        var proof=cadence.diagnostics();var inventory=proof.getAsJsonObject("inventory");var hotbar=proof.getAsJsonObject("hotbar");
        check(inventory.get("captured_frames").getAsLong()==4,"Counts successful inventory submissions");
        check(inventory.get("continuous_intervals").getAsLong()==2,"Screen transitions excluded from inventory timing");
        check(inventory.get("mean_interval_ms").getAsDouble()==33.5,"Real enqueue mean excludes other screens");
        check(inventory.get("max_interval_ms").getAsDouble()==34,"Enqueue peak retained");
        check(hotbar.get("continuous_intervals").getAsLong()==1 && hotbar.get("mean_interval_ms").getAsDouble()==66,"Hotbar measured independently");
        cadence.captured(true,500_000_000L);
        check(inventory.get("captured_frames").getAsLong()==4,"Frozen evidence cannot change");
        check(cadence.diagnostics().getAsJsonObject("inventory").get("max_interval_ms").getAsDouble()==267,"Real stalls remain visible, not smoothed away");
        System.out.println("HudCaptureCadenceTests: "+checks+" checks passed.");
    }
}
