package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.terrain.*;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.item.Items;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual Minecraft movement/building over explicitly synthetic, dynamically admitted terrain. */
public final class GameplayTerrainFixture {
    private static final String WITNESS="minecome-terrain-fixture.json";
    private record State(long at,Vec3d position,int base,int upper,int stones){}
    private final String mode,tileJson,tileHash;
    private final GameplayBlocks blocks;private final GameplayMovement movement;private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;private final Path directory,witness;
    private final Consumer<JsonObject> completed;private final JsonObject expected;
    private final AtomicReference<State> observed=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicReference<JsonObject> ack=new AtomicReference<>(),pendingResult=new AtomicReference<>(),pendingWitness=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean(),admissionRequested=new AtomicBoolean();
    private volatile boolean closing,written,admissionWritten;private volatile long viewWrites;
    private volatile BlockPos base;
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;
    private Vec3d target,initial,inventoryStart,beforeLate;private boolean terrainTarget,sent,finished;
    private boolean admissionVerified,crossingVerified,groundVerified,topVerified,breakVerified,inventoryVerified,laterWalking,resumeVerified;
    private int stage,action,key,inventoryTicks;private long begun,stageAt,actionAt,events;private JsonObject result;

    public GameplayTerrainFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
                                  HudInputProtocol.Identity identity,Path evidenceDirectory,Consumer<JsonObject> completed)throws IOException{
        if(!Set.of("terrain","terrain-resume").contains(mode)||!Boolean.getBoolean("minecome.gameplayStandalone"))throw new IllegalArgumentException("Explicit standalone terrain fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;
        save.verifyOwnership();directory=evidenceDirectory.toRealPath();witness=save.directory().resolve(WITNESS);
        if(Files.exists(directory.resolve("host-view.json"))||Files.exists(directory.resolve("terrain-admission.json")))throw new IOException("Terrain fixture output exists");
        Path tile=Path.of(System.getProperty("minecome.gameplayGroundFile")).toRealPath().getParent().resolve("east-patch.json");
        if(Files.isSymbolicLink(tile)||!Files.isRegularFile(tile,LinkOption.NOFOLLOW_LINKS)||Files.size(tile)>GroundPatch.MAX_BYTES)throw new IOException("Missing bounded fixture tile");
        var parsed=GroundPatch.read(tile,true);tileJson=Files.readString(tile,StandardCharsets.UTF_8);tileHash=parsed.sha256();
        if(!parsed.sourceKind().equals("standalone_fixture")||parsed.centerX()!=movement.surface().centerX()+8||parsed.centerY()!=movement.surface().centerY()||parsed.centerZ()!=movement.surface().centerZ())throw new IOException("East tile must retain explicit standalone provenance and lattice origin");
        if(mode.equals("terrain")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Terrain fixture requires a new isolated save");expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)throw new IOException("Terrain resume witness missing");
            expected=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(expected.get("schema").getAsInt()!=1||!expected.get("kind").getAsString().equals("minecome_gameplay_terrain_witness_v1")||!expected.get("world_id").getAsString().equals(save.id().toString())||!expected.get("tile_sha256").getAsString().equals(tileHash))throw new IOException("Terrain witness identity differs");
            base=position(expected.getAsJsonObject("base"));
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayTerrainFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0||result!=null)return;try{requireOwner(c);movement.authority(c,System.nanoTime(),true);refreshAim(c);}catch(Exception e){complete(c,false,e.toString());}}
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(result!=null){movement.suspend(c);blocks.suspend(c);if(written||failure.get()!=null){if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}finished=true;completed.accept(result.deepCopy());}return;}
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready())return;
            if(begun==0)begin(c);requireOwner(c);long now=System.nanoTime();
            if(now-begun>30_000_000_000L)throw new IllegalStateException("Terrain fixture timed out: stage="+stage+", action="+action+", movement="+movement.evidence(c));
            observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;if(initial==null)initial=s.position();
            refreshAim(c);if(expected==null)create(c,s,now);else resume(c,s,now);
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||c.getServer()==null||!c.isIntegratedServerRunning()||!(movement.surface() instanceof GameplayTerrain))throw new IllegalStateException("Terrain fixture requires composite integrated gameplay");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true);begun=stageAt=System.nanoTime();
        if(expected==null){if(!c.player.isCreative()||c.player.getMainHandStack().getCount()!=0)throw new IllegalStateException("New terrain fixture not empty Creative");c.getNetworkHandler().sendChatCommand("give @s minecraft:stone 64");}
    }
    private void create(MinecraftClient c,State s,long now){double elapsed=(now-stageAt)/1e9;var terrain=(GameplayTerrain)movement.surface();switch(stage){
        case 0 -> {if(s.stones()!=64||!c.player.getMainHandStack().isOf(Items.STONE))return;if(terrain.tileCount()!=1||terrain.generation()!=0||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("New terrain fixture already expanded");next(now);}
        case 1 -> {movement.authority(c,now,true);setKey(c,s.position().x<.8?'W':0);if(s.position().x>=.8){setKey(c,0);next(now);}}
        case 2 -> {if(elapsed<.4)return;if(s.position().x<.7||s.position().x>=4)throw new IllegalStateException("Tile arrival did not start inside original coverage");admissionRequested.set(true);next(now);}
        case 3 -> {if(!admissionWritten||!confirmedTerrain(c,terrain,ack.get()))return;admissionVerified=true;next(now);}
        case 4 -> {movement.authority(c,now,true);setKey(c,s.position().x<5.3?'W':0);if(s.position().x>=5.3){setKey(c,0);crossingVerified=true;next(now);}}
        case 5 -> {if(elapsed<.5)return;if(s.position().x<=4.3)throw new IllegalStateException("Actual server did not remain beyond original coverage");double x=Math.floor(s.position().x)+2.5;base=BlockPos.ofFloored(x,movement.surface().heightAt(x,.5),.5);if(base.getX()<4||base.getX()>10||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("New terrain build position invalid");next(now);}
        case 6 -> {if(runAction(c,s,now)){if(action==0)groundVerified=true;if(action==1)topVerified=true;if(action==2)breakVerified=true;action++;sent=false;actionAt=0;if(action==3)next(now);}}
        case 7 -> {setKey(c,0);movement.suspend(c);blocks.suspend(c);toggle(c);next(now);}
        case 8 -> {if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Terrain inventory did not open");if(elapsed<.3)return;if(inventoryStart==null)inventoryStart=s.position();movement.authority(c,now,true);setKey(c,elapsed<1?'W':0);inventoryTicks++;if(elapsed>=1.3){if(inventoryTicks<5||inventoryStart.distanceTo(s.position())>.025||!matches(c,s,1,0))throw new IllegalStateException("Terrain inventory failed to suppress world movement");inventoryVerified=true;setKey(c,0);toggle(c);beforeLate=s.position();next(now);}}
        case 9 -> {movement.authority(c,now,true);setKey(c,elapsed>=.3&&elapsed<.45?'S':0);if(elapsed>=.95){if(beforeLate.distanceTo(s.position())<.15||s.position().x<=4.1||!matches(c,s,1,0)||!blocks.ownedBlocks().equals(Set.of(base)))throw new IllegalStateException("Later walking or persistent expanded-terrain block failed");laterWalking=true;complete(c,true,null);}}
        default -> throw new IllegalStateException("Unexpected terrain fixture stage");
    }}
    private boolean confirmedTerrain(MinecraftClient c,GameplayTerrain terrain,JsonObject a){
        if(a==null)return false;
        if(!a.get("run").getAsString().equals(identity.run())||!a.get("world_id").getAsString().equals(save.id().toString())||!a.get("patch_run").getAsString().equals(terrain.run())||!a.get("patch_sha256").getAsString().equals(terrain.sha256())||
            a.get("target_pid").getAsInt()!=identity.targetPid()||!a.get("target_start_filetime").getAsString().equals(Long.toUnsignedString(identity.targetStart()))||a.get("generation").getAsLong()!=1||a.get("tx").getAsInt()!=1||a.get("tz").getAsInt()!=0||!a.get("tile_sha256").getAsString().equals(tileHash)||!a.get("status").getAsString().equals("admitted"))throw new IllegalStateException("Terrain admission acknowledgement differs");
        var proof=movement.evidence(c);return terrain.hasTile(1,0)&&terrain.tileCount()==2&&terrain.generation()==1&&a.get("coverage_digest").getAsString().equals(terrain.digest())&&proof.get("terrain_client_generation").getAsLong()==1&&proof.get("terrain_server_generation").getAsLong()==1;
    }
    private boolean runAction(MinecraftClient c,State s,long now){
        if(!sent){target=switch(action){case 0->new Vec3d(base.getX()+.5,movement.surface().heightAt(base.getX()+.5,base.getZ()+.5),base.getZ()+.5);case 1->new Vec3d(base.getX()+.5,base.getY()+1,base.getZ()+.5);case 2->new Vec3d(base.getX(),base.getY()+1.5,base.getZ()+.5);default->throw new IllegalStateException("Terrain block action");};terrainTarget=action==0;refreshAim(c);edge(c,7,action<2?1:0);edge(c,8,action<2?1:0);actionAt=now;sent=true;return false;}
        var proof=blocks.evidence(c);if(s.at()<=actionAt||now-actionAt<200_000_000L||proof.get("pending").getAsBoolean())return false;
        int upper=action==1?1:0;if(matches(c,s,1,upper)&&blocks.ownedBlocks().size()==1+upper)return true;
        if(now-actionAt>3_000_000_000L)throw new IllegalStateException("Block action outside initial terrain failed: "+proof);return false;
    }
    private void resume(MinecraftClient c,State s,long now){var terrain=(GameplayTerrain)movement.surface();double elapsed=(now-stageAt)/1e9;switch(stage){
        case 0 -> {var motion=movement.evidence(c);if(!expected.get("player_id").getAsString().equals(playerId.toString())||terrain.tileCount()!=2||terrain.generation()!=1||!terrain.hasTile(1,0)||!terrain.digest().equals(expected.get("coverage_digest").getAsString())||motion.get("terrain_client_generation").getAsLong()!=1||motion.get("terrain_server_generation").getAsLong()!=1||!motion.get("resume_position_restored").getAsBoolean()||initial.x<=4||initial.distanceTo(vector(expected.getAsJsonObject("position")))>.04||!matches(c,s,1,0)||!blocks.ownedBlocks().equals(Set.of(base))||s.stones()!=expected.get("stone_count").getAsInt())throw new IllegalStateException("Expanded coverage, base block or player checkpoint did not survive reopen");resumeVerified=true;next(now);}
        case 1 -> {movement.authority(c,now,true);setKey(c,elapsed<.15?'W':0);if(elapsed>=.7){if(initial.distanceTo(s.position())<.15||s.position().x<=4)throw new IllegalStateException("Resumed player could not walk on saved expanded terrain");laterWalking=true;target=new Vec3d(base.getX(),base.getY()+.5,base.getZ()+.5);terrainTarget=false;refreshAim(c);edge(c,7,0);edge(c,8,0);actionAt=now;next(now);}}
        case 2 -> {if(s.at()>actionAt&&matches(c,s,0,0)&&blocks.ownedBlocks().isEmpty()&&!blocks.evidence(c).get("pending").getAsBoolean()){breakVerified=true;complete(c,true,null);}else if(now-actionAt>3_000_000_000L)throw new IllegalStateException("Saved expanded-terrain block could not be broken");}
        default -> throw new IllegalStateException("Unexpected terrain resume stage");
    }}
    private void next(long now){stage++;stageAt=now;}
    private void refreshAim(MinecraftClient c){if(target==null)return;var eye=c.player.getEyePos();var delta=target.subtract(eye);double distance=delta.length();if(distance<=0||distance>4.5)throw new IllegalStateException("Terrain fixture target outside reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,terrainTarget?distance:-1,terrainTarget));}
    private void edge(MinecraftClient c,int kind,int button){blocks.event(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),kind,button,0,0,0));}
    private void setKey(MinecraftClient c,int desired){if(key==desired)return;long now=System.nanoTime();if(key!=0)movement.event(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),2,key,0,0,0),now);key=desired;if(key!=0)movement.event(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),1,key,0,0,0),now);}
    private void toggle(MinecraftClient c){ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),1,'E',0,0,0));ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),2,'E',0,0,0));}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Terrain fixture owner changed");}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);var w=server.getOverworld();if(!server.isOnThread()||p==null||p.getWorld()!=w||!server.getSaveProperties().getLevelName().equals(save.saveName()))throw new IllegalStateException("Terrain fixture server owner changed");int count=0;for(int i=0;i<p.getInventory().size();i++)if(p.getInventory().getStack(i).isOf(Items.STONE))count+=p.getInventory().getStack(i).getCount();var b=base;observed.set(new State(System.nanoTime(),p.getPos(),b==null?-1:state(w.getBlockState(b)),b==null?-1:state(w.getBlockState(b.up())),count));}catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private boolean matches(MinecraftClient c,State s,int b,int u){return base!=null&&s.base()==b&&s.upper()==u&&state(c.world.getBlockState(base))==b&&state(c.world.getBlockState(base.up()))==u;}
    private static int state(net.minecraft.block.BlockState s){return s.isAir()?0:s.isOf(Blocks.STONE)?1:2;}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static Vec3d vector(JsonObject j){return new Vec3d(j.get("x").getAsDouble(),j.get("y").getAsDouble(),j.get("z").getAsDouble());}
    private static BlockPos position(JsonObject j){return new BlockPos(j.get("x").getAsInt(),j.get("y").getAsInt(),j.get("z").getAsInt());}
    private void complete(MinecraftClient c,boolean passed,String error){if(result!=null||finished)return;try{setKey(c,0);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_terrain_fixture_v1");j.addProperty("mode",mode);j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("tile_source_kind","standalone_fixture");j.addProperty("tile_sha256",tileHash);
        j.addProperty("admission_written",admissionWritten);j.addProperty("admission_verified",admissionVerified);j.addProperty("crossing_verified",crossingVerified);j.addProperty("ground_placement_verified",groundVerified);j.addProperty("top_placement_verified",topVerified);j.addProperty("break_verified",breakVerified);j.addProperty("inventory_suppression_verified",inventoryVerified);j.addProperty("inventory_ticks",inventoryTicks);j.addProperty("later_walking_verified",laterWalking);j.addProperty("resume_verified",resumeVerified);j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("scripted_view_writes",viewWrites);
        j.add("blocks",blocks.evidence(c));j.add("movement",movement.evidence(c));if(initial!=null)j.add("initial_position",json(initial));if(base!=null)j.add("base",json(Vec3d.of(base)));var s=observed.get();if(s!=null){j.add("server_position",json(s.position()));j.addProperty("stone_count",s.stones());}
        if(passed&&expected==null){var w=new JsonObject();w.addProperty("schema",1);w.addProperty("kind","minecome_gameplay_terrain_witness_v1");w.addProperty("world_id",save.id().toString());w.addProperty("player_id",playerId.toString());w.addProperty("tile_sha256",tileHash);w.addProperty("coverage_digest",((GameplayTerrain)movement.surface()).digest());w.add("position",json(s.position()));w.add("base",json(Vec3d.of(base)));w.addProperty("stone_count",s.stones());pendingWitness.set(w);}result=j;pendingResult.set(j.deepCopy());
    }
    private JsonObject identity(String kind){var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind",kind);j.addProperty("run",identity.run());j.addProperty("world_id",save.id().toString());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));return j;}
    private void writeLoop(){long seq=0;try{while(!closing){
        var proof=pendingResult.getAndSet(null);if(proof!=null){var w=pendingWitness.getAndSet(null);if(w!=null){save.verifyOwnership();Files.writeString(witness,w.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}Files.writeString(directory.resolve("gameplay-terrain-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}
        if(admissionRequested.get()&&!admissionWritten){var a=identity("minecome_gameplay_terrain_admission_v1");a.addProperty("generation",1);a.addProperty("tx",1);a.addProperty("tz",0);a.addProperty("tile_sha256",tileHash);a.addProperty("tile_json",tileJson);a.addProperty("utc_ms",System.currentTimeMillis());Path tmp=directory.resolve("terrain-admission-fixture.tmp");Files.writeString(tmp,a.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(tmp,directory.resolve("terrain-admission.json")))admissionWritten=true;}
        Path response=directory.resolve("terrain-ack.json");if(Files.exists(response)){if(Files.size(response)>8192)throw new IOException("Terrain acknowledgement oversized");ack.set(JsonParser.parseString(Files.readString(response,StandardCharsets.UTF_8)).getAsJsonObject());}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());j.add("forward",json(new Vec3d(1,0,0)));j.add("up",json(new Vec3d(0,0,1)));Path tmp=directory.resolve("host-view-fixture.tmp");Files.writeString(tmp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(tmp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){setKey(c,0);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
