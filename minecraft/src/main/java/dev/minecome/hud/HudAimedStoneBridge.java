package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.aim.AimedStoneArena;
import dev.minecome.protocol.*;
import dev.minecome.terrain.HudPhysicalMovement;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.registry.Registries;
import net.minecraft.util.math.*;
import net.minecraft.world.World;
import org.joml.Quaternionf;

import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.atomic.*;

/** Optional minor-2 HUD guest. This adapter has no KCD calls and never changes inventory or camera. */
final class HudAimedStoneBridge implements HudBlockBridge {
    private static final Gson JSON=new Gson();
    private static final long FRESH_NS=500_000_000L;
    private record Baseline(long at,Vec3d eye,BlockPos seed,boolean air,boolean support,int slot,String item,int count) {}
    private final String save;
    private final BridgeClient bridge;
    private final AtomicReference<Baseline> baseline=new AtomicReference<>();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicBoolean reading=new AtomicBoolean();
    private final JsonArray requests=new JsonArray(),confirmations=new JsonArray();
    private Object world,player,server,serverWorld,serverPlayer;
    private UUID playerId;
    private AimedStoneArena arena;
    private AimGeometry.Alignment alignment;
    private Protocol.AimedArena offer;
    private BridgeClient.AimedEnvelope pending;
    private JsonObject pendingEvidence,initialBaseline,preBootstrapBaseline;
    private long session,generation,reset,ackAt,lastRead,lastPermit,componentId,activeId,permitCount;
    private int places,breaks,events,networkConfirmed,cancelledPending;
    private boolean started,acknowledged,bootstrapQueued,bootstrapConfirmed,closed;
    private String failure;
    private HudWalkingBuildSupport walkingSupport;
    private HudPhysicalMovement walkingMovement;
    private HudStreamProducer walkingOutput;
    private Protocol.Vec3 initialGuestFeet,initialHostPlayer;
    private boolean walkingReadyPublished,walkingClosing,walkingLogicallyClosed;
    private long walkingCloseStarted;

    HudAimedStoneBridge(Path token,String ownedSave) {
        if(ownedSave==null || !ownedSave.matches("MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"))
            throw new IllegalArgumentException("Exact owned HUD save required");
        save=ownedSave;
        bridge=new BridgeClient(token,"minecraft-hud-aimed-stone",Protocol.ROLE_MC,
                message->org.slf4j.LoggerFactory.getLogger("MineComeHudAimedStone").info("{}",message),BridgeClient.Mode.AIMED_STONE);
    }
    HudAimedStoneBridge(Path token,String ownedSave,HudWalkingBuildSupport support,HudPhysicalMovement movement,HudStreamProducer output){
        this(token,ownedSave);
        require(HudPhysicalMovementMode.walkingAimed(System.getProperties()) && support.ready(),"Prepared live walking build region required");
        walkingSupport=support;walkingMovement=movement;walkingOutput=output;
    }
    boolean walkingBootstrapped(){return bootstrapConfirmed;}

    @Override public void tick(MinecraftClient client,boolean actionsEnabled) {
        if(closed || failure!=null)return;
        try { advance(client,actionsEnabled); }
        catch(Exception error){failure=error.getClass().getSimpleName()+": "+error.getMessage();close();}
    }

