package dev.minecome;

import com.google.gson.*;
import com.sun.jna.platform.win32.Kernel32;
import com.sun.jna.platform.win32.WinBase;
import dev.minecome.aim.AimedStoneArena;
import dev.minecome.protocol.AimGeometry;
import dev.minecome.protocol.BridgeClient;
import dev.minecome.protocol.Protocol;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.GameMenuScreen;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.Registries;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.resource.DataConfiguration;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.*;
import net.minecraft.world.gen.GeneratorOptions;
import net.minecraft.world.gen.WorldPresets;
import net.minecraft.world.level.LevelInfo;
import org.joml.Quaternionf;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.*;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/** Real Minecraft fixture against the explicit synthetic native host; never accesses KCD. */
public final class AimedBridgeLab {
    private static final Logger LOG=LoggerFactory.getLogger("MineComeAimedBridge");
    private static final Gson JSON=new GsonBuilder().serializeNulls().setPrettyPrinting().create();
    private static final long DEADLINE_NS=150_000_000_000L, PROOF_AGE_NS=500_000_000L;
    private record Baseline(long at,Vec3d eye,BlockPos seed,boolean air,boolean support,
                            int slot,String item,int count) {}
    private final String run,save,producerStart;
    private final int producerPid;
    private final Path directory,token;
    private final long initializedAt=System.nanoTime();
    private final AtomicReference<Baseline> baseline=new AtomicReference<>();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicReference<BlockPos> finalAir=new AtomicReference<>();
    private final AtomicBoolean reading=new AtomicBoolean();
    private final JsonArray permits=new JsonArray(),events=new JsonArray();
    private BridgeClient bridge;
    private AimedStoneArena arena;
    private AimGeometry.Alignment alignment;
    private Protocol.AimedArena offer;
    private BridgeClient.AimedEnvelope pending;
    private JsonObject initialBaseline,preBootstrapBaseline,requestEvidence,resultEvidence,bootstrapEvidence;
    private Object worldIdentity,playerIdentity,serverIdentity,serverWorldIdentity,serverPlayerIdentity;
    private UUID playerId;
    private Boolean previousPause;
    private Integer previousFps;
    private boolean started,inventoryGiven,offered,acknowledged,bootstrapQueued,bootstrapConfirmed;
    private boolean resultQueued,finalReadRequested,finished,stopping;
    private long worldAt,inventoryAt,session,worldGeneration,resetGeneration,acknowledgedAt;
    private long requestId,actionAt,lastPermitAt,lastBaselineReadAt,hostGoodbyeSession;
    private String failure="";

    private AimedBridgeLab(String run,Path directory,Path token) throws Exception {
        this.run=run;this.directory=directory;this.token=token;
        save="MineCome-AimedStone-"+UUID.fromString(run.substring(0,8)+"-"+run.substring(8,12)+"-"+
                run.substring(12,16)+"-"+run.substring(16,20)+"-"+run.substring(20));
        var api=Kernel32.INSTANCE;producerPid=api.GetCurrentProcessId();
        var creation=new WinBase.FILETIME();
        require(api.GetProcessTimes(api.GetCurrentProcess(),creation,new WinBase.FILETIME(),new WinBase.FILETIME(),new WinBase.FILETIME()),
                "Cannot identify actual Java process");
        producerStart=Long.toUnsignedString((Integer.toUnsignedLong(creation.dwHighDateTime)<<32)|Integer.toUnsignedLong(creation.dwLowDateTime));
        write("aimed-bridge-ready.json",identity());
    }

    public static void initialize() {
        if(!Boolean.getBoolean("minecome.aimedBridgeLab"))return;
        try {
            String run=System.getProperty("minecome.aimedBridgeRun","");
            require(run.matches("[0-9a-f]{32}"),"Explicit aimed network fixture run required");
            Path directory=Path.of(System.getProperty("minecome.aimedBridgeDirectory","")).toAbsolutePath().normalize();
            Path root=MinecraftClient.getInstance().runDirectory.toPath().toAbsolutePath().normalize().getParent().getParent();
            require(directory.startsWith(root.resolve("runtime/evidence")) && Files.isDirectory(directory),"Existing workspace evidence directory required");
            Path token=Path.of(System.getProperty("minecome.aimedBridgeTokenFile","")).toAbsolutePath().normalize();
            require(token.getParent().equals(directory) && Files.isRegularFile(token) && !Files.isSymbolicLink(token),"Fresh fixture-local token file required");
            require(Files.readString(token).trim().matches("[0-9a-f]{64}"),"Invalid fixture token");
            int port=Integer.getInteger("minecome.port",Protocol.PORT);
            require(port>1024 && port<=65535 && port!=Protocol.PORT && port!=1403,"Explicit separate fixture port required");
            var lab=new AimedBridgeLab(run,directory,token);
            ClientTickEvents.END_CLIENT_TICK.register(lab::tick);
            ClientLifecycleEvents.CLIENT_STOPPING.register(lab::stopping);
            LOG.info("AIMED_BRIDGE_INITIALIZED run={} actualMinecraft=true syntheticHost=true kcdConnected=false",run);
        }catch(Exception e){throw new IllegalStateException("Cannot initialize aimed network fixture",e);}
    }

