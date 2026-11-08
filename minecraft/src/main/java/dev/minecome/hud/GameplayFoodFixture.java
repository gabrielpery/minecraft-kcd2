package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.effect.StatusEffects;
import net.minecraft.item.Items;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.world.GameRules;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual vanilla eating and persistence through the sustained right-button controller. */
public final class GameplayFoodFixture {
    private static final String WITNESS="minecome-food-fixture.json";
    private record State(UUID player,String mode,float health,int food,float saturation,float exhaustion,
                         boolean regeneration,boolean hunger,boolean using,int selected,int bread,int tick,long at){}
    private final String mode;
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
    private final List<String> commands=new ArrayList<>();
    private final JsonArray meals=new JsonArray();
    private MinecraftServer server;
    private Object world,player;
    private UUID playerId;
    private HudVanillaUiAdapter ui;
    private State baseline,holdBaseline,lastMeal;
    private long begun,events;
    private int stage,step,phase,atTick,firstTick,damageAfterTicks;
    private volatile boolean finished,closing;
    private volatile long viewWrites;
    private boolean earlyRelease,slotChange,inventoryInterrupt,authorityGate,modeChange,refilled,fullRejected,regenerated,resumed;

    public GameplayFoodFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
                               HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException {
        if(!Set.of("food","food-resume").contains(mode)||!Boolean.getBoolean("minecome.gameplayStandalone"))
            throw new IllegalArgumentException("Explicit standalone food fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();witness=save.directory().resolve(WITNESS);
        if(Files.exists(directory.resolve("host-view.json"))||Files.exists(directory.resolve("gameplay-food-fixture.json")))throw new IOException("Food fixture output already exists");
        if(mode.equals("food")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Food fixture requires a new owned save");
            expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)
                throw new IOException("Food resume requires its saved witness");
            var proof=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(proof.get("schema").getAsInt()!=1||!proof.get("kind").getAsString().equals("minecome_gameplay_food_witness_v1")||
                    !proof.get("world_id").getAsString().equals(save.id().toString())||!proof.get("save").getAsString().equals(save.saveName()))
                throw new IOException("Food witness belongs to another world");
            expected=proof.getAsJsonObject("state");
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayFoodFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){
        if(closing||finished||begun==0)return;
        try{owner(c);movement.authority(c,System.nanoTime(),true);}catch(Exception e){complete(c,false,e.toString());}
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready())return;
            if(begun==0){
                if(!c.isOnThread()||c.player==null||c.world==null||c.getServer()==null||!c.isIntegratedServerRunning())throw new IllegalStateException("Owned integrated client required");
                save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true);begun=System.nanoTime();
            }
            owner(c);long now=System.nanoTime();
            if(now-begun>60_000_000_000L)throw new IllegalStateException("Food fixture timed out stage="+stage+" step="+step+" phase="+phase+" controller="+blocks.evidence(c));
            observe();State s=observation.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
            if(!s.player().equals(playerId))throw new IllegalStateException("Observed player changed");
            if(!matches(c,s))return;
            if(firstTick==0)firstTick=s.tick();
            if(expected!=null){resume(c,s);return;}
            create(c,s);
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void create(MinecraftClient c,State s)throws IOException{
        switch(stage){
            case 0 -> {
                if(!s.mode().equals("creative")||s.health()!=20||s.food()!=20||s.bread()!=0)throw new IllegalStateException("Unexpected fresh-world state");
                send(c,"gamerule naturalRegeneration false");send(c,"gamemode survival");
                send(c,"item replace entity @s hotbar.0 with minecraft:bread 6");
                send(c,"item replace entity @s hotbar.1 with minecraft:wooden_sword");
                send(c,"effect give @s minecraft:hunger 3 199 true");stage=1;
            }
            case 1 -> {
                if(s.tick()-firstTick<61)return;
                damageAfterTicks=s.tick()-firstTick;send(c,"damage @s 8 minecraft:generic");stage=2;atTick=s.tick();
            }
            case 2 -> {
                if(s.hunger()||s.health()!=12||s.regeneration()||!s.mode().equals("survival")||s.food()<1||s.food()>14||s.saturation()!=0||s.bread()!=6||s.selected()!=0)return;
                if(s.tick()-atTick<12)return;
                baseline=s;stage=3;phase=0;
            }
            case 3 -> interruption(c,s);
            case 4 -> {
                if(phase==0){holdBaseline=s;press(c);atTick=s.tick();phase=1;return;}
                if(s.bread()==holdBaseline.bread())return;
                release(c);
                if(s.bread()!=holdBaseline.bread()-1||s.food()!=Math.min(20,holdBaseline.food()+5)||
                        Math.abs(s.saturation()-Math.min(s.food(),holdBaseline.saturation()+6))>.001||s.health()!=holdBaseline.health())
                    throw new IllegalStateException("Vanilla bread result differs from nutrition/saturation/count: "+state(s));
                if(s.tick()-atTick<25)throw new IllegalStateException("Bread completed before vanilla use duration");
                meals.add(state(s));lastMeal=s;atTick=s.tick();stage=5;
            }
            case 5 -> {
                if(s.using()||s.tick()-atTick<6)return;
                if(s.food()<20){stage=4;phase=0;return;}
                refilled=true;holdBaseline=s;press(c);atTick=s.tick();stage=6;
            }
            case 6 -> {
                if(s.using()||s.bread()!=holdBaseline.bread()||s.food()!=20)throw new IllegalStateException("Full hunger incorrectly admitted bread use");
                if(s.tick()-atTick<40)return;
                release(c);fullRejected=true;send(c,"gamerule naturalRegeneration true");atTick=s.tick();stage=7;
            }
            case 7 -> {
                if(s.health()<=holdBaseline.health())return;
                regenerated=true;send(c,"gamerule naturalRegeneration false");atTick=s.tick();stage=8;
            }
            case 8 -> {
                if(s.regeneration()||s.using()||s.tick()-atTick<12)return;
                if(s.bread()!=lastMeal.bread()||s.health()<=baseline.health())throw new IllegalStateException("Regeneration or inventory changed unexpectedly");
                var proof=new JsonObject();proof.addProperty("schema",1);proof.addProperty("kind","minecome_gameplay_food_witness_v1");
                proof.addProperty("world_id",save.id().toString());proof.addProperty("save",save.saveName());proof.add("state",state(s));
                save.verifyOwnership();Files.writeString(witness,proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
                complete(c,true,null);
            }
        }
    }
    private void interruption(MinecraftClient c,State s){
        if(phase==0){holdBaseline=s;press(c);phase=1;atTick=s.tick();return;}
        if(phase==1){if(!s.using())return;atTick=s.tick();phase=2;return;}
        if(phase==2){
            if(s.tick()-atTick<5)return;
            if(step==0)release(c);
            else if(step==1)key(c,'2');
            else if(step==2)key(c,'E');
            else if(step==3)blocks.beforeTick(c,false);
            else send(c,"gamemode creative");
            atTick=s.tick();phase=3;return;
        }
        if(s.bread()!=holdBaseline.bread()||s.food()!=holdBaseline.food()||s.saturation()!=holdBaseline.saturation()||s.health()!=holdBaseline.health())
            throw new IllegalStateException("Interrupted food changed vanilla state: step="+step+" "+state(s));
        if(phase==3){
            if(s.tick()-atTick<40)return;
            if(s.using()||c.player.isUsingItem())throw new IllegalStateException("Food use survived interruption step="+step);
            if(step==1)key(c,'1');else if(step==2){if(c.currentScreen==null)throw new IllegalStateException("Inventory did not open");key(c,'E');}
            else if(step==4){if(!s.mode().equals("creative"))throw new IllegalStateException("Mode command did not change to Creative");send(c,"gamemode survival");}
            atTick=s.tick();phase=4;return;
        }
        if(s.tick()-atTick<6)return;
        if(step==4&&!s.mode().equals("survival"))return;
        if(s.using()||c.player.isUsingItem())throw new IllegalStateException("Food restarted without a new press after interruption step="+step);
        release(c);
        if(step==0)earlyRelease=true;else if(step==1)slotChange=true;else if(step==2)inventoryInterrupt=true;else if(step==3)authorityGate=true;else modeChange=true;
        step++;phase=0;if(step==5)stage=4;
    }
    private void resume(MinecraftClient c,State s){
        if(!state(s).equals(expected))throw new IllegalStateException("Reopened food/health/inventory differs from saved witness: "+state(s)+" expected="+expected);
        if(s.using()||s.regeneration())throw new IllegalStateException("Reopened fixture retained active food/regen");
        if(stage==0){baseline=s;atTick=s.tick();stage=1;}
        if(s.tick()-atTick<12)return;
        resumed=true;complete(c,true,null);
    }
    private void owner(MinecraftClient c){
        if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning()||!c.player.getUuid().equals(playerId))
            throw new IllegalStateException("Food fixture client identity changed");
    }
    private void observe(){
        if(!observing.compareAndSet(false,true))return;
        server.execute(()->{try{
            if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);
            if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!server.getSaveProperties().getLevelName().equals(save.saveName()))throw new IllegalStateException("Food fixture server identity changed");
            observation.set(snapshot(p));
        }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});
    }
    private State snapshot(ServerPlayerEntity p){
        var h=p.getHungerManager();return new State(p.getUuid(),p.interactionManager.getGameMode().getName(),p.getHealth(),h.getFoodLevel(),h.getSaturationLevel(),h.getExhaustion(),
                server.getGameRules().getBoolean(GameRules.NATURAL_REGENERATION),p.hasStatusEffect(StatusEffects.HUNGER),p.isUsingItem(),p.getInventory().selectedSlot,bread(p),server.getTicks(),System.nanoTime());
    }
    private static int bread(net.minecraft.entity.player.PlayerEntity p){int count=0;for(int i=0;i<p.getInventory().size();i++){var stack=p.getInventory().getStack(i);if(stack.isOf(Items.BREAD))count+=stack.getCount();}return count;}
    private boolean matches(MinecraftClient c,State s){return c.interactionManager!=null&&c.interactionManager.getCurrentGameMode().getName().equals(s.mode())&&c.player.getHealth()==s.health()&&c.player.getHungerManager().getFoodLevel()==s.food()&&c.player.getInventory().selectedSlot==s.selected()&&bread(c.player)==s.bread();}
    private void send(MinecraftClient c,String command){owner(c);if(c.getNetworkHandler()==null)throw new IllegalStateException("Vanilla command connection missing");c.getNetworkHandler().sendChatCommand(command);commands.add(command);}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++events,System.currentTimeMillis(),kind,code,0,0,0);}
    private void press(MinecraftClient c){blocks.event(c,event(7,1));}
    private void release(MinecraftClient c){blocks.event(c,event(8,1));}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private static JsonObject state(State s){var j=new JsonObject();j.addProperty("player_id",s.player().toString());j.addProperty("mode",s.mode());j.addProperty("health",s.health());j.addProperty("food",s.food());j.addProperty("saturation",s.saturation());j.addProperty("exhaustion",s.exhaustion());j.addProperty("natural_regeneration",s.regeneration());j.addProperty("selected",s.selected());j.addProperty("bread_count",s.bread());return j;}
    private void complete(MinecraftClient c,boolean passed,String error){
        if(finished)return;finished=true;
        try{blocks.suspend(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var result=new JsonObject();result.addProperty("schema",1);result.addProperty("kind","minecome_gameplay_food_fixture_v1");result.addProperty("mode",mode);result.addProperty("result",passed?"passed":"failed");result.addProperty("failure",error);
        result.addProperty("world_id",save.id().toString());result.addProperty("save",save.saveName());result.addProperty("actual_minecraft",true);result.addProperty("standalone_scripted",true);result.addProperty("native_input_verified",false);result.addProperty("live_kcd_verified",false);result.addProperty("direct_health_food_inventory_writes",false);
        result.addProperty("early_release_verified",earlyRelease);result.addProperty("slot_change_verified",slotChange);result.addProperty("inventory_interrupt_verified",inventoryInterrupt);result.addProperty("authority_gate_verified",authorityGate);result.addProperty("mode_change_verified",modeChange);result.addProperty("hunger_refill_verified",refilled);result.addProperty("full_hunger_rejected",fullRejected);result.addProperty("regeneration_verified",regenerated);result.addProperty("resume_verified",resumed);
        result.addProperty("damage_after_observed_server_ticks",damageAfterTicks);result.addProperty("scripted_view_writes",viewWrites);result.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000L);result.addProperty("last_stage",stage);result.addProperty("last_step",step);result.addProperty("last_phase",phase);
        var sent=new JsonArray();commands.forEach(sent::add);result.add("commands",sent);result.add("meals",meals.deepCopy());if(baseline!=null)result.add("baseline",state(baseline));State s=observation.get();if(s!=null)result.add("final_state",state(s));result.add("blocks",blocks.evidence(c));
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-food-fixture.json"),result.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);}catch(Exception e){result.addProperty("result","failed");result.addProperty("failure","Food fixture evidence: "+e);}
        completed.accept(result);
    }
    /** The synthetic view lease is required before movement attachment can become ready. */
    private void writeLoop(){long sequence=0;try{while(!closing){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");
        j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());
        j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));
        j.addProperty("seq",++sequence);j.addProperty("utc_ms",System.currentTimeMillis());
        var forward=new JsonObject();forward.addProperty("x",1);forward.addProperty("y",0);forward.addProperty("z",0);j.add("forward",forward);
        var up=new JsonObject();up.addProperty("x",0);up.addProperty("y",0);up.addProperty("z",1);j.add("up",up);
        Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
        if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){blocks.suspend(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
