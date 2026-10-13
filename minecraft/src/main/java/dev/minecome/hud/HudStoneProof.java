package dev.minecome.hud;

import com.google.gson.JsonObject;
import java.io.IOException;

/** Separate terminal contract: this fixture selects two slots and does not swap stacks. */
final class HudStoneProof {
    static void require(JsonObject proof)throws IOException {
        number(proof,"input_events_applied",8);number(proof,"input_consumed_sequence",8);
        var stone=proof.getAsJsonObject("stone_bridge");
        if(stone==null)throw new IOException("Combined stone proof missing");
        for(String key:new String[]{"baseline_confirmed","closed","vanilla_dispatch_inventory_unchanged"})flag(stone,key,true);
        for(String key:new String[]{"failed","pending","confirmed_cell_stone","inventory_mutated","camera_mutated","engine_mirroring_verified","visual_verified"})flag(stone,key,false);
        number(stone,"request_count",6);number(stone,"accepted_dispatches",4);number(stone,"unavailable_results",2);
        number(stone,"confirmed_actions",4);number(stone,"confirmed_places",2);number(stone,"confirmed_breaks",2);number(stone,"block_events_queued",4);
        for(String key:new String[]{"cancelled_pending","stale_results","busy_results","omitted_requests","omitted_confirmations"})number(stone,key,0);
    }
    private static void flag(JsonObject value,String key,boolean expected)throws IOException {
        var field=value.get(key);
        if(field==null || !field.isJsonPrimitive() || !field.getAsJsonPrimitive().isBoolean() || field.getAsBoolean()!=expected)
            throw new IOException("Combined stone Boolean proof missing: "+key);
    }
    private static void number(JsonObject value,String key,long expected)throws IOException {
        var field=value.get(key);
        if(field==null || !field.isJsonPrimitive() || !field.getAsJsonPrimitive().isNumber() || !field.getAsString().equals(Long.toString(expected)))
            throw new IOException("Combined stone numeric proof missing: "+key);
    }
}
