package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;

/** Actual vanilla client/server walking, driven by explicitly scripted standalone input. */
public final class GameplayMovementFixture {
    private static final String WITNESS="minecome-movement-fixture.json";
    private final String mode;
    private final GameplayMovement movement;
    private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;
    private final Path directory,witness;
    private final Consumer<JsonObject> completed;
    private final JsonObject expected;
    private final AtomicReference<String> workerFailure=new AtomicReference<>();
    private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>(),pendingWitness=new AtomicReference<>();
    private volatile boolean closing,written;
    private volatile float yaw=-90;
    private volatile long viewWrites;
    private Object world,player,server;
    private HudVanillaUiAdapter ui;
    private String playerId,gameMode;
    private JsonObject abilities,initial,inventoryStart,afterEarly,beforeLate,afterLate,result;
    private long begun,eventSequence,inventoryTicks,idleTicks;
    private int key;
    private boolean inventoryOpened,inventoryClosed,inventoryVerified,afterInventoryVerified,earlyVerified,resumeVerified,lateVerified,finished;

    public GameplayMovementFixture(String mode,GameplayMovement movement,GameplayWorld save,HudInputProtocol.Identity identity,
                                   Path evidenceDirectory,Consumer<JsonObject> completed)throws IOException {
        if(!Set.of("walking","walking-resume").contains(mode)||!Boolean.getBoolean("minecome.gameplayStandalone"))
            throw new IllegalArgumentException("Explicit standalone walking fixture required");
        this.mode=mode;this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;
        save.verifyOwnership();directory=evidenceDirectory.toRealPath();witness=save.directory().resolve(WITNESS);
        if(Files.exists(directory.resolve("host-view.json"))||Files.exists(directory.resolve("gameplay-movement-fixture.json")))
            throw new IOException("Movement fixture output already exists");
        if(mode.equals("walking")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("First walking fixture requires a new owned save");
            expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)
                throw new IOException("Walking resume requires its saved witness");
            expected=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(expected.get("schema").getAsInt()!=1||!expected.get("kind").getAsString().equals("minecome_gameplay_movement_witness_v1")
                    ||!expected.get("world_id").getAsString().equals(save.id().toString()))throw new IOException("Walking witness belongs to another save");
            yaw=expected.get("yaw").getAsFloat();
        }
        Thread worker=new Thread(this::writeLoop,"MineComeGameplayMovementFixture");worker.setDaemon(true);worker.start();
    }

    public void beforeTick(MinecraftClient client){
        if(closing||finished||begun==0||result!=null)return;
        try{requireOwner(client);movement.authority(client,System.nanoTime(),true);}
        catch(Exception e){complete(client,false,e.toString());}
    }

    public void tick(MinecraftClient client){
        if(closing||finished)return;
        try{
            if(result!=null){
                movement.suspend(client);
                if(written||workerFailure.get()!=null){
                    if(workerFailure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",workerFailure.get());}
                    finished=true;completed.accept(result.deepCopy());
                }
                return;
            }
            if(workerFailure.get()!=null)throw new IllegalStateException(workerFailure.get());
            if(!movement.ready())return;
            if(begun==0)begin(client);
            requireOwner(client);
            JsonObject proof=movement.evidence(client);long now=System.nanoTime();double seconds=(now-begun)/1e9;
            if(!gameMode.equals(client.interactionManager.getCurrentGameMode().getName()))throw new IllegalStateException("Walking changed game mode");
            String changedAbility=abilityDifference(abilities,abilities(client));
            if(changedAbility!=null)throw new IllegalStateException("Walking changed player ability: "+changedAbility);
            if(!proof.get("failure").isJsonNull())throw new IllegalStateException(proof.get("failure").getAsString());
            if(mode.equals("walking-resume")){
                setKey(client,seconds>=2&&seconds<2.3?'S':0);
                if(seconds>=4){lateVerified=distance(initial,proof.getAsJsonObject("server_position"))>.15;}
                if(seconds>=7){if(!lateVerified)throw new IllegalStateException("Resumed vanilla server did not move");complete(client,true,null);}
                return;
            }
            if(seconds>=3&&!earlyVerified){
                afterEarly=proof.getAsJsonObject("server_position").deepCopy();
                if(distance(initial,afterEarly)<.15)throw new IllegalStateException("Early vanilla server step absent");earlyVerified=true;
            }
            if(seconds>=4&&!inventoryOpened){setKey(client,0);movement.suspend(client);toggleInventory(client);inventoryOpened=true;}
            if(inventoryOpened&&!inventoryClosed){
                if(!HudVanillaUiAdapter.inventory(client.currentScreen))throw new IllegalStateException("Actual vanilla inventory was not open");
                if(seconds>=4.4&&inventoryStart==null)inventoryStart=proof.getAsJsonObject("server_position").deepCopy();
                if(seconds>=4.5&&seconds<5.3)inventoryTicks++;
                if(seconds>=6){
                    setKey(client,0);
                    if(inventoryStart==null||inventoryTicks<3||distance(inventoryStart,proof.getAsJsonObject("server_position"))>.025)
                        throw new IllegalStateException("W moved the server player inside vanilla inventory");
                    inventoryVerified=true;toggleInventory(client);inventoryClosed=true;
                }
            }
            int desired=seconds>=1&&seconds<1.35?'W':seconds>=4.5&&seconds<5.3?'W':seconds>=8&&seconds<8.2?'S':seconds>=21&&seconds<21.2?'W':0;
            movement.authority(client,now,true);setKey(client,desired);
            if(seconds>=10&&!afterInventoryVerified){
                if(afterEarly==null||distance(afterEarly,proof.getAsJsonObject("server_position"))<.15)
                    throw new IllegalStateException("Walking did not resume after inventory closed");
                afterInventoryVerified=true;
            }
            if(seconds>=12&&seconds<19){
                if(client.currentScreen!=null||!movement.ready())throw new IllegalStateException("Idle hotbar session did not persist");idleTicks++;
            }
            if(seconds>=20&&beforeLate==null)beforeLate=proof.getAsJsonObject("server_position").deepCopy();
            if(seconds>=23&&!lateVerified){
                afterLate=proof.getAsJsonObject("server_position").deepCopy();
                if(beforeLate==null||distance(beforeLate,afterLate)<.15)throw new IllegalStateException("No server movement beyond the old15second cutoff");lateVerified=true;
            }
            if(seconds>=35){
                if(!earlyVerified||!lateVerified||!inventoryVerified||!afterInventoryVerified||idleTicks<20||distance(initial,proof.getAsJsonObject("server_position"))<.15
                        ||proof.get("client_walk").getAsDouble()<.15||proof.get("server_walk").getAsDouble()<.15||proof.get("server_queries").getAsLong()==0)
                    throw new IllegalStateException("Sustained walking proof incomplete");
                complete(client,true,null);
            }
        }catch(Exception e){complete(client,false,e.toString());}
    }

    private void begin(MinecraftClient client)throws IOException{
        if(!client.isOnThread()||client.player==null||client.world==null||client.getServer()==null||!client.isIntegratedServerRunning())
            throw new IllegalStateException("Movement fixture requires the owning integrated client");
        save.verifyOwnership();world=client.world;player=client.player;server=client.getServer();playerId=client.player.getUuid().toString();
        ui=new HudVanillaUiAdapter(client,true);gameMode=client.interactionManager.getCurrentGameMode().getName();abilities=abilities(client);
        JsonObject proof=movement.evidence(client);initial=proof.getAsJsonObject("server_position").deepCopy();
        if(expected!=null){
            if(!expected.get("player_id").getAsString().equals(playerId))throw new IllegalStateException("Resumed player UUID differs from saved witness");
            if(!expected.get("game_mode").getAsString().equals(gameMode))throw new IllegalStateException("Resumed game mode differs: saved="+expected.get("game_mode")+", loaded="+gameMode);
            String changedAbility=abilityDifference(expected.getAsJsonObject("abilities"),abilities);
            if(changedAbility!=null)throw new IllegalStateException("Resumed player ability differs: "+changedAbility);
            if(!proof.get("resume_position_restored").getAsBoolean())throw new IllegalStateException("Terrain resume checkpoint was not restored");
            if(proof.get("first_attachment").getAsBoolean())throw new IllegalStateException("Resumed world unexpectedly used first terrain attachment");
            double offset=distance(initial,expected.getAsJsonObject("position"));
            if(!Double.isFinite(offset)||offset>.04)throw new IllegalStateException("Resumed location differs from saved witness by "+offset+"m");
            resumeVerified=true;
        }else if(!proof.get("first_attachment").getAsBoolean())throw new IllegalStateException("First walking fixture unexpectedly resumed terrain");
        begun=System.nanoTime();
    }
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Walking fixture owner changed");}
    private void setKey(MinecraftClient c,int desired){
        long now=System.nanoTime();
        if(key==desired)return;
        if(key!=0)movement.event(c,new HudInputProtocol.Event(++eventSequence,System.currentTimeMillis(),2,key,0,0,0),now);
        key=desired;
        if(key!=0)movement.event(c,new HudInputProtocol.Event(++eventSequence,System.currentTimeMillis(),1,key,0,0,0),now);
    }
    private void toggleInventory(MinecraftClient c){
        ui.apply(c,new HudInputProtocol.Event(++eventSequence,System.currentTimeMillis(),1,'E',0,0,0));
        ui.apply(c,new HudInputProtocol.Event(++eventSequence,System.currentTimeMillis(),2,'E',0,0,0));
    }
    private static JsonObject abilities(MinecraftClient c){
        var a=c.player.getAbilities();var j=new JsonObject();j.addProperty("allow_flying",a.allowFlying);j.addProperty("flying",a.flying);
        j.addProperty("invulnerable",a.invulnerable);j.addProperty("creative",a.creativeMode);j.addProperty("modify_world",a.allowModifyWorld);
        j.addProperty("fly_speed",a.getFlySpeed());j.addProperty("walk_speed",a.getWalkSpeed());return j;
    }
    private static String abilityDifference(JsonObject saved,JsonObject loaded){
        if(saved==null||loaded==null||!saved.keySet().equals(loaded.keySet()))return "ability fields";
        for(String name:new String[]{"allow_flying","flying","invulnerable","creative","modify_world"}){
            JsonElement a=saved.get(name),b=loaded.get(name);
            if(a==null||b==null||!a.isJsonPrimitive()||!b.isJsonPrimitive()||!a.getAsJsonPrimitive().isBoolean()||!b.getAsJsonPrimitive().isBoolean()
                    ||a.getAsBoolean()!=b.getAsBoolean())return name+" saved="+a+" loaded="+b;
        }
        // Minecraft stores ability speeds as float. Parsed JSON decimals and
        // JsonPrimitive(Float) can compare unequal as doubles despite round-
        // tripping to the same actual float; compare the vanilla type exactly.
        for(String name:new String[]{"fly_speed","walk_speed"}){
            JsonElement a=saved.get(name),b=loaded.get(name);
            if(a==null||b==null||!a.isJsonPrimitive()||!b.isJsonPrimitive()||!a.getAsJsonPrimitive().isNumber()||!b.getAsJsonPrimitive().isNumber())return name+" type";
            float av=a.getAsFloat(),bv=b.getAsFloat();
            if(!Float.isFinite(av)||!Float.isFinite(bv)||Float.floatToIntBits(av)!=Float.floatToIntBits(bv))return name+" saved="+a+" loaded="+b;
        }
        return null;
    }
    private static double distance(JsonObject a,JsonObject b){double x=a.get("x").getAsDouble()-b.get("x").getAsDouble(),y=a.get("y").getAsDouble()-b.get("y").getAsDouble(),z=a.get("z").getAsDouble()-b.get("z").getAsDouble();return Math.sqrt(x*x+y*y+z*z);}
    private void complete(MinecraftClient client,boolean passed,String error){
        if(result!=null||finished)return;
        try{setKey(client,0);movement.suspend(client);if(ui!=null)ui.releaseAndClose(client);}catch(Exception e){passed=false;error=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_movement_fixture_v1");p.addProperty("mode",mode);
        p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",error);p.addProperty("standalone_scripted",true);p.addProperty("native_input_verified",false);p.addProperty("live_kcd_verified",false);
        p.addProperty("world_id",save.id().toString());p.addProperty("player_id",playerId);p.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);
        p.addProperty("game_mode",gameMode);if(abilities!=null)p.add("abilities",abilities.deepCopy());
        p.addProperty("early_step_verified",earlyVerified);p.addProperty("late_step_verified",lateVerified);p.addProperty("inventory_suppression_verified",inventoryVerified);
        p.addProperty("walking_after_inventory_verified",afterInventoryVerified);
        p.addProperty("resume_verified",resumeVerified);p.addProperty("idle_hotbar_ticks",idleTicks);p.addProperty("inventory_ticks",inventoryTicks);p.addProperty("scripted_view_writes",viewWrites);
        JsonObject motion=movement.evidence(client);p.add("movement",motion);if(initial!=null)p.add("initial_position",initial.deepCopy());
        if(afterEarly!=null)p.add("after_early",afterEarly);if(beforeLate!=null)p.add("before_late",beforeLate);if(afterLate!=null)p.add("after_late",afterLate);
        if(passed&&expected==null){
            var w=new JsonObject();w.addProperty("schema",1);w.addProperty("kind","minecome_gameplay_movement_witness_v1");w.addProperty("world_id",save.id().toString());
            w.addProperty("player_id",playerId);w.addProperty("game_mode",gameMode);w.addProperty("yaw",yaw);w.add("abilities",abilities.deepCopy());w.add("position",motion.getAsJsonObject("server_position").deepCopy());pendingWitness.set(w);
        }
        result=p;pendingResult.set(p.deepCopy());
    }
    private void writeLoop(){
        long sequence=0;
        try{
            while(!closing){
                JsonObject finalProof=pendingResult.getAndSet(null);
                if(finalProof!=null){
                    var w=pendingWitness.getAndSet(null);if(w!=null){save.verifyOwnership();Files.writeString(witness,w.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}
                    Files.writeString(directory.resolve("gameplay-movement-fixture.json"),finalProof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;
                }
                var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());
                j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());
                j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++sequence);j.addProperty("utc_ms",System.currentTimeMillis());
                double angle=Math.toRadians(yaw);var f=new JsonObject();f.addProperty("x",-Math.sin(angle));f.addProperty("y",-Math.cos(angle));f.addProperty("z",0);j.add("forward",f);
                var u=new JsonObject();u.addProperty("x",0);u.addProperty("y",0);u.addProperty("z",1);j.add("up",u);
                Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
                // The reader can briefly hold a Windows sharing lock. Reuse the
                // bounded fixture publisher: retries retain this exact sample's
                // sequence/UTC, and a 100ms timeout drops only this publication.
                if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;
                Thread.sleep(25);
            }
        }catch(Exception e){workerFailure.compareAndSet(null,e.toString());}
    }
    public void close(){
        if(closing)return;closing=true;var client=MinecraftClient.getInstance();
        if(client.isOnThread()&&client.player==player){setKey(client,0);movement.suspend(client);if(ui!=null)ui.releaseAndClose(client);}
    }
}
