package dev.minecome.hud;

import com.google.gson.*;
import com.sun.jna.platform.win32.Kernel32;
import com.sun.jna.platform.win32.WinBase;
import dev.minecome.protocol.Protocol;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.GameMenuScreen;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.resource.DataConfiguration;
import net.minecraft.util.math.BlockPos;
import net.minecraft.world.*;
import net.minecraft.world.gen.GeneratorOptions;
import net.minecraft.world.gen.WorldPresets;
import net.minecraft.world.level.LevelInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.*;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

/** Exercises the real HUD aimed adapter with an explicit synthetic host, without rendering or KCD. */
public final class HudAimedBridgeLab {
    private static final Logger LOG=LoggerFactory.getLogger("MineComeHudAimedBridgeLab");
    private static final Gson JSON=new GsonBuilder().serializeNulls().setPrettyPrinting().create();
    private static final long DEADLINE_NS=150_000_000_000L;
    private final String run,save,producerStart;
    private final int producerPid;
    private final Path directory,token;
    private final long initializedAt=System.nanoTime();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicReference<BlockPos> finalAir=new AtomicReference<>();
    private HudAimedStoneBridge adapter;
    private Object worldIdentity,playerIdentity,serverIdentity;
    private UUID playerId;
    private BlockPos seed;
    private Boolean previousPause;
    private Integer previousFps;
    private boolean started,inventoryGiven,adapterCompleted,nativeConfirmed,finalReadRequested,finished,stopping;
    private long worldAt,inventoryAt,completedAt;
    private String failure="";

    private HudAimedBridgeLab(String run,Path directory,Path token)throws Exception {
        this.run=run;this.directory=directory;this.token=token;
        save="MineCome-HudStream-"+UUID.fromString(run.substring(0,8)+"-"+run.substring(8,12)+"-"+
                run.substring(12,16)+"-"+run.substring(16,20)+"-"+run.substring(20));
        var api=Kernel32.INSTANCE;producerPid=api.GetCurrentProcessId();var creation=new WinBase.FILETIME();
        require(api.GetProcessTimes(api.GetCurrentProcess(),creation,new WinBase.FILETIME(),new WinBase.FILETIME(),new WinBase.FILETIME()),
                "Cannot identify actual Java process");
        producerStart=Long.toUnsignedString((Integer.toUnsignedLong(creation.dwHighDateTime)<<32)|Integer.toUnsignedLong(creation.dwLowDateTime));
        write("hud-aimed-bridge-ready.json",identity());
    }

    public static void initialize() {
        if(!Boolean.getBoolean("minecome.hudAimedBridgeLab"))return;
        try {
            String run=System.getProperty("minecome.hudAimedBridgeRun","");
            require(run.matches("[0-9a-f]{32}"),"Explicit HUD aimed fixture run required");
            Path directory=Path.of(System.getProperty("minecome.hudAimedBridgeDirectory","")).toAbsolutePath().normalize();
            Path root=MinecraftClient.getInstance().runDirectory.toPath().toAbsolutePath().normalize().getParent().getParent();
            require(directory.startsWith(root.resolve("runtime/evidence")) && Files.isDirectory(directory),"Existing workspace evidence directory required");
            Path token=Path.of(System.getProperty("minecome.hudAimedBridgeTokenFile","")).toAbsolutePath().normalize();
            require(token.getParent().equals(directory) && Files.isRegularFile(token) && !Files.isSymbolicLink(token),"Fresh fixture-local token required");
            require(Files.readString(token).trim().matches("[0-9a-f]{64}"),"Invalid fixture token");
            int port=Integer.getInteger("minecome.port",Protocol.PORT);
            require(port>1024 && port<=65535 && port!=Protocol.PORT && port!=1403,"Explicit separate fixture port required");
            var lab=new HudAimedBridgeLab(run,directory,token);
            ClientTickEvents.END_CLIENT_TICK.register(lab::tick);
            ClientLifecycleEvents.CLIENT_STOPPING.register(lab::stopping);
            LOG.info("HUD_AIMED_BRIDGE_INITIALIZED run={} actualMinecraft=true actualHudAdapter=true syntheticHost=true kcdConnected=false",run);
        }catch(Exception e){throw new IllegalStateException("Cannot initialize HUD aimed adapter fixture",e);}
    }

    private void tick(MinecraftClient client) {
        if(stopping)return;
        try {advance(client);}catch(Exception e){fail(client,e.getClass().getSimpleName()+": "+e.getMessage());}
    }

