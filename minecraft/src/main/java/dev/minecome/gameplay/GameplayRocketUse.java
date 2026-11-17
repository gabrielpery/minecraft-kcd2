package dev.minecome.gameplay;

import com.google.gson.JsonObject;
import dev.minecome.hud.HudInputProtocol;
import net.minecraft.client.MinecraftClient;
import net.minecraft.item.Items;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.stat.Stats;
import net.minecraft.util.Hand;
import java.util.UUID;

/** Immediate vanilla Elytra rocket use; no velocity, rocket entity or stack writes. */
public final class GameplayRocketUse {
    private record Snapshot(long at,Object server,UUID player,int slot,int count,com.google.gson.JsonElement components,boolean gliding,int uses){}
    private volatile Snapshot observed;
    private boolean held;
    private long attempts,accepted,rejected,lastSnapshot;
    private String result="idle";
    public boolean event(MinecraftClient c,HudInputProtocol.Event event,boolean allowed){
        if(event.code()!=1||(event.kind()!=7&&event.kind()!=8))return false;
        if(event.kind()==8){boolean consumed=held;held=false;return consumed;}
        if(c.player==null||!c.player.getMainHandStack().isOf(Items.FIREWORK_ROCKET))return false;
        if(held)return true;held=true;attempts++;
        var s=observed;long now=System.nanoTime();
        if(!allowed||!Boolean.getBoolean("minecome.gameplayFlight")||!c.isOnThread()||c.world==null||c.getServer()==null||!c.isIntegratedServerRunning()||c.interactionManager==null||
                c.currentScreen!=null||c.getOverlay()!=null||c.isPaused()||!c.player.isAlive()||c.player.isSpectator()||!c.player.isFallFlying()||c.player.isUsingItem()||
                s==null||s.server()!=c.getServer()||!s.player().equals(c.player.getUuid())||!s.gliding()||now<s.at()||now-s.at()>250_000_000L||
                s.at()==lastSnapshot||s.slot()!=c.player.getInventory().selectedSlot||s.count()!=c.player.getMainHandStack().getCount()||
                !s.components().equals(GameplayRangedUse.componentIdentity(c.player.getMainHandStack(),c.world.getRegistryManager()))){
            rejected++;result="authority_or_glide_changed";return true;
        }
        lastSnapshot=s.at();
        // Minecraft1.21.1 FireworkRocketItem.use: while fallFlying, spawn the
        // shooter-attached vanilla rocket and decrementUnlessCreative immediately.
        var action=c.interactionManager.interactItem(c.player,Hand.MAIN_HAND);
        if(action.isAccepted()){accepted++;result="vanilla_rocket_used";}else{rejected++;result="vanilla_rejected";}
        return true;
    }
    public void suspend(){held=false;}
    public void observe(ServerPlayerEntity player){
        if(!player.getServer().isOnThread())throw new IllegalStateException("Rocket observation requires server thread");
        var stack=player.getMainHandStack();
        if(!stack.isOf(Items.FIREWORK_ROCKET)){observed=null;return;}
        observed=new Snapshot(System.nanoTime(),player.getServer(),player.getUuid(),player.getInventory().selectedSlot,stack.getCount(),
                GameplayRangedUse.componentIdentity(stack,player.getRegistryManager()),player.isFallFlying(),player.getStatHandler().getStat(Stats.USED,Items.FIREWORK_ROCKET));
    }
    public JsonObject evidence(){
        var j=new JsonObject();j.addProperty("attempts",attempts);j.addProperty("accepted",accepted);j.addProperty("rejected",rejected);
        j.addProperty("last_result",result);j.addProperty("controls_released",!held);j.addProperty("direct_velocity_or_stack_writes",false);
        var s=observed;if(s!=null){j.addProperty("server_uses",s.uses());j.addProperty("server_gliding",s.gliding());j.addProperty("server_count",s.count());}return j;
    }
}