    private void tick(MinecraftClient client) {
        if(stopping)return;
        try {advance(client);}catch(Exception e){fail(client,e.getClass().getSimpleName()+": "+e.getMessage());}
    }

    private void advance(MinecraftClient client) throws Exception {
        long now=System.nanoTime();
        require(!Files.exists(directory.resolve("stop.request")),"Controller requested fixture stop");
        require(now-initializedAt<=DEADLINE_NS,"150-second network fixture deadline reached");
        if(!started && client.currentScreen!=null && client.getOverlay()==null)create(client);
        if(client.world==null || client.player==null || !client.isIntegratedServerRunning()) {
            require(worldIdentity==null,"Owned Minecraft world disconnected");return;
        }
        require(owned(client),"Owned Minecraft save/world/player/server changed");
        if(worldIdentity==null) {
            worldIdentity=client.world;playerIdentity=client.player;serverIdentity=client.getServer();
            playerId=client.player.getUuid();worldAt=now;
        }
        if(client.currentScreen instanceof GameMenuScreen)client.setScreen(null);
        require(serverFailure.get()==null,"Server observation failed: "+serverFailure.get());
        if(client.currentScreen!=null || client.getOverlay()!=null)return;
        if(!inventoryGiven) {
            if(now-worldAt<2_000_000_000L || !client.player.isOnGround())return;
            var stone=new ItemStack(Blocks.STONE,64);int slot=client.player.getInventory().selectedSlot;
            client.player.getInventory().setStack(slot,stone);
            client.interactionManager.clickCreativeStack(stone,36+slot);
            inventoryGiven=true;inventoryAt=now;
        }
        if(now-inventoryAt<500_000_000L)return;
        if(!bootstrapQueued && now-lastBaselineReadAt>=50_000_000L) {
            requestBaseline(client);lastBaselineReadAt=now;
        }
        if(bridge==null) {
            if(!baselineMatches(client,baseline.get(),now))return;
            bridge=new BridgeClient(token,"minecraft-aimed-bridge-fixture",Protocol.ROLE_MC,
                    message->LOG.info("{}",message),BridgeClient.Mode.AIMED_STONE);
            publish(client);bridge.start();return;
        }
        publish(client);
        if(session==0) {
            if(!bridge.connected())return;
            var status=bridge.status();session=status.session();worldGeneration=status.world();resetGeneration=status.resets();
        }
        hostGoodbyeSession=bridge.lastHostGoodbyeSession();
        if(hostGoodbyeSession==session) {
            require(resultQueued && bootstrapConfirmed && arena!=null && !arena.pending() && arena.ownedCells().isEmpty(),
                    "Host ended before the confirmed break and empty arena");
            finishCleanup(client);return;
        }
        require(bridge.connected() && bridge.status().session()==session && bridge.status().world()==worldGeneration &&
                bridge.status().resets()==resetGeneration,"Aimed connection/generation changed before host GOODBYE");
        if(arena==null) {
            Protocol.Pose host=bridge.latestAimedHostPose();
            if(host==null || !baselineMatches(client,baseline.get(),now))return;
            require(host.space()==Protocol.SPACE_KCD && host.flags()==(Protocol.HAS_PLAYER|Protocol.HAS_CAMERA|Protocol.IN_WORLD),
                    "Fresh uncalibrated synthetic host pose required");
            Baseline proof=baseline.get();
            alignment=new AimGeometry.Alignment(vector(client.player.getEyePos()),host.camera(),1);
            arena=new AimedStoneArena(alignment);
            initialBaseline=baselineEvidence(client,proof);
        }
        arena.tick(client);
        require(!arena.failed(),"Aimed arena failed: "+arena.failure());
        if(!arena.ready())return;
        if(!offered) {
            BlockPos seed=arena.seedCell();
            require(seed.equals(baseline.get().seed()),"Arena baseline seed changed");
            offer=new Protocol.AimedArena(1,alignment.minecraftAnchor(),alignment.kcdAnchor(),1,
                    cell(seed),cell(seed.add(-2,-2,-2)),cell(seed.add(2,2,2)));
            require(bridge.offerAimedArena(offer),"Arena offer refused by current connection");
            offered=true;return;
        }
        if(!acknowledged) {
            if(!bridge.aimedArenaReady())return;
            acknowledged=true;acknowledgedAt=now;
            LOG.info("AIMED_BRIDGE_ARENA_ACK run={} session={} arena={}",run,session,offer.arenaId());
        }
        if(!bootstrapQueued) {
            Baseline proof=baseline.get();
            if(proof==null || proof.at()<acknowledgedAt || !baselineMatches(client,proof,now))return;
            require(client.player.getEyePos().squaredDistanceTo(vec(alignment.minecraftAnchor()))<=0.0025,
                    "Gameplay eye changed after alignment offer");
            Protocol.Pose host=bridge.latestAimedHostPose();
            require(host!=null && distanceSquared(host.camera(),alignment.kcdAnchor())<=0.0025,"Host camera changed after alignment offer");
            preBootstrapBaseline=baselineEvidence(client,proof);
            var decision=arena.bootstrap(client,++requestId);
            require(decision.queued(),"Vanilla bootstrap refused: "+decision.reason());
            bootstrapQueued=true;actionAt=now;return;
        }
        if(!bootstrapConfirmed) {
            if(arena.pending()){require(now-actionAt<5_000_000_000L,"Bootstrap confirmation deadline");return;}
            var result=arena.lastResult();requireConfirmed(result,requestId,Protocol.PLACE_STONE);
            bootstrapEvidence=localResult(result);bootstrapConfirmed=true;
            publishEvent(Protocol.PLACE_STONE,result.target());
            LOG.info("AIMED_BRIDGE_BOOTSTRAP run={} seed={} clientServer=true",run,result.target());
        }
        if(pending==null && !resultQueued && now-lastPermitAt>=100_000_000L) {
            var permit=bridge.issueAimPermit();lastPermitAt=now;
            if(permit!=null) {
                require(permits.size()<96,"Permit evidence bound reached");
                permits.add(JSON.toJsonTree(permit));
            }
        }
        var incoming=bridge.pollAimedStoneRequest();
        if(incoming!=null) {
            require(pending==null && !resultQueued,"More than one aimed fixture request received");
            require(incoming.session()==session && incoming.world()==worldGeneration && incoming.reset()==resetGeneration,
                    "Aimed envelope generation differs");
            var request=incoming.request();
            require(request.arenaId()==offer.arenaId() && request.action()==Protocol.BREAK_STONE,"Fixture expects one break in its offered arena");
            long age=System.nanoTime()-incoming.capturedAtNanos();
            require(age>=0 && age<=AimedStoneArena.MAX_RAY_AGE_NS,"Aimed permit/request expired");
            require(bridge.aimedInputAvailability(incoming)==0,"Host state unavailable for aimed request");
            var occlusion=switch(request.occlusion()) {
                case Protocol.OCCLUSION_CLEAR -> AimedStoneArena.Occlusion.clear();
                case Protocol.OCCLUSION_HIT -> AimedStoneArena.Occlusion.hit(request.nearestDistance());
                default -> AimedStoneArena.Occlusion.unavailable();
            };
            var ray=new AimedStoneArena.HostRay(incoming.capturedAtNanos(),alignment,
                    new AimGeometry.Ray(request.origin(),request.direction(),request.range()),occlusion);
            pending=incoming;requestId++;actionAt=now;
            requestEvidence=new JsonObject();requestEvidence.add("wire",JSON.toJsonTree(request));
            requestEvidence.addProperty("session",incoming.session());requestEvidence.addProperty("world",incoming.world());
            requestEvidence.addProperty("reset",incoming.reset());requestEvidence.addProperty("captured_age_ns",age);
            requestEvidence.addProperty("component_request_id",requestId);
            var decision=arena.request(client,requestId,request.action(),ray);
            if(!decision.queued()) {
                bridge.sendAimedStoneResult(incoming,Protocol.AIM_INVALID_TARGET);
                throw new IllegalStateException("Actual Minecraft aimed request refused: "+decision.reason());
            }
            return;
        }
        if(pending!=null && !resultQueued) {
            if(arena.pending()){require(now-actionAt<5_000_000_000L,"Aimed break confirmation deadline");return;}
            var result=arena.lastResult();
            if(result==null || result.id()!=requestId || !result.status().equals("confirmed") || !result.clientAndServer()) {
                bridge.sendAimedStoneResult(pending,Protocol.AIM_VANILLA_FAILED);
                throw new IllegalStateException("Aimed break lacks actual client/server confirmation");
            }
            requireConfirmed(result,requestId,Protocol.BREAK_STONE);
            require(result.target().equals(arena.seedCell()),"Aimed fixture broke an unexpected target");
            publishEvent(Protocol.BREAK_STONE,result.target());
            require(bridge.sendAimedStoneResult(pending,Protocol.AIM_CONFIRMED),"Confirmed aimed result queue rejected");
            resultQueued=true;
            resultEvidence=new JsonObject();resultEvidence.addProperty("wire_result",Protocol.AIM_CONFIRMED);
            resultEvidence.addProperty("client_server_confirmed",true);resultEvidence.add("local",localResult(result));
            LOG.info("AIMED_BRIDGE_CONFIRMED run={} wireRequest={} componentRequest={} clientServer=true",
                    run,pending.request().requestId(),requestId);
        }
    }

