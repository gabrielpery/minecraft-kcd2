package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.hud.mixin.HudHandledScreenAccessor;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.block.Blocks;
import net.minecraft.block.entity.FurnaceBlockEntity;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ingame.*;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.*;
import net.minecraft.registry.Registries;
import net.minecraft.screen.*;
import net.minecraft.screen.slot.Slot;
import net.minecraft.server.MinecraftServer;
import net.minecraft.state.property.Properties;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Vanilla furnace ticks, real screen mouse packets and owned-save persistence.
 * Pinned Yarn1.21.1 AbstractFurnaceScreenHandler constructs input/fuel/output
 * slots0/1/2. Server-thread createNbt reads the furnace's vanilla timers without
 * changing them. No direct slot, inventory, block-entity or world writes occur.
 */
public final class GameplayFurnaceFixture {
    private static final String WITNESS="minecome-furnace-fixture.json";
    private record State(long at,int tick,UUID player,String mode,Vec3d position,int selected,
                         int furnaces,int cobble,int coal,int stone,int handler,int cursor,
                         boolean furnace,String block,String input,int inputs,String fuel,int fuels,
                         String output,int outputs,int burn,int cook,int total,boolean lit){}
    private record Click(int slot,int button){}
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
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(3);
    private final Map<String,JsonObject> images=new ConcurrentHashMap<>();
    private final Set<String> queued=new HashSet<>();
    private final ArrayDeque<Click> clicks=new ArrayDeque<>();
    private final List<String> commands=new ArrayList<>();
    private MinecraftServer server;
    private Object world,player;
    private UUID playerId;
    private HudVanillaUiAdapter ui;
    private BlockPos base;
    private Vec3d aimTarget,inventoryPosition;
    private GameplayAimReader.RenderSample nativeSample;
    private volatile Vec3d forward=new Vec3d(1,0,0);
    private volatile boolean closing,finished;
    private volatile long viewWrites;
    private boolean terrainTarget,placed,opened,smelted,fuelConsumed,preserved,collected,suppressed,rendered,resumed,walkingHeld;
    private int stage,ticks,lastClickTick=-1,inventoryTick,resumeStage,firstCook=-1,firstBurn,maxCook,firstSmeltingTick;
    private long begun,stageAt,events,actionAt,clickCount,nativeDwellAt,nativeStartedUtc,nativeCompletedUtc;
    private State savedInput;

