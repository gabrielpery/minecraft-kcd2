package dev.minecome;

import dev.minecome.protocol.BridgeClient;
import dev.minecome.protocol.Protocol;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.GameMenuScreen;
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
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/** Opt-in remote input is confined to one fixed cell in this newly created Creative save. */
final class InteractiveStoneLab {
    private static final Logger LOG=LoggerFactory.getLogger("MineComeInteractive");
    private record Observation(Object world,long id,int action,boolean stone,boolean air,boolean support) {}
    private record Pending(long id,int action,long startedAt) {}
    private final AtomicReference<Observation> observation=new AtomicReference<>();
    private final AtomicBoolean serverReadPending=new AtomicBoolean();
    private String saveName;
    private Object labWorld;
    private boolean started,failed,ready,serverBaseline;
    private long worldStartedAt,inventoryAt,lastServerRead;
    private BlockPos support,target;
    private Pending pending;
    String status(){return "interactive lab="+(failed?"disabled":ready?"ready":started?"initializing":"waiting")+
            " save="+saveName+" target="+target+" pending="+pending;}

    void tick(MinecraftClient client,BridgeClient bridge) {
        long now=System.nanoTime();
        if(!started && client.currentScreen!=null && client.getOverlay()==null)create(client);
        boolean owned=owned(client);
        if(labWorld!=null && !owned) {
            failed=true;ready=false;pending=null;
            LOG.error("INTERACTIVE_STONE_LAB_DISABLED: world/dimension changed; remote actions disabled");
            labWorld=null;
        }
        if(owned) {
            if(client.currentScreen instanceof GameMenuScreen)client.setScreen(null);
            if(labWorld==null){labWorld=client.world;worldStartedAt=now;}
            if(target==null && now-worldStartedAt>=5_000_000_000L && client.player.isOnGround())initializeCell(client,now);
            updateProof(client,now);
            var host=bridge.latestHostPose();
            if(!failed && !ready && target!=null && serverBaseline && now-inventoryAt>=1_000_000_000L &&
                    bridge.supportsStoneInput() && host!=null && (host.flags()&3)==3) {
                ready=true;
                LOG.info("INTERACTIVE_STONE_LAB_READY save={} target={} support={} session={}; KCD commands: minecome_place / minecome_break; result=1 means vanilla dispatch only",
                        saveName,target,support,bridge.status().session());
            }
        }
        // At most the bounded mailbox capacity is processed in one client tick.
        for(int i=0;i<16;i++) {
            BridgeClient.InputEnvelope envelope=bridge.pollStoneInputRequest();
            if(envelope==null)break;
            int result=bridge.stoneInputAvailability(envelope);
            if(result==0)result=dispatch(client,bridge,envelope,now);
            boolean queued=bridge.sendStoneInputResult(envelope,result);
            LOG.info("STONE_INPUT_RESULT request={} action={} result={} queued={} target={}",
                    envelope.request().requestId(),envelope.request().action(),result,queued,target);
        }
    }
    private void create(MinecraftClient client) {
        started=true;
        if(client.world!=null || client.isIntegratedServerRunning()) {
            failed=true;LOG.error("INTERACTIVE_STONE_LAB_DISABLED: refusing an already open world");return;
        }
        client.options.pauseOnLostFocus=false;
        saveName="MineCome-Interactive-"+UUID.randomUUID();
        var save=client.runDirectory.toPath().resolve("saves").resolve(saveName).normalize();
        if(Files.exists(save))throw new IllegalStateException("Refusing existing save: "+save);
        GameRules rules=new GameRules();
        rules.get(GameRules.DO_MOB_SPAWNING).set(false,null);
        rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0,null);
        LevelInfo info=new LevelInfo(saveName,GameMode.CREATIVE,false,Difficulty.PEACEFUL,true,rules,DataConfiguration.SAFE_MODE);
        LOG.info("Opt-in interactive stone lab creating NEW isolated flat world: {}",save);
        client.createIntegratedServerLoader().createAndStart(saveName,info,new GeneratorOptions(42,false,false),
                registries->registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder(),client.currentScreen);
    }
    private boolean owned(MinecraftClient client) {
        return started && !failed && saveName!=null && client.world!=null && client.player!=null && client.interactionManager!=null &&
                client.isIntegratedServerRunning() && client.getServer()!=null &&
                saveName.equals(client.getServer().getSaveProperties().getLevelName()) &&
                (labWorld==null || labWorld==client.world);
    }
    private void initializeCell(MinecraftClient client,long now) {
        support=client.player.getBlockPos().add(2,-1,0);target=support.up();
        if(!client.world.isChunkLoaded(support) || !client.world.getBlockState(target).isAir() ||
                !client.world.getBlockState(support).isSideSolidFullSquare(client.world,support,Direction.UP)) {
            failed=true;LOG.error("INTERACTIVE_STONE_LAB_DISABLED: fresh lab cell lacks air/solid support at {}",target);return;
        }
        client.player.setYaw(-90);client.player.setPitch(30);
        ItemStack stone=new ItemStack(Blocks.STONE);
        int slot=client.player.getInventory().selectedSlot;
        client.player.getInventory().setStack(slot,stone);
        client.interactionManager.clickCreativeStack(stone,36+slot);
        inventoryAt=now;
        readServer(client,0,0);
    }
    private int dispatch(MinecraftClient client,BridgeClient bridge,BridgeClient.InputEnvelope envelope,long now) {
        int action=envelope.request().action();
        boolean lab=ready && owned(client) && target!=null;
        var state=lab?client.world.getBlockState(target):Blocks.AIR.getDefaultState();
        int rejected=StoneInputGate.evaluate(action,new StoneInputGate.State(lab,
                lab && client.player.isCreative(),lab && client.world.isChunkLoaded(target) && client.world.isChunkLoaded(support),
                lab && client.player.canInteractWithBlockAt(target,0) && client.player.canInteractWithBlockAt(support,0),
                lab && client.world.getBlockState(support).isSideSolidFullSquare(client.world,support,Direction.UP),
                state.isOf(Blocks.STONE),state.isAir(),pending!=null));
        if(rejected!=0)return rejected;
        int availability=bridge.stoneInputAvailability(envelope);
        if(availability!=0)return availability;
        // These are real vanilla interaction APIs. The observer alone emits resulting BLOCK_EVENTs.
        boolean dispatched;
        if(action==Protocol.PLACE_STONE) {
            if(!client.player.getMainHandStack().isOf(Blocks.STONE.asItem()))return Protocol.INPUT_UNAVAILABLE;
            var hit=new BlockHitResult(new Vec3d(support.getX()+0.5,support.getY()+1,support.getZ()+0.5),Direction.UP,support,false);
            dispatched=client.interactionManager.interactBlock(client.player,Hand.MAIN_HAND,hit).isAccepted();
        } else dispatched=client.interactionManager.attackBlock(target,Direction.UP);
        if(!dispatched)return Protocol.INPUT_VANILLA_FAILED;
        pending=new Pending(envelope.request().requestId(),action,now);
        lastServerRead=0;
        LOG.info("STONE_INPUT_DISPATCH request={} action={} target={}; awaiting actual client/server block proof",pending.id(),action,target);
        return Protocol.INPUT_ACCEPTED;
    }
    private void updateProof(MinecraftClient client,long now) {
        Observation proof=observation.getAndSet(null);
        if(proof!=null && proof.world()==labWorld) {
            if(proof.id()==0) {
                serverBaseline=proof.air() && proof.support();
                if(!serverBaseline){failed=true;LOG.error("INTERACTIVE_STONE_LAB_DISABLED: authoritative initial cell is not air with solid support");}
            } else if(pending!=null && proof.id()==pending.id() && proof.action()==pending.action()) {
                boolean expected=pending.action()==Protocol.PLACE_STONE?
                        proof.stone() && client.world.getBlockState(target).isOf(Blocks.STONE):proof.air() && client.world.getBlockState(target).isAir();
                if(expected) {
                    LOG.info("STONE_INPUT_VANILLA_CONFIRMED request={} action={} target={} clientAndIntegratedServer=true",
                            pending.id(),pending.action(),target);
                    pending=null;
                }
            }
        }
        if(pending!=null) {
            if(now-pending.startedAt()>3_000_000_000L) {
                LOG.error("STONE_INPUT_VANILLA_PROOF_TIMEOUT request={} action={}; accepted only established dispatch",pending.id(),pending.action());
                pending=null;
            } else if(now-lastServerRead>=250_000_000L && !serverReadPending.get()) {
                lastServerRead=now;readServer(client,pending.id(),pending.action());
            }
        }
    }
    private void readServer(MinecraftClient client,long id,int action) {
        if(!serverReadPending.compareAndSet(false,true))return;
        var server=client.getServer();var dimension=client.world.getRegistryKey();Object world=labWorld;
        BlockPos cell=target,base=support;
        server.execute(()->{
            try {
                var serverWorld=server.getWorld(dimension);
                if(serverWorld!=null) {
                    var state=serverWorld.getBlockState(cell);
                    observation.set(new Observation(world,id,action,state.isOf(Blocks.STONE),state.isAir(),
                            serverWorld.getBlockState(base).isSideSolidFullSquare(serverWorld,base,Direction.UP)));
                }
            } finally {serverReadPending.set(false);}
        });
    }
}
