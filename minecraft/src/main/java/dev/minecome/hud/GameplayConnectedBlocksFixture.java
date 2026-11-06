package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayBlocksPalette;
import net.minecraft.block.FenceBlock;
import net.minecraft.block.WallBlock;
import net.minecraft.block.BlockRenderType;
import net.minecraft.state.property.Properties;
import net.minecraft.util.Identifier;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.block.ShapeContext;
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

/** Real fence/wall placement, neighbor connections, collision support and save/reopen. */
public final class GameplayConnectedBlocksFixture {
    private static final String WITNESS="minecome-connected-fixture.json",AIR="minecraft:air";
    private static final Vec3d EAST=new Vec3d(1,0,0);
    private record State(long at,Vec3d position,float yaw,int selected,String item,List<String> states,List<Double> collisionVolumes,List<Double> support){}
    private record Step(String name,int button,String item,Vec3d target,boolean terrain,Vec3d facing,List<String> states,int focus){}
    private record Sample(String stage,HudReadback.Completed frame,GameplayWorldRenderer.View view,BlockPos focus,List<Box> shapes){}
    private final String mode;private final GameplayBlocks blocks;private final GameplayMovement movement;private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;private final Path directory,witness;private final Consumer<JsonObject> completed;private final JsonObject expected;
    private final AtomicReference<State> observed=new AtomicReference<>();private final AtomicBoolean observing=new AtomicBoolean();private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>(),pendingWitness=new AtomicReference<>();
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(2);private final Map<String,JsonObject> images=new ConcurrentHashMap<>();private final Set<String> queued=new HashSet<>();
    private final List<BlockPos> cells=new ArrayList<>();private final List<Step> steps=new ArrayList<>();private final List<String> commands=new ArrayList<>();private final List<JsonObject> shapeChecks=new ArrayList<>();
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;
    private long begun,stageAt,actionAt,sequence;private int stage,index,ticks;private boolean finished,resumeVerified;private volatile boolean closing,written;private volatile long viewWrites;
    private volatile Vec3d hostForward=EAST;private JsonObject result;private int registryBlocksVerified,registryStatesVerified;

    public GameplayConnectedBlocksFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(!Set.of("connected","connected-resume").contains(mode)||!Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayWorldBlocks"))throw new IllegalArgumentException("Explicit standalone shape fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;this.directory=directory.toRealPath();witness=save.directory().resolve(WITNESS);save.verifyOwnership();
        if(Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-connected-fixture.json")))throw new IOException("Shape fixture output exists");
        if(mode.equals("connected")){if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("New shape fixture save required");expected=null;}
        else{if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness)||Files.size(witness)>16384)throw new IOException("Owned shape witness required");expected=JsonParser.parseString(Files.readString(witness)).getAsJsonObject();if(expected.get("schema").getAsInt()!=1||!expected.get("world_id").getAsString().equals(save.id().toString()))throw new IOException("Shape witness identity differs");}
        var worker=new Thread(this::writeLoop,"MineComeConnectedFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0||result!=null)return;try{requireOwner(c);movement.authority(c,System.nanoTime(),true);refreshAim(c);}catch(Exception e){complete(c,false,e.toString());}}
    private int focus(){return stage==0?0:steps.get(index).focus();}
    public GameplayWorldRenderer.View view(){var c=MinecraftClient.getInstance();if(begun==0||closing||finished||c.player!=player)return null;var eye=c.player.getEyePos();var f=Vec3d.ofCenter(cells.get(focus())).subtract(eye).normalize();var right=f.crossProduct(new Vec3d(0,1,0)).normalize();return new GameplayWorldRenderer.View(eye,f,right.crossProduct(f).normalize(),Math.toRadians(70));}
    public GameplayBlocks.Aim renderAim(){var v=view();if(v==null)return null;var cell=cells.get(focus());var state=MinecraftClient.getInstance().world.getBlockState(cell);if(state.isAir())return null;
        // Use the actual render camera ray, never a separate guessed hover box.
        var shape=state.getOutlineShape(MinecraftClient.getInstance().world,cell,ShapeContext.of(MinecraftClient.getInstance().player));
        var hit=shape.raycast(v.origin(),v.origin().add(v.forward().multiply(4.5)),cell);
        return hit==null?null:new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),v.origin(),v.forward(),4.5,true,-1,false);
    }
    public void tick(MinecraftClient c){if(closing||finished)return;try{
        if(result!=null){movement.suspend(c);blocks.suspend(c);if(written||failure.get()!=null){if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}finished=true;completed.accept(result.deepCopy());}return;}
        if(failure.get()!=null)throw new IllegalStateException(failure.get());if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);requireOwner(c);long now=System.nanoTime();
        if(now-begun>55_000_000_000L||now-stageAt>8_000_000_000L)throw new IllegalStateException("Shape fixture deadline stage="+stage+" step="+index+" controller="+blocks.evidence(c));
        observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;ticks++;refreshAim(c);
        switch(stage){
            case 0->{var want=expected==null?states(AIR,AIR,AIR,AIR):savedStates();requireStates(c,s,want);if(expected!=null){if(!playerId.toString().equals(expected.get("player_id").getAsString())||!movement.evidence(c).get("resume_position_restored").getAsBoolean()||s.position().distanceTo(vector(expected.getAsJsonObject("position")))>.04)throw new IllegalStateException("Saved shape/player restoration differs");resumeVerified=true;}
                if(images.containsKey(expected==null?"empty":"resumed")){prepare(c);next(1,now);}}
            case 1->{var step=steps.get(index);if(step.item()!=null&&(s.selected()!=0||c.player.getInventory().selectedSlot!=0||!s.item().equals("minecraft:"+step.item())||!Registries.ITEM.getId(c.player.getMainHandStack().getItem()).toString().equals(s.item())))return;
                float yaw=-90;if(Math.abs(MathHelper.wrapDegrees(s.yaw()-yaw))>.2||Math.abs(MathHelper.wrapDegrees(c.player.getYaw()-yaw))>.2)return;
                refreshAim(c);blocks.event(c,event(7,step.button()));blocks.event(c,event(8,step.button()));actionAt=now;next(2,now);}
            case 2->{if(s.at()<=actionAt||now-actionAt<250_000_000L||blocks.evidence(c).get("pending").getAsBoolean())return;requireStates(c,s,steps.get(index).states());verifyShapes(c,s);key(c,'9');next(3,now);}
            case 3->{if(images.containsKey(steps.get(index).name())){index++;if(index==steps.size()){index--;validateImages();if(expected==null){var w=new JsonObject();w.addProperty("schema",1);w.addProperty("world_id",save.id().toString());w.addProperty("player_id",playerId.toString());w.addProperty("connected_states_verified",true);w.add("position",json(s.position()));pendingWitness.set(w);}complete(c,true,null);}else{prepare(c);next(1,now);}}}
            default->throw new IllegalStateException("Unknown shape stage");
        }
    }catch(Exception e){complete(c,false,e.toString());}}
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||!c.isIntegratedServerRunning()||c.getServer()==null)throw new IllegalStateException("Owned integrated client required");save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);
        verifyRegistry();
        int y=(int)Math.floor(movement.surface().heightAt(2.5,.5));
        if(Math.abs(movement.surface().heightAt(-1.5,-.5)-y)>1e-6)throw new IllegalStateException("Flat connected fixture terrain required");
        cells.addAll(List.of(new BlockPos(2,y,0),new BlockPos(2,y,-1),new BlockPos(-2,y,0),new BlockPos(-2,y,-1)));
        if(expected==null){
            steps.add(new Step("fence_single",1,"oak_fence",new Vec3d(2.5,y,.5),true,EAST,states(fence(false,false),AIR,AIR,AIR),0));
            steps.add(new Step("fence_connected",1,"oak_fence",new Vec3d(2.5,y,-.5),true,EAST,states(fence(true,false),fence(false,true),AIR,AIR),0));
            steps.add(new Step("fence_restored",0,null,new Vec3d(2.5,y+.5,-.5),false,EAST,states(fence(false,false),AIR,AIR,AIR),0));
            steps.add(new Step("wall_single",1,"cobblestone_wall",new Vec3d(-1.5,y,.5),true,EAST,states(fence(false,false),AIR,wall(false,false),AIR),2));
            steps.add(new Step("wall_connected",1,"cobblestone_wall",new Vec3d(-1.5,y,-.5),true,EAST,states(fence(false,false),AIR,wall(true,false),wall(false,true)),2));
            steps.add(new Step("wall_restored",0,null,new Vec3d(-1.5,y+.5,-.5),false,EAST,savedStates(),2));
        }else{
            steps.add(new Step("mined_fence",0,null,new Vec3d(2.5,y+.5,.5),false,EAST,states(AIR,AIR,wall(false,false),AIR),2));
            steps.add(new Step("cleared",0,null,new Vec3d(-1.5,y+.5,.5),false,EAST,states(AIR,AIR,AIR,AIR),2));
        }
        begun=stageAt=System.nanoTime();key(c,'9');
    }
    private void verifyRegistry(){
        for(var id:GameplayBlocksPalette.blockIds()){
            if(!id.endsWith("_fence")&&!id.endsWith("_wall"))continue;
            var block=Registries.BLOCK.get(Identifier.of(id));
            if(!(block instanceof FenceBlock)&&!(block instanceof WallBlock))throw new IllegalStateException("Connected palette registry type differs: "+id);
            registryBlocksVerified++;
            for(var state:block.getStateManager().getStates())if(!state.get(Properties.WATERLOGGED)){
                if(!GameplayBlocksPalette.supportsState(GameplayBlocks.stateName(state))||state.getRenderType()!=BlockRenderType.MODEL)throw new IllegalStateException("Connected vanilla state rejected: "+state);
                registryStatesVerified++;
            }
        }
        if(registryBlocksVerified!=22||registryStatesVerified!=1812)throw new IllegalStateException("Connected registry state coverage differs");
    }
    private static String fence(boolean north,boolean south){return "minecraft:oak_fence[east=false,north="+north+",south="+south+",waterlogged=false,west=false]";}
    private static String wall(boolean north,boolean south){return "minecraft:cobblestone_wall[east=none,north="+(north?"low":"none")+",south="+(south?"low":"none")+",up=true,waterlogged=false,west=none]";}
    private static List<String> states(String... states){return List.of(states);}
    private static List<String> savedStates(){return states(fence(false,false),AIR,wall(false,false),AIR);}
    private void prepare(MinecraftClient c){var s=steps.get(index);hostForward=s.facing();if(s.item()!=null){command(c,"item replace entity @s hotbar.0 with minecraft:"+s.item());key(c,'1');}}
    private void refreshAim(MinecraftClient c){if(stage==0)return;var step=steps.get(index);var eye=c.player.getEyePos();var delta=step.target().subtract(eye);double distance=delta.length();if(distance<=0||distance>4.5)throw new IllegalStateException("Shape action outside reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,step.terrain()?distance:-1,step.terrain()));}
    private void requireStates(MinecraftClient c,State s,List<String> want){int count=0;for(int i=0;i<cells.size();i++){if(!want.get(i).equals(s.states().get(i))||!want.get(i).equals(GameplayBlocks.stateName(c.world.getBlockState(cells.get(i)))))throw new IllegalStateException("Shape state differs step="+index+" expected="+want+" actual="+s.states()+" controller="+blocks.evidence(c));if(!want.get(i).equals(AIR))count++;}if(blocks.ownedBlocks().size()!=count)throw new IllegalStateException("Shape ownership count differs");}
    private static double volume(List<Box> boxes){double n=0;for(var b:boxes)n+=(b.maxX-b.minX)*(b.maxY-b.minY)*(b.maxZ-b.minZ);return n;}
    // Pinned FenceBlock/WallBlock collision constructors use 24/16 height;
    // rendered outline/model height is separate (runtime/evidence/connected-shapes-source-20261106).
    private static Vec3d supportPoint(BlockPos p,String state){return new Vec3d(p.getX()+.5,p.getY()+1.5,p.getZ()+.5);}
    private void verifyShapes(MinecraftClient c,State s){var proof=new JsonObject();proof.addProperty("stage",steps.get(index).name());var a=new JsonArray();
        for(int i=0;i<cells.size();i++){String state=s.states().get(i);var p=cells.get(i);var actual=c.world.getBlockState(p);var shape=actual.getCollisionShape(c.world,p,ShapeContext.of(c.player));double volume=volume(shape.getBoundingBoxes());
            if(Math.abs(volume-s.collisionVolumes().get(i))>1e-8||(!state.equals(AIR)&&(volume<=0||volume>=1.5||Math.abs(shape.getMax(Direction.Axis.Y)-1.5)>1e-8)))throw new IllegalStateException("Connected collision shape differs: "+state);
            if(!state.equals(AIR)){var point=supportPoint(p,state);double support=blocks.groundForFeet(c.world,point.x,point.y,point.z,.1);if(Math.abs(support-point.y)>1e-6||Math.abs(s.support().get(i)-point.y)>1e-6)throw new IllegalStateException("Connected support must be 1.5 blocks high: "+state);}
            var item=new JsonObject();item.addProperty("state",state);item.addProperty("collision_volume",volume);item.addProperty("server_collision_volume",s.collisionVolumes().get(i));item.addProperty("support_y",s.support().get(i));a.add(item);
        }proof.add("cells",a);shapeChecks.add(proof);
    }
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Shape fixture server owner changed");var states=new ArrayList<String>();var volumes=new ArrayList<Double>();var support=new ArrayList<Double>();for(var cell:cells){var b=server.getOverworld().getBlockState(cell);String state=GameplayBlocks.stateName(b);states.add(state);volumes.add(volume(b.getCollisionShape(server.getOverworld(),cell,ShapeContext.of(p)).getBoundingBoxes()));var q=supportPoint(cell,state);support.add(blocks.groundForFeet(server.getOverworld(),q.x,q.y,q.z,.1));}observed.set(new State(System.nanoTime(),p.getPos(),p.getYaw(),p.getInventory().selectedSlot,Registries.ITEM.getId(p.getMainHandStack().getItem()).toString(),List.copyOf(states),List.copyOf(volumes),List.copyOf(support)));}catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Shape fixture owner changed");}
    private void next(int value,long now){stage=value;stageAt=now;ticks=0;}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void command(MinecraftClient c,String command){movement.suspend(c);key(c,0xbf);if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Shape command screen absent");command.codePoints().forEach(cp->ui.apply(c,event(9,cp)));if(!ui.chatText(c).equals("/"+command))throw new IllegalStateException("Shape command text differs");ui.apply(c,event(10,13));ui.apply(c,event(11,13));if(c.currentScreen!=null)throw new IllegalStateException("Shape command did not submit");commands.add("/"+command);}
    private List<String> names(){var names=new ArrayList<String>();names.add(expected==null?"empty":"resumed");steps.forEach(s->names.add(s.name()));return names;}
    public String captureStage(){if(closing||finished||result!=null||begun==0||ticks<12)return null;String name=stage==0?(expected==null?"empty":"resumed"):stage==3?steps.get(index).name():null;return name==null||queued.contains(name)||images.containsKey(name)?null:name;}
    public void captured(HudReadback.Completed frame){if(closing||finished||result!=null)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("world_blocks_fixture_stage"))return;String name=meta.get("world_blocks_fixture_stage").getAsString();if(!names().contains(name)||!queued.add(name))return;var c=MinecraftClient.getInstance();var shapes=new ArrayList<Box>();for(var cell:blocks.ownedBlocks())for(var box:c.world.getBlockState(cell).getOutlineShape(c.world,cell,ShapeContext.of(c.player)).getBoundingBoxes())shapes.add(box.offset(cell));if(!samples.offer(new Sample(name,frame,view(),cells.get(focus()),List.copyOf(shapes))))failure.compareAndSet(null,"Shape image queue full");}
    private int countFor(String name){return switch(name){case "empty","cleared"->0;case "fence_single","fence_restored","mined_fence"->1;case "wall_connected"->3;default->2;};}
    private void validateImages(){for(var name:names()){var p=images.get(name);if(p==null)throw new IllegalStateException("Missing connected image: "+name);var meta=p.getAsJsonObject("metadata");int count=countFor(name);
        if(meta.get("rendered_world_blocks").getAsInt()!=count||meta.get("screen").getAsInt()!=0||!meta.get("hand_pass_rendered").getAsBoolean()||meta.get("world_block_outline").getAsBoolean()!=(count>0))throw new IllegalStateException("Connected render/hover metadata differs: "+name);
        if(count>0&&(p.get("occupied_samples").getAsLong()<20||p.get("occupied_mismatches").getAsLong()>p.get("occupied_samples").getAsLong()*.02||p.get("empty_samples").getAsLong()<20||p.get("empty_mismatches").getAsLong()>p.get("empty_samples").getAsLong()*.02))throw new IllegalStateException("Connected solid post or open space pixels absent: "+name+" proof="+p);
    }}
    private void complete(MinecraftClient c,boolean passed,String error){if(result!=null||finished)return;try{movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_connected_fixture_v1");j.addProperty("mode",mode);j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("direct_command_api_used",false);j.addProperty("position_writes_used",false);j.addProperty("walking_verified",false);j.addProperty("render_pixels_verified",passed);j.addProperty("shape_support_verified",passed);j.addProperty("resume_verified",resumeVerified);j.addProperty("registry_blocks_verified",registryBlocksVerified);j.addProperty("registry_states_verified",registryStatesVerified);j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("stage",stage);j.addProperty("index",index);var a=new JsonArray();commands.forEach(a::add);j.add("submitted_commands",a);a=new JsonArray();for(String name:names())if(images.containsKey(name))a.add(images.get(name).deepCopy());j.add("images",a);a=new JsonArray();shapeChecks.forEach(a::add);j.add("shape_checks",a);j.add("blocks",blocks.evidence(c));var s=observed.get();if(s!=null){a=new JsonArray();s.states().forEach(a::add);j.add("actual_states",a);j.add("server_position",json(s.position()));}result=j;pendingResult.set(j.deepCopy());}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static Vec3d vector(JsonObject j){return new Vec3d(j.get("x").getAsDouble(),j.get("y").getAsDouble(),j.get("z").getAsDouble());}
    private void writeSample(Sample sample)throws Exception{var f=sample.frame();var rgba=HudPixels.straightTopLeft(f.bottomUp(),f.width(),f.height());var png=HudPixels.png(rgba,f.width(),f.height());Path file=directory.resolve("connected-"+sample.stage()+".png");Files.write(file,png,StandardOpenOption.CREATE_NEW);var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file.getFileName().toString());p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.add("metadata",JsonParser.parseString(f.metadata()));
        long occupied=0,empty=0,badOccupied=0,badEmpty=0;var v=sample.view();var right=v.forward().crossProduct(v.up()).normalize();double focal=f.height()/(2*Math.tan(v.verticalFovRadians()/2));var cube=new Box(sample.focus()).contract(.04);var post=new Box(sample.focus().getX()+.4,sample.focus().getY()+.1,sample.focus().getZ()+.4,sample.focus().getX()+.6,sample.focus().getY()+.9,sample.focus().getZ()+.6);
        // Test opaque post interior and space outside every outline, excluding edges,
        // crosshair, hand and HUD. Fence outline boxes fill the spaces between rails,
        // so their other interior pixels are deliberately not treated as solid.
        for(int y=(int)(f.height()*.15);y<f.height()*.7;y+=3)for(int x=(int)(f.width()*.2);x<f.width()*.65;x+=3){if(Math.abs(x-f.width()/2)<20&&Math.abs(y-f.height()/2)<20)continue;var direction=v.forward().add(right.multiply((x+.5-f.width()/2.0)/focal)).add(v.up().multiply((f.height()/2.0-y-.5)/focal)).normalize();var end=v.origin().add(direction.multiply(6));if(cube.raycast(v.origin(),end).isEmpty())continue;boolean inside=post.raycast(v.origin(),end).isPresent(),near=false;for(var b:sample.shapes()){if(b.expand(.025).raycast(v.origin(),end).isPresent())near=true;}int alpha=rgba[(y*f.width()+x)*4+3]&255;if(inside){occupied++;if(alpha<200)badOccupied++;}else if(!near){empty++;if(alpha>8)badEmpty++;}}
        p.addProperty("occupied_samples",occupied);p.addProperty("occupied_mismatches",badOccupied);p.addProperty("empty_samples",empty);p.addProperty("empty_mismatches",badEmpty);images.put(sample.stage(),p);
    }
    private void writeLoop(){long seq=0;try{while(!closing){var sample=samples.poll();if(sample!=null)writeSample(sample);var proof=pendingResult.getAndSet(null);if(proof!=null){var w=pendingWitness.getAndSet(null);if(w!=null){save.verifyOwnership();Files.writeString(witness,w.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}Files.writeString(directory.resolve("gameplay-connected-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}var f=hostForward;var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());j.add("forward",json(new Vec3d(f.x,-f.z,f.y)));j.add("up",json(new Vec3d(0,0,1)));Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);}}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
