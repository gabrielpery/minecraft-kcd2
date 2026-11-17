package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayAimReader;
import net.minecraft.stat.Stats;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.EquipmentSlot;
import net.minecraft.item.Items;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.Vec3d;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Real jump-edge gliding, steering, UI handoff and landing; never writes a flight flag or position. */
public final class GameplayElytraFixture {
    private record State(long at,Vec3d position,Vec3d velocity,String mode,boolean flying,boolean gliding,
                         boolean grounded,boolean elytra,int damage,float health,double eyeHeight,float yaw,float pitch,int rockets,int rocketUses,int tick){}
    private static final String WITNESS="minecome-elytra-fixture.json";
    private final String mode;
    private final boolean nativeMode;
    private final long created=System.nanoTime();
    private final JsonObject expected;
    private final Path witness;
    private final GameplayMovement movement;
    private final GameplayBlocks blocks;
    private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;
    private final Path directory;
    private final Consumer<JsonObject> completed;
    private final AtomicReference<State> observed=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>(),pendingWitness=new AtomicReference<>();
    private final Set<Integer> held=new HashSet<>();
    private final List<String> commands=new ArrayList<>();
    private final JsonObject points=new JsonObject();
    private volatile boolean closing,written;
    private volatile long viewWrites;
    private volatile float viewYaw=-90,viewPitch=0;
    private MinecraftServer server;
    private Object world,player;
    private UUID playerId;
    private HudVanillaUiAdapter ui;
    private long begun,stageAt,sequence,textEvents,glideTicks,inventoryTicks,nativeStartedUtc,nativeCompletedUtc;
    private GameplayAimReader.RenderSample nativeSample;
    private int stage,stageTicks;
    private boolean finished,takeoffVerified,glideVerified,steeringVerified,poseVerified,inventoryVerified,
        resumedVerified,landingVerified,walkingVerified,noEquipmentVerified,rocketVerified,groundRocketRejected,glidingSaveVerified,resumeVerified;
    private int rocketBaseline,rocketUseBaseline,nativeAscentCycleTick,nativeAscentReachedTick;
    private Vec3d initial,baseline;
    private double groundY,maxAltitude;
    private JsonObject result;

