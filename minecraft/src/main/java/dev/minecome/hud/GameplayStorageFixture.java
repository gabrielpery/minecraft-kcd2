package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.hud.mixin.HudHandledScreenAccessor;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.block.Blocks;
import net.minecraft.block.entity.BarrelBlockEntity;
import net.minecraft.entity.ItemEntity;
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

/** Real vanilla barrel slots, UI mouse packets, save/reload and survival drops.
 * Pinned Yarn1.21.1 BarrelBlockEntity uses GenericContainerScreenHandler9x3;
 * its server inventory is observed only. Source: runtime/evidence/barrel-source-20261117.
 * Seed commands affect only the isolated test player's inventory.
 */
public final class GameplayStorageFixture {
    private static final String WITNESS="minecome-storage-fixture.json";
    private record SlotState(int slot,String item,int count,String components){}
    private record Drop(UUID id,String item,int count){}
    private record State(long at,int tick,UUID player,String mode,Vec3d position,int selected,
                         int barrels,int diamonds,int cobble,int axes,int axeDamage,int handler,int cursor,
                         boolean barrel,String block,boolean open,List<SlotState> slots,List<Drop> drops){}
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
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(5);
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
    private boolean terrainTarget,placed,opened,deposited,preserved,collected,suppressed,rendered,resumed,mined,dropsVerified,walkingHeld;
    private int stage,ticks,lastClickTick=-1,inventoryTick,resumeStage;
    private long begun,stageAt,events,actionAt,clickCount,nativeDwellAt,nativeStartedUtc,nativeCompletedUtc;
    private State savedInput;


