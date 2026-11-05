package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.attribute.EntityAttributes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.Vec3d;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual vanilla flight from input edges and ChatScreen commands; no ability or position writes. */
public final class GameplayFlightFixture {
    private static final String WITNESS="minecome-flight-fixture.json";
    private record State(long at,Vec3d position,String mode,boolean allowFlying,boolean flying,boolean grounded,boolean sprinting,float health,float fallDistance,double safeFallDistance,double fallDamageMultiplier){}
    private final String mode;
    private final GameplayMovement movement;
    private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;
    private final Path directory,witness;
    private final Consumer<JsonObject> completed;
    private final JsonObject expected;
    private final AtomicReference<State> observed=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>(),pendingWitness=new AtomicReference<>();
    private final Set<Integer> held=new HashSet<>();
    private final List<String> commands=new ArrayList<>();
    private final JsonObject points=new JsonObject();
    private volatile boolean closing,written;
    private volatile long viewWrites;
    private MinecraftServer server;
    private Object world,player;
    private UUID playerId;
    private HudVanillaUiAdapter ui;
    private long begun,stageAt,sequence,textEvents,flightTicks,inventoryTicks,chatTicks;
    private int stage,stageTicks;
    private boolean finished,takeoffVerified,ascentVerified,descentVerified,horizontalVerified,sprintVerified,
        inventoryVerified,chatVerified,landingVerified,modeChangeVerified,resumeVerified,secondTakeoffVerified,fallingSaveVerified,fallDamageVerified,fallDistanceVerified,loginGraceVerified;
    private Vec3d initial,baseline;
    private double groundY,maxAltitude,normalPeakSpeed,sprintPeakSpeed;
    private JsonObject result;

