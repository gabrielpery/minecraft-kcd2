package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.block.BlockState;
import net.minecraft.client.MinecraftClient;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.state.property.Property;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual vanilla placement, owned-state rendering and saved-world continuation. */
public final class GameplayWorldBlocksFixture {
    private static final String WITNESS="minecome-world-blocks-fixture.json";
    private static final List<String> ITEMS=List.of("dirt","oak_planks","bricks","oak_log");
    private static final double PITCH=Math.toRadians(25);
    private static final Vec3d FORWARD=new Vec3d(Math.cos(PITCH),-Math.sin(PITCH),0),UP=new Vec3d(Math.sin(PITCH),Math.cos(PITCH),0);
    private record State(long at,Vec3d position,int selected,String item,List<String> blocks){}
    private record Sample(String stage,HudReadback.Completed frame){}
    private final String mode;private final GameplayBlocks blocks;private final GameplayMovement movement;private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;private final Path directory,witness;private final Consumer<JsonObject> completed;
    private final JsonObject expected;private final AtomicReference<State> observed=new AtomicReference<>();private final AtomicBoolean observing=new AtomicBoolean();
    private final AtomicReference<String> failure=new AtomicReference<>();private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>(),pendingWitness=new AtomicReference<>();
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(2);private final Map<String,JsonObject> images=new ConcurrentHashMap<>();private final Set<String> queued=new HashSet<>();
    private final List<String> commands=new ArrayList<>();private final List<BlockPos> cells=new ArrayList<>();private final List<String> desired=new ArrayList<>();
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;
    private long begun,stageAt,actionAt,sequence;private int stage,index,ticks;private Vec3d target;private boolean terrainTarget,finished,resumeVerified;private volatile boolean closing,written;private volatile long viewWrites;private JsonObject result;

