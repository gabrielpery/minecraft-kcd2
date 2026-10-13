package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.hud.mixin.*;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ingame.*;
import net.minecraft.item.*;
import net.minecraft.registry.Registries;
import net.minecraft.screen.slot.Slot;
import java.util.*;

/** Observes real Screen/inventory results; the native fixture alone supplies input. */
final class HudPointerFixture {
    private static final String[] STAGES={"opened","split","split_restored","picked_up","distributed","scrolled","scroll_restored","closed_held","reopened_held","late_release","complete"};
    private static final int[] SEQUENCES={20,23,25,27,32,33,34,38,40,41,43};
    private static final String[] FIXED_ITEMS={"minecraft:dirt","minecraft:cobblestone","minecraft:oak_planks","minecraft:stick","minecraft:apple","minecraft:torch"};
    private static final int[] FIXED_COUNTS={32,16,8,3,2,12};
    private int stage;
    private CreativeInventoryScreen firstScreen;
    private float initialScroll;
    private JsonArray initialGrid;
    private JsonObject lastProof;
    private final JsonArray completedStages=new JsonArray();
    private boolean split,distributed,scrolled,scrollRestored,heldClosed,reopened,lateReleased;

    void observe(MinecraftClient client,HudVanillaUiAdapter ui,long applied,long serverAgeMs,boolean serverConfirmed,JsonArray serverSlots,HudStreamProducer output){
        if(stage==STAGES.length)return;
        if(applied<SEQUENCES[stage])return;
        if(applied>SEQUENCES[stage])throw new IllegalStateException("Pointer fixture advanced before stage proof: "+STAGES[stage]);
        if(!serverConfirmed || serverAgeMs<0 || serverAgeMs>250)return;
        boolean open=HudVanillaUiAdapter.inventory(client.currentScreen);
        boolean shouldOpen=stage!=7 && stage!=10;
        if(open!=shouldOpen)return;
        if(open && !(client.currentScreen instanceof CreativeInventoryScreen))throw new IllegalStateException("Pointer fixture needs actual Creative inventory");
        var screen=open?(CreativeInventoryScreen)client.currentScreen:null;
        ItemStack cursor=screen!=null?screen.getScreenHandler().getCursorStack():client.player.currentScreenHandler.getCursorStack();
        int stone=stage==0 || stage==2?64:stage==1?32:0,destination=stage>=4?32:0,cursorCount=stage==1?32:stage==3?64:0;
        if(!matches(cursor,cursorCount==0?"minecraft:air":"minecraft:stone",cursorCount))return;
        for(int i=0;i<9;i++){
            int count=i==0?stone:i>=7?destination:FIXED_COUNTS[i-1];
            String item=i==0 || i>=7?(count==0?"minecraft:air":"minecraft:stone"):FIXED_ITEMS[i-1];
            if(!matches(client.player.getInventory().getStack(i),item,count))return;
        }
        JsonObject proof=ui.pointerDiagnostics();
        float scroll=screen==null?Float.NaN:((HudCreativeScreenAccessor)screen).minecome$scrollPosition();
        JsonArray grid=screen==null?null:grid(client,screen);
        if(stage==0){
            if(!((HudCreativeScreenAccessor)screen).minecome$hasScrollbar() || scroll!=0 || grid.size()!=45)throw new IllegalStateException("Pointer fixture requires the actual initial scrollable Creative grid");
            firstScreen=screen;initialScroll=scroll;initialGrid=grid.deepCopy();proof.add("targets",targets(client,screen));
        }
        boolean gridMatches=grid!=null && grid.equals(initialGrid);
        if(stage==1)split=true;
        if(stage==4){if(proof.get("mouse_drag_calls").getAsLong()<2)return;distributed=true;}
        if(stage==5){if(!(scroll>initialScroll) || gridMatches || proof.get("wheel_calls").getAsLong()!=1)return;scrolled=true;}
        if(stage==6){if(Math.abs(scroll-initialScroll)>0.000001 || !gridMatches || proof.get("wheel_calls").getAsLong()!=2)return;scrollRestored=true;}
        if(stage==7 || stage==8 || stage==9 || stage==10){
            if(proof.get("held_buttons").getAsInt()!=0 || proof.get("active_button").getAsInt()!=-1 || proof.get("cleanup_releases").getAsInt()!=1)return;
            if(stage==7 || stage==8){if(proof.get("pending_releases").getAsInt()!=1 || proof.get("late_releases_consumed").getAsInt()!=0)return;}
            else if(proof.get("pending_releases").getAsInt()!=0 || proof.get("late_releases_consumed").getAsInt()!=1)return;
            if(proof.get("screen_generation").getAsLong()!=(stage==7?1:2))return;
            if(stage==7)heldClosed=true;
            if(stage==8){if(screen==firstScreen)return;reopened=true;}
            if(stage==9)lateReleased=true;
        }
        proof.addProperty("stage",STAGES[stage]);proof.addProperty("applied_sequence",applied);proof.addProperty("server_confirmed",true);proof.addProperty("server_observation_age_ms",serverAgeMs);
        proof.addProperty("inventory_open",open);proof.addProperty("initial_scroll_position",initialScroll);
        if(screen==null)proof.add("scroll_position",JsonNull.INSTANCE);else proof.addProperty("scroll_position",scroll);
        proof.addProperty("grid_matches_initial",gridMatches);proof.addProperty("grid_changed_verified",scrolled);
        proof.add("client_slots",inventory(client));proof.add("server_slots",serverSlots.deepCopy());proof.add("cursor",stack(cursor));
        output.offerPointerStage(STAGES[stage],proof);
        var summary=new JsonObject();summary.addProperty("stage",STAGES[stage]);summary.addProperty("applied_sequence",applied);summary.addProperty("server_observation_age_ms",serverAgeMs);completedStages.add(summary);
        lastProof=proof.deepCopy();stage++;
    }
    boolean complete(){return stage==STAGES.length;}
    JsonObject evidence(){
        JsonObject proof=lastProof==null?new JsonObject():lastProof.deepCopy();
        proof.addProperty("completed",complete());proof.addProperty("expected_events",43);proof.add("stages",completedStages.deepCopy());
        proof.addProperty("right_split_verified",split);proof.addProperty("drag_distribution_verified",distributed);proof.addProperty("scroll_changed_verified",scrolled);proof.addProperty("scroll_restored_verified",scrollRestored);
        proof.addProperty("held_close_release_verified",heldClosed);proof.addProperty("reopened_screen_verified",reopened);proof.addProperty("late_release_consumed_verified",lateReleased);
        proof.addProperty("cursor_empty",lastProof!=null && lastProof.getAsJsonObject("cursor").get("count").getAsInt()==0);proof.addProperty("server_inventory_verified",complete());return proof;
    }
    private static boolean matches(ItemStack stack,String item,int count){return stack.getCount()==count && Registries.ITEM.getId(stack.getItem()).toString().equals(item);}
    private static JsonObject stack(ItemStack stack){var p=new JsonObject();p.addProperty("item",Registries.ITEM.getId(stack.getItem()).toString());p.addProperty("count",stack.getCount());return p;}
    private static JsonArray inventory(MinecraftClient client){var a=new JsonArray();for(int i=0;i<9;i++){var p=stack(client.player.getInventory().getStack(i));p.addProperty("slot",i);a.add(p);}return a;}
    private static JsonArray grid(MinecraftClient client,CreativeInventoryScreen screen){var a=new JsonArray();for(var slot:screen.getScreenHandler().slots)if(slot.inventory!=client.player.getInventory())a.add(stack(slot.getStack()));return a;}
    private static JsonObject point(double x,double y){if(!Double.isFinite(x) || !Double.isFinite(y) || x<0 || x>1 || y<0 || y>1)throw new IllegalStateException("Pointer fixture target outside real Screen");var p=new JsonObject();p.addProperty("x",x);p.addProperty("y",y);return p;}
    private static JsonObject slotPoint(CreativeInventoryScreen screen,Slot slot,double offsetX){var origin=(HudHandledScreenAccessor)screen;return point((origin.minecome$originX()+slot.x+8.0+offsetX)/screen.width,(origin.minecome$originY()+slot.y+8.0)/screen.height);}
    private static JsonObject targets(MinecraftClient client,CreativeInventoryScreen screen){
        var targets=new JsonObject();var slots=new JsonArray();Slot seven=null;
        for(int index:new int[]{0,7,8}){
            var slot=screen.getScreenHandler().slots.stream().filter(s->s.inventory==client.player.getInventory() && s.getIndex()==index).findFirst().orElseThrow();
            var p=slotPoint(screen,slot,0);p.addProperty("slot",index);slots.add(p);if(index==7)seven=slot;
        }
        targets.add("slots",slots);targets.add("drag_entry",slotPoint(screen,seven,2));
        var creative=screen.getScreenHandler().slots.stream().filter(s->s.inventory!=client.player.getInventory()).findFirst().orElseThrow();targets.add("scroll",slotPoint(screen,creative,0));
        var origin=(HudHandledScreenAccessor)screen;targets.add("blank",point((origin.minecome$originX()+8.0)/screen.width,(origin.minecome$originY()+6.0)/screen.height));return targets;
    }
}
