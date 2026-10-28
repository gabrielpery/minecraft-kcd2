package dev.minecome.hud;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.ArrayList;

/** Bounded client-thread observations only. Never supplies input or movement authority. */
public final class HudMovementInventoryEvidence {
    public static final int MAX_WINDOWS=4,MAX_EVENTS=32;
    public static final long FRESH_NS=250_000_000L,MIN_WINDOW_NS=250_000_000L;
    private static final double STILL=.01,RESUMED=.05;
    public record Position(double x,double y,double z) {
        boolean finite(){return Double.isFinite(x)&&Double.isFinite(y)&&Double.isFinite(z)&&Math.abs(x)<=30_000_000&&Math.abs(y)<=30_000_000&&Math.abs(z)<=30_000_000;}
    }
    public record Frame(long utcMs,long ns,boolean inventory,Position client,Position server,
                        long serverSequence,long serverNs,boolean clientGrounded,boolean serverGrounded,int bindingMask,boolean beforeVanilla) {}
    private record Edge(long sequence,long capturedUtc,long receivedUtc,long ns,int kind,int key,
                        boolean accepted,boolean inventory,int window,boolean contextObserved) {}
    private static final class Resume {
        final Edge edge;final Position client,server;
        boolean binding;long stale,lastServerSequence,lastServerNs;double clientDistance,serverDistance,clientFromClose,serverFromClose;
        Resume(Edge edge,Frame f){this.edge=edge;client=f.client();server=f.server();lastServerSequence=f.serverSequence();lastServerNs=f.serverNs();}
    }
    private static final class Window {
        final int id;final long openedUtc,openedNs;final Position client,server;
        long closedUtc,closedNs,observations,samples,stale,maxGap,maxAge,lastNs,lastServerSequence,lastServerNs;
        long intervalServerSequence,serverAdvances,nonzeroBindings,inventoryDowns,inventoryReleases;
        int bindingsOr;double clientDistance,serverDistance,error;
        boolean closed,allGrounded=true,physicalAttempt;
        Position closeClient,closeServer;Resume resume;
        Window(int id,Frame f){this.id=id;openedUtc=f.utcMs();openedNs=f.ns();client=f.client();server=f.server();}
    }
    private final ArrayList<Window> windows=new ArrayList<>();
    private final ArrayList<Edge> edges=new ArrayList<>();
    private Frame last;
    private Window active,resumeWindow;
    private long windowCount,eventCount,lastEventSequence;
    private boolean inventory,finished,truncated;
    private String failure;