    private void advance(MinecraftClient client)throws Exception {
        long now=System.nanoTime();
        require(!Files.exists(directory.resolve("stop.request")),"Controller requested fixture stop");
        require(now-initializedAt<=DEADLINE_NS,"150-second HUD adapter fixture deadline reached");
        if(!started && client.currentScreen!=null && client.getOverlay()==null)create(client);
        if(client.world==null || client.player==null || !client.isIntegratedServerRunning()) {
            require(worldIdentity==null,"Owned Minecraft world disconnected");return;
        }
        require(owned(client),"Owned Minecraft save/world/player/server changed");
        if(worldIdentity==null){
            worldIdentity=client.world;playerIdentity=client.player;serverIdentity=client.getServer();
            playerId=client.player.getUuid();worldAt=now;
        }
        if(client.currentScreen instanceof GameMenuScreen)client.setScreen(null);
        require(serverFailure.get()==null,"Server observation failed: "+serverFailure.get());
        if(client.currentScreen!=null || client.getOverlay()!=null)return;
        if(!inventoryGiven){
            if(now-worldAt<2_000_000_000L || !client.player.isOnGround())return;
            var stone=new ItemStack(Blocks.STONE,64);int slot=client.player.getInventory().selectedSlot;
            client.player.getInventory().setStack(slot,stone);
            client.interactionManager.clickCreativeStack(stone,36+slot);
            inventoryGiven=true;inventoryAt=now;
        }
        if(now-inventoryAt<500_000_000L)return;
        if(adapter==null)adapter=new HudAimedStoneBridge(token,save);
        if(!adapterCompleted){
            // Only this isolated fixture supplies programmatic arming; the production
            // controller still requires its own physical-input and host-arming gates.
            adapter.tick(client,true);
            require(!adapter.failed(),"HUD aimed adapter failed: "+adapter.failure());
            var proof=adapter.evidence();
            if(proof.get("confirmed_network_actions").getAsInt()==0)return;
            require(proof.get("confirmed_network_actions").getAsInt()==1 && proof.get("request_count").getAsInt()==1
                    && proof.get("confirmed_places").getAsInt()==1 && proof.get("confirmed_breaks").getAsInt()==1
                    && !proof.get("pending").getAsBoolean(),"Unexpected HUD aimed adapter action trace");
            var cell=proof.getAsJsonObject("arena_offer").getAsJsonObject("seed");
            seed=new BlockPos(cell.get("x").getAsInt(),cell.get("y").getAsInt(),cell.get("z").getAsInt());
            adapterCompleted=true;completedAt=now;
            LOG.info("HUD_AIMED_BRIDGE_CONFIRMED run={} seed={} clientServer=true",run,seed);
            return;
        }
        // The synthetic host stops normally after receiving both confirmed block
        // events and result 1. Do not tick the live adapter after this terminal test
        // phase: its normal live policy correctly rejects a disconnected host.
        require(now-completedAt<=10_000_000_000L,"Synthetic host/cleanup completion deadline");
        if(!nativeConfirmed){
            Path path=directory.resolve("native.json");if(!Files.isRegularFile(path))return;
            require(Files.size(path)>1 && Files.size(path)<=16_384,"Invalid native fixture receipt size");
            // The host writes on shutdown. An incomplete write is not a successful receipt.
            JsonObject nativeReceipt;
            try{nativeReceipt=JsonParser.parseString(Files.readString(path)).getAsJsonObject();}
            catch(JsonParseException | IllegalStateException incomplete){return;}
            require(nativeReceipt.get("schema").getAsInt()==1
                    && nativeReceipt.get("kind").getAsString().equals("minecome_aimed_bridge_fixture_v1")
                    && nativeReceipt.get("result").getAsString().equals("passed")
                    && nativeReceipt.get("result_code").getAsInt()==1 && nativeReceipt.get("request_id").getAsLong()==1
                    && nativeReceipt.get("placed").getAsInt()==1 && nativeReceipt.get("removed").getAsInt()==1
                    && nativeReceipt.get("alignment_ack").getAsBoolean() && nativeReceipt.get("graceful_stop").getAsBoolean()
                    && !nativeReceipt.get("kcd_connected").getAsBoolean() && nativeReceipt.get("synthetic_host").getAsBoolean(),
                    "Synthetic host did not confirm the adapter event/result stream");
            var nativeSeed=nativeReceipt.getAsJsonObject("seed");
            require(nativeSeed.get("x").getAsInt()==seed.getX() && nativeSeed.get("y").getAsInt()==seed.getY()
                    && nativeSeed.get("z").getAsInt()==seed.getZ(),"Native fixture seed differs from adapter offer");
            nativeConfirmed=true;
        }
        if(!finalReadRequested){
            finalReadRequested=true;var server=client.getServer();
            server.execute(()->{
                try{
                    var world=server.getOverworld();var player=server.getPlayerManager().getPlayer(playerId);
                    require(server==serverIdentity && world!=null && player!=null && player.getWorld()==world
                            && player.isCreative() && save.equals(server.getSaveProperties().getLevelName()),"Authoritative cleanup owner unavailable");
                    require(world.isChunkLoaded(seed) && world.getBlockState(seed).isAir(),"Authoritative final seed is not air");
                    finalAir.set(seed);
                }catch(Exception e){serverFailure.set(e.getMessage());}
            });return;
        }
        if(finalAir.get()==null)return;
        require(finalAir.get().equals(seed) && client.world.isChunkLoaded(seed) && client.world.getBlockState(seed).isAir(),
                "Client final seed is not air");
        finish(client,"passed");
    }

