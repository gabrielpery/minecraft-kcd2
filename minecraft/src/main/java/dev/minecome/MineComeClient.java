package dev.minecome;

import dev.minecome.protocol.*;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.command.v2.ClientCommandRegistrationCallback;
import net.fabricmc.fabric.api.client.command.v2.ClientCommandManager;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.Camera;
import net.minecraft.block.BlockState;
import net.minecraft.registry.Registries;
import net.minecraft.text.Text;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Vec3d;
import org.joml.Quaternionf;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.ArrayBlockingQueue;

/** Vanilla owns gameplay; optional stone requests are dispatched on the client tick in a fresh lab. */
public final class MineComeClient implements ClientModInitializer {
    private static final Logger LOG=LoggerFactory.getLogger("MineCome");
    private final ArrayBlockingQueue<String> messages=new ArrayBlockingQueue<>(64);
    private final Map<BlockPos,BlockState> observed=new HashMap<>();
    private BridgeClient bridge;
    private Object observedWorld;
    private long observedSession=-1;
    private int ticks;
    private boolean startupExportAttempted;
    private long initializedAt;
    private final DevelopmentSmokeTest smokeTest=new DevelopmentSmokeTest();
    private final boolean interactive=Boolean.getBoolean("minecome.interactiveStoneLab");
    private final InteractiveStoneLab interactiveLab=new InteractiveStoneLab();
    @Override public void onInitializeClient() {
        if(Boolean.getBoolean("minecome.hudStreamLab")) {
            if(Boolean.getBoolean("minecome.hudExportLab") || interactive || Boolean.getBoolean("minecome.externalInputLab") || Boolean.getBoolean("minecome.groundMovementLab") || Boolean.getBoolean("minecome.smokeWorld") || Boolean.getBoolean("minecome.dynamicBridgeSmoke"))
                throw new IllegalArgumentException("Choose one isolated development lab mode");
            dev.minecome.hud.HudStreamLab.initialize();
            return;
        }
        if(Boolean.getBoolean("minecome.hudExportLab")) {
            if(interactive || Boolean.getBoolean("minecome.externalInputLab") || Boolean.getBoolean("minecome.groundMovementLab") || Boolean.getBoolean("minecome.smokeWorld") || Boolean.getBoolean("minecome.dynamicBridgeSmoke"))
                throw new IllegalArgumentException("Choose one isolated development lab mode");
            dev.minecome.hud.HudExportLab.initialize();
            return;
        }
        if(Boolean.getBoolean("minecome.externalInputLab")) {
            if(interactive || Boolean.getBoolean("minecome.groundMovementLab") || Boolean.getBoolean("minecome.smokeWorld") || Boolean.getBoolean("minecome.dynamicBridgeSmoke"))
                throw new IllegalArgumentException("Choose one isolated development lab mode");
            dev.minecome.input.ExternalInputLab.initialize();
            return;
        }
        if(Boolean.getBoolean("minecome.groundMovementLab")) {
            if(interactive || Boolean.getBoolean("minecome.smokeWorld") || Boolean.getBoolean("minecome.dynamicBridgeSmoke"))
                throw new IllegalArgumentException("Choose one isolated development lab mode");
            dev.minecome.terrain.GroundMovementLab.initialize();
            return;
        }
        initializedAt=System.nanoTime();
        MinecraftClient client=MinecraftClient.getInstance();
        Path token=Path.of(System.getProperty("minecome.tokenFile",client.runDirectory.toPath().resolve("config/bridge.token").toString()));
        if(interactive && (Boolean.getBoolean("minecome.smokeWorld") || Boolean.getBoolean("minecome.dynamicBridgeSmoke")))
            throw new IllegalArgumentException("Choose interactive lab or automatic smoke; these are separate opt-in modes");
        bridge=new BridgeClient(token,"minecraft-fabric-1.21.1",Protocol.ROLE_MC,this::diagnostic,interactive);
        ClientTickEvents.END_CLIENT_TICK.register(this::tick);
        ClientLifecycleEvents.CLIENT_STOPPING.register(ignored->bridge.close());
        ClientCommandRegistrationCallback.EVENT.register((dispatcher,registryAccess)->{
            dispatcher.register(ClientCommandManager.literal("minecome")
                    .then(ClientCommandManager.literal("status").executes(context->{
                        context.getSource().sendFeedback(Text.literal("MineCome: "+(bridge.connected()?"connected":"disconnected")+
                                ", status="+bridge.status()+", last socket event="+bridge.lastSentBlockEvent()+
                                ", smoke="+smokeTest.status()+", "+interactiveLab.status()));return 1;
                    }))
                    .then(ClientCommandManager.literal("export-stone").executes(context->{
                        try {
                            Path exported=BlockModelExport.exportStone(context.getSource().getClient());
                            context.getSource().sendFeedback(Text.literal("Exported vanilla stone model to "+exported)); return 1;
                        }catch(Exception e){ LOG.error("Block model export failed",e);context.getSource().sendError(Text.literal("Export failed: "+e.getMessage()));return 0; }
                    })));
        });
        bridge.start();
        diagnostic("Fabric bridge initialized; token file: "+token);
    }
    private void diagnostic(String message) { LOG.info(message); messages.offer(message); }
    private static Protocol.Vec3 vector(Vec3d v) { return new Protocol.Vec3(v.x,v.y,v.z); }
    private void tick(MinecraftClient client) {
        int exitSeconds=Integer.getInteger("minecome.exitAfterSeconds",0);
        if (exitSeconds>0 && System.nanoTime()-initializedAt>=exitSeconds*1_000_000_000L) {
            LOG.info("Opt-in development test duration reached; scheduling normal Minecraft shutdown");
            client.scheduleStop(); return;
        }
        if (!startupExportAttempted && Boolean.getBoolean("minecome.exportStoneOnStart") &&
                client.currentScreen!=null && client.getOverlay()==null) {
            startupExportAttempted=true;
            try { diagnostic("Actual vanilla stone model exported: "+BlockModelExport.exportStone(client)); }
            catch(Exception e) { LOG.error("Startup vanilla model export failed",e);diagnostic("Vanilla model export failed: "+e.getMessage()); }
        }
        boolean singlePlayer=client.isIntegratedServerRunning() && client.world!=null && client.player!=null;
        Object currentWorld=singlePlayer?client.world:null;
        if(currentWorld!=observedWorld) {
            observed.clear();ticks=0;observedWorld=currentWorld;bridge.resetWorldState();
        }
        BridgeClient.Status bridgeStatus=bridge.status();
        if(!bridgeStatus.connected() || observedSession!=bridgeStatus.session()) {
            observed.clear();ticks=0;observedSession=bridgeStatus.session();
        }
        if (Boolean.getBoolean("minecome.smokeWorld") || Boolean.getBoolean("minecome.dynamicBridgeSmoke")) smokeTest.tick(client,bridge);
        if(interactive)interactiveLab.tick(client,bridge);
        String message;
        while ((message=messages.poll())!=null)
            if (client.player!=null) client.player.sendMessage(Text.literal("[MineCome] "+message),false);
        Protocol.Vec3 zero=new Protocol.Vec3(0,0,0);
        Protocol.Vec3 player=zero,cameraPosition=zero;
        Protocol.Quaternion orientation=new Protocol.Quaternion(0,0,0,1);
        int flags=0;
        if (singlePlayer) {
            player=vector(client.player.getPos());
            Camera camera=client.gameRenderer.getCamera();
            cameraPosition=vector(camera.getPos());
            Quaternionf q=new Quaternionf(camera.getRotation()).normalize();
            orientation=new Protocol.Quaternion(q.x(),q.y(),q.z(),q.w());
            flags=Protocol.HAS_PLAYER|Protocol.HAS_CAMERA|Protocol.IN_WORLD;
        }
        Protocol.Pose host=bridge.latestHostPose();
        Protocol.Vec3 origin=zero; double scale=1;
        if (host!=null && (host.flags()&Protocol.CALIBRATED)!=0) {
            origin=host.kcdOrigin();scale=host.blocksPerUnit();flags|=Protocol.CALIBRATED;
        }
        // Options FOV is vertical. Dynamic sprint/zoom/death modifiers are not exported yet.
        double fov=Math.toRadians(client.options.getFov().getValue());
        bridge.publish(new Protocol.Pose(player,cameraPosition,orientation,fov,origin,scale,Protocol.SPACE_MC,flags));
        if (singlePlayer && bridge.connected() && ++ticks%2==0) observeBlocks(client);
        else if (!singlePlayer) observed.clear();
    }
    private void observeBlocks(MinecraftClient client) {
        BlockPos center=client.player.getBlockPos();
        Map<BlockPos,BlockState> next=new HashMap<>(729);
        for (BlockPos mutable:BlockPos.iterate(center.add(-4,-4,-4),center.add(4,4,4))) {
            BlockPos pos=mutable.toImmutable();
            if (!client.world.isChunkLoaded(pos)) continue;
            BlockState state=client.world.getBlockState(pos),old=observed.get(pos);
            next.put(pos,state);
            // Protocol v1 carries only registry identity, so property-only changes cannot be represented.
            if (old!=null && old.getBlock()!=state.getBlock()) {
                if (!old.isAir()) emitBlock(2,pos,old);
                if (!state.isAir()) emitBlock(1,pos,state);
            }
        }
        observed.clear();observed.putAll(next);
    }
    private void emitBlock(int operation,BlockPos pos,BlockState state) {
        LOG.info("Observed vanilla block event operation={} position={} id={}",operation,pos,Registries.BLOCK.getId(state.getBlock()));
        boolean queued=bridge.blockEvent(new Protocol.BlockEvent(operation,pos.getX(),pos.getY(),pos.getZ(),
                Registries.BLOCK.getId(state.getBlock()).toString()));
        if(!queued)LOG.warn("Observed block event was not queued; {}",bridge.status());
    }
}
