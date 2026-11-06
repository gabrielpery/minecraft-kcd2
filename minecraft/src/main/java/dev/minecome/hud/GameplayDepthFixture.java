package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import dev.minecome.terrain.GroundPatch;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.client.MinecraftClient;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual block/outline pixels against controlled heightfield boxes through the production depth pass. */
public final class GameplayDepthFixture {
    private static final List<String> NAMES=List.of("empty_terrain","visible","hidden","far","partial","restored","cleared");
    private record State(long at,int slot,String item,String block){}
    private record Sample(String name,HudReadback.Completed frame,GameplayWorldRenderer.View view,BlockPos block){}
    /** Render-only immutable fixture geometry; never installed as movement/placement collision. */
    private record Surface(GroundSurface base,List<GroundPatch.Slab> slabs) implements GroundSurface {
        public String run(){return base.run();} public String sourceKind(){return "standalone_depth_fixture";}
        public String sha256(){return base.sha256();} public double centerX(){return base.centerX();}
        public double centerY(){return base.centerY();} public double centerZ(){return base.centerZ();}
        public List<GroundPatch.Point> points(){return base.points();} public List<GroundPatch.Cell> cells(){return List.of();}
        public double heightAt(double x,double z){return base.heightAt(x,z);}
        public double groundForFeet(double x,double z,double radius){return base.groundForFeet(x,z,radius);}
        public boolean containsFeet(double x,double z,double margin){return base.containsFeet(x,z,margin);}
        public boolean wide(){return base.wide();}
    }
    private final GameplayBlocks blocks;private final GameplayMovement movement;private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;private final Path directory;private final Consumer<JsonObject> completed;
    private final AtomicReference<State> observed=new AtomicReference<>();private final AtomicBoolean observing=new AtomicBoolean();
    private final AtomicReference<String> failure=new AtomicReference<>();private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>();
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(2);private final Map<String,JsonObject> images=new ConcurrentHashMap<>();
    private final Set<String> queued=new HashSet<>();private final List<String> commands=new ArrayList<>();
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;private BlockPos block;
    private GameplayWorldRenderer.View fixedView;private GroundSurface empty,near,far,partial;
    private long begun,stageAt,actionAt,sequence;private int stage,index,ticks;private boolean finished;private volatile boolean closing,written;
    private JsonObject result;private byte[] visiblePixels;private int visibleWidth,visibleHeight;

