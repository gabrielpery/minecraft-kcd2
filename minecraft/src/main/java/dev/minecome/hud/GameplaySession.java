package dev.minecome.hud;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.blaze3d.systems.RenderSystem;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayAimReader;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import dev.minecome.terrain.GameplayMovement;
import dev.minecome.terrain.GameplayMovementKeys;
import com.sun.jna.platform.win32.Kernel32;
import com.sun.jna.platform.win32.WinBase;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gl.Framebuffer;
import net.minecraft.client.option.GraphicsMode;
import org.lwjgl.glfw.GLFW;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL14;
import org.lwjgl.opengl.GL30;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Set;
import java.util.function.BooleanSupplier;

/** Persistent vanilla guest/HUD, optionally attached to captured host terrain. */
public final class GameplaySession {
    private static final Logger LOG=LoggerFactory.getLogger("MineComeGameplay");
    private static volatile GameplaySession active;
    private final Path root,directory,stopFile;
    private final HudStreamProducer.Identity identity;
    private final boolean standalone=Boolean.getBoolean("minecome.gameplayStandalone");
    private final String fixtureMode=System.getProperty("minecome.gameplayFixture","");
    private final boolean chatMode=Boolean.getBoolean("minecome.gameplayChat");
    private final boolean flightMode=Boolean.getBoolean("minecome.gameplayFlight");
    private final boolean handsMode=Boolean.getBoolean("minecome.gameplayHands"); private final boolean worldBlocksMode=Boolean.getBoolean("minecome.gameplayWorldBlocks");
    private final boolean blocksMode=Boolean.getBoolean("minecome.gameplayBlocks");
    private final boolean movementMode=blocksMode||Boolean.getBoolean("minecome.gameplayMovement");
    private final HudStreamLayout layout=HudStreamLayout.configured();
    private final HudReadback readback=new HudReadback();
    private final GameplayWorldLayers worldLayers=new GameplayWorldLayers();
    private JsonObject frameWorldCamera;
    private final HudInputGate gate=new HudInputGate(movementMode,blocksMode,chatMode);
    private final long initializedAt=System.nanoTime();
    private GameplayWorld save;
    private HudStreamProducer output;
    private HudInputReader input;
    private HudVanillaUiAdapter ui;
    private GameplayPersistenceFixture fixture;
    private GameplayMovement movement;
    private GameplayMovementFixture movementFixture;
    private GameplayBlocks blocks;
    private GameplayAimReader aimReader;
    private GameplayAimReader.RenderSample admittedNativeView; private volatile int desiredPerspective;
    private boolean nativePerspectiveObserved; private int lastAcknowledgedPerspective;
    private GameplayBlocksFixture blocksFixture;
    private GameplayTerrainFixture terrainFixture;
    private GameplayChatFixture chatFixture;
    private GameplayFlightFixture flightFixture;
    private GameplayHandsFixture handsFixture; private GameplayWorldBlocksFixture worldBlocksFixture; private int renderedWorldBlocks; private long worldBlockFrames,worldOutlineFrames;
    private GameplayShapesFixture shapesFixture; private GameplayDepthFixture depthFixture;
    private GameplayPlayerFixture playerFixture; private boolean playerFrameRendered; private long playerRenderFrames; private net.minecraft.client.option.Perspective oldPerspective;
    private GameplayConnectedBlocksFixture connectedFixture; private GameplayShapeWalkingFixture shapeWalkingFixture;
    private int renderedTerrainOccluders; private long terrainDepthFrames;
    private net.minecraft.util.math.BlockPos outlinedBlock;
    private boolean handFrameRendered;
    private long handRenderStarts,handRenderPasses,handCapturedFrames;
    private Object world,player,server;
    private boolean opening,ready,stopping,writerFinished,shutdownRequested,frameTransparent,sessionReportWritten;
    private long readyAt,stopAt,writerAt,lastCaptureAt,inputEvents;
    private long uiWarmupAt; private int uiWarmupFrames; private boolean uiWarmupComplete;
    private int captureId,lastReadbackId;
    private String stopReason="not_stopped",failure;
    private JsonObject fixtureResult;
    private int[] priorBlend;
    private Boolean oldPause,oldHidden,oldFullscreen,oldVsync;
    private Integer oldScale,oldFps;
    private GraphicsMode oldGraphics;
    private int oldWidth,oldHeight;
    private long hiddenWindow,focusLossCallbacksAfterHide,desktopSwapsSkipped;
    private Boolean oldWindowVisible,oldFocusOnShow;
    private boolean windowHideRequested,windowHideVerified,clientFocusedBeforeHide;
    private boolean inputConnectedSeen,inputArmedSeen;
    private JsonObject windowCleanup;

    private GameplaySession(Path root,Path directory,HudStreamProducer.Identity identity)throws IOException{
        if(!root.isAbsolute()||!directory.isAbsolute())throw new IllegalArgumentException("Absolute gameplay paths required");
        this.root=root.toRealPath();this.directory=directory.normalize();this.identity=identity;
        Path parent=directory.getParent().toRealPath();
        if(!parent.startsWith(this.root.resolve("runtime/evidence")))throw new IOException("Gameplay session output must be inside runtime/evidence");
        Path requested=Path.of(System.getProperty("minecome.gameplayStopFile",parent.resolve("session.stop").toString())).toAbsolutePath().normalize();
        if(!requested.getParent().equals(parent))throw new IOException("Gameplay stop file must be in this session directory");
        stopFile=requested;
        if(!fixtureMode.isEmpty()&&!standalone)throw new IllegalArgumentException("Persistence fixture requires standalone gameplay");
        if(chatMode&&!blocksMode)throw new IllegalArgumentException("Gameplay chat requires the explicit blocks/movement profile");
        if(flightMode&&!chatMode)throw new IllegalArgumentException("Gameplay flight requires the chat/world input profile");
        if(worldBlocksMode&&!handsMode)throw new IllegalArgumentException("World blocks requires the hands/gameplay profile"); if(handsMode&&!flightMode)throw new IllegalArgumentException("Gameplay hands requires the flight/gameplay profile");
    }

