package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.hud.mixin.HudHandledScreenAccessor;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ingame.*;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.*;
import net.minecraft.registry.Registries;
import net.minecraft.screen.*;
import net.minecraft.screen.slot.Slot;
import net.minecraft.server.MinecraftServer;
import net.minecraft.stat.Stats;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual vanilla recipe/output clicks, owned workbench interaction and persistence.
 * Pinned Yarn1.21.1 PlayerScreenHandler/CraftingScreenHandler expose result slot0
 * and row-major crafting inputs1..4/1..9. Player slots are resolved by inventory
 * identity/index, screen pixels by the existing HandledScreen origin accessor.
 * No ScreenHandler.onSlotClick, recipe fill, inventory or world writes are used.
 */
public final class GameplayCraftingFixture {
    private static final String WITNESS="minecome-crafting-fixture.json";
    private record State(long at,int tick,UUID player,String mode,Vec3d position,int selected,
                         int logs,int planks,int sticks,int tables,int picks,int craftedPlanks,int craftedSticks,
                         int craftedTables,int craftedPicks,int handler,int inputs,int cursor,String output,String block){}
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
    private Vec3d aimTarget,initial,inventoryPosition;
    private GameplayAimReader.RenderSample nativeSample;
    private volatile Vec3d forward=new Vec3d(1,0,0);
    private volatile boolean closing,finished;
    private volatile long viewWrites;
    private boolean terrainTarget,inventoryCrafted,tablePlaced,tableOpened,tableCrafted,returned,suppressed,rendered,resumed,walkingHeld;
    private int stage,ticks,lastClickTick=-1,inventoryTick,resumeStage;
    private long begun,stageAt,events,actionAt,clickCount,nativeDwellAt,nativeStartedUtc,nativeCompletedUtc;

