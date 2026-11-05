package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayWorld;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.effect.StatusEffects;
import net.minecraft.entity.player.PlayerInventory;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.world.GameMode;
import net.minecraft.world.GameRules;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Two actual-client launches; commands travel through vanilla's client packet path. */
public final class GameplayPersistenceFixture {
    private static final String WITNESS="minecome-persistence-fixture.json";
    private static final String[] CREATE_COMMANDS={
            "gamerule naturalRegeneration false", "gamemode survival",
            "give @s minecraft:apple 17", "give @s minecraft:iron_pickaxe 1",
            "effect give @s minecraft:hunger 3 199 true", "damage @s 4 minecraft:generic"
    };
    private record Slot(String item,int count){}
    private record State(UUID player,String mode,float health,int food,float saturation,float exhaustion,
                         boolean naturalRegeneration,boolean hunger,boolean onGround,boolean allowFlying,
                         int selected,List<Slot> slots,int serverTick,long at){}
    private final String mode;
    private final GameplayWorld world;
    private final Path output,witness;
    private final Consumer<JsonObject> finish;
    private final AtomicReference<State> serverState=new AtomicReference<>();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();
    private final List<String> commands=new ArrayList<>();
    private MinecraftServer server;
    private Object clientWorld,clientPlayer;
    private UUID playerId;
    private long begun,lastCommand,stableAt;
    private int stage,commandIndex,firstServerTick=-1,damageAfterTicks;
    private volatile boolean finished;
    private boolean resumeVerified,creativeAbilityVerified;
    private State baseline;
    private JsonObject expected;

