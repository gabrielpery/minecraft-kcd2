package dev.minecome.hud;

import com.google.gson.JsonObject;
import java.io.IOException;

/** Fixture expectations and live bridge lifecycle evidence are separate contracts. */
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

    /** Completion certifies the guest bridge lifecycle, never host rendering or physical input. */
    static void requireLive(JsonObject proof)throws IOException {
        flag(proof,"input_fixture",false);flag(proof,"live_mouse",true);flag(proof,"host_armed",true);
        long applied=count(proof,"input_events_applied");
        if(applied!=count(proof,"input_consumed_sequence"))throw new IOException("Live stone input consumption incomplete");
        var field=proof.get("stone_bridge");
        if(field==null || !field.isJsonObject())throw new IOException("Live stone bridge proof missing");
        var stone=field.getAsJsonObject();
        for(String key:new String[]{"baseline_confirmed","closed","vanilla_dispatch_inventory_unchanged"})flag(stone,key,true);
        for(String key:new String[]{"failed","pending","inventory_mutated","camera_mutated","engine_mirroring_verified","visual_verified"})flag(stone,key,false);
        number(stone,"cancelled_pending",0);
        if(count(stone,"session")==0)throw new IOException("Live stone bridge was never authenticated");
        long requests=count(stone,"request_count"),accepted=count(stone,"accepted_dispatches"),confirmed=count(stone,"confirmed_actions");
        if(applied==0 && confirmed==0)throw new IOException("Live stone stream has no consumed UI input or confirmed block action");
        long placed=count(stone,"confirmed_places"),broken=count(stone,"confirmed_breaks");
        if(accepted>requests || accepted!=confirmed || confirmed!=count(stone,"block_events_queued") || placed>confirmed || broken!=confirmed-placed)
            throw new IOException("Live stone dispatch/confirmation totals differ");
        boolean cellStone=bool(stone,"confirmed_cell_stone");
        if(placed<broken || placed-broken!=(cellStone?1:0))throw new IOException("Live stone final cell differs from confirmed actions");
        long remaining=requests-accepted;
        for(String key:new String[]{"unavailable_results","stale_results","busy_results"}){
            long total=count(stone,key);if(total>remaining)throw new IOException("Live stone request result totals exceed requests");remaining-=total;
        }
        if(count(stone,"omitted_requests")>requests || count(stone,"omitted_confirmations")>confirmed)
            throw new IOException("Live stone omitted diagnostics exceed totals");
    }

    /** Physical world clicks travel through the stone transport, not the UI ring. */
    static boolean hasConfirmedLiveInteraction(JsonObject proof) {
        if(proof==null)return false;
        try {
            requireLive(proof);
            return count(proof.getAsJsonObject("stone_bridge"),"confirmed_actions")>0;
        }catch(IOException invalid){return false;}
    }

    private static boolean bool(JsonObject value,String key)throws IOException {
        var field=value.get(key);
        if(field==null || !field.isJsonPrimitive() || !field.getAsJsonPrimitive().isBoolean())
            throw new IOException("Combined stone Boolean proof missing: "+key);
        return field.getAsBoolean();
    }
    private static void flag(JsonObject value,String key,boolean expected)throws IOException {
        if(bool(value,key)!=expected)
            throw new IOException("Combined stone Boolean proof missing: "+key);
    }
    private static long count(JsonObject value,String key)throws IOException {
        var field=value.get(key);
        if(field==null || !field.isJsonPrimitive() || !field.getAsJsonPrimitive().isNumber() || !field.getAsString().matches("0|[1-9][0-9]{0,18}"))
            throw new IOException("Combined stone count missing: "+key);
        try{return Long.parseLong(field.getAsString());}
        catch(NumberFormatException invalid){throw new IOException("Combined stone count overflows: "+key,invalid);}
    }
    private static void number(JsonObject value,String key,long expected)throws IOException {
        var field=value.get(key);
        if(field==null || !field.isJsonPrimitive() || !field.getAsJsonPrimitive().isNumber() || !field.getAsString().equals(Long.toString(expected)))
            throw new IOException("Combined stone numeric proof missing: "+key);
    }
}