    public GameplayFlightFixture(String mode,GameplayMovement movement,GameplayWorld save,HudInputProtocol.Identity identity,
                                 Path directory,Consumer<JsonObject> completed)throws IOException {
        if(!Set.of("flight","flight-resume","flight-fall","flight-fall-resume").contains(mode)||!Boolean.getBoolean("minecome.gameplayStandalone")
                ||!Boolean.getBoolean("minecome.gameplayFlight")||!Boolean.getBoolean("minecome.gameplayChat"))
            throw new IllegalArgumentException("Explicit standalone flight/chat fixture required");
        this.mode=mode;this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;
        save.verifyOwnership();this.directory=directory.toRealPath();witness=save.directory().resolve(WITNESS);
        if(Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-flight-fixture.json")))
            throw new IOException("Flight fixture output exists");
        if(mode.equals("flight")||mode.equals("flight-fall")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Flight fixture needs new isolated save");expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)
                throw new IOException("Saved flight witness required");
            expected=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(expected.get("schema").getAsInt()!=1||!expected.get("kind").getAsString().equals("minecome_gameplay_flight_witness_v1")
                    ||!expected.get("world_id").getAsString().equals(save.id().toString()))throw new IOException("Flight witness identity differs");
            if(mode.equals("flight-fall-resume")!=expected.has("falling"))throw new IOException("Flight witness scenario differs");
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayFlightFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){
        if(closing||finished||begun==0||result!=null)return;
        try{requireOwner(c);movement.authority(c,System.nanoTime(),true);}catch(Exception e){complete(c,false,e.toString());}
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(result!=null){movement.suspend(c);if(written||failure.get()!=null){
                if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}
                finished=true;completed.accept(result.deepCopy());}return;}
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready())return;
            if(begun==0)begin(c);requireOwner(c);long now=System.nanoTime();
            if(now-begun>45_000_000_000L||now-stageAt>8_000_000_000L)throw new IllegalStateException("Flight fixture deadline stage="+stage+", ticks="+stageTicks);
            observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;
            if(initial==null){initial=s.position();groundY=movement.surface().groundForFeet(initial.x,initial.z,.3);}
            if(c.player.getAbilities().flying&&s.flying())flightTicks++;
            maxAltitude=Math.max(maxAltitude,s.position().y-groundY);stageTicks++;
            if(mode.equals("flight-fall"))createFall(c,s,now);else if(mode.equals("flight-fall-resume"))resumeFall(c,s,now);
            else if(expected==null)create(c,s,now);else resume(c,s,now);
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException {
        if(!c.isOnThread()||c.world==null||c.player==null||!c.isIntegratedServerRunning()||c.getServer()==null)
            throw new IllegalStateException("Flight fixture requires integrated client");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();
        ui=new HudVanillaUiAdapter(c,true,true);begun=stageAt=System.nanoTime();
    }
    private void create(MinecraftClient c,State s,long now){switch(stage){
        case 0 -> {command(c,"gamemode survival");next(now);}
        case 1 -> {if(s.at()<=stageAt||!mode(c,s,"survival")||s.allowFlying()||c.player.getAbilities().allowFlying)return;command(c,"gamemode creative");next(now);}
        case 2 -> {if(s.at()<=stageAt||!creative(c,s)||!s.grounded())return;point("ground_start",s);next(now);}
        case 3 -> {doubleTap(c);if(stageTicks>=10&&flying(c,s)){takeoffVerified=true;point("takeoff",s);baseline=s.position();next(now);}}
        case 4 -> {keys(c,stageTicks<=6?new int[]{0x20}:new int[0]);if(stageTicks>=18){requireFlying(c,s);if(s.position().y-baseline.y<.65)throw new IllegalStateException("Jump did not ascend during Creative flight");ascentVerified=true;point("ascent",s);baseline=s.position();next(now);}}
        case 5 -> {keys(c,stageTicks<=3?new int[]{'D'}:new int[0]);normalPeakSpeed=Math.max(normalPeakSpeed,c.player.getVelocity().horizontalLength());if(stageTicks>=20){requireFlying(c,s);if(horizontal(baseline,s.position())<.15)throw new IllegalStateException("Horizontal flight absent");horizontalVerified=true;point("horizontal",s);baseline=s.position();next(now);}}
        case 6 -> {
            keys(c,stageTicks<=3?new int[]{'W',0x11}:stageTicks>=21&&stageTicks<=26?new int[]{'S'}:new int[0]);
            if(stageTicks<=20){sprintPeakSpeed=Math.max(sprintPeakSpeed,c.player.getVelocity().horizontalLength());if(c.player.isSprinting()&&s.sprinting())sprintVerified=true;}
            if(stageTicks==20){requireFlying(c,s);if(horizontal(baseline,s.position())<.15||!sprintVerified)throw new IllegalStateException("Vanilla sprint flight absent");point("sprint",s);}
            // Return toward the centre using normal input so the second takeoff
            // has room for the ordinary conservative sprint-jump envelope.
            if(stageTicks>=42){requireFlying(c,s);point("after_return",s);keys(c);movement.suspend(c);inventory(c);baseline=s.position();next(now);}
        }
        case 7 -> {
            if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Flight inventory closed unexpectedly");
            if(stageTicks==4)baseline=s.position();keys(c,stageTicks>=5&&stageTicks<=13?new int[]{'W',0x20,0x10,0x11}:new int[0]);inventoryTicks++;
            if(stageTicks>=20){requireFlying(c,s);if(baseline.distanceTo(s.position())>.035)throw new IllegalStateException("Flight moved while inventory open");inventoryVerified=true;keys(c);inventory(c);point("after_inventory",s);next(now);}
        }
        case 8 -> {if(stageTicks<5)return;openChat(c);type(c,"flight isolation");baseline=s.position();next(now);}
        case 9 -> {
            if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Flight chat closed unexpectedly");
            keys(c,stageTicks<=10?new int[]{'W',0x20}:new int[0]);chatTicks++;
            if(stageTicks>=18){requireFlying(c,s);if(baseline.distanceTo(s.position())>.035)throw new IllegalStateException("Flight moved while chat open");chatVerified=true;keys(c);edit(c,0x1b);baseline=s.position();next(now);}
        }
        case 10 -> {keys(c,0x10);if(s.position().y<baseline.y-.5)descentVerified=true;if(s.grounded()&&!s.flying()&&!c.player.getAbilities().flying){keys(c);landingVerified=true;point("landed",s);command(c,"gamemode survival");next(now);}}
        case 11 -> {if(s.at()<=stageAt||!mode(c,s,"survival")||s.flying()||s.allowFlying()||c.player.getAbilities().flying)return;modeChangeVerified=true;command(c,"gamemode creative");next(now);}
        case 12 -> {if(s.at()<=stageAt||!creative(c,s)||!s.grounded())return;next(now);}
        case 13 -> {doubleTap(c);if(stageTicks>=10&&flying(c,s)){secondTakeoffVerified=true;baseline=s.position();next(now);}}
        case 14 -> {keys(c,stageTicks<=4?new int[]{0x20}:new int[0]);if(stageTicks>=22){requireFlying(c,s);if(s.position().y-groundY<.8)throw new IllegalStateException("Aerial checkpoint not above ground");point("saved_hover",s);complete(c,true,null);}}
        default -> throw new IllegalStateException("Unknown flight stage");
    }}
    private void resume(MinecraftClient c,State s,long now){switch(stage){
        case 0 -> {
            var proof=movement.evidence(c);requireFlying(c,s);
            if(!playerId.toString().equals(expected.get("player_id").getAsString())||!proof.get("resume_position_restored").getAsBoolean()
                    ||proof.get("first_attachment").getAsBoolean()||initial.distanceTo(vector(expected.getAsJsonObject("position")))>.04)
                throw new IllegalStateException("Flying player/checkpoint did not survive reopen");
            resumeVerified=true;point("resumed_hover",s);baseline=s.position();next(now);
        }
        case 1 -> {keys(c,stageTicks<=3?new int[]{0x10}:new int[0]);if(stageTicks>=15){requireFlying(c,s);if(baseline.y-s.position().y<.2)throw new IllegalStateException("Resumed flight did not descend");descentVerified=true;baseline=s.position();next(now);}}
        case 2 -> {keys(c,stageTicks<=3?new int[]{0x20}:new int[0]);if(stageTicks>=15){requireFlying(c,s);if(s.position().y-baseline.y<.2)throw new IllegalStateException("Resumed flight did not ascend");ascentVerified=true;next(now);}}
        case 3 -> {keys(c,0x10);if(s.grounded()&&!s.flying()&&!c.player.getAbilities().flying){keys(c);landingVerified=true;point("resume_landed",s);next(now);}}
        case 4 -> {if(stageTicks>=8){if(!s.grounded()||s.flying())throw new IllegalStateException("Reopened landing did not settle");complete(c,true,null);}}
        default -> throw new IllegalStateException("Unknown flight resume stage");
    }}
    private void createFall(MinecraftClient c,State s,long now){switch(stage){
        case 0 -> {if(!creative(c,s)||!s.grounded())return;point("ground_start",s);next(now);}
        case 1 -> {doubleTap(c);if(stageTicks>=10&&flying(c,s)){takeoffVerified=true;baseline=s.position();next(now);}}
        case 2 -> {
            keys(c,stageTicks<=16?new int[]{0x20}:new int[0]);
            if(stageTicks>=30){requireFlying(c,s);if(s.position().y-groundY<6)throw new IllegalStateException("Fall checkpoint test did not reach altitude");ascentVerified=true;point("before_fall",s);command(c,"gamemode survival");next(now);}
        }
        case 3 -> {
            if(s.at()<=stageAt||!mode(c,s,"survival")||s.flying()||c.player.getAbilities().flying||s.allowFlying())return;
            if(s.grounded()||s.position().y-groundY<3)throw new IllegalStateException("Fall checkpoint test landed before stop");
            if(s.fallDistance()>3&&c.player.getVelocity().y<-.1){modeChangeVerified=true;fallingSaveVerified=true;point("falling_stop",s);complete(c,true,null);}
        }
        default -> throw new IllegalStateException("Unknown falling checkpoint stage");
    }}
    private void resumeFall(MinecraftClient c,State s,long now){
        if(stageTicks<6)return;
        var proof=movement.evidence(c);var checkpoint=proof.getAsJsonObject("resume_checkpoint");
        if(!playerId.toString().equals(expected.get("player_id").getAsString())||!proof.get("resume_position_restored").getAsBoolean()
                ||proof.get("first_attachment").getAsBoolean()||checkpoint==null||!checkpoint.get("falling").getAsBoolean()
                ||checkpoint.get("flying").getAsBoolean()||checkpoint.get("fall_distance").getAsFloat()<=0)
            throw new IllegalStateException("Falling checkpoint identity/state was not restored");
        if(!mode(c,s,"survival")||s.allowFlying()||s.flying()||c.player.getAbilities().flying||!s.grounded()
                ||Math.abs(s.position().y-groundY)>.15||Math.abs(s.position().x-checkpoint.get("x").getAsDouble())>.04
                ||Math.abs(s.position().z-checkpoint.get("z").getAsDouble())>.04)
            throw new IllegalStateException("Reopened falling player did not naturally settle on imported ground");
        if(!proof.get("resume_fall_restored").getAsBoolean()||!proof.get("resume_fall_landed").getAsBoolean()
                ||proof.get("resume_fall_distance_max").getAsDouble()<checkpoint.get("fall_distance").getAsDouble()+.5)
            throw new IllegalStateException("Restored fall distance did not continue accumulating on the server");
        float previousHealth=expected.get("health").getAsFloat();
        // Inspected ServerPlayerEntity constructor/tick/damage: vanilla grants
        // 60 join-invulnerability ticks. Preserve that rule rather than forcing damage.
        if(proof.get("resume_fall_landing_age").getAsInt()<60){
            if(proof.get("resume_fall_landing_health").getAsFloat()!=previousHealth||s.health()!=previousHealth)
                throw new IllegalStateException("Landing during vanilla login grace changed health");
            loginGraceVerified=true;
        }else{
            if(s.health()>=previousHealth||s.health()<=0||c.player.getHealth()>=previousHealth)
                throw new IllegalStateException("Survival landing after login grace did not apply fall damage");
            fallDamageVerified=true;
        }
        resumeVerified=true;landingVerified=true;fallDistanceVerified=true;point("fall_resume_landed",s);complete(c,true,null);
    }
    /** Two ordinary rising jump edges inside vanilla's double-tap window. */
    private void doubleTap(MinecraftClient c){keys(c,stageTicks<=2||stageTicks>=5&&stageTicks<=6?new int[]{0x20}:new int[0]);}
    private void next(long now){stage++;stageTicks=0;stageAt=now;}
    private boolean mode(MinecraftClient c,State s,String value){return value.equals(s.mode())&&value.equals(c.interactionManager.getCurrentGameMode().getName());}
    private boolean creative(MinecraftClient c,State s){return mode(c,s,"creative")&&s.allowFlying()&&c.player.getAbilities().allowFlying;}
    private boolean flying(MinecraftClient c,State s){return creative(c,s)&&s.flying()&&c.player.getAbilities().flying;}
    private void requireFlying(MinecraftClient c,State s){if(!flying(c,s))throw new IllegalStateException("Expected actual Creative flight at stage "+stage);}
    private void keys(MinecraftClient c,int... desired){
        Set<Integer> next=new HashSet<>();for(int key:desired)next.add(key);long now=System.nanoTime();
        for(int key:List.copyOf(held))if(!next.contains(key)){movement.event(c,event(2,key),now);held.remove(key);}
        for(int key:next)if(held.add(key))movement.event(c,event(1,key),now);
    }
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void inventory(MinecraftClient c){ui.apply(c,event(1,'E'));ui.apply(c,event(2,'E'));}
    private void edit(MinecraftClient c,int code){ui.apply(c,event(10,code));ui.apply(c,event(11,code));}
    private void type(MinecraftClient c,String text){text.codePoints().forEach(cp->{ui.apply(c,event(9,cp));textEvents++;});}
    private void openChat(MinecraftClient c){keys(c);movement.suspend(c);ui.apply(c,event(1,0xbf));ui.apply(c,event(2,0xbf));if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Real command editor did not open");}
    private void command(MinecraftClient c,String text){openChat(c);type(c,text);if(!ui.chatText(c).equals("/"+text))throw new IllegalStateException("Actual command text differs");edit(c,13);if(c.currentScreen!=null||!c.inGameHud.getChatHud().getMessageHistory().contains("/"+text))throw new IllegalStateException("Vanilla command did not submit");commands.add("/"+text);}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);
        if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Flight fixture server identity changed");
        observed.set(new State(System.nanoTime(),p.getPos(),p.interactionManager.getGameMode().getName(),p.getAbilities().allowFlying,p.getAbilities().flying,p.isOnGround(),p.isSprinting(),p.getHealth(),p.fallDistance,p.getAttributeValue(EntityAttributes.GENERIC_SAFE_FALL_DISTANCE),p.getAttributeValue(EntityAttributes.GENERIC_FALL_DAMAGE_MULTIPLIER)));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Flight fixture owner changed");}
    private void point(String name,State s){var j=json(s.position());j.addProperty("flying",s.flying());j.addProperty("grounded",s.grounded());j.addProperty("health",s.health());j.addProperty("fall_distance",s.fallDistance());points.add(name,j);}
    private static double horizontal(Vec3d a,Vec3d b){return Math.hypot(a.x-b.x,a.z-b.z);}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static Vec3d vector(JsonObject j){return new Vec3d(j.get("x").getAsDouble(),j.get("y").getAsDouble(),j.get("z").getAsDouble());}
    private void complete(MinecraftClient c,boolean passed,String error){
        if(result!=null||finished)return;
        try{keys(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_flight_fixture_v1");j.addProperty("mode",mode);j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);
        j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("direct_command_api_used",false);j.addProperty("ability_writes_used",false);j.addProperty("position_writes_used",false);
        j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("stage",stage);j.addProperty("stage_ticks",stageTicks);j.addProperty("text_events",textEvents);j.addProperty("flight_ticks",flightTicks);j.addProperty("inventory_ticks",inventoryTicks);j.addProperty("chat_ticks",chatTicks);j.addProperty("scripted_view_writes",viewWrites);j.addProperty("max_altitude",maxAltitude);j.addProperty("normal_peak_speed",normalPeakSpeed);j.addProperty("sprint_peak_speed",sprintPeakSpeed);
        j.addProperty("takeoff_verified",takeoffVerified);j.addProperty("ascent_verified",ascentVerified);j.addProperty("descent_verified",descentVerified);j.addProperty("horizontal_verified",horizontalVerified);j.addProperty("sprint_verified",sprintVerified);j.addProperty("inventory_suppression_verified",inventoryVerified);j.addProperty("chat_suppression_verified",chatVerified);j.addProperty("landing_verified",landingVerified);j.addProperty("mode_change_verified",modeChangeVerified);j.addProperty("second_takeoff_verified",secondTakeoffVerified);j.addProperty("resume_verified",resumeVerified);
        j.addProperty("falling_save_verified",fallingSaveVerified);j.addProperty("fall_damage_verified",fallDamageVerified);j.addProperty("fall_distance_preserved",fallDistanceVerified);j.addProperty("login_grace_verified",loginGraceVerified);
        var list=new JsonArray();commands.forEach(list::add);j.add("submitted_commands",list);j.add("movement",movement.evidence(c));j.add("points",points.deepCopy());if(initial!=null)j.add("initial_position",json(initial));var s=observed.get();
        if(s!=null){j.addProperty("game_mode",s.mode());j.addProperty("server_flying",s.flying());j.addProperty("health",s.health());j.addProperty("fall_distance",s.fallDistance());j.addProperty("safe_fall_distance",s.safeFallDistance());j.addProperty("fall_damage_multiplier",s.fallDamageMultiplier());j.add("server_position",json(s.position()));}
        if(passed&&expected==null){var w=new JsonObject();w.addProperty("schema",1);w.addProperty("kind","minecome_gameplay_flight_witness_v1");w.addProperty("world_id",save.id().toString());w.addProperty("player_id",playerId.toString());w.addProperty("game_mode",s.mode());w.addProperty("flying",s.flying());if(mode.equals("flight-fall")){w.addProperty("falling",true);w.addProperty("health",s.health());w.addProperty("fall_distance",s.fallDistance());}w.add("position",json(s.position()));pendingWitness.set(w);}
        result=j;pendingResult.set(j.deepCopy());
    }
    private void writeLoop(){long seq=0;try{while(!closing){
        var proof=pendingResult.getAndSet(null);if(proof!=null){var w=pendingWitness.getAndSet(null);if(w!=null){save.verifyOwnership();Files.writeString(witness,w.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}Files.writeString(directory.resolve("gameplay-flight-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());j.add("forward",json(new Vec3d(1,0,0)));j.add("up",json(new Vec3d(0,0,1)));
        Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){keys(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