    private void create(MinecraftClient client) {
        require(client.world==null && !client.isIntegratedServerRunning(),"Refusing existing open world");
        require(!Files.exists(client.runDirectory.toPath().resolve("saves").resolve(save)),"Refusing existing save");
        started=true;previousPause=client.options.pauseOnLostFocus;previousFps=client.options.getMaxFps().getValue();
        client.options.pauseOnLostFocus=false;client.options.getMaxFps().setValue(60);
        GameRules rules=new GameRules();rules.get(GameRules.DO_MOB_SPAWNING).set(false,null);rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0,null);
        var info=new LevelInfo(save,GameMode.CREATIVE,false,Difficulty.PEACEFUL,true,rules,DataConfiguration.SAFE_MODE);
        client.createIntegratedServerLoader().createAndStart(save,info,new GeneratorOptions(42,false,false),
                registries->registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder(),client.currentScreen);
    }
    private boolean owned(MinecraftClient client) {
        return started && client.player!=null && client.world!=null && client.interactionManager!=null &&
                client.getServer()!=null && client.isIntegratedServerRunning() && client.player.isCreative() &&
                save.equals(client.getServer().getSaveProperties().getLevelName()) && client.world.getRegistryKey()==World.OVERWORLD &&
                (worldIdentity==null || client.world==worldIdentity) && (playerIdentity==null || client.player==playerIdentity) &&
                (serverIdentity==null || client.getServer()==serverIdentity);
    }
    private void requestBaseline(MinecraftClient client) {
        if(!reading.compareAndSet(false,true))return;
        var server=client.getServer();var seed=client.player.getBlockPos().add(2,0,0).toImmutable();
        server.execute(()->{
            try {
                var world=server.getOverworld();var player=server.getPlayerManager().getPlayer(playerId);
                require(server==serverIdentity && save.equals(server.getSaveProperties().getLevelName()) &&
                        world!=null && player!=null && player.getWorld()==world && player.isCreative(),"Authoritative owner unavailable");
                if(serverWorldIdentity==null){serverWorldIdentity=world;serverPlayerIdentity=player;}
                require(serverWorldIdentity==world && serverPlayerIdentity==player,"Authoritative world/player identity changed");
                require(world.isChunkLoaded(seed) && world.isChunkLoaded(seed.down()),"Authoritative baseline chunk unavailable");
                int slot=player.getInventory().selectedSlot;var stack=player.getInventory().getStack(slot);
                baseline.set(new Baseline(System.nanoTime(),player.getEyePos(),seed,world.getBlockState(seed).isAir(),
                        world.getBlockState(seed.down()).isSideSolidFullSquare(world,seed.down(),Direction.UP),
                        slot,Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount()));
            }catch(Exception e){serverFailure.set(e.getMessage());}finally{reading.set(false);}
        });
    }
    private boolean baselineMatches(MinecraftClient client,Baseline proof,long now) {
        if(proof==null || now-proof.at()<0 || now-proof.at()>PROOF_AGE_NS || !proof.air() || !proof.support() ||
                !client.player.isOnGround() || client.player.getEyePos().squaredDistanceTo(proof.eye())>0.0025 ||
                !proof.seed().equals(client.player.getBlockPos().add(2,0,0)) ||
                !client.world.isChunkLoaded(proof.seed()) || !client.world.getBlockState(proof.seed()).isAir() ||
                !client.world.getBlockState(proof.seed().down()).isSideSolidFullSquare(client.world,proof.seed().down(),Direction.UP))return false;
        int slot=client.player.getInventory().selectedSlot;var stack=client.player.getInventory().getStack(slot);
        return slot==proof.slot() && proof.item().equals("minecraft:stone") && proof.count()==64 &&
                stack.isOf(Blocks.STONE.asItem()) && stack.getCount()==proof.count();
    }
    private JsonObject baselineEvidence(MinecraftClient client,Baseline proof) {
        var value=new JsonObject();value.add("client_eye",JSON.toJsonTree(vector(client.player.getEyePos())));
        value.add("server_eye",JSON.toJsonTree(vector(proof.eye())));value.add("seed",JSON.toJsonTree(cell(proof.seed())));
        value.addProperty("seed_air",proof.air());value.addProperty("support_solid_up",proof.support());
        value.addProperty("selected_slot",proof.slot());value.addProperty("selected_item",proof.item());value.addProperty("selected_count",proof.count());
        value.addProperty("observation_age_ns",System.nanoTime()-proof.at());
        return value;
    }
    private void publish(MinecraftClient client) {
        // Pinned Minecraft 1.21.1 Camera.setRotation uses this YXZ basis. Position
        // comes from the current gameplay eye, independent of render interpolation.
        float radians=(float)(Math.PI/180);
        var q=new Quaternionf().rotationYXZ((float)Math.PI-client.player.getYaw()*radians,-client.player.getPitch()*radians,0).normalize();
        bridge.publish(new Protocol.Pose(vector(client.player.getPos()),vector(client.player.getEyePos()),
                new Protocol.Quaternion(q.x(),q.y(),q.z(),q.w()),Math.toRadians(client.options.getFov().getValue()),
                new Protocol.Vec3(0,0,0),1,Protocol.SPACE_MC,Protocol.HAS_PLAYER|Protocol.HAS_CAMERA|Protocol.IN_WORLD));
    }
    private void publishEvent(int operation,BlockPos pos) {
        require(bridge.blockEvent(new Protocol.BlockEvent(operation,pos.getX(),pos.getY(),pos.getZ(),"minecraft:stone")),
                "Confirmed block event queue rejected");
        var value=new JsonObject();value.addProperty("operation",operation);value.addProperty("x",pos.getX());
        value.addProperty("y",pos.getY());value.addProperty("z",pos.getZ());value.addProperty("block_id","minecraft:stone");
        value.addProperty("queued",true);events.add(value);
    }
    private void finishCleanup(MinecraftClient client) throws Exception {
        BlockPos seed=arena.seedCell();
        if(!finalReadRequested) {
            finalReadRequested=true;var server=client.getServer();
            server.execute(()->{
                try {
                    var world=server.getOverworld();var player=server.getPlayerManager().getPlayer(playerId);
                    require(server==serverIdentity && world==serverWorldIdentity && player==serverPlayerIdentity &&
                            save.equals(server.getSaveProperties().getLevelName()) && world.isChunkLoaded(seed) &&
                            world.getBlockState(seed).isAir(),"Final authoritative cleanup incomplete");
                    finalAir.set(seed);
                }catch(Exception e){serverFailure.set(e.getMessage());}
            });return;
        }
        if(finalAir.get()==null)return;
        require(finalAir.get().equals(seed) && client.world.isChunkLoaded(seed) && client.world.getBlockState(seed).isAir(),
                "Final client cleanup incomplete");
        require(events.size()==2 && bridge.status().sentEvents()==2 && bridge.status().droppedEvents()==0,
                "Confirmed event stream is incomplete");
        finish(client,"passed");
    }
    private static void requireConfirmed(AimedStoneArena.Result result,long id,int action) {
        require(result!=null && result.id()==id && result.action()==action && result.status().equals("confirmed") &&
                result.clientAndServer(),"Vanilla action lacks matching client/server proof");
    }
    private JsonObject identity() {
        var value=new JsonObject();value.addProperty("schema",1);value.addProperty("kind","minecome_aimed_bridge_fixture_v1");
        value.addProperty("run",run);value.addProperty("save",save);value.addProperty("producer_pid",producerPid);
        value.addProperty("producer_start_filetime",producerStart);value.addProperty("kcd_connected",false);
        value.addProperty("synthetic_host",true);value.addProperty("synthetic_host_rays",true);
        value.addProperty("network_fixture",true);value.addProperty("protocol_minor",2);return value;
    }
    private void finish(MinecraftClient client,String result) throws Exception {
        if(finished || stopping)return;
        try {
            restore(client);
            require(previousPause==null || client.options.pauseOnLostFocus==previousPause,"Pause option restoration failed");
            require(previousFps==null || client.options.getMaxFps().getValue().equals(previousFps),"FPS option restoration failed");
            var value=identity();value.addProperty("result",result);value.addProperty("failure",failure);
            value.addProperty("options_restored",true);value.addProperty("world_block_writes",false);
            value.addProperty("session",session);value.addProperty("world",worldGeneration);value.addProperty("reset",resetGeneration);
            value.addProperty("arena_acknowledged",acknowledged);value.addProperty("bootstrap_confirmed",bootstrapConfirmed);
            value.addProperty("host_goodbye_session",hostGoodbyeSession);
            value.add("initial_baseline",initialBaseline);value.add("pre_bootstrap_baseline",preBootstrapBaseline);
            value.add("arena_offer",JSON.toJsonTree(offer));
            value.add("bootstrap",bootstrapEvidence);value.add("permits",permits);value.add("request",requestEvidence);
            value.add("result_evidence",resultEvidence);value.add("block_events",events);
            var cleanup=new JsonArray();if(finalAir.get()!=null)cleanup.add(JSON.toJsonTree(cell(finalAir.get())));
            value.add("final_client_server_air_cells",cleanup);
            value.add("arena",arena==null?JsonNull.INSTANCE:arena.evidence());
            if(bridge!=null)value.add("bridge_status",JSON.toJsonTree(bridge.status()));
            write("aimed-bridge.json",value);finished=true;
            LOG.info("AIMED_BRIDGE_TERMINAL run={} result={} failure={}",run,result,failure);
        }finally {
            if(bridge!=null)bridge.close();
            if(arena!=null)arena.close();
            stopping=true;client.scheduleStop();
        }
    }
    private void fail(MinecraftClient client,String reason) {
        if(stopping)return;failure=reason;LOG.error("AIMED_BRIDGE_FAIL: {}",reason);
        try{finish(client,"failed");}catch(Exception e){restore(client);stopping=true;client.scheduleStop();LOG.error("Cannot preserve failed aimed bridge receipt",e);}
    }
    private void stopping(MinecraftClient client) {
        if(!finished){failure="Minecraft stopped before network fixture completion";try{finish(client,"failed");}catch(Exception e){LOG.error("Cannot preserve stopped fixture",e);}}
        if(bridge!=null)bridge.close();restore(client);
    }
    private void restore(MinecraftClient client) {
        if(previousPause!=null)client.options.pauseOnLostFocus=previousPause;
        if(previousFps!=null)client.options.getMaxFps().setValue(previousFps);
    }
    private void write(String name,JsonObject value) throws Exception {
        Path temporary=directory.resolve(name+".tmp");
        Files.writeString(temporary,JSON.toJson(value),StandardOpenOption.CREATE_NEW);
        Files.move(temporary,directory.resolve(name),StandardCopyOption.ATOMIC_MOVE);
    }
    private static JsonObject localResult(AimedStoneArena.Result result) {
        var value=new JsonObject();value.addProperty("id",result.id());value.addProperty("action",result.action());
        value.addProperty("status",result.status());value.addProperty("reason",result.reason());
        value.addProperty("client_and_server",result.clientAndServer());value.add("target",JSON.toJsonTree(cell(result.target())));
        value.add("hit_block",JSON.toJsonTree(cell(result.hit().block())));value.addProperty("face",result.hit().side().name());
        value.add("hit_point",JSON.toJsonTree(vector(result.hit().point())));value.addProperty("inside",result.hit().inside());return value;
    }
    private static Protocol.Cell cell(BlockPos pos){return new Protocol.Cell(pos.getX(),pos.getY(),pos.getZ());}
    private static Protocol.Vec3 vector(Vec3d v){return new Protocol.Vec3(v.x,v.y,v.z);}
    private static Vec3d vec(Protocol.Vec3 v){return new Vec3d(v.x(),v.y(),v.z());}
    private static double distanceSquared(Protocol.Vec3 a,Protocol.Vec3 b){return vec(a).squaredDistanceTo(vec(b));}
    private static void require(boolean value,String reason){if(!value)throw new IllegalStateException(reason);}
}