    public GameplayCraftingFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
                                   HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        nativeMode=mode.equals("crafting-native");
        if(!Set.of("crafting","crafting-resume","crafting-native").contains(mode)||!Boolean.getBoolean("minecome.gameplayWorldBlocks")||
            (nativeMode?Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayCraftingCheck"):!Boolean.getBoolean("minecome.gameplayStandalone")))
            throw new IllegalArgumentException("Explicit WorldBlocks crafting fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();witness=save.directory().resolve(WITNESS);
        if((!nativeMode&&Files.exists(this.directory.resolve("host-view.json")))||Files.exists(this.directory.resolve("gameplay-crafting-fixture.json")))throw new IOException("Crafting fixture output exists");
        if(!mode.equals("crafting-resume")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Crafting fixture needs a new owned save");expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)throw new IOException("Missing owned crafting witness");
            var proof=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(proof.get("schema").getAsInt()!=1||!proof.get("kind").getAsString().equals("minecome_gameplay_crafting_witness_v1")||!proof.get("world_id").getAsString().equals(save.id().toString())||!proof.get("save").getAsString().equals(save.saveName()))throw new IOException("Crafting witness identity differs");
            expected=proof.getAsJsonObject("state");var b=proof.getAsJsonObject("table");base=new BlockPos(b.get("x").getAsInt(),b.get("y").getAsInt(),b.get("z").getAsInt());
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayCraftingFixture");worker.setDaemon(true);worker.start();
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
        if(!nativeMode)throw new IllegalStateException("Native crafting overload used by standalone fixture");
        if(closing||finished)return;
        if(begun!=0&&System.nanoTime()-begun>90_000_000_000L){complete(c,false,"Native crafting deadline exceeded");return;}
        if(begun==0){
            if(System.nanoTime()-created>90_000_000_000L){complete(c,false,"Native crafting never armed");return;}
            if(!armed||sample==null||!sample.fresh()||sample.schema()!=3||sample.perspective()!=0)return;
        }else if(!armed){complete(c,false,"Native crafting input authority lost");return;}
        nativeSample=sample;
        if(sample==null||!sample.fresh()||sample.perspective()!=0){setWalking(c,false);return;}
        tick(c);
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);owner(c);
            long now=System.nanoTime();if(now-begun>90_000_000_000L||now-stageAt>25_000_000_000L)throw new IllegalStateException("Crafting timeout stage="+stage+" state="+state(observation.get()));
            observe();var s=observation.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
            if(!s.player().equals(playerId))throw new IllegalStateException("Crafting observed player differs");
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
        initial=c.player.getPos();double x=2.5,z=.5;
        if(nativeMode){var f=nativeSample.view().forward();var flat=new Vec3d(f.x,0,f.z);if(flat.lengthSquared()<.1)throw new IllegalStateException("Native view too vertical");forward=flat.normalize();var target=initial.add(forward.multiply(2.5));x=Math.floor(target.x)+.5;z=Math.floor(target.z)+.5;}
        if(base==null){if(!movement.surface().containsFeet(x,z,.3))throw new IllegalStateException("Workbench target lacks captured terrain");base=BlockPos.ofFloored(x,movement.surface().heightAt(x,z),z);}
        begun=stageAt=System.nanoTime();
    }
    private void create(MinecraftClient c,State s,long now)throws IOException{
        switch(stage){
            case 0->{
                if(!s.mode().equals("creative")||s.logs()!=0||s.planks()!=0||s.sticks()!=0||s.tables()!=0||s.picks()!=0||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("Unexpected fresh crafting state");
                send(c,"gamemode survival");send(c,"item replace entity @s hotbar.0 with minecraft:oak_log 3");next(1,now);
            }
            case 1->{if(!s.mode().equals("survival")||s.logs()!=3||count(c.player,Items.OAK_LOG)!=3)return;key(c,'E');next(2,now);}
            case 2->{
                if(!(c.currentScreen instanceof InventoryScreen)||s.handler()!=0)return;
                var h=handler(c);requireGrid(h,2);enqueue(playerSlot(c,0),0);enqueue(1,0);next(3,now);
            }
            case 3->{
                if(!output(c,s,Items.OAK_PLANKS))return;
                enqueue(0,0);enqueue(0,0);enqueue(0,0);enqueue(playerSlot(c,0),0);next(4,now);
            }
            case 4->{
                if(s.logs()!=0||s.planks()!=12||s.inputs()!=0||s.cursor()!=0)return;
                enqueue(playerSlot(c,0),0);for(int i=1;i<=4;i++)enqueue(i,1);enqueue(playerSlot(c,0),0);next(5,now);
            }
            case 5->{
                if(!output(c,s,Items.CRAFTING_TABLE)||!images.containsKey("inventory_recipe"))return;
                validateImage("inventory_recipe","InventoryScreen");enqueue(0,0);enqueue(playerSlot(c,1),0);next(6,now);
            }
            case 6->{
                if(s.tables()!=1||s.planks()!=8||s.inputs()!=0||s.cursor()!=0)return;
                enqueue(playerSlot(c,0),0);enqueue(1,1);enqueue(3,1);enqueue(playerSlot(c,0),0);next(7,now);
            }
            case 7->{if(!output(c,s,Items.STICK))return;enqueue(0,0);enqueue(playerSlot(c,2),0);next(8,now);}
            case 8->{
                if(s.planks()!=6||s.sticks()!=4||s.tables()!=1||s.inputs()!=0||s.cursor()!=0||s.craftedPlanks()!=12||s.craftedSticks()!=4||s.craftedTables()!=1)return;
                inventoryCrafted=true;key(c,'E');key(c,'2');next(9,now);
            }
            case 9->{
                if(c.currentScreen!=null||s.selected()!=1||!c.player.getMainHandStack().isOf(Items.CRAFTING_TABLE))return;
                terrainTarget=true;aimTarget=new Vec3d(base.getX()+.5,movement.surface().heightAt(base.getX()+.5,base.getZ()+.5),base.getZ()+.5);refreshAim(c);edge(c,7,1);edge(c,8,1);actionAt=now;next(10,now);
            }
            case 10->{
                if(s.at()<=actionAt||blocks.evidence(c).get("pending").getAsBoolean())return;
                if(!tableMatches(c,s)||s.tables()!=0)throw new IllegalStateException("Crafted table placement failed: "+state(s));
                tablePlaced=true;key(c,'9');terrainTarget=false;aimTarget=Vec3d.ofCenter(base);next(11,now);
            }
            case 11->{
                if(s.selected()!=8||!c.player.getMainHandStack().isEmpty())return;
                refreshAim(c);edge(c,7,1);edge(c,8,1);next(12,now);
            }
            case 12->{
                if(!(c.currentScreen instanceof CraftingScreen)||s.handler()!=1)return;
                requireGrid(handler(c),3);tableOpened=true;aimTarget=null;
                enqueue(playerSlot(c,0),0);enqueue(1,1);enqueue(2,1);enqueue(3,1);enqueue(playerSlot(c,0),0);
                enqueue(playerSlot(c,2),0);enqueue(5,1);enqueue(8,1);enqueue(playerSlot(c,2),0);next(13,now);
            }
            case 13->{
                if(!output(c,s,Items.WOODEN_PICKAXE))return;
                if(inventoryPosition==null){inventoryPosition=s.position();inventoryTick=s.tick();setWalking(c,true);}
                if(s.position().distanceTo(inventoryPosition)>.02)throw new IllegalStateException("Crafting screen allowed world walking");
                if(s.tick()-inventoryTick<8||!images.containsKey("table_recipe"))return;
                setWalking(c,false);suppressed=true;validateImage("table_recipe","CraftingScreen");rendered=true;
                if(nativeMode){if(nativeDwellAt==0){nativeDwellAt=now;nativeStartedUtc=System.currentTimeMillis();}if(now-nativeDwellAt<11_000_000_000L)return;nativeCompletedUtc=System.currentTimeMillis();}
                enqueue(0,0);enqueue(playerSlot(c,3),0);next(14,now);
            }
            case 14->{
                if(s.picks()!=1||s.planks()!=3||s.sticks()!=2||s.craftedPicks()!=1||s.inputs()!=0||s.cursor()!=0)return;
                tableCrafted=true;enqueue(playerSlot(c,0),0);enqueue(1,1);enqueue(playerSlot(c,0),0);next(15,now);
            }
            case 15->{
                if(s.inputs()!=1||s.planks()!=2||s.cursor()!=0)return;
                key(c,'E');next(16,now);
            }
            case 16->{
                if(c.currentScreen!=null||s.handler()!=0||s.inputs()!=0||s.cursor()!=0||s.planks()!=3||s.sticks()!=2||s.picks()!=1)return;
                if(!tableMatches(c,s)||!images.containsKey("closed"))return;
                validateImage("closed","none");returned=true;
                var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_crafting_witness_v1");p.addProperty("world_id",save.id().toString());p.addProperty("save",save.saveName());p.add("state",state(s));p.add("table",table());
                save.verifyOwnership();Files.writeString(witness,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);complete(c,true,null);
            }
            default->throw new IllegalStateException("Unknown crafting stage");
        }
    }
    private void resume(MinecraftClient c,State s,long now){
        if(!tableMatches(c,s))throw new IllegalStateException("Saved crafting table missing");
        if(resumeStage==0){
            var actual=state(s);for(String name:List.of("player_id","mode","log_count","plank_count","stick_count","table_count","wooden_pickaxe_count","crafted_planks","crafted_sticks","crafted_tables","crafted_pickaxes"))if(!actual.get(name).equals(expected.get(name)))throw new IllegalStateException("Saved crafting state differs: "+name);
            if(!movement.evidence(c).get("resume_position_restored").getAsBoolean())return;
            if(count(c.player,Items.OAK_PLANKS)!=3||count(c.player,Items.STICK)!=2||count(c.player,Items.WOODEN_PICKAXE)!=1)return;
            key(c,'9');terrainTarget=false;aimTarget=Vec3d.ofCenter(base);resumeStage=1;
        }else if(resumeStage==1){
            if(s.selected()!=8||!c.player.getMainHandStack().isEmpty())return;
            refreshAim(c);edge(c,7,1);edge(c,8,1);resumeStage=2;
        }else if(resumeStage==2){
            if(!(c.currentScreen instanceof CraftingScreen)||s.handler()!=1||s.inputs()!=0||s.cursor()!=0)return;
            tableOpened=true;aimTarget=null;if(!images.containsKey("resumed"))return;validateImage("resumed","CraftingScreen");key(c,'E');resumeStage=3;
        }else if(c.currentScreen==null&&s.handler()==0&&s.inputs()==0&&s.cursor()==0){resumed=true;complete(c,true,null);}
    }
    private boolean tableMatches(MinecraftClient c,State s){return s.block().equals("minecraft:crafting_table")&&GameplayBlocks.stateName(c.world.getBlockState(base)).equals(s.block())&&blocks.ownedBlocks().equals(Set.of(base));}
    private void refreshAim(MinecraftClient c){if(aimTarget==null||c.currentScreen!=null)return;var eye=c.player.getEyePos();var delta=aimTarget.subtract(eye);double distance=delta.length();if(distance<=0||distance>4.5)throw new IllegalStateException("Crafting target outside vanilla reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,terrainTarget?distance:-1,terrainTarget));}
    private void owner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Crafting fixture owner changed");}
    private static int count(PlayerEntity p,Item item){int n=0;for(int i=0;i<p.getInventory().size();i++){var stack=p.getInventory().getStack(i);if(stack.isOf(item))n+=stack.getCount();}return n;}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);var w=server.getOverworld();
        if(!server.isOnThread()||p==null||p.getWorld()!=w||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Crafting server owner changed");
        var h=p.currentScreenHandler;int inputs=0;String output="minecraft:air";
        if(h instanceof AbstractRecipeScreenHandler<?,?> recipe){for(int i=1;i<recipe.getCraftingSlotCount();i++)inputs+=h.getSlot(i).getStack().getCount();output=Registries.ITEM.getId(h.getSlot(recipe.getCraftingResultSlotIndex()).getStack().getItem()).toString();}
        observation.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p.interactionManager.getGameMode().getName(),p.getPos(),p.getInventory().selectedSlot,
            count(p,Items.OAK_LOG),count(p,Items.OAK_PLANKS),count(p,Items.STICK),count(p,Items.CRAFTING_TABLE),count(p,Items.WOODEN_PICKAXE),
            p.getStatHandler().getStat(Stats.CRAFTED,Items.OAK_PLANKS),p.getStatHandler().getStat(Stats.CRAFTED,Items.STICK),p.getStatHandler().getStat(Stats.CRAFTED,Items.CRAFTING_TABLE),p.getStatHandler().getStat(Stats.CRAFTED,Items.WOODEN_PICKAXE),
            h instanceof CraftingScreenHandler?1:h==p.playerScreenHandler?0:-1,inputs,h.getCursorStack().getCount(),output,GameplayBlocks.stateName(w.getBlockState(base))));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private AbstractRecipeScreenHandler<?,?> handler(MinecraftClient c){if(!(c.currentScreen instanceof HandledScreen<?> screen)||!(screen.getScreenHandler() instanceof AbstractRecipeScreenHandler<?,?> h)||h!=c.player.currentScreenHandler)throw new IllegalStateException("No actual owned crafting handler");return h;}
    private static void requireGrid(AbstractRecipeScreenHandler<?,?> h,int width){if(h.getCraftingWidth()!=width||h.getCraftingHeight()!=width||h.getCraftingResultSlotIndex()!=0||h.getCraftingSlotCount()!=width*width+1)throw new IllegalStateException("Vanilla crafting layout differs");}
    private int playerSlot(MinecraftClient c,int index){return handler(c).slots.stream().filter(s->s.inventory==c.player.getInventory()&&s.getIndex()==index).findFirst().orElseThrow().id;}
    private boolean output(MinecraftClient c,State s,Item item){return s.output().equals(Registries.ITEM.getId(item).toString())&&handler(c).getSlot(0).getStack().isOf(item);}
    private void enqueue(int slot,int button){clicks.addLast(new Click(slot,button));}
    private void click(MinecraftClient c,Click action){
        var h=handler(c);var screen=(HandledScreen<?>)c.currentScreen;var origin=(HudHandledScreenAccessor)screen;Slot slot=h.getSlot(action.slot());
        double x=(origin.minecome$originX()+slot.x+8.0)/screen.width,y=(origin.minecome$originY()+slot.y+8.0)/screen.height;
        if(x<=0||x>=1||y<=0||y>=1)throw new IllegalStateException("Crafting slot outside current screen");
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
        var c=MinecraftClient.getInstance();String name=expected!=null&&resumeStage==2&&c.currentScreen instanceof CraftingScreen?"resumed":expected!=null?null:
            stage==5&&c.currentScreen instanceof InventoryScreen&&handler(c).getSlot(0).getStack().isOf(Items.CRAFTING_TABLE)?"inventory_recipe":
            stage==13&&c.currentScreen instanceof CraftingScreen&&handler(c).getSlot(0).getStack().isOf(Items.WOODEN_PICKAXE)?"table_recipe":stage==16&&c.currentScreen==null?"closed":null;
        return name==null||queued.contains(name)||images.containsKey(name)?null:name;
    }
    public void captured(HudReadback.Completed frame){
        if(closing||finished)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("crafting_fixture_stage"))return;
        String name=meta.get("crafting_fixture_stage").getAsString();if(!Set.of("inventory_recipe","table_recipe","closed","resumed").contains(name)||!queued.add(name))return;
        if(!samples.offer(new Sample(name,frame)))failure.compareAndSet(null,"Crafting capture queue full");
    }
    private void validateImage(String name,String screen){
        var image=images.get(name);if(image==null)throw new IllegalStateException("Missing crafting image "+name);var m=image.getAsJsonObject("metadata");
        if(!m.get("screen_kind").getAsString().equals(screen)||m.get("frame_format").getAsInt()!=2||image.get("hud_pixels").getAsLong()<1000)throw new IllegalStateException("Crafting screen pixels differ: "+image);
        if(!screen.equals("none")&&(!m.get("state").getAsString().equals("inventory")||m.get("screen").getAsInt()!=1))throw new IllegalStateException("Crafting did not use inventory input mode");
    }
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();byte[] layers=f.layersBottomUp();HudLayerPixels.require(layers,f.width(),f.height());int plane=HudPixels.byteSize(f.width(),f.height());long pixels=0;
        for(int i=3;i<plane;i+=4)if((layers[i]&255)>8)pixels++;
        byte[] rgba=HudPixels.straightTopLeft(Arrays.copyOfRange(layers,0,plane),f.width(),f.height()),png=HudPixels.png(rgba,f.width(),f.height());String file="crafting-"+sample.stage()+".png";Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);
        var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file);p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.addProperty("width",f.width());p.addProperty("height",f.height());p.addProperty("hud_pixels",pixels);p.add("metadata",JsonParser.parseString(f.metadata()));images.put(sample.stage(),p);
    }
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private JsonObject table(){var j=new JsonObject();j.addProperty("x",base.getX());j.addProperty("y",base.getY());j.addProperty("z",base.getZ());return j;}
    private static JsonObject state(State s){
        var j=new JsonObject();if(s==null)return j;j.addProperty("player_id",s.player().toString());j.addProperty("mode",s.mode());j.addProperty("log_count",s.logs());j.addProperty("plank_count",s.planks());j.addProperty("stick_count",s.sticks());j.addProperty("table_count",s.tables());j.addProperty("wooden_pickaxe_count",s.picks());
        j.addProperty("crafted_planks",s.craftedPlanks());j.addProperty("crafted_sticks",s.craftedSticks());j.addProperty("crafted_tables",s.craftedTables());j.addProperty("crafted_pickaxes",s.craftedPicks());j.addProperty("crafting_inputs",s.inputs());j.addProperty("cursor_count",s.cursor());j.addProperty("handler",s.handler());j.add("position",vector(s.position()));return j;
    }
    private void complete(MinecraftClient c,boolean passed,String error){
        if(finished)return;finished=true;try{setWalking(c,false);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_crafting_fixture_v1");p.addProperty("mode",mode);p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",error);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("standalone_scripted",!nativeMode);p.addProperty("native_input_verified",false);p.addProperty("live_kcd_verified",false);p.addProperty("live_kcd_connected",nativeMode);p.addProperty("scripted_aiming",true);p.addProperty("scripted_mouse_input",true);p.addProperty("native_camera_preserved",nativeMode);p.addProperty("direct_world_inventory_entity_writes",false);p.addProperty("position_writes_used",false);p.addProperty("recipe_fill_used",false);
        p.addProperty("inventory_crafting_verified",inventoryCrafted);p.addProperty("table_placement_verified",tablePlaced);p.addProperty("table_open_verified",tableOpened);p.addProperty("table_crafting_verified",tableCrafted);p.addProperty("ingredient_return_verified",returned);p.addProperty("inventory_suppression_verified",suppressed);p.addProperty("render_pixels_verified",rendered);p.addProperty("resume_verified",resumed);p.addProperty("mouse_clicks",clickCount);p.addProperty("scripted_view_writes",viewWrites);p.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);p.addProperty("last_stage",stage);p.addProperty("resume_stage",resumeStage);
        p.addProperty("native_crafting_started_utc_ms",nativeStartedUtc);p.addProperty("native_crafting_completed_utc_ms",nativeCompletedUtc);
        var a=new JsonArray();commands.forEach(a::add);p.add("commands",a);a=new JsonArray();for(String name:List.of("inventory_recipe","table_recipe","closed","resumed"))if(images.containsKey(name))a.add(images.get(name).deepCopy());p.add("images",a);var s=observation.get();if(s!=null)p.add("final_state",state(s));if(base!=null)p.add("table",table());if(ui!=null)p.add("pointer",ui.pointerDiagnostics());p.add("blocks",blocks.evidence(c));p.add("movement",movement.evidence(c));
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-crafting-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    private void writeLoop(){long sequence=0;try{while(!closing){
        var sample=samples.poll();if(sample!=null)writeSample(sample);
        if(nativeMode){Thread.sleep(25);continue;}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("source_kind","standalone_hud_physical_view_fixture");p.addProperty("run",identity.run());p.addProperty("patch_run",movement.surface().run());p.addProperty("patch_sha256",movement.surface().sha256());p.addProperty("target_pid",identity.targetPid());p.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));p.addProperty("seq",++sequence);p.addProperty("utc_ms",System.currentTimeMillis());var f=forward;p.add("forward",vector(new Vec3d(f.x,-f.z,0)));p.add("up",vector(new Vec3d(0,0,1)));
        Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){setWalking(c,false);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
