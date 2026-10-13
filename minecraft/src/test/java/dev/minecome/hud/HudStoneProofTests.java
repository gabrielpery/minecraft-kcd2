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
        System.out.println("HudStoneProofTests: "+checks+" checks passed.");
    }
}
