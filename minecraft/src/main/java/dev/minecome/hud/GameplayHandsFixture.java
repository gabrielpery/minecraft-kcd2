package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.Hand;
import net.minecraft.util.math.Vec3d;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Real held-item render pixels from ordinary hotbar/UI actions in one isolated Minecraft session. */
public final class GameplayHandsFixture {
    private record State(long at,String mode,int selected,String first,String second,String held,Vec3d position){}
    private record Sample(String stage,HudReadback.Completed frame){}
    private static final List<String> STAGES=List.of("empty","stone","sword","swing","inventory","restored","empty_after");
    private final GameplayMovement movement;
    private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;
    private final Path directory;
    private final Consumer<JsonObject> completed;
    private final AtomicReference<State> observed=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>();
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(2);
    private final Map<String,JsonObject> images=new ConcurrentHashMap<>();
    private final Set<String> queued=new HashSet<>();
    private final List<String> commands=new ArrayList<>();
    private MinecraftServer server;
    private Object world,player;
    private UUID playerId;
    private HudVanillaUiAdapter ui;
    private long begun,stageAt,sequence,swingCalls;
    private int stage,stageTicks;
    private boolean finished;
    private volatile boolean closing,written;
    private volatile long viewWrites;
    private JsonObject result;

    public GameplayHandsFixture(String mode,GameplayMovement movement,GameplayWorld save,HudInputProtocol.Identity identity,
                                Path directory,Consumer<JsonObject> completed)throws IOException {
        if(!"hands".equals(mode)||!Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayHands")
                ||!Boolean.getBoolean("minecome.gameplayChat"))throw new IllegalArgumentException("Explicit standalone hands/chat fixture required");
        this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;this.directory=directory.toRealPath();
        save.verifyOwnership();if(!save.newlyCreated())throw new IOException("Hands fixture requires a new isolated save");
        if(Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-hands-fixture.json")))throw new IOException("Hands fixture output exists");
        var worker=new Thread(this::writeLoop,"MineComeGameplayHandsFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0||result!=null)return;try{requireOwner(c);movement.authority(c,System.nanoTime(),true);}catch(Exception e){complete(c,false,e.toString());}}
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(result!=null){movement.suspend(c);if(written||failure.get()!=null){if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}finished=true;completed.accept(result.deepCopy());}return;}
            if(failure.get()!=null)throw new IllegalStateException(failure.get());if(!movement.ready())return;
            if(begun==0)begin(c);requireOwner(c);long now=System.nanoTime();
            if(now-begun>35_000_000_000L||now-stageAt>6_000_000_000L)throw new IllegalStateException("Hands fixture deadline stage="+stage+", ticks="+stageTicks);
            observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;stageTicks++;
            if(!s.mode().equals("creative")||!c.interactionManager.getCurrentGameMode().getName().equals("creative"))throw new IllegalStateException("Hands fixture game mode changed");
            switch(stage){
                case 0 -> {if(s.selected()!=8||!s.held().equals("minecraft:air")||!c.player.getMainHandStack().isEmpty())return;if(images.containsKey("empty")){command(c,"item replace entity @s hotbar.0 with minecraft:stone");next(now);}}
                case 1 -> {if(s.at()<=stageAt||!s.first().equals("minecraft:stone")||!item(c,0).equals("minecraft:stone"))return;command(c,"item replace entity @s hotbar.1 with minecraft:diamond_sword");next(now);}
                case 2 -> {if(s.at()<=stageAt||!s.second().equals("minecraft:diamond_sword")||!item(c,1).equals("minecraft:diamond_sword"))return;key(c,'1');next(now);}
                case 3 -> {requireItem(c,s,"minecraft:stone",0);if(images.containsKey("stone")){key(c,'2');next(now);}}
                case 4 -> {requireItem(c,s,"minecraft:diamond_sword",1);if(images.containsKey("sword")){swing(c);next(now);}}
                case 5 -> {requireItem(c,s,"minecraft:diamond_sword",1);if(images.containsKey("swing")){key(c,'E');next(now);}else if(stageTicks%12==0)swing(c);}
                case 6 -> {if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Actual Creative inventory did not open");if(stageTicks>=12&&images.containsKey("inventory")){key(c,'E');next(now);}}
                case 7 -> {if(c.currentScreen!=null)throw new IllegalStateException("Inventory did not close");requireItem(c,s,"minecraft:diamond_sword",1);if(images.containsKey("restored")){key(c,'9');next(now);}}
                case 8 -> {requireItem(c,s,"minecraft:air",8);if(images.containsKey("empty_after")){validateImages();complete(c,true,null);}}
                default -> throw new IllegalStateException("Unknown hands stage");
            }
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||!c.isIntegratedServerRunning()||c.getServer()==null)throw new IllegalStateException("Hands fixture requires integrated client");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);begun=stageAt=System.nanoTime();key(c,'9');
    }
    /** Captured alongside the PBO bytes, never inferred later from a different UI state. */
    public String captureStage(){
        if(closing||finished||result!=null||begun==0)return null;
        String name=switch(stage){case 0->"empty";case 3->"stone";case 4->"sword";case 5->"swing";case 6->"inventory";case 7->"restored";case 8->"empty_after";default->null;};
        if(name==null||queued.contains(name)||images.containsKey(name))return null;
        var c=MinecraftClient.getInstance();
        if(stage==5)return c.player!=null&&c.player.handSwinging&&c.player.handSwingProgress>.1f&&c.player.handSwingProgress<.9f?name:null;
        return stageTicks>=12?name:null;
    }
    /** Transfer at most two already-completed PBO frames; PNG work stays off the render thread. */
    public void captured(HudReadback.Completed frame){
        if(closing||finished||result!=null)return;
        var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("hands_fixture_stage"))return;
        String name=meta.get("hands_fixture_stage").getAsString();if(!STAGES.contains(name)||!queued.add(name))return;
        if(!samples.offer(new Sample(name,frame)))failure.compareAndSet(null,"Hands image evidence queue full");
    }
    private void requireItem(MinecraftClient c,State s,String expected,int slot){
        if(c.player.getInventory().selectedSlot!=slot||!Registries.ITEM.getId(c.player.getMainHandStack().getItem()).toString().equals(expected))throw new IllegalStateException("Actual client held item differs at stage "+stage);
        // Vanilla sends selected-slot changes on its next tick. The client image
        // is already authoritative for rendering; server convergence is required
        // before a settled stage is eligible for capture.
        if(stageTicks>=12&&(s.selected()!=slot||!s.held().equals(expected)))throw new IllegalStateException("Server hotbar selection did not converge");
    }
    private String item(MinecraftClient c,int slot){return Registries.ITEM.getId(c.player.getInventory().getStack(slot).getItem()).toString();}
    private void swing(MinecraftClient c){
        // ClientPlayerEntity.swingHand(Hand) is vanilla's normal animation/packet
        // path. This scripted render fixture does not claim a native attack click.
        c.player.swingHand(Hand.MAIN_HAND);swingCalls++;
    }
    private void next(long now){stage++;stageTicks=0;stageAt=now;}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void command(MinecraftClient c,String command){
        movement.suspend(c);key(c,0xbf);if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Actual command editor did not open");
        command.codePoints().forEach(cp->ui.apply(c,event(9,cp)));
        if(!ui.chatText(c).equals("/"+command))throw new IllegalStateException("Actual command text differs");
        ui.apply(c,event(10,13));ui.apply(c,event(11,13));
        if(c.currentScreen!=null||!c.inGameHud.getChatHud().getMessageHistory().contains("/"+command))throw new IllegalStateException("Vanilla command did not submit");commands.add("/"+command);
    }
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);
        if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Hands fixture server identity changed");
        observed.set(new State(System.nanoTime(),p.interactionManager.getGameMode().getName(),p.getInventory().selectedSlot,
                Registries.ITEM.getId(p.getInventory().getStack(0).getItem()).toString(),Registries.ITEM.getId(p.getInventory().getStack(1).getItem()).toString(),Registries.ITEM.getId(p.getMainHandStack().getItem()).toString(),p.getPos()));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Hands fixture owner changed");}
    private void validateImages(){
        for(String name:STAGES){var p=images.get(name);if(p==null)throw new IllegalStateException("Missing actual image "+name);
            var meta=p.getAsJsonObject("metadata");boolean inventory=name.equals("inventory");
            if(!meta.get("no_world_pixels").getAsBoolean()||meta.get("hand_pass_rendered").getAsBoolean()==inventory)throw new IllegalStateException("Production hand/world render pass differs for "+name);
            if(!inventory&&(p.get("hand_region_pixels").getAsLong()<200||p.get("clear_region_pixels").getAsLong()!=0||p.get("transparent_pixels").getAsLong()<p.get("pixels").getAsLong()*.4))throw new IllegalStateException("Missing hand or opaque world leakage in "+name);
            if(p.get("opaque_pixels").getAsLong()<200)throw new IllegalStateException("Actual image lacks visible geometry/UI in "+name);
        }
        String empty=images.get("empty").get("hand_region_sha256").getAsString(),stone=images.get("stone").get("hand_region_sha256").getAsString(),sword=images.get("sword").get("hand_region_sha256").getAsString(),swing=images.get("swing").get("hand_region_sha256").getAsString();
        if(empty.equals(stone)||stone.equals(sword)||sword.equals(swing))throw new IllegalStateException("Item selection/swing did not change actual hand pixels");
    }
    private void complete(MinecraftClient c,boolean passed,String error){
        if(result!=null||finished)return;try{movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_hands_fixture_v1");j.addProperty("mode","hands");j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);
        j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("direct_command_api_used",false);j.addProperty("ability_writes_used",false);j.addProperty("position_writes_used",false);
        j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("stage",stage);j.addProperty("scripted_swing_calls",swingCalls);j.addProperty("scripted_view_writes",viewWrites);j.addProperty("render_pixels_verified",passed);j.addProperty("inventory_hand_suppression_verified",passed);
        var list=new JsonArray();commands.forEach(list::add);j.add("submitted_commands",list);var captures=new JsonArray();for(String name:STAGES){var p=images.get(name);if(p!=null)captures.add(p.deepCopy());}j.add("images",captures);j.add("movement",movement.evidence(c));
        var s=observed.get();if(s!=null){j.addProperty("game_mode",s.mode());j.addProperty("selected_slot",s.selected());j.addProperty("first_item",s.first());j.addProperty("second_item",s.second());j.add("server_position",json(s.position()));}
        result=j;pendingResult.set(j.deepCopy());
    }
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static String hash(byte[] data)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));}
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();byte[] rgba=HudPixels.straightTopLeft(f.bottomUp(),f.width(),f.height());byte[] png=HudPixels.png(rgba,f.width(),f.height());
        Path file=directory.resolve("hands-"+sample.stage()+".png");Files.write(file,png,StandardOpenOption.CREATE_NEW);
        long transparent=0,opaque=0,hand=0,clear=0;var digest=MessageDigest.getInstance("SHA-256");
        // The right-hand region excludes the hotbar and centred item-name label.
        // The top-centre region contains neither vanilla HUD nor ordinary hands.
        for(int y=0;y<f.height();y++)for(int x=0;x<f.width();x++){
            int i=(y*f.width()+x)*4,a=rgba[i+3]&255;if(a==0)transparent++;if(a==255)opaque++;
            if(x>=f.width()*.65&&y>=f.height()*.2&&y<f.height()*.91){digest.update(rgba,i,4);if(a!=0)hand++;}
            if(x>=f.width()*.35&&x<f.width()*.65&&y<f.height()*.15&&a!=0)clear++;
        }
        var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file.getFileName().toString());p.addProperty("sha256",hash(png));p.addProperty("capture_id",f.id());p.addProperty("width",f.width());p.addProperty("height",f.height());p.addProperty("pixels",(long)f.width()*f.height());p.addProperty("transparent_pixels",transparent);p.addProperty("opaque_pixels",opaque);p.addProperty("hand_region_pixels",hand);p.addProperty("clear_region_pixels",clear);p.addProperty("hand_region_sha256",HexFormat.of().formatHex(digest.digest()));p.add("metadata",JsonParser.parseString(f.metadata()));images.put(sample.stage(),p);
    }
    private void writeLoop(){long seq=0;try{while(!closing){
        var sample=samples.poll();if(sample!=null)writeSample(sample);
        var proof=pendingResult.getAndSet(null);if(proof!=null){Files.writeString(directory.resolve("gameplay-hands-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());j.add("forward",json(new Vec3d(1,0,0)));j.add("up",json(new Vec3d(0,0,1)));
        Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
