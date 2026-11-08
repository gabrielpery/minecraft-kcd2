package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayAimReader;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.Vec3d;
import java.io.IOException;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Explicit native acceptance: scripted ordinary input, never player/camera position writes. */
public final class GameplayNativeWalkingFixture implements AutoCloseable {
    private record State(long at,Vec3d position,Vec3d velocity){}
    private record Frame(String stage,HudReadback.Completed frame){}
    private static final List<String> IMAGES=List.of("back_before","back_walking","back_after","inventory","front_before","front_walking","front_after","first_person");
    private final GameplayMovement movement;private final GameplayWorld save;private final Path directory;private final Consumer<JsonObject> completed;
    private final AtomicReference<State> observed=new AtomicReference<>();private final AtomicBoolean observing=new AtomicBoolean();
    private final AtomicReference<String> failure=new AtomicReference<>();private final ArrayBlockingQueue<Frame> queue=new ArrayBlockingQueue<>(8);
    private final Map<String,JsonObject> images=new ConcurrentHashMap<>();private final Set<String> queued=new HashSet<>();private final JsonArray points=new JsonArray();
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;
    private final long created=System.nanoTime();private long began,stageAt,sequence;private int stage,ticks,held,backStrides,frontStrides;
    private long backDwellAt,backDwellStartedUtc,backDwellCompletedUtc,backDwellMs;
    private volatile boolean closed,finished;private boolean backVerified,frontVerified,inventoryVerified,firstVerified;
    private volatile boolean writerClosed;private Vec3d walkStart,eyeStart,inventoryStart,loopStart,loopEye;private GameplayAimReader.RenderSample sample;
    private double backDistance,frontDistance,maxExcursion;private JsonObject result;

