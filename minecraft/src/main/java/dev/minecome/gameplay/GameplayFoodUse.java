package dev.minecome.gameplay;

import com.google.gson.JsonObject;
import dev.minecome.hud.HudInputProtocol;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.client.network.ClientPlayerInteractionManager;
import net.minecraft.component.DataComponentTypes;
import net.minecraft.item.Item;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.Registries;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.stat.Stats;
import net.minecraft.util.Hand;
import net.minecraft.world.GameMode;
import java.util.HashMap;
import java.util.Map;

/** Main-hand food use through vanilla packets, duration, hunger and consumption. */
public final class GameplayFoodUse {
    private Object world,server;
    private ClientPlayerEntity player;
    private ClientPlayerInteractionManager interaction;
    private GameMode mode;
    private ItemStack selected=ItemStack.EMPTY;
    private int slot=-1;
    private boolean held,active,enabled;
    private long lastAttempt,starts,rejected,interruptions,preservedTicks,endedUses;
    private String lastResult="idle";
    private final Map<Item,Integer> serverUses=new HashMap<>(); // Server thread only.
    private long serverConsumptions;
    private record ServerState(long at,long consumptions,int food,float saturation,float health,String item,int count,boolean using){}
    private volatile ServerState serverState;

    /** Consumes only food right-button edges; block and other item paths remain unchanged. */
    public boolean event(MinecraftClient client,HudInputProtocol.Event event,boolean allowed){
        if(event.code()!=1||(event.kind()!=7&&event.kind()!=8))return false;
        if(event.kind()==8){
            if(!held&&!active)return false;
            suspend(client,"released");return true;
        }
        if(!food(client))return false;
        if(held||active)suspend(client,"new_press");
        if(!allowed||!usable(client)){rejected++;lastResult="unavailable";return true;}
        world=client.world;server=client.getServer();player=client.player;interaction=client.interactionManager;
        mode=interaction.getCurrentGameMode();slot=player.getInventory().selectedSlot;selected=player.getMainHandStack().copy();
        held=true;enabled=true;lastAttempt=0;tick(client,allowed);return true;
    }

    /** Run before vanilla input processing and at the controller's normal end-tick. */
    public void tick(MinecraftClient client,boolean allowed){
        enabled=allowed;
        if(!held&&!active)return;
        if(!allowed||!usable(client)||!owns(client)){suspend(client,"authority_or_owner_lost");return;}
        if(mode!=interaction.getCurrentGameMode()){suspend(client,"mode_changed");return;}
        if(slot!=player.getInventory().selectedSlot){suspend(client,"slot_changed");return;}
        if(active&&!player.isUsingItem()){
            active=false;endedUses++;lastResult="vanilla_use_ended";
            // The vanilla server may have consumed the final item or returned a bowl.
            // Never turn a held food button into an unrelated item/block action.
            if(!ItemStack.areItemsAndComponentsEqual(selected,player.getMainHandStack())){
                suspend(client,"food_finished_or_stack_changed");return;
            }
        }
        if(!sameFood(client)){suspend(client,"stack_changed");return;}
        if(active){
            if(player.getActiveHand()!=Hand.MAIN_HAND||!ItemStack.areItemsAndComponentsEqual(selected,player.getActiveItem()))
                suspend(client,"active_item_changed");
            return;
        }
        if(!held||player.isUsingItem())return;
        long now=System.nanoTime();if(lastAttempt!=0&&now-lastAttempt<250_000_000L)return;lastAttempt=now;
        var result=interaction.interactItem(player,Hand.MAIN_HAND);
        active=result.isAccepted()&&player.isUsingItem()&&player.getActiveHand()==Hand.MAIN_HAND;
        if(active){starts++;lastResult="using_vanilla_food";}
        else{rejected++;lastResult="vanilla_use_rejected";}
    }

    /** Only the inspected handleInputEvents cancellation is suppressed for this live hold. */
    public boolean preserve(MinecraftClient client,boolean authorityFresh){
        if(!authorityFresh||!enabled||!held||!active||!usable(client)||!owns(client)||mode!=interaction.getCurrentGameMode()||
                slot!=player.getInventory().selectedSlot||!sameFood(client)||!player.isUsingItem()||
                player.getActiveHand()!=Hand.MAIN_HAND||!ItemStack.areItemsAndComponentsEqual(selected,player.getActiveItem())){
            if(held||active){if(active)interruptions++;held=false;active=false;enabled=false;lastResult="continuation_rejected";}
            // The redirect invokes vanilla stopUsingItem itself on this false path.
            return false;
        }
        preservedTicks++;return true;
    }

