package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.Perspective;
import net.minecraft.entity.EquipmentSlot;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.Vec3d;
import java.io.IOException;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual player/armor/item pixels through the gameplay world layer, in one owned vanilla save. */
public final class GameplayPlayerFixture {
    private static final List<String> STAGES=List.of("back","front","armored","sword","walking_a","walking_b","inventory","restored","first_person");
    private record State(long at,String head,String chest,String held,int slot,Vec3d position,Vec3d velocity){}
    private record Sample(String name,HudReadback.Completed frame){}
    private final GameplayBlocks blocks;private final GameplayMovement movement;private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;private final Path directory;private final Consumer<JsonObject> completed;
    private final AtomicReference<State> observed=new AtomicReference<>();private final AtomicBoolean observing=new AtomicBoolean();
    private final AtomicReference<String> failure=new AtomicReference<>();private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>();
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(2);private final Map<String,JsonObject> images=new ConcurrentHashMap<>();
    private final Set<String> queued=new HashSet<>();private final List<String> commands=new ArrayList<>();private final Map<String,byte[]> worldPixels=new HashMap<>();
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;private Perspective originalPerspective;
    private Vec3d start,walkStart;private String skinTexture,skinModel;private long begun,stageAt,sequence;private int stage,ticks;private boolean finished,perspectiveRestored,forwardHeld,walkVerified,inventoryVerified;
    private double clientDistance,serverDistance;
    private volatile boolean closing,written;private JsonObject result;

