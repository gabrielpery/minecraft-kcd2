package dev.minecome.gameplay;

import com.google.gson.JsonObject;
import dev.minecome.hud.HudInputProtocol;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayNetworking;
import net.fabricmc.fabric.api.networking.v1.PayloadTypeRegistry;
import net.fabricmc.fabric.api.networking.v1.ServerPlayNetworking;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerLifecycleEvents;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.client.network.ClientPlayerInteractionManager;
import net.minecraft.item.ItemStack;
import net.minecraft.item.Items;
import net.minecraft.network.RegistryByteBuf;
import net.minecraft.network.codec.PacketCodec;
import net.minecraft.network.packet.CustomPayload;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.Hand;
import net.minecraft.util.Identifier;
import net.minecraft.world.GameMode;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/** Experimental bow input. Only vanilla use/release may create or charge arrows. */
public final class GameplayRangedUse {
    private record Cancel(UUID id) implements CustomPayload {
        private static final Id<Cancel> ID=new Id<>(Identifier.of("minecome","cancel_bow_use"));
        private static final PacketCodec<RegistryByteBuf,Cancel> CODEC=PacketCodec.of(
            (value,buf)->buf.writeUuid(value.id()),buf->new Cancel(buf.readUuid()));
        @Override public Id<Cancel> getId(){return ID;}
    }
    private record ServerOwner(long at,ServerPlayerEntity player,Object world,int slot,ItemStack stack){}
    private static final class Cancellation {
        final ServerOwner owner;final long at=System.nanoTime();
        volatile boolean done;volatile String failure;
        Cancellation(ServerOwner owner){this.owner=owner;}
    }
    private static final ConcurrentHashMap<UUID,Cancellation> cancellations=new ConcurrentHashMap<>();
    private static boolean registered;
    public static boolean enabled(){return GameplayMode.rangedUseEnabled(System.getProperties());}

    /** Fabric's typed receiver runs on the server thread, in packet order. */
    public static void register(){
        if(registered)return;registered=true;
        PayloadTypeRegistry.playC2S().register(Cancel.ID,Cancel.CODEC);
        ServerPlayNetworking.registerGlobalReceiver(Cancel.ID,(payload,context)->{
            var pending=cancellations.remove(payload.id());if(pending==null)return;
            try{
                var p=context.player();var owner=pending.owner;
                if(!enabled()||!context.server().isOnThread()||p!=owner.player()||p.getWorld()!=owner.world()||p.getServer()!=context.server()||
                    System.nanoTime()-pending.at>2_000_000_000L)throw new IllegalStateException("Bow cancellation owner or deadline changed");
                if(p.isUsingItem()){
                    if(p.getActiveHand()!=Hand.MAIN_HAND||p.getInventory().selectedSlot!=owner.slot()||
                        !p.getActiveItem().isOf(Items.BOW)||!ItemStack.areItemsAndComponentsEqual(owner.stack(),p.getActiveItem()))
                        throw new IllegalStateException("Bow cancellation active stack changed");
                    // Pinned LivingEntity.clearActiveItem does not call BowItem.onStoppedUsing.
                    // A RELEASE_USE_ITEM packet would fire, including on lost focus/inventory.
                    p.clearActiveItem();
                }
            }catch(Exception e){pending.failure=e.toString();}finally{pending.done=true;}
        });
        ServerLifecycleEvents.SERVER_STOPPED.register(server->cancellations.forEach((id,pending)->{
            // A disconnected connection may never deliver its queued cancel.
            // Release old player/world references without touching stopped state.
            if(pending.owner.player().getServer()==server&&cancellations.remove(id,pending))pending.done=true;
        }));
    }

    private Object world,server;private ClientPlayerEntity player;private ClientPlayerInteractionManager interaction;
    private GameMode mode;private int slot=-1;private ItemStack selected=ItemStack.EMPTY;
    private boolean held,active;private long starts,releases,cancelled,rejected,preserved;
    private String result="idle";private volatile ServerOwner observed;private ServerOwner drawOwner;
    private Cancellation cancellation;private UUID cancellationId;

