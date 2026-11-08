package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.terrain.*;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.DeathScreen;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.entity.ItemEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.*;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.stat.Stats;
import net.minecraft.text.Text;
import net.minecraft.util.math.*;
import net.minecraft.world.GameRules;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Ordinary kill command, actual DeathScreen Respawn button, vanilla replacement
 * player and inventory drops. Commands seed only the owned test save. The
 * production lifecycle owns relocation/rebinding; this fixture never requests
 * respawn, moves an entity, changes health, or writes inventory/world state.
 */
public final class GameplayRespawnFixture {
    private static final String WITNESS="minecome-respawn-fixture.json";
    private record Drop(UUID id,String item,int count,Vec3d position){}
    private record State(long at,int tick,UUID player,Object entity,String mode,Vec3d position,double speed,
                         float health,int food,boolean alive,boolean keepInventory,int diamonds,int tables,
                         int deaths,String block,List<Drop> drops){}
    private record Sample(String stage,HudReadback.Completed frame){}
    private record Admission(int tx,int tz,String json,String hash,GameplayTerrain next){}
    private static final int[][] PREFETCH={{1,0},{0,1},{-1,0},{0,-1},{1,1},{-1,1},{-1,-1},{1,-1}};
    private final String mode;
    private final boolean nativeMode;
    private final long created=System.nanoTime();
    private final GameplayBlocks blocks;
    private final GameplayMovement movement;
    private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;
    private final Path directory,witness;
    private final Consumer<JsonObject> completed;
    private final JsonObject expected;
    private final JsonObject syntheticBase;
    private final AtomicReference<State> observation=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(2);
    private final Map<String,JsonObject> images=new ConcurrentHashMap<>();
    private final Set<String> queued=new HashSet<>();
    private final List<String> commands=new ArrayList<>();
    private MinecraftServer server;
    private Object world,player,originalClient,originalServer;
    private UUID playerId,dropId;
    private HudVanillaUiAdapter ui;
    private JsonObject deathPointer;
    private BlockPos base;
    private Vec3d aimTarget,initial,deathPosition,respawnPosition;
    private GameplayAimReader.RenderSample nativeSample;
    private State deadState;
    private volatile Vec3d forward=new Vec3d(1,0,0);
    private volatile boolean closing,finished;
    private volatile long viewWrites;
    private volatile boolean prefetchRequested,prefetchAcknowledged;
    private volatile int prefetchAdmissions,prefetchAcks;
    private Admission pendingAdmission;
    private boolean admissionWritten,prefetchVerified;
    private boolean terrainTarget,placed,dead,dropped,buttonClicked,reborn,preserved,walked,rendered,resumed,clientReplaced,serverReplaced;
    private int stage,ticks,key,settleTick,pulseTick,walkPulses,readyTick=-1;
    private long begun,stageAt,events,actionAt,nativeDwellAt,nativeStartedUtc,nativeCompletedUtc;

