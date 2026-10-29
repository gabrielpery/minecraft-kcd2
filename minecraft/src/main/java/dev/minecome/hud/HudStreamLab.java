package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.terrain.GroundPatch;
import com.mojang.blaze3d.systems.RenderSystem;
import dev.minecome.hud.mixin.HudWindowVsyncAccessor;
import dev.minecome.terrain.HudGroundMovementFixture;
import dev.minecome.terrain.HudPhysicalMovement;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.*;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gl.Framebuffer;
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
import org.lwjgl.glfw.GLFW;
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
    private final boolean liveMouse=Boolean.getBoolean("minecome.hudStreamLiveMouse");
    private final boolean mouseInputEnabled=HudMousePolicy.enabled(inputMode,inputFixture,liveMouse);
    private final boolean inputDelayFixture=Boolean.getBoolean("minecome.hudStreamInputDelayFixture");
    private final boolean inputPointerFixture=Boolean.getBoolean("minecome.hudStreamInputPointerFixture");
    private final boolean stoneMode=Boolean.getBoolean("minecome.hudStoneBridge"),stoneFixture=Boolean.getBoolean("minecome.hudStoneFixture"),stoneLive=Boolean.getBoolean("minecome.hudStoneLive");
    private final boolean aimedStone=Boolean.getBoolean("minecome.hudAimedStoneBridge");
    private final boolean walkingAimedMode=HudPhysicalMovementMode.walkingAimed(System.getProperties());
    private volatile HudWalkingBuildSupport walkingSupport;
    private final HudGroundMovementMode.Mode groundMovementMode=HudGroundMovementMode.mode(System.getProperties());
    private HudGroundMovementFixture groundMovement;
    private final boolean physicalMovementMode=HudPhysicalMovementMode.require(System.getProperties());
    private final boolean physicalFixtureMode=HudPhysicalMovementMode.fixture(System.getProperties());
    private final HudMovementSession movementSession=HudMovementSession.selected(System.getProperties());
    private final boolean physicalInputAtStart=inputMode && physicalMovementMode && !physicalFixtureMode;
    private HudPhysicalMovement physicalMovement;
    private HudPhysicalMovementFixture physicalFixture;
    private final boolean backgroundTrial=Boolean.getBoolean("minecome.hudStreamBackgroundTrial");
    private final boolean offscreenPresentation=Boolean.getBoolean("minecome.hudStreamOffscreenPresentation"),offscreenTrial=Boolean.getBoolean("minecome.hudStreamOffscreenTrial");
    private final long initializedAt=System.nanoTime();
    private final long offscreenLeaseDeadline;
    private final AtomicReference<Observation> server=new AtomicReference<>();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicReference<ServerOwner> serverOwner=new AtomicReference<>();
    private final HudReadback readback=new HudReadback(offscreenPresentation);
    private final HudCaptureCadence captureCadence=new HudCaptureCadence();
    private final Path outputDirectory;
    private HudStreamProducer output;
    private HudInputReader input;
    private HudVanillaUiAdapter ui;
    private HudPointerFixture pointerFixture;
    private HudBlockBridge stoneBridge;
    private boolean stoneActionsEnabled;
    private final HudInputGate inputGate=new HudInputGate(physicalMovementMode);
    private long armedAt,inputEventsApplied,pointerEventsApplied;
    private boolean fixtureTargetsSent,selectedNineVerified,inventoryOpened,inventoryClosed,serverSwapVerified;
    private JsonObject inputEndingProof;
    private String inputFailure;
    private long lastInputTickAt,maxInputTickGapMs,maxImageAgeMs,firstReadyAckAt,prearmDelayStartUtc,prearmDelayEndUtc,delayedCloseAckAt,closeDelayStartUtc;
    private long prearmIneligibleTicks,withheldReadyTicks;
    private HudRenderTiming timing;
    private final JsonArray backgroundPhases=new JsonArray();
    private long backgroundPhaseAt,backgroundPhaseUtc,focusGainEpoch,phaseFocusEpoch;
    private int backgroundResets;
    private boolean backgroundComplete;
    private Boolean oldVsync;
    private Integer oldMaxFps;
    private Boolean oldWindowVsync;
    private Integer oldWindowMaxFps;
    private static final int OFFSCREEN_FPS=30;
    private boolean offscreenFrameCapApplied;
    private long offscreenBlits,offscreenClears;
    private long offscreenSkipped,offscreenFlushes,offscreenGuardRejections,offscreenFirstUtc,offscreenLastUtc,offscreenClosureAt,offscreenClosureSkips;
    private long offscreenTrialAt,offscreenTrialUtc,offscreenTrialFocusEpoch,offscreenPhaseSkipped,offscreenPhaseRejected;
    private long offscreenUnfocusedEvents,offscreenFocusedEvents,offscreenFocusInterruptions;
    private long hiddenWindow,hiddenUnfocusedTicks,hiddenUnfocusedEvents,visibleWindowEvents,focusedWindowEvents;
    private Boolean oldWindowVisible,oldFocusOnShow;
    private boolean windowHideRequested,windowHideVerified,visibleAfterHide,glfwFocusedAfterHideRaw;
    private boolean clientFocusedBeforeHide,clientFocusedAfterHide,observedWindowVisible,observedGlfwFocusedRaw;
    private boolean focusReadyObserved,clientFocusedWhenReady=true;
    private long focusLossCallbacksAfterHide,focusReadyUtc;
    private JsonObject windowRestoration;
    private int offscreenFocusResets;
    private JsonObject offscreenTrialEvidence;
    private String terminalResult="passed";
    private Object world,player,serverIdentity;
    private long worldAt,streamAt,streamStartedUtc,stateAt,lastCaptureAt,terminalAt,pauseStartedUtc,pauseEndedUtc;
    private long capturedServerConfirmed,capturedServerPending;
    private long captureServerStaleSkips,captureUnconfirmedSkips,captureOlderReadbacks,maxServerObservationAgeMs,lastCaptureEnqueuedUtc;
    private String lastCaptureDecision="not_started";
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
    private HudStreamLab(Path outputDirectory,HudStreamProducer.Identity identity){this.outputDirectory=outputDirectory;this.identity=identity;offscreenLeaseDeadline=initializedAt+Math.max(0,Math.min(180_000,identity.expiresUtcMs()-System.currentTimeMillis()))*1_000_000L;}
    public static void initialize(){
        if(!Boolean.getBoolean("minecome.hudStreamLab"))return;
        if(active!=null)throw new IllegalStateException("HUD stream already active");
        var identity=new HudStreamProducer.Identity(required("minecome.hudStreamRun"),Integer.parseInt(required("minecome.hudStreamTargetPid")),Long.parseUnsignedLong(required("minecome.hudStreamTargetStart")),Long.parseLong(required("minecome.hudStreamExpiresUtcMs")));
        var lab=new HudStreamLab(Path.of(required("minecome.hudStreamDirectory")),identity);active=lab;
        if(lab.inputFixture && !lab.inputMode)throw new IllegalArgumentException("Input fixture requires HUD input mode");
        if(lab.inputDelayFixture && !lab.inputFixture)throw new IllegalArgumentException("Delayed input fixture requires standalone fixture mode");
        if(lab.inputPointerFixture && (!lab.inputFixture || lab.inputDelayFixture || lab.backgroundTrial))throw new IllegalArgumentException("Pointer fixture requires standalone input fixture without delay/background trial");
        if(lab.backgroundTrial && (!lab.inputFixture || lab.inputDelayFixture))throw new IllegalArgumentException("Background trial requires input fixture without deliberate ACK delay");
        if(lab.offscreenPresentation && (!lab.inputMode || lab.backgroundTrial || lab.inputDelayFixture))throw new IllegalArgumentException("Offscreen presentation requires input lab without background A/B or delayed ACK trial");
        if(lab.offscreenTrial && (!lab.offscreenPresentation || !lab.inputFixture || lab.inputDelayFixture || lab.backgroundTrial))throw new IllegalArgumentException("Offscreen trial requires exclusive offscreen input fixture");
        HudStoneMode.require(lab.stoneMode,lab.stoneFixture,lab.stoneLive,lab.inputMode,lab.inputFixture,lab.offscreenPresentation,
                lab.offscreenTrial,lab.inputPointerFixture,lab.inputDelayFixture,lab.backgroundTrial,lab.liveMouse);
        HudAimedStoneMode.require(lab.aimedStone,lab.stoneMode,lab.stoneLive,lab.stoneFixture,lab.inputMode,lab.inputFixture);
        if(lab.groundMovementMode!=HudGroundMovementMode.Mode.NONE){
            try{lab.groundMovement=new HudGroundMovementFixture(Path.of(required("minecome.groundPatchFile")),identity.run(),lab.save,
                    lab.groundMovementMode,lab.groundMovementMode.coupled()?Path.of(required("minecome.movementTraceFile")):null);}
            catch(java.io.IOException e){throw new IllegalArgumentException("HUD ground fixture patch invalid",e);}
        }
        ClientTickEvents.START_CLIENT_TICK.register(lab::timingTick);
        ClientTickEvents.END_CLIENT_TICK.register(lab::tick);ServerTickEvents.END_SERVER_TICK.register(lab::observe);
        ClientLifecycleEvents.CLIENT_STOPPING.register(client->{
            if(lab.groundMovement!=null)lab.groundMovement.close(client);
            try{lab.stopInput(client);}finally{lab.restoreOwnedWindow(client);}
            lab.stopping=true;lab.restoreBlend();lab.readback.close();if(lab.output!=null)lab.output.close();
            if(lab.oldPause!=null)client.options.pauseOnLostFocus=lab.oldPause;
            if(lab.oldHidden!=null)client.options.hudHidden=lab.oldHidden;
            if(lab.oldGraphics!=null)client.options.getGraphicsMode().setValue(lab.oldGraphics);
            lab.restoreLayout(client);
            lab.restorePresentation(client);if(lab.timing!=null)lab.timing.close();
            active=null;
        });
        LOG.info("HUD_STREAM_INITIALIZED run={} output={} actualVanillaRenderPath=true",identity.run(),lab.outputDirectory);
    }
    private static String required(String name){String value=System.getProperty(name);if(value==null || value.isBlank())throw new IllegalArgumentException(name+" is required");return value;}
    private boolean owned(MinecraftClient client){return !stopping && world!=null && client.world==world && client.player==player && client.getServer()==serverIdentity && client.isIntegratedServerRunning();}
    public static boolean suppressWorld(){var lab=active;return lab!=null && lab.given && lab.owned(MinecraftClient.getInstance());}
    public static boolean transparentFrame(){var lab=active;return lab!=null && lab.frameTransparent && lab.owned(MinecraftClient.getInstance());}
    public static void timingStage(String stage){var lab=active;if(lab!=null && lab.timing!=null && !lab.stopping)lab.timing.stage(stage);}
    public static void timingFocusChanged(boolean focused){
        var lab=active;if(lab==null)return;
        if(lab.offscreenPresentation && lab.windowHideRequested && !focused)lab.focusLossCallbacksAfterHide++;
        if((lab.backgroundTrial || lab.offscreenTrial) && focused){lab.focusGainEpoch++;if(lab.offscreenTrialEvidence!=null)lab.offscreenFocusInterruptions++;}
    }
    public static void groundPositionCorrection(){var lab=active;if(lab!=null){if(lab.groundMovement!=null)lab.groundMovement.positionCorrection();if(lab.physicalMovement!=null)lab.physicalMovement.positionCorrection();}}
    private void timingTick(MinecraftClient client){
        // Consume physical movement and UI edges in their original sequence
        // before vanilla polls KeyBindings. Reading at END made every accepted
        // movement edge wait for the following client tick. The labelled fixture
        // exercises the same phase; other profiles keep their existing END route.
        // Readiness transitions never run both paths.
        if(physicalMovementMode)physicalControlsStartTick(client);
        if(groundMovement!=null && !stopping){try{groundMovement.beforeTick(client,System.nanoTime());}catch(Exception e){fail(client,"HUD ground movement: "+e.getMessage());}}
        if(physicalMovement!=null && !stopping){try{physicalMovement.beforeTick(client,System.nanoTime());}catch(Exception e){fail(client,"HUD physical movement: "+e.getMessage());}}
        if(timing!=null && !stopping)timing.tick(armedAt!=0,client.isWindowFocused(),client.getOverlay()!=null,System.nanoTime());
    }
    private void physicalControlsStartTick(MinecraftClient client){
        // Creation, terrain setup, post-vanilla observations and final output
        // shutdown remain at END. Do not acquire input before that setup exists.
        if(stopping || terminal || physicalMovement==null || output==null || !given || streamAt==0)return;
        long now=System.nanoTime();
        // Keep the same lifetime/identity gates as tick() ahead of the earlier
        // input dispatch. inputTick retains freshness, focus, sequence and UI gates.
        if(now-initializedAt>=(inputMode?180_000_000_000L:120_000_000_000L)){fail(client,"Global HUD deadline");return;}
        if(!owned(client)){fail(client,"World/player/server identity changed");return;}
        if(now-worldAt>=(inputMode?100_000_000_000L:35_000_000_000L)){fail(client,"World HUD deadline");return;}
        if(serverFailure.get()!=null){fail(client,serverFailure.get());return;}
        if(client.getOverlay()!=null)return;
        if(output.failure()!=null){fail(client,"HUD stream worker: "+output.failure());return;}
        if(!output.isReady())return;
        try{
            if(physicalFixtureMode){if(physicalFixture!=null)physicalFixture.tick(client,now);}
            else if(physicalInputAtStart)inputTick(client,now);
        }catch(Exception e){fail(client,physicalFixtureMode?"HUD scripted physical fixture: "+e.getMessage():"HUD input: "+e.getMessage());}
    }
    public static boolean skipDesktopSwap(long window){
        var lab=active;if(lab==null || !lab.offscreenPresentation || !lab.inputMode)return false;
        RenderSystem.assertOnRenderThread();var client=MinecraftClient.getInstance();long now=System.nanoTime();
        if(!lab.offscreenAllowed(client,window,now))return false;
        boolean closed=lab.input!=null && lab.input.isClosed();
        GL11.glFlush();lab.offscreenFlushes++;lab.offscreenSkipped++;if(closed)lab.offscreenClosureSkips++;
        long utc=System.currentTimeMillis();if(lab.offscreenFirstUtc==0)lab.offscreenFirstUtc=utc;lab.offscreenLastUtc=utc;return true;
    }
    private boolean offscreenAllowed(MinecraftClient client,long window,long now){
        if(!given || terminal || !owned(client) || client.getWindow().getHandle()!=window || System.currentTimeMillis()>=identity.expiresUtcMs() || now>=offscreenLeaseDeadline){offscreenGuardRejections++;return false;}
        boolean closed=input!=null && input.isClosed();
        if(closed){
            String reason=input.reason();
            // Controlled client cleanup or normal host closure may finish the real
            // ACK without re-entering the blocking desktop swap. No input is applied here.
            if(inputEndingProof==null && !"host_closed".equals(reason) && !"guest_closed".equals(reason)){offscreenGuardRejections++;return false;}
            if(offscreenClosureAt==0)offscreenClosureAt=now;
            if(now-offscreenClosureAt>=1_500_000_000L){offscreenGuardRejections++;return false;}
        }
        return true;
    }
    public static boolean skipDesktopBlit(Framebuffer framebuffer,int width,int height){
        var lab=active;if(lab==null || !lab.offscreenPresentation || !lab.inputMode)return false;
        RenderSystem.assertOnRenderThread();var client=MinecraftClient.getInstance();
        if(framebuffer!=client.getFramebuffer() || width!=client.getWindow().getFramebufferWidth() || height!=client.getWindow().getFramebufferHeight())return false;
        if(!lab.offscreenAllowed(client,client.getWindow().getHandle(),System.nanoTime()))return false;
        var shader=client.gameRenderer.blitScreenProgram;if(shader==null)return false;
        // endWrite already bound framebuffer0. Preserve drawInternal's resulting
        // GL/cache state without sampling/drawing its desktop quad. Real HUD/PBO
        // rendering occurred earlier inside GameRenderer.render and is untouched.
        RenderSystem.disableDepthTest();RenderSystem.disableBlend();RenderSystem.viewport(0,0,width,height);
        shader.addSampler("DiffuseSampler",framebuffer.getColorAttachment());shader.unbind();
        RenderSystem.depthMask(true);RenderSystem.colorMask(true,true,true,true);lab.offscreenBlits++;return true;
    }
    public static boolean skipDesktopClear(int mask){
        var lab=active;if(lab==null || !lab.offscreenPresentation || !lab.inputMode || mask!=(GL11.GL_COLOR_BUFFER_BIT|GL11.GL_DEPTH_BUFFER_BIT))return false;
        RenderSystem.assertOnRenderThread();var client=MinecraftClient.getInstance();
        if(GL11.glGetInteger(GL30.GL_DRAW_FRAMEBUFFER_BINDING)!=0)return false;
        if(!lab.offscreenAllowed(client,client.getWindow().getHandle(),System.nanoTime()))return false;
        // This exact outer clear targets only the desktop drawable. The genuine
        // HUD color clear and vanilla depth clear run later on the owned FBO.
        lab.offscreenClears++;return true;
    }
    public static Double virtualMouseX(){var lab=active;var client=MinecraftClient.getInstance();return lab!=null && lab.ui!=null && lab.mouseInputEnabled && lab.owned(client)?lab.ui.windowX(client):null;}
    public static Double virtualMouseY(){var lab=active;var client=MinecraftClient.getInstance();return lab!=null && lab.ui!=null && lab.mouseInputEnabled && lab.owned(client)?lab.ui.windowY(client):null;}
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
    private boolean publicationPaused(long now){return !inputMode && !physicalFixtureMode && streamAt!=0 && now-streamAt>=10_500_000_000L && now-streamAt<11_800_000_000L;}
    private void capture(MinecraftClient client){
        RenderSystem.assertOnRenderThread();long now=System.nanoTime();boolean paused=publicationPaused(now);
        timingStage("pbo_poll");
        readback.poll(frame->{
            // PBO slots can complete in a different order after reuse. An older slot
            // must never replace the latest captured UI in the worker mailbox.
            if(frame.id()<=lastReadbackId){captureOlderReadbacks++;return;}
            lastReadbackId=frame.id();
            if(output==null || terminal || paused)return;
            var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();
            if(groundMovement!=null && meta.has("ground_movement_phase"))groundMovement.captured(meta);
            if(physicalFixture!=null && meta.has("physical_fixture_phase"))physicalFixture.captured(meta.get("physical_fixture_phase").getAsString());
            if(timing!=null)timing.readbackAge(System.currentTimeMillis()-meta.get("captured_utc_ms").getAsLong());
            output.offer(new HudStreamProducer.Frame(frame.width(),frame.height(),frame.bottomUp(),meta.get("captured_utc_ms").getAsLong(),meta.get("selected_slot").getAsInt(),meta.get("screen").getAsInt(),frame.metadata()));
        });
        timingStage("capture_metadata");
        if(output==null || !output.isReady() || terminal || (!inputMode && stage<0)){lastCaptureDecision="output_or_stage_not_ready";return;}
        if(paused || (!inputMode && now-stateAt<250_000_000L)){lastCaptureDecision="capture_interval";return;}
        if(client.getOverlay()!=null){lastCaptureDecision="overlay";return;}
        boolean inventory=(inputMode||physicalFixtureMode)?HudVanillaUiAdapter.inventory(client.currentScreen):stage==2;
        if(inventory && !(client.currentScreen instanceof InventoryScreen) && !(client.currentScreen instanceof CreativeInventoryScreen))return;
        if(!inventory && client.currentScreen!=null)return;
        // A 50 ms timer skips alternate frames at the owned 30 FPS cap. Capture
        // mouse-controlled inventory once per render; the hotbar keeps its timer.
        boolean renderDriven=HudCaptureCadence.renderDriven(inputMode,mouseInputEnabled,offscreenPresentation,offscreenFrameCapApplied,inventory);
        if(!HudCaptureCadence.due(now,lastCaptureAt,renderDriven)){lastCaptureDecision="capture_interval";return;}
        Observation observation=server.get();List<Slot> local=slots(client.player.getInventory());int selected=client.player.getInventory().selectedSlot;
        int expected=stage==0?0:stage==3?2:1;
        boolean serverFresh=observation!=null && now-observation.at()<=250_000_000L && observation.world()!=null;
        if(observation!=null)maxServerObservationAgeMs=Math.max(maxServerObservationAgeMs,(now-observation.at())/1_000_000);
        boolean serverConfirmed=serverFresh && observation.slots().equals(local) && observation.selected()==selected;
        // Interactive frames show vanilla client prediction immediately. Requiring
        // server agreement here starves pixels while successive slot keys are in flight.
        // Authoritative input proof remains in inputTick's fresh matching observation.
        if(!serverFresh){captureServerStaleSkips++;lastCaptureDecision="server_observation_stale";return;}
        if(!inputMode && (!serverConfirmed || (!physicalFixtureMode && selected!=expected))){captureUnconfirmedSkips++;lastCaptureDecision="auto_state_unconfirmed";return;}
        if(!inputMode && !matches(local))throw new IllegalStateException("Actual stream inventory differs from fixture");
        var meta=new JsonObject();meta.addProperty("state",(inputMode||physicalFixtureMode)?(inventory?"inventory":"hotbar"):(stage==0?"hotbar_slot0":stage==1?"hotbar_slot1":stage==2?"inventory_screen":"hotbar_slot2"));
        if(physicalFixture!=null)meta.addProperty("state","fixture_"+physicalFixture.phase());
        meta.addProperty("selected_slot",selected);meta.addProperty("screen",inventory?1:0);meta.addProperty("screen_kind",client.currentScreen==null?"none":client.currentScreen.getClass().getSimpleName());
        meta.addProperty("captured_utc_ms",System.currentTimeMillis());meta.addProperty("client_server_inventory_confirmed",serverConfirmed);
        meta.addProperty("server_selected_slot",observation.selected());meta.addProperty("server_observation_age_ms",(now-observation.at())/1_000_000);
        meta.addProperty("no_world_pixels",true);meta.addProperty("hand_pixels",false);meta.addProperty("gui_scale",client.getWindow().getScaleFactor());
        if(groundMovement!=null){meta.addProperty("ground_movement_phase",groundMovement.phase());groundMovement.captureMetadata(meta);}
        if(physicalFixture!=null)meta.addProperty("physical_fixture_phase",physicalFixture.phase());
        meta.add("client_slots",jsonSlots(local));meta.add("server_slots",jsonSlots(observation.slots()));
        timingStage("pbo_enqueue");
        try{if(readback.capture(client.getFramebuffer(),++captureId,meta.toString())){lastCaptureAt=now;captureCadence.captured(inventory,now);lastCaptureEnqueuedUtc=System.currentTimeMillis();lastCaptureDecision="enqueued";if(serverConfirmed)capturedServerConfirmed++;else capturedServerPending++;}else lastCaptureDecision="pbo_busy";}
        finally{timingStage("game_render");}
    }
    private void tick(MinecraftClient client){
        if(stopping)return;long now=System.nanoTime();
        if(now-initializedAt>=(inputMode?180_000_000_000L:120_000_000_000L)){fail(client,"Global HUD deadline");return;}
        if(!started && client.currentScreen!=null && client.getOverlay()==null){create(client);return;}
        if(!started || client.world==null || client.player==null || !client.isIntegratedServerRunning()){if(world!=null)fail(client,"Owned stream world disconnected");return;}
        if(world==null){world=client.world;player=client.player;serverIdentity=client.getServer();worldAt=now;serverOwner.set(new ServerOwner(serverIdentity,client.player.getUuid()));}
        if(!owned(client)){fail(client,"World/player/server identity changed");return;}
        if(now-worldAt>=(inputMode?((backgroundTrial||offscreenTrial)?140_000_000_000L:100_000_000_000L):35_000_000_000L)){fail(client,"World HUD deadline");return;}
        if(serverFailure.get()!=null){fail(client,serverFailure.get());return;}
        if(client.getOverlay()!=null)return;
        if(!given){
            if(client.currentScreen!=null)return;
            if(client.getFramebuffer().textureWidth!=layout.width() || client.getFramebuffer().textureHeight!=layout.height() || client.getWindow().getScaleFactor()!=layout.guiScale()){
                fail(client,"Requested stream framebuffer/GUI scale was not applied");return;
            }
            if(client.interactionManager==null || client.interactionManager.getCurrentGameMode()!=GameMode.CREATIVE){fail(client,"Fresh Creative inventory API unavailable");return;}
            for(int i=0;i<9;i++){var stack=inputPointerFixture && i>=7?ItemStack.EMPTY:new ItemStack(Fixture.ITEMS[i],Fixture.COUNTS[i]);client.player.getInventory().setStack(i,stack);client.interactionManager.clickCreativeStack(stack,36+i);}
            client.player.getInventory().selectedSlot=0;given=true;
            if(groundMovement!=null || physicalFixtureMode){stage=0;stateAt=now;}
            if(offscreenPresentation){
                client.options.getMaxFps().setValue(OFFSCREEN_FPS);offscreenFrameCapApplied=client.getWindow().getFramerateLimit()==OFFSCREEN_FPS && client.options.getMaxFps().getValue()==OFFSCREEN_FPS;
                if(!offscreenFrameCapApplied){fail(client,"Offscreen frame cap was not applied");return;}
                try{hideOwnedWindow(client);}catch(Exception e){fail(client,"Owned offscreen window hide: "+e.getMessage());return;}
            }
            Path project=client.runDirectory.toPath().toAbsolutePath().normalize().getParent().getParent();
            output=new HudStreamProducer(project,outputDirectory,identity,save,true,inputMode?(inputFixture?2:1):0);output.start();
            if(inputMode)ui=new HudVanillaUiAdapter(client,mouseInputEnabled);
            if(inputPointerFixture)pointerFixture=new HudPointerFixture();
            if(stoneMode && !walkingAimedMode)stoneBridge=aimedStone?new HudAimedStoneBridge(Path.of(required("minecome.tokenFile")),save):new HudStoneBridge(Path.of(required("minecome.tokenFile")));
            if(backgroundTrial || offscreenPresentation)timing=new HudRenderTiming(Thread.currentThread(),RenderSystem::isFrozenAtPollEvents);
        }
        if(output.failure()!=null){fail(client,"HUD stream worker: "+output.failure());return;}
        if(physicalMovementMode && !terminal && inputEndingProof==null && output.isReady()){
            try{
                if(physicalMovement==null){
                    var wire=new HudInputProtocol.Identity(identity.run(),output.producerPid(),output.producerStart(),identity.targetPid(),identity.targetStart(),identity.expiresUtcMs());
                    physicalMovement=new HudPhysicalMovement(Path.of(required("minecome.groundPatchFile")),Path.of(required("minecome.movementTraceFile")),
                            Path.of(required("minecome.hudHostViewFile")),save,wire,physicalFixtureMode,movementSession);
                    if(physicalFixtureMode)physicalFixture=new HudPhysicalMovementFixture(client,physicalMovement,Path.of(required("minecome.groundPatchFile")),Path.of(required("minecome.hudHostViewFile")),wire);
                }
                physicalMovement.afterTick(client,System.nanoTime());
                if(walkingAimedMode && physicalMovement.inputReady(System.nanoTime()) && stoneBridge==null){
                    if(walkingSupport==null){
                        boolean wide=HudPhysicalMovementMode.wide(System.getProperties());
                        var heading=physicalMovement.freshBuildHeading(System.nanoTime());
                        if(!wide || heading!=null)walkingSupport=new HudWalkingBuildSupport(client,GroundPatch.read(Path.of(required("minecome.groundPatchFile")),wide),save,heading);
                    }
                    if(walkingSupport!=null && walkingSupport.prepare(client))stoneBridge=new HudAimedStoneBridge(Path.of(required("minecome.tokenFile")),save,walkingSupport,physicalMovement,output);
                }
            }catch(Exception e){fail(client,"HUD physical movement: "+e.getMessage());return;}
        }
        if(groundMovement!=null && !terminal){
            try{groundMovement.afterTick(client,now);}
            catch(Exception e){fail(client,"HUD ground movement: "+e.getMessage());return;}
            // Stage0 already captures real HUD pixels while vanilla moves. The
            // unchanged20s UI sequence begins only after movement is complete.
            if(!groundMovement.passed())return;
        }
        if(offscreenPresentation && !terminal && inputEndingProof==null){
            try{
                observeHiddenWindow(client);
                if(hiddenClientUnfocused(client)){
                    hiddenUnfocusedTicks++;
                    if(!focusReadyObserved){clientFocusedWhenReady=client.isWindowFocused();focusReadyUtc=System.currentTimeMillis();focusReadyObserved=true;}
                }
            }
            catch(Exception e){fail(client,"Owned offscreen window: "+e.getMessage());return;}
        }
        if(!terminal && output.isReady()){
            if(streamAt==0){
                streamAt=now;
                // Metadata only: map the existing monotonic start to wall time.
                // Round elapsed time up so a prompt never gains an extra millisecond.
                long sampledUtc=System.currentTimeMillis(),sampledNs=System.nanoTime();
                streamStartedUtc=sampledUtc-(sampledNs-streamAt+999_999L)/1_000_000L;
                LOG.info("HUD_STREAM_READY run={} save={} realCreativePackets=true inputMode={}",identity.run(),save,inputMode);
            }
            long elapsed=now-streamAt;
            if(physicalFixtureMode){
                try{
                    if(physicalFixture.finished()){
                        var proof=new JsonObject();proof.addProperty("new_world",true);proof.addProperty("real_creative_packets",true);
                        proof.addProperty("normal_vanilla_render_path",true);proof.addProperty("scripted_input",true);proof.addProperty("physical_input_verified",false);
                        proof.addProperty("input_tick_phase","start_before_vanilla");
                        proof.add("physical_controller_fixture",physicalFixture.evidence(client));
                        output.finish("passed",proof);terminal=true;terminalAt=now;
                    }
                }catch(Exception e){fail(client,"HUD scripted physical fixture: "+e.getMessage());return;}
            }else if(inputMode){
                try{
                    if(backgroundTrial && !backgroundComplete)backgroundTrialTick(client,now);if(offscreenTrial)offscreenTrialTick(client,now);
                    if(!physicalInputAtStart)inputTick(client,now);
                    if(stoneBridge!=null && inputEndingProof==null && !terminal){
                        stoneBridge.tick(client,stoneActionsEnabled);
                        if(stoneBridge.failed())throw new IllegalStateException("Combined stone bridge: "+stoneBridge.failure());
                    }
                }catch(Exception e){fail(client,"HUD input: "+e.getMessage());return;}
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
                if(groundMovement!=null){
                    try{if(!groundMovement.finish(client))return;}
                    catch(Exception e){fail(client,"HUD ground cleanup: "+e.getMessage());return;}
                }
                var proof=new JsonObject();proof.addProperty("new_world",true);proof.addProperty("real_creative_packets",true);
                proof.addProperty("normal_vanilla_render_path",true);proof.addProperty("scheduled_capture_hz",20);proof.addProperty("elapsed_ms",elapsed/1_000_000);
                proof.addProperty("capture_width",layout.width());proof.addProperty("capture_height",layout.height());proof.addProperty("vanilla_gui_scale",layout.guiScale());
                proof.addProperty("intentional_publication_pause_start_utc_ms",pauseStartedUtc);proof.addProperty("intentional_publication_pause_end_utc_ms",pauseEndedUtc);
                proof.addProperty("intentional_publication_pause_ms",pauseEndedUtc-pauseStartedUtc);proof.addProperty("normal_shutdown_requested",true);
                if(groundMovement!=null)proof.add("ground_movement",groundMovement.evidence(client));
                output.finish("passed",proof);terminal=true;terminalAt=now;
            }
            }
        }
        if(terminal){
            if(!output.isFinished()){if(now-terminalAt>4_000_000_000L)fail(client,"Stream finalization 4s deadline");return;}
            if(output.failure()!=null){fail(client,"Stream terminal: "+output.failure());return;}
            LOG.info("HUD_STREAM_TERMINAL run={} save={} result={} published={} actualVanillaHud=true actualVanillaInventory={} hostCompositingVerified=false",identity.run(),save,terminalResult,output.publishedFrames(),inputMode?inventoryOpened:physicalFixtureMode?physicalFixture.inventoryCaptured():stage==3);
            stopping=true;client.scheduleStop();
        }
    }
    private void inputTick(MinecraftClient client,long now){
        stoneActionsEnabled=false;
        if(timing!=null)timing.inputTick(now);
        if(lastInputTickAt!=0)maxInputTickGapMs=Math.max(maxInputTickGapMs,(now-lastInputTickAt)/1_000_000);
        lastInputTickAt=now;
        if(inputEndingProof!=null){
            if(delayedCloseAckAt!=0 && now>=delayedCloseAckAt){
                publishClosedAck(client);delayedCloseAckAt=0;
                inputEndingProof.addProperty("closed_ack_delay_ms",System.currentTimeMillis()-closeDelayStartUtc);
            }
            if(!input.isFinished()){if(now-terminalAt>1_500_000_000L)throw new IllegalStateException("Input cleanup1.5s timeout");return;}
            if(physicalMovement!=null){
                if(!physicalMovement.cleanupComplete()){if(now-terminalAt>1_500_000_000L)throw new IllegalStateException("Physical movement cleanup1.5s timeout");return;}
                inputEndingProof.add("physical_movement",physicalMovement.evidence(client));
            }
            inputEndingProof.addProperty("input_handles_closed",input.cleanupComplete());inputEndingProof.addProperty("closed_acknowledgement_published",input.closedAcknowledgementPublished());
            inputEndingProof.add("input_timing",input.diagnostics());inputEndingProof.addProperty("max_client_tick_gap_ms",maxInputTickGapMs);inputEndingProof.addProperty("max_own_image_age_ms",maxImageAgeMs);
            inputEndingProof.add("capture_pipeline",captureDiagnostics());inputEndingProof.add("publication_at_cleanup",output.diagnostics());
            if(timing!=null){timing.close();inputEndingProof.add("render_timing",timing.overall());}
            if(backgroundTrial)inputEndingProof.add("background_trial",backgroundEvidence());
            if(backgroundTrial || offscreenPresentation){restorePresentation(client);var restored=presentationRestoration(client);inputEndingProof.add("presentation_restoration",restored);if(!restored.get("restored").getAsBoolean())throw new IllegalStateException("HUD presentation restoration failed");}
            if(offscreenPresentation){restoreOwnedWindow(client);inputEndingProof.add("window_restoration",windowRestoration.deepCopy());if(!windowRestoration.get("cleanup_succeeded").getAsBoolean())throw new IllegalStateException("Owned window terminal cleanup failed");}
            addOffscreenEvidence(inputEndingProof);
            if(!input.cleanupComplete())throw new IllegalStateException("Input handle cleanup failed");
            boolean interacted=inputEventsApplied>0 || (stoneLive && (aimedStone?HudAimedStoneProof.hasConfirmedLiveInteraction(inputEndingProof):HudStoneProof.hasConfirmedLiveInteraction(inputEndingProof)));
            String result=inputFailure!=null?"failed":inputFixture?"input_passed":(armedAt!=0 && interacted?"input_completed":"input_cancelled");
            terminalResult=result;output.finish(result,inputEndingProof);terminal=true;terminalAt=now;return;
        }
        if(input==null && output.publishedFrames()>0){
            var wire=new HudInputProtocol.Identity(identity.run(),output.producerPid(),output.producerStart(),identity.targetPid(),identity.targetStart(),identity.expiresUtcMs());
            input=new HudInputReader(wire,physicalMovementMode);input.start();
        }
        if(input==null)return;
        ui.synchronizeScreen(client);
        if(offscreenPresentation && (client.options.getMaxFps().getValue()!=OFFSCREEN_FPS || client.getWindow().getFramerateLimit()!=OFFSCREEN_FPS))throw new IllegalStateException("Owned offscreen frame cap changed");
        boolean inventory=HudVanillaUiAdapter.inventory(client.currentScreen);
        if(client.currentScreen!=null && !inventory)throw new IllegalStateException("Unexpected screen in owned UI lab");
        Observation observation=server.get();List<Slot> local=slots(client.player.getInventory());
        if(observation!=null && now-observation.at()<=250_000_000L && observation.slots().equals(local) && observation.selected()==client.player.getInventory().selectedSlot){
            if(observation.selected()==8)selectedNineVerified=true;
            if(swapped(local))serverSwapVerified=true;
        }
        if(inventory){
            inventoryOpened=true;
            if(inputFixture && !inputPointerFixture && !stoneFixture && !fixtureTargetsSent){output.offerFixtureTargets(ui.fixtureTargets(client));fixtureTargetsSent=true;}
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
        boolean offscreenFocusReady=!offscreenPresentation || hiddenClientUnfocused(client);
        boolean walkingBootstrapReady=!walkingAimedMode || (stoneBridge instanceof HudAimedStoneBridge aimed && aimed.walkingBootstrapped());
        if(physicalMovement!=null)physicalMovement.authority(client,now,hostState==1 && hostFresh && imageFresh && offscreenFocusReady && walkingBootstrapReady);
        if(hostState==1 && !offscreenFocusReady)throw new IllegalStateException("Owned offscreen window is not actually unfocused");
        if(hostState==1 && !hostFresh)throw new IllegalStateException("Input host observation stale");
        if(hostState==1 && !imageFresh)throw new IllegalStateException("Own image publication stale");
        if(hostState==1){
            if(backgroundTrial && !backgroundComplete)throw new IllegalStateException("Background fixture armed before comparison completed");
            if(offscreenTrial && offscreenTrialEvidence==null)throw new IllegalStateException("Offscreen fixture armed before background readiness");
            if(armedAt==0){armedAt=now;if(physicalMovement!=null)physicalMovement.activate(now);LOG.info("HUD_INPUT_ARMED run={} fixture={}",identity.run(),inputFixture);}
            for(int count=0;count<64;count++){
                var event=input.poll();if(event==null)break;
                if(offscreenPresentation){
                    observeHiddenWindow(client);
                    if(!hiddenClientUnfocused(client))throw new IllegalStateException("Owned window focus/visibility changed before input");
                }
                inputGate.apply(event,System.currentTimeMillis());
                if(physicalMovement!=null && event.kind()<=2 && HudMovementKeys.movement(event.code())){
                    try{physicalMovement.event(client,event,System.nanoTime());}
                    catch(java.io.IOException e){throw new IllegalStateException("Physical movement trace: "+e.getMessage(),e);}
                }else{
                    if(physicalMovement!=null && event.kind()==1 && (event.code()==0x45 || event.code()==0x1b))physicalMovement.suspend(client);
                    ui.apply(client,event);
                }
                inputEventsApplied++;
                if(event.kind()>=3)pointerEventsApplied++;
                if(offscreenPresentation)hiddenUnfocusedEvents++;
                if(offscreenTrial){if(client.isWindowFocused())offscreenFocusedEvents++;else offscreenUnfocusedEvents++;}
            }
            if(pointerFixture!=null){
                // Re-read both sides after actual Screen calls; the pre-event observation
                // cannot certify a gesture that has just changed the client inventory.
                Observation current=server.get();long observedAt=System.nanoTime();
                long age=current==null?-1:(observedAt-current.at())/1_000_000;
                boolean confirmed=current!=null && age>=0 && age<=250 && current.slots().equals(slots(client.player.getInventory())) && current.selected()==client.player.getInventory().selectedSlot;
                pointerFixture.observe(client,ui,inputEventsApplied,age,confirmed,current==null?new JsonArray():jsonSlots(current.slots()),output);
            }
            if(now-armedAt>=30_000_000_000L){finishInput(client,now,"activation_30s_complete");return;}
            stoneActionsEnabled=true;
        }else if(now-streamAt>=((backgroundTrial||offscreenTrial)?100_000_000_000L:60_000_000_000L)){finishInput(client,now,(backgroundTrial||offscreenTrial)?"waiting_100s_complete":"waiting_60s_complete");return;}
        // While waiting we own no controls. Old image/heartbeat/ticks make us
        // ineligible; only a later real fresh client tick can restore readiness.
        if(!hostFresh || !imageFresh || !offscreenFocusReady ||
                (walkingAimedMode && (walkingSupport==null || stoneBridge==null)) ||
                (physicalMovementMode && (physicalMovement==null || !physicalMovement.inputReady(System.nanoTime())))){prearmIneligibleTicks++;return;}
        if(inputDelayFixture && hostState==0 && firstReadyAckAt!=0){
            long elapsed=now-firstReadyAckAt;
            if(elapsed>=200_000_000L && elapsed<700_000_000L){
                if(prearmDelayStartUtc==0)prearmDelayStartUtc=System.currentTimeMillis();withheldReadyTicks++;return;
            }
            if(elapsed>=700_000_000L && prearmDelayStartUtc!=0 && prearmDelayEndUtc==0)prearmDelayEndUtc=System.currentTimeMillis();
        }
        input.acknowledge(new HudInputReader.Acknowledgement(inputGate.sequence(),System.currentTimeMillis(),1,HudVanillaUiAdapter.inventory(client.currentScreen)?1:0,client.player.getInventory().selectedSlot));
        if(physicalMovement!=null && streamStartedUtc>0){try{physicalMovement.publishReady(outputDirectory,System.nanoTime(),streamStartedUtc,streamStartedUtc+60_000L);}catch(java.io.IOException e){throw new IllegalStateException("Physical readiness receipt: "+e.getMessage(),e);}}
        if(firstReadyAckAt==0)firstReadyAckAt=now;
    }
    private void finishInput(MinecraftClient client,long now,String reason){
        if(inputPointerFixture && inputFailure==null && (pointerFixture==null || !pointerFixture.complete()))throw new IllegalStateException("Pointer fixture ended before all real gesture proofs");
        var proof=new JsonObject();proof.addProperty("input_fixture",inputFixture);proof.addProperty("input_armed",armedAt!=0);proof.addProperty("end_reason",reason);
        proof.addProperty("input_tick_phase",physicalInputAtStart?"start_before_vanilla":"end_after_vanilla");
        proof.addProperty("aimed_stone_bridge",aimedStone);
        proof.addProperty("live_mouse",liveMouse);proof.addProperty("pointer_events_applied",pointerEventsApplied);if(ui!=null)proof.add("pointer_adapter",ui.pointerDiagnostics());
        proof.addProperty("pointer_fixture",inputPointerFixture);if(pointerFixture!=null)proof.add("pointer_evidence",pointerFixture.evidence());
        proof.addProperty("host_armed",armedAt!=0);proof.addProperty("input_events_applied",inputEventsApplied);proof.addProperty("input_consumed_sequence",inputGate.sequence());
        proof.addProperty("input_delay_fixture",inputDelayFixture);proof.addProperty("withheld_ready_ack_ticks",withheldReadyTicks);proof.addProperty("prearm_ineligible_ticks",prearmIneligibleTicks);
        proof.addProperty("prearm_ack_delay_start_utc_ms",prearmDelayStartUtc);proof.addProperty("prearm_ack_delay_end_utc_ms",prearmDelayEndUtc);proof.addProperty("prearm_ack_delay_ms",prearmDelayEndUtc-prearmDelayStartUtc);
        proof.addProperty("captured_server_confirmed",capturedServerConfirmed);proof.addProperty("captured_server_pending",capturedServerPending);
        proof.addProperty("server_swap_verified",serverSwapVerified);proof.addProperty("inventory_opened",inventoryOpened);proof.addProperty("inventory_closed",inventoryClosed);proof.addProperty("selected_nine_verified",selectedNineVerified);
        proof.addProperty("events_applied",inputEventsApplied);proof.addProperty("capture_width",layout.width());proof.addProperty("capture_height",layout.height());proof.addProperty("vanilla_gui_scale",layout.guiScale());
        proof.addProperty("new_world",true);proof.addProperty("real_creative_packets",true);proof.addProperty("normal_vanilla_render_path",true);proof.addProperty("normal_shutdown_requested",true);
        proof.add("final_client_slots",jsonSlots(slots(client.player.getInventory())));Observation observation=server.get();if(observation!=null)proof.add("final_server_slots",jsonSlots(observation.slots()));
        if(inputDelayFixture && inputFailure==null){
            if(ui!=null)ui.releaseAndClose(client);inputGate.releaseAll();input.close();
            delayedCloseAckAt=now+500_000_000L;closeDelayStartUtc=System.currentTimeMillis();
        }else stopInput(client);
        if(stoneBridge!=null)proof.add("stone_bridge",stoneBridge.evidence());
        if(ui!=null)proof.add("pointer_adapter_after_cleanup",ui.pointerDiagnostics());
        proof.addProperty("controls_released",inputGate.heldKeyCount()==0 && inputGate.heldButtonCount()==0);
        inputEndingProof=proof;terminalAt=now;
        LOG.info("HUD_INPUT_TERMINAL run={} reason={} events={} serverSwapVerified={}",identity.run(),reason,inputEventsApplied,serverSwapVerified);
    }
    private static boolean swapped(List<Slot> local){
        if(local.size()!=9)return false;
        for(int i=0;i<9;i++){int expected=i==0?1:i==1?0:i;if(!local.get(i).item().equals(Registries.ITEM.getId(Fixture.ITEMS[expected]).toString()) || local.get(i).count()!=Fixture.COUNTS[expected])return false;}
        return true;
    }
    private void stopInput(MinecraftClient client){
        if(physicalFixture!=null)physicalFixture.close();
        if(physicalMovement!=null)physicalMovement.close(client);
        stoneActionsEnabled=false;if(stoneBridge!=null)stoneBridge.close();
        if(ui!=null)ui.releaseAndClose(client);inputGate.releaseAll();
        if(input!=null){publishClosedAck(client);input.close();}
    }
    private void publishClosedAck(MinecraftClient client){int selected=client.player==null?0:client.player.getInventory().selectedSlot;input.acknowledge(new HudInputReader.Acknowledgement(inputGate.sequence(),System.currentTimeMillis(),2,0,selected));}
    private void create(MinecraftClient client){
        started=true;if(client.world!=null || client.isIntegratedServerRunning()){fail(client,"Refusing existing/open world");return;}
        oldPause=client.options.pauseOnLostFocus;client.options.pauseOnLostFocus=false;oldHidden=client.options.hudHidden;client.options.hudHidden=false;
        oldGraphics=client.options.getGraphicsMode().getValue();client.options.getGraphicsMode().setValue(GraphicsMode.FAST);
        if(backgroundTrial || offscreenPresentation || physicalFixtureMode){oldVsync=client.options.getEnableVsync().getValue();oldMaxFps=client.options.getMaxFps().getValue();oldWindowVsync=((HudWindowVsyncAccessor)(Object)client.getWindow()).minecome$vsync();oldWindowMaxFps=client.getWindow().getFramerateLimit();}
        if(physicalFixtureMode){client.options.getEnableVsync().setValue(false);client.options.getMaxFps().setValue(30);}
        // Exact Yarn1.21.1 Window.setWindowedSize updates the GLFW window region;
        // MinecraftClient.onResolutionChanged recalculates vanilla GUI/framebuffer sizes.
        oldGuiScale=client.options.getGuiScale().getValue();oldFullscreenOption=client.options.getFullscreen().getValue();
        oldWindowWidth=client.getWindow().getWidth();oldWindowHeight=client.getWindow().getHeight();oldWindowFullscreen=client.getWindow().isFullscreen();
        client.options.getFullscreen().setValue(false);client.getWindow().setWindowedSize(layout.width(),layout.height());
        client.options.getGuiScale().setValue(layout.guiScale());client.onResolutionChanged();
        if(Files.exists(client.runDirectory.toPath().resolve("saves").resolve(save))){fail(client,"Refusing existing HUD stream save");return;}
        GameRules rules=new GameRules();rules.get(GameRules.DO_MOB_SPAWNING).set(false,null);rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0,null);
        LevelInfo info=new LevelInfo(save,GameMode.CREATIVE,false,Difficulty.PEACEFUL,true,rules,DataConfiguration.SAFE_MODE);
        client.createIntegratedServerLoader().createAndStart(save,info,new GeneratorOptions(42,false,false),registries->{
            var dimensions=registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder();
            if(groundMovementMode==HudGroundMovementMode.Mode.NONE && !physicalMovementMode)return dimensions;
            var biome=registries.get(RegistryKeys.BIOME).getEntry(net.minecraft.world.biome.BiomeKeys.THE_VOID).orElseThrow();
            var config=new net.minecraft.world.gen.chunk.FlatChunkGeneratorConfig(Optional.of(net.minecraft.registry.entry.RegistryEntryList.of()),biome,List.of());
            config.updateLayerBlocks();
            return dimensions.with(registries,new net.minecraft.world.gen.chunk.FlatChunkGenerator(config));
        },client.currentScreen);
    }
    private void observe(MinecraftServer source){
        var owner=serverOwner.get();if(stopping || owner==null)return;
        try {
            if(source!=owner.server() || !save.equals(source.getSaveProperties().getLevelName()))throw new IllegalStateException("Stream server/save identity changed");
            var entity=source.getPlayerManager().getPlayer(owner.player());if(entity==null || entity.getWorld()!=source.getOverworld())throw new IllegalStateException("Stream server player identity changed");
            server.set(new Observation(entity.getWorld(),System.nanoTime(),entity.getInventory().selectedSlot,slots(entity.getInventory())));
            if(groundMovement!=null)groundMovement.observe(source);
            if(physicalMovement!=null)physicalMovement.observe(source);
            if(physicalFixture!=null)physicalFixture.observe(source);
            var buildSupport=walkingSupport;if(buildSupport!=null)buildSupport.observe(source);
        }catch(Exception e){serverFailure.set(e.getMessage());}
    }
    private void restoreLayout(MinecraftClient client){
        if(oldGuiScale==null)return;
        restoreOwnedWindow(client);
        if(keepOwnedWindowHiddenForExit())return;
        client.options.getGuiScale().setValue(oldGuiScale);
        client.getWindow().setWindowedSize(oldWindowWidth,oldWindowHeight);
        client.options.getFullscreen().setValue(oldFullscreenOption);
        if(client.getWindow().isFullscreen()!=oldWindowFullscreen)client.getWindow().toggleFullscreen();
        client.onResolutionChanged();
    }
    private static boolean windowAttribute(long handle,int attribute){
        int value=GLFW.glfwGetWindowAttrib(handle,attribute);
        if(value!=GLFW.GLFW_TRUE && value!=GLFW.GLFW_FALSE)throw new IllegalStateException("Invalid GLFW window attribute");
        return value==GLFW.GLFW_TRUE;
    }
    private void hideOwnedWindow(MinecraftClient client){
        RenderSystem.assertOnRenderThread();long handle=client.getWindow().getHandle();
        if(!offscreenPresentation || !offscreenAllowed(client,handle,System.nanoTime()))throw new IllegalStateException("Offscreen window ownership/lease unavailable");
        if(client.getWindow().isFullscreen() || GLFW.glfwGetWindowMonitor(handle)!=0)throw new IllegalStateException("Hiding requires the owned windowed guest");
        hiddenWindow=handle;oldWindowVisible=windowAttribute(handle,GLFW.GLFW_VISIBLE);oldFocusOnShow=windowAttribute(handle,GLFW.GLFW_FOCUS_ON_SHOW);
        clientFocusedBeforeHide=client.isWindowFocused();windowHideRequested=true;GLFW.glfwHideWindow(handle);
        visibleAfterHide=windowAttribute(handle,GLFW.GLFW_VISIBLE);glfwFocusedAfterHideRaw=windowAttribute(handle,GLFW.GLFW_FOCUSED);clientFocusedAfterHide=client.isWindowFocused();windowHideVerified=!visibleAfterHide;
        if(!windowHideVerified)throw new IllegalStateException("GLFW did not hide the owned guest");
        observeHiddenWindow(client);
        LOG.info("HUD_OWNED_WINDOW_HIDDEN run={} visible={} glfwFocusedRaw={} clientFocused={} lossCallbacks={}",identity.run(),visibleAfterHide,glfwFocusedAfterHideRaw,clientFocusedAfterHide,focusLossCallbacksAfterHide);
    }
    private void observeHiddenWindow(MinecraftClient client){
        RenderSystem.assertOnRenderThread();long handle=client.getWindow().getHandle();
        if(!windowHideVerified || hiddenWindow!=handle || client.getWindow().isFullscreen() || GLFW.glfwGetWindowMonitor(handle)!=0)throw new IllegalStateException("Owned hidden window identity/mode changed");
        observedWindowVisible=windowAttribute(handle,GLFW.GLFW_VISIBLE);observedGlfwFocusedRaw=windowAttribute(handle,GLFW.GLFW_FOCUSED);
        if(observedWindowVisible)throw new IllegalStateException("Owned offscreen window became visible");
        if(client.getFramebuffer().textureWidth!=layout.width() || client.getFramebuffer().textureHeight!=layout.height() || client.getWindow().getScaleFactor()!=layout.guiScale())throw new IllegalStateException("Hidden guest framebuffer/GUI size changed");
    }
    private boolean hiddenClientUnfocused(MinecraftClient client){
        // Bundled GLFW3.4 Win32 uses GetActiveWindow (calling-thread queue) for
        // GLFW_FOCUSED. Its WM_KILLFOCUS callback, forwarded by MC's exact Window,
        // is the focus authority here; the raw attribute remains diagnostic only.
        return !observedWindowVisible && !client.isWindowFocused() && (!clientFocusedBeforeHide || focusLossCallbacksAfterHide>0);
    }
    private void restoreOwnedWindow(MinecraftClient client){
        if(oldWindowVisible==null)return;
        RenderSystem.assertOnRenderThread();boolean keepHidden=keepOwnedWindowHiddenForExit();
        var proof=HudWindowCleanup.finish(new HudWindowCleanup.Window(){
            public long handle(){return client.getWindow().getHandle();}
            public boolean windowed(){return !client.getWindow().isFullscreen() && GLFW.glfwGetWindowMonitor(hiddenWindow)==0;}
            public boolean visible(){return windowAttribute(hiddenWindow,GLFW.GLFW_VISIBLE);}
            public boolean focusOnShow(){return windowAttribute(hiddenWindow,GLFW.GLFW_FOCUS_ON_SHOW);}
            public void focusOnShow(boolean value){GLFW.glfwSetWindowAttrib(hiddenWindow,GLFW.GLFW_FOCUS_ON_SHOW,value?GLFW.GLFW_TRUE:GLFW.GLFW_FALSE);}
            public void show(){GLFW.glfwShowWindow(hiddenWindow);}
            public void hide(){GLFW.glfwHideWindow(hiddenWindow);}
        },hiddenWindow,oldWindowVisible,oldFocusOnShow,keepHidden);
        boolean layoutSkipped=false;
        try{
            if(keepHidden && proof.get("cleanup_succeeded").getAsBoolean() && oldGuiScale!=null){
                client.options.getGuiScale().setValue(oldGuiScale);client.options.getFullscreen().setValue(oldFullscreenOption);
                // Pinned1.21.1 option callback only toggles Window.fullscreen. Cancel
                // that pending runtime change before another swap; native resize or
                // fullscreen restoration could show this process just before exit.
                if(client.getWindow().isFullscreen())client.getWindow().toggleFullscreen();
                layoutSkipped=true;
            }
            if(proof.get("window_identity_verified").getAsBoolean()){
                proof.addProperty("glfw_focused_after_raw",windowAttribute(hiddenWindow,GLFW.GLFW_FOCUSED));proof.addProperty("client_focused_after",client.isWindowFocused());
            }
        }catch(RuntimeException e){proof.addProperty("cleanup_succeeded",false);proof.addProperty("failure",e.getMessage());}
        proof.addProperty("layout_runtime_restore_skipped",layoutSkipped);
        proof.addProperty("layout_options_restored",oldGuiScale!=null && client.options.getGuiScale().getValue().equals(oldGuiScale) && client.options.getFullscreen().getValue().equals(oldFullscreenOption));
        proof.addProperty("process_exit_observed",false);
        windowRestoration=proof;
    }
    private boolean keepOwnedWindowHiddenForExit(){return HudWindowCleanup.retainHidden(inputMode,inputFixture,liveMouse,offscreenPresentation,windowHideVerified);}
    private void restorePresentation(MinecraftClient client){
        if(oldVsync==null)return;
        client.options.getEnableVsync().setValue(oldVsync);client.options.getMaxFps().setValue(oldMaxFps);
        client.getWindow().setVsync(oldWindowVsync);client.getWindow().setFramerateLimit(oldWindowMaxFps);
    }
    private JsonObject presentationRestoration(MinecraftClient client){
        var proof=new JsonObject();boolean actualVsync=((HudWindowVsyncAccessor)(Object)client.getWindow()).minecome$vsync();int actualFps=client.getWindow().getFramerateLimit();
        boolean restored=client.options.getEnableVsync().getValue().equals(oldVsync) && client.options.getMaxFps().getValue().equals(oldMaxFps) && actualVsync==oldWindowVsync && actualFps==oldWindowMaxFps;
        proof.addProperty("restored",restored);proof.addProperty("original_vsync",oldVsync);proof.addProperty("original_max_fps",oldMaxFps);proof.addProperty("actual_window_vsync",actualVsync);proof.addProperty("actual_window_max_fps",actualFps);
        proof.addProperty("option_vsync",client.options.getEnableVsync().getValue());proof.addProperty("option_max_fps",client.options.getMaxFps().getValue());proof.addProperty("explicit_options_file_write",false);
        proof.addProperty("original_window_vsync",oldWindowVsync);proof.addProperty("original_window_max_fps",oldWindowMaxFps);
        return proof;
    }
    private void backgroundTrialTick(MinecraftClient client,long now){
        if(timing==null)return;
        if(client.isWindowFocused() || (backgroundPhaseAt!=0 && phaseFocusEpoch!=focusGainEpoch)){
            if(backgroundPhaseAt!=0){backgroundResets++;backgroundPhaseAt=0;timing.beginPhase();}
            return;
        }
        boolean baseline=backgroundPhases.isEmpty();boolean expectedVsync=baseline?oldVsync:false;int expectedFps=baseline?oldMaxFps:60;
        if(client.options.getEnableVsync().getValue()!=expectedVsync || ((HudWindowVsyncAccessor)(Object)client.getWindow()).minecome$vsync()!=expectedVsync || client.options.getMaxFps().getValue()!=expectedFps || client.getWindow().getFramerateLimit()!=expectedFps)
            throw new IllegalStateException("Background trial presentation settings changed unexpectedly");
        if(backgroundPhaseAt==0){backgroundPhaseAt=now;backgroundPhaseUtc=System.currentTimeMillis();phaseFocusEpoch=focusGainEpoch;timing.beginPhase();LOG.info("HUD_BACKGROUND_PHASE run={} phase={} vsync={} fps={} actualUnfocused=true",identity.run(),baseline?"baseline":"trial",expectedVsync,expectedFps);return;}
        if(now-backgroundPhaseAt<12_000_000_000L)return;
        var measured=timing.phase();
        if(measured.get("focused_ticks").getAsLong()!=0 || measured.get("unfocused_ticks").getAsLong()==0)throw new IllegalStateException("Background phase lacks actual unfocused ticks");
        var phase=new JsonObject();phase.addProperty("name",baseline?"baseline":"trial");phase.addProperty("duration_ms",(now-backgroundPhaseAt)/1_000_000);
        phase.addProperty("started_utc_ms",backgroundPhaseUtc);phase.addProperty("ended_utc_ms",System.currentTimeMillis());phase.addProperty("focused_ticks",0);phase.add("unfocused_ticks",measured.get("unfocused_ticks"));
        phase.addProperty("vsync",expectedVsync);phase.addProperty("max_fps",expectedFps);phase.add("timing",measured);backgroundPhases.add(phase);backgroundPhaseAt=0;
        if(baseline){timingStage("trial_settings");client.options.getEnableVsync().setValue(false);client.options.getMaxFps().setValue(60);timingStage("client_tick");}
        else{backgroundComplete=true;output.offerBackgroundTrial(backgroundEvidence());LOG.info("HUD_BACKGROUND_COMPARISON_READY run={} phases=2 performanceFixedClaim=false",identity.run());}
    }
    private JsonObject backgroundEvidence(){var proof=new JsonObject();proof.addProperty("completed",backgroundComplete);proof.addProperty("focus_resets",backgroundResets);proof.addProperty("focus_evidence","actual_client_tick_and_focus_callback; observation gaps reported in timing");proof.add("phases",backgroundPhases.deepCopy());return proof;}
    private void offscreenTrialTick(MinecraftClient client,long now){
        if(timing==null || inputEndingProof!=null)return;
        if(offscreenTrialEvidence!=null){
            if(!hiddenClientUnfocused(client) || focusGainEpoch!=offscreenTrialFocusEpoch)throw new IllegalStateException("Offscreen trial regained focus after readiness");
            return;
        }
        if(!hiddenClientUnfocused(client) || (offscreenTrialAt!=0 && offscreenTrialFocusEpoch!=focusGainEpoch)){
            if(offscreenTrialAt!=0){offscreenFocusResets++;offscreenTrialAt=0;timing.beginPhase();}return;
        }
        if(offscreenTrialAt==0){
            offscreenTrialAt=now;offscreenTrialUtc=System.currentTimeMillis();offscreenTrialFocusEpoch=focusGainEpoch;offscreenPhaseSkipped=offscreenSkipped;offscreenPhaseRejected=offscreenGuardRejections;
            timing.beginPhase();LOG.info("HUD_OFFSCREEN_PHASE run={} actualUnfocused=true desktopSwapSuppressed=true",identity.run());return;
        }
        if(now-offscreenTrialAt<12_000_000_000L)return;
        var measured=timing.phase();long skipped=offscreenSkipped-offscreenPhaseSkipped;
        if(measured.get("focused_ticks").getAsLong()!=0 || measured.get("unfocused_ticks").getAsLong()==0 || skipped<=0 || offscreenGuardRejections!=offscreenPhaseRejected)
            throw new IllegalStateException("Offscreen trial lacks continuously owned unfocused presentation proof");
        var proof=new JsonObject();proof.addProperty("completed",true);proof.addProperty("duration_ms",(now-offscreenTrialAt)/1_000_000);proof.addProperty("started_utc_ms",offscreenTrialUtc);proof.addProperty("ended_utc_ms",System.currentTimeMillis());
        proof.addProperty("focused_ticks",0);proof.add("unfocused_ticks",measured.get("unfocused_ticks"));proof.addProperty("presentation_suppressed",true);proof.addProperty("skipped_swaps",skipped);proof.addProperty("focus_resets",offscreenFocusResets);
        proof.addProperty("window_vsync",((HudWindowVsyncAccessor)(Object)client.getWindow()).minecome$vsync());proof.addProperty("window_max_fps",client.getWindow().getFramerateLimit());
        proof.addProperty("window_visible",observedWindowVisible);proof.addProperty("window_client_focused",client.isWindowFocused());proof.addProperty("window_glfw_focused_raw",observedGlfwFocusedRaw);proof.addProperty("focus_authority","minecraft_window_focus_callback");proof.addProperty("framebuffer_size_preserved",client.getFramebuffer().textureWidth==layout.width() && client.getFramebuffer().textureHeight==layout.height());
        proof.addProperty("focus_evidence","actual_client_tick_and_focus_callback; observation gaps reported in timing");proof.add("timing",measured);
        offscreenTrialEvidence=proof;output.offerOffscreenTrial(proof);LOG.info("HUD_OFFSCREEN_READY run={} skippedSwaps={} actualUnfocused=true",identity.run(),skipped);
    }
    private void addOffscreenEvidence(JsonObject proof){
        if(!offscreenPresentation)return;
        var presentation=new JsonObject();presentation.addProperty("enabled",true);presentation.addProperty("skipped_swaps",offscreenSkipped);presentation.addProperty("gl_flushes",offscreenFlushes);
        presentation.addProperty("guard_rejections",offscreenGuardRejections);presentation.addProperty("first_skip_utc_ms",offscreenFirstUtc);presentation.addProperty("last_skip_utc_ms",offscreenLastUtc);
        presentation.addProperty("vanilla_flip_frame_preserved",true);presentation.addProperty("closure_grace_limit_ms",1500);presentation.addProperty("closure_skipped_swaps",offscreenClosureSkips);proof.add("offscreen_presentation",presentation);
        presentation.addProperty("desktop_blits_skipped",offscreenBlits);presentation.addProperty("desktop_clears_skipped",offscreenClears);presentation.addProperty("active_guest_fps_limit",OFFSCREEN_FPS);presentation.addProperty("frame_limit_applied",offscreenFrameCapApplied);
        var window=new JsonObject();window.addProperty("hide_requested",windowHideRequested);window.addProperty("hide_verified",windowHideVerified);
        window.addProperty("owned_window_handle",Long.toUnsignedString(hiddenWindow));
        window.addProperty("original_visible",oldWindowVisible);window.addProperty("original_focus_on_show",oldFocusOnShow);window.addProperty("visible_after_hide",visibleAfterHide);window.addProperty("glfw_focused_after_hide_raw",glfwFocusedAfterHideRaw);
        window.addProperty("client_focused_before_hide",clientFocusedBeforeHide);window.addProperty("client_focused_after_hide",clientFocusedAfterHide);window.addProperty("focus_loss_callbacks_after_hide",focusLossCallbacksAfterHide);window.addProperty("focus_authority","minecraft_window_focus_callback");
        window.addProperty("focus_ready_observed",focusReadyObserved);window.addProperty("client_focused_when_ready",clientFocusedWhenReady);window.addProperty("focus_ready_utc_ms",focusReadyUtc);
        window.addProperty("hidden_unfocused_ticks",hiddenUnfocusedTicks);window.addProperty("hidden_unfocused_events_applied",hiddenUnfocusedEvents);window.addProperty("visible_events_applied",visibleWindowEvents);window.addProperty("focused_events_applied",focusedWindowEvents);proof.add("offscreen_window",window);
        if(windowRestoration!=null)proof.add("window_restoration",windowRestoration.deepCopy());
        if(offscreenTrial){
            if(offscreenTrialEvidence!=null)proof.add("offscreen_trial",offscreenTrialEvidence.deepCopy());
            var events=new JsonObject();events.addProperty("unfocused_events_applied",offscreenUnfocusedEvents);events.addProperty("focused_events_applied",offscreenFocusedEvents);events.addProperty("focus_interruptions",offscreenFocusInterruptions);proof.add("offscreen_trial_events",events);
        }
    }
    private JsonObject captureDiagnostics(){
        var proof=new JsonObject();proof.addProperty("last_decision",lastCaptureDecision);proof.addProperty("server_stale_skips",captureServerStaleSkips);proof.addProperty("auto_unconfirmed_skips",captureUnconfirmedSkips);
        proof.addProperty("older_completed_readbacks_ignored",captureOlderReadbacks);proof.addProperty("max_server_observation_age_ms",maxServerObservationAgeMs);proof.addProperty("last_enqueued_utc_ms",lastCaptureEnqueuedUtc);
        var cadence=captureCadence.diagnostics();cadence.addProperty("inventory_render_driven",HudCaptureCadence.renderDriven(inputMode,mouseInputEnabled,offscreenPresentation,offscreenFrameCapApplied,true));proof.add("cadence",cadence);
        var observed=server.get();proof.addProperty("current_server_observation_age_ms",observed==null?-1:(System.nanoTime()-observed.at())/1_000_000);proof.add("pbo",readback.diagnostics());return proof;
    }
    private static List<Slot> slots(net.minecraft.entity.player.PlayerInventory inventory){List<Slot> result=new ArrayList<>(9);for(int i=0;i<9;i++){var stack=inventory.getStack(i);result.add(new Slot(i,Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount()));}return List.copyOf(result);}
    private static boolean matches(List<Slot> slots){for(int i=0;i<9;i++)if(!slots.get(i).item().equals(Registries.ITEM.getId(Fixture.ITEMS[i]).toString()) || slots.get(i).count()!=Fixture.COUNTS[i])return false;return true;}
    private static JsonArray jsonSlots(List<Slot> slots){var values=new JsonArray();for(Slot slot:slots){var value=new JsonObject();value.addProperty("slot",slot.slot());value.addProperty("item",slot.item());value.addProperty("count",slot.count());values.add(value);}return values;}
    private void fail(MinecraftClient client,String reason){
        if(stopping)return;
        if(groundMovement!=null)groundMovement.abort(client,reason);
        if(physicalMovement!=null)physicalMovement.abort(client,reason);
        if(inputMode && input!=null && inputEndingProof==null && owned(client)){
            inputFailure=reason;var snapshot=new JsonObject();snapshot.add("capture_pipeline",captureDiagnostics());snapshot.add("publication",output.diagnostics());snapshot.add("input_timing",input.diagnostics());
            finishInput(client,System.nanoTime(),"failure");inputEndingProof.addProperty("failure",reason);inputEndingProof.add("failure_snapshot",snapshot);
            LOG.error("HUD_STREAM_FAIL run={} stage={} reason={} cleanupPending=true",identity.run(),stage,reason);return;
        }
        try{stopInput(client);}finally{restoreOwnedWindow(client);}
        stopping=true;restoreBlend();
        if(output!=null){
            var evidence=inputEndingProof==null?new JsonObject():inputEndingProof.deepCopy();evidence.addProperty("failure",reason);evidence.add("capture_pipeline",captureDiagnostics());evidence.add("publication_at_failure",output.diagnostics());
            if(stoneBridge!=null)evidence.add("stone_bridge",stoneBridge.evidence());
            if(groundMovement!=null)evidence.add("ground_movement",groundMovement.evidence(client));
            if(physicalFixture!=null)evidence.add("physical_controller_fixture",physicalFixture.evidence(client));
            if(input!=null){evidence.add("input_timing",input.diagnostics());evidence.addProperty("input_handles_closed",input.cleanupComplete());evidence.addProperty("closed_acknowledgement_published",input.closedAcknowledgementPublished());evidence.addProperty("input_cleanup_finished",input.isFinished());}
            if(timing!=null){timing.close();evidence.add("render_timing",timing.overall());}
            if(backgroundTrial)evidence.add("background_trial",backgroundEvidence());
            if(backgroundTrial || offscreenPresentation){restorePresentation(client);evidence.add("presentation_restoration",presentationRestoration(client));}addOffscreenEvidence(evidence);output.finish("failed",evidence);
        }
        LOG.error("HUD_STREAM_FAIL run={} stage={} reason={}",identity.run(),stage,reason);client.scheduleStop();
    }
}
