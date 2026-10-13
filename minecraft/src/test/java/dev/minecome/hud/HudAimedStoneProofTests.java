package dev.minecome.hud;

import com.google.gson.*;
import java.io.IOException;
import java.util.function.Consumer;

/** Synthetic receipt correlation only; never claims a game or physical input test. */
public final class HudAimedStoneProofTests {
    private static int checks;
    private static JsonObject valid() {
        return JsonParser.parseString("""
            {"aimed_stone_bridge":true,"input_fixture":false,"live_mouse":true,"host_armed":true,
             "input_events_applied":0,"input_consumed_sequence":0,"stone_bridge":{
              "schema":1,"kind":"minecome_hud_aimed_stone_bridge_v1","protocol_minor":2,
              "session":1,"world":1,"reset":1,"baseline_confirmed":true,"arena_acknowledged":true,
              "bootstrap_confirmed":true,"closed":true,"failed":false,"pending":false,
              "inventory_mutated":false,"camera_mutated":false,"engine_mirroring_verified":false,
              "visual_verified":false,"cancelled_pending":0,"request_count":1,"confirmed_actions":2,
              "block_events_queued":2,"confirmed_network_actions":1,"confirmed_places":1,
              "confirmed_breaks":1,"owned_count":0,"guest_world_cleanup_complete":true,
              "arena":{"owned_count":0,"owned_cells":[]},
              "arena_offer":{"arenaId":1,"minecraftAnchor":{"x":0.5,"y":65.62,"z":0.5},
               "kcdAnchor":{"x":100,"y":200,"z":50},"blocksPerUnit":1,
               "seed":{"x":2,"y":64,"z":0},"minimum":{"x":0,"y":62,"z":-2},"maximum":{"x":4,"y":66,"z":2}},
              "requests":[{"wire":{"arenaId":1,"requestId":1,"permitId":1,"action":2},
               "session":1,"world":1,"reset":1,"result":1,"result_queued":true,
               "client_and_server":true,"actions_enabled":true,"vanilla_queued":true,"component_request_id":2}],
              "confirmations":[
               {"component_request_id":1,"wire_request_id":0,"action":1,"bootstrap":true,
                "client_and_server":true,"block_event_queued":true,"target":{"x":2,"y":64,"z":0},"hit_block":{"x":2,"y":63,"z":0}},
               {"component_request_id":2,"wire_request_id":1,"action":2,"bootstrap":false,
                "client_and_server":true,"block_event_queued":true,"target":{"x":2,"y":64,"z":0},"hit_block":{"x":2,"y":64,"z":0}}]}}
            """).getAsJsonObject();
    }
    private static JsonObject stone(JsonObject p){return p.getAsJsonObject("stone_bridge");}
    private static JsonObject request(JsonObject p){return stone(p).getAsJsonArray("requests").get(0).getAsJsonObject();}
    private static JsonObject wire(JsonObject p){return request(p).getAsJsonObject("wire");}
    private static JsonObject confirmation(JsonObject p){return stone(p).getAsJsonArray("confirmations").get(1).getAsJsonObject();}
    private static JsonObject cell(int x,int y,int z){var c=new JsonObject();c.addProperty("x",x);c.addProperty("y",y);c.addProperty("z",z);return c;}
    private static JsonObject twoOwnedCells(){
        var p=valid();var s=stone(p);wire(p).addProperty("action",1);confirmation(p).addProperty("action",1);
        confirmation(p).add("target",cell(3,64,0));s.addProperty("confirmed_places",2);s.addProperty("confirmed_breaks",0);
        s.addProperty("owned_count",2);s.addProperty("guest_world_cleanup_complete",false);
        var a=s.getAsJsonObject("arena");a.addProperty("owned_count",2);a.getAsJsonArray("owned_cells").add(cell(2,64,0));a.getAsJsonArray("owned_cells").add(cell(3,64,0));return p;
    }
    private static JsonObject placeThenBreak(){
        var p=twoOwnedCells();var s=stone(p);var r=request(p).deepCopy();r.addProperty("component_request_id",3);
        r.getAsJsonObject("wire").addProperty("requestId",2);r.getAsJsonObject("wire").addProperty("permitId",2);r.getAsJsonObject("wire").addProperty("action",2);
        s.getAsJsonArray("requests").add(r);var c=confirmation(p).deepCopy();c.addProperty("component_request_id",3);
        c.addProperty("wire_request_id",2);c.addProperty("action",2);c.add("target",cell(2,64,0));s.getAsJsonArray("confirmations").add(c);
        s.addProperty("request_count",2);s.addProperty("confirmed_actions",3);s.addProperty("block_events_queued",3);
        s.addProperty("confirmed_network_actions",2);s.addProperty("confirmed_breaks",1);s.addProperty("owned_count",1);
        s.getAsJsonObject("arena").addProperty("owned_count",1);s.getAsJsonObject("arena").getAsJsonArray("owned_cells").remove(0);return p;
    }
    private static void reject(JsonObject proof) throws IOException {
        try { HudAimedStoneProof.requireLive(proof); }
        catch(IOException expected){checks++;return;}
        throw new AssertionError("Uncorrelated aimed HUD receipt accepted");
    }
    private static void mutate(Consumer<JsonObject> edit)throws IOException {var p=valid();edit.accept(p);reject(p);}
    public static void main(String[] args)throws Exception {
        var p=valid();HudAimedStoneProof.requireLive(p);checks++;
        if(!HudAimedStoneProof.hasConfirmedLiveInteraction(p))throw new AssertionError("Confirmed network action lost");checks++;
        mutate(v->v.addProperty("aimed_stone_bridge",false));
        mutate(v->stone(v).addProperty("kind","minecome_hud_stone_bridge_v1"));
        mutate(v->stone(v).addProperty("protocol_minor",1));
        mutate(v->stone(v).addProperty("session",0));
        mutate(v->v.addProperty("input_consumed_sequence",1));
        mutate(v->request(v).addProperty("client_and_server",false));
        mutate(v->request(v).addProperty("result_queued",false));
        mutate(v->request(v).addProperty("actions_enabled",false));
        mutate(v->request(v).addProperty("vanilla_queued",false));
        mutate(v->request(v).addProperty("world",2));
        mutate(v->request(v).addProperty("reset",2));
        mutate(v->request(v).addProperty("result",2));
        mutate(v->confirmation(v).addProperty("wire_request_id",99));
        mutate(v->confirmation(v).addProperty("component_request_id",3));
        mutate(v->confirmation(v).addProperty("action",1));
        mutate(v->confirmation(v).addProperty("bootstrap",true));
        mutate(v->confirmation(v).addProperty("client_and_server",false));
        mutate(v->confirmation(v).add("target",new JsonObject()));
        mutate(v->confirmation(v).getAsJsonObject("hit_block").addProperty("x","2"));
        mutate(v->wire(v).addProperty("permitId",0));
        mutate(v->wire(v).addProperty("permitId",9007199254740992L));
        mutate(v->wire(v).addProperty("arenaId",2));
        mutate(v->{wire(v).addProperty("requestId",9007199254740992L);confirmation(v).addProperty("wire_request_id",9007199254740992L);});
        mutate(v->{request(v).addProperty("component_request_id",9007199254740992L);confirmation(v).addProperty("component_request_id",9007199254740992L);});
        mutate(v->stone(v).addProperty("owned_count",1));
        mutate(v->stone(v).addProperty("guest_world_cleanup_complete",false));
        mutate(v->stone(v).addProperty("block_events_queued",1));
        mutate(v->stone(v).addProperty("cancelled_pending",1));
        mutate(v->stone(v).addProperty("visual_verified",true));
        mutate(v->stone(v).addProperty("confirmed_actions",2.5));
        mutate(v->{stone(v).getAsJsonArray("requests").add(request(v).deepCopy());stone(v).addProperty("request_count",2);});
        // Counts alone cannot prove cleanup: replay the exact confirmed cells.
        mutate(v->confirmation(v).add("target",cell(99,64,0)));
        mutate(v->confirmation(v).add("target",cell(3,64,0)));
        mutate(v->stone(v).getAsJsonArray("confirmations").get(0).getAsJsonObject().add("target",cell(3,64,0)));
        mutate(v->stone(v).getAsJsonObject("arena_offer").getAsJsonObject("maximum").addProperty("x",99));
        mutate(v->stone(v).getAsJsonObject("arena").addProperty("owned_count",1));
        mutate(v->stone(v).getAsJsonObject("arena").getAsJsonArray("owned_cells").add(cell(2,64,0)));
        p=twoOwnedCells();HudAimedStoneProof.requireLive(p);checks++;
        confirmation(p).add("target",cell(2,64,0));reject(p); // duplicate placement
        p=twoOwnedCells();var owned=stone(p).getAsJsonObject("arena").getAsJsonArray("owned_cells");
        owned.set(1,cell(4,64,0));reject(p); // same count, wrong component cells
        p=twoOwnedCells();stone(p).getAsJsonObject("arena").getAsJsonArray("owned_cells").add(cell(3,64,0));reject(p);
        p=placeThenBreak();HudAimedStoneProof.requireLive(p);checks++;
        stone(p).getAsJsonArray("requests").get(1).getAsJsonObject().getAsJsonObject("wire").addProperty("permitId",1);reject(p);
        // A refused aiming request with real UI input is a valid completed guest
        // session, but must never count as an authoritative block interaction.
        p=valid();p.addProperty("input_events_applied",4);p.addProperty("input_consumed_sequence",4);
        var s=stone(p);s.getAsJsonArray("confirmations").remove(1);s.addProperty("confirmed_actions",1);
        s.addProperty("block_events_queued",1);s.addProperty("confirmed_network_actions",0);s.addProperty("confirmed_breaks",0);
        s.addProperty("owned_count",1);s.addProperty("guest_world_cleanup_complete",false);
        s.getAsJsonObject("arena").addProperty("owned_count",1);s.getAsJsonObject("arena").getAsJsonArray("owned_cells").add(cell(2,64,0));
        request(p).addProperty("result",3);request(p).addProperty("client_and_server",false);
        request(p).addProperty("vanilla_queued",false);request(p).addProperty("component_request_id",0);
        HudAimedStoneProof.requireLive(p);checks++;
        if(HudAimedStoneProof.hasConfirmedLiveInteraction(p))throw new AssertionError("Refusal became gameplay proof");checks++;
        p.addProperty("input_events_applied",0);p.addProperty("input_consumed_sequence",0);reject(p);
        System.out.println("HudAimedStoneProofTests: "+checks+" checks passed (synthetic receipts).");
    }
}