    public GameplayStorageFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
                                  HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        nativeMode=mode.equals("storage-native");
        if(!Set.of("storage","storage-resume","storage-native").contains(mode)||!Boolean.getBoolean("minecome.gameplayWorldBlocks")||
            (nativeMode?Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayStorageCheck"):!Boolean.getBoolean("minecome.gameplayStandalone")))
            throw new IllegalArgumentException("Explicit WorldBlocks storage fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();witness=save.directory().resolve(WITNESS);
        if((!nativeMode&&Files.exists(this.directory.resolve("host-view.json")))||Files.exists(this.directory.resolve("gameplay-storage-fixture.json")))throw new IOException("Storage fixture output exists");
        if(!mode.equals("storage-resume")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Storage fixture needs a new owned save");expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)throw new IOException("Missing owned storage witness");
            var proof=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(proof.get("schema").getAsInt()!=1||!proof.get("kind").getAsString().equals("minecome_gameplay_storage_witness_v1")||!proof.get("world_id").getAsString().equals(save.id().toString())||!proof.get("save").getAsString().equals(save.saveName()))throw new IOException("Storage witness identity differs");
            expected=proof.getAsJsonObject("state");var b=proof.getAsJsonObject("storage");base=new BlockPos(b.get("x").getAsInt(),b.get("y").getAsInt(),b.get("z").getAsInt());
            if(expected.get("diamond_count").getAsInt()!=2||expected.get("cobblestone_count").getAsInt()!=0||expected.get("slots").getAsJsonArray().size()!=27||expected.get("open").getAsBoolean())throw new IOException("Storage witness inventory/closed state differs");
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayStorageFixture");worker.setDaemon(true);worker.start();
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
        if(!nativeMode)throw new IllegalStateException("Native storage overload used by standalone fixture");
        if(closing||finished)return;
        if(begun!=0&&System.nanoTime()-begun>90_000_000_000L){complete(c,false,"Native storage deadline exceeded");return;}
        if(begun==0){
            if(System.nanoTime()-created>90_000_000_000L){complete(c,false,"Native storage never armed");return;}
            if(!armed||sample==null||!sample.fresh()||sample.schema()!=3||sample.perspective()!=0)return;
        }else if(!armed){complete(c,false,"Native storage input authority lost");return;}
        nativeSample=sample;
        if(sample==null||!sample.fresh()||sample.perspective()!=0){setWalking(c,false);return;}
        tick(c);
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);owner(c);
            long now=System.nanoTime();if(now-begun>90_000_000_000L||now-stageAt>30_000_000_000L)throw new IllegalStateException("Storage timeout stage="+stage+" resume="+resumeStage+" state="+state(observation.get()));
            observe();var s=observation.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
            if(!s.player().equals(playerId))throw new IllegalStateException("Storage observed player differs");
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
        if(base==null){if(!movement.surface().containsFeet(x,z,.3))throw new IllegalStateException("Storage target lacks captured terrain");base=BlockPos.ofFloored(x,movement.surface().heightAt(x,z),z);}
        begun=stageAt=System.nanoTime();
    }
    private void create(MinecraftClient c,State s,long now)throws IOException{
        switch(stage){
            case 0->{
                if(!s.mode().equals("creative")||s.barrels()!=0||s.diamonds()!=0||s.cobble()!=0||s.axes()!=0||!s.drops().isEmpty()||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("Unexpected fresh storage state");
                send(c,"gamemode survival");send(c,"item replace entity @s hotbar.0 with minecraft:barrel");send(c,"item replace entity @s hotbar.1 with minecraft:diamond 7");send(c,"item replace entity @s hotbar.2 with minecraft:cobblestone 16");send(c,"item replace entity @s hotbar.3 with minecraft:iron_axe");next(1,now);
            }
            case 1->{
                if(!s.mode().equals("survival")||s.barrels()!=1||s.diamonds()!=7||s.cobble()!=16||s.axes()!=1||!c.player.getMainHandStack().isOf(Items.BARREL))return;
                terrainTarget=true;aimTarget=new Vec3d(base.getX()+.5,movement.surface().heightAt(base.getX()+.5,base.getZ()+.5),base.getZ()+.5);refreshAim(c);edge(c,7,1);edge(c,8,1);actionAt=now;next(2,now);
            }
            case 2->{
                if(s.at()<=actionAt||blocks.evidence(c).get("pending").getAsBoolean())return;
                if(!storageMatches(c,s)||s.barrels()!=0)throw new IllegalStateException("Barrel placement failed: "+state(s));
                placed=true;key(c,'9');terrainTarget=false;aimTarget=Vec3d.ofCenter(base);next(3,now);
            }
            case 3->{if(s.selected()!=8||!c.player.getMainHandStack().isEmpty())return;refreshAim(c);edge(c,7,1);edge(c,8,1);next(4,now);}
            case 4->{
                if(!(c.currentScreen instanceof GenericContainerScreen)||s.handler()!=1||!s.open())return;
                handler(c);opened=true;aimTarget=null;
                enqueue(playerSlot(c,1),0);enqueue(0,0);enqueue(playerSlot(c,2),0);enqueue(26,0);next(5,now);
            }
            case 5->{
                if(s.diamonds()!=0||s.cobble()!=0||s.cursor()!=0||!contents(s,7,16)||!s.open())return;
                deposited=true;
                if(inventoryPosition==null){inventoryPosition=s.position();inventoryTick=s.tick();setWalking(c,true);if(nativeMode){nativeDwellAt=now;nativeStartedUtc=System.currentTimeMillis();}}
                if(s.position().distanceTo(inventoryPosition)>.02)throw new IllegalStateException("Storage screen allowed world walking");
                if(s.tick()-inventoryTick<8||!images.containsKey("stored")||nativeMode&&now-nativeDwellAt<11_000_000_000L)return;
                setWalking(c,false);suppressed=true;validateImage("stored","GenericContainerScreen");rendered=true;
                if(nativeMode)nativeCompletedUtc=System.currentTimeMillis();
                enqueue(0,0);enqueue(playerSlot(c,1),1);enqueue(playerSlot(c,1),1);enqueue(0,0);next(6,now);
            }
            case 6->{if(s.diamonds()!=2||s.cobble()!=0||s.cursor()!=0||!contents(s,5,16))return;collected=true;key(c,'E');next(7,now);}
            case 7->{
                if(c.currentScreen!=null||s.handler()!=0||s.cursor()!=0||s.open()||!images.containsKey("closed"))return;
                if(!storageMatches(c,s)||!contents(s,5,16))throw new IllegalStateException("Closed barrel lost its contents");
                validateImage("closed","none");preserved=true;savedInput=s;
                terrainTarget=false;aimTarget=Vec3d.ofCenter(base);refreshAim(c);edge(c,7,1);edge(c,8,1);next(8,now);
            }
            case 8->{
                if(!(c.currentScreen instanceof GenericContainerScreen)||s.handler()!=1||!s.open()||!contents(s,5,16)||!images.containsKey("reopened"))return;
                aimTarget=null;validateImage("reopened","GenericContainerScreen");key(c,'E');next(9,now);
            }
            case 9->{
                if(c.currentScreen!=null||s.handler()!=0||s.cursor()!=0||s.open())return;
                if(!contents(s,5,16)||s.diamonds()!=2)throw new IllegalStateException("Reopened barrel inventory changed");
                savedInput=s;
                if(!nativeMode){writeWitness(s);complete(c,true,null);return;}
                key(c,'4');aimTarget=Vec3d.ofCenter(base);next(10,now);
            }
            case 10->{if(s.selected()!=3||!c.player.getMainHandStack().isOf(Items.IRON_AXE))return;refreshAim(c);edge(c,7,0);next(11,now);}
            case 11->{if(verifyBreak(c,s,5,2)){next(12,now);}}
            case 12->{if(!images.containsKey("dropped"))return;validateImage("dropped","none");complete(c,true,null);}
            default->throw new IllegalStateException("Unknown storage stage");
        }
    }
    private void resume(MinecraftClient c,State s,long now){
        if(resumeStage==0){
            if(!storageMatches(c,s))throw new IllegalStateException("Saved barrel missing");
            var actual=state(s);for(String name:List.of("player_id","mode","barrel_count","diamond_count","cobblestone_count","axe_count","axe_damage","slots","block","open"))if(!actual.get(name).equals(expected.get(name)))throw new IllegalStateException("Saved storage state differs: "+name);
            if(!contents(s,5,16)||!s.drops().isEmpty())throw new IllegalStateException("Saved storage content conservation differs");
            if(!movement.evidence(c).get("resume_position_restored").getAsBoolean()||count(c.player,Items.DIAMOND)!=2)return;
            preserved=true;savedInput=s;key(c,'9');terrainTarget=false;aimTarget=Vec3d.ofCenter(base);resumeStage=1;
        }else if(resumeStage==1){
            if(s.selected()!=8||!c.player.getMainHandStack().isEmpty())return;
            refreshAim(c);edge(c,7,1);edge(c,8,1);resumeStage=2;stageAt=now;
        }else if(resumeStage==2){
            if(!(c.currentScreen instanceof GenericContainerScreen)||s.handler()!=1||!s.open()||!contents(s,5,16)||!images.containsKey("resumed"))return;
            opened=true;aimTarget=null;validateImage("resumed","GenericContainerScreen");rendered=resumed=true;
            enqueue(0,0);enqueue(playerSlot(c,1),1);enqueue(0,0);resumeStage=3;
        }else if(resumeStage==3){
            if(s.diamonds()!=3||s.cursor()!=0||!contents(s,4,16))return;
            collected=true;key(c,'E');resumeStage=4;
        }else if(resumeStage==4){
            if(c.currentScreen!=null||s.handler()!=0||s.open()||s.cursor()!=0)return;
            key(c,'4');aimTarget=Vec3d.ofCenter(base);resumeStage=5;
        }else if(resumeStage==5){
            if(s.selected()!=3||!c.player.getMainHandStack().isOf(Items.IRON_AXE))return;
            refreshAim(c);edge(c,7,0);resumeStage=6;
        }else if(resumeStage==6){if(verifyBreak(c,s,4,3)){resumeStage=7;}}
        else if(images.containsKey("dropped")){validateImage("dropped","none");complete(c,true,null);}
    }
    private boolean verifyBreak(MinecraftClient c,State s,int diamondDrops,int playerDiamonds){
        if(!s.block().equals("minecraft:air")||!c.world.getBlockState(base).isAir()||!blocks.ownedBlocks().isEmpty()||blocks.evidence(c).get("pending").getAsBoolean())return false;
        edge(c,8,0);aimTarget=null;
        if(s.barrel()||s.axes()!=1||s.axeDamage()!=1||s.diamonds()!=playerDiamonds||s.cobble()!=0||s.barrels()!=0||blocks.evidence(c).get("survival_breaks").getAsLong()!=1)throw new IllegalStateException("Barrel mining/player inventory differs: "+state(s));
        var counts=new HashMap<String,Integer>();for(var d:s.drops())counts.merge(d.item(),d.count(),Integer::sum);
        if(!counts.equals(Map.of("minecraft:barrel",1,"minecraft:diamond",diamondDrops,"minecraft:cobblestone",16)))throw new IllegalStateException("Barrel contents were lost or duplicated on break: "+state(s));
        mined=dropsVerified=true;return true;
    }
    private void writeWitness(State s)throws IOException{
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_storage_witness_v1");p.addProperty("world_id",save.id().toString());p.addProperty("save",save.saveName());p.add("state",state(s));p.add("storage",position());
        save.verifyOwnership();Files.writeString(witness,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
    }
    private static boolean contents(State s,int diamonds,int cobble){
        if(!s.barrel()||s.slots().size()!=27)return false;
        for(var slot:s.slots()){
            String wanted=slot.slot()==0?"minecraft:diamond":slot.slot()==26?"minecraft:cobblestone":"minecraft:air";
            int count=slot.slot()==0?diamonds:slot.slot()==26?cobble:0;
            if(!slot.item().equals(wanted)||slot.count()!=count)return false;
        }return true;
    }
    private boolean storageMatches(MinecraftClient c,State s){return s.barrel()&&c.world.getBlockState(base).isOf(Blocks.BARREL)&&blocks.ownedBlocks().equals(Set.of(base));}
    private void refreshAim(MinecraftClient c){if(aimTarget==null||c.currentScreen!=null)return;var eye=c.player.getEyePos();var delta=aimTarget.subtract(eye);double distance=delta.length();if(distance<=0||distance>4.5)throw new IllegalStateException("Storage target outside vanilla reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,terrainTarget?distance:-1,terrainTarget));}
    private void owner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Storage fixture owner changed");}
    private static int count(PlayerEntity p,Item item){int n=0;for(int i=0;i<p.getInventory().size();i++){var stack=p.getInventory().getStack(i);if(stack.isOf(item))n+=stack.getCount();}return n;}
    private static String item(ItemStack stack){return Registries.ITEM.getId(stack.getItem()).toString();}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);var w=server.getOverworld();
        if(!server.isOnThread()||p==null||p.getWorld()!=w||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Storage server owner changed");
        var h=p.currentScreenHandler;var block=w.getBlockState(base);var entity=w.getBlockEntity(base);boolean barrel=block.isOf(Blocks.BARREL)&&entity instanceof BarrelBlockEntity;
        var slots=new ArrayList<SlotState>();if(barrel){var be=(BarrelBlockEntity)entity;if(be.size()!=27)throw new IllegalStateException("Vanilla barrel size changed");for(int i=0;i<be.size();i++){var stack=be.getStack(i);slots.add(new SlotState(i,item(stack),stack.getCount(),GameplayRangedUse.componentIdentity(stack,w.getRegistryManager()).toString()));}}
        var drops=new ArrayList<Drop>();var box=new Box(base.getX()-8,base.getY()-8,base.getZ()-8,base.getX()+8,base.getY()+8,base.getZ()+8);
        for(var e:w.getEntitiesByClass(ItemEntity.class,box,e->!e.isRemoved()&&!e.getStack().isEmpty()))drops.add(new Drop(e.getUuid(),item(e.getStack()),e.getStack().getCount()));
        int axeDamage=-1;for(int i=0;i<p.getInventory().size();i++){var stack=p.getInventory().getStack(i);if(stack.isOf(Items.IRON_AXE))axeDamage=stack.getDamage();}
        observation.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p.interactionManager.getGameMode().getName(),p.getPos(),p.getInventory().selectedSlot,
            count(p,Items.BARREL),count(p,Items.DIAMOND),count(p,Items.COBBLESTONE),count(p,Items.IRON_AXE),axeDamage,h instanceof GenericContainerScreenHandler generic&&generic.getRows()==3&&generic.getInventory()==entity?1:h==p.playerScreenHandler?0:-1,h.getCursorStack().getCount(),
            barrel,GameplayBlocks.stateName(block),barrel&&block.get(Properties.OPEN),List.copyOf(slots),List.copyOf(drops)));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private GenericContainerScreenHandler handler(MinecraftClient c){
        if(!(c.currentScreen instanceof GenericContainerScreen screen))throw new IllegalStateException("No actual storage screen");
        var h=screen.getScreenHandler();if(h!=c.player.currentScreenHandler||h.syncId<=0||h.getRows()!=3||h.getInventory().size()!=27||h.slots.size()!=63)throw new IllegalStateException("No actual vanilla barrel handler");return h;
    }
    private int playerSlot(MinecraftClient c,int index){return handler(c).slots.stream().filter(s->s.inventory==c.player.getInventory()&&s.getIndex()==index).findFirst().orElseThrow().id;}
    private void enqueue(int slot,int button){clicks.addLast(new Click(slot,button));}
    private void click(MinecraftClient c,Click action){
        var h=handler(c);var screen=(HandledScreen<?>)c.currentScreen;var origin=(HudHandledScreenAccessor)screen;Slot slot=h.getSlot(action.slot());
        double x=(origin.minecome$originX()+slot.x+8.0)/screen.width,y=(origin.minecome$originY()+slot.y+8.0)/screen.height;
        if(x<=0||x>=1||y<=0||y>=1)throw new IllegalStateException("Storage slot outside current screen");
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
        var c=MinecraftClient.getInstance();String name;
        if(expected!=null)name=resumeStage==2&&c.currentScreen instanceof GenericContainerScreen?"resumed":resumeStage==7&&c.currentScreen==null?"dropped":null;
        else name=stage==5&&c.currentScreen instanceof GenericContainerScreen?"stored":stage==7&&c.currentScreen==null?"closed":stage==8&&c.currentScreen instanceof GenericContainerScreen?"reopened":stage==12&&c.currentScreen==null?"dropped":null;
        return name==null||queued.contains(name)||images.containsKey(name)?null:name;
    }
    public void captured(HudReadback.Completed frame){
        if(closing||finished)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("storage_fixture_stage"))return;
        String name=meta.get("storage_fixture_stage").getAsString();if(!Set.of("stored","closed","reopened","resumed","dropped").contains(name)||!queued.add(name))return;
        if(!samples.offer(new Sample(name,frame)))failure.compareAndSet(null,"Storage capture queue full");
    }
    private void validateImage(String name,String screen){
        var image=images.get(name);if(image==null)throw new IllegalStateException("Missing storage image "+name);var m=image.getAsJsonObject("metadata");
        if(!m.get("screen_kind").getAsString().equals(screen)||m.get("frame_format").getAsInt()!=2||image.get("hud_pixels").getAsLong()<1000)throw new IllegalStateException("Storage screen pixels differ: "+image);
        if(!screen.equals("none")&&(!m.get("state").getAsString().equals("inventory")||m.get("screen").getAsInt()!=1))throw new IllegalStateException("Storage did not use inventory input mode");
    }
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();byte[] layers=f.layersBottomUp();HudLayerPixels.require(layers,f.width(),f.height());int plane=HudPixels.byteSize(f.width(),f.height());long pixels=0;
        for(int i=3;i<plane;i+=4)if((layers[i]&255)>8)pixels++;
        byte[] rgba=HudPixels.straightTopLeft(Arrays.copyOfRange(layers,0,plane),f.width(),f.height()),png=HudPixels.png(rgba,f.width(),f.height());String file="storage-"+sample.stage()+".png";Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);
        var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file);p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.addProperty("width",f.width());p.addProperty("height",f.height());p.addProperty("hud_pixels",pixels);p.add("metadata",JsonParser.parseString(f.metadata()));images.put(sample.stage(),p);
    }
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private JsonObject position(){var j=new JsonObject();j.addProperty("x",base.getX());j.addProperty("y",base.getY());j.addProperty("z",base.getZ());return j;}
    private static JsonObject state(State s){
        var j=new JsonObject();if(s==null)return j;j.addProperty("player_id",s.player().toString());j.addProperty("mode",s.mode());j.addProperty("barrel_count",s.barrels());j.addProperty("diamond_count",s.diamonds());j.addProperty("cobblestone_count",s.cobble());j.addProperty("axe_count",s.axes());j.addProperty("axe_damage",s.axeDamage());j.addProperty("handler",s.handler());j.addProperty("cursor_count",s.cursor());j.addProperty("block_entity_present",s.barrel());j.addProperty("block",s.block());j.addProperty("open",s.open());j.addProperty("server_tick",s.tick());j.add("position",vector(s.position()));
        var slots=new JsonArray();for(var slot:s.slots()){var v=new JsonObject();v.addProperty("slot",slot.slot());v.addProperty("item",slot.item());v.addProperty("count",slot.count());v.add("components",JsonParser.parseString(slot.components()));slots.add(v);}j.add("slots",slots);
        var drops=new JsonArray();for(var d:s.drops()){var v=new JsonObject();v.addProperty("id",d.id().toString());v.addProperty("item",d.item());v.addProperty("count",d.count());drops.add(v);}j.add("drops",drops);return j;
    }
    private void complete(MinecraftClient c,boolean passed,String error){
        if(finished)return;finished=true;try{setWalking(c,false);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_storage_fixture_v1");p.addProperty("mode",mode);p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",error);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("standalone_scripted",!nativeMode);p.addProperty("native_input_verified",false);p.addProperty("live_kcd_verified",false);p.addProperty("live_kcd_connected",nativeMode);p.addProperty("scripted_aiming",true);p.addProperty("scripted_mouse_input",true);p.addProperty("native_camera_preserved",nativeMode);p.addProperty("direct_world_inventory_entity_writes",false);p.addProperty("position_writes_used",false);p.addProperty("container_slot_writes_used",false);
        p.addProperty("barrel_placement_verified",placed);p.addProperty("barrel_open_verified",opened);p.addProperty("deposit_verified",deposited);p.addProperty("inventory_suppression_verified",suppressed);p.addProperty("contents_persistence_verified",preserved);p.addProperty("retrieval_verified",collected);p.addProperty("render_pixels_verified",rendered);p.addProperty("resume_verified",resumed);p.addProperty("survival_mining_verified",mined);p.addProperty("contents_drops_verified",dropsVerified);p.addProperty("mouse_clicks",clickCount);p.addProperty("scripted_view_writes",viewWrites);p.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);p.addProperty("last_stage",stage);p.addProperty("resume_stage",resumeStage);
        p.addProperty("native_storage_started_utc_ms",nativeStartedUtc);p.addProperty("native_storage_completed_utc_ms",nativeCompletedUtc);
        var a=new JsonArray();commands.forEach(a::add);p.add("commands",a);a=new JsonArray();for(String name:List.of("stored","closed","reopened","resumed","dropped"))if(images.containsKey(name))a.add(images.get(name).deepCopy());p.add("images",a);var s=observation.get();if(s!=null)p.add("final_state",state(s));if(savedInput!=null)p.add("preserved_state",state(savedInput));if(base!=null)p.add("storage",position());if(ui!=null)p.add("pointer",ui.pointerDiagnostics());p.add("blocks",blocks.evidence(c));p.add("movement",movement.evidence(c));
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-storage-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    private void writeLoop(){long sequence=0;try{while(!closing){
        var sample=samples.poll();if(sample!=null)writeSample(sample);
        if(nativeMode){Thread.sleep(25);continue;}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("source_kind","standalone_hud_physical_view_fixture");p.addProperty("run",identity.run());p.addProperty("patch_run",movement.surface().run());p.addProperty("patch_sha256",movement.surface().sha256());p.addProperty("target_pid",identity.targetPid());p.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));p.addProperty("seq",++sequence);p.addProperty("utc_ms",System.currentTimeMillis());var f=forward;p.add("forward",vector(new Vec3d(f.x,-f.z,0)));p.add("up",vector(new Vec3d(0,0,1)));
        Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){setWalking(c,false);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