    public GameplayDepthFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(!mode.equals("depth")||!Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayWorldBlocks"))throw new IllegalArgumentException("Explicit standalone depth fixture required");
        this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;this.directory=directory.toRealPath();save.verifyOwnership();
        if(!save.newlyCreated()||Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-depth-fixture.json")))throw new IOException("New isolated depth fixture required");
        var worker=new Thread(this::writeLoop,"MineComeDepthFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0||result!=null)return;try{requireOwner(c);movement.authority(c,System.nanoTime(),true);refreshAim(c);}catch(Exception e){complete(c,false,e.toString());}}
    public GameplayWorldRenderer.View view(){return begun==0||closing||finished?null:fixedView;}
    public GameplayBlocks.Aim renderAim(){var v=view();return v==null?null:new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),v.origin(),v.forward(),4.5,true,-1,false);}
    public GroundSurface surface(){if(begun==0)return null;if(stage==0)return near;if(stage!=3)return empty;return switch(index){case 1->near;case 2->far;case 3->partial;default->empty;};}
    public void tick(MinecraftClient c){if(closing||finished)return;try{
        if(result!=null){movement.suspend(c);blocks.suspend(c);if(written||failure.get()!=null){if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}finished=true;completed.accept(result.deepCopy());}return;}
        if(failure.get()!=null)throw new IllegalStateException(failure.get());if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);requireOwner(c);long now=System.nanoTime();
        if(now-begun>45_000_000_000L||now-stageAt>8_000_000_000L)throw new IllegalStateException("Depth fixture deadline stage="+stage+" index="+index+" controller="+blocks.evidence(c));
        observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;ticks++;refreshAim(c);
        switch(stage){
            case 0->{requireBlock(c,s,false);if(images.containsKey("empty_terrain")){command(c,"item replace entity @s hotbar.0 with minecraft:stone");key(c,'1');next(1,now);}}
            case 1->{if(s.slot()!=0||c.player.getInventory().selectedSlot!=0||!s.item().equals("minecraft:stone")||!Registries.ITEM.getId(c.player.getMainHandStack().getItem()).toString().equals(s.item()))return;click(c,1);actionAt=now;next(2,now);}
            case 2->{if(s.at()<=actionAt||now-actionAt<250_000_000L||blocks.evidence(c).get("pending").getAsBoolean())return;requireBlock(c,s,true);key(c,'9');next(3,now);}
            case 3->{requireBlock(c,s,true);if(images.containsKey(NAMES.get(index+1))){if(++index==5){click(c,0);actionAt=now;next(4,now);}else next(3,now);}}
            case 4->{if(s.at()<=actionAt||now-actionAt<250_000_000L||blocks.evidence(c).get("pending").getAsBoolean())return;requireBlock(c,s,false);next(5,now);}
            case 5->{requireBlock(c,s,false);if(images.containsKey("cleared")){validateImages();complete(c,true,null);}}
            default->throw new IllegalStateException("Unknown depth fixture stage");
        }
    }catch(Exception e){complete(c,false,e.toString());}}
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||!c.isIntegratedServerRunning()||c.getServer()==null)throw new IllegalStateException("Owned integrated client required");save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);
        int y=(int)Math.floor(movement.surface().heightAt(2.5,.5));block=new BlockPos(2,y,0);var eye=c.player.getEyePos();var f=Vec3d.ofCenter(block).subtract(eye).normalize();var right=f.crossProduct(new Vec3d(0,1,0)).normalize();fixedView=new GameplayWorldRenderer.View(eye,f,right.crossProduct(f).normalize(),Math.toRadians(70));
        var base=movement.surface();empty=new Surface(base,List.of());near=new Surface(base,List.of(new GroundPatch.Slab(.8,y-8,-2,1.4,y+4,2)));
        far=new Surface(base,List.of(new GroundPatch.Slab(4.5,y-8,-2,5,y+4,2)));partial=new Surface(base,List.of(new GroundPatch.Slab(.8,y-8,.24,1.4,y+4,2)));
        begun=stageAt=System.nanoTime();key(c,'9');
    }
    private void refreshAim(MinecraftClient c){if(stage==0)return;var eye=c.player.getEyePos();var target=stage<=2?new Vec3d(block.getX()+.5,block.getY(),block.getZ()+.5):Vec3d.ofCenter(block);var delta=target.subtract(eye);double distance=delta.length();if(distance>4.5)throw new IllegalStateException("Depth block outside reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,stage<=2?distance:-1,stage<=2));}
    private void requireBlock(MinecraftClient c,State s,boolean present){String expected=present?"minecraft:stone":"minecraft:air";if(!s.block().equals(expected)||!GameplayBlocks.stateName(c.world.getBlockState(block)).equals(expected)||blocks.ownedBlocks().size()!=(present?1:0))throw new IllegalStateException("Depth owned block differs: "+s+" "+blocks.evidence(c));}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Depth fixture server owner changed");observed.set(new State(System.nanoTime(),p.getInventory().selectedSlot,Registries.ITEM.getId(p.getMainHandStack().getItem()).toString(),GameplayBlocks.stateName(server.getOverworld().getBlockState(block))));}catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Depth fixture owner changed");}
    private void next(int value,long now){stage=value;stageAt=now;ticks=0;}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void click(MinecraftClient c,int button){refreshAim(c);blocks.event(c,event(7,button));blocks.event(c,event(8,button));}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void command(MinecraftClient c,String text){movement.suspend(c);key(c,0xbf);if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Depth command screen absent");text.codePoints().forEach(cp->ui.apply(c,event(9,cp)));if(!ui.chatText(c).equals("/"+text))throw new IllegalStateException("Depth command differs");ui.apply(c,event(10,13));ui.apply(c,event(11,13));if(c.currentScreen!=null)throw new IllegalStateException("Depth command did not submit");commands.add("/"+text);}
    public String captureStage(){if(closing||finished||result!=null||begun==0||ticks<12)return null;String name=stage==0?"empty_terrain":stage==3?NAMES.get(index+1):stage==5?"cleared":null;return name==null||queued.contains(name)||images.containsKey(name)?null:name;}
    public void captured(HudReadback.Completed frame){if(closing||finished||result!=null)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("world_blocks_fixture_stage"))return;String name=meta.get("world_blocks_fixture_stage").getAsString();if(!NAMES.contains(name)||!queued.add(name))return;if(!samples.offer(new Sample(name,frame,fixedView,block)))failure.compareAndSet(null,"Depth image queue full");}
    private void validateImages(){for(String name:NAMES){var p=images.get(name);if(p==null)throw new IllegalStateException("Missing depth image "+name);var m=p.getAsJsonObject("metadata");boolean emptyFrame=name.equals("empty_terrain")||name.equals("cleared");boolean depth=Set.of("empty_terrain","hidden","far","partial").contains(name);
        var layers=p.getAsJsonObject("layers");
        if(m.get("frame_format").getAsInt()!=2||m.getAsJsonObject("world_camera").get("utc_ms").getAsLong()!=0||
            !layers.get("depth_finite_unit_range").getAsBoolean()||layers.get("overlay_world_region_samples").getAsLong()!=0||
            layers.get("overlay_hand_samples").getAsLong()<100||layers.get("overlay_hud_samples").getAsLong()<100||layers.get("world_foreground_samples").getAsLong()!=0)
            throw new IllegalStateException("World/overlay/depth planes are not independently preserved: "+p);
        long world=layers.get("world_opaque_pixels").getAsLong(),worldDepth=layers.get("world_with_depth_pixels").getAsLong();
        if(emptyFrame||name.equals("hidden")){if(world!=0)throw new IllegalStateException("Empty world layer retains pixels: "+p);}
        else if(world<1000||worldDepth<world*.90)throw new IllegalStateException("World colour lacks same-frame GL depth: "+p);
        if((depth||!emptyFrame)&&layers.get("nonclear_depth_pixels").getAsLong()<1000)throw new IllegalStateException("World depth plane was cleared by the later hand pass: "+p);
        if(name.equals("cleared")&&layers.get("nonclear_depth_pixels").getAsLong()!=0)throw new IllegalStateException("World depth survives block cleanup: "+p);
        if(m.get("rendered_world_blocks").getAsInt()!=(emptyFrame?0:1)||m.get("screen").getAsInt()!=0||!m.get("hand_pass_rendered").getAsBoolean()||m.get("world_block_outline").getAsBoolean()==emptyFrame||m.get("terrain_depth_occlusion").getAsBoolean()!=depth||m.get("terrain_depth_boxes").getAsInt()!=(depth?1:0))throw new IllegalStateException("Depth render pass metadata differs: "+name);
        if(p.get("stray_opaque_samples").getAsLong()!=0||p.get("hand_opaque_samples").getAsLong()<100||p.get("hud_opaque_samples").getAsLong()<100)throw new IllegalStateException("Depth leaked colour or hid foreground: "+p);
        long baseline=p.get("baseline_samples").getAsLong(),present=p.get("retained_samples").getAsLong(),hidden=p.get("hidden_samples").getAsLong();
        if(emptyFrame||name.equals("hidden")){if(p.get("block_region_opaque_samples").getAsLong()!=0)throw new IllegalStateException("Occluded block or terrain colour remains: "+p);}
        else if(name.equals("visible")){if(p.get("block_region_opaque_samples").getAsLong()<1000)throw new IllegalStateException("Visible baseline missing");}
        else if(name.equals("partial")){if(baseline<1000||present<baseline*.15||hidden<baseline*.15||present+hidden<baseline*.98)throw new IllegalStateException("Partial depth must keep and hide actual block pixels: "+p);}
        else if(baseline<1000||present<baseline*.98)throw new IllegalStateException("Far terrain/return changed visible block alpha: "+p);
    }}
    private void complete(MinecraftClient c,boolean passed,String error){if(result!=null||finished)return;try{movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_depth_fixture_v1");j.addProperty("mode","depth");j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);j.addProperty("world_id",save.id().toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",true);j.addProperty("synthetic_render_surface",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("direct_command_api_used",false);j.addProperty("position_writes_used",false);j.addProperty("walking_verified",false);j.addProperty("render_pixels_verified",passed);j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("stage",stage);j.addProperty("index",index);var a=new JsonArray();commands.forEach(a::add);j.add("submitted_commands",a);a=new JsonArray();for(String name:NAMES)if(images.containsKey(name))a.add(images.get(name).deepCopy());j.add("images",a);j.add("blocks",blocks.evidence(c));result=j;pendingResult.set(j.deepCopy());}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private void writeSample(Sample sample)throws Exception{var f=sample.frame();var rgba=HudPixels.straightTopLeft(f.bottomUp(),f.width(),f.height());var png=HudPixels.png(rgba,f.width(),f.height());Path file=directory.resolve("depth-"+sample.name()+".png");Files.write(file,png,StandardOpenOption.CREATE_NEW);var p=new JsonObject();p.addProperty("stage",sample.name());p.addProperty("file",file.getFileName().toString());p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.add("metadata",JsonParser.parseString(f.metadata()));
        if(visiblePixels!=null&&(f.width()!=visibleWidth||f.height()!=visibleHeight))throw new IllegalStateException("Depth fixture framebuffer changed");
        long region=0,stray=0,baseline=0,retained=0,hidden=0,hand=0,hud=0;var v=sample.view();var right=v.forward().crossProduct(v.up()).normalize();double focal=f.height()/(2*Math.tan(v.verticalFovRadians()/2));var cube=new Box(sample.block()).expand(.04);
        // The mask is independent of the depth mesh. Compare actual baseline
        // pixels with later frames, including silhouette/outline pixels.
        for(int y=(int)(f.height()*.15);y<f.height()*.70;y+=2)for(int x=(int)(f.width()*.15);x<f.width()*.65;x+=2){if(Math.abs(x-f.width()/2)<22&&Math.abs(y-f.height()/2)<22)continue;int offset=(y*f.width()+x)*4+3;int alpha=rgba[offset]&255;var direction=v.forward().add(right.multiply((x+.5-f.width()/2.0)/focal)).add(v.up().multiply((f.height()/2.0-y-.5)/focal)).normalize();boolean inBlock=cube.raycast(v.origin(),v.origin().add(direction.multiply(6))).isPresent();
            if(inBlock){if(alpha>8)region++;if(visiblePixels!=null&&(visiblePixels[offset]&255)>8){baseline++;if(Math.abs(alpha-(visiblePixels[offset]&255))<=2)retained++;else if(alpha<=8)hidden++;}}else if(alpha>8)stray++;
        }
        for(int y=(int)(f.height()*.78);y<f.height()*.92;y+=2)for(int x=(int)(f.width()*.72);x<f.width()*.93;x+=2)if((rgba[(y*f.width()+x)*4+3]&255)>200)hand++;
        for(int y=(int)(f.height()*.95);y<f.height();y+=2)for(int x=(int)(f.width()*.37);x<f.width()*.63;x+=2)if((rgba[(y*f.width()+x)*4+3]&255)>200)hud++;
        p.addProperty("block_region_opaque_samples",region);p.addProperty("stray_opaque_samples",stray);p.addProperty("baseline_samples",baseline);p.addProperty("retained_samples",retained);p.addProperty("hidden_samples",hidden);p.addProperty("hand_opaque_samples",hand);p.addProperty("hud_opaque_samples",hud);
        p.add("layers",inspectLayers(f));
        if(sample.name().equals("visible")){visiblePixels=rgba;visibleWidth=f.width();visibleHeight=f.height();}images.put(sample.name(),p);
    }
    private static JsonObject inspectLayers(HudReadback.Completed frame){
        byte[] layers=frame.layersBottomUp();HudLayerPixels.require(layers,frame.width(),frame.height());
        int plane=HudPixels.byteSize(frame.width(),frame.height()),w=frame.width(),h=frame.height();
        var raw=java.nio.ByteBuffer.wrap(layers).order(java.nio.ByteOrder.LITTLE_ENDIAN);
        long world=0,worldDepth=0,depthPixels=0,overlayRegion=0,overlayHand=0,overlayHud=0,worldForeground=0;boolean valid=true;
        for(int i=0;i<plane;i+=4){float depth=raw.getFloat(plane*2+i);valid&=Float.isFinite(depth)&&depth>=0&&depth<=1;
            if(depth<1)depthPixels++;if((layers[plane+i+3]&255)>8){world++;if(depth>0&&depth<1)worldDepth++;}
        }
        // Same independent regions as the legacy flattened proof, now on each plane.
        for(int y=(int)(h*.15);y<h*.70;y+=2)for(int x=(int)(w*.15);x<w*.65;x+=2){
            if(Math.abs(x-w/2)<22&&Math.abs(y-h/2)<22)continue;
            if((layers[((h-1-y)*w+x)*4+3]&255)>8)overlayRegion++;
        }
        for(int y=(int)(h*.78);y<h*.92;y+=2)for(int x=(int)(w*.72);x<w*.93;x+=2){int pixel=((h-1-y)*w+x)*4+3;
            if((layers[pixel]&255)>200)overlayHand++;if((layers[plane+pixel]&255)>8)worldForeground++;
        }
        for(int y=(int)(h*.95);y<h;y+=2)for(int x=(int)(w*.37);x<w*.63;x+=2){int pixel=((h-1-y)*w+x)*4+3;
            if((layers[pixel]&255)>200)overlayHud++;if((layers[plane+pixel]&255)>8)worldForeground++;
        }
        var proof=new JsonObject();proof.addProperty("format",2);proof.addProperty("plane_bytes",plane);proof.addProperty("payload_bytes",layers.length);
        proof.addProperty("depth_finite_unit_range",valid);proof.addProperty("nonclear_depth_pixels",depthPixels);proof.addProperty("world_opaque_pixels",world);proof.addProperty("world_with_depth_pixels",worldDepth);
        proof.addProperty("overlay_world_region_samples",overlayRegion);proof.addProperty("overlay_hand_samples",overlayHand);proof.addProperty("overlay_hud_samples",overlayHud);proof.addProperty("world_foreground_samples",worldForeground);
        return proof;
    }
    private void writeLoop(){long seq=0;try{while(!closing){var sample=samples.poll();if(sample!=null)writeSample(sample);var proof=pendingResult.getAndSet(null);if(proof!=null){Files.writeString(directory.resolve("gameplay-depth-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());j.add("forward",json(new Vec3d(1,0,0)));j.add("up",json(new Vec3d(0,0,1)));Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json"));Thread.sleep(25);}}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