    public GameplayWorldBlocksFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(!Set.of("world-blocks","world-blocks-resume").contains(mode)||!Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayWorldBlocks"))throw new IllegalArgumentException("Explicit standalone world-block fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;this.directory=directory.toRealPath();witness=save.directory().resolve(WITNESS);save.verifyOwnership();
        if(Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-world-blocks-fixture.json")))throw new IOException("World-block fixture output exists");
        if(mode.equals("world-blocks")){if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("First world-block fixture needs a new save");expected=null;}
        else {if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness)||Files.size(witness)>16384)throw new IOException("Resume requires owned witness");expected=JsonParser.parseString(Files.readString(witness)).getAsJsonObject();if(expected.get("schema").getAsInt()!=1||!expected.get("world_id").getAsString().equals(save.id().toString()))throw new IOException("Witness identity differs");}
        var worker=new Thread(this::writeLoop,"MineComeWorldBlocksFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0||result!=null)return;try{requireOwner(c);movement.authority(c,System.nanoTime(),true);refreshAim(c);}catch(Exception e){complete(c,false,e.toString());}}
    public GameplayWorldRenderer.View view(){var c=MinecraftClient.getInstance();return begun==0||closing||finished||c.player!=player?null:new GameplayWorldRenderer.View(c.player.getEyePos(),FORWARD,UP,Math.toRadians(70));}
    public void tick(MinecraftClient c){if(closing||finished)return;try{
        if(result!=null){movement.suspend(c);blocks.suspend(c);if(written||failure.get()!=null){if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}finished=true;completed.accept(result.deepCopy());}return;}
        if(failure.get()!=null)throw new IllegalStateException(failure.get());if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);requireOwner(c);long now=System.nanoTime();
        if(now-begun>50_000_000_000L||now-stageAt>8_000_000_000L)throw new IllegalStateException("World-block fixture deadline: stage="+stage+", index="+index+", controller="+blocks.evidence(c));
        observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;ticks++;refreshAim(c);
        if(expected==null)create(c,s,now);else resume(c,s,now);
    }catch(Exception e){complete(c,false,e.toString());}}
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||!c.isIntegratedServerRunning()||c.getServer()==null)throw new IllegalStateException("Owned integrated client required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);
        var base=BlockPos.ofFloored(2.5,movement.surface().heightAt(2.5,.5),.5);cells.addAll(List.of(base,base.up(),base.west(),base.up().west()));
        desired.addAll(List.of("minecraft:dirt","minecraft:oak_planks","minecraft:bricks","minecraft:oak_log[axis=x]"));
        if(expected!=null){if(!expected.get("player_id").getAsString().equals(playerId.toString()))throw new IllegalStateException("Saved player identity changed");var positions=expected.getAsJsonArray("cells");for(int i=0;i<4;i++)if(!json(cells.get(i)).equals(positions.get(i)))throw new IllegalStateException("Saved build coordinates differ");}
        begun=stageAt=System.nanoTime();key(c,'9');
    }
    private void create(MinecraftClient c,State s,long now){switch(stage){
        case 0->{if(!matches(c,s,0)||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("Initial cells occupied");if(images.containsKey("empty")){prepare(c);next(1,now);}}
        case 1->{if(s.selected()!=0||!s.item().equals("minecraft:"+ITEMS.get(index))||c.player.getInventory().selectedSlot!=0||!Registries.ITEM.getId(c.player.getMainHandStack().getItem()).toString().equals(s.item()))return;placeTarget();click(c,1);actionAt=now;next(2,now);}
        case 2->{if(s.at()<=actionAt||now-actionAt<250_000_000L||blocks.evidence(c).get("pending").getAsBoolean())return;if(!matches(c,s,index+1)||blocks.ownedBlocks().size()!=index+1)throw new IllegalStateException("Vanilla placement/state did not confirm: "+blocks.evidence(c)+" states="+s.blocks());key(c,'9');next(3,now);}
        case 3->{if(images.containsKey(ITEMS.get(index))){index++;if(index==4){key(c,'E');next(4,now);}else{prepare(c);next(1,now);}}}
        case 4->{if(!HudVanillaUiAdapter.inventory(c.currentScreen)||!matches(c,s,4)||blocks.ownedBlocks().size()!=4)throw new IllegalStateException("Inventory transition changed owned blocks or did not open");if(images.containsKey("inventory")){key(c,'E');next(5,now);}}
        case 5->{if(c.currentScreen!=null||!matches(c,s,4)||blocks.ownedBlocks().size()!=4)throw new IllegalStateException("Inventory close changed owned blocks or did not restore world");if(images.containsKey("restored")){validateImages();var w=new JsonObject();w.addProperty("schema",1);w.addProperty("world_id",save.id().toString());w.addProperty("player_id",playerId.toString());var a=new JsonArray();cells.forEach(p->a.add(json(p)));w.add("cells",a);w.add("position",json(s.position()));pendingWitness.set(w);complete(c,true,null);}}
        default->throw new IllegalStateException("Unknown create stage");
    }}
    private void resume(MinecraftClient c,State s,long now){switch(stage){
        case 0->{if(!matches(c,s,4)||!blocks.ownedBlocks().equals(Set.copyOf(cells)))throw new IllegalStateException("Saved block identities/properties were not restored: "+s.blocks());if(!movement.evidence(c).get("resume_position_restored").getAsBoolean()||s.position().distanceTo(vector(expected.getAsJsonObject("position")))>.04)throw new IllegalStateException("Saved player position differs");resumeVerified=true;if(images.containsKey("resumed")){index=3;next(1,now);}}
        case 1->{var p=cells.get(index);target=new Vec3d(p.getX(),p.getY()+.5,p.getZ()+.5);terrainTarget=false;click(c,0);actionAt=now;next(2,now);}
        case 2->{if(s.at()<=actionAt||now-actionAt<250_000_000L||blocks.evidence(c).get("pending").getAsBoolean())return;if(!matches(c,s,index)||blocks.ownedBlocks().size()!=index)throw new IllegalStateException("Saved block could not be mined: "+blocks.evidence(c)+" states="+s.blocks());index--;next(index<0?3:1,now);}
        case 3->{if(images.containsKey("cleared")){validateImages();complete(c,true,null);}}
        default->throw new IllegalStateException("Unknown resume stage");
    }}
    private void prepare(MinecraftClient c){command(c,"item replace entity @s hotbar.0 with minecraft:"+ITEMS.get(index));key(c,'1');}
    private void placeTarget(){var base=cells.get(0);terrainTarget=index==0;target=switch(index){case 0->new Vec3d(2.5,movement.surface().heightAt(2.5,.5),.5);case 1->new Vec3d(base.getX()+.5,base.getY()+1,base.getZ()+.5);case 2->new Vec3d(base.getX(),base.getY()+.5,base.getZ()+.5);case 3->new Vec3d(base.getX(),base.getY()+1.5,base.getZ()+.5);default->throw new IllegalStateException();};}
    private void click(MinecraftClient c,int button){refreshAim(c);blocks.event(c,event(7,button));blocks.event(c,event(8,button));}
    private void refreshAim(MinecraftClient c){if(target==null)return;var eye=c.player.getEyePos();var delta=target.subtract(eye);double distance=delta.length();if(distance<=0||distance>4.5)throw new IllegalStateException("Target outside vanilla reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,terrainTarget?distance:-1,terrainTarget));}
    private boolean matches(MinecraftClient c,State s,int count){for(int i=0;i<4;i++){String want=i<count?desired.get(i):"minecraft:air";if(!want.equals(s.blocks().get(i))||!want.equals(state(c.world.getBlockState(cells.get(i)))))return false;}return true;}
    private void next(int next,long now){stage=next;stageAt=now;ticks=0;}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void command(MinecraftClient c,String command){movement.suspend(c);key(c,0xbf);if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Command field failed");command.codePoints().forEach(cp->ui.apply(c,event(9,cp)));if(!ui.chatText(c).equals("/"+command))throw new IllegalStateException("Command text differs");ui.apply(c,event(10,13));ui.apply(c,event(11,13));if(c.currentScreen!=null)throw new IllegalStateException("Command did not submit");commands.add("/"+command);}
    public String captureStage(){if(closing||finished||result!=null||begun==0||ticks<12)return null;String name=expected==null?(stage==0?"empty":stage==3?ITEMS.get(index):stage==4?"inventory":stage==5?"restored":null):(stage==0?"resumed":stage==3?"cleared":null);return name==null||queued.contains(name)||images.containsKey(name)?null:name;}
    public void captured(HudReadback.Completed frame){if(closing||finished||result!=null)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("world_blocks_fixture_stage"))return;String name=meta.get("world_blocks_fixture_stage").getAsString();if(!names().contains(name)||!queued.add(name))return;if(!samples.offer(new Sample(name,frame)))failure.compareAndSet(null,"World-block image queue full");}
    private List<String> names(){return expected==null?List.of("empty","dirt","oak_planks","bricks","oak_log","inventory","restored"):List.of("resumed","cleared");}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Fixture server owner changed");var states=new ArrayList<String>();for(var cell:cells)states.add(state(server.getOverworld().getBlockState(cell)));observed.set(new State(System.nanoTime(),p.getPos(),p.getInventory().selectedSlot,Registries.ITEM.getId(p.getMainHandStack().getItem()).toString(),List.copyOf(states)));}catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Fixture client owner changed");}
    private void validateImages(){String previous=null;for(String name:names()){
        var p=images.get(name);if(p==null)throw new IllegalStateException("Missing image "+name);var meta=p.getAsJsonObject("metadata");boolean inventory=name.equals("inventory");
        int count=Set.of("resumed","inventory","restored").contains(name)?4:name.equals("cleared")||name.equals("empty")?0:ITEMS.indexOf(name)+1;
        if(meta.get("rendered_world_blocks").getAsInt()!=count||meta.get("world_block_pixels").getAsBoolean()!=(count>0))throw new IllegalStateException("Actual owned render count differs: "+name);
        if(meta.get("hand_pass_rendered").getAsBoolean()==inventory||meta.get("screen").getAsInt()!=(inventory?1:0)||!meta.get("screen_kind").getAsString().equals(inventory?"CreativeInventoryScreen":"none"))throw new IllegalStateException("Inventory/hand rendering differs: "+name);
        // Vanilla inventory intentionally dims every background pixel. Only
        // ordinary world frames must retain clear pixels outside owned models.
        if(!inventory&&(p.get("clear_region_pixels").getAsLong()!=0||p.get("transparent_pixels").getAsLong()<p.get("pixels").getAsLong()*.25))throw new IllegalStateException("Opaque world leaked: "+name);
        if(count>0&&p.get("world_region_pixels").getAsLong()<200)throw new IllegalStateException("Missing block geometry: "+name);String hash=p.get("world_region_sha256").getAsString();if(hash.equals(previous))throw new IllegalStateException("Block geometry/image did not change");previous=hash;
    }}
    private void complete(MinecraftClient c,boolean passed,String error){if(result!=null||finished)return;try{movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_world_blocks_fixture_v1");j.addProperty("mode",mode);j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("direct_command_api_used",false);j.addProperty("position_writes_used",false);j.addProperty("render_pixels_verified",passed);j.addProperty("resume_verified",resumeVerified);j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("stage",stage);j.addProperty("index",index);j.addProperty("scripted_view_writes",viewWrites);var a=new JsonArray();commands.forEach(a::add);j.add("submitted_commands",a);a=new JsonArray();for(String name:names())if(images.containsKey(name))a.add(images.get(name).deepCopy());j.add("images",a);j.add("blocks",blocks.evidence(c));j.add("movement",movement.evidence(c));var s=observed.get();if(s!=null){a=new JsonArray();s.blocks().forEach(a::add);j.add("actual_states",a);j.add("server_position",json(s.position()));}result=j;pendingResult.set(j.deepCopy());}
    private static <T extends Comparable<T>> String value(Property<T> p,Comparable<?> v){return p.name((T)v);}
    private static String state(BlockState s){String id=Registries.BLOCK.getId(s.getBlock()).toString();if(s.getEntries().isEmpty())return id;var props=new TreeMap<String,String>();s.getEntries().forEach((p,v)->props.put(p.getName(),value(p,v)));return id+"["+String.join(",",props.entrySet().stream().map(e->e.getKey()+"="+e.getValue()).toList())+"]";}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static JsonObject json(BlockPos p){return json(Vec3d.of(p));}
    private static Vec3d vector(JsonObject j){return new Vec3d(j.get("x").getAsDouble(),j.get("y").getAsDouble(),j.get("z").getAsDouble());}
    private void writeSample(Sample sample)throws Exception{var f=sample.frame();byte[] rgba=HudPixels.straightTopLeft(f.bottomUp(),f.width(),f.height()),png=HudPixels.png(rgba,f.width(),f.height());Path file=directory.resolve("world-blocks-"+sample.stage()+".png");Files.write(file,png,StandardOpenOption.CREATE_NEW);long transparent=0,opaque=0,worldPixels=0,clear=0;var digest=MessageDigest.getInstance("SHA-256");for(int y=0;y<f.height();y++)for(int x=0;x<f.width();x++){int i=(y*f.width()+x)*4,a=rgba[i+3]&255;if(a==0)transparent++;if(a==255)opaque++;if(x>=f.width()*.15&&x<f.width()*.65&&y>=f.height()*.15&&y<f.height()*.85){digest.update(rgba,i,4);if(a!=0)worldPixels++;}if(x>=f.width()*.02&&x<f.width()*.2&&y>=f.height()*.05&&y<f.height()*.2&&a!=0)clear++;}var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file.getFileName().toString());p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.addProperty("pixels",(long)f.width()*f.height());p.addProperty("width",f.width());p.addProperty("height",f.height());p.addProperty("transparent_pixels",transparent);p.addProperty("opaque_pixels",opaque);p.addProperty("world_region_pixels",worldPixels);p.addProperty("clear_region_pixels",clear);p.addProperty("world_region_sha256",HexFormat.of().formatHex(digest.digest()));p.add("metadata",JsonParser.parseString(f.metadata()));images.put(sample.stage(),p);}
    private void writeLoop(){long seq=0;try{while(!closing){var sample=samples.poll();if(sample!=null)writeSample(sample);var proof=pendingResult.getAndSet(null);if(proof!=null){var w=pendingWitness.getAndSet(null);if(w!=null){save.verifyOwnership();Files.writeString(witness,w.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}Files.writeString(directory.resolve("gameplay-world-blocks-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());j.add("forward",json(new Vec3d(FORWARD.x,0,FORWARD.y)));j.add("up",json(new Vec3d(UP.x,0,UP.y)));Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);}}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
