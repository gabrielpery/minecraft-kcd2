package dev.minecome.hud;

/** Diagnostics must preserve blocked/batched edges and never imply native or display proof. */
final class HudMovementTimingTests {
    private static int checks;
    private static void check(boolean condition,String why){checks++;if(!condition)throw new AssertionError(why);}
    private static HudInputProtocol.Event edge(long sequence,int kind,int key){return new HudInputProtocol.Event(sequence,1000+sequence,kind,key,0,0,0);}
    static int run(){
        var timing=new HudMovementTiming();
        timing.bindings(1000,-100,false,false,false,false,false,false);
        timing.bindings(1001,-90,false,false,false,false,false,false);
        timing.event(edge(1,1,0x57),1002,-80,false); // Inventory-blocked down.
        timing.bindings(1002,-70,false,false,false,false,false,false);
        timing.event(edge(2,2,0x57),1003,-60,false);
        timing.event(edge(3,1,0x57),1004,-50,true);
        timing.event(edge(4,2,0x57),1005,-40,false); // Down/up before vanilla polls.
        timing.bindings(1005,-30,false,false,false,false,false,true);
        var proof=timing.evidence();var states=proof.getAsJsonArray("binding_states");var events=proof.getAsJsonArray("events");
        check(states.size()==3,"Idle ticks deduplicate but blocked/batched consumption stays visible");
        check(events.size()==4,"Every consumed movement edge retained including releases and blocked down");
        check(!events.get(0).getAsJsonObject().get("accepted_down").getAsBoolean(),"Inventory rejection remains rejection");
        check(events.get(2).getAsJsonObject().get("accepted_down").getAsBoolean(),"Accepted hold retained independently of actual polling");
        check(states.get(2).getAsJsonObject().get("mask").getAsInt()==0,"Batched edges do not invent effective movement");
        check(states.get(2).getAsJsonObject().get("after_input_sequence").getAsLong()==4,"Watermark names latest consumed edge only");
        check(events.get(2).getAsJsonObject().get("received_monotonic_ns").getAsLong()==-50,"Signed monotonic time preserved");
        check(!proof.get("native_application_measured").getAsBoolean() && !proof.get("display_latency_measured").getAsBoolean(),"Binding evidence cannot assert native application/display latency");
        states.get(0).getAsJsonObject().addProperty("mask",31);
        check(timing.evidence().getAsJsonArray("binding_states").get(0).getAsJsonObject().get("mask").getAsInt()==0,"Export cannot mutate retained evidence");
        timing.event(edge(5,1,0x57),900,-20,true); // Retain wall-clock adjustment without clamping.
        timing.bindings(900,-10,true,true,true,true,true,true);
        proof=timing.evidence();
        check(proof.getAsJsonArray("events").get(4).getAsJsonObject().get("received_utc_ms").getAsLong()==900,"Clock anomaly remains observable rather than fabricated zero delay");
        check(proof.getAsJsonArray("binding_states").get(3).getAsJsonObject().get("mask").getAsInt()==31,"All five actual bindings represented");
        timing.bindings(901,0,false,false,false,false,false,false);
        check(timing.evidence().getAsJsonArray("binding_states").get(4).getAsJsonObject().get("stage").getAsString().equals("release"),"Revocation/cleanup distinguished from pre-vanilla application");
        for(int i=6;i<=300;i++){
            timing.event(edge(i,1,0x57),1000+i,i,true);
            timing.bindings(1000+i,i,true,false,false,false,false,true);
        }
        proof=timing.evidence();
        check(proof.get("event_count").getAsLong()==300,"Overflow preserves complete aggregate event count");
        check(proof.get("retained_events").getAsInt()==HudMovementTiming.CAPACITY && proof.get("retained_binding_states").getAsInt()==HudMovementTiming.CAPACITY,"Both histories strictly bounded");
        check(proof.get("truncated").getAsBoolean(),"Truncation never silently claims complete evidence");
        check(proof.getAsJsonArray("events").get(HudMovementTiming.CAPACITY-1).getAsJsonObject().get("input_sequence").getAsLong()==HudMovementTiming.CAPACITY,"First retained events immutable after overflow");
        var worst=new HudMovementTiming();
        for(int i=0;i<HudMovementTiming.CAPACITY+1;i++){
            worst.event(new HudInputProtocol.Event(Long.MAX_VALUE-i,Long.MAX_VALUE,1,0x57,0,0,0),Long.MAX_VALUE,Long.MIN_VALUE,true);
            worst.bindings(Long.MAX_VALUE,Long.MIN_VALUE,true,true,true,true,true,true);
        }
        var envelope=new com.google.gson.JsonObject();var nested=envelope;
        for(String name:java.util.List.of("lab_evidence","physical_controller_fixture","physical_movement")){
            var child=new com.google.gson.JsonObject();nested.add(name,child);nested=child;
        }
        nested.add("input_timing",worst.evidence());
        int diagnosticBytes=new com.google.gson.GsonBuilder().setPrettyPrinting().create().toJson(envelope).getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
        check(diagnosticBytes<24576,"Worst-width nested pretty diagnostics leave at least 40 KiB for the shared stream receipt");
        return checks;
    }
}