    public GameplayFurnaceFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
                                  HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        nativeMode=mode.equals("furnace-native");
        if(!Set.of("furnace","furnace-resume","furnace-native").contains(mode)||!Boolean.getBoolean("minecome.gameplayWorldBlocks")||
            (nativeMode?Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayFurnaceCheck"):!Boolean.getBoolean("minecome.gameplayStandalone")))
            throw new IllegalArgumentException("Explicit WorldBlocks furnace fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();witness=save.directory().resolve(WITNESS);
        if((!nativeMode&&Files.exists(this.directory.resolve("host-view.json")))||Files.exists(this.directory.resolve("gameplay-furnace-fixture.json")))throw new IOException("Furnace fixture output exists");
        if(!mode.equals("furnace-resume")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Furnace fixture needs a new owned save");expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)throw new IOException("Missing owned furnace witness");
            var proof=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(proof.get("schema").getAsInt()!=1||!proof.get("kind").getAsString().equals("minecome_gameplay_furnace_witness_v1")||!proof.get("world_id").getAsString().equals(save.id().toString())||!proof.get("save").getAsString().equals(save.saveName()))throw new IOException("Furnace witness identity differs");
            expected=proof.getAsJsonObject("state");var b=proof.getAsJsonObject("furnace");base=new BlockPos(b.get("x").getAsInt(),b.get("y").getAsInt(),b.get("z").getAsInt());
            if(expected.get("input_count").getAsInt()!=1||expected.get("output_count").getAsInt()!=0||expected.get("stone_count").getAsInt()!=1||expected.get("burn_ticks").getAsInt()<=0)throw new IOException("Furnace witness did not save an active remaining input");
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayFurnaceFixture");worker.setDaemon(true);worker.start();
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
        if(!nativeMode)throw new IllegalStateException("Native furnace overload used by standalone fixture");
        if(closing||finished)return;
        if(begun!=0&&System.nanoTime()-begun>90_000_000_000L){complete(c,false,"Native furnace deadline exceeded");return;}
        if(begun==0){
            if(System.nanoTime()-created>90_000_000_000L){complete(c,false,"Native furnace never armed");return;}
            if(!armed||sample==null||!sample.fresh()||sample.schema()!=3||sample.perspective()!=0)return;
        }else if(!armed){complete(c,false,"Native furnace input authority lost");return;}
        nativeSample=sample;
        if(sample==null||!sample.fresh()||sample.perspective()!=0){setWalking(c,false);return;}
        tick(c);
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);owner(c);
            long now=System.nanoTime();if(now-begun>90_000_000_000L||now-stageAt>30_000_000_000L)throw new IllegalStateException("Furnace timeout stage="+stage+" resume="+resumeStage+" state="+state(observation.get()));
            observe();var s=observation.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
            if(!s.player().equals(playerId))throw new IllegalStateException("Furnace observed player differs");
            ticks++;refreshAim(c);
            if(!clicks.isEmpty()){if(s.tick()-lastClickTick>=2){click(c,clicks.removeFirst());lastClickTick=s.tick();}return;}
            if(s.tick()-lastClickTick<2)return;
            if(expected!=null){resume(c,s,now);return;}
            create(c,s,now);
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||c.getServer()==null||!c.isIntegratedServerRunning()||!c.options.getPerspective().isFirstPerson())throw new IllegalStateException("Owned first-person integrated client required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true);
        double x=2.5,z=.5;
        if(nativeMode){var f=nativeSample.view().forward();var flat=new Vec3d(f.x,0,f.z);if(flat.lengthSquared()<.1)throw new IllegalStateException("Native view too vertical");forward=flat.normalize();var target=c.player.getPos().add(forward.multiply(2.5));x=Math.floor(target.x)+.5;z=Math.floor(target.z)+.5;}
        if(base==null){if(!movement.surface().containsFeet(x,z,.3))throw new IllegalStateException("Furnace target lacks captured terrain");base=BlockPos.ofFloored(x,movement.surface().heightAt(x,z),z);}
        begun=stageAt=System.nanoTime();
    }
    private void create(MinecraftClient c,State s,long now)throws IOException{
        switch(stage){
            case 0->{
                if(!s.mode().equals("creative")||s.furnaces()!=0||s.cobble()!=0||s.coal()!=0||s.stone()!=0||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("Unexpected fresh furnace state");
                send(c,"gamemode survival");send(c,"item replace entity @s hotbar.0 with minecraft:furnace");send(c,"item replace entity @s hotbar.1 with minecraft:cobblestone 2");send(c,"item replace entity @s hotbar.2 with minecraft:coal");next(1,now);
            }
            case 1->{
                if(!s.mode().equals("survival")||s.furnaces()!=1||s.cobble()!=2||s.coal()!=1||!c.player.getMainHandStack().isOf(Items.FURNACE))return;
                terrainTarget=true;aimTarget=new Vec3d(base.getX()+.5,movement.surface().heightAt(base.getX()+.5,base.getZ()+.5),base.getZ()+.5);refreshAim(c);edge(c,7,1);edge(c,8,1);actionAt=now;next(2,now);
            }
            case 2->{
                if(s.at()<=actionAt||blocks.evidence(c).get("pending").getAsBoolean())return;
                if(!furnaceMatches(c,s)||s.furnaces()!=0)throw new IllegalStateException("Furnace placement failed: "+state(s));
                placed=true;key(c,'9');terrainTarget=false;aimTarget=Vec3d.ofCenter(base);next(3,now);
            }
            case 3->{if(s.selected()!=8||!c.player.getMainHandStack().isEmpty())return;refreshAim(c);edge(c,7,1);edge(c,8,1);next(4,now);}
            case 4->{
                if(!(c.currentScreen instanceof FurnaceScreen)||s.handler()!=1)return;
                handler(c);opened=true;aimTarget=null;
                enqueue(playerSlot(c,1),0);enqueue(0,1);enqueue(playerSlot(c,1),0);enqueue(playerSlot(c,2),0);enqueue(1,0);next(5,now);
            }
            case 5->{
                if(s.inputs()!=1||!s.input().equals("minecraft:cobblestone")||s.cobble()!=1||s.coal()!=0||s.fuels()!=0||s.burn()<=0||!s.lit()||s.cook()<=0||s.total()!=200||s.cursor()!=0)return;
                if(firstCook<0){firstCook=s.cook();firstBurn=s.burn();firstSmeltingTick=s.tick();inventoryPosition=s.position();inventoryTick=s.tick();setWalking(c,true);if(nativeMode){nativeDwellAt=now;nativeStartedUtc=System.currentTimeMillis();}}
                maxCook=Math.max(maxCook,s.cook());
                if(s.position().distanceTo(inventoryPosition)>.02)throw new IllegalStateException("Furnace screen allowed world walking");
                if(s.tick()-inventoryTick<8||s.cook()<=firstCook||s.burn()>=firstBurn||!images.containsKey("smelting"))return;
                setWalking(c,false);suppressed=true;fuelConsumed=true;validateImage("smelting","FurnaceScreen");rendered=true;next(6,now);
            }
            case 6->{
                maxCook=Math.max(maxCook,s.cook());
                if(!stoneOutput(c,s)||s.inputs()!=0||s.stone()!=0||!images.containsKey("result"))return;
                if(s.tick()-firstSmeltingTick<200-firstCook)throw new IllegalStateException("Furnace output preceded vanilla cook duration");
                validateImage("result","FurnaceScreen");smelted=true;
                if(nativeMode){if(now-nativeDwellAt<11_000_000_000L)return;nativeCompletedUtc=System.currentTimeMillis();}
                enqueue(2,0);enqueue(playerSlot(c,3),0);next(7,now);
            }
            case 7->{
                if(s.stone()!=1||s.outputs()!=0||s.inputs()!=0||s.cursor()!=0)return;
                collected=true;enqueue(playerSlot(c,1),0);enqueue(0,0);next(8,now);
            }
            case 8->{
                if(s.inputs()!=1||!s.input().equals("minecraft:cobblestone")||s.cobble()!=0||s.stone()!=1||s.cursor()!=0)return;
                key(c,'E');next(9,now);
            }
            case 9->{
                if(c.currentScreen!=null||s.handler()!=0||s.cursor()!=0||s.inputs()!=1||s.outputs()!=0||s.cobble()!=0||s.stone()!=1||s.burn()<=0||!images.containsKey("closed"))return;
                if(!furnaceMatches(c,s))throw new IllegalStateException("Furnace disappeared after closing its screen");
                validateImage("closed","none");preserved=true;savedInput=s;
                if(!nativeMode){writeWitness(s);complete(c,true,null);return;}
                terrainTarget=false;aimTarget=Vec3d.ofCenter(base);refreshAim(c);edge(c,7,1);edge(c,8,1);next(10,now);
            }
            case 10->{if(!(c.currentScreen instanceof FurnaceScreen)||s.handler()!=1)return;aimTarget=null;remaining(s);next(11,now);}
            case 11->{if(!stoneOutput(c,s)||s.inputs()!=0)return;enqueue(2,0);enqueue(playerSlot(c,3),0);next(12,now);}
            case 12->{if(s.stone()!=2||s.outputs()!=0||s.inputs()!=0||s.cursor()!=0)return;key(c,'E');next(13,now);}
            case 13->{if(c.currentScreen==null&&s.handler()==0&&s.cursor()==0&&s.stone()==2&&s.inputs()==0&&s.outputs()==0)complete(c,true,null);}
            default->throw new IllegalStateException("Unknown furnace stage");
        }
    }
    private void resume(MinecraftClient c,State s,long now){
        if(!furnaceMatches(c,s))throw new IllegalStateException("Saved furnace missing");
        if(resumeStage==0){
            var actual=state(s);for(String name:List.of("player_id","mode","furnace_count","cobblestone_count","coal_count","stone_count"))if(!actual.get(name).equals(expected.get(name)))throw new IllegalStateException("Saved furnace state differs: "+name);
            remaining(s);if(s.fuels()!=0||s.burn()>expected.get("burn_ticks").getAsInt())throw new IllegalStateException("Saved furnace fuel differs");
            if(!movement.evidence(c).get("resume_position_restored").getAsBoolean())return;
            if(count(c.player,Items.STONE)!=1||count(c.player,Items.COBBLESTONE)!=0)return;
            preserved=true;fuelConsumed=true;savedInput=s;key(c,'9');terrainTarget=false;aimTarget=Vec3d.ofCenter(base);resumeStage=1;
        }else if(resumeStage==1){
            if(s.selected()!=8||!c.player.getMainHandStack().isEmpty())return;
            refreshAim(c);edge(c,7,1);edge(c,8,1);resumeStage=2;stageAt=now;
        }else if(resumeStage==2){
            if(!(c.currentScreen instanceof FurnaceScreen)||s.handler()!=1)return;
            opened=true;aimTarget=null;remaining(s);
            if(!stoneOutput(c,s)||!images.containsKey("resumed"))return;
            validateImage("resumed","FurnaceScreen");rendered=true;smelted=true;enqueue(2,0);enqueue(playerSlot(c,3),0);resumeStage=3;
        }else if(resumeStage==3){
            if(s.stone()!=2||s.cursor()!=0||s.inputs()!=0||s.outputs()!=0)return;
            collected=true;key(c,'E');resumeStage=4;
        }else if(c.currentScreen==null&&s.handler()==0&&s.cursor()==0){resumed=true;complete(c,true,null);}
    }
    private void writeWitness(State s)throws IOException{
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_furnace_witness_v1");p.addProperty("world_id",save.id().toString());p.addProperty("save",save.saveName());p.add("state",state(s));p.add("furnace",position());
        save.verifyOwnership();Files.writeString(witness,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
    }
    private static void remaining(State s){if(s.inputs()+s.outputs()!=1||s.inputs()>0&&!s.input().equals("minecraft:cobblestone")||s.outputs()>0&&!s.output().equals("minecraft:stone")||s.cobble()!=0||s.stone()!=1)throw new IllegalStateException("Remaining furnace ingredient/output not conserved: "+state(s));}
    private boolean furnaceMatches(MinecraftClient c,State s){return s.furnace()&&c.world.getBlockState(base).isOf(Blocks.FURNACE)&&blocks.ownedBlocks().equals(Set.of(base));}
    private void refreshAim(MinecraftClient c){if(aimTarget==null||c.currentScreen!=null)return;var eye=c.player.getEyePos();var delta=aimTarget.subtract(eye);double distance=delta.length();if(distance<=0||distance>4.5)throw new IllegalStateException("Furnace target outside vanilla reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,terrainTarget?distance:-1,terrainTarget));}
    private void owner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Furnace fixture owner changed");}
    private static int count(PlayerEntity p,Item item){int n=0;for(int i=0;i<p.getInventory().size();i++){var stack=p.getInventory().getStack(i);if(stack.isOf(item))n+=stack.getCount();}return n;}
    private static String item(ItemStack stack){return Registries.ITEM.getId(stack.getItem()).toString();}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);var w=server.getOverworld();
        if(!server.isOnThread()||p==null||p.getWorld()!=w||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Furnace server owner changed");
        var h=p.currentScreenHandler;var block=w.getBlockState(base);var entity=w.getBlockEntity(base);boolean furnace=block.isOf(Blocks.FURNACE)&&entity instanceof FurnaceBlockEntity;
        ItemStack input=ItemStack.EMPTY,fuel=ItemStack.EMPTY,output=ItemStack.EMPTY;int burn=0,cook=0,total=0;
        if(furnace){var be=(FurnaceBlockEntity)entity;input=be.getStack(0);fuel=be.getStack(1);output=be.getStack(2);var nbt=be.createNbt(w.getRegistryManager());burn=nbt.getShort("BurnTime");cook=nbt.getShort("CookTime");total=nbt.getShort("CookTimeTotal");}
        observation.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p.interactionManager.getGameMode().getName(),p.getPos(),p.getInventory().selectedSlot,
            count(p,Items.FURNACE),count(p,Items.COBBLESTONE),count(p,Items.COAL),count(p,Items.STONE),h instanceof FurnaceScreenHandler?1:h==p.playerScreenHandler?0:-1,h.getCursorStack().getCount(),
            furnace,GameplayBlocks.stateName(block),item(input),input.getCount(),item(fuel),fuel.getCount(),item(output),output.getCount(),burn,cook,total,furnace&&block.get(Properties.LIT)));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private FurnaceScreenHandler handler(MinecraftClient c){
        if(!(c.currentScreen instanceof FurnaceScreen screen))throw new IllegalStateException("No actual furnace screen");
        var h=screen.getScreenHandler();if(h!=c.player.currentScreenHandler||h.syncId<=0||h.getCraftingResultSlotIndex()!=2||h.slots.size()!=39)throw new IllegalStateException("No actual owned vanilla furnace handler");return h;
    }
    private int playerSlot(MinecraftClient c,int index){return handler(c).slots.stream().filter(s->s.inventory==c.player.getInventory()&&s.getIndex()==index).findFirst().orElseThrow().id;}
    private boolean stoneOutput(MinecraftClient c,State s){return s.outputs()==1&&s.output().equals("minecraft:stone")&&handler(c).getSlot(2).getStack().isOf(Items.STONE)&&handler(c).getSlot(2).getStack().getCount()==1;}
    private void enqueue(int slot,int button){clicks.addLast(new Click(slot,button));}
    private void click(MinecraftClient c,Click action){
        var h=handler(c);var screen=(HandledScreen<?>)c.currentScreen;var origin=(HudHandledScreenAccessor)screen;Slot slot=h.getSlot(action.slot());
        double x=(origin.minecome$originX()+slot.x+8.0)/screen.width,y=(origin.minecome$originY()+slot.y+8.0)/screen.height;
        if(x<=0||x>=1||y<=0||y>=1)throw new IllegalStateException("Furnace slot outside current screen");
        ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),4,action.button(),(float)x,(float)y,0));ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),5,action.button(),(float)x,(float)y,0));clickCount++;
    }
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++events,System.currentTimeMillis(),kind,code,0,0,0);}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void edge(MinecraftClient c,int kind,int button){blocks.event(c,event(kind,button));}
    private void setWalking(MinecraftClient c,boolean held){if(walkingHeld==held)return;walkingHeld=held;movement.event(c,event(held?1:2,'W'),System.nanoTime());}
    private void send(MinecraftClient c,String command){owner(c);c.getNetworkHandler().sendChatCommand(command);commands.add(command);}
    private void next(int value,long now){stage=value;stageAt=now;ticks=0;}
    public String captureStage(){
        if(closing||finished||begun==0||ticks<12||!clicks.isEmpty()||nativeMode&&(nativeSample==null||!nativeSample.fresh()))return null;
        var c=MinecraftClient.getInstance();String name=expected!=null&&resumeStage==2&&c.currentScreen instanceof FurnaceScreen?"resumed":expected!=null?null:
            stage==5&&c.currentScreen instanceof FurnaceScreen&&handler(c).isBurning()&&handler(c).getCookProgress()>0?"smelting":
            stage==6&&c.currentScreen instanceof FurnaceScreen&&handler(c).getSlot(2).getStack().isOf(Items.STONE)?"result":stage==9&&c.currentScreen==null?"closed":null;
        return name==null||queued.contains(name)||images.containsKey(name)?null:name;
    }
    public void captured(HudReadback.Completed frame){
        if(closing||finished)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("furnace_fixture_stage"))return;
        String name=meta.get("furnace_fixture_stage").getAsString();if(!Set.of("smelting","result","closed","resumed").contains(name)||!queued.add(name))return;
        if(!samples.offer(new Sample(name,frame)))failure.compareAndSet(null,"Furnace capture queue full");
    }
    private void validateImage(String name,String screen){
        var image=images.get(name);if(image==null)throw new IllegalStateException("Missing furnace image "+name);var m=image.getAsJsonObject("metadata");
        if(!m.get("screen_kind").getAsString().equals(screen)||m.get("frame_format").getAsInt()!=2||image.get("hud_pixels").getAsLong()<1000)throw new IllegalStateException("Furnace screen pixels differ: "+image);
        if(!screen.equals("none")&&(!m.get("state").getAsString().equals("inventory")||m.get("screen").getAsInt()!=1))throw new IllegalStateException("Furnace did not use inventory input mode");
    }
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();byte[] layers=f.layersBottomUp();HudLayerPixels.require(layers,f.width(),f.height());int plane=HudPixels.byteSize(f.width(),f.height());long pixels=0;
        for(int i=3;i<plane;i+=4)if((layers[i]&255)>8)pixels++;
        byte[] rgba=HudPixels.straightTopLeft(Arrays.copyOfRange(layers,0,plane),f.width(),f.height()),png=HudPixels.png(rgba,f.width(),f.height());String file="furnace-"+sample.stage()+".png";Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);
        var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file);p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.addProperty("width",f.width());p.addProperty("height",f.height());p.addProperty("hud_pixels",pixels);p.add("metadata",JsonParser.parseString(f.metadata()));images.put(sample.stage(),p);
    }
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private JsonObject position(){var j=new JsonObject();j.addProperty("x",base.getX());j.addProperty("y",base.getY());j.addProperty("z",base.getZ());return j;}
    private static JsonObject state(State s){
        var j=new JsonObject();if(s==null)return j;j.addProperty("player_id",s.player().toString());j.addProperty("mode",s.mode());j.addProperty("furnace_count",s.furnaces());j.addProperty("cobblestone_count",s.cobble());j.addProperty("coal_count",s.coal());j.addProperty("stone_count",s.stone());j.addProperty("handler",s.handler());j.addProperty("cursor_count",s.cursor());j.addProperty("block_entity_present",s.furnace());j.addProperty("block",s.block());j.addProperty("input",s.input());j.addProperty("input_count",s.inputs());j.addProperty("fuel",s.fuel());j.addProperty("fuel_count",s.fuels());j.addProperty("output",s.output());j.addProperty("output_count",s.outputs());j.addProperty("burn_ticks",s.burn());j.addProperty("cook_ticks",s.cook());j.addProperty("cook_total_ticks",s.total());j.addProperty("lit",s.lit());j.addProperty("server_tick",s.tick());j.add("position",vector(s.position()));return j;
    }
    private void complete(MinecraftClient c,boolean passed,String error){
        if(finished)return;finished=true;try{setWalking(c,false);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_furnace_fixture_v1");p.addProperty("mode",mode);p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",error);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("standalone_scripted",!nativeMode);p.addProperty("native_input_verified",false);p.addProperty("live_kcd_verified",false);p.addProperty("live_kcd_connected",nativeMode);p.addProperty("scripted_aiming",true);p.addProperty("scripted_mouse_input",true);p.addProperty("native_camera_preserved",nativeMode);p.addProperty("direct_world_inventory_entity_writes",false);p.addProperty("position_writes_used",false);p.addProperty("recipe_fill_used",false);p.addProperty("furnace_timer_writes_used",false);
        p.addProperty("furnace_placement_verified",placed);p.addProperty("furnace_open_verified",opened);p.addProperty("smelting_verified",smelted);p.addProperty("fuel_consumption_verified",fuelConsumed);p.addProperty("inventory_suppression_verified",suppressed);p.addProperty("input_persistence_verified",preserved);p.addProperty("output_collection_verified",collected);p.addProperty("render_pixels_verified",rendered);p.addProperty("resume_verified",resumed);p.addProperty("mouse_clicks",clickCount);p.addProperty("scripted_view_writes",viewWrites);p.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);p.addProperty("last_stage",stage);p.addProperty("resume_stage",resumeStage);p.addProperty("first_cook_ticks",firstCook);p.addProperty("max_observed_cook_ticks",maxCook);p.addProperty("first_burn_ticks",firstBurn);
        p.addProperty("native_furnace_started_utc_ms",nativeStartedUtc);p.addProperty("native_furnace_completed_utc_ms",nativeCompletedUtc);
        var a=new JsonArray();commands.forEach(a::add);p.add("commands",a);a=new JsonArray();for(String name:List.of("smelting","result","closed","resumed"))if(images.containsKey(name))a.add(images.get(name).deepCopy());p.add("images",a);var s=observation.get();if(s!=null)p.add("final_state",state(s));if(savedInput!=null)p.add("preserved_state",state(savedInput));if(base!=null)p.add("furnace",position());if(ui!=null)p.add("pointer",ui.pointerDiagnostics());p.add("blocks",blocks.evidence(c));p.add("movement",movement.evidence(c));
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-furnace-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    private void writeLoop(){long sequence=0;try{while(!closing){
        var sample=samples.poll();if(sample!=null)writeSample(sample);
        if(nativeMode){Thread.sleep(25);continue;}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("source_kind","standalone_hud_physical_view_fixture");p.addProperty("run",identity.run());p.addProperty("patch_run",movement.surface().run());p.addProperty("patch_sha256",movement.surface().sha256());p.addProperty("target_pid",identity.targetPid());p.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));p.addProperty("seq",++sequence);p.addProperty("utc_ms",System.currentTimeMillis());var f=forward;p.add("forward",vector(new Vec3d(f.x,-f.z,0)));p.add("up",vector(new Vec3d(0,0,1)));
        Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){setWalking(c,false);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