    private void create(MinecraftClient client){
        require(client.world==null && !client.isIntegratedServerRunning(),"Refusing existing open world");
        require(!Files.exists(client.runDirectory.toPath().resolve("saves").resolve(save)),"Refusing existing save");
        started=true;previousPause=client.options.pauseOnLostFocus;previousFps=client.options.getMaxFps().getValue();
        client.options.pauseOnLostFocus=false;client.options.getMaxFps().setValue(60);
        GameRules rules=new GameRules();rules.get(GameRules.DO_MOB_SPAWNING).set(false,null);rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0,null);
        var info=new LevelInfo(save,GameMode.CREATIVE,false,Difficulty.PEACEFUL,true,rules,DataConfiguration.SAFE_MODE);
        client.createIntegratedServerLoader().createAndStart(save,info,new GeneratorOptions(42,false,false),
                registries->registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder(),client.currentScreen);
    }
    private boolean owned(MinecraftClient client){
        return started && client.player!=null && client.world!=null && client.interactionManager!=null
                && client.getServer()!=null && client.isIntegratedServerRunning() && client.player.isCreative()
                && save.equals(client.getServer().getSaveProperties().getLevelName()) && client.world.getRegistryKey()==World.OVERWORLD
                && (worldIdentity==null || client.world==worldIdentity) && (playerIdentity==null || client.player==playerIdentity)
                && (serverIdentity==null || client.getServer()==serverIdentity);
    }
    private JsonObject identity(){
        var value=new JsonObject();value.addProperty("schema",1);value.addProperty("kind","minecome_hud_aimed_bridge_fixture_v1");
        value.addProperty("run",run);value.addProperty("save",save);value.addProperty("producer_pid",producerPid);
        value.addProperty("producer_start_filetime",producerStart);value.addProperty("protocol_minor",2);
        for(String key:new String[]{"actual_minecraft","hud_adapter","synthetic_host","synthetic_host_rays","synthetic_arming"})value.addProperty(key,true);
        for(String key:new String[]{"kcd_connected","hud_rendered","physical_input_verified"})value.addProperty(key,false);
        return value;
    }
    private void finish(MinecraftClient client,String result)throws Exception {
        if(finished || stopping)return;
        try{
            if(adapter!=null)adapter.close();restore(client);
            require(previousPause==null || client.options.pauseOnLostFocus==previousPause,"Pause option restoration failed");
            require(previousFps==null || client.options.getMaxFps().getValue().equals(previousFps),"FPS option restoration failed");
            var value=identity();value.addProperty("result",result);value.addProperty("failure",failure);
            value.addProperty("options_restored",true);value.addProperty("world_block_writes",false);
            value.addProperty("fixture_inventory_prepared",inventoryGiven);value.addProperty("native_receipt_confirmed",nativeConfirmed);
            JsonObject proof=adapter==null?null:adapter.evidence();
            if(result.equals("passed"))HudAimedStoneProof.requireBridge(proof);
            value.addProperty("bridge_contract_validated",result.equals("passed"));
            var cleanup=new JsonArray();if(finalAir.get()!=null){var cell=new JsonObject();cell.addProperty("x",seed.getX());cell.addProperty("y",seed.getY());cell.addProperty("z",seed.getZ());cleanup.add(cell);}
            value.add("final_client_server_air_cells",cleanup);value.add("stone_bridge",proof==null?JsonNull.INSTANCE:proof);
            write("hud-aimed-bridge.json",value);finished=true;
            LOG.info("HUD_AIMED_BRIDGE_TERMINAL run={} result={} failure={}",run,result,failure);
        }finally{if(adapter!=null)adapter.close();stopping=true;client.scheduleStop();}
    }
    private void fail(MinecraftClient client,String reason){
        if(stopping)return;failure=reason;LOG.error("HUD_AIMED_BRIDGE_FAIL: {}",reason);
        try{finish(client,"failed");}catch(Exception e){restore(client);stopping=true;client.scheduleStop();LOG.error("Cannot preserve failed HUD adapter fixture receipt",e);}
    }
    private void stopping(MinecraftClient client){
        if(!finished){failure="Minecraft stopped before HUD adapter fixture completion";try{finish(client,"failed");}catch(Exception e){LOG.error("Cannot preserve stopped fixture",e);}}
        if(adapter!=null)adapter.close();restore(client);
    }
    private void restore(MinecraftClient client){
        if(previousPause!=null)client.options.pauseOnLostFocus=previousPause;
        if(previousFps!=null)client.options.getMaxFps().setValue(previousFps);
    }
    private void write(String name,JsonObject value)throws Exception {
        Path temporary=directory.resolve(name+".tmp");Files.writeString(temporary,JSON.toJson(value),StandardOpenOption.CREATE_NEW);
        Files.move(temporary,directory.resolve(name),StandardCopyOption.ATOMIC_MOVE);
    }
    private static void require(boolean value,String reason){if(!value)throw new IllegalStateException(reason);}
}