    public GameplayElytraFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,HudInputProtocol.Identity identity,
                                 Path directory,Consumer<JsonObject> completed)throws IOException {
        nativeMode=mode.equals("elytra-native");
        if(!Set.of("elytra","elytra-save","elytra-resume","elytra-native").contains(mode)||(nativeMode?Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayElytraCheck"):!Boolean.getBoolean("minecome.gameplayStandalone"))
                ||!Boolean.getBoolean("minecome.gameplayFlight")||!Boolean.getBoolean("minecome.gameplayChat"))
            throw new IllegalArgumentException("Explicit standalone Elytra/flight/chat fixture required");
        this.mode=mode;this.blocks=Objects.requireNonNull(blocks);this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;
        save.verifyOwnership();this.directory=directory.toRealPath();witness=save.directory().resolve(WITNESS);
        if((!nativeMode&&Files.exists(this.directory.resolve("host-view.json")))||Files.exists(this.directory.resolve("gameplay-elytra-fixture.json")))
            throw new IOException("Elytra fixture requires fresh evidence");
        if(mode.equals("elytra-resume")){
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)
                throw new IOException("Saved Elytra fixture witness required");
            expected=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(expected.get("schema").getAsInt()!=1||!expected.get("kind").getAsString().equals("minecome_gameplay_elytra_witness_v1")
                    ||!expected.get("world_id").getAsString().equals(save.id().toString())||!expected.get("gliding").getAsBoolean())throw new IOException("Saved Elytra witness identity differs");
            viewYaw=expected.get("yaw").getAsFloat();viewPitch=expected.get("pitch").getAsFloat();
        }else{
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("Elytra fixture requires a new isolated save");expected=null;
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayElytraFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){
        if(closing||finished||begun==0)return;
        if(result!=null){movement.suspend(c);return;}
        try{requireOwner(c);if(!nativeMode)movement.authority(c,System.nanoTime(),expected==null||resumeVerified);else if(nativeSample==null||!nativeSample.fresh())movement.suspend(c);}catch(Exception e){complete(c,false,e.toString());}
    }
    public void tick(MinecraftClient c,boolean armed,GameplayAimReader.RenderSample sample){
        if(!nativeMode)throw new IllegalStateException("Native Elytra overload used by standalone fixture");
        if(closing||finished)return;
        if(begun==0){
            if(System.nanoTime()-created>90_000_000_000L){complete(c,false,"Native Elytra never armed");return;}
            if(!armed||sample==null||!sample.fresh()||sample.schema()!=3||sample.perspective()!=0)return;
        }else if(!armed){complete(c,false,"Native Elytra input authority lost");return;}
        nativeSample=sample;
        if(sample==null||!sample.fresh()||sample.perspective()!=0){keys(c);movement.suspend(c);return;}
        tick(c);
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(result!=null){movement.suspend(c);if(written||failure.get()!=null){
                if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}
                finished=true;completed.accept(result.deepCopy());}return;}
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready())return;
            if(begun==0)begin(c);requireOwner(c);long now=System.nanoTime();
            if(now-begun>55_000_000_000L||now-stageAt>(nativeMode?30_000_000_000L:10_000_000_000L))throw new IllegalStateException("Elytra fixture deadline stage="+stage+", ticks="+stageTicks);
            observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;
            if(initial==null){initial=s.position();groundY=movement.surface().groundForFeet(initial.x,initial.z,.3);}
            if(c.player.isFallFlying()&&s.gliding())glideTicks++;
            if(s.health()<=0)throw new IllegalStateException("Elytra fixture player died");
            maxAltitude=Math.max(maxAltitude,s.position().y-groundY);stageTicks++;
            if(nativeMode)runNative(c,s,now);else if(expected==null)run(c,s,now);else resume(c,s,now);
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException {
        if(!c.isOnThread()||c.world==null||c.player==null||!c.isIntegratedServerRunning()||c.getServer()==null)
            throw new IllegalStateException("Elytra fixture requires integrated client");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();
        ui=new HudVanillaUiAdapter(c,true,true);begun=stageAt=System.nanoTime();
    }
    private void run(MinecraftClient c,State s,long now){switch(stage){
        case 0 -> {command(c,"item replace entity @s armor.chest with minecraft:elytra");next(now);}
        case 1 -> {
            if(s.at()<=stageAt||!s.elytra()||!c.player.getEquippedStack(EquipmentSlot.CHEST).isOf(Items.ELYTRA)||!s.grounded())return;
            if(!"creative".equals(s.mode()))throw new IllegalStateException("Fixture did not begin in Creative");point("equipped",s);command(c,"item replace entity @s weapon.mainhand with minecraft:firework_rocket 3");next(now);
        }
        case 2 -> {
            if(s.rockets()!=3||!c.player.getMainHandStack().isOf(Items.FIREWORK_ROCKET)||c.player.getMainHandStack().getCount()!=3){stageTicks=0;return;}
            keys(c,stageTicks<=2||stageTicks>=5&&stageTicks<=6?new int[]{0x20}:new int[0]);
            if(stageTicks>=10&&s.flying()&&c.player.getAbilities().flying){takeoffVerified=true;next(now);}
        }
        case 3 -> {
            keys(c,stageTicks<=26?new int[]{0x20}:new int[0]);
            if(stageTicks>=40){
                if(!s.flying()||s.position().y-groundY<9)throw new IllegalStateException("Vanilla ascent did not reach glide altitude");
                point("before_glide",s);viewPitch=40;command(c,"gamemode survival");next(now);
            }
        }
        case 4 -> {
            if(s.at()<=stageAt||!"survival".equals(s.mode())||s.flying()||c.player.getAbilities().flying)return;
            if(s.grounded())throw new IllegalStateException("Landed before ordinary Elytra jump edge");
            keys(c,0x20);next(now);
        }
        case 5 -> {
            keys(c);if(s.at()<=stageAt||!s.gliding()||!c.player.isFallFlying())return;
            if(!s.elytra()||s.flying()||c.player.getAbilities().flying)throw new IllegalStateException("Glide is not vanilla Survival Elytra");
            if(Math.abs(s.eyeHeight()-.4)>.001||Math.abs(c.player.getEyeHeight(c.player.getPose())-.4)>.001)return;
            glideVerified=true;poseVerified=true;point("glide_started",s);baseline=s.position();next(now);
        }
        case 6 -> {
            requireGlide(c,s);
            if(stageTicks>=5){if(horizontal(baseline,s.position())<.015)throw new IllegalStateException("Glide did not move without walking keys");point("forward_glide",s);viewYaw=0;viewPitch=25;baseline=s.position();next(now);}
        }
        case 7 -> {
            requireGlide(c,s);
            if(stageTicks>=8){
                if(Math.abs(c.player.getYaw())>.1||Math.abs(c.player.getPitch()-25)>.1||s.position().z-baseline.z<.01)
                    throw new IllegalStateException("Host-view yaw/pitch did not steer actual glide");
                steeringVerified=true;point("steered",s);
                if(mode.equals("elytra-save")){glidingSaveVerified=true;point("saved_glide",s);complete(c,true,null);return;}
                keys(c);viewYaw=90;viewPitch=78;next(now);
            }
        }
        case 8 -> {
            requireGlide(c,s);
            if(stageTicks>=3&&Math.abs(c.player.getPitch()-78)<.1){
                rocketBaseline=s.rockets();rocketUseBaseline=s.rocketUses();baseline=s.position();
                blocks.event(c,event(7,1));blocks.event(c,event(8,1));next(now);
            }
        }
        case 9 -> {
            requireGlide(c,s);
            if(s.rockets()==rocketBaseline-1&&s.rocketUses()==rocketUseBaseline+1&&c.player.getMainHandStack().getCount()==s.rockets()
                    &&c.player.getVelocity().y<-.3&&baseline.y-s.position().y>.1){
                rocketVerified=true;point("rocket_boost",s);movement.suspend(c);inventory(c);next(now);
            }
            if(stageTicks>8)throw new IllegalStateException("Vanilla rocket use/consumption/boost missing: "+blocks.evidence(c));
        }
        case 10 -> {
            if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Glide inventory closed unexpectedly");
            requireGlide(c,s);inventoryTicks++;
            if(stageTicks==4)baseline=s.position();
            keys(c,stageTicks>=5&&stageTicks<=12?new int[]{'W',0x20}:new int[0]);
            if(stageTicks>=18){
                if(baseline.distanceTo(s.position())>.035)throw new IllegalStateException("Glide drifted during the bridge inventory hold");
                inventoryVerified=true;keys(c);viewYaw=90;viewPitch=78;inventory(c);baseline=s.position();point("held_inventory",s);next(now);
            }
        }
        case 11 -> {
            if(stageTicks>=2&&s.position().distanceTo(baseline)>.06)resumedVerified=true;
            if(s.grounded()&&!s.gliding()&&!c.player.isFallFlying()){
                if(!resumedVerified||s.flying()||Math.abs(s.position().y-groundY)>.15)throw new IllegalStateException("Glide did not resume and land naturally on captured terrain");
                landingVerified=true;point("landed",s);viewPitch=0;baseline=s.position();next(now);
            }
        }
        case 12 -> {
            keys(c,stageTicks<=2?new int[]{'W'}:new int[0]);
            if(stageTicks>=16){
                if(!s.grounded()||s.gliding()||horizontal(baseline,s.position())<.05)throw new IllegalStateException("Walking failed after glide landing");
                walkingVerified=true;point("walked_after_landing",s);rocketBaseline=s.rockets();rocketUseBaseline=s.rocketUses();
                blocks.event(c,event(7,1));blocks.event(c,event(8,1));next(now);
            }
        }
        case 13 -> {
            if(stageTicks<6)return;
            if(s.rockets()!=rocketBaseline||s.rocketUses()!=rocketUseBaseline)throw new IllegalStateException("Grounded right click incorrectly consumed a glide rocket");
            groundRocketRejected=true;command(c,"item replace entity @s armor.chest with minecraft:air");next(now);
        }
        case 14 -> {if(s.at()<=stageAt||s.elytra()||c.player.getEquippedStack(EquipmentSlot.CHEST).isOf(Items.ELYTRA))return;next(now);}
        case 15 -> {
            keys(c,stageTicks<=2||stageTicks>=5&&stageTicks<=6?new int[]{0x20}:new int[0]);
            if(s.gliding()||c.player.isFallFlying())throw new IllegalStateException("Missing Elytra still permitted gliding");
            if(stageTicks>=25&&s.grounded()){noEquipmentVerified=true;point("unequipped_jump",s);complete(c,true,null);}
        }
        default -> throw new IllegalStateException("Unknown Elytra fixture stage");
    }}
    private void runNative(MinecraftClient c,State s,long now){switch(stage){
        case 0 -> {command(c,"item replace entity @s armor.chest with minecraft:elytra");next(now);}
        case 1 -> {
            if(s.at()<=stageAt||!s.elytra()||!c.player.getEquippedStack(EquipmentSlot.CHEST).isOf(Items.ELYTRA)||!s.grounded())return;
            if(!"creative".equals(s.mode()))throw new IllegalStateException("Native fixture did not begin in Creative");
            point("native_equipped",s);command(c,"item replace entity @s weapon.mainhand with minecraft:firework_rocket 3");next(now);
        }
        case 2 -> {
            if(s.rockets()!=3||!c.player.getMainHandStack().isOf(Items.FIREWORK_ROCKET)||c.player.getMainHandStack().getCount()!=3){stageTicks=0;return;}
            keys(c,stageTicks<=2||stageTicks>=5&&stageTicks<=6?new int[]{0x20}:new int[0]);
            if(stageTicks>=10&&s.flying()&&c.player.getAbilities().flying){takeoffVerified=true;next(now);}
        }
        case 3 -> {
            if(!s.flying()||!c.player.getAbilities().flying)throw new IllegalStateException("Native Creative ascent lost vanilla flight");
            // Additive terrain installation releases all controls. Balance the
            // fixture's cached key edge too, then wait beyond vanilla's seven-tick
            // double-tap window. Actual server age bounds each input cycle; this
            // never changes abilities or treats a lost hold as completed ascent.
            if(movement.terrainTransition()){
                keys(c);nativeAscentCycleTick=s.tick()+12;nativeAscentReachedTick=0;return;
            }
            if(s.position().y-groundY>=7){
                keys(c);if(nativeAscentReachedTick==0)nativeAscentReachedTick=s.tick();
                if(s.tick()-nativeAscentReachedTick>=12){point("native_before_glide",s);command(c,"gamemode survival");next(now);}
                return;
            }
            if(nativeAscentCycleTick==0)nativeAscentCycleTick=s.tick()+12;
            int elapsed=s.tick()-nativeAscentCycleTick;
            keys(c,elapsed>=0&&elapsed%24<12?new int[]{0x20}:new int[0]);
        }
        case 4 -> {
            if(s.at()<=stageAt||!"survival".equals(s.mode())||s.flying()||c.player.getAbilities().flying)return;
            if(s.grounded())throw new IllegalStateException("Native player landed before Elytra jump edge");keys(c,0x20);next(now);
        }
        case 5 -> {
            keys(c);if(s.at()<=stageAt||!s.gliding()||!c.player.isFallFlying())return;
            if(!s.elytra()||s.flying()||c.player.getAbilities().flying)throw new IllegalStateException("Native glide is not vanilla Survival Elytra");
            if(Math.abs(s.eyeHeight()-.4)>.001||Math.abs(c.player.getEyeHeight(c.player.getPose())-.4)>.001)return;
            glideVerified=true;poseVerified=true;point("glide_started",s);baseline=s.position();nativeStartedUtc=System.currentTimeMillis();next(now);
        }
        case 6 -> {
            requireGlide(c,s);
            if(stageTicks>=10){
                if(horizontal(baseline,s.position())<.08)throw new IllegalStateException("Native-view glide did not travel without walking keys");
                point("native_glided",s);keys(c);movement.suspend(c);inventory(c);next(now);
            }
        }
        case 7 -> {
            if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Native glide inventory closed unexpectedly");
            requireGlide(c,s);inventoryTicks++;if(stageTicks==4)baseline=s.position();
            keys(c,stageTicks>=5&&stageTicks<=12?new int[]{'W',0x20}:new int[0]);
            if(stageTicks>=20&&now-stageAt>=12_000_000_000L){
                if(baseline.distanceTo(s.position())>.035)throw new IllegalStateException("Native glide moved during inventory hold");
                inventoryVerified=true;keys(c);inventory(c);baseline=s.position();point("held_inventory",s);next(now);
            }
        }
        case 8 -> {
            requireGlide(c,s);
            if(stageTicks>=10){
                if(s.position().distanceTo(baseline)<.08)throw new IllegalStateException("Native glide did not resume after inventory");
                resumedVerified=true;point("native_resumed",s);movement.suspend(c);inventory(c);next(now);
            }
        }
        case 9 -> {
            requireGlide(c,s);
            if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Native final glide hold lost inventory");
            if(now-stageAt>=600_000_000L){
                glidingSaveVerified=true;nativeCompletedUtc=System.currentTimeMillis();point("native_final_hold",s);complete(c,true,null);
            }
        }
        default -> throw new IllegalStateException("Unknown native Elytra fixture stage");
    }}
    private void resume(MinecraftClient c,State s,long now){switch(stage){
        case 0 -> {
            requireGlide(c,s);var proof=movement.evidence(c);var checkpoint=proof.getAsJsonObject("resume_checkpoint");
            if(!playerId.toString().equals(expected.get("player_id").getAsString())||!proof.get("resume_position_restored").getAsBoolean()
                    ||proof.get("first_attachment").getAsBoolean()||checkpoint==null||!checkpoint.get("gliding").getAsBoolean()
                    ||checkpoint.get("flying").getAsBoolean()||checkpoint.get("falling").getAsBoolean()
                    ||s.position().distanceTo(vector(checkpoint))>.04||initial.distanceTo(vector(checkpoint))>.04)
                throw new IllegalStateException("Reopened Elytra did not restore exact owned glide checkpoint");
            if(!s.mode().equals("survival")||s.health()!=expected.get("health").getAsFloat()||s.rockets()!=expected.get("rockets").getAsInt()
                    ||s.rocketUses()!=expected.get("rocket_uses").getAsInt()||s.damage()<expected.get("elytra_damage").getAsInt()
                    ||Math.abs(s.eyeHeight()-.4)>.001||!c.player.getEquippedStack(EquipmentSlot.CHEST).isOf(Items.ELYTRA))
                throw new IllegalStateException("Saved vanilla player/equipment/glide pose differs");
            glideVerified=true;poseVerified=true;resumeVerified=true;point("resumed_glide",s);baseline=s.position();viewYaw=90;viewPitch=78;next(now);
        }
        case 1 -> {
            if(s.position().distanceTo(baseline)>.1)resumedVerified=true;
            if(Math.abs(c.player.getYaw()-90)<.1&&Math.abs(c.player.getPitch()-78)<.1&&s.position().x<baseline.x-.01)steeringVerified=true;
            if(s.grounded()&&!s.gliding()&&!c.player.isFallFlying()){
                if(!resumedVerified||!steeringVerified||s.flying()||Math.abs(s.position().y-groundY)>.15)throw new IllegalStateException("Saved glide did not steer and land on captured terrain");
                landingVerified=true;point("resume_landed",s);viewPitch=0;baseline=s.position();next(now);
            }
        }
        case 2 -> {
            keys(c,stageTicks<=2?new int[]{'W'}:new int[0]);
            if(stageTicks>=16){
                if(!s.grounded()||s.gliding()||horizontal(baseline,s.position())<.05)throw new IllegalStateException("Walking failed after reopened glide landing");
                walkingVerified=true;point("resume_walked",s);complete(c,true,null);
            }
        }
        default -> throw new IllegalStateException("Unknown Elytra resume stage");
    }}
    private void requireGlide(MinecraftClient c,State s){if(!s.gliding()||!c.player.isFallFlying()||s.flying()||!s.elytra())throw new IllegalStateException("Expected actual Elytra glide at stage "+stage);}
    private void next(long now){stage++;stageTicks=0;stageAt=now;}
    private void keys(MinecraftClient c,int... desired){
        Set<Integer> next=new HashSet<>();for(int key:desired)next.add(key);long now=System.nanoTime();
        for(int key:List.copyOf(held))if(!next.contains(key)){movement.event(c,event(2,key),now);held.remove(key);}
        for(int key:next)if(held.add(key))movement.event(c,event(1,key),now);
    }
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void inventory(MinecraftClient c){ui.apply(c,event(1,'E'));ui.apply(c,event(2,'E'));}
    private void edit(MinecraftClient c,int code){ui.apply(c,event(10,code));ui.apply(c,event(11,code));}
    private void type(MinecraftClient c,String text){text.codePoints().forEach(cp->{ui.apply(c,event(9,cp));textEvents++;});}
    private void command(MinecraftClient c,String text){
        keys(c);movement.suspend(c);ui.apply(c,event(1,0xbf));ui.apply(c,event(2,0xbf));
        if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Real command editor did not open");
        type(c,text);if(!ui.chatText(c).equals("/"+text))throw new IllegalStateException("Actual command text differs");
        edit(c,13);if(c.currentScreen!=null||!c.inGameHud.getChatHud().getMessageHistory().contains("/"+text))throw new IllegalStateException("Vanilla command did not submit");commands.add("/"+text);
    }
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);
        if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Elytra fixture server identity changed");
        var chest=p.getEquippedStack(EquipmentSlot.CHEST);
        observed.set(new State(System.nanoTime(),p.getPos(),p.getVelocity(),p.interactionManager.getGameMode().getName(),p.getAbilities().flying,p.isFallFlying(),p.isOnGround(),chest.isOf(Items.ELYTRA),chest.getDamage(),p.getHealth(),p.getEyeHeight(p.getPose()),p.getYaw(),p.getPitch(),p.getMainHandStack().isOf(Items.FIREWORK_ROCKET)?p.getMainHandStack().getCount():0,p.getStatHandler().getStat(Stats.USED,Items.FIREWORK_ROCKET),p.age));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Elytra fixture owner changed");}
    private void point(String name,State s){var j=json(s.position());j.addProperty("gliding",s.gliding());j.addProperty("flying",s.flying());j.addProperty("grounded",s.grounded());j.addProperty("health",s.health());j.addProperty("elytra_damage",s.damage());j.addProperty("eye_height",s.eyeHeight());j.addProperty("yaw",s.yaw());j.addProperty("pitch",s.pitch());j.addProperty("rockets",s.rockets());j.addProperty("rocket_uses",s.rocketUses());j.add("velocity",json(s.velocity()));points.add(name,j);}
    private static Vec3d vector(JsonObject j){return new Vec3d(j.get("x").getAsDouble(),j.get("y").getAsDouble(),j.get("z").getAsDouble());}
    private static double horizontal(Vec3d a,Vec3d b){return Math.hypot(a.x-b.x,a.z-b.z);}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private void complete(MinecraftClient c,boolean passed,String error){
        if(result!=null||finished)return;
        try{keys(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_elytra_fixture_v1");j.addProperty("mode",mode);j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);
        j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",!nativeMode);j.addProperty("live_kcd_connected",nativeMode);j.addProperty("native_camera_preserved",nativeMode);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("direct_command_api_used",false);j.addProperty("ability_writes_used",false);j.addProperty("position_writes_used",false);j.addProperty("glide_flag_writes_used",false);
        j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("stage",stage);j.addProperty("stage_ticks",stageTicks);j.addProperty("text_events",textEvents);j.addProperty("glide_ticks",glideTicks);j.addProperty("inventory_ticks",inventoryTicks);j.addProperty("scripted_view_writes",viewWrites);j.addProperty("native_elytra_started_utc_ms",nativeStartedUtc);j.addProperty("native_elytra_completed_utc_ms",nativeCompletedUtc);j.addProperty("max_altitude",maxAltitude);
        j.addProperty("creative_takeoff_verified",takeoffVerified);j.addProperty("glide_verified",glideVerified);j.addProperty("steering_verified",steeringVerified);j.addProperty("glide_pose_verified",poseVerified);j.addProperty("inventory_hold_verified",inventoryVerified);j.addProperty("glide_resumed_verified",resumedVerified);j.addProperty("landing_verified",landingVerified);j.addProperty("walking_after_landing_verified",walkingVerified);j.addProperty("missing_elytra_rejected",noEquipmentVerified);j.addProperty("rocket_boost_verified",rocketVerified);j.addProperty("ground_rocket_rejected",groundRocketRejected);j.addProperty("gliding_save_verified",glidingSaveVerified);j.addProperty("resume_verified",resumeVerified);j.add("blocks",blocks.evidence(c));
        var list=new JsonArray();commands.forEach(list::add);j.add("submitted_commands",list);j.add("movement",movement.evidence(c));j.add("points",points.deepCopy());if(initial!=null)j.add("initial_position",json(initial));var s=observed.get();
        if(s!=null){j.addProperty("game_mode",s.mode());j.addProperty("server_gliding",s.gliding());j.addProperty("health",s.health());j.add("server_position",json(s.position()));}
        if(passed&&mode.equals("elytra-save")){
            var w=new JsonObject();w.addProperty("schema",1);w.addProperty("kind","minecome_gameplay_elytra_witness_v1");w.addProperty("world_id",save.id().toString());w.addProperty("player_id",playerId.toString());
            w.addProperty("gliding",s.gliding());w.addProperty("health",s.health());w.addProperty("rockets",s.rockets());w.addProperty("rocket_uses",s.rocketUses());w.addProperty("elytra_damage",s.damage());
            w.addProperty("yaw",s.yaw());w.addProperty("pitch",s.pitch());w.add("position",json(s.position()));pendingWitness.set(w);
        }
        result=j;pendingResult.set(j.deepCopy());
    }
    private void writeLoop(){long seq=0;try{while(!closing){
        var proof=pendingResult.getAndSet(null);if(proof!=null){var w=pendingWitness.getAndSet(null);if(w!=null){save.verifyOwnership();Files.writeString(witness,w.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}Files.writeString(directory.resolve("gameplay-elytra-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}
        if(nativeMode){Thread.sleep(25);continue;}
        double yaw=Math.toRadians(viewYaw),pitch=Math.toRadians(viewPitch);
        var forward=new Vec3d(-Math.sin(yaw)*Math.cos(pitch),-Math.cos(yaw)*Math.cos(pitch),-Math.sin(pitch));
        var up=new Vec3d(-Math.sin(yaw)*Math.sin(pitch),-Math.cos(yaw)*Math.sin(pitch),Math.cos(pitch));
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());j.add("forward",json(forward));j.add("up",json(up));
        Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){keys(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
