package dev.minecome.hud;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.ArrayList;

/** Client-thread diagnostics only. Never supplies input, clocks or authority to movement. */
public final class HudMovementTiming {
    // Final stream receipts share a 64 KiB budget with HUD/cleanup evidence.
    static final int CAPACITY=32;
    private record Edge(long sequence,long capturedUtc,long receivedUtc,long receivedNs,int kind,int key,boolean acceptedDown){}
    private record State(long afterSequence,long utc,long ns,int mask,boolean beforeVanilla){}
    private final ArrayList<Edge> edges=new ArrayList<>();
    private final ArrayList<State> states=new ArrayList<>();
    private long edgeCount,stateCount,lastSequence;
    private State previous;

    public void event(HudInputProtocol.Event event,long receivedUtc,long receivedNs,boolean acceptedDown){
        edgeCount++;lastSequence=event.sequence();
        if(edges.size()<CAPACITY)edges.add(new Edge(event.sequence(),event.capturedUtcMs(),receivedUtc,receivedNs,event.kind(),event.code(),acceptedDown));
    }
    /** Record actual KeyBinding values after the writes, not the requested hold state. */
    public void bindings(long utc,long ns,boolean forward,boolean back,boolean left,boolean right,boolean jump,boolean beforeVanilla){
        int mask=(forward?1:0)|(back?2:0)|(left?4:0)|(right?8:0)|(jump?16:0);
        // Idle ticks add no useful information. Keep a new watermark even when
        // opposite edges cancel within a batch, without inventing a key press.
        if(previous!=null && previous.afterSequence()==lastSequence && previous.mask()==mask && previous.beforeVanilla()==beforeVanilla)return;
        previous=new State(lastSequence,utc,ns,mask,beforeVanilla);stateCount++;
        if(states.size()<CAPACITY)states.add(previous);
    }
    public JsonObject evidence(){
        var out=new JsonObject();out.addProperty("schema",1);out.addProperty("kind","minecome_hud_movement_timing_v1");
        out.addProperty("event_count",edgeCount);out.addProperty("binding_state_count",stateCount);
        out.addProperty("retained_events",edges.size());out.addProperty("retained_binding_states",states.size());
        out.addProperty("truncated",edgeCount>edges.size() || stateCount>states.size());
        out.addProperty("capacity_per_series",CAPACITY);
        out.addProperty("clock_note","UTC capture comes from the input producer; monotonic timestamps share the Minecraft JVM clock. UTC differences are diagnostic and may reflect clock adjustment.");
        out.addProperty("binding_mask_bits","W=1,S=2,A=4,D=8,Space=16");
        out.addProperty("sequence_note","after_input_sequence is the latest consumed movement-edge sequence, not the global UI watermark or proof every edge affected vanilla. Batched down/up edges may cancel before polling.");
        out.addProperty("native_application_measured",false);out.addProperty("display_latency_measured",false);
        var eventRows=new JsonArray();
        for(var edge:edges){
            var row=new JsonObject();row.addProperty("input_sequence",edge.sequence());row.addProperty("captured_utc_ms",edge.capturedUtc());
            row.addProperty("received_utc_ms",edge.receivedUtc());row.addProperty("received_monotonic_ns",edge.receivedNs());
            row.addProperty("kind",edge.kind());row.addProperty("key",edge.key());row.addProperty("accepted_down",edge.acceptedDown());
            eventRows.add(row);
        }
        out.add("events",eventRows);
        var bindingRows=new JsonArray();
        for(var state:states){
            var row=new JsonObject();row.addProperty("after_input_sequence",state.afterSequence());row.addProperty("utc_ms",state.utc());
            row.addProperty("monotonic_ns",state.ns());row.addProperty("mask",state.mask());
            row.addProperty("stage",state.beforeVanilla()?"before_vanilla_poll":"release");bindingRows.add(row);
        }
        out.add("binding_states",bindingRows);return out;
    }
}
