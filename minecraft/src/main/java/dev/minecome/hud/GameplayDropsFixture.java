package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayAimReader;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.ItemEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.Items;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.stat.Stats;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Real Survival mining, tracked ItemEntity pixels, vanilla walking pickup and saved inventory. */
public final class GameplayDropsFixture {
    private static final String WITNESS="minecome-drops-fixture.json";
    private record Drop(UUID id,String item,int count,Vec3d position,boolean grounded){}
    private record State(long at,int tick,UUID player,String mode,Vec3d position,int selected,int stone,int cobble,int tools,int damage,int pickups,String block,List<Drop> drops){}
    private record Sample(String stage,HudReadback.Completed frame){}
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
    private final AtomicReference<State> observation=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(2);
    private final Map<String,JsonObject> images=new ConcurrentHashMap<>();
    private final Set<String> queued=new HashSet<>();
    private final List<String> commands=new ArrayList<>();
    private MinecraftServer server;
    private Object world,player;
    private UUID playerId,dropId;
    private HudVanillaUiAdapter ui;
    private BlockPos base;
    private Vec3d aimTarget,initial,dropPosition;
    private GameplayAimReader.RenderSample nativeSample;
    private volatile Vec3d forward=new Vec3d(1,0,0);
    private volatile boolean closing;
    private volatile long viewWrites;
    private boolean finished,terrainTarget,placed,mined,realDrop,grounded,rendered,picked,durable,resumed;
    private int stage,key,ticks,groundTicks,atTick,pulseTick,walkPulses,firstDropTick;
    private long begun,stageAt,events,actionAt;
    private long nativeDropDwellAt,nativeDropStartedUtc,nativeDropCompletedUtc;