    public void suspend(MinecraftClient client){suspend(client,"suspended");}
    private void suspend(MinecraftClient client,String reason){
        boolean wasHeld=held||active;
        if(active&&player!=null&&player.isUsingItem()){
            if(owns(client)&&client.isOnThread())interaction.stopUsingItem(player);
            else player.stopUsingItem(); // Drop local old-owner state without sending on another world's connection.
            interruptions++;
        }
        held=false;active=false;enabled=false;
        if(wasHeld)lastResult=reason;
    }

    /** Read-only evidence from the same owned server player as the block controller. */
    public void observe(ServerPlayerEntity player){
        if(!player.getServer().isOnThread())throw new IllegalStateException("Food observation requires server thread");
        var stack=player.getMainHandStack();
        if(stack.contains(DataComponentTypes.FOOD))serverUses.putIfAbsent(stack.getItem(),player.getStatHandler().getStat(Stats.USED,stack.getItem()));
        // Inspected Yarn 1.21.1 PlayerEntity.eatFood: vanilla increments USED for
        // the consumed item after HungerManager.eat, never on merely starting use.
        for(var entry:serverUses.entrySet()){
            int current=player.getStatHandler().getStat(Stats.USED,entry.getKey());
            if(current>entry.getValue())serverConsumptions+=current-entry.getValue();
            entry.setValue(current);
        }
        serverState=new ServerState(System.nanoTime(),serverConsumptions,player.getHungerManager().getFoodLevel(),
            player.getHungerManager().getSaturationLevel(),player.getHealth(),Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount(),player.isUsingItem());
    }

    public JsonObject evidence(MinecraftClient client){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_food_use_v1");
        j.addProperty("held",held);j.addProperty("active",active);j.addProperty("starts",starts);j.addProperty("rejected",rejected);
        j.addProperty("interruptions",interruptions);j.addProperty("preserved_ticks",preservedTicks);j.addProperty("client_ended_uses",endedUses);
        j.addProperty("last_result",lastResult);j.addProperty("controls_released",!held&&!active);j.addProperty("synthetic_use_key",false);
        j.addProperty("health_food_stack_written_directly",false);j.addProperty("main_hand_only",true);
        var observed=serverState;
        if(observed!=null){j.addProperty("server_consumptions",observed.consumptions());j.addProperty("server_observation_age_ms",(System.nanoTime()-observed.at())/1_000_000L);
            j.addProperty("food_server",observed.food());j.addProperty("saturation_server",observed.saturation());j.addProperty("health_server",observed.health());
            j.addProperty("selected_item_server",observed.item());j.addProperty("selected_count_server",observed.count());j.addProperty("server_using_item",observed.using());}
        if(client.player!=null){var stack=client.player.getMainHandStack();j.addProperty("selected_item",Registries.ITEM.getId(stack.getItem()).toString());
            j.addProperty("selected_count",stack.getCount());j.addProperty("client_using_item",client.player.isUsingItem());
            j.addProperty("food_client",client.player.getHungerManager().getFoodLevel());j.addProperty("health_client",client.player.getHealth());}
        return j;
    }
    private boolean owns(MinecraftClient client){return client.world==world&&client.player==player&&client.getServer()==server&&client.interactionManager==interaction;}
    private boolean sameFood(MinecraftClient client){return food(client)&&ItemStack.areItemsAndComponentsEqual(selected,client.player.getMainHandStack());}
    private static boolean food(MinecraftClient client){return client.player!=null&&!client.player.getMainHandStack().isEmpty()&&client.player.getMainHandStack().contains(DataComponentTypes.FOOD);}
    private static boolean usable(MinecraftClient client){return client.isOnThread()&&client.world!=null&&client.player!=null&&client.player.isAlive()&&!client.player.isSpectator()&&
        client.interactionManager!=null&&client.getServer()!=null&&client.isIntegratedServerRunning()&&client.currentScreen==null&&client.getOverlay()==null&&!client.isPaused();}
}
