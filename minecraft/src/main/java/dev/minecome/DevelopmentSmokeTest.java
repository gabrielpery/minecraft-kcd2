package dev.minecome;

import dev.minecome.protocol.BridgeClient;
import dev.minecome.protocol.Protocol;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.GameMenuScreen;
import net.minecraft.client.util.ScreenshotRecorder;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.resource.DataConfiguration;
import net.minecraft.util.Hand;
import net.minecraft.util.hit.BlockHitResult;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.Difficulty;
import net.minecraft.world.GameMode;
import net.minecraft.world.GameRules;
import net.minecraft.world.gen.GeneratorOptions;
import net.minecraft.world.gen.WorldPresets;
import net.minecraft.world.level.LevelInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

/** Explicitly opt-in vanilla gameplay test, confined to one newly created lab save. */
final class DevelopmentSmokeTest {
    private static final Logger LOG=LoggerFactory.getLogger("MineComeSmoke");
    private final boolean dynamic=Boolean.getBoolean("minecome.dynamicBridgeSmoke");
    private final SmokeSequence sequence=new SmokeSequence((dynamic?15L:2L)*1_000_000_000L);
    private record ServerObservation(boolean placement,boolean expectedState,BlockPos position) {}
    private final AtomicReference<ServerObservation> serverObservation=new AtomicReference<>();
    private boolean started,clientPlacementObserved,clientRemovalObserved,passReported;
    private Object labWorld;
    private long worldStartedAt;
    private BlockPos placed;

    String status(){return (dynamic?"dynamic":"vanilla")+" smoke="+sequence.phase()+
            (sequence.failure().isEmpty()?"":" failure="+sequence.failure());}