    /** Main-hand bow only; workstation block use remains ahead of this path. */
    public boolean event(MinecraftClient client,HudInputProtocol.Event event,boolean allowed){
        if(!enabled()||event.code()!=1||(event.kind()!=7&&event.kind()!=8))return false;
        if(event.kind()==8){
            if(!held&&!active&&cancellation==null)return false;
            if(held&&active&&valid(client,allowed)){
                // Inspected ClientPlayerInteractionManager sends vanilla RELEASE_USE_ITEM;
                // BowItem owns charge, ammunition, enchantments, durability and projectile.
                interaction.stopUsingItem(player);releases++;held=false;active=false;result="released_vanilla_bow";
            }else suspend(client);
            return true;
        }
        if(!bow(client))return false;
        settleCancellation();
        if(held||active)return true;
        var owner=observed;long now=System.nanoTime();
        if(cancellation!=null||!allowed||!usable(client)||!GameplayMode.bowFixtureEnabled(System.getProperties())&&!GameplayProjectiles.readyForDraw(client)||owner==null||now<owner.at()||now-owner.at()>500_000_000L||
            owner.player().getServer()!=client.getServer()||!owner.player().getUuid().equals(client.player.getUuid())||
            owner.slot()!=client.player.getInventory().selectedSlot||!ItemStack.areItemsAndComponentsEqual(owner.stack(),client.player.getMainHandStack())||
            !ClientPlayNetworking.canSend(Cancel.ID)){
            rejected++;result="bow_unavailable";return true;
        }
        world=client.world;server=client.getServer();player=client.player;interaction=client.interactionManager;
        mode=interaction.getCurrentGameMode();slot=player.getInventory().selectedSlot;selected=player.getMainHandStack().copy();drawOwner=owner;
        held=true;var accepted=interaction.interactItem(player,Hand.MAIN_HAND);
        active=accepted.isAccepted()&&player.isUsingItem()&&player.getActiveHand()==Hand.MAIN_HAND&&player.getActiveItem().isOf(Items.BOW);
        if(active){starts++;result="drawing_vanilla_bow";}else{
            // interactItem already sent a packet even when client prediction
            // rejected it. Cancel in order in case server ammunition differed.
            rejected++;suspend(client);result="vanilla_bow_rejected";
        }
        return true;
    }
    public void tick(MinecraftClient client,boolean allowed){
        if(!enabled())return;settleCancellation();
        if((held||active)&&!valid(client,allowed))suspend(client);
    }
    /** Returns true also when cancelling here: the redirect must NOT send release. */
    public boolean interceptVanillaStop(MinecraftClient client,boolean allowed){
        if(!enabled())return false;
        if(cancellation!=null&&owns(client)){
            // A late USING_ITEM tracker update must not turn a pending cancel
            // back into RELEASE_USE_ITEM. The normal tick settles/raises an ACK
            // failure inside Session's cleanup boundary, never from this mixin.
            if(player.isUsingItem()&&player.getActiveHand()==Hand.MAIN_HAND&&player.getActiveItem().isOf(Items.BOW))player.clearActiveItem();
            return true;
        }
        if(!held&&!active)return false;
        if(valid(client,allowed)){preserved++;return true;}
        suspend(client);return true;
    }
    public void suspend(MinecraftClient client){
        if(!held&&!active)return;
        try{
            if(drawOwner!=null&&owns(client)&&client.getNetworkHandler()!=null&&ClientPlayNetworking.canSend(Cancel.ID)){
                cancellation=new Cancellation(drawOwner);cancellationId=UUID.randomUUID();cancellations.put(cancellationId,cancellation);
                // Same connection as the preceding use packet. No server.execute race,
                // invented slot switch, release packet or artificial projectile.
                try{ClientPlayNetworking.send(new Cancel(cancellationId));cancelled++;}
                catch(RuntimeException failed){cancellations.remove(cancellationId,cancellation);cancellation=null;cancellationId=null;throw failed;}
            }
        }finally{
            if(player!=null&&client.isOnThread()&&player.isUsingItem()&&player.getActiveHand()==Hand.MAIN_HAND&&player.getActiveItem().isOf(Items.BOW))player.clearActiveItem();
            held=false;active=false;result="bow_cancelled_without_release";
        }
    }
    private void settleCancellation(){
        var pending=cancellation;if(pending==null)return;
        if(pending.done){cancellation=null;cancellationId=null;if(pending.failure!=null)throw new IllegalStateException(pending.failure);}
        else if(System.nanoTime()-pending.at>2_000_000_000L){cancellations.remove(cancellationId,pending);throw new IllegalStateException("Bow cancellation was not acknowledged");}
    }
    public void observe(ServerPlayerEntity player){
        if(!enabled())return;if(!player.getServer().isOnThread())throw new IllegalStateException("Bow observation requires server thread");
        observed=new ServerOwner(System.nanoTime(),player,player.getWorld(),player.getInventory().selectedSlot,player.getMainHandStack().copy());
    }
    public JsonObject evidence(){
        var j=new JsonObject();j.addProperty("experimental_fixture_only",GameplayMode.bowFixtureEnabled(System.getProperties()));j.addProperty("enabled",enabled());j.addProperty("held",held);j.addProperty("active",active);
        j.addProperty("starts",starts);j.addProperty("vanilla_releases",releases);j.addProperty("cancellations",cancelled);j.addProperty("rejected",rejected);j.addProperty("preserved_ticks",preserved);
        j.addProperty("cancel_pending",cancellation!=null&&!cancellation.done);j.addProperty("last_result",result);j.addProperty("synthetic_use_key",false);j.addProperty("projectiles_created_directly",false);return j;
    }
    private boolean valid(MinecraftClient client,boolean allowed){return allowed&&usable(client)&&owns(client)&&mode==interaction.getCurrentGameMode()&&
        slot==player.getInventory().selectedSlot&&bow(client)&&ItemStack.areItemsAndComponentsEqual(selected,player.getMainHandStack())&&
        player.isUsingItem()&&player.getActiveHand()==Hand.MAIN_HAND&&ItemStack.areItemsAndComponentsEqual(selected,player.getActiveItem());}
    private boolean owns(MinecraftClient client){return client.world==world&&client.player==player&&client.getServer()==server&&client.interactionManager==interaction;}
    private static boolean bow(MinecraftClient client){return client.player!=null&&client.player.getMainHandStack().isOf(Items.BOW);}
    private static boolean usable(MinecraftClient client){return client.isOnThread()&&client.world!=null&&client.player!=null&&client.player.isAlive()&&!client.player.isSpectator()&&
        client.interactionManager!=null&&client.getServer()!=null&&client.isIntegratedServerRunning()&&client.currentScreen==null&&client.getOverlay()==null&&!client.isPaused();}
}
