package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.item.Items;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.Vec3d;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Real ChatScreen editing/submission and authoritative vanilla results; no direct command API. */
public final class GameplayChatFixture {
    private static final String WITNESS="minecome-chat-fixture.json";
    private record State(long at,Vec3d position,String mode,int stones,boolean allowFlying){}
    private final String mode;private final GameplayMovement movement;private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;private final Path directory,witness;private final Consumer<JsonObject> completed;
    private final JsonObject expected;private final AtomicReference<State> observed=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>(),pendingWitness=new AtomicReference<>();
    private final List<String> commands=new ArrayList<>();
    private volatile boolean closing,written;private volatile long viewWrites;
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;
    private long begun,stageAt,sequence,textEvents,editEvents,chatTicks;private int stage,key,historyBefore;
    private boolean finished,editVerified,cancelVerified,invalidVerified,chatSuppressed,walkingVerified,resumeVerified,survivalVerified,creativeVerified,giveVerified;
    private Vec3d initial,chatPosition,beforeWalk;private JsonObject result;

    public GameplayChatFixture(String mode,GameplayMovement movement,GameplayWorld save,HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(!Set.of("chat","chat-resume").contains(mode)||!Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayChat"))throw new IllegalArgumentException("Explicit standalone chat fixture required");
        this.mode=mode;this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;save.verifyOwnership();this.directory=directory.toRealPath();witness=save.directory().resolve(WITNESS);
        if(Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-chat-fixture.json")))throw new IOException("Chat fixture output exists");
        if(mode.equals("chat")){if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Chat fixture needs new isolated save");expected=null;}
        else{if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)throw new IOException("Saved chat witness required");expected=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();if(expected.get("schema").getAsInt()!=1||!expected.get("kind").getAsString().equals("minecome_gameplay_chat_witness_v1")||!expected.get("world_id").getAsString().equals(save.id().toString()))throw new IOException("Chat witness identity differs");}
        var worker=new Thread(this::writeLoop,"MineComeGameplayChatFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0||result!=null)return;try{requireOwner(c);movement.authority(c,System.nanoTime(),true);}catch(Exception e){complete(c,false,e.toString());}}
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(result!=null){movement.suspend(c);if(written||failure.get()!=null){if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}finished=true;completed.accept(result.deepCopy());}return;}
            if(failure.get()!=null)throw new IllegalStateException(failure.get());if(!movement.ready())return;
            if(begun==0)begin(c);requireOwner(c);long now=System.nanoTime();if(now-begun>25_000_000_000L)throw new IllegalStateException("Chat fixture deadline stage="+stage);
            observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;if(initial==null)initial=s.position();
            if(expected==null)create(c,s,now);else resume(c,s,now);
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||!c.isIntegratedServerRunning()||c.getServer()==null)throw new IllegalStateException("Chat fixture requires integrated client");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);begun=stageAt=System.nanoTime();
    }
    private void create(MinecraftClient c,State s,long now){double elapsed=(now-stageAt)/1e9;switch(stage){
        case 0 -> {if(!matches(c,s,"creative",0))return;historyBefore=c.inGameHud.getChatHud().getMessageHistory().size();open(c,false);type(c,"MineCome caf\u00e9 \ud83d\ude00");requireText(c,"MineCome caf\u00e9 \ud83d\ude00");edit(c,8);requireText(c,"MineCome caf\u00e9 ");edit(c,0x24);edit(c,0x2e);edit(c,0x23);edit(c,8);requireText(c,"ineCome caf\u00e9");edit(c,0x1b);if(c.currentScreen!=null||c.inGameHud.getChatHud().getMessageHistory().size()!=historyBefore)throw new IllegalStateException("Cancelled Unicode editor text was submitted");editVerified=true;next(now);}
        case 1 -> {open(c,false);type(c,"/gamemode survivaX");edit(c,8);type(c,"l");submit(c,"/gamemode survival");next(now);}
        case 2 -> {if(s.at()<=stageAt||!matches(c,s,"survival",0))return;survivalVerified=true;command(c,"give @s minecraft:stone 7");next(now);}
        case 3 -> {if(s.at()<=stageAt||!matches(c,s,"survival",7))return;giveVerified=true;command(c,"minecome_nonexistent_command");next(now);}
        case 4 -> {if(elapsed<.4||s.at()<=stageAt)return;if(!matches(c,s,"survival",7)||c.currentScreen!=null)throw new IllegalStateException("Invalid command broke owned gameplay state");invalidVerified=true;open(c,true);type(c,"gamemode creative");requireText(c,"/gamemode creative");edit(c,0x1b);next(now);}
        case 5 -> {if(elapsed<.3||s.at()<=stageAt)return;if(!matches(c,s,"survival",7)||c.currentScreen!=null||c.inGameHud.getChatHud().getMessageHistory().contains("/gamemode creative"))throw new IllegalStateException("Escape submitted an unfinished mode command");cancelVerified=true;open(c,false);type(c,"wasd");next(now);}
        case 6 -> {if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Actual chat screen closed during movement suppression");if(elapsed<.3)return;if(chatPosition==null)chatPosition=s.position();movement.authority(c,now,true);setKey(c,elapsed<.9?'W':0);chatTicks++;requireText(c,"wasd");if(elapsed>=1.2){setKey(c,0);if(chatPosition.distanceTo(s.position())>.025||chatTicks<5)throw new IllegalStateException("W moved the authoritative player while chat was open");chatSuppressed=true;edit(c,0x1b);command(c,"gamemode creative");next(now);}}
        case 7 -> {if(s.at()<=stageAt||!matches(c,s,"creative",7)||!s.allowFlying()||!c.player.getAbilities().allowFlying)return;creativeVerified=true;beforeWalk=s.position();next(now);}
        case 8 -> {movement.authority(c,now,true);setKey(c,elapsed<.2?'W':0);if(elapsed>=.8){if(beforeWalk.distanceTo(s.position())<.15||c.currentScreen!=null)throw new IllegalStateException("Walking did not resume after chat commands");walkingVerified=true;command(c,"gamemode survival");next(now);}}
        case 9 -> {if(elapsed<.4||s.at()<=stageAt||!matches(c,s,"survival",7))return;complete(c,true,null);}
        default -> throw new IllegalStateException("Unexpected chat fixture stage");
    }}
    private void resume(MinecraftClient c,State s,long now){double elapsed=(now-stageAt)/1e9;switch(stage){
        case 0 -> {var proof=movement.evidence(c);if(!matches(c,s,"survival",7)||!playerId.toString().equals(expected.get("player_id").getAsString())||!proof.get("resume_position_restored").getAsBoolean()||proof.get("first_attachment").getAsBoolean()||initial.distanceTo(vector(expected.getAsJsonObject("position")))>.04)throw new IllegalStateException("Chat-produced mode/items/player checkpoint did not survive reopen");resumeVerified=true;survivalVerified=true;giveVerified=true;command(c,"gamemode creative");next(now);}
        case 1 -> {if(s.at()<=stageAt||!matches(c,s,"creative",7)||!s.allowFlying()||!c.player.getAbilities().allowFlying)return;creativeVerified=true;beforeWalk=s.position();next(now);}
        case 2 -> {movement.authority(c,now,true);setKey(c,elapsed<.2?'S':0);if(elapsed>=.8){if(beforeWalk.distanceTo(s.position())<.15)throw new IllegalStateException("Reopened chat session did not walk");walkingVerified=true;command(c,"gamemode survival");next(now);}}
        case 3 -> {if(elapsed<.4||s.at()<=stageAt||!matches(c,s,"survival",7))return;complete(c,true,null);}
        default -> throw new IllegalStateException("Unexpected chat resume stage");
    }}
    private void next(long now){stage++;stageAt=now;}
    private void open(MinecraftClient c,boolean slash){setKey(c,0);movement.suspend(c);key(c,slash?0xbf:'T');if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Real ChatScreen did not open");requireText(c,slash?"/":"");}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void edit(MinecraftClient c,int code){ui.apply(c,event(10,code));ui.apply(c,event(11,code));editEvents++;}
    private void type(MinecraftClient c,String text){text.codePoints().forEach(cp->{ui.apply(c,event(9,cp));textEvents++;});}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void requireText(MinecraftClient c,String expectedText){String actual=ui.chatText(c);if(!expectedText.equals(actual))throw new IllegalStateException("Vanilla chat text differs: expected="+expectedText+", actual="+actual);}
    private void submit(MinecraftClient c,String command){requireText(c,command);edit(c,0x0d);if(c.currentScreen!=null||!c.inGameHud.getChatHud().getMessageHistory().contains(command))throw new IllegalStateException("Vanilla chat did not submit: "+command);commands.add(command);}
    private void command(MinecraftClient c,String text){open(c,true);type(c,text);submit(c,"/"+text);}
    private void setKey(MinecraftClient c,int desired){if(key==desired)return;long now=System.nanoTime();if(key!=0)movement.event(c,event(2,key),now);key=desired;if(key!=0)movement.event(c,event(1,key),now);}
    private boolean matches(MinecraftClient c,State s,String gameMode,int stones){int count=0;for(int i=0;i<c.player.getInventory().size();i++)if(c.player.getInventory().getStack(i).isOf(Items.STONE))count+=c.player.getInventory().getStack(i).getCount();return s.mode().equals(gameMode)&&c.interactionManager.getCurrentGameMode().getName().equals(gameMode)&&s.stones()==stones&&count==stones;}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Chat fixture server identity changed");int stones=0;for(int i=0;i<p.getInventory().size();i++)if(p.getInventory().getStack(i).isOf(Items.STONE))stones+=p.getInventory().getStack(i).getCount();observed.set(new State(System.nanoTime(),p.getPos(),p.interactionManager.getGameMode().getName(),stones,p.getAbilities().allowFlying));}catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Chat fixture owner changed");}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static Vec3d vector(JsonObject j){return new Vec3d(j.get("x").getAsDouble(),j.get("y").getAsDouble(),j.get("z").getAsDouble());}
    private void complete(MinecraftClient c,boolean passed,String error){if(result!=null||finished)return;try{setKey(c,0);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_chat_fixture_v1");j.addProperty("mode",mode);j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("direct_command_api_used",false);j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("text_events",textEvents);j.addProperty("edit_events",editEvents);j.addProperty("chat_ticks",chatTicks);j.addProperty("scripted_view_writes",viewWrites);
        j.addProperty("editing_verified",editVerified);j.addProperty("cancel_verified",cancelVerified);j.addProperty("invalid_command_recovered",invalidVerified);j.addProperty("chat_suppression_verified",chatSuppressed);j.addProperty("walking_after_chat_verified",walkingVerified);j.addProperty("survival_verified",survivalVerified);j.addProperty("creative_verified",creativeVerified);j.addProperty("give_verified",giveVerified);j.addProperty("resume_verified",resumeVerified);var list=new JsonArray();commands.forEach(list::add);j.add("submitted_commands",list);j.add("movement",movement.evidence(c));if(initial!=null)j.add("initial_position",json(initial));if(ui!=null)j.add("ui",ui.pointerDiagnostics());var s=observed.get();if(s!=null){j.addProperty("game_mode",s.mode());j.addProperty("stone_count",s.stones());j.add("server_position",json(s.position()));}
        if(passed&&expected==null){var w=new JsonObject();w.addProperty("schema",1);w.addProperty("kind","minecome_gameplay_chat_witness_v1");w.addProperty("world_id",save.id().toString());w.addProperty("player_id",playerId.toString());w.addProperty("game_mode",s.mode());w.addProperty("stone_count",s.stones());w.add("position",json(s.position()));pendingWitness.set(w);}result=j;pendingResult.set(j.deepCopy());
    }
    private void writeLoop(){long seq=0;try{while(!closing){var proof=pendingResult.getAndSet(null);if(proof!=null){var w=pendingWitness.getAndSet(null);if(w!=null){save.verifyOwnership();Files.writeString(witness,w.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}Files.writeString(directory.resolve("gameplay-chat-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());j.add("forward",json(new Vec3d(1,0,0)));j.add("up",json(new Vec3d(0,0,1)));Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){setKey(c,0);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