    public GameplayNativeWalkingFixture(GameplayMovement movement,GameplayWorld save,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayWorldBlocks")||!Boolean.getBoolean("minecome.gameplayThirdPersonWalkingCheck"))throw new IllegalArgumentException("Explicit native WorldBlocks check required");
        this.movement=movement;this.save=save;this.directory=directory.toRealPath();this.completed=completed;save.verifyOwnership();
        var writer=new Thread(this::writeLoop,"MineComeNativeWalkingImages");writer.setDaemon(true);writer.start();
    }
    public void tick(MinecraftClient c,boolean armed,GameplayAimReader.RenderSample nativeSample){if(closed||finished)return;try{
        if(failure.get()!=null)throw new IllegalStateException(failure.get());
        long now=System.nanoTime();if(began==0){
            if(now-created>90_000_000_000L)throw new IllegalStateException("Native walking check never armed");
            if(!armed||!movement.ready()||nativeSample==null||!nativeSample.fresh()||nativeSample.schema()!=3||nativeSample.perspective()!=0)return;
            begin(c);sample=nativeSample;key(c,0x74);next(1,now);return;
        }
        requireOwner(c);if(!armed)throw new IllegalStateException("Native input authority lost during scripted walk");
        if(now-began>90_000_000_000L||now-stageAt>(stage==1?25_000_000_000L:8_000_000_000L))throw new IllegalStateException("Native walking deadline stage="+stage+", ticks="+ticks);
        sample=nativeSample;observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;ticks++;
        if(loopStart!=null){double excursion=horizontal(c.player.getPos().subtract(loopStart));maxExcursion=Math.max(maxExcursion,excursion);if(excursion>1)throw new IllegalStateException("Native walking exceeded its one-metre excursion");}
        switch(stage){
            case 1->{if(ack(1)&&ticks>=4&&images.containsKey("back_before")){
                // Isolate stationary native depth stability before movement
                // changes the scene; keep ordinary movement proof unchanged.
                if(backDwellAt==0){backDwellAt=now;backDwellStartedUtc=System.currentTimeMillis();}
                if(now-backDwellAt<12_000_000_000L)return;
                backDwellMs=(now-backDwellAt)/1_000_000;backDwellCompletedUtc=System.currentTimeMillis();
                point("back_before",c,s);loopStart=c.player.getPos();loopEye=sample.aim().origin();startWalk(c,'W');next(2,now);}}
            case 2->{if(strideComplete(c)){release(c);next(3,now);}}
            case 3->{if(settled(c,s)&&ack(1)&&ticks>=20&&images.containsKey("back_walking")&&(backStrides<5||images.containsKey("back_after"))){
                backDistance+=verifyWalk(c,s,"back_stride_"+(++backStrides));
                if(backStrides<6){startWalk(c,backStrides%2==0?'W':'S');next(2,now);}else{
                    verifyRecovery(c,s);point("back_after",c,s);backVerified=true;inventoryStart=c.player.getPos();key(c,'E');next(4,now);}}}
            case 4->{if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Native inventory did not open");
                if(ticks==2)movementKey(c,'W',true);if(ticks==10)release(c);
                if(c.player.getPos().distanceTo(inventoryStart)>.025||s.position().distanceTo(inventoryStart)>.04)throw new IllegalStateException("Inventory allowed walking");
                if(ticks>=20&&images.containsKey("inventory")){release(c);point("inventory_suppressed",c,s);inventoryVerified=true;key(c,'E');next(5,now);}}
            case 5->{if(c.currentScreen==null&&ticks>=4&&ack(1)){key(c,0x74);next(6,now);}}
            case 6->{if(ack(2)&&ticks>=4&&images.containsKey("front_before")){point("front_before",c,s);loopStart=c.player.getPos();loopEye=sample.aim().origin();startWalk(c,'W');next(7,now);}}
            case 7->{if(strideComplete(c)){release(c);next(8,now);}}
            case 8->{if(settled(c,s)&&ack(2)&&ticks>=20&&images.containsKey("front_walking")&&(frontStrides<5||images.containsKey("front_after"))){
                frontDistance+=verifyWalk(c,s,"front_stride_"+(++frontStrides));
                if(frontStrides<6){startWalk(c,frontStrides%2==0?'W':'S');next(7,now);}else{
                    verifyRecovery(c,s);point("front_after",c,s);frontVerified=true;key(c,0x74);next(9,now);}}}
            case 9->{if(ack(0)&&ticks>=8&&images.containsKey("first_person")){point("first_person",c,s);firstVerified=true;finish(c,true,null);}}
            default->throw new IllegalStateException("Unknown native walking stage");
        }
    }catch(Exception e){finish(c,false,e.toString());}}
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||!c.isIntegratedServerRunning()||c.getServer()==null||c.currentScreen!=null)throw new IllegalStateException("Owned native gameplay required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);began=stageAt=System.nanoTime();
        if(c.player.getAbilities().flying)throw new IllegalStateException("Walking fixture requires grounded walking mode");observe();
    }
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Native walking owner changed");}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closed||finished)return;var p=server.getPlayerManager().getPlayer(playerId);
        if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Native walking server owner changed");
        observed.set(new State(System.nanoTime(),p.getPos(),p.getVelocity()));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private boolean ack(int mode){return sample!=null&&sample.schema()==3&&sample.fresh()&&sample.perspective()==mode;}
    private static boolean settled(MinecraftClient c,State s){return c.player.getVelocity().horizontalLength()<.004&&s.velocity().horizontalLength()<.004&&c.player.getPos().distanceTo(s.position())<.04;}
    private void startWalk(MinecraftClient c,int code){walkStart=c.player.getPos();eyeStart=sample.aim().origin();movementKey(c,code,true);}
    // Release early enough to include vanilla deceleration inside the one-metre envelope.
    private boolean strideComplete(MinecraftClient c){return ticks>=6||horizontal(c.player.getPos().subtract(walkStart))>=.3;}
    private void verifyRecovery(MinecraftClient c,State s){if(horizontal(c.player.getPos().subtract(loopStart))>.25||horizontal(s.position().subtract(loopStart))>.25||horizontal(sample.aim().origin().subtract(loopEye))>.3)throw new IllegalStateException("Repeated forward/back steps did not recover their starting point");}
    private double verifyWalk(MinecraftClient c,State s,String name){
        Vec3d clientDelta=c.player.getPos().subtract(walkStart),serverDelta=s.position().subtract(walkStart),nativeDelta=sample.aim().origin().subtract(eyeStart);
        double distance=clientDelta.horizontalLength();
        if(distance<.35||distance>1||Math.abs(distance-serverDelta.horizontalLength())>.04||nativeDelta.horizontalLength()<.25||horizontal(clientDelta.subtract(nativeDelta))>.25)throw new IllegalStateException("Native/player walk mismatch "+name+": "+clientDelta+" / "+serverDelta+" / "+nativeDelta);
        point(name,c,s);return distance;
    }
    private static double horizontal(Vec3d v){return Math.hypot(v.x,v.z);}
    private void point(String name,MinecraftClient c,State s){var p=captureState(c);p.addProperty("stage",name);p.add("server_position",json(s.position()));points.add(p);}
    private void next(int value,long now){stage=value;ticks=0;stageAt=now;}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void key(MinecraftClient c,int code){if(code=='E')movement.suspend(c);ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void movementKey(MinecraftClient c,int code,boolean down){movement.event(c,event(down?1:2,code),System.nanoTime());held=down?code:0;}
    private void release(MinecraftClient c){if(held!=0)movementKey(c,held,false);}
    public String captureStage(){if(closed||finished||began==0||sample==null||!sample.fresh())return null;
        // A tick count alone does not prove vanilla has consumed the key yet.
        // Capture actual motion, including the ordinary deceleration after key
        // release, without extending a stride just to obtain an image.
        var c=MinecraftClient.getInstance();boolean moving=c.player==player&&c.player.getVelocity().horizontalLength()>=.04&&c.player.limbAnimator.getSpeed()>=.1;
        String walking=(stage==2||stage==3)&&ack(1)?"back_walking":(stage==7||stage==8)&&ack(2)?"front_walking":null;
        if(moving&&walking!=null&&!queued.contains(walking)&&!images.containsKey(walking))return walking;
        String name=switch(stage){
        case 1->ack(1)&&ticks>=3?"back_before":null;case 3->backStrides==5&&ticks>=20?"back_after":null;
        case 4->ticks>=12?"inventory":null;case 6->ack(2)&&ticks>=3?"front_before":null;
        case 8->frontStrides==5&&ticks>=20?"front_after":null;case 9->ack(0)&&ticks>=6?"first_person":null;default->null;};
        return name==null||queued.contains(name)||images.containsKey(name)?null:name;
    }
    public JsonObject captureState(MinecraftClient c){var j=new JsonObject();j.add("client_position",json(c.player.getPos()));j.addProperty("client_speed",c.player.getVelocity().horizontalLength());j.addProperty("limb_speed",c.player.limbAnimator.getSpeed());
        if(sample!=null){j.addProperty("native_perspective",sample.perspective());j.addProperty("native_sample_utc_ms",sample.aim().capturedUtcMs());j.add("native_eye",json(sample.aim().origin()));j.add("native_camera",json(sample.view().origin()));}return j;}
    public void captured(HudReadback.Completed f){if(closed||finished)return;var meta=JsonParser.parseString(f.metadata()).getAsJsonObject();if(!meta.has("native_walking_stage"))return;String name=meta.get("native_walking_stage").getAsString();if(!IMAGES.contains(name)||!queued.add(name))return;if(!queue.offer(new Frame(name,f)))failure.compareAndSet(null,"Native walking image queue full");}
    private void writeLoop(){try{while(!writerClosed){var frame=queue.poll(100,TimeUnit.MILLISECONDS);if(frame==null)continue;var f=frame.frame();var meta=JsonParser.parseString(f.metadata()).getAsJsonObject();
        boolean first=frame.stage().equals("first_person"),inventory=frame.stage().equals("inventory");int mode=first?0:frame.stage().startsWith("front")?2:1;
        if(meta.get("frame_format").getAsInt()!=2||meta.get("player_pixels").getAsBoolean()==first||meta.get("hand_pass_rendered").getAsBoolean()!=first||meta.get("screen").getAsInt()!=(inventory?1:0)||meta.getAsJsonObject("native_walking_motion").get("native_perspective").getAsInt()!=mode)throw new IllegalStateException("Native walking frame differs: "+frame.stage());
        if(frame.stage().endsWith("walking")){
            var motion=meta.getAsJsonObject("native_walking_motion");double speed=motion.get("client_speed").getAsDouble(),limbs=motion.get("limb_speed").getAsDouble();
            if(speed<.04||limbs<.1)throw new IllegalStateException("Native walking frame lacks real movement/limbs: stage="+frame.stage()+", capture="+f.id()+", speed="+speed+", limbs="+limbs+", nativeUtc="+motion.get("native_sample_utc_ms"));
        }
        int plane=HudPixels.byteSize(f.width(),f.height());byte[] layers=f.layersBottomUp();if(layers==null||layers.length!=plane*3)throw new IllegalStateException("Native walking world/depth frame absent");
        byte[] rgba=HudPixels.straightTopLeft(f.bottomUp(),f.width(),f.height()),world=HudPixels.straightTopLeft(Arrays.copyOfRange(layers,plane,plane*2),f.width(),f.height());
        byte[] png=HudPixels.png(rgba,f.width(),f.height()),worldPng=HudPixels.png(world,f.width(),f.height());String file="native-walking-"+frame.stage()+".png",worldFile="native-walking-"+frame.stage()+"-world.png";
        Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);Files.write(directory.resolve(worldFile),worldPng,StandardOpenOption.CREATE_NEW);
        var p=new JsonObject();p.addProperty("stage",frame.stage());p.addProperty("file",file);p.addProperty("sha256",hash(png));p.addProperty("world_file",worldFile);p.addProperty("world_sha256",hash(worldPng));p.add("metadata",meta);images.put(frame.stage(),p);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    private static String hash(byte[] b)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(b));}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private void finish(MinecraftClient c,boolean passed,String why){if(finished)return;finished=true;try{release(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;why=e.toString();}
        result=new JsonObject();result.addProperty("schema",1);result.addProperty("kind","minecome_native_third_person_walking_v1");result.addProperty("result",passed?"passed":"failed");result.addProperty("failure",why);result.addProperty("world_id",save.id().toString());result.addProperty("actual_minecraft",true);result.addProperty("scripted_guest_input",true);result.addProperty("physical_native_keys_verified",false);result.addProperty("position_writes_used",false);result.addProperty("velocity_writes_used",false);result.addProperty("camera_writes_used",false);
        result.addProperty("back_walking_verified",backVerified);result.addProperty("front_walking_verified",frontVerified);result.addProperty("inventory_suppression_verified",inventoryVerified);result.addProperty("first_person_return_verified",firstVerified);result.addProperty("back_distance",backDistance);result.addProperty("front_distance",frontDistance);result.addProperty("elapsed_ms",began==0?0:(System.nanoTime()-began)/1_000_000);result.addProperty("stage",stage);result.add("points",points.deepCopy());
        result.addProperty("back_strides",backStrides);result.addProperty("front_strides",frontStrides);result.addProperty("max_excursion",maxExcursion);
        result.addProperty("stationary_back_dwell_ms",backDwellMs);result.addProperty("stationary_back_started_utc_ms",backDwellStartedUtc);result.addProperty("stationary_back_completed_utc_ms",backDwellCompletedUtc);
        if(!passed&&player!=null&&c.player==player){var state=captureState(c);var s=observed.get();if(s!=null)state.add("server_position",json(s.position()));result.add("failure_state",state);}
        var captures=new JsonArray();for(String name:IMAGES)if(images.containsKey(name))captures.add(images.get(name).deepCopy());result.add("images",captures);completed.accept(result.deepCopy());
    }
    @Override public void close(){if(closed)return;closed=true;writerClosed=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){release(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