    private static double distance(Position a,Position b){return a==null||b==null||!a.finite()||!b.finite()?0:Math.sqrt(Math.pow(a.x()-b.x(),2)+Math.pow(a.y()-b.y(),2)+Math.pow(a.z()-b.z(),2));}
    private static boolean fresh(Frame f){return f.client()!=null&&f.server()!=null&&f.client().finite()&&f.server().finite()
            &&f.serverSequence()>0&&f.ns()>=f.serverNs()&&f.ns()-f.serverNs()>=0&&f.ns()-f.serverNs()<=FRESH_NS;}
    private void fail(String reason){if(failure==null)failure=reason;}
    public void observe(Frame f){
        if(finished)return;
        if(last!=null&&(f.ns()<last.ns()||f.utcMs()<last.utcMs()))fail("observation_clock_regressed");
        if(f.bindingMask()<0||f.bindingMask()>31)fail("invalid_binding_mask");
        if(f.inventory()&&!inventory){
            windowCount++;resumeWindow=null;
            if(windows.size()<MAX_WINDOWS){active=new Window((int)windowCount,f);windows.add(active);}
            else {active=null;truncated=true;}
        }
        if(active!=null){
            observeWindow(active,f);
            if(!f.inventory()){
                active.closed=true;active.closedUtc=f.utcMs();active.closedNs=f.ns();
                active.closeClient=f.client();active.closeServer=f.server();resumeWindow=active;active=null;
            }
        } else if(!f.inventory()&&resumeWindow!=null&&resumeWindow.resume!=null)observeResume(resumeWindow,f);
        inventory=f.inventory();last=f;
    }
    private void observeWindow(Window w,Frame f){
        if(w.observations++>0)w.maxGap=Math.max(w.maxGap,f.ns()-w.lastNs);w.lastNs=f.ns();
        if(f.server()!=null)w.maxAge=Math.max(w.maxAge,f.ns()-f.serverNs());
        boolean valid=fresh(f);
        if(valid&&w.lastServerSequence>0&&(f.serverSequence()<w.lastServerSequence||f.serverNs()<w.lastServerNs
                ||(f.serverSequence()==w.lastServerSequence&&f.serverNs()!=w.lastServerNs)))valid=false;
        if(!valid)w.stale++;
        else {
            w.lastServerSequence=f.serverSequence();w.lastServerNs=f.serverNs();
            // A still-fresh pre-open server observation is not evidence of what
            // happened while the inventory was actually open.
            if(f.serverNs()>=w.openedNs){
                w.samples++;
                if(w.intervalServerSequence>0&&f.serverSequence()>w.intervalServerSequence)w.serverAdvances++;
                w.intervalServerSequence=f.serverSequence();
            }
        }
        w.allGrounded&=valid&&f.clientGrounded()&&f.serverGrounded();
        w.clientDistance=Math.max(w.clientDistance,distance(w.client,f.client()));
        w.serverDistance=Math.max(w.serverDistance,distance(w.server,f.server()));
        w.error=Math.max(w.error,distance(f.client(),f.server()));
        if(f.bindingMask()!=0)w.nonzeroBindings++;w.bindingsOr|=f.bindingMask();
    }
    /** Same immutable received clocks as HudMovementTiming; native-suppressed edges are absent. */
    public void event(HudInputProtocol.Event event,long receivedUtc,long receivedNs,boolean acceptedDown){
        if(finished)return;
        if(event.sequence()<=lastEventSequence)fail("input_sequence_regressed");lastEventSequence=event.sequence();
        if(last!=null&&(receivedNs<last.ns()||receivedUtc<last.utcMs()))fail("input_clock_regressed");
        eventCount++;
        var edge=new Edge(event.sequence(),event.capturedUtcMs(),receivedUtc,receivedNs,event.kind(),event.code(),
                acceptedDown,inventory,active==null?0:active.id,last!=null);
        if(edges.size()<MAX_EVENTS)edges.add(edge);else truncated=true;
        if(active!=null){
            if(event.kind()==1){active.inventoryDowns++;if(event.code()==0x57)active.physicalAttempt=true;}
            if(event.kind()==2)active.inventoryReleases++;
            if(acceptedDown)fail("inventory_movement_down_accepted");
        } else if(!inventory&&resumeWindow!=null&&resumeWindow.resume==null&&acceptedDown&&event.kind()==1
                &&event.code()!=0x20&&HudMovementKeys.movement(event.code())&&last!=null&&fresh(last)
                &&receivedNs>resumeWindow.closedNs&&event.capturedUtcMs()>=resumeWindow.closedUtc
                &&receivedNs>=last.ns()&&receivedNs-last.ns()>=0&&receivedNs-last.ns()<=FRESH_NS){
            resumeWindow.resume=new Resume(edge,last);
        }
    }
    private void observeResume(Window w,Frame f){
        var r=w.resume;
        if(!fresh(f)){r.stale++;return;}
        if(f.serverSequence()<r.lastServerSequence||f.serverNs()<r.lastServerNs
                ||(f.serverSequence()==r.lastServerSequence&&f.serverNs()!=r.lastServerNs)){r.stale++;return;}
        r.lastServerSequence=f.serverSequence();r.lastServerNs=f.serverNs();
        int bit=switch(r.edge.key()){case 0x57->1;case 0x53->2;case 0x41->4;case 0x44->8;default->0;};
        if(f.beforeVanilla()&&f.ns()>r.edge.ns()&&(f.bindingMask()&bit)!=0)r.binding=true;
        // A short valid key pulse can reach vanilla before the next server tick.
        // Keep that actual binding, but only newer server observations can prove
        // the following movement on both sides.
        if(f.serverNs()<r.edge.ns())return;
        r.clientDistance=Math.max(r.clientDistance,distance(r.client,f.client()));
        r.serverDistance=Math.max(r.serverDistance,distance(r.server,f.server()));
        r.clientFromClose=Math.max(r.clientFromClose,distance(w.closeClient,f.client()));
        r.serverFromClose=Math.max(r.serverFromClose,distance(w.closeServer,f.server()));
    }
    /** Cleanup never synthesizes a close transition or an accepted return to walking. */
    public void finish(){finished=true;}
    private boolean complete(){return finished&&!inventory&&!truncated&&failure==null;}
    private boolean immobile(Window w){return complete()&&w.closed&&w.closedNs-w.openedNs>=MIN_WINDOW_NS
            &&w.samples>=3&&w.serverAdvances>=2&&w.stale==0&&w.maxGap<=FRESH_NS&&w.maxAge<=FRESH_NS
            &&w.clientDistance<=STILL&&w.serverDistance<=STILL&&w.error<=STILL&&w.allGrounded&&w.nonzeroBindings==0&&w.bindingsOr==0;}
    public JsonObject evidence(){
        var out=new JsonObject();out.addProperty("schema",1);out.addProperty("kind","minecome_hud_movement_inventory_v1");
        out.addProperty("capture_finished",finished);out.addProperty("capture_complete",complete());
        out.addProperty("max_windows",MAX_WINDOWS);out.addProperty("max_events",MAX_EVENTS);out.addProperty("window_count",windowCount);out.addProperty("event_count",eventCount);
        out.addProperty("truncated",truncated);out.addProperty("failure",failure);
        out.addProperty("physical_attempt_observed",false);
        out.addProperty("delivered_w_down_observed",windows.stream().anyMatch(w->w.physicalAttempt));
        out.addProperty("clock_note","Observed actual inventory screen on the client thread; monotonic clocks share the JVM. No unobserved native-suppressed input is inferred.");
        var rows=new JsonArray();
        for(var w:windows){
            var row=new JsonObject();row.addProperty("id",w.id);row.addProperty("opened_utc_ms",w.openedUtc);row.addProperty("opened_monotonic_ns",w.openedNs);
            row.addProperty("closed_utc_ms",w.closed?w.closedUtc:null);row.addProperty("closed_monotonic_ns",w.closed?w.closedNs:null);row.addProperty("complete",w.closed);
            row.addProperty("samples",w.samples);row.addProperty("server_sequence_advances",w.serverAdvances);row.addProperty("stale_samples",w.stale);
            row.addProperty("max_sample_gap_ns",w.maxGap);row.addProperty("max_server_age_ns",w.maxAge);
            row.addProperty("max_client_displacement",w.clientDistance);row.addProperty("max_server_displacement",w.serverDistance);row.addProperty("client_server_max_error",w.error);
            row.addProperty("all_grounded",w.allGrounded);row.addProperty("nonzero_binding_samples",w.nonzeroBindings);row.addProperty("bindings_or",w.bindingsOr);
            row.addProperty("inventory_down_events",w.inventoryDowns);row.addProperty("inventory_release_events",w.inventoryReleases);row.addProperty("physical_attempt_observed",false);row.addProperty("delivered_w_down_observed",w.physicalAttempt);
            row.addProperty("immobility_verified",immobile(w));
            var resume=new JsonObject();var r=w.resume;
            resume.addProperty("input_sequence",r==null?0:r.edge.sequence());resume.addProperty("key",r==null?0:r.edge.key());
            resume.addProperty("captured_utc_ms",r==null?0:r.edge.capturedUtc());resume.addProperty("received_utc_ms",r==null?0:r.edge.receivedUtc());resume.addProperty("received_monotonic_ns",r==null?0:r.edge.ns());
            resume.addProperty("binding_observed",r!=null&&r.binding);resume.addProperty("stale_samples",r==null?0:r.stale);
            resume.addProperty("client_displacement",r==null?0:r.clientDistance);resume.addProperty("server_displacement",r==null?0:r.serverDistance);
            resume.addProperty("client_displacement_from_close",r==null?0:r.clientFromClose);resume.addProperty("server_displacement_from_close",r==null?0:r.serverFromClose);
            resume.addProperty("verified",immobile(w)&&r!=null&&r.stale==0&&r.binding&&r.clientDistance>=RESUMED&&r.serverDistance>=RESUMED&&r.clientFromClose>=RESUMED&&r.serverFromClose>=RESUMED);
            row.add("resumed_movement",resume);rows.add(row);
        }
        out.add("windows",rows);var events=new JsonArray();
        for(var e:edges){var row=new JsonObject();row.addProperty("input_sequence",e.sequence());row.addProperty("captured_utc_ms",e.capturedUtc());row.addProperty("received_utc_ms",e.receivedUtc());row.addProperty("received_monotonic_ns",e.ns());
            row.addProperty("kind",e.kind());row.addProperty("key",e.key());row.addProperty("accepted_down",e.accepted());row.addProperty("inventory_open",e.inventory());row.addProperty("window_id",e.window());row.addProperty("context_observed",e.contextObserved());events.add(row);}
        out.add("events",events);return out;
    }
}