    private void advance(MinecraftClient client,boolean actionsEnabled) {
        require(client.isOnThread(),"Client thread required");
        require(client.world!=null && client.player!=null && client.getServer()!=null && client.isIntegratedServerRunning()
                && client.interactionManager!=null && client.player.isCreative() && client.world.getRegistryKey()==World.OVERWORLD
                && save.equals(client.getServer().getSaveProperties().getLevelName()),"Owned Creative HUD world unavailable");
        if(world==null){world=client.world;player=client.player;server=client.getServer();playerId=client.player.getUuid();}
        require(world==client.world && player==client.player && server==client.getServer(),"HUD world/player/server changed");
        require(serverFailure.get()==null,"Authoritative observation failed: "+serverFailure.get());
        long now=System.nanoTime();
        if(walkingLogicallyClosed){publish(client);return;}
        boolean allowed=actionsEnabled && client.currentScreen==null && client.getOverlay()==null;
        if(!bootstrapQueued && !bootstrapConfirmed && now-lastRead>=50_000_000L){readBaseline(client);lastRead=now;}
        if(!started){
            if(!matches(client,baseline.get(),now))return;
            publish(client);bridge.start();started=true;return;
        }
        publish(client);
        if(session==0){
            if(!bridge.connected())return;
            var status=bridge.status();session=status.session();generation=status.world();reset=status.resets();
        }
        var status=bridge.status();
        require(bridge.connected() && status.session()==session && status.world()==generation && status.resets()==reset,
                "Aimed transport connection/generation changed");
        allowed=allowed && bridge.latestAimedHostPose()!=null && bridge.aimedArenaReady();
        if(arena==null){
            var host=bridge.latestAimedHostPose();
            if(host==null || !matches(client,baseline.get(),now))return;
            alignment=new AimGeometry.Alignment(vector(client.player.getEyePos()),host.camera(),1);
            initialBaseline=baselineEvidence(client,baseline.get());
            initialGuestFeet=vector(client.player.getPos());initialHostPlayer=host.player();
            arena=walkingSupport==null?new AimedStoneArena(alignment,save):new AimedStoneArena(alignment,save,walkingSupport.region());
        }
        if(walkingMovement!=null){
            long began=walkingMovement.startedAtNanos();
            if(HudWalkingAimGate.cutoff(began,now)){walkingClosing=true;if(walkingCloseStarted==0)walkingCloseStarted=now;}
            allowed=allowed && !walkingClosing && walkingMovement.interactionSettled(client,now) && walkingHostAligned(client);
        }
        // Revocation is processed before a queued vanilla preproof can dispatch.
        arena.tick(client,allowed);
        require(!arena.failed(),"Aimed arena failed: "+arena.failure());
        if(!arena.ready())return;
        if(offer==null){
            var seed=arena.seedCell();require(seed.equals(baseline.get().seed()),"Seed changed before offer");
            offer=new Protocol.AimedArena(1,alignment.minecraftAnchor(),alignment.kcdAnchor(),1,
                    cell(seed),cell(seed.add(-2,-2,-2)),cell(seed.add(2,2,2)));
            require(bridge.offerAimedArena(offer),"Arena offer queue rejected");return;
        }
        if(!acknowledged){if(!bridge.aimedArenaReady())return;acknowledged=true;ackAt=now;}
        if(!bootstrapQueued && !bootstrapConfirmed){
            var proof=baseline.get();var host=bridge.latestAimedHostPose();
            if(!allowed || proof==null || proof.at()<ackAt || !matches(client,proof,now) || host==null)return;
            require(client.player.getEyePos().squaredDistanceTo(vec(alignment.minecraftAnchor()))<=.0025
                    && vec(host.camera()).squaredDistanceTo(vec(alignment.kcdAnchor()))<=.0025,"Eye moved after fixed alignment offer");
            preBootstrapBaseline=baselineEvidence(client,proof);activeId=++componentId;
            var decision=arena.bootstrap(client,activeId);
            require(decision.queued(),"Bootstrap rejected: "+decision.reason());bootstrapQueued=true;return;
        }
        if(!bootstrapConfirmed){
            if(arena.pending())return;
            var result=arena.lastResult();require(result!=null && result.id()==activeId,"Missing bootstrap outcome");
            if(result.reason().equals("actions_disabled_before_dispatch")){bootstrapQueued=false;return;}
            confirm(result,true,0);bootstrapConfirmed=true;
            if(walkingSupport!=null && !walkingReadyPublished){
                var receipt=walkingReceipt("ready");receipt.addProperty("bootstrap_confirmed",true);
                receipt.add("initial_guest_feet",JSON.toJsonTree(initialGuestFeet));receipt.add("initial_guest_eye",JSON.toJsonTree(alignment.minecraftAnchor()));
                receipt.add("host_anchor",JSON.toJsonTree(alignment.kcdAnchor()));receipt.add("host_player_anchor",JSON.toJsonTree(initialHostPlayer));
                receipt.add("arena_offer",JSON.toJsonTree(offer));walkingOutput.offerWalkingAimState("ready",receipt);walkingReadyPublished=true;
            }
        }
        if(pending!=null && !arena.pending()){
            var result=arena.lastResult();require(result!=null && result.id()==activeId,"Missing aimed action outcome");
            int code;
            if(result.status().equals("confirmed") && result.clientAndServer()){
                confirm(result,false,pending.request().requestId());networkConfirmed++;code=Protocol.AIM_CONFIRMED;
            }else code=resultCode(result.reason());
            terminalResult(code,result.reason(),result.clientAndServer());
        }
        var incoming=bridge.pollAimedStoneRequest();
        if(incoming!=null){
            require(pending==null,"Concurrent aimed action");require(requests.size()<16,"Aimed HUD request bound reached");
            pending=incoming;pendingEvidence=new JsonObject();
            pendingEvidence.add("wire",JSON.toJsonTree(incoming.request()));
            pendingEvidence.addProperty("session",incoming.session());pendingEvidence.addProperty("world",incoming.world());
            pendingEvidence.addProperty("reset",incoming.reset());pendingEvidence.addProperty("actions_enabled",allowed);
            pendingEvidence.addProperty("captured_age_ns",System.nanoTime()-incoming.capturedAtNanos());
            pendingEvidence.addProperty("component_request_id",0);pendingEvidence.addProperty("vanilla_queued",false);
            requests.add(pendingEvidence);
            int availability=bridge.aimedInputAvailability(incoming);
            if(!allowed || availability!=0){terminalResult(availability==0?Protocol.AIM_UNAVAILABLE:availability,"input_unavailable",false);return;}
            require(incoming.session()==session && incoming.world()==generation && incoming.reset()==reset
                    && incoming.request().arenaId()==offer.arenaId(),"Aimed request identity changed");
            var request=incoming.request();
            var occlusion=switch(request.occlusion()){
                case Protocol.OCCLUSION_CLEAR -> AimedStoneArena.Occlusion.clear();
                case Protocol.OCCLUSION_HIT -> AimedStoneArena.Occlusion.hit(request.nearestDistance());
                default -> AimedStoneArena.Occlusion.unavailable();
            };
            var ray=new AimedStoneArena.HostRay(incoming.capturedAtNanos(),alignment,
                    new AimGeometry.Ray(request.origin(),request.direction(),request.range()),occlusion);
            activeId=++componentId;pendingEvidence.addProperty("component_request_id",activeId);
            var decision=arena.request(client,activeId,request.action(),ray);
            pendingEvidence.addProperty("vanilla_queued",decision.queued());
            if(!decision.queued())terminalResult(resultCode(decision.reason()),decision.reason(),false);
        }
        if(allowed && pending==null && !arena.pending() && now-lastPermit>=100_000_000L){
            lastPermit=now;if(bridge.issueAimPermit()!=null)permitCount++;
        }
        if(walkingClosing){
            require(now-walkingCloseStarted<HudWalkingAimGate.DRAIN_NS,"Walking aimed pending/cleanup deadline");
            if(pending==null && !arena.pending()){
                if(!arena.cleanupOwned(client,now) || !walkingSupport.cleanup(client,arena.cleanupCompletedAtNanos()))return;
                walkingLogicallyClosed=true;
                var receipt=walkingReceipt("closed");receipt.addProperty("logical_closed",true);receipt.addProperty("pending",false);
                receipt.addProperty("owned_count",arena.ownedCells().size());receipt.addProperty("guest_world_cleanup_complete",true);
                receipt.add("owned_cleanup",arena.cleanupEvidence());
                receipt.addProperty("support_cleanup_complete",walkingSupport.cleaned());walkingOutput.offerWalkingAimState("closed",receipt);
            }
        }
    }