    public static void initialize(){
        if(!Boolean.getBoolean("minecome.gameplay"))return;
        if(active!=null)throw new IllegalStateException("Gameplay session already initialized");
        for(String key:System.getProperties().stringPropertyNames()){
            if(!key.startsWith("minecome.")||key.startsWith("minecome.gameplay"))continue;
            if(Boolean.getBoolean(key)&&(key.endsWith("Lab")||key.contains("Fixture")||key.startsWith("minecome.hudGround")
                    ||key.startsWith("minecome.hudPhysical")||key.equals("minecome.smokeWorld")||key.equals("minecome.dynamicBridgeSmoke")))
                throw new IllegalArgumentException("Gameplay cannot share development lab ownership: "+key);
        }
        try{
            var identity=new HudStreamProducer.Identity(required("minecome.hudStreamRun"),Integer.parseInt(required("minecome.hudStreamTargetPid")),
                    Long.parseUnsignedLong(required("minecome.hudStreamTargetStart")),Long.parseLong(required("minecome.hudStreamExpiresUtcMs")));
            var session=new GameplaySession(Path.of(required("minecome.root")),Path.of(required("minecome.hudStreamDirectory")),identity);
            active=session;
            ClientTickEvents.START_CLIENT_TICK.register(session::beforeTick);
            ClientTickEvents.END_CLIENT_TICK.register(session::tick);
            ServerTickEvents.END_SERVER_TICK.register(source->{var b=session.blocks;if(b!=null)b.observe(source);var m=session.movement;if(m!=null)m.observe(source);});
            ClientLifecycleEvents.CLIENT_STOPPING.register(session::onClientStopping);
            LOG.info("GAMEPLAY_INITIALIZED run={} standalone={} persistentSave={}",identity.run(),session.standalone,GameplayWorld.SAVE_NAME);
        }catch(IOException e){throw new IllegalArgumentException("Gameplay session paths invalid",e);}
    }
    private static String required(String key){String value=System.getProperty(key);if(value==null||value.isBlank())throw new IllegalArgumentException(key+" is required");return value;}
    private HudInputProtocol.Identity wireIdentity(){
        var api=Kernel32.INSTANCE;var created=new WinBase.FILETIME();
        if(!api.GetProcessTimes(api.GetCurrentProcess(),created,new WinBase.FILETIME(),new WinBase.FILETIME(),new WinBase.FILETIME()))throw new IllegalStateException("Gameplay process identity unavailable");
        long start=(Integer.toUnsignedLong(created.dwHighDateTime)<<32)|Integer.toUnsignedLong(created.dwLowDateTime);
        return new HudInputProtocol.Identity(identity.run(),api.GetCurrentProcessId(),start,identity.targetPid(),identity.targetStart(),identity.expiresUtcMs());
    }
    private void beforeTick(MinecraftClient client){
        if(stopping||movement==null)return;
        try{if(playerFixture!=null)playerFixture.beforeTick(client);if(connectedFixture!=null)connectedFixture.beforeTick(client);if(shapeWalkingFixture!=null)shapeWalkingFixture.beforeTick(client);if(depthFixture!=null)depthFixture.beforeTick(client);if(shapesFixture!=null)shapesFixture.beforeTick(client);if(worldBlocksFixture!=null)worldBlocksFixture.beforeTick(client);if(handsFixture!=null)handsFixture.beforeTick(client);if(flightFixture!=null)flightFixture.beforeTick(client);if(chatFixture!=null)chatFixture.beforeTick(client);if(terrainFixture!=null)terrainFixture.beforeTick(client);if(blocksFixture!=null)blocksFixture.beforeTick(client);if(movementFixture!=null)movementFixture.beforeTick(client);movement.beforeTick(client,System.nanoTime());}
        catch(Exception e){requestStop(client,"movement_failure",e.toString());}
    }
    private boolean owns(MinecraftClient client){return ready&&!stopping&&client.world==world&&client.player==player&&client.getServer()==server&&client.isIntegratedServerRunning();}
    public static boolean preserveBlockBreaking(){var s=active;var client=MinecraftClient.getInstance();return s!=null&&s.blocks!=null&&s.owns(client)&&s.blocks.needsVanillaBreakPreserved(client);}
    public static boolean suppressWorld(){var s=active;return s!=null&&(!s.standalone||s.handsMode)&&s.owns(MinecraftClient.getInstance());}
    public static boolean handsEnabled(){var s=active;return s!=null&&s.handsMode&&s.owns(MinecraftClient.getInstance());}
    /** Request only; actual perspective changes after the matching native camera sample arrives. */
    public static boolean requestPerspective(){
        var s=active;var client=MinecraftClient.getInstance();
        if(s==null||s.standalone||!s.worldBlocksMode||!client.isOnThread()||!s.owns(client)||client.currentScreen!=null)return false;
        s.desiredPerspective=(s.desiredPerspective+1)%3;return true;
    }
    public static int requestedPerspective(){var s=active;return s==null?0:s.desiredPerspective;}
    public static boolean transparentFrame(){var s=active;return s!=null&&s.frameTransparent&&s.owns(MinecraftClient.getInstance());}
    public static Double virtualMouseX(){var s=active;var c=MinecraftClient.getInstance();return s!=null&&s.ui!=null&&s.owns(c)?s.ui.windowX(c):null;}
    public static Double virtualMouseY(){var s=active;var c=MinecraftClient.getInstance();return s!=null&&s.ui!=null&&s.owns(c)?s.ui.windowY(c):null;}
    public static void timingFocusChanged(boolean focused){
        var s=active;if(s!=null&&!s.standalone&&s.windowHideRequested&&!focused)s.focusLossCallbacksAfterHide++;
    }
    public static boolean skipDesktopSwap(long window){
        var s=active;if(s==null||!s.offscreenAllowed(MinecraftClient.getInstance(),window))return false;
        RenderSystem.assertOnRenderThread();GL11.glFlush();s.desktopSwapsSkipped++;return true;
    }
    public static boolean skipDesktopBlit(Framebuffer framebuffer,int width,int height){
        var s=active;var client=MinecraftClient.getInstance();
        if(s==null||framebuffer!=client.getFramebuffer()||width!=client.getWindow().getFramebufferWidth()
                ||height!=client.getWindow().getFramebufferHeight()||!s.offscreenAllowed(client,client.getWindow().getHandle()))return false;
        RenderSystem.assertOnRenderThread();var shader=client.gameRenderer.blitScreenProgram;if(shader==null)return false;
        // Same desktop-only state changes as the proven stream lab; the actual
        // HUD framebuffer and its asynchronous readback have already rendered.
        RenderSystem.disableDepthTest();RenderSystem.disableBlend();RenderSystem.viewport(0,0,width,height);
        shader.addSampler("DiffuseSampler",framebuffer.getColorAttachment());shader.unbind();
        RenderSystem.depthMask(true);RenderSystem.colorMask(true,true,true,true);return true;
    }
    public static boolean skipDesktopClear(int mask){
        var s=active;if(s==null||mask!=(GL11.GL_COLOR_BUFFER_BIT|GL11.GL_DEPTH_BUFFER_BIT))return false;
        RenderSystem.assertOnRenderThread();var client=MinecraftClient.getInstance();
        return GL11.glGetInteger(GL30.GL_DRAW_FRAMEBUFFER_BINDING)==0&&s.offscreenAllowed(client,client.getWindow().getHandle());
    }
    private boolean offscreenAllowed(MinecraftClient client,long window){
        if(standalone||!ready||!windowHideVerified||window!=hiddenWindow||client.getWindow().getHandle()!=hiddenWindow)return false;
        // Continue only the desktop bypass during bounded terminal cleanup, so
        // a hidden drawable cannot block saving; this path applies no input.
        if(stopping)return System.nanoTime()-stopAt<6_000_000_000L;
        return System.currentTimeMillis()<identity.expiresUtcMs()&&client.getServer()==server&&client.isIntegratedServerRunning();
    }