    public GameplayPersistenceFixture(String mode,GameplayWorld world,Path output,Consumer<JsonObject> finish)throws IOException{
        if(!Set.of("create","resume").contains(mode)||world==null||output==null||finish==null||!output.isAbsolute())
            throw new IllegalArgumentException("Explicit create/resume fixture and owned output required");
        if(!Boolean.getBoolean("minecome.gameplayStandalone"))
            throw new IllegalArgumentException("Persistence fixture requires its explicit standalone gameplay session");
        this.mode=mode;this.world=world;this.output=output;this.finish=finish;
        world.verifyOwnership();witness=world.directory().resolve(WITNESS);
        if(mode.equals("create")){
            if(!world.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))
                throw new IOException("Create fixture requires its newly reserved world; no existing save is changed");
        }else{
            if(world.newlyCreated())throw new IOException("Resume fixture requires its previously saved world");
            if(Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)
                    ||Files.size(witness)<2||Files.size(witness)>16384)throw new IOException("Missing persistence witness");
            var proof=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(proof.get("schema").getAsInt()!=1||!proof.get("kind").getAsString().equals("minecome_gameplay_persistence_witness_v1")
                    ||!proof.get("world_id").getAsString().equals(world.id().toString())
                    ||!proof.get("save").getAsString().equals(world.saveName()))throw new IOException("Persistence witness belongs to another world");
            expected=proof.getAsJsonObject("state");
            if(expected==null||!expected.get("mode").getAsString().equals("survival"))throw new IOException("Persistence witness lacks Survival state");
        }
    }

    /** Called on the owned client tick after the ordinary stream is ready. */
    public void tick(MinecraftClient client){
        if(finished)return;
        try{
            long now=System.nanoTime();
            if(begun==0){
                if(!client.isOnThread()||client.world==null||client.player==null||client.getServer()==null
                        ||!client.isIntegratedServerRunning())throw new IllegalStateException("Fixture requires the owned integrated client");
                world.verifyOwnership();server=client.getServer();clientWorld=client.world;clientPlayer=client.player;
                playerId=client.player.getUuid();begun=now;
            }
            requireOwner(client);
            if(now-begun>45_000_000_000L)throw new IllegalStateException("Persistence fixture did not complete within45seconds; last stage="+stage);
            if(serverFailure.get()!=null)throw new IllegalStateException(serverFailure.get());
            observe();
            State state=serverState.get();
            if(state==null||now<state.at()||now-state.at()>500_000_000L)return;
            if(firstServerTick<0)firstServerTick=state.serverTick();
            if(!matchesClient(client,state)){stableAt=0;return;}
            if(mode.equals("create"))create(client,state,now);else resume(client,state,now);
        }catch(Exception error){complete(false,error.getMessage(),serverState.get());}
    }

    private void create(MinecraftClient client,State state,long now)throws IOException{
        if(stage==0){
            if(!state.mode().equals("creative")||state.health()!=20||state.food()!=20||!state.naturalRegeneration()
                    ||state.slots().stream().anyMatch(s->s.count()!=0))throw new IllegalStateException("New fixture world has unexpected player state");
            if(!state.onGround()){stableAt=0;return;}
            if(stableAt==0)stableAt=now;
            if(now-stableAt<500_000_000L)return;
            baseline=state;stage=1;stableAt=0;
        }
        if(stage==1){
            if(commandIndex<CREATE_COMMANDS.length){
                if(CREATE_COMMANDS[commandIndex].startsWith("damage ")){
                    // Inspected Yarn1.21.1 ServerPlayerEntity: construction sets
                    // joinInvulnerabilityTicks=60; tick() decrements it, and damage()
                    // rejects generic damage until it expires. Observe real server
                    // ticks after the owned player exists, rather than bypassing it.
                    int elapsed=state.serverTick()-firstServerTick;
                    if(elapsed<61)return;
                    damageAfterTicks=elapsed;
                }
                if(lastCommand==0||now-lastCommand>=200_000_000L){send(client,CREATE_COMMANDS[commandIndex++],now);}
                return;
            }
            if(!state.mode().equals("survival")||state.health()!=16||state.food()<=0||state.food()>=20
                    ||state.saturation()!=0||state.naturalRegeneration()||state.hunger()||!state.onGround()
                    ||count(state,"minecraft:apple")!=17||count(state,"minecraft:iron_pickaxe")!=1){stableAt=0;return;}
            if(state.slots().stream().anyMatch(s->s.count()>0&&!Set.of("minecraft:apple","minecraft:iron_pickaxe").contains(s.item())))
                throw new IllegalStateException("Fixture inventory contains unexpected items");
            if(stableAt==0)stableAt=now;
            if(now-stableAt<700_000_000L)return;
            // This explicit fixture keeps the real stream/world alive beyond the
            // retired thirty-second diagnostic cutoff. State is rechecked on
            // every tick and the witness records the final fresh observation.
            if(now-begun<35_000_000_000L)return;
            world.verifyOwnership();
            var proof=new JsonObject();proof.addProperty("schema",1);proof.addProperty("kind","minecome_gameplay_persistence_witness_v1");
            proof.addProperty("world_id",world.id().toString());proof.addProperty("save",world.saveName());proof.add("state",stateJson(state));
            Files.writeString(witness,proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
            complete(true,null,state);
        }
    }

    private void resume(MinecraftClient client,State state,long now){
        if(stage==0){
            if(!sameSavedState(state,expected))throw new IllegalStateException("Reopened Minecraft player state differs from the saved fixture witness");
            if(!state.onGround()){stableAt=0;return;}
            if(stableAt==0)stableAt=now;
            if(now-stableAt<500_000_000L)return;
            baseline=state;resumeVerified=true;send(client,"gamemode creative",now);stage=1;stableAt=0;return;
        }
        if(stage==1){
            if(!state.mode().equals("creative")||!state.allowFlying()||!client.player.getAbilities().allowFlying)return;
            creativeAbilityVerified=true;send(client,"gamemode survival",now);stage=2;return;
        }
        if(stage==2){
            if(!state.mode().equals("survival")||state.allowFlying()||client.player.getAbilities().allowFlying)return;
            if(!sameSavedState(state,expected))throw new IllegalStateException("Mode commands altered persisted inventory/survival state unexpectedly");
            if(stableAt==0)stableAt=now;
            if(now-stableAt<500_000_000L)return;
            complete(true,null,state);
        }
    }

    private void send(MinecraftClient client,String command,long now){
        requireOwner(client);
        if(client.getNetworkHandler()==null)throw new IllegalStateException("Vanilla client command connection missing");
        // Inspected mapped Yarn1.21.1 ClientPlayNetworkHandler.sendChatCommand(String):
        // parses the command, collects signing arguments and sends CommandExecutionC2SPacket.
        client.getNetworkHandler().sendChatCommand(command);commands.add(command);lastCommand=now;
    }
    private void requireOwner(MinecraftClient client){
        if(!client.isOnThread()||client.world!=clientWorld||client.player!=clientPlayer||client.getServer()!=server
                ||!client.isIntegratedServerRunning()||!client.player.getUuid().equals(playerId))
            throw new IllegalStateException("Gameplay fixture client/world/server ownership changed");
    }
    private void observe(){
        if(!observing.compareAndSet(false,true))return;
        server.execute(()->{
            try{
                if(finished)return;
                var entity=server.getPlayerManager().getPlayer(playerId);
                if(!server.isOnThread()||entity==null||entity.getWorld()!=server.getOverworld()
                        ||!server.getSaveProperties().getLevelName().equals(world.saveName()))
                    throw new IllegalStateException("Gameplay fixture server ownership changed");
                serverState.set(snapshot(entity));
            }catch(Exception error){serverFailure.compareAndSet(null,error.getMessage());}
            finally{observing.set(false);}
        });
    }
    private State snapshot(ServerPlayerEntity player){
        var hunger=player.getHungerManager();
        return new State(player.getUuid(),player.interactionManager.getGameMode().getName(),player.getHealth(),
                hunger.getFoodLevel(),hunger.getSaturationLevel(),hunger.getExhaustion(),
                server.getGameRules().getBoolean(GameRules.NATURAL_REGENERATION),player.hasStatusEffect(StatusEffects.HUNGER),
                player.isOnGround(),player.getAbilities().allowFlying,player.getInventory().selectedSlot,slots(player.getInventory()),server.getTicks(),System.nanoTime());
    }
    private boolean matchesClient(MinecraftClient client,State state){
        return client.interactionManager!=null&&client.interactionManager.getCurrentGameMode().getName().equals(state.mode())
                &&client.player.getHealth()==state.health()&&client.player.getHungerManager().getFoodLevel()==state.food()
                &&client.player.getInventory().selectedSlot==state.selected()&&slots(client.player.getInventory()).equals(state.slots());
    }
    private static List<Slot> slots(PlayerInventory inventory){
        var slots=new ArrayList<Slot>();
        for(int i=0;i<inventory.size();i++){
            var stack=inventory.getStack(i);slots.add(new Slot(Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount()));
        }
        return List.copyOf(slots);
    }
    private static int count(State state,String item){return state.slots().stream().filter(s->s.item().equals(item)).mapToInt(Slot::count).sum();}
    private static JsonObject stateJson(State state){
        var json=new JsonObject();json.addProperty("player_id",state.player().toString());json.addProperty("mode",state.mode());
        json.addProperty("health",state.health());json.addProperty("food",state.food());json.addProperty("saturation",state.saturation());
        json.addProperty("exhaustion",state.exhaustion());json.addProperty("natural_regeneration",state.naturalRegeneration());json.addProperty("selected",state.selected());
        var inventory=new JsonArray();for(var slot:state.slots()){var value=new JsonObject();value.addProperty("item",slot.item());value.addProperty("count",slot.count());inventory.add(value);}json.add("inventory",inventory);
        return json;
    }
    private static boolean sameSavedState(State state,JsonObject expected){return stateJson(state).equals(expected);}
    private void complete(boolean passed,String failure,State state){
        if(finished)return;finished=true;
        var result=new JsonObject();result.addProperty("schema",1);result.addProperty("kind","minecome_gameplay_persistence_fixture_v1");
        result.addProperty("mode",mode);result.addProperty("result",passed?"passed":"failed");result.addProperty("failure",failure);
        result.addProperty("world_id",world.id().toString());result.addProperty("save",world.saveName());
        result.addProperty("scripted_commands",true);result.addProperty("actual_minecraft",true);result.addProperty("kcd_connected",false);
        result.addProperty("host_command_typing_verified",false);result.addProperty("flight_movement_verified",false);
        result.addProperty("resume_verified",resumeVerified);result.addProperty("creative_ability_verified",creativeAbilityVerified);
        if(mode.equals("create"))result.addProperty("damage_after_observed_server_ticks",damageAfterTicks);
        result.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000L);
        var sent=new JsonArray();commands.forEach(sent::add);result.add("commands",sent);
        if(baseline!=null)result.add("baseline",stateJson(baseline));if(state!=null)result.add("final_state",stateJson(state));
        try{
            world.verifyOwnership();
            Files.writeString(output.resolve("gameplay-fixture.json"),result.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
        }catch(Exception error){result.addProperty("result","failed");result.addProperty("failure","Fixture evidence: "+error.getMessage());}
        finish.accept(result);
    }
}