    public GameplayDropsFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
                                HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        nativeMode=mode.equals("drops-native");
        if(!Set.of("drops","drops-resume","drops-native").contains(mode)||!Boolean.getBoolean("minecome.gameplayWorldBlocks")||
                (nativeMode?Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayDropsCheck"):!Boolean.getBoolean("minecome.gameplayStandalone")))
            throw new IllegalArgumentException("Explicit WorldBlocks drops fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();witness=save.directory().resolve(WITNESS);
        if(!nativeMode&&Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-drops-fixture.json")))throw new IOException("Drops fixture output exists");
        if(!mode.equals("drops-resume")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Drops fixture needs a new owned save");expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)throw new IOException("Missing owned drops witness");
            var proof=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(proof.get("schema").getAsInt()!=1||!proof.get("kind").getAsString().equals("minecome_gameplay_drops_witness_v1")||!proof.get("world_id").getAsString().equals(save.id().toString())||!proof.get("save").getAsString().equals(save.saveName()))throw new IOException("Drops witness identity differs");
            expected=proof.getAsJsonObject("state");
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayDropsFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){
        if(closing||finished||begun==0)return;
        try{owner(c);if(!nativeMode)movement.authority(c,System.nanoTime(),true);refreshAim(c);}catch(Exception e){complete(c,false,e.toString());}
    }
    public GameplayWorldRenderer.View view(){
        var c=MinecraftClient.getInstance();if(begun==0||closing||finished||c.player!=player)return null;
        var eye=c.player.getEyePos();var target=dropPosition!=null?dropPosition.add(0,.2,0):new Vec3d(base.getX()+.5,base.getY()+.2,base.getZ()+.5);
        var f=target.subtract(eye).normalize();var right=f.crossProduct(new Vec3d(0,1,0)).normalize();
        return new GameplayWorldRenderer.View(eye,f,right.crossProduct(f).normalize(),Math.toRadians(70));
    }
    /** No outline is needed to establish isolated drop pixels. Actions use their own admitted ray. */
    public GameplayBlocks.Aim renderAim(){return null;}
    /** Explicit coupled check: retain the real native camera and ordinary input leases. */
    public void tick(MinecraftClient c,boolean armed,GameplayAimReader.RenderSample sample){
        if(!nativeMode)throw new IllegalStateException("Native drops overload used by standalone fixture");
        if(closing||finished)return;
        if(begun!=0&&System.nanoTime()-begun>60_000_000_000L){complete(c,false,"Native drops fixture deadline exceeded");return;}
        if(begun==0){
            if(System.nanoTime()-created>90_000_000_000L){complete(c,false,"Native drops fixture never armed");return;}
            if(!armed||sample==null||!sample.fresh()||sample.schema()!=3||sample.perspective()!=0)return;
        }else if(!armed){complete(c,false,"Native drops input authority lost");return;}
        nativeSample=sample;
        if(sample==null||!sample.fresh()||sample.perspective()!=0){setKey(c,0);return;}
        tick(c);
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);owner(c);
            long now=System.nanoTime();if(now-begun>60_000_000_000L||now-stageAt>(nativeMode&&stage==5?20_000_000_000L:12_000_000_000L))throw new IllegalStateException("Drops fixture timeout stage="+stage+" controller="+blocks.evidence(c));
            observe();var s=observation.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
            if(!s.player().equals(playerId))throw new IllegalStateException("Drops observed player differs");
            ticks++;refreshAim(c);
            if(expected!=null){resume(c,s,now);return;}
            create(c,s,now);
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||c.getServer()==null||!c.isIntegratedServerRunning()||!c.options.getPerspective().isFirstPerson())throw new IllegalStateException("Owned first-person integrated client required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true);
        initial=c.player.getPos();double x=2.5,z=.5;
        if(nativeMode){var direction=nativeSample.view().forward();var flat=new Vec3d(direction.x,0,direction.z);if(flat.lengthSquared()<.1)throw new IllegalStateException("Native view too vertical for bounded pickup walk");forward=flat.normalize();var target=initial.add(forward.multiply(2.5));x=Math.floor(target.x)+.5;z=Math.floor(target.z)+.5;}
        if(!movement.surface().containsFeet(x,z,.3))throw new IllegalStateException("Drop target lacks captured terrain");
        base=BlockPos.ofFloored(x,movement.surface().heightAt(x,z),z);begun=stageAt=System.nanoTime();
    }
    private void create(MinecraftClient c,State s,long now)throws IOException{
        switch(stage){
            case 0->{
                if(!s.mode().equals("creative")||s.stone()!=0||s.cobble()!=0||s.tools()!=0||!s.drops().isEmpty()||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("Unexpected fresh drops world state");
                if(!images.containsKey("empty"))return;
                send(c,"gamemode survival");send(c,"item replace entity @s hotbar.0 with minecraft:stone 2");send(c,"item replace entity @s hotbar.1 with minecraft:iron_pickaxe");next(1,now);
            }
            case 1->{
                if(!s.mode().equals("survival")||s.stone()!=2||s.tools()!=1||s.damage()!=0||!c.player.getMainHandStack().isOf(Items.STONE))return;
                terrainTarget=true;aimTarget=new Vec3d(base.getX()+.5,movement.surface().heightAt(base.getX()+.5,base.getZ()+.5),base.getZ()+.5);refreshAim(c);edge(c,7,1);edge(c,8,1);actionAt=now;next(2,now);
            }
            case 2->{
                if(s.at()<=actionAt||blocks.evidence(c).get("pending").getAsBoolean())return;
                if(!s.block().equals("minecraft:stone")||!GameplayBlocks.stateName(c.world.getBlockState(base)).equals(s.block())||!blocks.ownedBlocks().equals(Set.of(base))||s.stone()!=1)throw new IllegalStateException("Survival ground placement did not confirm");
                placed=true;key(c,'2');terrainTarget=false;aimTarget=Vec3d.ofCenter(base);next(3,now);
            }
            case 3->{
                if(s.selected()!=1||!c.player.getMainHandStack().isOf(Items.IRON_PICKAXE))return;
                refreshAim(c);edge(c,7,0);actionAt=now;next(4,now);
            }
            case 4->{
                if(!s.block().equals("minecraft:air")||!c.world.getBlockState(base).isAir()||!blocks.ownedBlocks().isEmpty()||blocks.evidence(c).get("pending").getAsBoolean())return;
                edge(c,8,0);aimTarget=null;
                if(blocks.evidence(c).get("survival_breaks").getAsLong()!=1||blocks.evidence(c).get("survival_preserved_ticks").getAsLong()<2||s.damage()!=1||s.tools()!=1||s.stone()!=1||s.cobble()!=0)throw new IllegalStateException("Vanilla held mining/durability differs: "+state(s));
                mined=durable=true;next(5,now);
            }
            case 5->{
                if(s.cobble()!=0||s.position().distanceTo(initial)>.05)throw new IllegalStateException("Drop picked up before actual walking");
                if(s.drops().isEmpty())return;if(s.drops().size()!=1)throw new IllegalStateException("Unexpected additional item entities");
                var d=s.drops().getFirst();if(!d.item().equals("minecraft:cobblestone")||d.count()!=1)throw new IllegalStateException("Mining produced wrong actual item");
                if(dropId==null){dropId=d.id();firstDropTick=s.tick();}else if(!dropId.equals(d.id()))throw new IllegalStateException("Drop identity changed before pickup");
                dropPosition=d.position();realDrop=true;
                double floor=movement.surface().groundForFeet(dropPosition.x,dropPosition.z,.125);
                if(!Double.isFinite(floor))throw new IllegalStateException("Invalid drop terrain height");
                if(dropPosition.y<floor-.02){
                    // The server snapshot can observe vanilla's spawn before
                    // its first ItemEntity tick resolves fractional terrain.
                    if(s.tick()-firstDropTick<=2)return;
                    throw new IllegalStateException("Item below captured terrain: position="+dropPosition+" floor="+floor+" grounded="+d.grounded()+" base="+base);
                }
                if(d.grounded()&&Math.abs(dropPosition.y-floor)<.05){if(atTick!=s.tick()){groundTicks++;atTick=s.tick();}}else groundTicks=0;
                if(groundTicks<12)return;grounded=true;
                if(!images.containsKey("dropped"))return;
                validateImage("dropped",true);rendered=true;
                if(nativeMode){
                    if(nativeDropDwellAt==0){nativeDropDwellAt=now;nativeDropStartedUtc=System.currentTimeMillis();}
                    if(now-nativeDropDwellAt<11_000_000_000L)return;
                    nativeDropCompletedUtc=System.currentTimeMillis();
                }
                pulseTick=s.tick();setKey(c,0);next(6,now);
            }
            case 6->{
                if(s.position().distanceTo(initial)>4){setKey(c,0);throw new IllegalStateException("Drops pickup walk exceeded four-metre bound");}
                if(!s.drops().isEmpty()){dropPosition=s.drops().getFirst().position();var delta=dropPosition.subtract(c.player.getPos());var horizontal=new Vec3d(delta.x,0,delta.z);if(horizontal.lengthSquared()>.01)forward=horizontal.normalize();}
                if(s.cobble()==0){
                    // Short ordinary key strides allow vanilla ground friction to
                    // settle between presses. The production boundary deliberately
                    // budgets a long possible downhill coast; never bypass it here.
                    if(key!=0&&s.tick()-pulseTick>=2){setKey(c,0);pulseTick=s.tick();}
                    else if(key==0&&s.tick()-pulseTick>=4){setKey(c,pickupKey(c));pulseTick=s.tick();walkPulses++;}
                    return;
                }
                setKey(c,0);movement.suspend(c);
                if(s.cobble()!=1||s.pickups()!=1||!s.drops().isEmpty()||s.position().distanceTo(initial)<.4||s.tools()!=1||s.damage()!=1)throw new IllegalStateException("Actual walking pickup evidence differs: "+state(s));
                picked=true;atTick=s.tick();next(7,now);
            }
            case 7->{
                if(s.tick()-atTick<12||count(c.player,Items.COBBLESTONE)!=1||!clientDrops(c).isEmpty())return;
                if(!images.containsKey("picked_up"))return;
                validateImage("empty",false);validateImage("picked_up",false);
                var proof=new JsonObject();proof.addProperty("schema",1);proof.addProperty("kind","minecome_gameplay_drops_witness_v1");proof.addProperty("world_id",save.id().toString());proof.addProperty("save",save.saveName());proof.add("state",state(s));
                save.verifyOwnership();Files.writeString(witness,proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);complete(c,true,null);
            }
            default->throw new IllegalStateException("Unknown drops stage");
        }
    }
    private void resume(MinecraftClient c,State s,long now){
        var saved=state(s);for(String key:List.of("player_id","mode","stone_count","cobble_count","pickaxe_count","pickaxe_damage","picked_up_stat"))if(!saved.get(key).equals(expected.get(key)))throw new IllegalStateException("Saved drops inventory differs: "+key);
        if(!s.drops().isEmpty()||!clientDrops(c).isEmpty()||!blocks.ownedBlocks().isEmpty()||!s.block().equals("minecraft:air"))throw new IllegalStateException("Collected entity or mined block reappeared on resume");
        if(count(c.player,Items.COBBLESTONE)!=1||count(c.player,Items.STONE)!=1||damage(c.player)!=1)return;
        if(!movement.evidence(c).get("resume_position_restored").getAsBoolean())return;
        if(!images.containsKey("resumed"))return;validateImage("resumed",false);resumed=true;complete(c,true,null);
    }
    private void refreshAim(MinecraftClient c){if(aimTarget==null)return;var eye=c.player.getEyePos();var delta=aimTarget.subtract(eye);double distance=delta.length();if(distance<=0||distance>4.5)throw new IllegalStateException("Drops action outside vanilla reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,terrainTarget?distance:-1,terrainTarget));}
    private void owner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Drops fixture owner changed");}
    private Box box(){return new Box(base.getX()-16,base.getY()-8,base.getZ()-16,base.getX()+16,base.getY()+8,base.getZ()+16);}
    private List<ItemEntity> clientDrops(MinecraftClient c){return c.world.getEntitiesByClass(ItemEntity.class,box(),e->!e.isRemoved()&&!e.getStack().isEmpty());}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);var w=server.getOverworld();
        if(!server.isOnThread()||p==null||p.getWorld()!=w||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Drops fixture server owner changed");
        var drops=new ArrayList<Drop>();for(var e:w.getEntitiesByClass(ItemEntity.class,box(),e->!e.isRemoved()&&!e.getStack().isEmpty()))drops.add(new Drop(e.getUuid(),Registries.ITEM.getId(e.getStack().getItem()).toString(),e.getStack().getCount(),e.getPos(),e.isOnGround()));
        observation.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p.interactionManager.getGameMode().getName(),p.getPos(),p.getInventory().selectedSlot,count(p,Items.STONE),count(p,Items.COBBLESTONE),count(p,Items.IRON_PICKAXE),damage(p),p.getStatHandler().getStat(Stats.PICKED_UP,Items.COBBLESTONE),GameplayBlocks.stateName(w.getBlockState(base)),List.copyOf(drops)));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private static int count(PlayerEntity p,net.minecraft.item.Item item){int count=0;for(int i=0;i<p.getInventory().size();i++){var stack=p.getInventory().getStack(i);if(stack.isOf(item))count+=stack.getCount();}return count;}
    private static int damage(PlayerEntity p){for(int i=0;i<p.getInventory().size();i++){var stack=p.getInventory().getStack(i);if(stack.isOf(Items.IRON_PICKAXE))return stack.getDamage();}return -1;}
    private void send(MinecraftClient c,String command){owner(c);c.getNetworkHandler().sendChatCommand(command);commands.add(command);}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++events,System.currentTimeMillis(),kind,code,0,0,0);}
    private void edge(MinecraftClient c,int kind,int button){blocks.event(c,event(kind,button));}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void setKey(MinecraftClient c,int desired){if(key==desired)return;long now=System.nanoTime();if(key!=0)movement.event(c,event(2,key),now);key=desired;if(key!=0)movement.event(c,event(1,key),now);}
    private int pickupKey(MinecraftClient c){
        if(!nativeMode)return 'W';
        if(nativeSample==null||!nativeSample.fresh()||dropPosition==null)return 0;
        var f=nativeSample.view().forward();f=new Vec3d(f.x,0,f.z).normalize();
        var d=dropPosition.subtract(c.player.getPos());double along=d.dotProduct(f),side=d.dotProduct(f.crossProduct(new Vec3d(0,1,0)));
        return Math.abs(along)>=Math.abs(side)?along>=0?'W':'S':side>=0?'D':'A';
    }
    private void next(int value,long now){stage=value;stageAt=now;ticks=0;}
    public String captureStage(){
        if(closing||finished||begun==0||ticks<12||nativeMode&&(nativeSample==null||!nativeSample.fresh()))return null;
        String name=expected!=null?"resumed":stage==0?"empty":stage==5&&grounded?"dropped":stage==7?"picked_up":null;
        return name==null||queued.contains(name)||images.containsKey(name)?null:name;
    }
    public void captured(HudReadback.Completed frame){
        if(closing||finished)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("drops_fixture_stage"))return;
        String name=meta.get("drops_fixture_stage").getAsString();if(!Set.of("empty","dropped","picked_up","resumed").contains(name)||!queued.add(name))return;
        if(!samples.offer(new Sample(name,frame)))failure.compareAndSet(null,"Drops capture queue full");
    }
    private void validateImage(String name,boolean hasDrop){
        var image=images.get(name);if(image==null)throw new IllegalStateException("Missing dropped-item pixels "+name);var meta=image.getAsJsonObject("metadata");
        if(meta.get("frame_format").getAsInt()!=2||meta.get("rendered_world_blocks").getAsInt()!=0||meta.get("dropped_item_render_count").getAsInt()!=(hasDrop?1:0)||
                !image.get("depth_finite_unit_range").getAsBoolean())throw new IllegalStateException("Drop world layer metadata differs: "+image);
        long pixels=image.get("world_pixels").getAsLong();if(hasDrop){
            var rendered=meta.getAsJsonArray("dropped_items");if(rendered.size()!=1||!rendered.get(0).getAsJsonObject().get("id").getAsString().equals(dropId.toString())||!rendered.get(0).getAsJsonObject().get("item").getAsString().equals("minecraft:cobblestone")||rendered.get(0).getAsJsonObject().get("count").getAsInt()!=1)throw new IllegalStateException("Rendered item is not the server's mined entity");
            if(pixels<100||image.get("world_with_depth_pixels").getAsLong()<pixels*.9)throw new IllegalStateException("Actual dropped-item model lacks visible same-frame depth pixels: "+image);
        }else if(pixels!=0)throw new IllegalStateException("Empty world retained dropped-item pixels: "+image);
    }
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();byte[] layers=f.layersBottomUp();HudLayerPixels.require(layers,f.width(),f.height());int plane=HudPixels.byteSize(f.width(),f.height());
        var raw=ByteBuffer.wrap(layers).order(ByteOrder.LITTLE_ENDIAN);long pixels=0,withDepth=0;boolean valid=true;
        for(int i=0;i<plane;i+=4){float d=raw.getFloat(plane*2+i);valid&=Float.isFinite(d)&&d>=0&&d<=1;if((layers[plane+i+3]&255)>8){pixels++;if(d>0&&d<1)withDepth++;}}
        byte[] rgba=HudPixels.straightTopLeft(Arrays.copyOfRange(layers,plane,plane*2),f.width(),f.height()),png=HudPixels.png(rgba,f.width(),f.height());String file="drops-"+sample.stage()+".png";Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);
        var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file);p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.addProperty("width",f.width());p.addProperty("height",f.height());p.addProperty("world_pixels",pixels);p.addProperty("world_with_depth_pixels",withDepth);p.addProperty("depth_finite_unit_range",valid);p.add("metadata",JsonParser.parseString(f.metadata()));images.put(sample.stage(),p);
    }
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static JsonObject state(State s){var j=new JsonObject();j.addProperty("player_id",s.player().toString());j.addProperty("mode",s.mode());j.addProperty("stone_count",s.stone());j.addProperty("cobble_count",s.cobble());j.addProperty("pickaxe_count",s.tools());j.addProperty("pickaxe_damage",s.damage());j.addProperty("picked_up_stat",s.pickups());j.add("position",vector(s.position()));return j;}
    private void complete(MinecraftClient c,boolean passed,String error){
        if(finished)return;finished=true;try{setKey(c,0);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_drops_fixture_v1");p.addProperty("mode",mode);p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",error);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("standalone_scripted",!nativeMode);p.addProperty("native_input_verified",false);p.addProperty("live_kcd_verified",false);p.addProperty("live_kcd_connected",nativeMode);p.addProperty("scripted_aiming",true);p.addProperty("scripted_movement_input",true);p.addProperty("native_camera_preserved",nativeMode);p.addProperty("direct_world_inventory_entity_writes",false);p.addProperty("position_writes_used",false);
        p.addProperty("survival_placement_verified",placed);p.addProperty("survival_mining_verified",mined);p.addProperty("real_drop_verified",realDrop);p.addProperty("drop_ground_collision_verified",grounded);p.addProperty("render_pixels_verified",rendered);p.addProperty("walking_pickup_verified",picked);p.addProperty("walking_pulses",walkPulses);p.addProperty("durability_verified",durable);p.addProperty("resume_verified",resumed);p.addProperty("grounded_drop_observations",groundTicks);p.addProperty("drop_id",dropId==null?null:dropId.toString());p.addProperty("scripted_view_writes",viewWrites);p.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);p.addProperty("last_stage",stage);
        p.addProperty("native_drop_started_utc_ms",nativeDropStartedUtc);p.addProperty("native_drop_completed_utc_ms",nativeDropCompletedUtc);
        p.addProperty("terrain_item_recoveries",dev.minecome.terrain.GroundCollision.itemRecoveries(true));
        var a=new JsonArray();commands.forEach(a::add);p.add("commands",a);a=new JsonArray();for(String name:List.of("empty","dropped","picked_up","resumed"))if(images.containsKey(name))a.add(images.get(name).deepCopy());p.add("images",a);var s=observation.get();if(s!=null)p.add("final_state",state(s));p.add("blocks",blocks.evidence(c));p.add("movement",movement.evidence(c));
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-drops-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    private void writeLoop(){long sequence=0;try{while(!closing){
        var sample=samples.poll();if(sample!=null)writeSample(sample);
        if(nativeMode){Thread.sleep(25);continue;}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("source_kind","standalone_hud_physical_view_fixture");p.addProperty("run",identity.run());p.addProperty("patch_run",movement.surface().run());p.addProperty("patch_sha256",movement.surface().sha256());p.addProperty("target_pid",identity.targetPid());p.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));p.addProperty("seq",++sequence);p.addProperty("utc_ms",System.currentTimeMillis());var f=forward;p.add("forward",vector(new Vec3d(f.x,-f.z,0)));p.add("up",vector(new Vec3d(0,0,1)));
        Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){setKey(c,0);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