    public GameplayPlayerFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
            HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(!mode.equals("player")||!Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayWorldBlocks"))throw new IllegalArgumentException("Explicit standalone world-block player fixture required");
        this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();if(!save.newlyCreated()||Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-player-fixture.json")))throw new IOException("New isolated player fixture required");
        var worker=new Thread(this::writeLoop,"MineComePlayerFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0||result!=null)return;try{requireOwner(c);movement.authority(c,System.nanoTime(),true);}catch(Exception e){complete(c,false,e.toString());}}
    public GameplayWorldRenderer.View view(){var c=MinecraftClient.getInstance();return begun==0||closing||finished||c.player!=player?null:GameplayPerspective.view(c,1F,Math.toRadians(70));}
    public GameplayBlocks.Aim renderAim(){return null;}
    public void tick(MinecraftClient c){if(closing||finished)return;try{
        if(result!=null){movement.suspend(c);blocks.suspend(c);if(written||failure.get()!=null){if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}finished=true;completed.accept(result.deepCopy());}return;}
        if(failure.get()!=null)throw new IllegalStateException(failure.get());if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);requireOwner(c);
        long now=System.nanoTime();if(now-begun>45_000_000_000L||now-stageAt>8_000_000_000L)throw new IllegalStateException("Player fixture deadline stage="+stage+", ticks="+ticks);
        observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;ticks++;
        if(stage!=9&&stage!=10&&(start.distanceTo(c.player.getPos())>.025||start.distanceTo(s.position())>.025))throw new IllegalStateException("Perspective fixture unexpectedly moved the player");
        switch(stage){
            case 0->{requireEquipment(c,s,"minecraft:air","minecraft:air","minecraft:air",8);if(images.containsKey("back")){GameplayPerspective.select(c,Perspective.THIRD_PERSON_FRONT);next(1,now);}}
            case 1->{if(images.containsKey("front")){command(c,"item replace entity @s armor.head with minecraft:diamond_helmet");command(c,"item replace entity @s armor.chest with minecraft:diamond_chestplate");next(2,now);}}
            case 2->{if(!equipmentMatches(c,s,"minecraft:diamond_helmet","minecraft:diamond_chestplate","minecraft:air",8))return;if(s.at()<=stageAt)return;next(3,now);}
            case 3->{requireEquipment(c,s,"minecraft:diamond_helmet","minecraft:diamond_chestplate","minecraft:air",8);if(images.containsKey("armored")){command(c,"item replace entity @s hotbar.0 with minecraft:diamond_sword");key(c,'1');next(4,now);}}
            case 4->{if(!equipmentMatches(c,s,"minecraft:diamond_helmet","minecraft:diamond_chestplate","minecraft:diamond_sword",0))return;if(s.at()<=stageAt)return;next(5,now);}
            case 5->{requireEquipment(c,s,"minecraft:diamond_helmet","minecraft:diamond_chestplate","minecraft:diamond_sword",0);if(images.containsKey("sword")){walkStart=c.player.getPos();forward(c,true);next(9,now);}}
            case 6->{if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Player fixture inventory did not open");forward(c,ticks>=2&&ticks<=9);if(ticks>=20&&images.containsKey("inventory")){forward(c,false);inventoryVerified=true;key(c,'E');next(7,now);}}
            case 7->{if(c.currentScreen!=null)throw new IllegalStateException("Player fixture inventory did not close");requireEquipment(c,s,"minecraft:diamond_helmet","minecraft:diamond_chestplate","minecraft:diamond_sword",0);if(images.containsKey("restored")){GameplayPerspective.select(c,Perspective.FIRST_PERSON);next(8,now);}}
            case 8->{requireEquipment(c,s,"minecraft:diamond_helmet","minecraft:diamond_chestplate","minecraft:diamond_sword",0);if(images.containsKey("first_person")){validateImages();complete(c,true,null);}}
            case 9->{requireEquipment(c,s,"minecraft:diamond_helmet","minecraft:diamond_chestplate","minecraft:diamond_sword",0);if(ticks>=6){forward(c,false);next(10,now);}}
            case 10->{if(ticks>=12&&(!images.containsKey("walking_a")||!images.containsKey("walking_b")))throw new IllegalStateException("Walking animation capture incomplete before release: queued="+queued+", images="+images.keySet());
                if(ticks<10||!images.containsKey("walking_a")||!images.containsKey("walking_b")||c.player.getVelocity().horizontalLength()>.004||s.velocity().horizontalLength()>.004||c.player.getPos().distanceTo(s.position())>.04)return;
                clientDistance=walkStart.distanceTo(c.player.getPos());serverDistance=walkStart.distanceTo(s.position());if(clientDistance<.5||serverDistance<.5||Math.abs(clientDistance-serverDistance)>.04||clientDistance>3.25)throw new IllegalStateException("Third-person walk did not converge inside the fixture ground: "+clientDistance+" "+serverDistance);
                walkVerified=true;start=c.player.getPos();key(c,'E');next(6,now);}
            default->throw new IllegalStateException("Unknown player fixture stage");
        }
    }catch(Exception e){complete(c,false,e.toString());}}
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||!c.isIntegratedServerRunning()||c.getServer()==null)throw new IllegalStateException("Owned integrated client required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);start=c.player.getPos();
        var skin=c.player.getSkinTextures();skinTexture=skin.texture().toString();skinModel=skin.model().name();
        if(!skinTexture.equals("minecraft:textures/entity/player/wide/steve.png")||!skinModel.equals("WIDE"))throw new IllegalStateException("Gameplay player does not use bundled classic Steve: "+skinTexture+" "+skinModel);
        originalPerspective=c.options.getPerspective();GameplayPerspective.select(c,Perspective.THIRD_PERSON_BACK);key(c,'9');begun=stageAt=System.nanoTime();
    }
    private static String item(net.minecraft.item.ItemStack stack){return Registries.ITEM.getId(stack.getItem()).toString();}
    private boolean equipmentMatches(MinecraftClient c,State s,String head,String chest,String held,int slot){return s.head().equals(head)&&s.chest().equals(chest)&&s.held().equals(held)&&s.slot()==slot&&item(c.player.getEquippedStack(EquipmentSlot.HEAD)).equals(head)&&item(c.player.getEquippedStack(EquipmentSlot.CHEST)).equals(chest)&&item(c.player.getMainHandStack()).equals(held)&&c.player.getInventory().selectedSlot==slot;}
    private void requireEquipment(MinecraftClient c,State s,String head,String chest,String held,int slot){if(ticks>=12&&!equipmentMatches(c,s,head,chest,held,slot))throw new IllegalStateException("Player fixture client/server equipment differs at stage "+stage+": "+s);}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Player fixture server owner changed");
        observed.set(new State(System.nanoTime(),item(p.getEquippedStack(EquipmentSlot.HEAD)),item(p.getEquippedStack(EquipmentSlot.CHEST)),item(p.getMainHandStack()),p.getInventory().selectedSlot,p.getPos(),p.getVelocity()));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Player fixture owner changed");}
    private void next(int value,long now){stage=value;ticks=0;stageAt=now;}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void forward(MinecraftClient c,boolean pressed){if(forwardHeld==pressed)return;movement.event(c,event(pressed?1:2,'W'),System.nanoTime());forwardHeld=pressed;}
    private void command(MinecraftClient c,String text){movement.suspend(c);key(c,0xbf);if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Player fixture command screen absent");text.codePoints().forEach(cp->ui.apply(c,event(9,cp)));if(!ui.chatText(c).equals("/"+text))throw new IllegalStateException("Player fixture command differs");ui.apply(c,event(10,13));ui.apply(c,event(11,13));if(c.currentScreen!=null)throw new IllegalStateException("Player command did not submit");commands.add("/"+text);}
    public String captureStage(){if(closing||finished||result!=null||begun==0)return null;String name;
        if(stage==9){var c=MinecraftClient.getInstance();if(ticks<2||c.player.getVelocity().horizontalLength()<.05||c.player.limbAnimator.getSpeed()<.1f)return null;name=!queued.contains("walking_a")&&!images.containsKey("walking_a")?"walking_a":ticks>=4?"walking_b":null;}
        else{if(ticks<12)return null;name=switch(stage){case 0->"back";case 1->"front";case 3->"armored";case 5->"sword";case 6->"inventory";case 7->"restored";case 8->"first_person";default->null;};}
        return name==null||queued.contains(name)||images.containsKey(name)?null:name;
    }
    /** Recorded with each PBO's metadata, before another tick can change the pose. */
    public JsonObject captureState(){var j=new JsonObject();var c=MinecraftClient.getInstance();if(begun==0||c.player!=player)return j;
        j.add("client_position",json(c.player.getPos()));j.add("camera_position",json(c.gameRenderer.getCamera().getPos()));j.addProperty("client_horizontal_speed",c.player.getVelocity().horizontalLength());
        // Inspected pinned 1.21.1 LivingEntity exposes its actual LimbAnimator;
        // getPos/getSpeed are observations only, never fixture animation writes.
        j.addProperty("limb_position",c.player.limbAnimator.getPos());j.addProperty("limb_speed",c.player.limbAnimator.getSpeed());var s=observed.get();if(s!=null){j.add("server_position",json(s.position()));j.addProperty("server_horizontal_speed",s.velocity().horizontalLength());}return j;
    }
    public void captured(HudReadback.Completed frame){if(closing||finished||result!=null)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("player_fixture_stage"))return;String name=meta.get("player_fixture_stage").getAsString();if(!STAGES.contains(name)||!queued.add(name))return;if(!samples.offer(new Sample(name,frame)))failure.compareAndSet(null,"Player image queue full");}
    private void validateImages(){for(String name:STAGES){var p=images.get(name);if(p==null)throw new IllegalStateException("Missing player frame "+name);var meta=p.getAsJsonObject("metadata");boolean first=name.equals("first_person"),inventory=name.equals("inventory");
        String perspective=first?"FIRST_PERSON":name.equals("back")?"THIRD_PERSON_BACK":"THIRD_PERSON_FRONT";
        if(meta.get("frame_format").getAsInt()!=2||meta.get("rendered_world_blocks").getAsInt()!=0||meta.get("player_pixels").getAsBoolean()==first||!meta.get("perspective").getAsString().equals(perspective)||meta.get("hand_pass_rendered").getAsBoolean()!=first||meta.get("screen").getAsInt()!=(inventory?1:0))throw new IllegalStateException("Player render metadata differs: "+p);
        long body=p.get("world_opaque_pixels").getAsLong();if(!p.get("depth_finite_unit_range").getAsBoolean()||(first?body!=0:body<500||p.get("world_with_depth_pixels").getAsLong()<body*.95))throw new IllegalStateException("Player body/depth absent or leaked into first person: "+p);
        if(p.get("world_stray_pixels").getAsLong()!=0)throw new IllegalStateException("Player rendering leaked outside its central view: "+p);
        if(first&&p.get("foreground_hand_pixels").getAsLong()<100)throw new IllegalStateException("First-person hand did not return");
    }
        if(images.get("back").get("world_rgba_sha256").getAsString().equals(images.get("front").get("world_rgba_sha256").getAsString()))throw new IllegalStateException("Front/back player views are identical");
        if(images.get("armored").get("changed_from_front_pixels").getAsLong()<150||images.get("sword").get("changed_from_armored_pixels").getAsLong()<50)throw new IllegalStateException("Vanilla equipment did not change player body pixels");
        var a=images.get("walking_a");var b=images.get("walking_b");var ma=a.getAsJsonObject("metadata").getAsJsonObject("player_fixture_motion");var mb=b.getAsJsonObject("metadata").getAsJsonObject("player_fixture_motion");
        if(!walkVerified||!inventoryVerified||a.get("changed_from_sword_pixels").getAsLong()<100||b.get("changed_from_walking_a_pixels").getAsLong()<100||ma.get("limb_speed").getAsDouble()<.1||mb.get("limb_speed").getAsDouble()<.1||Math.abs(mb.get("limb_position").getAsDouble()-ma.get("limb_position").getAsDouble())<.2)throw new IllegalStateException("Ordinary movement did not animate actual player pixels");
        Vec3d cameraA=vector(ma.getAsJsonObject("camera_position")),cameraB=vector(mb.getAsJsonObject("camera_position")),feetA=vector(ma.getAsJsonObject("client_position")),feetB=vector(mb.getAsJsonObject("client_position"));
        if(cameraA.distanceTo(cameraB)<.25||cameraA.subtract(feetA).distanceTo(cameraB.subtract(feetB))>.15)throw new IllegalStateException("Third-person camera did not follow the walking player");
    }
    private void complete(MinecraftClient c,boolean passed,String error){if(result!=null||finished)return;try{forward(c,false);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);restorePerspective(c);}catch(Exception e){passed=false;error=e.toString();}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_player_fixture_v1");j.addProperty("mode","player");j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("native_camera_verified",false);j.addProperty("direct_command_api_used",false);j.addProperty("position_writes_used",false);j.addProperty("walking_verified",false);j.addProperty("render_pixels_verified",passed);j.addProperty("perspective_restored",perspectiveRestored);j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("stage",stage);
        j.addProperty("walking_verified",walkVerified);j.addProperty("inventory_suppression_verified",inventoryVerified);j.addProperty("velocity_writes_used",false);j.addProperty("client_walk_distance",clientDistance);j.addProperty("server_walk_distance",serverDistance);
        j.addProperty("skin_texture",skinTexture);j.addProperty("skin_model",skinModel);var a=new JsonArray();commands.forEach(a::add);j.add("submitted_commands",a);a=new JsonArray();for(String name:STAGES)if(images.containsKey(name))a.add(images.get(name).deepCopy());j.add("images",a);
        var s=observed.get();if(s!=null){j.addProperty("helmet",s.head());j.addProperty("chestplate",s.chest());j.addProperty("held",s.held());j.addProperty("selected_slot",s.slot());}result=j;pendingResult.set(j.deepCopy());
    }
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static Vec3d vector(JsonObject j){return new Vec3d(j.get("x").getAsDouble(),j.get("y").getAsDouble(),j.get("z").getAsDouble());}
    private static String hash(byte[] data)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));}
    private static long changes(byte[] baseline,byte[] pixels){if(baseline==null||baseline.length!=pixels.length)return 0;long n=0;for(int i=0;i<pixels.length;i+=4){boolean changed=false;for(int c=0;c<4;c++)if(Math.abs((baseline[i+c]&255)-(pixels[i+c]&255))>12)changed=true;if(changed)n++;}return n;}
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();int plane=HudPixels.byteSize(f.width(),f.height());byte[] layers=f.layersBottomUp();if(layers==null||layers.length!=plane*3)throw new IllegalStateException("Player capture is missing world/depth planes");
        byte[] world=HudPixels.straightTopLeft(Arrays.copyOfRange(layers,plane,plane*2),f.width(),f.height());
        byte[] rgba=HudPixels.straightTopLeft(f.bottomUp(),f.width(),f.height()),png=HudPixels.png(rgba,f.width(),f.height()),worldPng=HudPixels.png(world,f.width(),f.height());
        Path file=directory.resolve("player-"+sample.name()+".png"),worldFile=directory.resolve("player-"+sample.name()+"-world.png");Files.write(file,png,StandardOpenOption.CREATE_NEW);Files.write(worldFile,worldPng,StandardOpenOption.CREATE_NEW);
        long body=0,bodyDepth=0,stray=0,hand=0;boolean valid=true;var raw=ByteBuffer.wrap(layers).order(ByteOrder.LITTLE_ENDIAN);
        for(int y=0;y<f.height();y++)for(int x=0;x<f.width();x++){int top=(y*f.width()+x)*4,bottom=((f.height()-1-y)*f.width()+x)*4;float depth=raw.getFloat(plane*2+bottom);valid&=Float.isFinite(depth)&&depth>=0&&depth<=1;
            if((world[top+3]&255)>8){body++;if(depth>0&&depth<1)bodyDepth++;if(x<f.width()*.1||x>=f.width()*.9||y<f.height()*.05)stray++;}
            if(x>f.width()*.65&&y>f.height()*.2&&y<f.height()*.91&&(layers[bottom+3]&255)>8)hand++;
        }
        var p=new JsonObject();p.addProperty("stage",sample.name());p.addProperty("file",file.getFileName().toString());p.addProperty("sha256",hash(png));p.addProperty("world_file",worldFile.getFileName().toString());p.addProperty("world_sha256",hash(worldPng));p.addProperty("world_rgba_sha256",hash(world));p.addProperty("capture_id",f.id());p.addProperty("width",f.width());p.addProperty("height",f.height());p.addProperty("world_opaque_pixels",body);p.addProperty("world_with_depth_pixels",bodyDepth);p.addProperty("depth_finite_unit_range",valid);p.addProperty("world_stray_pixels",stray);p.addProperty("foreground_hand_pixels",hand);p.addProperty("changed_from_front_pixels",changes(worldPixels.get("front"),world));p.addProperty("changed_from_armored_pixels",changes(worldPixels.get("armored"),world));p.add("metadata",JsonParser.parseString(f.metadata()));
        p.addProperty("changed_from_sword_pixels",changes(worldPixels.get("sword"),world));p.addProperty("changed_from_walking_a_pixels",changes(worldPixels.get("walking_a"),world));
        if(Set.of("front","armored","sword","walking_a").contains(sample.name()))worldPixels.put(sample.name(),world);images.put(sample.name(),p);
    }
    private void writeLoop(){long seq=0;try{while(!closing){var sample=samples.poll();if(sample!=null)writeSample(sample);var proof=pendingResult.getAndSet(null);if(proof!=null){Files.writeString(directory.resolve("gameplay-player-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());j.add("forward",json(new Vec3d(1,0,0)));j.add("up",json(new Vec3d(0,0,1)));Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json"));Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    private void restorePerspective(MinecraftClient c){if(originalPerspective!=null&&c.player==player){GameplayPerspective.select(c,originalPerspective);perspectiveRestored=c.options.getPerspective()==originalPerspective;}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){forward(c,false);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);restorePerspective(c);}}
}