    void tick(MinecraftClient client,BridgeClient bridge) {
        if(!started && client.currentScreen!=null && client.getOverlay()==null) {
            started=true;
            if(client.world!=null || client.isIntegratedServerRunning()) {
                sequence.fail("Refusing smoke interactions in an already open world");
                LOG.error("VANILLA_SMOKE_FAIL: {}",sequence.failure());return;
            }
            client.options.pauseOnLostFocus=false;
            String name="MineCome-Lab-"+UUID.randomUUID();
            Path save=client.runDirectory.toPath().resolve("saves").resolve(name).normalize();
            if(Files.exists(save))throw new IllegalStateException("Refusing to touch an existing save: "+save);
            GameRules rules=new GameRules();
            rules.get(GameRules.DO_MOB_SPAWNING).set(false,null);
            rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0,null);
            LevelInfo info=new LevelInfo(name,GameMode.CREATIVE,false,Difficulty.PEACEFUL,true,rules,DataConfiguration.SAFE_MODE);
            LOG.info("Opt-in {} smoke creating NEW isolated flat world: {}",dynamic?"dynamic bridge":"vanilla",save);
            client.createIntegratedServerLoader().createAndStart(name,info,new GeneratorOptions(42,false,false),
                    registries->registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder(),
                    client.currentScreen);
        }
        if(!started || client.player==null || client.world==null || !client.isIntegratedServerRunning())return;
        if(labWorld!=null && labWorld!=client.world) {
            if(sequence.phase()!=SmokeSequence.Phase.FAILED && sequence.phase()!=SmokeSequence.Phase.DONE) {
                sequence.fail("Smoke world/dimension changed; no further test interactions");
                LOG.error("VANILLA_SMOKE_FAIL: {}",sequence.failure());
            }
            return;
        }
        if(sequence.phase()==SmokeSequence.Phase.FAILED && labWorld==null)return;
        if(client.currentScreen instanceof GameMenuScreen)client.setScreen(null);
        long now=System.nanoTime();
        if(worldStartedAt==0) {
            labWorld=client.world;worldStartedAt=now;
            LOG.info("Real singleplayer world active; player={} camera={}",client.player.getPos(),client.gameRenderer.getCamera().getPos());
        }
        int duration=Integer.getInteger("minecome.smokeWorldSeconds",90);
        if(duration<30 || duration>3600)throw new IllegalArgumentException("Smoke world duration must be 30..3600 seconds");
        if(now-worldStartedAt>=duration*1_000_000_000L) {
            if(sequence.phase()!=SmokeSequence.Phase.DONE)LOG.error("VANILLA_SMOKE_FAIL: runtime ended before completion; {}",status());
            LOG.info("Opt-in real world smoke reached {} seconds; scheduling normal save and shutdown",duration);
            client.scheduleStop();return;
        }
        Protocol.Pose host=bridge.latestHostPose();
        boolean ready=bridge.connected() && (!dynamic || (host!=null && (host.flags()&3)==3));
        SmokeSequence.Action action=sequence.update(now,ready,bridge.connected(),bridge.status().session());
        switch(action) {
            case GIVE_STONE -> {
                ItemStack stone=new ItemStack(Blocks.STONE);
                int slot=client.player.getInventory().selectedSlot;
                client.player.getInventory().setStack(slot,stone);
                client.interactionManager.clickCreativeStack(stone,36+slot);
                LOG.info("Issued vanilla Creative inventory packet; session={} freshHostPose={} (protocol v1 has no sink acknowledgement)",bridge.status().session(),host!=null);
            }
            case PLACE_STONE -> {
                client.player.setYaw(-90);client.player.setPitch(30);
                BlockPos support=client.player.getBlockPos().add(2,-1,0);placed=support.up();
                var hit=new BlockHitResult(new Vec3d(support.getX()+0.5,support.getY()+1,support.getZ()+0.5),Direction.UP,support,false);
                var result=client.interactionManager.interactBlock(client.player,Hand.MAIN_HAND,hit);
                LOG.info("Issued vanilla block interaction at {}; result={}",placed,result);
            }
            case CHECK_PLACEMENT -> {
                clientPlacementObserved=client.world.getBlockState(placed).isOf(Blocks.STONE);
                LOG.info("Observed real client block after placement: {} at {}",client.world.getBlockState(placed),placed);
                observeServer(client,true);
            }
            case BREAK_STONE -> {
                boolean attacked=client.interactionManager.attackBlock(placed,Direction.UP);
                LOG.info("Issued vanilla creative block-break packet at {}; accepted={}",placed,attacked);
            }
            case CHECK_REMOVAL -> {
                clientRemovalObserved=client.world.getBlockState(placed).isAir();
                LOG.info("Observed real client block after break: {} at {}",client.world.getBlockState(placed),placed);
                observeServer(client,false);
            }
            case FAIL -> {
                LOG.error("VANILLA_SMOKE_FAIL: {}",sequence.failure());
                // Cleanup only the new lab's test position through the same vanilla interaction API.
                if(placed!=null && client.world.getBlockState(placed).isOf(Blocks.STONE))
                    client.interactionManager.attackBlock(placed,Direction.UP);
            }
            default -> {}
        }
        // Server reads happen on its thread; only this immutable observation crosses to the client thread.
        ServerObservation observation=serverObservation.getAndSet(null);
        if(observation!=null && observation.position().equals(placed)) {
            if(observation.placement()) {
                sequence.confirmPlacement(now,clientPlacementObserved && observation.expectedState());
                if(sequence.phase()==SmokeSequence.Phase.HOLDING) {
                    LOG.info("Authoritative placement confirmed; holding real stone for {} wall-clock seconds",dynamic?15:2);
                    ScreenshotRecorder.saveScreenshot(client.runDirectory,"minecome-smoke-placement.png",client.getFramebuffer(),
                            message->LOG.info("Vanilla gameplay screenshot: {}",message.getString()));
                }
            } else sequence.confirmRemoval(clientRemovalObserved && observation.expectedState());
        }
        if(sequence.phase()==SmokeSequence.Phase.DONE && !passReported) {
            passReported=true;
            LOG.info("VANILLA_SMOKE_PASS: actual vanilla client AND integrated server confirmed stone placement and break; bridge={} lastSocketEvent={}",bridge.status(),bridge.lastSentBlockEvent());
        }
    }

    private void observeServer(MinecraftClient client,boolean placement) {
        var server=client.getServer();BlockPos target=placed;
        server.execute(()->{
            var state=server.getOverworld().getBlockState(target);
            LOG.info("Authoritative vanilla server block after {}: {} at {}",placement?"placement":"break",state,target);
            serverObservation.set(new ServerObservation(placement,placement?state.isOf(Blocks.STONE):state.isAir(),target));
        });
    }
}