    private void tick(MinecraftClient client){
        try{
            if(stopping){finishStop(client);return;}
            if(Files.exists(stopFile)){requestStop(client,"stop_requested",null);return;}
            if(System.currentTimeMillis()>=identity.expiresUtcMs()){requestStop(client,"session_expired",null);return;}
            if(!opening){
                if(!client.isFinishedLoading()||client.getOverlay()!=null)return;
                if(client.world!=null||client.isIntegratedServerRunning())throw new IllegalStateException("Refusing an existing active world");
                opening=true;configure(client);
                save=GameplayWorld.prepare(client.getLevelStorage().getSavesDirectory().toAbsolutePath(),root);
                if(movementMode){
                    var wire=wireIdentity();
                    movement=new GameplayMovement(root,save,Path.of(required("minecome.gameplayGroundFile")),standalone,wire,directory.getParent());
                    if(blocksMode){
                        blocks=new GameplayBlocks(root,save,movement.surface(),wire,directory.getParent(),worldBlocksMode);
                        movement.blockController(blocks);
                        if(!standalone)aimReader=new GameplayAimReader(directory.getParent(),wire,movement.surface(),save.id().toString(),worldBlocksMode);
                        if(fixtureMode.startsWith("blocks"))blocksFixture=new GameplayBlocksFixture(fixtureMode,blocks,movement,save,wire,directory.getParent(),proof->{
                            fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"blocks_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());
                        });
                        if(fixtureMode.startsWith("terrain"))terrainFixture=new GameplayTerrainFixture(fixtureMode,blocks,movement,save,wire,directory.getParent(),proof->{
                            fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"terrain_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());
                        });
                        if(fixtureMode.startsWith("chat"))chatFixture=new GameplayChatFixture(fixtureMode,movement,save,wire,directory.getParent(),proof->{
                            fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"chat_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());
                        });
                        if(fixtureMode.startsWith("flight"))flightFixture=new GameplayFlightFixture(fixtureMode,movement,save,wire,directory.getParent(),proof->{
                            fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"flight_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());
                        });
                        if(fixtureMode.equals("player"))playerFixture=new GameplayPlayerFixture(fixtureMode,blocks,movement,save,wire,directory.getParent(),proof->{fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"player_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());});
                        if(fixtureMode.startsWith("connected"))connectedFixture=new GameplayConnectedBlocksFixture(fixtureMode,blocks,movement,save,wire,directory.getParent(),proof->{fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"connected_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());});
                        if(fixtureMode.equals("shape-walking"))shapeWalkingFixture=new GameplayShapeWalkingFixture(fixtureMode,blocks,movement,save,wire,directory.getParent(),proof->{fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"shape_walking_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());});
                        if(fixtureMode.equals("depth"))depthFixture=new GameplayDepthFixture(fixtureMode,blocks,movement,save,wire,directory.getParent(),proof->{fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"depth_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());});
                        if(fixtureMode.startsWith("shapes"))shapesFixture=new GameplayShapesFixture(fixtureMode,blocks,movement,save,wire,directory.getParent(),proof->{fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"shapes_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());});
                        if(fixtureMode.startsWith("world-blocks"))worldBlocksFixture=new GameplayWorldBlocksFixture(fixtureMode,blocks,movement,save,wire,directory.getParent(),proof->{fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"world_blocks_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());}); if(fixtureMode.equals("hands"))handsFixture=new GameplayHandsFixture(fixtureMode,movement,save,wire,directory.getParent(),proof->{
                            fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"hands_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());
                        });
                    }
                    if(fixtureMode.startsWith("walking"))movementFixture=new GameplayMovementFixture(fixtureMode,movement,save,wire,directory.getParent(),proof->{
                        fixtureResult=proof.deepCopy();requestStop(MinecraftClient.getInstance(),"movement_fixture_complete",proof.get("result").getAsString().equals("passed")?null:proof.toString());
                    });
                }
                save.open(client,()->requestStop(client,"world_load_cancelled",null));
                return;
            }
            if(!ready){
                if(System.nanoTime()-initializedAt>120_000_000_000L)throw new IllegalStateException("Gameplay world startup deadline");
                if(client.world==null||client.player==null||!client.isIntegratedServerRunning()||client.currentScreen!=null||client.getOverlay()!=null)return;
                if(!client.getServer().getSaveProperties().getLevelName().equals(save.saveName()))throw new IllegalStateException("Gameplay world name differs");
                save.verifyOwnership();world=client.world;player=client.player;server=client.getServer();
                if(!standalone){ui=new HudVanillaUiAdapter(client,true,chatMode);hideOwnedWindow(client);}
                ready=true;readyAt=System.nanoTime();
                if(!fixtureMode.isEmpty()&&!fixtureMode.startsWith("walking")&&!fixtureMode.startsWith("blocks")&&!fixtureMode.startsWith("terrain")&&!fixtureMode.startsWith("chat")&&!fixtureMode.startsWith("flight")&&!fixtureMode.equals("hands")&&!fixtureMode.startsWith("world-blocks")&&!fixtureMode.startsWith("shapes")&&!fixtureMode.equals("depth")&&!fixtureMode.startsWith("connected")&&!fixtureMode.equals("shape-walking")&&!fixtureMode.equals("player"))fixture=new GameplayPersistenceFixture(fixtureMode,save,directory.getParent(),proof->{
                    fixtureResult=proof.deepCopy();boolean passed=proof.has("result")&&proof.get("result").getAsString().equals("passed");
                    requestStop(MinecraftClient.getInstance(),"fixture_complete",passed?null:proof.toString());
                });
                if(worldBlocksMode&&!standalone){
                    // Render the real inventory once before admitting native input.
                    // The first Creative screen can initialize item GPU resources
                    // beyond the 250ms live publication lease. Keep that lease
                    // unchanged; do cold initialization while no host is armed.
                    uiWarmupAt=System.nanoTime();
                    client.setScreen(new net.minecraft.client.gui.screen.ingame.InventoryScreen(client.player));
                }else startPublication(client);
            }
            if(client.getServer()!=server||!client.isIntegratedServerRunning()){requestStop(client,"world_closed",null);return;}
            if(output==null){
                observeHiddenWindow(client);
                if(System.nanoTime()-uiWarmupAt>10_000_000_000L)throw new IllegalStateException("Inventory preparation deadline");
                if(!HudVanillaUiAdapter.inventory(client.currentScreen))throw new IllegalStateException("Inventory preparation screen changed");
                if(uiWarmupFrames<12||System.nanoTime()-uiWarmupAt<750_000_000L)return;
                ui.releaseAndClose(client);uiWarmupComplete=true;startPublication(client);return;
            }
            // Transport shutdown must still save and exit during a vanilla world
            // transition, before the replacement player/world objects exist.
            if(output.failure()!=null)throw new IllegalStateException("HUD publication failed: "+output.failure());
            if(stopForClosedInput(client))return;
            if(!standalone)observeHiddenWindow(client);
            // Respawn/dimension travel can replace the vanilla client objects while
            // retaining the exact integrated server and persistent save.
            if(client.world==null||client.player==null)return;
            if(client.world!=world||client.player!=player){
                if(movement!=null)throw new IllegalStateException("Movement world/player changed; saved position retained for restart");
                if(ui!=null)ui.releaseAndClose(client);gate.releaseAll();world=client.world;player=client.player;
                if(!standalone)ui=new HudVanillaUiAdapter(client,true);
            }
            if(movement!=null)movement.afterTick(client,System.nanoTime());
            // Admit once on the client thread, before click dispatch. Projection,
            // player visibility and interaction use this same native observation.
            if(aimReader!=null&&!stopping){
                if(aimReader.failure()!=null)throw new IllegalStateException("Native aim: "+aimReader.failure());
                if(worldBlocksMode){admittedNativeView=aimReader.worldSample();
                    if(admittedNativeView!=null){
                        GameplayPerspective.select(client,GameplayPerspective.acknowledged(admittedNativeView.perspective()));
                        if(admittedNativeView.schema()==3){nativePerspectiveObserved=true;lastAcknowledgedPerspective=admittedNativeView.perspective();}
                    }
                    blocks.aim(admittedNativeView==null?null:admittedNativeView.aim());
                }else blocks.aim(aimReader.current());
            }
            if(!standalone)inputTick(client);
            if(blocksFixture!=null&&!stopping)blocksFixture.tick(client);
            if(terrainFixture!=null&&!stopping)terrainFixture.tick(client);
            if(chatFixture!=null&&!stopping)chatFixture.tick(client);
            if(flightFixture!=null&&!stopping)flightFixture.tick(client);
            if(playerFixture!=null&&!stopping)playerFixture.tick(client);if(handsFixture!=null&&!stopping)handsFixture.tick(client);if(worldBlocksFixture!=null&&!stopping)worldBlocksFixture.tick(client);if(shapesFixture!=null&&!stopping)shapesFixture.tick(client);if(depthFixture!=null&&!stopping)depthFixture.tick(client);if(connectedFixture!=null&&!stopping)connectedFixture.tick(client);if(shapeWalkingFixture!=null&&!stopping)shapeWalkingFixture.tick(client);
            if(blocks!=null&&!stopping)blocks.tick(client,!movement.terrainTransition()&&(standalone||input!=null&&input.connected()&&input.hostState()==1));
            if(movementFixture!=null&&!stopping)movementFixture.tick(client);
            if(fixture!=null&&output.isReady()&&output.publishedFrames()>0&&!stopping)fixture.tick(client);
        }catch(Exception e){requestStop(client,"failure",e.toString());}
    }

    private void startPublication(MinecraftClient client)throws IOException{
        output=new HudStreamProducer(root,directory,identity,save.saveName(),true,standalone?0:1);output.start();
        var notice=evidence(client);notice.addProperty("ready",true);
        Files.writeString(directory.getParent().resolve("gameplay-ready.json"),notice.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
        LOG.info("GAMEPLAY_READY run={} world={} newWorld={} standalone={}",identity.run(),save.id(),save.newlyCreated(),standalone);
    }

    private void inputTick(MinecraftClient client){
        if(input==null&&output.publishedFrames()>0){
            input=new HudInputReader(new HudInputProtocol.Identity(identity.run(),output.producerPid(),output.producerStart(),identity.targetPid(),identity.targetStart(),identity.expiresUtcMs()),movementMode,true,blocksMode,chatMode);
            input.start();
        }
        if(input==null||stopForClosedInput(client))return;
        if(input.connected())inputConnectedSeen=true;
        if(input.connected()&&input.hostState()==1)inputArmedSeen=true;
        ui.synchronizeScreen(client);
        long now=System.nanoTime(),utc=System.currentTimeMillis();
        if(movement!=null)movement.authority(client,now,input.connected()&&input.hostState()==1);
        if(input.connected()&&input.hostState()==1){
            if(!hiddenClientUnfocused(client))throw new IllegalStateException("Gameplay guest window is not hidden and unfocused");
            if(utc-input.heartbeat()>250||now-input.observedAt()>250_000_000L)throw new IllegalStateException("Gameplay host input stale");
            if(now-output.lastPublishedAt()>250_000_000L)throw new IllegalStateException("Gameplay HUD publication stale");
            for(int i=0;i<64;i++){
                var event=input.poll();if(event==null)break;gate.apply(event,System.currentTimeMillis());
                if(chatMode&&event.kind()>=9){if(blocks!=null)blocks.suspend(client);if(movement!=null)movement.suspend(client);ui.apply(client,event);}
                else if(blocks!=null&&(event.kind()==7||event.kind()==8))blocks.event(client,event);
                else if(movement!=null&&event.kind()<=2&&GameplayMovementKeys.movement(event.code())){
                    if(flightMode||HudMovementKeys.movement(event.code()))movement.event(client,event,System.nanoTime());
                }
                else{if(event.kind()<=2&&(event.code()==0x45||event.code()==0x1b||chatMode&&(event.code()==0x54||event.code()==0xbf))){if(blocks!=null)blocks.suspend(client);if(movement!=null)movement.suspend(client);}ui.apply(client,event);}
                inputEvents++;
            }
        }
        input.acknowledge(new HudInputReader.Acknowledgement(gate.sequence(),System.currentTimeMillis(),1,
                HudVanillaUiAdapter.screenKind(client.currentScreen),client.player.getInventory().selectedSlot));
    }

    private boolean stopForClosedInput(MinecraftClient client){
        if(input==null||!input.isClosed())return false;
        String reason=input.reason();requestStop(client,reason==null?"input_closed":reason,
                Set.of("host_closed","guest_closed").contains(reason==null?"":reason)?null:reason);
        return true;
    }

    private void configure(MinecraftClient client){
        oldPerspective=client.options.getPerspective();if(worldBlocksMode&&!standalone)GameplayPerspective.select(client,net.minecraft.client.option.Perspective.FIRST_PERSON);
        oldPause=client.options.pauseOnLostFocus;oldHidden=client.options.hudHidden;oldGraphics=client.options.getGraphicsMode().getValue();
        oldFullscreen=client.options.getFullscreen().getValue();oldScale=client.options.getGuiScale().getValue();
        oldFps=client.options.getMaxFps().getValue();oldVsync=client.options.getEnableVsync().getValue();
        oldWidth=client.getWindow().getWidth();oldHeight=client.getWindow().getHeight();
        client.options.pauseOnLostFocus=false;client.options.hudHidden=false;client.options.getGraphicsMode().setValue(GraphicsMode.FAST);
        client.options.getFullscreen().setValue(false);client.getWindow().setWindowedSize(layout.width(),layout.height());
        client.options.getGuiScale().setValue(layout.guiScale());client.options.getEnableVsync().setValue(false);
        client.options.getMaxFps().setValue(60);client.onResolutionChanged();
    }
    private void restore(MinecraftClient client){
        if(oldPause==null)return;
        restoreOwnedWindow(client);
        GameplayPerspective.select(client,oldPerspective);client.options.pauseOnLostFocus=oldPause;client.options.hudHidden=oldHidden;client.options.getGraphicsMode().setValue(oldGraphics);
        client.options.getGuiScale().setValue(oldScale);client.options.getEnableVsync().setValue(oldVsync);client.options.getMaxFps().setValue(oldFps);
        if(!standalone&&windowHideVerified){
            // Restore saved options without a native resize/fullscreen transition
            // that would show the owned guest again immediately before exit.
            client.options.getFullscreen().setValue(oldFullscreen);
            if(client.getWindow().isFullscreen())client.getWindow().toggleFullscreen();
        }else{client.getWindow().setWindowedSize(oldWidth,oldHeight);client.options.getFullscreen().setValue(oldFullscreen);client.onResolutionChanged();}
        oldPause=null;
    }

    private static boolean windowAttribute(long handle,int attribute){
        int value=GLFW.glfwGetWindowAttrib(handle,attribute);
        if(value!=GLFW.GLFW_TRUE&&value!=GLFW.GLFW_FALSE)throw new IllegalStateException("Invalid GLFW window attribute");
        return value==GLFW.GLFW_TRUE;
    }
    private void hideOwnedWindow(MinecraftClient client){
        RenderSystem.assertOnRenderThread();long handle=client.getWindow().getHandle();
        if(standalone||save==null||client.getServer()!=server||!client.isIntegratedServerRunning()
                ||client.getWindow().isFullscreen()||GLFW.glfwGetWindowMonitor(handle)!=0)
            throw new IllegalStateException("Hiding requires the owned windowed gameplay guest");
        hiddenWindow=handle;oldWindowVisible=windowAttribute(handle,GLFW.GLFW_VISIBLE);oldFocusOnShow=windowAttribute(handle,GLFW.GLFW_FOCUS_ON_SHOW);
        clientFocusedBeforeHide=client.isWindowFocused();windowHideRequested=true;GLFW.glfwHideWindow(handle);
        windowHideVerified=!windowAttribute(handle,GLFW.GLFW_VISIBLE);
        if(!windowHideVerified)throw new IllegalStateException("GLFW did not hide the gameplay guest");
        observeHiddenWindow(client);
        LOG.info("GAMEPLAY_WINDOW_HIDDEN run={} window={}",identity.run(),Long.toUnsignedString(hiddenWindow));
    }
    private void observeHiddenWindow(MinecraftClient client){
        RenderSystem.assertOnRenderThread();long handle=client.getWindow().getHandle();
        if(!windowHideVerified||hiddenWindow!=handle||client.getWindow().isFullscreen()||GLFW.glfwGetWindowMonitor(handle)!=0
                ||windowAttribute(handle,GLFW.GLFW_VISIBLE))throw new IllegalStateException("Hidden gameplay window identity/visibility changed");
        if(client.getFramebuffer().textureWidth!=layout.width()||client.getFramebuffer().textureHeight!=layout.height()
                ||client.getWindow().getScaleFactor()!=layout.guiScale())throw new IllegalStateException("Hidden gameplay framebuffer/GUI size changed");
    }
    private boolean hiddenClientUnfocused(MinecraftClient client){
        // As in HudStreamLab, the actual Minecraft WM_KILLFOCUS callback is the
        // authority; bundled GLFW's raw focus attribute uses the caller's queue.
        return windowHideVerified&&!windowAttribute(hiddenWindow,GLFW.GLFW_VISIBLE)&&!client.isWindowFocused()
                &&(!clientFocusedBeforeHide||focusLossCallbacksAfterHide>0);
    }
    private void restoreOwnedWindow(MinecraftClient client){
        if(oldWindowVisible==null||windowCleanup!=null)return;
        RenderSystem.assertOnRenderThread();
        windowCleanup=HudWindowCleanup.finish(new HudWindowCleanup.Window(){
            public long handle(){return client.getWindow().getHandle();}
            public boolean windowed(){return !client.getWindow().isFullscreen()&&GLFW.glfwGetWindowMonitor(hiddenWindow)==0;}
            public boolean visible(){return windowAttribute(hiddenWindow,GLFW.GLFW_VISIBLE);}
            public boolean focusOnShow(){return windowAttribute(hiddenWindow,GLFW.GLFW_FOCUS_ON_SHOW);}
            public void focusOnShow(boolean value){GLFW.glfwSetWindowAttrib(hiddenWindow,GLFW.GLFW_FOCUS_ON_SHOW,value?GLFW.GLFW_TRUE:GLFW.GLFW_FALSE);}
            public void show(){GLFW.glfwShowWindow(hiddenWindow);}
            public void hide(){GLFW.glfwHideWindow(hiddenWindow);}
        },hiddenWindow,oldWindowVisible,oldFocusOnShow,windowHideVerified);
        if(!windowCleanup.get("cleanup_succeeded").getAsBoolean()&&failure==null)failure="Owned gameplay window cleanup failed";
    }

    public static void beforeGuiClear(){
        var s=active;var client=MinecraftClient.getInstance();if(s==null||(s.standalone&&!s.handsMode)||!s.owns(client))return;
        // The hand pass already cleared the world colour; keep its actual pixels
        // beneath the normal HUD. UI-only profiles still begin here.
        if(s.handsMode&&s.frameTransparent)return;
        s.beginTransparentFrame(client);
    }
    public static void beforeHandClear(){
        var s=active;var client=MinecraftClient.getInstance();
        if(s==null||!s.handsMode||!s.owns(client)||client.currentScreen!=null||client.getOverlay()!=null||!client.options.getPerspective().isFirstPerson())return;
        if(!s.frameTransparent)s.beginTransparentFrame(client);
    }
    public static void handRenderStarted(){var s=active;if(s!=null&&s.handsMode&&s.frameTransparent&&s.owns(MinecraftClient.getInstance()))s.handRenderStarts++;}
    public static boolean worldBlocksEnabled(){var s=active;return s!=null&&s.worldBlocksMode&&s.owns(MinecraftClient.getInstance());}
    public record WorldFrame(GameplayWorldRenderer.View view,java.util.Map<net.minecraft.util.math.BlockPos,net.minecraft.block.BlockState> blocks,net.minecraft.util.hit.BlockHitResult hover,dev.minecome.terrain.GroundSurface surface,long cameraUtcMs){}
    public static WorldFrame worldBlocksFrame(){
        var s=active;if(!worldBlocksEnabled()||s.blocks==null)return null;
        GameplayWorldRenderer.View view;GameplayBlocks.Aim ray;
        if(s.playerFixture!=null){view=s.playerFixture.view();ray=s.playerFixture.renderAim();}
        else if(s.depthFixture!=null){view=s.depthFixture.view();ray=s.depthFixture.renderAim();}
        else if(s.connectedFixture!=null){view=s.connectedFixture.view();ray=s.connectedFixture.renderAim();}
        else if(s.shapeWalkingFixture!=null){view=s.shapeWalkingFixture.view();ray=s.shapeWalkingFixture.renderAim();}
        else if(s.shapesFixture!=null){view=s.shapesFixture.view();ray=s.shapesFixture.renderAim();}
        else if(s.worldBlocksFixture!=null){view=s.worldBlocksFixture.view();ray=s.worldBlocksFixture.renderAim();}
        else{var sample=s.admittedNativeView;if(sample==null||!sample.fresh()||s.aimReader==null||s.aimReader.failure()!=null)return null;view=sample.view();ray=sample.aim();}
        // A valid rendering view does not require a hover ray. Fixtures and
        // ordinary denied/missed targets deliberately omit the outline ray.
        if(view==null)return null;
        var client=MinecraftClient.getInstance();
        return new WorldFrame(view,s.blocks.ownedBlockStates(client),s.blocks.hoveredBlock(client,ray),s.depthFixture!=null?s.depthFixture.surface():s.movement.surface(),s.standalone?0:ray.capturedUtcMs());
    }
    public static void beforeWorldClear(){var s=active;if(worldBlocksEnabled()&&!s.frameTransparent)s.beginTransparentFrame(MinecraftClient.getInstance());}
    public static void worldRenderCompleted(GameplayWorldRenderer.Result result){var s=active;if(worldBlocksEnabled()&&s.frameTransparent){s.playerFrameRendered=result.playerRendered();if(s.playerFrameRendered)s.playerRenderFrames++;s.renderedWorldBlocks=result.blocks();s.outlinedBlock=result.outlined();s.renderedTerrainOccluders=result.terrainOccluders();if(result.blocks()>0)s.worldBlockFrames++;if(s.outlinedBlock!=null)s.worldOutlineFrames++;if(result.terrainOccluders()>0)s.terrainDepthFrames++;}}
    public static void preserveWorldLayers(WorldFrame frame){
        var s=active;if(!worldBlocksEnabled()||!s.frameTransparent)return;
        // Snapshot the exact view submitted above, never a newer camera-reader tick.
        s.frameWorldCamera=frame==null?null:worldCamera(frame);
        s.worldLayers.capture(MinecraftClient.getInstance().getFramebuffer(),frame!=null);
    }
    private static JsonObject worldCamera(WorldFrame frame){
        var view=frame.view();var surface=frame.surface();var origin=view.origin();
        var result=new JsonObject();result.addProperty("utc_ms",frame.cameraUtcMs());
        result.add("origin",vector(origin.x+surface.centerX(),surface.centerY()-origin.z,origin.y-64+surface.centerZ()));
        result.add("forward",vector(view.forward().x,-view.forward().z,view.forward().y));
        result.add("up",vector(view.up().x,-view.up().z,view.up().y));
        result.addProperty("vertical_fov",view.verticalFovRadians());result.addProperty("near",.05);result.addProperty("far",512);
        return result;
    }
    private static JsonObject vector(double x,double y,double z){var value=new JsonObject();value.addProperty("x",x);value.addProperty("y",y);value.addProperty("z",z);return value;}
    private boolean suppressWorldPixels(){return renderedWorldBlocks==0&&!playerFrameRendered;}
    public static void handRenderCompleted(){var s=active;if(s!=null&&s.handsMode&&s.frameTransparent&&s.owns(MinecraftClient.getInstance())){s.handFrameRendered=true;s.handRenderPasses++;}}
    private void beginTransparentFrame(MinecraftClient client){
        RenderSystem.assertOnRenderThread();
        if(frameTransparent){requestStop(client,"render_failure","Nested gameplay HUD frame");return;}
        priorBlend=new int[]{GL11.glGetInteger(GL14.GL_BLEND_SRC_RGB),GL11.glGetInteger(GL14.GL_BLEND_DST_RGB),GL11.glGetInteger(GL14.GL_BLEND_SRC_ALPHA),GL11.glGetInteger(GL14.GL_BLEND_DST_ALPHA)};
        frameTransparent=true;handFrameRendered=false;playerFrameRendered=false;renderedWorldBlocks=0;renderedTerrainOccluders=0;outlinedBlock=null;
        frameWorldCamera=null;worldLayers.beginFrame();
        float[] color=new float[4];GL11.glGetFloatv(GL11.GL_COLOR_CLEAR_VALUE,color);
        var mask=org.lwjgl.BufferUtils.createByteBuffer(4);GL11.glGetBooleanv(GL11.GL_COLOR_WRITEMASK,mask);
        boolean scissor=GL11.glIsEnabled(GL11.GL_SCISSOR_TEST);int[] box=new int[4];GL11.glGetIntegerv(GL11.GL_SCISSOR_BOX,box);
        try{RenderSystem.disableScissor();RenderSystem.colorMask(true,true,true,true);RenderSystem.clearColor(0,0,0,0);RenderSystem.clear(GL11.GL_COLOR_BUFFER_BIT,MinecraftClient.IS_SYSTEM_MAC);}
        finally{RenderSystem.clearColor(color[0],color[1],color[2],color[3]);RenderSystem.colorMask(mask.get(0)!=0,mask.get(1)!=0,mask.get(2)!=0,mask.get(3)!=0);if(scissor)RenderSystem.enableScissor(box[0],box[1],box[2],box[3]);}
    }
    public static void afterRender(){
        var s=active;if(s==null)return;var client=MinecraftClient.getInstance();
        try{if(s.owns(client)&&(s.standalone&&!s.handsMode||s.frameTransparent)){
            if(s.uiWarmupAt!=0&&!s.uiWarmupComplete)s.uiWarmupFrames++;
            s.capture(client);
        }}
        catch(Exception e){s.requestStop(client,"render_failure",e.toString());}
        finally{s.restoreBlend();}
    }
    private void restoreBlend(){frameTransparent=false;handFrameRendered=false;playerFrameRendered=false;renderedWorldBlocks=0;renderedTerrainOccluders=0;outlinedBlock=null;if(priorBlend!=null){RenderSystem.blendFuncSeparate(priorBlend[0],priorBlend[1],priorBlend[2],priorBlend[3]);priorBlend=null;}}
    private void capture(MinecraftClient client){
        readback.poll(frame->{
            if(frame.id()<=lastReadbackId)return;lastReadbackId=frame.id();if(stopping||output==null)return;
            var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();
            if(playerFixture!=null)playerFixture.captured(frame);if(handsFixture!=null)handsFixture.captured(frame);if(worldBlocksFixture!=null)worldBlocksFixture.captured(frame);if(shapesFixture!=null)shapesFixture.captured(frame);if(depthFixture!=null)depthFixture.captured(frame);if(connectedFixture!=null)connectedFixture.captured(frame);
            output.offer(new HudStreamProducer.Frame(frame.width(),frame.height(),frame.layersBottomUp()==null?frame.bottomUp():null,meta.get("captured_utc_ms").getAsLong(),meta.get("selected_slot").getAsInt(),meta.get("screen").getAsInt(),frame.metadata(),frame.layersBottomUp()));
        });
        long now=System.nanoTime();if(output==null||!output.isReady()||client.getOverlay()!=null||now-lastCaptureAt<50_000_000L)return;
        boolean inventory=HudVanillaUiAdapter.inventory(client.currentScreen);
        var meta=new JsonObject();meta.addProperty("state",inventory?"inventory":HudVanillaUiAdapter.chat(client.currentScreen)?"chat":client.currentScreen==null?"hotbar":"screen");
        meta.addProperty("selected_slot",client.player.getInventory().selectedSlot);meta.addProperty("screen",client.currentScreen==null?0:1);
        meta.addProperty("screen_kind",client.currentScreen==null?"none":client.currentScreen.getClass().getSimpleName());
        meta.addProperty("captured_utc_ms",System.currentTimeMillis());meta.addProperty("world_id",save.id().toString());
        meta.addProperty("gameplay",true);meta.addProperty("no_world_pixels",(!standalone||handsMode)&&suppressWorldPixels());
        if(!standalone||handsMode)meta.addProperty("hand_pixels",handsMode&&handFrameRendered);
        if(handsMode)meta.addProperty("hand_pass_rendered",handFrameRendered);if(worldBlocksMode){
            if(worldLayers.framebuffer()==null)return;
            meta.addProperty("player_pixels",playerFrameRendered);meta.addProperty("perspective",client.options.getPerspective().name());
            meta.addProperty("frame_format",2);if(frameWorldCamera!=null)meta.add("world_camera",frameWorldCamera.deepCopy());
            meta.addProperty("world_block_pixels",renderedWorldBlocks>0);meta.addProperty("rendered_world_blocks",renderedWorldBlocks);meta.addProperty("world_block_outline",outlinedBlock!=null);
            meta.addProperty("terrain_depth_occlusion",renderedTerrainOccluders>0);meta.addProperty("terrain_depth_boxes",renderedTerrainOccluders);
            if(outlinedBlock!=null){var position=new JsonObject();position.addProperty("x",outlinedBlock.getX());position.addProperty("y",outlinedBlock.getY());position.addProperty("z",outlinedBlock.getZ());meta.add("outline_position",position);}
        }if(worldBlocksFixture!=null){var stage=worldBlocksFixture.captureStage();if(stage!=null)meta.addProperty("world_blocks_fixture_stage",stage);}
        if(shapesFixture!=null){var stage=shapesFixture.captureStage();if(stage!=null)meta.addProperty("world_blocks_fixture_stage",stage);}
        if(connectedFixture!=null){var stage=connectedFixture.captureStage();if(stage!=null)meta.addProperty("world_blocks_fixture_stage",stage);}
        if(depthFixture!=null){var stage=depthFixture.captureStage();if(stage!=null)meta.addProperty("world_blocks_fixture_stage",stage);}
        if(playerFixture!=null){var stage=playerFixture.captureStage();if(stage!=null){meta.addProperty("player_fixture_stage",stage);meta.add("player_fixture_motion",playerFixture.captureState());}}
        if(handsFixture!=null){var stage=handsFixture.captureStage();if(stage!=null)meta.addProperty("hands_fixture_stage",stage);}
        meta.addProperty("health_client",client.player.getHealth());meta.addProperty("food_client",client.player.getHungerManager().getFoodLevel());
        if(readback.capture(client.getFramebuffer(),worldBlocksMode?worldLayers.framebuffer():null,++captureId,meta.toString())){lastCaptureAt=now;if(handFrameRendered)handCapturedFrames++;}
    }

    private JsonObject evidence(MinecraftClient client){
        var e=new JsonObject();e.addProperty("schema",1);e.addProperty("kind","minecome_gameplay_session_v1");e.addProperty("run",identity.run());
        e.addProperty("standalone",standalone);e.addProperty("persistent_world",true);e.addProperty("save",GameplayWorld.SAVE_NAME);
        if(save!=null){e.addProperty("world_id",save.id().toString());e.addProperty("new_world",save.newlyCreated());}
        e.addProperty("input_events_applied",inputEvents);e.addProperty("stop_reason",stopReason);e.addProperty("failure",failure);
        e.addProperty("input_connected",inputConnectedSeen);e.addProperty("input_armed_seen",inputArmedSeen);
        e.addProperty("active_ms",readyAt==0?0:(System.nanoTime()-readyAt)/1_000_000);e.addProperty("bootstrap_ground","vanilla_superflat");
        JsonObject motion=movement==null?null:movement.evidence(client);
        boolean attached=motion!=null&&motion.get("ready").getAsBoolean();
        e.addProperty("terrain_collision_attached",attached);
        e.addProperty("kcd_terrain_imported",attached&&!standalone);e.addProperty("kcd_movement_connected",attached&&!standalone&&inputArmedSeen);e.addProperty("host_command_typing_verified",false);
        if(motion!=null)e.add("movement",motion);
        if(blocks!=null)e.add("blocks",blocks.evidence(client));
        e.addProperty("blocks_enabled",blocksMode);
        e.addProperty("chat_enabled",chatMode);
        e.addProperty("flight_enabled",flightMode);
        e.addProperty("world_blocks_enabled",worldBlocksMode);e.addProperty("world_block_render_frames",worldBlockFrames);e.addProperty("world_outline_render_frames",worldOutlineFrames);e.addProperty("hands_enabled",handsMode);e.addProperty("hand_render_starts",handRenderStarts);e.addProperty("hand_render_passes",handRenderPasses);e.addProperty("hand_captured_frames",handCapturedFrames);
        e.addProperty("player_render_frames",playerRenderFrames);e.addProperty("native_perspective_connected",nativePerspectiveObserved);
        e.addProperty("native_perspective_requested",desiredPerspective);if(nativePerspectiveObserved)e.addProperty("native_perspective_last_acknowledged",lastAcknowledgedPerspective);
        e.addProperty("inventory_prepared_before_input",uiWarmupComplete);e.addProperty("inventory_preparation_frames",uiWarmupFrames);
        if(worldBlocksMode)e.addProperty("terrain_depth_render_frames",terrainDepthFrames);
        if(ui!=null&&chatMode)e.add("chat_input",ui.chatDiagnostics());
        e.addProperty("normal_shutdown_requested",stopping);e.addProperty("controls_released",gate.heldKeyCount()==0&&gate.heldButtonCount()==0);
        e.addProperty("producer_finished",output!=null&&output.isFinished());e.addProperty("producer_failure",output==null?null:output.failure());
        if(!standalone){
            e.addProperty("owned_window_hidden",windowHideVerified);e.addProperty("focus_loss_callbacks_after_hide",focusLossCallbacksAfterHide);
            e.addProperty("desktop_swaps_skipped",desktopSwapsSkipped);
            if(windowCleanup!=null)e.add("window_cleanup",windowCleanup.deepCopy());
        }
        if(input!=null){e.add("input",input.diagnostics());e.addProperty("input_cleanup_complete",input.cleanupComplete());}
        if(fixtureResult!=null)e.add("fixture",fixtureResult.deepCopy());e.add("capture",readback.diagnostics());return e;
    }
    private void requestStop(MinecraftClient client,String reason,String problem){
        if(stopping)return;stopReason=reason;failure=problem;
        // End the host pose lease before draining asynchronous collision/input
        // cleanup. The final receipt can legitimately take longer than the lease.
        try{
            var notice=new JsonObject();notice.addProperty("schema",1);notice.addProperty("kind","minecome_gameplay_stopping_v1");
            notice.addProperty("run",identity.run());notice.addProperty("reason",reason);
            Path temporary=directory.getParent().resolve("gameplay-stopping.tmp");
            Files.writeString(temporary,notice.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
            Files.move(temporary,directory.getParent().resolve("gameplay-stopping.json"),java.nio.file.StandardCopyOption.ATOMIC_MOVE);
        }catch(Exception e){if(failure==null)failure="Stop notice: "+e;}
        try{if(playerFixture!=null)playerFixture.close();if(connectedFixture!=null)connectedFixture.close();if(shapeWalkingFixture!=null)shapeWalkingFixture.close();if(depthFixture!=null)depthFixture.close();if(shapesFixture!=null)shapesFixture.close();if(worldBlocksFixture!=null)worldBlocksFixture.close();if(handsFixture!=null)handsFixture.close();if(flightFixture!=null)flightFixture.close();if(chatFixture!=null)chatFixture.close();if(terrainFixture!=null)terrainFixture.close();if(blocksFixture!=null)blocksFixture.close();if(aimReader!=null)aimReader.close();if(blocks!=null)blocks.close(client);}catch(Exception e){if(failure==null)failure=e.toString();}
        try{if(movementFixture!=null)movementFixture.close();if(movement!=null){if(failure==null)movement.close(client);else movement.abort(client,failure);}}catch(Exception e){if(failure==null)failure=e.toString();}
        try{if(ui!=null)ui.releaseAndClose(client);}catch(Exception e){if(failure==null)failure=e.toString();}
        gate.releaseAll();
        if(input!=null){
            int selected=client.player==null?0:client.player.getInventory().selectedSlot;
            input.acknowledge(new HudInputReader.Acknowledgement(gate.sequence(),System.currentTimeMillis(),2,0,selected));input.close();
        }
        stopping=true;stopAt=System.nanoTime();
        LOG.info("GAMEPLAY_STOP run={} reason={} failure={}",identity.run(),reason,failure);
    }
    private void finishStop(MinecraftClient client){
        if(shutdownRequested)return;
        if(!writerFinished){
            if(blocks!=null&&!blocks.cleanupComplete()&&System.nanoTime()-stopAt<2_000_000_000L)return;
            if(blocks!=null&&!blocks.cleanupComplete()&&failure==null)failure="Block ledger cleanup incomplete";
            if(movement!=null&&!movement.cleanupComplete()&&System.nanoTime()-stopAt<2_000_000_000L)return;
            if(movement!=null&&!movement.cleanupComplete()&&failure==null)failure="Movement cleanup incomplete";
            if(input!=null&&!input.isFinished()&&System.nanoTime()-stopAt<2_000_000_000L)return;
            if(input!=null&&!input.cleanupComplete()&&failure==null)failure="Input cleanup incomplete";
            try{restoreOwnedWindow(client);}catch(RuntimeException e){if(failure==null)failure="Window cleanup: "+e;}
            var proof=evidence(client);
            try{Files.writeString(directory.getParent().resolve("gameplay-session.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);sessionReportWritten=true;}
            catch(IOException e){if(failure==null)failure="Session receipt: "+e;proof.addProperty("failure",failure);LOG.error("GAMEPLAY_RECEIPT_FAILED",e);}
            writerFinished=true;writerAt=System.nanoTime();
            try{if(output!=null)output.finish(failure==null?"stopped":"failed",proof);}
            catch(RuntimeException e){if(failure==null)failure="Producer finalization: "+e;LOG.error("GAMEPLAY_FINALIZATION_FAILED",e);}
        }
        if(output!=null&&!output.isFinished()&&System.nanoTime()-writerAt<3_000_000_000L)return;
        if(output!=null&&output.failure()!=null&&failure==null)failure="Producer finalization: "+output.failure();
        if(output!=null&&!output.isFinished()&&failure==null)failure="Producer shutdown deadline";
        if(sessionReportWritten){
            try{Files.writeString(directory.getParent().resolve("gameplay-session.json"),evidence(client).toString(),StandardCharsets.UTF_8,StandardOpenOption.TRUNCATE_EXISTING);}
            catch(IOException e){if(failure==null)failure="Final session receipt: "+e;LOG.error("GAMEPLAY_FINAL_RECEIPT_FAILED",e);}
        }
        shutdownRequested=true;
        try{restoreBlend();restore(client);}finally{client.scheduleStop();}
    }
    private void onClientStopping(MinecraftClient client){
        if(!stopping)requestStop(client,"client_closed",null);
        try{
            try{restoreBlend();try{readback.close();}finally{worldLayers.close();}restore(client);}
            catch(RuntimeException e){if(failure==null)failure="Client cleanup: "+e;LOG.error("GAMEPLAY_CLIENT_CLEANUP_FAILED",e);}
            // An external window close has no further client ticks. Drain the
            // already-requested shutdown here before recording its final state.
            // No UI/input dispatch occurs after these bounded waits begin.
            if(!writerFinished){
                if(blocks!=null){
                    awaitShutdown(blocks::cleanupComplete,2_000_000_000L);
                    if(!blocks.cleanupComplete()&&failure==null)failure="Block ledger cleanup incomplete";
                }
                if(movement!=null){
                    awaitShutdown(movement::cleanupComplete,2_000_000_000L);
                    if(!movement.cleanupComplete()&&failure==null)failure="Movement cleanup incomplete";
                }
                if(input!=null){
                    awaitShutdown(input::isFinished,2_000_000_000L);
                    if(!input.cleanupComplete()&&failure==null)failure="Input cleanup incomplete";
                }
                writerFinished=true;writerAt=System.nanoTime();
                try{if(output!=null)output.finish(failure==null?"stopped":"failed",evidence(client));}
                catch(RuntimeException e){if(failure==null)failure="Producer finalization: "+e;LOG.error("GAMEPLAY_FINALIZATION_FAILED",e);}
            }
            if(output!=null){
                awaitShutdown(output::isFinished,3_000_000_000L);
                if(output.failure()!=null&&failure==null)failure="Producer finalization: "+output.failure();
                if(!output.isFinished()&&failure==null)failure="Producer shutdown deadline";
            }
            try{
                Files.writeString(directory.getParent().resolve("gameplay-session.json"),evidence(client).toString(),StandardCharsets.UTF_8,
                        sessionReportWritten?StandardOpenOption.TRUNCATE_EXISTING:StandardOpenOption.CREATE_NEW);
                sessionReportWritten=true;
            }catch(IOException e){if(failure==null)failure="Final session receipt: "+e;LOG.error("GAMEPLAY_FINAL_RECEIPT_FAILED",e);}
        }finally{active=null;}
    }
    private static void awaitShutdown(BooleanSupplier finished,long timeoutNanos){
        long began=System.nanoTime();
        while(!finished.getAsBoolean()&&System.nanoTime()-began<timeoutNanos){
            try{Thread.sleep(10);}
            catch(InterruptedException e){Thread.currentThread().interrupt();return;}
        }
    }
}
