package dev.minecome.hud;

import com.google.gson.JsonObject;
import java.io.IOException;

public final class HudStoneProofTests {
    private static int checks;
    private static JsonObject valid(){
        var proof=new JsonObject();proof.addProperty("input_events_applied",8);proof.addProperty("input_consumed_sequence",8);
        var stone=new JsonObject();proof.add("stone_bridge",stone);
        for(String key:new String[]{"baseline_confirmed","closed","vanilla_dispatch_inventory_unchanged"})stone.addProperty(key,true);
        for(String key:new String[]{"failed","pending","confirmed_cell_stone","inventory_mutated","camera_mutated","engine_mirroring_verified","visual_verified"})stone.addProperty(key,false);
        stone.addProperty("request_count",6);stone.addProperty("accepted_dispatches",4);stone.addProperty("unavailable_results",2);
        stone.addProperty("confirmed_actions",4);stone.addProperty("confirmed_places",2);stone.addProperty("confirmed_breaks",2);stone.addProperty("block_events_queued",4);
        for(String key:new String[]{"cancelled_pending","stale_results","busy_results","omitted_requests","omitted_confirmations"})stone.addProperty(key,0);
        return proof;
    }
    private static void reject(JsonObject proof)throws IOException {
        try{HudStoneProof.require(proof);}catch(IOException expected){checks++;return;}
        throw new AssertionError("Incomplete combined proof accepted");
    }
    private static JsonObject live(long placed,long broken,long unavailable){
        var proof=valid();proof.addProperty("input_fixture",false);proof.addProperty("live_mouse",true);proof.addProperty("host_armed",true);
        proof.addProperty("input_events_applied",2);proof.addProperty("input_consumed_sequence",2);
        var stone=proof.getAsJsonObject("stone_bridge");stone.addProperty("session",1);
        stone.addProperty("request_count",placed+broken+unavailable);stone.addProperty("accepted_dispatches",placed+broken);stone.addProperty("unavailable_results",unavailable);
        stone.addProperty("confirmed_actions",placed+broken);stone.addProperty("confirmed_places",placed);stone.addProperty("confirmed_breaks",broken);stone.addProperty("block_events_queued",placed+broken);
        stone.addProperty("confirmed_cell_stone",placed!=broken);return proof;
    }
    private static void rejectLive(JsonObject proof)throws IOException {
        try{HudStoneProof.requireLive(proof);}catch(IOException expected){checks++;return;}
        throw new AssertionError("Incomplete live bridge proof accepted");
    }
    private static void liveContracts()throws IOException {
        for(var proof:new JsonObject[]{live(0,0,0),live(1,0,0),live(1,1,0),live(2,2,3),live(3,2,7)}){
            HudStoneProof.requireLive(proof);checks++;
        }
        rejectLive(valid()); // Standalone proof cannot become live proof by changing its result label.
        for(String key:new String[]{"input_fixture","live_mouse","host_armed","input_events_applied","input_consumed_sequence","stone_bridge"}){
            var proof=live(1,0,1);proof.remove(key);rejectLive(proof);
        }
        for(String key:new String[]{"input_fixture","live_mouse","host_armed"}){
            var proof=live(1,0,1);proof.addProperty(key,!proof.get(key).getAsBoolean());rejectLive(proof);
        }
        for(String key:new String[]{"input_events_applied","input_consumed_sequence"}){
            for(long count:new long[]{0,1,3,-1}){var proof=live(1,0,1);proof.addProperty(key,count);rejectLive(proof);}
        }
        for(String key:live(1,0,1).getAsJsonObject("stone_bridge").keySet()){
            var proof=live(1,0,1);proof.getAsJsonObject("stone_bridge").remove(key);rejectLive(proof);
            proof=live(1,0,1);var stone=proof.getAsJsonObject("stone_bridge");stone.addProperty(key,stone.get(key).getAsString());rejectLive(proof);
            proof=live(1,0,1);stone=proof.getAsJsonObject("stone_bridge");var value=stone.get(key).getAsJsonPrimitive();
            if(value.isBoolean()){stone.addProperty(key,!value.getAsBoolean());rejectLive(proof);}
            else{
                stone.addProperty(key,-1);rejectLive(proof);
                proof=live(1,0,1);proof.getAsJsonObject("stone_bridge").addProperty(key,1.5);rejectLive(proof);
                proof=live(1,0,1);proof.getAsJsonObject("stone_bridge").add(key,com.google.gson.JsonParser.parseString("9223372036854775808"));rejectLive(proof);
            }
        }
        for(String key:new String[]{"accepted_dispatches","confirmed_actions","confirmed_places","confirmed_breaks","block_events_queued","cancelled_pending"}){
            var proof=live(1,0,1);var stone=proof.getAsJsonObject("stone_bridge");stone.addProperty(key,stone.get(key).getAsLong()+1);rejectLive(proof);
        }
        for(String key:new String[]{"unavailable_results","busy_results","stale_results","omitted_requests","omitted_confirmations"}){
            var proof=live(1,0,1);proof.getAsJsonObject("stone_bridge").addProperty(key,3);rejectLive(proof);
        }
        var proof=live(1,0,1);proof.getAsJsonObject("stone_bridge").addProperty("session",0);rejectLive(proof);
        proof=live(1,0,1);proof.getAsJsonObject("stone_bridge").addProperty("request_count",0);rejectLive(proof);
        rejectLive(live(0,1,0));rejectLive(live(2,0,0));
        proof=live(20,20,1);proof.getAsJsonObject("stone_bridge").addProperty("omitted_requests",25);proof.getAsJsonObject("stone_bridge").addProperty("omitted_confirmations",24);
        HudStoneProof.requireLive(proof);checks++; // Bounded diagnostics may omit records; totals stay truthful.
    }
    public static void main(String[] args)throws IOException {
        HudStoneProof.require(valid());checks++;
        // Different fixture contracts are not interchangeable.
        for(int count:new int[]{0,7,9,31,43}){var proof=valid();proof.addProperty("input_events_applied",count);reject(proof);}
        var proof=valid();proof.remove("stone_bridge");reject(proof);
        for(String key:valid().getAsJsonObject("stone_bridge").keySet()){
            proof=valid();proof.getAsJsonObject("stone_bridge").remove(key);reject(proof);
            proof=valid();var stone=proof.getAsJsonObject("stone_bridge");var value=stone.get(key).getAsJsonPrimitive();
            if(value.isBoolean())stone.addProperty(key,!value.getAsBoolean());else stone.addProperty(key,value.getAsInt()+1);reject(proof);
            proof=valid();stone=proof.getAsJsonObject("stone_bridge");stone.addProperty(key,stone.get(key).getAsString());reject(proof);
        }
        proof=valid();proof.addProperty("input_consumed_sequence",7);reject(proof);
        liveContracts();
        System.out.println("HudStoneProofTests: "+checks+" checks passed.");
    }
}
