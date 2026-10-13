package dev.minecome.hud;

import com.google.gson.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Bounded diagnostics only. Never advances a heartbeat or changes game scheduling. */
public final class HudRenderTiming implements AutoCloseable {
    private record Stage(String name,long at){}
    private static final class Stats {
        final Map<String,Long> stageMax=new TreeMap<>();
        final JsonArray slowSamples=new JsonArray();
        long tickAt,inputAt,waitingGap,armedGap,transitionGap,inputGap,tickGapUtc,focused,unfocused,overlay,readbackAge;
        boolean lastArmed;
    }
    private final Thread renderThread;
    private final BooleanSupplier frozenAtPoll;
    private final Object guard=new Object();
    private final Stats overall=new Stats();
    private Stats phase=new Stats();
    private long phaseStarted=System.nanoTime();
    private volatile Stage stage=new Stage("between_frames",System.nanoTime());
    private volatile boolean stopped;
    private volatile boolean lastArmed,lastFocused;
    private volatile long lastTickUtc;
    private final Thread sampler;
    public HudRenderTiming(Thread renderThread,BooleanSupplier frozenAtPoll){
        this.renderThread=Objects.requireNonNull(renderThread);this.frozenAtPoll=Objects.requireNonNull(frozenAtPoll);
        sampler=new Thread(this::sample,"MineComeHudRenderTiming");sampler.setDaemon(true);sampler.start();
    }
    public void stage(String name){
        long now=System.nanoTime();Stage previous=stage;stage=new Stage(name,now);
        synchronized(guard){recordStage(overall,previous,now);recordStage(phase,new Stage(previous.name(),Math.max(previous.at(),phaseStarted)),now);}
    }
    private static void recordStage(Stats stats,Stage previous,long now){stats.stageMax.merge(previous.name(),Math.max(0,now-previous.at()),Math::max);}
    public void tick(boolean armed,boolean focused,boolean overlay,long now){lastArmed=armed;lastFocused=focused;lastTickUtc=System.currentTimeMillis();synchronized(guard){tick(overall,armed,focused,overlay,now);tick(phase,armed,focused,overlay,now);}}
    private static void tick(Stats s,boolean armed,boolean focused,boolean overlay,long now){
        if(s.tickAt!=0){long gap=Math.max(0,now-s.tickAt);if(gap>Math.max(Math.max(s.waitingGap,s.armedGap),s.transitionGap))s.tickGapUtc=System.currentTimeMillis();if(armed!=s.lastArmed)s.transitionGap=Math.max(s.transitionGap,gap);else if(armed)s.armedGap=Math.max(s.armedGap,gap);else s.waitingGap=Math.max(s.waitingGap,gap);}
        s.tickAt=now;s.lastArmed=armed;if(focused)s.focused++;else s.unfocused++;if(overlay)s.overlay++;
    }
    public void inputTick(long now){synchronized(guard){if(overall.inputAt!=0)overall.inputGap=Math.max(overall.inputGap,now-overall.inputAt);overall.inputAt=now;if(phase.inputAt!=0)phase.inputGap=Math.max(phase.inputGap,now-phase.inputAt);phase.inputAt=now;}}
    public void readbackAge(long ageMs){synchronized(guard){overall.readbackAge=Math.max(overall.readbackAge,ageMs);phase.readbackAge=Math.max(phase.readbackAge,ageMs);}}
    public void beginPhase(){synchronized(guard){phase=new Stats();phaseStarted=System.nanoTime();}}
    public JsonObject phase(){synchronized(guard){return json(phase);}}
    public JsonObject overall(){synchronized(guard){var result=json(overall);result.addProperty("sampler_stopped",!sampler.isAlive());return result;}}
    private static JsonObject json(Stats s){
        var out=new JsonObject();out.addProperty("waiting_max_tick_gap_ms",s.waitingGap/1_000_000);out.addProperty("armed_max_tick_gap_ms",s.armedGap/1_000_000);
        out.addProperty("state_transition_tick_gap_ms",s.transitionGap/1_000_000);
        out.addProperty("max_tick_gap_utc_ms",s.tickGapUtc);out.addProperty("max_input_tick_gap_ms",s.inputGap/1_000_000);
        out.addProperty("focused_ticks",s.focused);out.addProperty("unfocused_ticks",s.unfocused);out.addProperty("overlay_skipped_ticks",s.overlay);out.addProperty("max_readback_age_ms",s.readbackAge);
        var stages=new JsonObject();s.stageMax.forEach((name,nanos)->stages.addProperty(name,nanos/1_000_000.0));out.add("stage_max_ms",stages);out.add("slow_samples",s.slowSamples.deepCopy());return out;
    }
    private void sample(){
        long last=0;
        while(!stopped){
            try{Thread.sleep(50);}catch(InterruptedException ignored){if(stopped)return;}
            Stage observed=stage;long now=System.nanoTime();if(now-observed.at()<200_000_000L || now-last<500_000_000L)continue;
            Stats phaseAt; synchronized(guard){phaseAt=phase;if(overall.slowSamples.size()>=8 && phaseAt.slowSamples.size()>=4)continue;}
            // Stack capture is outside the lock and never performed by the render thread.
            var sample=new JsonObject();sample.addProperty("utc_ms",System.currentTimeMillis());sample.addProperty("stage",observed.name());sample.addProperty("stage_age_ms",(now-observed.at())/1_000_000);
            sample.addProperty("input_phase",lastArmed?"armed":"waiting");sample.addProperty("last_observed_focused",lastFocused);sample.addProperty("last_observed_tick_utc_ms",lastTickUtc);
            sample.addProperty("frozen_at_glfw_poll_events",frozenAtPoll.getAsBoolean());sample.addProperty("thread_state",renderThread.getState().name());
            var stack=new JsonArray();StackTraceElement[] elements=renderThread.getStackTrace();for(int i=0;i<Math.min(6,elements.length);i++){String line=elements[i].toString();stack.add(line.length()>180?line.substring(0,180):line);}sample.add("stack",stack);last=now;
            synchronized(guard){if(stopped || stage!=observed)continue;if(overall.slowSamples.size()<8)overall.slowSamples.add(sample);if(phase==phaseAt && phase.slowSamples.size()<4)phase.slowSamples.add(sample.deepCopy());}
        }
    }
    @Override public void close(){stopped=true;sampler.interrupt();try{sampler.join(300);}catch(InterruptedException e){Thread.currentThread().interrupt();}}
}
