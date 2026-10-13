package dev.minecome.hud;

import com.google.gson.*;
import java.io.IOException;
import java.util.*;

/** A distinct receipt contract: minor-1 dispatch acceptance cannot prove minor-2 confirmation. */
final class HudAimedStoneProof {
    private record Cell(int x,int y,int z) {
        boolean inside(Cell minimum,Cell maximum){return x>=minimum.x && x<=maximum.x && y>=minimum.y && y<=maximum.y && z>=minimum.z && z<=maximum.z;}
    }
    static void requireLive(JsonObject proof)throws IOException {
        flag(proof,"aimed_stone_bridge",true);flag(proof,"input_fixture",false);
        flag(proof,"live_mouse",true);flag(proof,"host_armed",true);
        long input=count(proof,"input_events_applied");equal(input,count(proof,"input_consumed_sequence"),"UI consumption");
        var stone=object(proof,"stone_bridge");
        requireBridge(stone);
        if(input==0 && count(stone,"confirmed_network_actions")==0)throw invalid("No consumed UI input or confirmed network interaction");
    }
    /** Shared adapter semantics only; this does not establish physical arming, UI input or KCD rendering. */
    static void requireBridge(JsonObject stone)throws IOException {
        text(stone,"kind","minecome_hud_aimed_stone_bridge_v1");equal(count(stone,"schema"),1,"schema");
        equal(count(stone,"protocol_minor"),2,"protocol minor");
        if(count(stone,"session")==0)throw invalid("Unauthenticated aimed bridge");
        var offer=object(stone,"arena_offer");long arenaId=id(offer,"arenaId",false);
        Cell seed=cell(object(offer,"seed")),minimum=cell(object(offer,"minimum")),maximum=cell(object(offer,"maximum"));
        if((long)minimum.x!=((long)seed.x)-2 || (long)minimum.y!=((long)seed.y)-2 || (long)minimum.z!=((long)seed.z)-2
                || (long)maximum.x!=((long)seed.x)+2 || (long)maximum.y!=((long)seed.y)+2 || (long)maximum.z!=((long)seed.z)+2)
            throw invalid("Arena bounds disagree with seed");
        for(String key:List.of("baseline_confirmed","arena_acknowledged","bootstrap_confirmed","closed"))flag(stone,key,true);
        for(String key:List.of("failed","pending","inventory_mutated","camera_mutated","engine_mirroring_verified","visual_verified"))flag(stone,key,false);
        equal(count(stone,"cancelled_pending"),0,"cancelled pending");
        var requests=array(stone,"requests");var confirmations=array(stone,"confirmations");
        equal(count(stone,"request_count"),requests.size(),"request count");
        if(requests.size()>16)throw invalid("Aimed request bound exceeded");
        equal(count(stone,"confirmed_actions"),confirmations.size(),"confirmation count");
        equal(count(stone,"block_events_queued"),confirmations.size(),"event count");
        Map<Long,JsonObject> byWire=new HashMap<>();Set<Long> components=new HashSet<>(),permits=new HashSet<>();long lastWire=0,network=0,places=0,breaks=0,bootstrap=0;
        for(var item:requests){
            if(!item.isJsonObject())throw invalid("Request object missing");var r=item.getAsJsonObject();var wire=object(r,"wire");
            long id=id(wire,"requestId",false);if(id<=lastWire)throw invalid("Wire IDs not increasing");lastWire=id;
            if(!permits.add(id(wire,"permitId",false)))throw invalid("Permit reused across requests");
            equal(id(wire,"arenaId",false),arenaId,"request arena");
            id(r,"component_request_id",true);
            equal(count(r,"session"),count(stone,"session"),"request session");
            equal(count(r,"world"),count(stone,"world"),"request world");equal(count(r,"reset"),count(stone,"reset"),"request reset");
            long action=count(wire,"action"),result=count(r,"result");if(action<1 || action>2 || result<1 || result>10)throw invalid("Unknown action/result");
            flag(r,"result_queued",true);flag(r,"client_and_server",result==1);
            if(result==1){flag(r,"actions_enabled",true);flag(r,"vanilla_queued",true);if(count(r,"component_request_id")==0)throw invalid("Confirmed component missing");network++;}
            byWire.put(id,r);
        }
        Set<Long> matched=new HashSet<>();Set<Cell> replayedOwned=new HashSet<>();long lastComponent=0;
        for(var item:confirmations){
            if(!item.isJsonObject())throw invalid("Confirmation object missing");var c=item.getAsJsonObject();
            long component=id(c,"component_request_id",false),wire=id(c,"wire_request_id",true),action=count(c,"action");
            if(component==0 || !components.add(component))throw invalid("Duplicate confirmation component");
            if(component<=lastComponent)throw invalid("Confirmation components not increasing");lastComponent=component;
            flag(c,"client_and_server",true);flag(c,"block_event_queued",true);
            if(action==1)places++;else if(action==2)breaks++;else throw invalid("Invalid confirmed action");
            Cell target=cell(object(c,"target"));cell(object(c,"hit_block"));
            if(!target.inside(minimum,maximum))throw invalid("Confirmed target outside arena");
            if(bool(c,"bootstrap")){
                bootstrap++;if(wire!=0 || action!=1 || components.size()!=1 || !target.equals(seed))throw invalid("Invalid bootstrap confirmation");
            }
            else{
                var r=byWire.get(wire);if(r==null || !matched.add(wire))throw invalid("Orphan/duplicate wire confirmation");
                equal(count(r,"result"),1,"confirmed wire result");equal(count(r,"component_request_id"),component,"component binding");
                equal(count(object(r,"wire"),"action"),action,"action binding");
            }
            if(action==1){if(!replayedOwned.add(target) || replayedOwned.size()>16)throw invalid("Placement duplicates/exceeds owned cells");}
            else if(!replayedOwned.remove(target))throw invalid("Break removes an unowned cell");
        }
        equal(bootstrap,1,"bootstrap count");equal(network,matched.size(),"confirmed wire correlation");
        equal(count(stone,"confirmed_network_actions"),network,"network confirmation count");
        equal(count(stone,"confirmed_places"),places,"placement count");equal(count(stone,"confirmed_breaks"),breaks,"break count");
        long owned=count(stone,"owned_count");if(breaks>places || owned>16)throw invalid("Invalid owned count");
        equal(owned,places-breaks,"owned balance");flag(stone,"guest_world_cleanup_complete",owned==0);
        equal(owned,replayedOwned.size(),"replayed owned count");
        var arena=object(stone,"arena");equal(count(arena,"owned_count"),owned,"component owned count");
        Set<Cell> observedOwned=new HashSet<>();
        for(var item:array(arena,"owned_cells")){
            if(!item.isJsonObject())throw invalid("Owned cell object missing");Cell observed=cell(item.getAsJsonObject());
            if(!observed.inside(minimum,maximum) || !observedOwned.add(observed))throw invalid("Invalid/duplicate owned cell");
        }
        if(!observedOwned.equals(replayedOwned))throw invalid("Component owned cells disagree with confirmed transitions");
    }
    static boolean hasConfirmedLiveInteraction(JsonObject proof){
        if(proof==null)return false;
        try{requireLive(proof);return count(object(proof,"stone_bridge"),"confirmed_network_actions")>0;}
        catch(IOException invalid){return false;}
    }
    private static JsonObject object(JsonObject value,String key)throws IOException{
        var field=value.get(key);if(field==null || !field.isJsonObject())throw invalid("Missing object: "+key);return field.getAsJsonObject();
    }
    private static JsonArray array(JsonObject value,String key)throws IOException{
        var field=value.get(key);if(field==null || !field.isJsonArray())throw invalid("Missing array: "+key);return field.getAsJsonArray();
    }
    private static boolean bool(JsonObject value,String key)throws IOException{
        var field=value.get(key);if(field==null || !field.isJsonPrimitive() || !field.getAsJsonPrimitive().isBoolean())throw invalid("Missing Boolean: "+key);return field.getAsBoolean();
    }
    private static void flag(JsonObject value,String key,boolean expected)throws IOException{if(bool(value,key)!=expected)throw invalid("Wrong Boolean: "+key);}
    private static long count(JsonObject value,String key)throws IOException{
        var field=value.get(key);if(field==null || !field.isJsonPrimitive() || !field.getAsJsonPrimitive().isNumber()
                || !field.getAsString().matches("0|[1-9][0-9]{0,18}"))throw invalid("Missing count: "+key);
        try{return Long.parseLong(field.getAsString());}catch(NumberFormatException e){throw invalid("Count overflow: "+key);}
    }
    private static void text(JsonObject value,String key,String expected)throws IOException{
        var field=value.get(key);if(field==null || !field.isJsonPrimitive() || !field.getAsJsonPrimitive().isString() || !field.getAsString().equals(expected))throw invalid("Wrong text: "+key);
    }
    private static void equal(long a,long b,String name)throws IOException{if(a!=b)throw invalid("Mismatched "+name);}
    private static long id(JsonObject value,String key,boolean zero)throws IOException{
        long result=count(value,key);if(result>(1L<<53)-1 || (!zero && result==0))throw invalid("Invalid identifier: "+key);return result;
    }
    private static Cell cell(JsonObject value)throws IOException{
        int[] coordinates=new int[3];int index=0;
        for(String axis:List.of("x","y","z")){
            var f=value.get(axis);if(f==null || !f.isJsonPrimitive() || !f.getAsJsonPrimitive().isNumber()
                    || !f.getAsString().matches("-?(0|[1-9][0-9]{0,9})"))throw invalid("Invalid cell axis: "+axis);
            try{coordinates[index++]=Integer.parseInt(f.getAsString());}catch(NumberFormatException e){throw invalid("Cell axis overflow: "+axis);}
        }
        return new Cell(coordinates[0],coordinates[1],coordinates[2]);
    }
    private static IOException invalid(String message){return new IOException("Aimed HUD proof: "+message);}
}