    public GameplayRespawnFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
                                  HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        nativeMode=mode.equals("respawn-native");
        if(!Set.of("respawn","respawn-resume","respawn-native").contains(mode)||!Boolean.getBoolean("minecome.gameplayWorldBlocks")||
            (nativeMode?Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayRespawnCheck"):!Boolean.getBoolean("minecome.gameplayStandalone")))
            throw new IllegalArgumentException("Explicit WorldBlocks respawn fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        if(!Boolean.getBoolean("minecome.gameplayExplore")||!(movement.surface() instanceof GameplayTerrain))throw new IllegalArgumentException("Respawn fixture requires expanded terrain mode");
        save.verifyOwnership();witness=save.directory().resolve(WITNESS);
        if((!nativeMode&&Files.exists(this.directory.resolve("host-view.json")))||Files.exists(this.directory.resolve("gameplay-respawn-fixture.json")))throw new IOException("Respawn fixture output exists");
        if(!mode.equals("respawn-resume")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Respawn fixture needs a new owned save");expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)throw new IOException("Missing owned respawn witness");
            var proof=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(proof.get("schema").getAsInt()!=1||!proof.get("kind").getAsString().equals("minecome_gameplay_respawn_witness_v1")||!proof.get("world_id").getAsString().equals(save.id().toString())||!proof.get("save").getAsString().equals(save.saveName()))throw new IOException("Respawn witness identity differs");
            expected=proof.getAsJsonObject("state");var b=proof.getAsJsonObject("table");base=new BlockPos(b.get("x").getAsInt(),b.get("y").getAsInt(),b.get("z").getAsInt());dropId=UUID.fromString(proof.get("drop_id").getAsString());
        }
        if(nativeMode)syntheticBase=null;
        else{
            Path source=Path.of(System.getProperty("minecome.gameplayGroundFile")).toRealPath();var patch=GroundPatch.read(source,true);
            if(!patch.sourceKind().equals("standalone_fixture")||!patch.wide()||!patch.sha256().equals(movement.surface().sha256()))throw new IOException("Respawn expansion needs its verified synthetic base");
            syntheticBase=JsonParser.parseString(Files.readString(source,StandardCharsets.UTF_8)).getAsJsonObject();
            for(var value:syntheticBase.getAsJsonArray("points")){var point=value.getAsJsonObject();if(point.get("z").getAsDouble()!=patch.centerZ()||point.get("nx").getAsDouble()!=0||point.get("ny").getAsDouble()!=0||point.get("nz").getAsDouble()!=1)throw new IOException("Respawn synthetic expansion requires an explicitly flat fixture");}
            if(Files.exists(this.directory.resolve("terrain-admission.json"))||Files.exists(this.directory.resolve("terrain-ack.json")))throw new IOException("Respawn terrain transport exists");
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayRespawnFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){
        if(closing||finished||begun==0)return;
        try{owner(c);if(!nativeMode)movement.authority(c,System.nanoTime(),true);refreshAim(c);}catch(Exception e){complete(c,false,e.toString());}
    }
    public GameplayWorldRenderer.View view(){
        var c=MinecraftClient.getInstance();if(begun==0||closing||finished||c.player!=player)return null;
        var eye=c.player.getEyePos();var f=Vec3d.ofCenter(base).subtract(eye).normalize();var right=f.crossProduct(new Vec3d(0,1,0)).normalize();
        return new GameplayWorldRenderer.View(eye,f,right.crossProduct(f).normalize(),Math.toRadians(70));
    }
    public GameplayBlocks.Aim renderAim(){return null;}
    public void tick(MinecraftClient c,boolean armed,GameplayAimReader.RenderSample sample){
        if(!nativeMode)throw new IllegalStateException("Native respawn overload used by standalone fixture");
        if(closing||finished)return;
        if(begun==0){
            if(System.nanoTime()-created>90_000_000_000L){complete(c,false,"Native respawn never armed");return;}
            if(!armed||sample==null||!sample.fresh()||sample.schema()!=3||sample.perspective()!=0)return;
        }else if(!armed){complete(c,false,"Native respawn input authority lost");return;}
        nativeSample=sample;
        // Continue lifecycle observations while death/repositioning temporarily
        // suspends movement. A stale view must never leave a walking key held.
        if(sample==null||!sample.fresh()||sample.perspective()!=0){setKey(c,0);if(stage<5||stage>6)return;}
        tick(c);
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(begun==0){
                if(System.nanoTime()-created>90_000_000_000L)throw new IllegalStateException("Respawn terrain prefetch setup deadline");
                if(!movement.ready()||!blocks.ready())return;prefetchRequested=true;if(!expanded(c))return;begin(c);
            }owner(c);
            long now=System.nanoTime();if(now-begun>90_000_000_000L||now-stageAt>30_000_000_000L)throw new IllegalStateException("Respawn timeout stage="+stage+" client_alive="+c.player.isAlive()+" screen="+(c.currentScreen==null?"none":c.currentScreen.getClass().getSimpleName())+" state="+state(observation.get()));
            observe();var s=observation.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
            if(!s.player().equals(playerId))throw new IllegalStateException("Respawn observed player differs");
            if(originalServer==null)originalServer=s.entity();
            else if(s.entity()!=originalServer){if(!buttonClicked)throw new IllegalStateException("Server player changed before actual Respawn click");serverReplaced=true;}
            ticks++;refreshAim(c);
            if(expected!=null){resume(c,s);return;}create(c,s,now);
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||c.getServer()==null||!c.isIntegratedServerRunning()||!c.options.getPerspective().isFirstPerson())throw new IllegalStateException("Owned first-person integrated client required");
        save.verifyOwnership();world=c.world;player=originalClient=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true);initial=c.player.getPos();
        if(nativeMode){var f=nativeSample.view().forward();var flat=new Vec3d(f.x,0,f.z);if(flat.lengthSquared()<.1)throw new IllegalStateException("Native view too vertical for respawn walk");forward=flat.normalize();}
        if(base==null){var target=initial.add(forward.crossProduct(new Vec3d(0,1,0)).multiply(2.5));double x=Math.floor(target.x)+.5,z=Math.floor(target.z)+.5;
            if(!movement.surface().containsFeet(x,z,.3))throw new IllegalStateException("Respawn table lacks captured terrain");base=BlockPos.ofFloored(x,movement.surface().heightAt(x,z),z);}
        begun=stageAt=System.nanoTime();
    }
    private boolean expanded(MinecraftClient c){
        if(!(movement.surface() instanceof GameplayTerrain terrain)||terrain.tileCount()>9)throw new IllegalStateException("Respawn terrain coverage profile changed");
        if(terrain.tileCount()!=9||terrain.generation()!=8||movement.terrainTransition())return false;
        for(int x=-1;x<=1;x++)for(int z=-1;z<=1;z++)if(!terrain.hasTile(x,z))throw new IllegalStateException("Respawn prefetch tile missing");
        var proof=movement.evidence(c);if(proof.get("terrain_client_generation").getAsInt()!=8||proof.get("terrain_server_generation").getAsInt()!=8)return false;
        if(expected==null&&!prefetchAcknowledged)return false;prefetchVerified=true;return true;
    }
    private void create(MinecraftClient c,State s,long now)throws IOException{
        switch(stage){
            case 0->{
                if(!s.mode().equals("creative")||s.diamonds()!=0||s.tables()!=0||s.deaths()!=0||!s.drops().isEmpty()||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("Unexpected fresh respawn state");
                send(c,"gamemode survival");send(c,"gamerule keepInventory false");send(c,"gamerule doImmediateRespawn false");send(c,"item replace entity @s hotbar.0 with minecraft:crafting_table");send(c,"item replace entity @s hotbar.1 with minecraft:diamond 3");next(1,now);
            }
            case 1->{
                if(!s.mode().equals("survival")||s.tables()!=1||s.diamonds()!=3||s.keepInventory()||!c.player.getMainHandStack().isOf(Items.CRAFTING_TABLE))return;
                terrainTarget=true;aimTarget=new Vec3d(base.getX()+.5,movement.surface().heightAt(base.getX()+.5,base.getZ()+.5),base.getZ()+.5);refreshAim(c);edge(c,7,1);edge(c,8,1);actionAt=now;next(2,now);
            }
            case 2->{
                if(s.at()<=actionAt||blocks.evidence(c).get("pending").getAsBoolean())return;
                if(!tableMatches(c,s)||s.tables()!=0)throw new IllegalStateException("Pre-death construction placement failed");
                placed=true;aimTarget=null;key(c,'9');pulseTick=s.tick();setKey(c,0);next(3,now);
            }
            case 3->{
                double distance=horizontal(s.position(),initial);if(distance>3.5)throw new IllegalStateException("Pre-death walk exceeded bound");
                if(distance<2.1){walkPulse(c,s,'W');return;}setKey(c,0);settleTick=s.tick();next(4,now);
            }
            case 4->{
                if(s.tick()-settleTick<12||s.speed()>.0001)return;
                if(horizontal(s.position(),initial)<2.1||horizontal(s.position(),initial)>3.5)throw new IllegalStateException("Death location not isolated from respawn pickup range");
                deathPosition=s.position();send(c,"kill @s");next(5,now);
            }
            case 5->{
                if(s.alive()||s.health()>0||c.player.isAlive()||!(c.currentScreen instanceof DeathScreen)||s.deaths()!=1||s.diamonds()!=0||s.tables()!=0)return;
                verifyDrops(s);dead=true;dropped=true;deadState=s;
                if(!images.containsKey("dead"))return;validateImage("dead","DeathScreen");rendered=true;
                if(nativeMode){if(nativeDwellAt==0){nativeDwellAt=now;nativeStartedUtc=System.currentTimeMillis();}if(now-nativeDwellAt<11_000_000_000L)return;nativeCompletedUtc=System.currentTimeMillis();}
                var button=respawnButton(c);if(button==null||!button.active)return;
                clickRespawn(c,button);buttonClicked=true;deathPointer=ui.pointerDiagnostics();next(6,now);
            }
            case 6->{
                if(!movement.ready()||movement.respawnEpoch()<1||movement.respawnPending()||!clientReplaced||!serverReplaced||!s.alive()||!c.player.isAlive()||c.currentScreen!=null)return;
                if(s.health()!=20||s.food()!=20||s.diamonds()!=0||s.tables()!=0||s.deaths()!=1||horizontal(s.position(),initial)>.2||Math.abs(s.position().y-initial.y)>.2)throw new IllegalStateException("Replacement player state or captured respawn anchor differs: "+state(s));
                verifyDrops(s);if(!tableMatches(c,s))throw new IllegalStateException("Respawn lost construction");
                if(readyTick<0){readyTick=s.tick();return;}if(s.tick()-readyTick<2)return;
                reborn=preserved=true;respawnPosition=s.position();pulseTick=s.tick();setKey(c,0);next(7,now);
            }
            case 7->{
                double distance=horizontal(s.position(),respawnPosition);if(distance>1.2)throw new IllegalStateException("Post-respawn walk exceeded bound");
                if(distance<.25){walkPulse(c,s,'S');return;}setKey(c,0);settleTick=s.tick();next(8,now);
            }
            case 8->{
                if(s.tick()-settleTick<12||s.speed()>.0001||c.currentScreen!=null||!images.containsKey("respawned"))return;
                if(!s.alive()||s.health()!=20||s.food()!=20||s.diamonds()!=0||!tableMatches(c,s)||horizontal(s.position(),respawnPosition)<.25)throw new IllegalStateException("Post-respawn gameplay differs");
                verifyDrops(s);validateImage("respawned","none");walked=true;writeWitness(s);complete(c,true,null);
            }
            default->throw new IllegalStateException("Unknown respawn stage");
        }
    }
    private void resume(MinecraftClient c,State s){
        var actual=state(s);for(String name:List.of("player_id","mode","health","food","alive","keep_inventory","diamond_count","table_count","deaths"))if(!actual.get(name).equals(expected.get(name)))throw new IllegalStateException("Saved respawn state differs: "+name);
        verifyDrops(s);if(!tableMatches(c,s))throw new IllegalStateException("Saved construction missing");
        if(!movement.evidence(c).get("resume_position_restored").getAsBoolean()||!images.containsKey("resumed"))return;
        validateImage("resumed","none");preserved=dropped=rendered=resumed=true;complete(c,true,null);
    }
    private void verifyDrops(State s){
        if(s.drops().size()!=1)throw new IllegalStateException("Death drop entity count differs: "+state(s));
        var d=s.drops().getFirst();if(!d.item().equals("minecraft:diamond")||d.count()!=3)throw new IllegalStateException("Death drop stack differs");
        if(dropId==null)dropId=d.id();else if(!dropId.equals(d.id()))throw new IllegalStateException("Death drop identity changed");
    }
    private void writeWitness(State s)throws IOException{
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_respawn_witness_v1");p.addProperty("world_id",save.id().toString());p.addProperty("save",save.saveName());p.addProperty("drop_id",dropId.toString());p.add("state",state(s));p.add("table",position());
        save.verifyOwnership();Files.writeString(witness,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
    }
    private static double horizontal(Vec3d a,Vec3d b){return Math.hypot(a.x-b.x,a.z-b.z);}
    private boolean tableMatches(MinecraftClient c,State s){return s.block().equals("minecraft:crafting_table")&&c.world.getBlockState(base).isOf(Blocks.CRAFTING_TABLE)&&blocks.ownedBlocks().equals(Set.of(base));}
    private void refreshAim(MinecraftClient c){if(aimTarget==null||!c.player.isAlive()||c.currentScreen!=null)return;var eye=c.player.getEyePos();var delta=aimTarget.subtract(eye);double distance=delta.length();if(distance<=0||distance>4.5)throw new IllegalStateException("Respawn setup target outside vanilla reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,terrainTarget?distance:-1,terrainTarget));}
    private void owner(MinecraftClient c){
        if(!c.isOnThread()||c.world!=world||c.player==null||c.getServer()!=server||!c.isIntegratedServerRunning()||!c.player.getUuid().equals(playerId))throw new IllegalStateException("Respawn fixture world/player identity changed");
        if(c.player!=player){if(!buttonClicked||!dead||player!=originalClient)throw new IllegalStateException("Unexpected client player replacement");player=c.player;clientReplaced=true;ui=new HudVanillaUiAdapter(c,true);}
    }
    private static int count(PlayerEntity p,Item item){int n=0;for(int i=0;i<p.getInventory().size();i++){var stack=p.getInventory().getStack(i);if(stack.isOf(item))n+=stack.getCount();}return n;}
    private Box box(){return new Box(-16,initial.y-8,-16,16,initial.y+8,16);}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);var w=server.getOverworld();
        if(!server.isOnThread()||p==null||p.getWorld()!=w||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Respawn server ownership changed");
        var drops=new ArrayList<Drop>();for(var e:w.getEntitiesByClass(ItemEntity.class,box(),e->!e.isRemoved()&&!e.getStack().isEmpty()))drops.add(new Drop(e.getUuid(),Registries.ITEM.getId(e.getStack().getItem()).toString(),e.getStack().getCount(),e.getPos()));
        observation.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p,p.interactionManager.getGameMode().getName(),p.getPos(),p.getVelocity().horizontalLengthSquared(),p.getHealth(),p.getHungerManager().getFoodLevel(),p.isAlive(),w.getGameRules().getBoolean(GameRules.KEEP_INVENTORY),count(p,Items.DIAMOND),count(p,Items.CRAFTING_TABLE),p.getStatHandler().getStat(Stats.CUSTOM,Stats.DEATHS),GameplayBlocks.stateName(w.getBlockState(base)),List.copyOf(drops)));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private static ButtonWidget respawnButton(MinecraftClient c){
        if(!(c.currentScreen instanceof DeathScreen screen))return null;String label=Text.translatable("deathScreen.respawn").getString();
        return screen.children().stream().filter(e->e instanceof ButtonWidget b&&b.visible&&b.getMessage().getString().equals(label)).map(e->(ButtonWidget)e).findFirst().orElse(null);
    }
    private void clickRespawn(MinecraftClient c,ButtonWidget button){
        var screen=c.currentScreen;float x=(float)((button.getX()+button.getWidth()/2.0)/screen.width),y=(float)((button.getY()+button.getHeight()/2.0)/screen.height);
        ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),4,0,x,y,0));ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),5,0,x,y,0));
    }
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++events,System.currentTimeMillis(),kind,code,0,0,0);}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void edge(MinecraftClient c,int kind,int button){blocks.event(c,event(kind,button));}
    private void setKey(MinecraftClient c,int desired){if(key==desired)return;long now=System.nanoTime();if(key!=0)movement.event(c,event(2,key),now);key=desired;if(key!=0)movement.event(c,event(1,key),now);}
    private void walkPulse(MinecraftClient c,State s,int desired){
        // Fresh key edges after a neutral interval recover ordinary bounded
        // input when a late frame has legitimately expired the movement lease.
        if(key!=0&&s.tick()-pulseTick>=2){setKey(c,0);pulseTick=s.tick();}
        else if(key==0&&s.tick()-pulseTick>=4){setKey(c,desired);pulseTick=s.tick();walkPulses++;}
    }
    private void send(MinecraftClient c,String command){owner(c);c.getNetworkHandler().sendChatCommand(command);commands.add(command);}
    private void next(int value,long now){stage=value;stageAt=now;ticks=0;}
    public String captureStage(){
        if(closing||finished||begun==0||ticks<12||nativeMode&&(nativeSample==null||!nativeSample.fresh()))return null;
        var c=MinecraftClient.getInstance();String name=expected!=null&&c.currentScreen==null?"resumed":expected!=null?null:stage==5&&dead&&c.currentScreen instanceof DeathScreen?"dead":stage==8&&c.currentScreen==null?"respawned":null;
        return name==null||queued.contains(name)||images.containsKey(name)?null:name;
    }
    public void captured(HudReadback.Completed frame){
        if(closing||finished)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("respawn_fixture_stage"))return;
        String name=meta.get("respawn_fixture_stage").getAsString();if(!Set.of("dead","respawned","resumed").contains(name)||!queued.add(name))return;
        if(!samples.offer(new Sample(name,frame)))failure.compareAndSet(null,"Respawn capture queue full");
    }
    private void validateImage(String name,String screen){
        var image=images.get(name);if(image==null)throw new IllegalStateException("Missing respawn image "+name);var m=image.getAsJsonObject("metadata");
        if(!m.get("screen_kind").getAsString().equals(screen)||m.get("frame_format").getAsInt()!=2||!m.has("world_camera")||image.get("hud_pixels").getAsLong()<1000)throw new IllegalStateException("Respawn screen pixels or world view differ: "+image);
        if(!screen.equals("none")&&(!m.get("state").getAsString().equals("inventory")||m.get("screen").getAsInt()!=1))throw new IllegalStateException("Death screen did not use UI input mode");
    }
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();byte[] layers=f.layersBottomUp();HudLayerPixels.require(layers,f.width(),f.height());int plane=HudPixels.byteSize(f.width(),f.height());long pixels=0;
        for(int i=3;i<plane;i+=4)if((layers[i]&255)>8)pixels++;
        byte[] rgba=HudPixels.straightTopLeft(Arrays.copyOfRange(layers,0,plane),f.width(),f.height()),png=HudPixels.png(rgba,f.width(),f.height());String file="respawn-"+sample.stage()+".png";Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);
        var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file);p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.addProperty("width",f.width());p.addProperty("height",f.height());p.addProperty("hud_pixels",pixels);p.add("metadata",JsonParser.parseString(f.metadata()));images.put(sample.stage(),p);
    }
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private JsonObject position(){var j=new JsonObject();j.addProperty("x",base.getX());j.addProperty("y",base.getY());j.addProperty("z",base.getZ());return j;}
    private static JsonObject state(State s){
        var j=new JsonObject();if(s==null)return j;j.addProperty("player_id",s.player().toString());j.addProperty("mode",s.mode());j.addProperty("health",s.health());j.addProperty("food",s.food());j.addProperty("alive",s.alive());j.addProperty("keep_inventory",s.keepInventory());j.addProperty("diamond_count",s.diamonds());j.addProperty("table_count",s.tables());j.addProperty("deaths",s.deaths());j.addProperty("block",s.block());j.addProperty("server_tick",s.tick());j.add("position",vector(s.position()));
        var a=new JsonArray();for(var d:s.drops()){var p=new JsonObject();p.addProperty("id",d.id().toString());p.addProperty("item",d.item());p.addProperty("count",d.count());p.add("position",vector(d.position()));a.add(p);}j.add("drops",a);return j;
    }
    private void complete(MinecraftClient c,boolean passed,String error){
        if(finished)return;finished=true;try{setKey(c,0);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_respawn_fixture_v1");p.addProperty("mode",mode);p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",error);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("standalone_scripted",!nativeMode);p.addProperty("native_input_verified",false);p.addProperty("live_kcd_verified",false);p.addProperty("live_kcd_connected",nativeMode);p.addProperty("scripted_aiming",true);p.addProperty("scripted_mouse_input",true);p.addProperty("scripted_movement_input",true);p.addProperty("native_camera_preserved",nativeMode);p.addProperty("direct_world_inventory_entity_writes",false);p.addProperty("position_writes_used",false);p.addProperty("direct_respawn_request_used",false);
        p.addProperty("construction_placement_verified",placed);p.addProperty("death_verified",dead);p.addProperty("death_drops_verified",dropped);p.addProperty("respawn_button_verified",buttonClicked);p.addProperty("respawn_verified",reborn);p.addProperty("construction_preserved_verified",preserved);p.addProperty("walking_after_respawn_verified",walked);p.addProperty("render_pixels_verified",rendered);p.addProperty("resume_verified",resumed);p.addProperty("client_player_replaced",clientReplaced);p.addProperty("server_player_replaced",serverReplaced);p.addProperty("respawn_epoch",movement.respawnEpoch());p.addProperty("respawn_pending",movement.respawnPending());p.addProperty("drop_id",dropId==null?null:dropId.toString());p.addProperty("scripted_view_writes",viewWrites);p.addProperty("walking_pulses",walkPulses);p.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);p.addProperty("last_stage",stage);
        p.addProperty("native_respawn_started_utc_ms",nativeStartedUtc);p.addProperty("native_respawn_completed_utc_ms",nativeCompletedUtc);
        p.addProperty("terrain_prefetch_verified",prefetchVerified);p.addProperty("terrain_prefetch_admissions",prefetchAdmissions);p.addProperty("terrain_prefetch_acknowledgements",prefetchAcks);
        if(movement.surface() instanceof GameplayTerrain terrain){p.addProperty("terrain_tiles",terrain.tileCount());p.addProperty("terrain_generation",terrain.generation());p.addProperty("terrain_digest",terrain.digest());}
        var a=new JsonArray();commands.forEach(a::add);p.add("commands",a);a=new JsonArray();for(String name:List.of("dead","respawned","resumed"))if(images.containsKey(name))a.add(images.get(name).deepCopy());p.add("images",a);var s=observation.get();if(s!=null)p.add("final_state",state(s));if(deadState!=null)p.add("dead_state",state(deadState));if(initial!=null)p.add("initial_position",vector(initial));if(deathPosition!=null)p.add("death_position",vector(deathPosition));if(respawnPosition!=null)p.add("respawn_position",vector(respawnPosition));if(base!=null)p.add("table",position());if(deathPointer!=null)p.add("pointer",deathPointer);else if(ui!=null)p.add("pointer",ui.pointerDiagnostics());p.add("blocks",blocks.evidence(c));p.add("movement",movement.evidence(c));
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-respawn-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    private void writeLoop(){long sequence=0;try{while(!closing){
        var sample=samples.poll();if(sample!=null)writeSample(sample);
        prefetch();
        if(nativeMode){Thread.sleep(25);continue;}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("source_kind","standalone_hud_physical_view_fixture");p.addProperty("run",identity.run());p.addProperty("patch_run",movement.surface().run());p.addProperty("patch_sha256",movement.surface().sha256());p.addProperty("target_pid",identity.targetPid());p.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));p.addProperty("seq",++sequence);p.addProperty("utc_ms",System.currentTimeMillis());var f=forward;p.add("forward",vector(new Vec3d(f.x,-f.z,0)));p.add("up",vector(new Vec3d(0,0,1)));
        Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    private void prefetch()throws IOException,InterruptedException{
        if(expected!=null||!prefetchRequested||prefetchAcknowledged||finished)return;
        if(!(movement.surface() instanceof GameplayTerrain terrain))throw new IOException("Respawn terrain prefetch owner changed");
        var ack=terrainAck();
        if(nativeMode){
            // Native coverage is supplied exclusively by genuine host captures.
            // Observe only the guest's durable final receipt; never invent tiles.
            if(terrain.tileCount()==9&&ack!=null&&ack.get("generation").getAsInt()==8){
                var last=terrain.tiles().getLast();verifyAck(ack,terrain,last.tx(),last.tz(),last.patch().sha256());prefetchAcknowledged=true;
            }
            return;
        }
        if(pendingAdmission!=null&&admissionWritten){
            if(ack==null||ack.get("generation").getAsInt()<pendingAdmission.next().generation())return;
            verifyAck(ack,pendingAdmission.next(),pendingAdmission.tx(),pendingAdmission.tz(),pendingAdmission.hash());
            if(terrain.generation()!=pendingAdmission.next().generation()||!terrain.digest().equals(pendingAdmission.next().digest()))return;
            prefetchAcks++;pendingAdmission=null;admissionWritten=false;if(prefetchAcks==8){prefetchAcknowledged=true;return;}
        }
        if(pendingAdmission==null){
            if(terrain.generation()!=prefetchAcks||terrain.tileCount()!=prefetchAcks+1)throw new IOException("Unexpected synthetic respawn coverage");
            int tx=PREFETCH[prefetchAcks][0],tz=PREFETCH[prefetchAcks][1];var tile=syntheticBase.deepCopy();
            tile.getAsJsonObject("center").addProperty("x",terrain.centerX()+8*tx);tile.getAsJsonObject("center").addProperty("y",terrain.centerY()-8*tz);
            for(var value:tile.getAsJsonArray("points")){var point=value.getAsJsonObject();point.addProperty("x",point.get("x").getAsDouble()+8*tx);point.addProperty("y",point.get("y").getAsDouble()-8*tz);}
            String json=tile.toString();var parsed=GroundPatch.parse(json.getBytes(StandardCharsets.UTF_8),true);pendingAdmission=new Admission(tx,tz,json,parsed.sha256(),terrain.admit(tx,tz,parsed));
        }
        var a=new JsonObject();a.addProperty("schema",1);a.addProperty("kind","minecome_gameplay_terrain_admission_v1");a.addProperty("run",identity.run());a.addProperty("world_id",save.id().toString());a.addProperty("patch_run",terrain.run());a.addProperty("patch_sha256",terrain.sha256());a.addProperty("target_pid",identity.targetPid());a.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));a.addProperty("generation",pendingAdmission.next().generation());a.addProperty("tx",pendingAdmission.tx());a.addProperty("tz",pendingAdmission.tz());a.addProperty("tile_sha256",pendingAdmission.hash());a.addProperty("tile_json",pendingAdmission.json());a.addProperty("utc_ms",System.currentTimeMillis());
        Path temporary=directory.resolve("terrain-admission-respawn.tmp");Files.writeString(temporary,a.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
        if(HudFixtureCameraFiles.replace(temporary,directory.resolve("terrain-admission.json"))){admissionWritten=true;prefetchAdmissions++;}
    }
    private JsonObject terrainAck()throws IOException{
        Path path=directory.resolve("terrain-ack.json");
        try{if(!Files.exists(path,LinkOption.NOFOLLOW_LINKS))return null;if(Files.isSymbolicLink(path)||!Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS)||Files.size(path)>8192)throw new IOException("Invalid respawn terrain receipt");return JsonParser.parseString(Files.readString(path,StandardCharsets.UTF_8)).getAsJsonObject();}
        catch(NoSuchFileException|AccessDeniedException e){return null;}
    }
    private void verifyAck(JsonObject ack,GameplayTerrain terrain,int tx,int tz,String hash)throws IOException{
        if(ack.get("schema").getAsInt()!=1||!ack.get("kind").getAsString().equals("minecome_gameplay_terrain_ack_v1")||!ack.get("run").getAsString().equals(identity.run())||!ack.get("world_id").getAsString().equals(save.id().toString())||
            !ack.get("patch_run").getAsString().equals(terrain.run())||!ack.get("patch_sha256").getAsString().equals(terrain.sha256())||ack.get("target_pid").getAsInt()!=identity.targetPid()||!ack.get("target_start_filetime").getAsString().equals(Long.toUnsignedString(identity.targetStart()))||
            ack.get("generation").getAsInt()!=terrain.generation()||ack.get("tx").getAsInt()!=tx||ack.get("tz").getAsInt()!=tz||!ack.get("tile_sha256").getAsString().equals(hash)||!ack.get("status").getAsString().equals("admitted")||!ack.get("coverage_digest").getAsString().equals(terrain.digest()))throw new IOException("Respawn terrain durable acknowledgment differs");
    }
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){setKey(c,0);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