    private boolean walkingHostAligned(MinecraftClient client){
        var host=bridge.latestAimedHostPose();if(host==null || alignment==null || initialHostPlayer==null)return false;
        return HudWalkingAimGate.aligned(alignment,initialGuestFeet,initialHostPlayer,host.player(),host.camera(),vector(client.player.getPos()),vector(client.player.getEyePos()));
    }
    private JsonObject walkingReceipt(String stage){
        var receipt=new JsonObject();receipt.addProperty("schema",1);receipt.addProperty("kind","minecome_hud_walking_aim_"+stage+"_v1");
        receipt.addProperty("utc_ms",System.currentTimeMillis());receipt.addProperty("patch_run",walkingSupport.patch().run());
        receipt.addProperty("patch_sha256",walkingSupport.patch().sha256());return receipt;
    }

    private void confirm(AimedStoneArena.Result result,boolean bootstrap,long wireId){
        require(result.id()==activeId && result.status().equals("confirmed") && result.clientAndServer(),"Action lacks authoritative confirmation");
        require(bridge.blockEvent(new Protocol.BlockEvent(result.action(),result.target().getX(),result.target().getY(),result.target().getZ(),"minecraft:stone")),"Confirmed block event queue rejected");
        events++;if(result.action()==Protocol.PLACE_STONE)places++;else breaks++;
        var record=new JsonObject();record.addProperty("component_request_id",result.id());record.addProperty("wire_request_id",wireId);
        record.addProperty("action",result.action());record.addProperty("bootstrap",bootstrap);record.addProperty("client_and_server",true);
        record.addProperty("block_event_queued",true);record.add("target",JSON.toJsonTree(cell(result.target())));
        record.add("hit_block",JSON.toJsonTree(cell(result.hit().block())));record.addProperty("face",result.hit().side().name());
        confirmations.add(record);
    }
    private void terminalResult(int code,String reason,boolean clientServer){
        boolean queued=bridge.sendAimedStoneResult(pending,code);
        pendingEvidence.addProperty("result",code);pendingEvidence.addProperty("reason",reason);
        pendingEvidence.addProperty("client_and_server",clientServer);pendingEvidence.addProperty("result_queued",queued);
        pending=null;pendingEvidence=null;require(queued,"Aimed terminal result queue rejected");
    }
    static int resultCode(String reason){
        return switch(reason){
            case "actions_disabled_before_dispatch","inventory_or_screen_open","selected_item_not_stone","arena_unavailable",
                    "host_obstruction_unavailable","chunk_unavailable","creative_required","selected_stack_changed" -> Protocol.AIM_UNAVAILABLE;
            case "ray_stale" -> Protocol.AIM_STALE;
            case "action_pending" -> Protocol.AIM_BUSY;
            case "target_occupied","placement_target_not_air","bootstrap_target_not_air" -> Protocol.AIM_OCCUPIED;
            case "ray_miss","unowned_hit" -> Protocol.AIM_ABSENT;
            case "host_obstructed" -> Protocol.AIM_HOST_OBSTRUCTED;
            case "out_of_reach","host_ray_range_exceeded" -> Protocol.AIM_OUT_OF_REACH;
            case "vanilla_dispatch_rejected" -> Protocol.AIM_VANILLA_FAILED;
            default -> Protocol.AIM_INVALID_TARGET;
        };
    }
    private void readBaseline(MinecraftClient client){
        if(!reading.compareAndSet(false,true))return;
        var owner=client.getServer();var seed=walkingSupport==null?client.player.getBlockPos().add(2,0,0).toImmutable():new BlockPos(walkingSupport.region().seed().x(),walkingSupport.region().seed().y(),walkingSupport.region().seed().z());
        owner.execute(()->{
            try{
                var w=owner.getOverworld();var p=owner.getPlayerManager().getPlayer(playerId);
                require(owner==server && save.equals(owner.getSaveProperties().getLevelName()) && w!=null && p!=null && p.getWorld()==w && p.isCreative(),"Authoritative owner unavailable");
                if(serverWorld==null){serverWorld=w;serverPlayer=p;}
                require(serverWorld==w && serverPlayer==p && w.isChunkLoaded(seed) && w.isChunkLoaded(seed.down()),"Authoritative baseline owner/chunk changed");
                int slot=p.getInventory().selectedSlot;var stack=p.getInventory().getStack(slot);
                baseline.set(new Baseline(System.nanoTime(),p.getEyePos(),seed,w.getBlockState(seed).isAir(),
                        w.getBlockState(seed.down()).isSideSolidFullSquare(w,seed.down(),Direction.UP),slot,
                        Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount()));
            }catch(Exception e){serverFailure.set(e.getMessage());}finally{reading.set(false);}
        });
    }
    private boolean matches(MinecraftClient client,Baseline proof,long now){
        if(proof==null || now-proof.at()<0 || now-proof.at()>FRESH_NS || !proof.air() || !proof.support()
                || !client.player.isOnGround() || client.player.getEyePos().squaredDistanceTo(proof.eye())>.0025
                || (walkingSupport==null && !proof.seed().equals(client.player.getBlockPos().add(2,0,0))) || !client.world.isChunkLoaded(proof.seed())
                || !client.world.getBlockState(proof.seed()).isAir()
                || !client.world.getBlockState(proof.seed().down()).isSideSolidFullSquare(client.world,proof.seed().down(),Direction.UP))return false;
        int slot=client.player.getInventory().selectedSlot;var stack=client.player.getInventory().getStack(slot);
        return slot==proof.slot() && proof.item().equals("minecraft:stone") && proof.count()>0 && stack.isOf(Blocks.STONE.asItem()) && stack.getCount()==proof.count();
    }
    private JsonObject baselineEvidence(MinecraftClient client,Baseline proof){
        var value=new JsonObject();value.add("client_eye",JSON.toJsonTree(vector(client.player.getEyePos())));
        value.add("server_eye",JSON.toJsonTree(vector(proof.eye())));value.add("seed",JSON.toJsonTree(cell(proof.seed())));
        value.addProperty("seed_air",proof.air());value.addProperty("support_solid_up",proof.support());
        value.addProperty("selected_slot",proof.slot());value.addProperty("selected_item",proof.item());value.addProperty("selected_count",proof.count());
        value.addProperty("observation_age_ns",System.nanoTime()-proof.at());return value;
    }
    private void publish(MinecraftClient client){
        float radians=(float)(Math.PI/180);
        var q=new Quaternionf().rotationYXZ((float)Math.PI-client.player.getYaw()*radians,-client.player.getPitch()*radians,0).normalize();
        bridge.publish(new Protocol.Pose(vector(client.player.getPos()),vector(client.player.getEyePos()),
                new Protocol.Quaternion(q.x(),q.y(),q.z(),q.w()),Math.toRadians(client.options.getFov().getValue()),
                new Protocol.Vec3(0,0,0),1,Protocol.SPACE_MC,Protocol.HAS_PLAYER|Protocol.HAS_CAMERA|Protocol.IN_WORLD));
    }
    @Override public boolean failed(){return failure!=null;}
    @Override public String failure(){return failure;}
    @Override public JsonObject evidence(){
        var value=new JsonObject();value.addProperty("kind","minecome_hud_aimed_stone_bridge_v1");value.addProperty("schema",1);
        value.addProperty("protocol_minor",2);value.addProperty("save",save);value.addProperty("session",session);
        value.addProperty("world",generation);value.addProperty("reset",reset);value.addProperty("baseline_confirmed",initialBaseline!=null);
        value.addProperty("arena_acknowledged",acknowledged);value.addProperty("bootstrap_confirmed",bootstrapConfirmed);
        value.addProperty("closed",closed);value.addProperty("failed",failed());value.addProperty("failure",failure);
        value.addProperty("pending",pending!=null || (arena!=null && arena.pending()));value.addProperty("cancelled_pending",cancelledPending);
        value.addProperty("request_count",requests.size());value.addProperty("confirmed_network_actions",networkConfirmed);
        value.addProperty("confirmed_actions",confirmations.size());value.addProperty("confirmed_places",places);value.addProperty("confirmed_breaks",breaks);
        value.addProperty("block_events_queued",events);value.addProperty("permits_issued",permitCount);
        value.addProperty("owned_count",arena==null?0:arena.ownedCells().size());
        value.addProperty("guest_world_cleanup_complete",arena!=null && arena.ownedCells().isEmpty() && !arena.pending() && cancelledPending==0);
        if(walkingSupport!=null){
            value.addProperty("walking_aimed",true);value.addProperty("logical_closed_before_restore",walkingLogicallyClosed);
            value.addProperty("aim_cutoff_ms",12000);value.add("build_support",walkingSupport.evidence());
            if(arena!=null)value.add("owned_cleanup",arena.cleanupEvidence());
        }
        for(String key:new String[]{"inventory_mutated","camera_mutated","engine_mirroring_verified","visual_verified"})value.addProperty(key,false);
        value.add("initial_baseline",initialBaseline);value.add("pre_bootstrap_baseline",preBootstrapBaseline);
        value.add("arena_offer",JSON.toJsonTree(offer));value.add("requests",requests.deepCopy());value.add("confirmations",confirmations.deepCopy());
        // Component details retain exact selected stacks, hit points and pre/post proof outcomes.
        value.add("arena",arena==null?JsonNull.INSTANCE:arena.evidence());return value;
    }
    @Override public void close(){
        if(closed)return;closed=true;
        if(pending!=null || (arena!=null && arena.pending()))cancelledPending++;
        if(arena!=null)arena.close();bridge.close();
    }
    private static Protocol.Cell cell(BlockPos p){return new Protocol.Cell(p.getX(),p.getY(),p.getZ());}
    private static Protocol.Vec3 vector(Vec3d p){return new Protocol.Vec3(p.x,p.y,p.z);}
    private static Vec3d vec(Protocol.Vec3 p){return new Vec3d(p.x(),p.y(),p.z());}
    private static void require(boolean value,String reason){if(!value)throw new IllegalStateException(reason);}
}
