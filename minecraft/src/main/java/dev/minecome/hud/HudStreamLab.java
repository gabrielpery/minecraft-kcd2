package dev.minecome.hud;

import com.google.gson.*;
import com.mojang.blaze3d.systems.RenderSystem;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.*;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ingame.InventoryScreen;
import net.minecraft.client.gui.screen.ingame.CreativeInventoryScreen;
import net.minecraft.client.option.GraphicsMode;
import net.minecraft.item.*;
import net.minecraft.registry.*;
import net.minecraft.resource.DataConfiguration;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.*;
import net.minecraft.world.gen.*;
import net.minecraft.world.level.LevelInfo;
import org.lwjgl.opengl.*;
import org.slf4j.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Twenty-second actual vanilla UI stream in a new isolated Creative save. */
public final class HudStreamLab {
    private static final Logger LOG=LoggerFactory.getLogger("MineComeHudStream");
    private static volatile HudStreamLab active;
    private static final class Fixture {
        static final Item[] ITEMS={Items.STONE,Items.DIRT,Items.COBBLESTONE,Items.OAK_PLANKS,Items.STICK,Items.APPLE,Items.TORCH,Items.DIAMOND,Items.IRON_PICKAXE};
        static final int[] COUNTS={64,32,16,8,3,2,12,1,1};
    }
    private record Slot(int slot,String item,int count){}
    private record Observation(Object world,long at,int selected,List<Slot> slots){}
    private record ServerOwner(Object server,UUID player){}
    private final String save="MineCome-HudStream-"+UUID.randomUUID();
    private final HudStreamProducer.Identity identity;
    private final HudStreamLayout layout=HudStreamLayout.configured();
    private final boolean inputMode=Boolean.getBoolean("minecome.hudStreamInput"),inputFixture=Boolean.getBoolean("minecome.hudStreamInputFixture");
    private final boolean inputDelayFixture=Boolean.getBoolean("minecome.hudStreamInputDelayFixture");
    private final long initializedAt=System.nanoTime();
    private final AtomicReference<Observation> server=new AtomicReference<>();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicReference<ServerOwner> serverOwner=new AtomicReference<>();
    private final HudReadback readback=new HudReadback();
    private final Path outputDirectory;
    private HudStreamProducer output;
    private HudInputReader input;
    private HudVanillaUiAdapter ui;
    private final HudInputGate inputGate=new HudInputGate();
    private long armedAt;
    private boolean fixtureTargetsSent,selectedNineVerified,inventoryOpened,inventoryClosed,serverSwapVerified;
    private JsonObject inputEndingProof;
    private long lastInputTickAt,maxInputTickGapMs,maxImageAgeMs,firstReadyAckAt,prearmDelayStartUtc,prearmDelayEndUtc,delayedCloseAckAt,closeDelayStartUtc;
    private long prearmIneligibleTicks,withheldReadyTicks;
    private String terminalResult="passed";
    private Object world,player,serverIdentity;
    private long worldAt,streamAt,stateAt,lastCaptureAt,terminalAt,pauseStartedUtc,pauseEndedUtc;
    private long capturedServerConfirmed,capturedServerPending;
    private int stage=-1,captureId,lastReadbackId;
    private boolean started,given,terminal,frameTransparent;
    private volatile boolean stopping;
    private Boolean oldPause,oldHidden;
    private GraphicsMode oldGraphics;
    private Integer oldGuiScale;
    private Boolean oldFullscreenOption;
    private int oldWindowWidth,oldWindowHeight;
    private boolean oldWindowFullscreen;
    private int[] priorBlend;
    private HudStreamLab(Path outputDirectory,HudStreamProducer.Identity identity){this.outputDirectory=outputDirectory;this.identity=identity;}
    public static void initialize(){
        if(!Boolean.getBoolean("minecome.hudStreamLab"))return;
        if(active!=null)throw new IllegalStateException("HUD stream already active");
        var identity=new HudStreamProducer.Identity(required("minecome.hudStreamRun"),Integer.parseInt(required("minecome.hudStreamTargetPid")),Long.parseUnsignedLong(required("minecome.hudStreamTargetStart")),Long.parseLong(required("minecome.hudStreamExpiresUtcMs")));
        var lab=new HudStreamLab(Path.of(required("minecome.hudStreamDirectory")),identity);active=lab;
        if(lab.inputFixture && !lab.inputMode)throw new IllegalArgumentException("Input fixture requires HUD input mode");
        if(lab.inputDelayFixture && !lab.inputFixture)throw new IllegalArgumentException("Delayed input fixture requires standalone fixture mode");
        ClientTickEvents.END_CLIENT_TICK.register(lab::tick);ServerTickEvents.END_SERVER_TICK.register(lab::observe);
        ClientLifecycleEvents.CLIENT_STOPPING.register(client->{
            lab.stopInput(client);lab.stopping=true;lab.restoreBlend();lab.readback.close();if(lab.output!=null)lab.output.close();
            if(lab.oldPause!=null)client.options.pauseOnLostFocus=lab.oldPause;
            if(lab.oldHidden!=null)client.options.hudHidden=lab.oldHidden;
            if(lab.oldGraphics!=null)client.options.getGraphicsMode().setValue(lab.oldGraphics);
            lab.restoreLayout(client);
            active=null;
        });
        LOG.info("HUD_STREAM_INITIALIZED run={} output={} actualVanillaRenderPath=true",identity.run(),lab.outputDirectory);
    }
    private static String required(String name){String value=System.getProperty(name);if(value==null || value.isBlank())throw new IllegalArgumentException(name+" is required");return value;}
    private boolean owned(MinecraftClient client){return !stopping && world!=null && client.world==world && client.player==player && client.getServer()==serverIdentity && client.isIntegratedServerRunning();}
    public static boolean suppressWorld(){var lab=active;return lab!=null && lab.given && lab.owned(MinecraftClient.getInstance());}
    public static boolean transparentFrame(){var lab=active;return lab!=null && lab.frameTransparent && lab.owned(MinecraftClient.getInstance());}
    public static Double virtualMouseX(){var lab=active;var client=MinecraftClient.getInstance();return lab!=null && lab.ui!=null && lab.inputFixture && lab.owned(client)?lab.ui.windowX(client):null;}
    public static Double virtualMouseY(){var lab=active;var client=MinecraftClient.getInstance();return lab!=null && lab.ui!=null && lab.inputFixture && lab.owned(client)?lab.ui.windowY(client):null;}
    public static void beforeGuiClear(){
        var lab=active;if(lab==null || !lab.given)return;var client=MinecraftClient.getInstance();if(!lab.owned(client))return;
        RenderSystem.assertOnRenderThread();
        if(lab.frameTransparent){lab.fail(client,"Nested/unclosed HUD render frame");return;}
        lab.priorBlend=new int[]{GL11.glGetInteger(GL14.GL_BLEND_SRC_RGB),GL11.glGetInteger(GL14.GL_BLEND_DST_RGB),GL11.glGetInteger(GL14.GL_BLEND_SRC_ALPHA),GL11.glGetInteger(GL14.GL_BLEND_DST_ALPHA)};
        lab.frameTransparent=true;
        float[] previousColor=new float[4];GL11.glGetFloatv(GL11.GL_COLOR_CLEAR_VALUE,previousColor);
        boolean[] mask=new boolean[4];java.nio.ByteBuffer maskBytes=org.lwjgl.BufferUtils.createByteBuffer(4);GL11.glGetBooleanv(GL11.GL_COLOR_WRITEMASK,maskBytes);
        for(int i=0;i<4;i++)mask[i]=maskBytes.get(i)!=0;
        boolean scissor=GL11.glIsEnabled(GL11.GL_SCISSOR_TEST);int[] scissorBox=new int[4];GL11.glGetIntegerv(GL11.GL_SCISSOR_BOX,scissorBox);
        try {RenderSystem.disableScissor();RenderSystem.colorMask(true,true,true,true);RenderSystem.clearColor(0,0,0,0);RenderSystem.clear(GL11.GL_COLOR_BUFFER_BIT,MinecraftClient.IS_SYSTEM_MAC);}
        finally {RenderSystem.clearColor(previousColor[0],previousColor[1],previousColor[2],previousColor[3]);RenderSystem.colorMask(mask[0],mask[1],mask[2],mask[3]);if(scissor)RenderSystem.enableScissor(scissorBox[0],scissorBox[1],scissorBox[2],scissorBox[3]);}
    }
    public static void afterRender(){
        var lab=active;if(lab==null)return;var client=MinecraftClient.getInstance();
        try {if(lab.frameTransparent && lab.owned(client))lab.capture(client);}
        catch(Exception e){lab.fail(client,"HUD stream readback: "+e.getMessage());}
        finally {lab.restoreBlend();}
    }
    private void restoreBlend(){frameTransparent=false;if(priorBlend!=null){RenderSystem.blendFuncSeparate(priorBlend[0],priorBlend[1],priorBlend[2],priorBlend[3]);priorBlend=null;}}
    private boolean publicationPaused(long now){return !inputMode && streamAt!=0 && now-streamAt>=10_500_000_000L && now-streamAt<11_800_000_000L;}
    private void capture(MinecraftClient client){
        RenderSystem.assertOnRenderThread();long now=System.nanoTime();boolean paused=publicationPaused(now);
        readback.poll(frame->{
            // PBO slots can complete in a different order after reuse. An older slot
            // must never replace the latest captured UI in the worker mailbox.
            if(frame.id()<=lastReadbackId)return;
            lastReadbackId=frame.id();
            if(output==null || terminal || paused)return;
            var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();
            output.offer(new HudStreamProducer.Frame(frame.width(),frame.height(),frame.bottomUp(),meta.get("captured_utc_ms").getAsLong(),meta.get("selected_slot").getAsInt(),meta.get("screen").getAsInt(),frame.metadata()));
        });
        if(output==null || !output.isReady() || terminal || (!inputMode && stage<0) || paused || now-lastCaptureAt<50_000_000L || (!inputMode && now-stateAt<250_000_000L) || client.getOverlay()!=null)return;
        boolean inventory=inputMode?HudVanillaUiAdapter.inventory(client.currentScreen):stage==2;
        if(inventory && !(client.currentScreen instanceof InventoryScreen) && !(client.currentScreen instanceof CreativeInventoryScreen))return;
        if(!inventory && client.currentScreen!=null)return;
        Observation observation=server.get();List<Slot> local=slots(client.player.getInventory());int selected=client.player.getInventory().selectedSlot;
        int expected=stage==0?0:stage==3?2:1;
        boolean serverFresh=observation!=null && now-observation.at()<=250_000_000L && observation.world()!=null;
        boolean serverConfirmed=serverFresh && observation.slots().equals(local) && observation.selected()==selected;
        // Interactive frames show vanilla client prediction immediately. Requiring
        // server agreement here starves pixels while successive slot keys are in flight.
        // Authoritative input proof remains in inputTick's fresh matching observation.
        if(!serverFresh || (!inputMode && (!serverConfirmed || selected!=expected)))return;
        if(!inputMode && !matches(local))throw new IllegalStateException("Actual stream inventory differs from fixture");
        var meta=new JsonObject();meta.addProperty("state",inputMode?(inventory?"inventory":"hotbar"):(stage==0?"hotbar_slot0":stage==1?"hotbar_slot1":stage==2?"inventory_screen":"hotbar_slot2"));
        meta.addProperty("selected_slot",selected);meta.addProperty("screen",inventory?1:0);meta.addProperty("screen_kind",client.currentScreen==null?"none":client.currentScreen.getClass().getSimpleName());
        meta.addProperty("captured_utc_ms",System.currentTimeMillis());meta.addProperty("client_server_inventory_confirmed",serverConfirmed);
        meta.addProperty("server_selected_slot",observation.selected());meta.addProperty("server_observation_age_ms",(now-observation.at())/1_000_000);
        meta.addProperty("no_world_pixels",true);meta.addProperty("hand_pixels",false);meta.addProperty("gui_scale",client.getWindow().getScaleFactor());
        meta.add("client_slots",jsonSlots(local));meta.add("server_slots",jsonSlots(observation.slots()));
        if(readback.capture(client.getFramebuffer(),++captureId,meta.toString())){lastCaptureAt=now;if(serverConfirmed)capturedServerConfirmed++;else capturedServerPending++;}
    }
    private void tick(MinecraftClient client){
        if(stopping)return;long now=System.nanoTime();
        if(now-initializedAt>=(inputMode?180_000_000_000L:120_000_000_000L)){fail(client,"Global HUD deadline");return;}
        if(!started && client.currentScreen!=null && client.getOverlay()==null){create(client);return;}
        if(!started || client.world==null || client.player==null || !client.isIntegratedServerRunning()){if(world!=null)fail(client,"Owned stream world disconnected");return;}
        if(world==null){world=client.world;player=client.player;serverIdentity=client.getServer();worldAt=now;serverOwner.set(new ServerOwner(serverIdentity,client.player.getUuid()));}
        if(!owned(client)){fail(client,"World/player/server identity changed");return;}
        if(now-worldAt>=(inputMode?100_000_000_000L:35_000_000_000L)){fail(client,"World HUD deadline");return;}
        if(serverFailure.get()!=null){fail(client,serverFailure.get());return;}
        if(client.getOverlay()!=null)return;
        if(!given){
            if(client.currentScreen!=null)return;
            if(client.getFramebuffer().textureWidth!=layout.width() || client.getFramebuffer().textureHeight!=layout.height() || client.getWindow().getScaleFactor()!=layout.guiScale()){
                fail(client,"Requested stream framebuffer/GUI scale was not applied");return;
            }
            if(client.interactionManager==null || client.interactionManager.getCurrentGameMode()!=GameMode.CREATIVE){fail(client,"Fresh Creative inventory API unavailable");return;}
            for(int i=0;i<9;i++){var stack=new ItemStack(Fixture.ITEMS[i],Fixture.COUNTS[i]);client.player.getInventory().setStack(i,stack);client.interactionManager.clickCreativeStack(stack,36+i);}
            client.player.getInventory().selectedSlot=0;given=true;
            Path project=client.runDirectory.toPath().toAbsolutePath().normalize().getParent().getParent();
            output=new HudStreamProducer(project,outputDirectory,identity,save,true,inputMode?(inputFixture?2:1):0);output.start();
            if(inputMode)ui=new HudVanillaUiAdapter(client,inputFixture);
        }
        if(output.failure()!=null){fail(client,"HUD stream worker: "+output.failure());return;}
        if(!terminal && output.isReady()){
            if(streamAt==0){streamAt=now;LOG.info("HUD_STREAM_READY run={} save={} realCreativePackets=true inputMode={}",identity.run(),save,inputMode);}
            long elapsed=now-streamAt;
            if(inputMode){
                try{inputTick(client,now);}catch(Exception e){fail(client,"HUD input: "+e.getMessage());return;}
            }else{
            if(publicationPaused(now) && pauseStartedUtc==0){pauseStartedUtc=System.currentTimeMillis();LOG.info("HUD_STREAM_PUBLICATION_PAUSED run={}",identity.run());}
            if(pauseStartedUtc!=0 && pauseEndedUtc==0 && elapsed>=11_800_000_000L){pauseEndedUtc=System.currentTimeMillis();LOG.info("HUD_STREAM_PUBLICATION_RESUMED run={}",identity.run());}
            int next=(int)Math.min(3,elapsed/5_000_000_000L);
            if(next!=stage){
                stage=next;stateAt=now;
                client.player.getInventory().selectedSlot=stage==0?0:stage==3?2:1;
                if(stage==2)client.setScreen(new InventoryScreen(client.player));else client.setScreen(null);
                LOG.info("HUD_STREAM_STATE run={} stage={} selected={}",identity.run(),stage,client.player.getInventory().selectedSlot);
            }
            if(elapsed>=20_000_000_000L){
                var proof=new JsonObject();proof.addProperty("new_world",true);proof.addProperty("real_creative_packets",true);
                proof.addProperty("normal_vanilla_render_path",true);proof.addProperty("scheduled_capture_hz",20);proof.addProperty("elapsed_ms",elapsed/1_000_000);
                proof.addProperty("capture_width",layout.width());proof.addProperty("capture_height",layout.height());proof.addProperty("vanilla_gui_scale",layout.guiScale());
                proof.addProperty("intentional_publication_pause_start_utc_ms",pauseStartedUtc);proof.addProperty("intentional_publication_pause_end_utc_ms",pauseEndedUtc);
                proof.addProperty("intentional_publication_pause_ms",pauseEndedUtc-pauseStartedUtc);proof.addProperty("normal_shutdown_requested",true);
                output.finish("passed",proof);terminal=true;terminalAt=now;
            }
            }
        }
        if(terminal){
            if(!output.isFinished()){if(now-terminalAt>4_000_000_000L)fail(client,"Stream finalization 4s deadline");return;}
            if(output.failure()!=null){fail(client,"Stream terminal: "+output.failure());return;}
            LOG.info("HUD_STREAM_TERMINAL run={} save={} result={} published={} actualVanillaHud=true actualVanillaInventory={} hostCompositingVerified=false",identity.run(),save,terminalResult,output.publishedFrames(),inputMode?inventoryOpened:stage==3);
            stopping=true;client.scheduleStop();
        }
    }
    private void inputTick(MinecraftClient client,long now){
        if(lastInputTickAt!=0)maxInputTickGapMs=Math.max(maxInputTickGapMs,(now-lastInputTickAt)/1_000_000);
        lastInputTickAt=now;
        if(inputEndingProof!=null){
            if(delayedCloseAckAt!=0 && now>=delayedCloseAckAt){
                publishClosedAck(client);delayedCloseAckAt=0;
                inputEndingProof.addProperty("closed_ack_delay_ms",System.currentTimeMillis()-closeDelayStartUtc);
            }
            if(!input.isFinished()){if(now-terminalAt>1_500_000_000L)throw new IllegalStateException("Input cleanup1.5s timeout");return;}
            inputEndingProof.addProperty("input_handles_closed",input.cleanupComplete());inputEndingProof.addProperty("closed_acknowledgement_published",input.closedAcknowledgementPublished());
            inputEndingProof.add("input_timing",input.diagnostics());inputEndingProof.addProperty("max_client_tick_gap_ms",maxInputTickGapMs);inputEndingProof.addProperty("max_own_image_age_ms",maxImageAgeMs);
            if(!input.cleanupComplete())throw new IllegalStateException("Input handle cleanup failed");
            String result=inputFixture?"input_passed":(armedAt!=0 && inputGate.sequence()>0?"input_completed":"input_cancelled");
            terminalResult=result;output.finish(result,inputEndingProof);terminal=true;terminalAt=now;return;
        }
        if(input==null && output.publishedFrames()>0){
            var wire=new HudInputProtocol.Identity(identity.run(),output.producerPid(),output.producerStart(),identity.targetPid(),identity.targetStart(),identity.expiresUtcMs());
            input=new HudInputReader(wire);input.start();
        }
        if(input==null)return;
        boolean inventory=HudVanillaUiAdapter.inventory(client.currentScreen);
        if(client.currentScreen!=null && !inventory)throw new IllegalStateException("Unexpected screen in owned UI lab");
        Observation observation=server.get();List<Slot> local=slots(client.player.getInventory());
        if(observation!=null && now-observation.at()<=250_000_000L && observation.slots().equals(local) && observation.selected()==client.player.getInventory().selectedSlot){
            if(observation.selected()==8)selectedNineVerified=true;
            if(swapped(local))serverSwapVerified=true;
        }
        if(inventory){
            inventoryOpened=true;
            if(inputFixture && !fixtureTargetsSent){output.offerFixtureTargets(ui.fixtureTargets(client));fixtureTargetsSent=true;}
        }else if(inventoryOpened)inventoryClosed=true;
        if(input.isClosed()){
            String reason=input.reason();
            if(!"host_closed".equals(reason) && !"guest_closed".equals(reason))throw new IllegalStateException("Input peer ended: "+reason);
            finishInput(client,now,reason);return;
        }
        boolean connected=input.connected();int hostState=connected?input.hostState():0;
        boolean hostFresh=connected && System.currentTimeMillis()-input.heartbeat()<=250 && now-input.observedAt()<=250_000_000L;
        long imageAgeMs=(now-output.lastPublishedAt())/1_000_000;maxImageAgeMs=Math.max(maxImageAgeMs,imageAgeMs);
        boolean imageFresh=imageAgeMs<=250;
        if(hostState==1 && !hostFresh)throw new IllegalStateException("Input host observation stale");
        if(hostState==1 && !imageFresh)throw new IllegalStateException("Own image publication stale");
        if(hostState==1){
            if(armedAt==0){armedAt=now;LOG.info("HUD_INPUT_ARMED run={} fixture={}",identity.run(),inputFixture);}
            for(int count=0;count<64;count++){
                var event=input.poll();if(event==null)break;
                inputGate.apply(event,System.currentTimeMillis());ui.apply(client,event);
            }
            if(now-armedAt>=30_000_000_000L){finishInput(client,now,"activation_30s_complete");return;}
        }else if(now-streamAt>=60_000_000_000L){finishInput(client,now,"waiting_60s_complete");return;}
        // While waiting we own no controls. Old image/heartbeat/ticks make us
        // ineligible; only a later real fresh client tick can restore readiness.
        if(!hostFresh || !imageFresh){prearmIneligibleTicks++;return;}
        if(inputDelayFixture && hostState==0 && firstReadyAckAt!=0){
            long elapsed=now-firstReadyAckAt;
            if(elapsed>=200_000_000L && elapsed<700_000_000L){
                if(prearmDelayStartUtc==0)prearmDelayStartUtc=System.currentTimeMillis();withheldReadyTicks++;return;
            }
            if(elapsed>=700_000_000L && prearmDelayStartUtc!=0 && prearmDelayEndUtc==0)prearmDelayEndUtc=System.currentTimeMillis();
        }
        input.acknowledge(new HudInputReader.Acknowledgement(inputGate.sequence(),System.currentTimeMillis(),1,HudVanillaUiAdapter.inventory(client.currentScreen)?1:0,client.player.getInventory().selectedSlot));
        if(firstReadyAckAt==0)firstReadyAckAt=now;
    }
    private void finishInput(MinecraftClient client,long now,String reason){
        var proof=new JsonObject();proof.addProperty("input_fixture",inputFixture);proof.addProperty("input_armed",armedAt!=0);proof.addProperty("end_reason",reason);
        proof.addProperty("host_armed",armedAt!=0);proof.addProperty("input_events_applied",inputGate.sequence());
        proof.addProperty("input_delay_fixture",inputDelayFixture);proof.addProperty("withheld_ready_ack_ticks",withheldReadyTicks);proof.addProperty("prearm_ineligible_ticks",prearmIneligibleTicks);
        proof.addProperty("prearm_ack_delay_start_utc_ms",prearmDelayStartUtc);proof.addProperty("prearm_ack_delay_end_utc_ms",prearmDelayEndUtc);proof.addProperty("prearm_ack_delay_ms",prearmDelayEndUtc-prearmDelayStartUtc);
        proof.addProperty("captured_server_confirmed",capturedServerConfirmed);proof.addProperty("captured_server_pending",capturedServerPending);
        proof.addProperty("server_swap_verified",serverSwapVerified);proof.addProperty("inventory_opened",inventoryOpened);proof.addProperty("inventory_closed",inventoryClosed);proof.addProperty("selected_nine_verified",selectedNineVerified);
        proof.addProperty("events_applied",inputGate.sequence());proof.addProperty("capture_width",layout.width());proof.addProperty("capture_height",layout.height());proof.addProperty("vanilla_gui_scale",layout.guiScale());
        proof.addProperty("new_world",true);proof.addProperty("real_creative_packets",true);proof.addProperty("normal_vanilla_render_path",true);proof.addProperty("normal_shutdown_requested",true);
        proof.add("final_client_slots",jsonSlots(slots(client.player.getInventory())));Observation observation=server.get();if(observation!=null)proof.add("final_server_slots",jsonSlots(observation.slots()));
        if(inputDelayFixture){
            if(ui!=null)ui.releaseAndClose(client);inputGate.releaseAll();input.close();
            delayedCloseAckAt=now+500_000_000L;closeDelayStartUtc=System.currentTimeMillis();
        }else stopInput(client);
        proof.addProperty("controls_released",inputGate.heldKeyCount()==0 && inputGate.heldButtonCount()==0);
        inputEndingProof=proof;terminalAt=now;
        LOG.info("HUD_INPUT_TERMINAL run={} reason={} events={} serverSwapVerified={}",identity.run(),reason,inputGate.sequence(),serverSwapVerified);
    }
    private static boolean swapped(List<Slot> local){
        if(local.size()!=9)return false;
        for(int i=0;i<9;i++){int expected=i==0?1:i==1?0:i;if(!local.get(i).item().equals(Registries.ITEM.getId(Fixture.ITEMS[expected]).toString()) || local.get(i).count()!=Fixture.COUNTS[expected])return false;}
        return true;
    }
    private void stopInput(MinecraftClient client){
        if(ui!=null)ui.releaseAndClose(client);inputGate.releaseAll();
        if(input!=null){publishClosedAck(client);input.close();}
    }
    private void publishClosedAck(MinecraftClient client){int selected=client.player==null?0:client.player.getInventory().selectedSlot;input.acknowledge(new HudInputReader.Acknowledgement(inputGate.sequence(),System.currentTimeMillis(),2,0,selected));}
    private void create(MinecraftClient client){
        started=true;if(client.world!=null || client.isIntegratedServerRunning()){fail(client,"Refusing existing/open world");return;}
        oldPause=client.options.pauseOnLostFocus;client.options.pauseOnLostFocus=false;oldHidden=client.options.hudHidden;client.options.hudHidden=false;
        oldGraphics=client.options.getGraphicsMode().getValue();client.options.getGraphicsMode().setValue(GraphicsMode.FAST);
        // Exact Yarn1.21.1 Window.setWindowedSize updates the GLFW window region;
        // MinecraftClient.onResolutionChanged recalculates vanilla GUI/framebuffer sizes.
        oldGuiScale=client.options.getGuiScale().getValue();oldFullscreenOption=client.options.getFullscreen().getValue();
        oldWindowWidth=client.getWindow().getWidth();oldWindowHeight=client.getWindow().getHeight();oldWindowFullscreen=client.getWindow().isFullscreen();
        client.options.getFullscreen().setValue(false);client.getWindow().setWindowedSize(layout.width(),layout.height());
        client.options.getGuiScale().setValue(layout.guiScale());client.onResolutionChanged();
        if(Files.exists(client.runDirectory.toPath().resolve("saves").resolve(save))){fail(client,"Refusing existing HUD stream save");return;}
        GameRules rules=new GameRules();rules.get(GameRules.DO_MOB_SPAWNING).set(false,null);rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0,null);
        LevelInfo info=new LevelInfo(save,GameMode.CREATIVE,false,Difficulty.PEACEFUL,true,rules,DataConfiguration.SAFE_MODE);
        client.createIntegratedServerLoader().createAndStart(save,info,new GeneratorOptions(42,false,false),registries->registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder(),client.currentScreen);
    }
    private void observe(MinecraftServer source){
        var owner=serverOwner.get();if(stopping || owner==null)return;
        try {
            if(source!=owner.server() || !save.equals(source.getSaveProperties().getLevelName()))throw new IllegalStateException("Stream server/save identity changed");
            var entity=source.getPlayerManager().getPlayer(owner.player());if(entity==null || entity.getWorld()!=source.getOverworld())throw new IllegalStateException("Stream server player identity changed");
            server.set(new Observation(entity.getWorld(),System.nanoTime(),entity.getInventory().selectedSlot,slots(entity.getInventory())));
        }catch(Exception e){serverFailure.set(e.getMessage());}
    }
    private void restoreLayout(MinecraftClient client){
        if(oldGuiScale==null)return;
        client.options.getGuiScale().setValue(oldGuiScale);
        client.getWindow().setWindowedSize(oldWindowWidth,oldWindowHeight);
        client.options.getFullscreen().setValue(oldFullscreenOption);
        if(client.getWindow().isFullscreen()!=oldWindowFullscreen)client.getWindow().toggleFullscreen();
        client.onResolutionChanged();
    }
    private static List<Slot> slots(net.minecraft.entity.player.PlayerInventory inventory){List<Slot> result=new ArrayList<>(9);for(int i=0;i<9;i++){var stack=inventory.getStack(i);result.add(new Slot(i,Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount()));}return List.copyOf(result);}
    private static boolean matches(List<Slot> slots){for(int i=0;i<9;i++)if(!slots.get(i).item().equals(Registries.ITEM.getId(Fixture.ITEMS[i]).toString()) || slots.get(i).count()!=Fixture.COUNTS[i])return false;return true;}
    private static JsonArray jsonSlots(List<Slot> slots){var values=new JsonArray();for(Slot slot:slots){var value=new JsonObject();value.addProperty("slot",slot.slot());value.addProperty("item",slot.item());value.addProperty("count",slot.count());values.add(value);}return values;}
    private void fail(MinecraftClient client,String reason){if(stopping)return;stopInput(client);stopping=true;restoreBlend();if(output!=null){var evidence=new JsonObject();evidence.addProperty("failure",reason);output.finish("failed",evidence);}LOG.error("HUD_STREAM_FAIL run={} stage={} reason={}",identity.run(),stage,reason);client.scheduleStop();}
}
