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

/** Isolated genuine vanilla HUD/screens capture foundation, never a host compositor. */
public final class HudExportLab {
    private static final Logger LOG=LoggerFactory.getLogger("MineComeHud");
    private static volatile HudExportLab active;
    // Mixin hooks may load this class before/without opt-in. Registry access stays lazy.
    private static final class Fixture {
        static final Item[] ITEMS={Items.STONE,Items.DIRT,Items.COBBLESTONE,Items.OAK_PLANKS,Items.STICK,Items.APPLE,Items.TORCH,Items.DIAMOND,Items.IRON_PICKAXE};
        static final int[] COUNTS={64,32,16,8,3,2,12,1,1};
    }
    private record Slot(int slot,String item,int count){}
    private record Observation(Object world,long at,int selected,List<Slot> slots){}
    private record ServerOwner(Object server,UUID player){}
    private final String run=UUID.randomUUID().toString().replace("-","");
    private final String save="MineCome-Hud-"+UUID.randomUUID();
    private final long initializedAt=System.nanoTime();
    private final AtomicReference<Observation> server=new AtomicReference<>();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicReference<ServerOwner> serverOwner=new AtomicReference<>();
    private final HudReadback readback=new HudReadback();
    private final Path outputDirectory;
    private HudOutput output;
    private Object world,player,serverIdentity;
    private UUID playerId;
    private long worldAt,stateAt,terminalAt;
    private int stage=1,pendingId,completed;
    private boolean started,given,terminal,frameTransparent;
    private volatile boolean stopping;
    private Boolean oldPause,oldHidden;
    private GraphicsMode oldGraphics;
    private int[] priorBlend;
    private HudExportLab(Path outputDirectory){this.outputDirectory=outputDirectory;}
    public static void initialize(){
        if(!Boolean.getBoolean("minecome.hudExportLab"))return;
        if(active!=null)throw new IllegalStateException("HUD lab already active");
        String path=System.getProperty("minecome.hudExportDirectory");
        if(path==null || path.isBlank())throw new IllegalArgumentException("minecome.hudExportDirectory is required (NEW directory)");
        var lab=new HudExportLab(Path.of(path));active=lab;
        ClientTickEvents.END_CLIENT_TICK.register(lab::tick);ServerTickEvents.END_SERVER_TICK.register(lab::observe);
        ClientLifecycleEvents.CLIENT_STOPPING.register(client->{
            lab.stopping=true;lab.restoreBlend();lab.readback.close();if(lab.output!=null)lab.output.close();
            if(lab.oldPause!=null)client.options.pauseOnLostFocus=lab.oldPause;
            if(lab.oldHidden!=null)client.options.hudHidden=lab.oldHidden;
            if(lab.oldGraphics!=null)client.options.getGraphicsMode().setValue(lab.oldGraphics);
            active=null;
        });
        LOG.info("HUD_EXPORT_LAB_INITIALIZED run={} output={} actualVanillaRenderPath=true worldPixels=false handPixels=false hostCompositingVerified=false",lab.run,path);
    }
    private boolean owned(MinecraftClient client){return !stopping && world!=null && client.world==world && client.player==player && client.getServer()==serverIdentity && client.isIntegratedServerRunning();}
    /** Exact owning world only: every default mode and unrelated world retains normal rendering. */
    public static boolean suppressWorld(){var lab=active;return lab!=null && lab.given && lab.owned(MinecraftClient.getInstance());}
    public static boolean transparentFrame(){var lab=active;return lab!=null && lab.frameTransparent && lab.owned(MinecraftClient.getInstance());}
    /** Called at GameRenderer.render's sole GUI depth-clear; world/hand passes have finished. */
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
    /** Captures the actual finished normal vanilla HUD/screens, never replays a private HUD method. */
    public static void afterRender(){
        var lab=active;if(lab==null)return;var client=MinecraftClient.getInstance();
        try {if(lab.frameTransparent && lab.owned(client))lab.capture(client);}
        catch(Exception e){lab.fail(client,"HUD readback: "+e.getMessage());}
        finally {lab.restoreBlend();}
    }
    private void restoreBlend(){
        frameTransparent=false;if(priorBlend!=null){RenderSystem.blendFuncSeparate(priorBlend[0],priorBlend[1],priorBlend[2],priorBlend[3]);priorBlend=null;}
    }
    private void capture(MinecraftClient client)throws Exception{
        RenderSystem.assertOnRenderThread();
        readback.poll(frame->{
            try {
                byte[] rgba=HudPixels.straightTopLeft(frame.bottomUp(),frame.width(),frame.height());
                output.offer(new HudOutput.Frame(frame.id(),frame.width(),frame.height(),rgba,frame.metadata()));
                completed=frame.id();pendingId=0;
                LOG.info("HUD_EXPORT_FRAME_COPIED run={} frame={} width={} height={} alphaMode=straight_rgba8 origin=top_left",run,frame.id(),frame.width(),frame.height());
            }catch(Exception e){throw new IllegalStateException(e);}
        });
        if(output==null || !output.isReady() || !given || pendingId!=0 || completed>=stage || stage>3 || terminal)return;
        if(client.getOverlay()!=null || (stage<=2 && client.currentScreen!=null) || System.nanoTime()-stateAt<1_000_000_000L)return;
        if(stage==3 && client.currentScreen==null)return;
        if(stage==3 && !(client.currentScreen instanceof InventoryScreen) && !(client.currentScreen instanceof CreativeInventoryScreen))
            throw new IllegalStateException("Third capture is not a genuine vanilla inventory screen");
        Observation observation=server.get();List<Slot> local=slots(client.player.getInventory());
        int selected=client.player.getInventory().selectedSlot;
        if(observation==null || System.nanoTime()-observation.at()>250_000_000L || observation.world()==null ||
                !observation.slots().equals(local) || observation.selected()!=selected || selected!=(stage==1?0:1))return;
        if(!matches(local))throw new IllegalStateException("Actual hotbar differs from bounded fixture inventory");
        JsonObject metadata=new JsonObject();metadata.addProperty("state",stage==1?"hotbar_slot0":stage==2?"hotbar_slot1":"inventory_screen");
        metadata.addProperty("selected_slot",selected);metadata.addProperty("screen_kind",client.currentScreen==null?"none":client.currentScreen.getClass().getSimpleName());
        metadata.addProperty("captured_utc_ms",System.currentTimeMillis());metadata.addProperty("client_server_inventory_confirmed",true);
        metadata.addProperty("no_world_pixels",true);metadata.addProperty("hand_pixels",false);metadata.addProperty("gui_scale",client.getWindow().getScaleFactor());
        metadata.add("client_slots",jsonSlots(local));metadata.add("server_slots",jsonSlots(observation.slots()));
        if(readback.capture(client.getFramebuffer(),stage,metadata.toString())){
            pendingId=stage;LOG.info("HUD_EXPORT_FRAME_QUEUED run={} frame={} state={} selected={} clientServerConfirmed=true",run,stage,metadata.get("state"),selected);
        }
    }
    private void tick(MinecraftClient client){
        if(stopping)return;long now=System.nanoTime();
        if(now-initializedAt>=120_000_000_000L){fail(client,"Global120s deadline");return;}
        if(!started && client.currentScreen!=null && client.getOverlay()==null){create(client);return;}
        if(!started || client.world==null || client.player==null || !client.isIntegratedServerRunning()){
            if(world!=null)fail(client,"Owned HUD world disconnected");return;
        }
        if(world==null){world=client.world;player=client.player;serverIdentity=client.getServer();playerId=client.player.getUuid();worldAt=now;serverOwner.set(new ServerOwner(serverIdentity,playerId));}
        if(!owned(client)){fail(client,"World/player/server identity changed");return;}
        if(now-worldAt>=30_000_000_000L){fail(client,"World30s deadline");return;}
        if(serverFailure.get()!=null){fail(client,serverFailure.get());return;}
        if(client.getOverlay()!=null)return;
        if(!given){
            if(client.currentScreen!=null)return;
            if(client.interactionManager==null || client.interactionManager.getCurrentGameMode()!=GameMode.CREATIVE){fail(client,"Fresh Creative inventory API unavailable");return;}
            for(int i=0;i<9;i++){var stack=new ItemStack(Fixture.ITEMS[i],Fixture.COUNTS[i]);client.player.getInventory().setStack(i,stack);client.interactionManager.clickCreativeStack(stack,36+i);}
            client.player.getInventory().selectedSlot=0;given=true;stateAt=now;
            Path project=client.runDirectory.toPath().toAbsolutePath().normalize().getParent().getParent();
            output=new HudOutput(project,outputDirectory,run,save);output.start();
            LOG.info("HUD_EXPORT_LAB_READY run={} save={} newWorld=true realCreativePackets=true capture=normal_main_target worldSuppressed=true handSuppressed=true",run,save);
        }
        if(output.failure()!=null){fail(client,"HUD output: "+output.failure().getMessage());return;}
        if(completed==stage && stage<3){
            stage++;stateAt=now;
            if(stage==2)client.player.getInventory().selectedSlot=1;
            else client.setScreen(new InventoryScreen(client.player));
        }
        if(completed==3 && !terminal){
            try {output.finish("passed");terminal=true;terminalAt=now;}catch(Exception e){fail(client,e.getMessage());return;}
        }
        if(terminal){
            if(!output.isFinished()){if(now-terminalAt>4_000_000_000L)fail(client,"HUD output finalization4s deadline");return;}
            if(output.failure()!=null){fail(client,"HUD output terminal failed: "+output.failure().getMessage());return;}
            LOG.info("HUD_EXPORT_LAB_PASS run={} save={} frames={} actualVanillaHud=true actualVanillaInventoryScreen=true clientServerInventoryConfirmed=true worldPixels=false alphaMode=straight_rgba8 hostCompositingVerified=false output={}",run,save,output.written(),outputDirectory);
            stopping=true;client.scheduleStop();
        }
    }
    private void create(MinecraftClient client){
        started=true;if(client.world!=null || client.isIntegratedServerRunning()){fail(client,"Refusing existing/open world");return;}
        oldPause=client.options.pauseOnLostFocus;client.options.pauseOnLostFocus=false;
        oldHidden=client.options.hudHidden;client.options.hudHidden=false;
        oldGraphics=client.options.getGraphicsMode().getValue();client.options.getGraphicsMode().setValue(GraphicsMode.FAST);
        if(Files.exists(client.runDirectory.toPath().resolve("saves").resolve(save))){fail(client,"Refusing existing HUD save");return;}
        GameRules rules=new GameRules();rules.get(GameRules.DO_MOB_SPAWNING).set(false,null);rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0,null);
        LevelInfo info=new LevelInfo(save,GameMode.CREATIVE,false,Difficulty.PEACEFUL,true,rules,DataConfiguration.SAFE_MODE);
        client.createIntegratedServerLoader().createAndStart(save,info,new GeneratorOptions(42,false,false),registries->registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder(),client.currentScreen);
    }
    private void observe(MinecraftServer source){
        var owner=serverOwner.get();if(stopping || owner==null)return;
        try {
            if(source!=owner.server() || !save.equals(source.getSaveProperties().getLevelName()))throw new IllegalStateException("HUD integrated server/save identity changed");
            var entity=source.getPlayerManager().getPlayer(owner.player());if(entity==null || entity.getWorld()!=source.getOverworld())throw new IllegalStateException("HUD server player identity changed");
            server.set(new Observation(entity.getWorld(),System.nanoTime(),entity.getInventory().selectedSlot,slots(entity.getInventory())));
        }catch(Exception e){serverFailure.set(e.getMessage());}
    }
    private static List<Slot> slots(net.minecraft.entity.player.PlayerInventory inventory){
        List<Slot> result=new ArrayList<>(9);for(int i=0;i<9;i++){var stack=inventory.getStack(i);result.add(new Slot(i,Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount()));}return List.copyOf(result);
    }
    private static boolean matches(List<Slot> slots){for(int i=0;i<9;i++)if(!slots.get(i).item().equals(Registries.ITEM.getId(Fixture.ITEMS[i]).toString()) || slots.get(i).count()!=Fixture.COUNTS[i])return false;return true;}
    private static JsonArray jsonSlots(List<Slot> slots){var values=new JsonArray();for(Slot slot:slots){var value=new JsonObject();value.addProperty("slot",slot.slot());value.addProperty("item",slot.item());value.addProperty("count",slot.count());values.add(value);}return values;}
    private void fail(MinecraftClient client,String reason){
        if(stopping)return;stopping=true;restoreBlend();if(output!=null)try{output.finish("failed");}catch(Exception ignored){}
        LOG.error("HUD_EXPORT_LAB_FAIL run={} save={} stage={} reason={}",run,save,stage,reason);client.scheduleStop();
    }
}
