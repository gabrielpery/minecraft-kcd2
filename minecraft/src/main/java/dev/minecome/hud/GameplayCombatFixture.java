package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ingame.InventoryScreen;
import net.minecraft.entity.EquipmentSlot;
import net.minecraft.item.Items;
import net.minecraft.block.Blocks;
import net.minecraft.util.math.BlockPos;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.Vec3d;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual vanilla attack packets and mob damage, with an explicitly synthetic host.
 * The fixture writes only its host transport, evidence and ordinary chat commands.
 * It never assigns player health, equipment, entity position or combat cooldowns.
 */
public final class GameplayCombatFixture {
    private record State(long at,int tick,UUID player,String mode,Vec3d position,float health,
                         String held,int heldDamage,String chest,int chestDamage,int armor){}
    private record Sample(String stage,HudReadback.Completed frame){}
    private final GameplayCombat combat;private final GameplayBlocks blocks;private final GameplayMovement movement;
    private final GameplayWorld save;private final HudInputProtocol.Identity identity;private final Path directory;
    private final Consumer<JsonObject> completed;private final long created=System.nanoTime();
    private final AtomicReference<State> observation=new AtomicReference<>();private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(2);
    private final Map<String,JsonObject> images=new ConcurrentHashMap<>();private final Set<String> queued=new HashSet<>();
    private final CopyOnWriteArrayList<JsonObject> hits=new CopyOnWriteArrayList<>();private final List<String> commands=new ArrayList<>();
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;
    private volatile boolean closing,finished;private volatile long hitAck,hurtAck,requestedHurt,hostWrites,viewWrites;
    private volatile Vec3d forward=new Vec3d(1,0,0);private int targetToken=1,stage,ticks,actionTick,readyTick=-1;
    private long begun,stageAt,events;private double bareHit,woodHit,diamondHit,quickHit,bareHurt,armoredHurt;
    private boolean fistVerified,woodVerified,diamondVerified,cooldownVerified,durabilityVerified,inventoryVerified,inventoryAttackAttempted,occlusionVerified,incomingVerified,armorVerified,rendered;
    private float beforeHurt;private State finalState;

    public GameplayCombatFixture(String mode,GameplayCombat combat,GameplayBlocks blocks,GameplayMovement movement,
                                 GameplayWorld save,HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(!mode.equals("combat")||!Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayCombat")||!Boolean.getBoolean("minecome.gameplayWorldBlocks"))
            throw new IllegalArgumentException("Explicit standalone WorldBlocks combat fixture required");
        this.combat=combat;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();if(!save.newlyCreated()||Files.exists(this.directory.resolve("host-combat.json"))||Files.exists(this.directory.resolve("gameplay-combat-fixture.json")))throw new IOException("Combat fixture needs a fresh owned save and transport");
        var worker=new Thread(this::writeLoop,"MineComeGameplayCombatFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0)return;try{owner(c);movement.authority(c,System.nanoTime(),true);}catch(Exception e){complete(c,false,e.toString());}}
    private Vec3d target(){return new Vec3d(2.2,64.9,targetToken==1?0:1.1);}
    public GameplayWorldRenderer.View view(){
        var c=MinecraftClient.getInstance();if(begun==0||closing||finished||c.player!=player)return null;
        var eye=c.player.getEyePos();var f=target().subtract(eye).normalize();var right=f.crossProduct(new Vec3d(0,1,0)).normalize();return new GameplayWorldRenderer.View(eye,f,right.crossProduct(f).normalize(),Math.toRadians(70));
    }
    public GameplayBlocks.Aim renderAim(){
        var c=MinecraftClient.getInstance();if(begun==0||closing||finished||c.player!=player)return null;
        var eye=c.player.getEyePos();var direction=target().subtract(eye).normalize();return new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,direction,3,true,-1,false);
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;
        try{
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready()){if(System.nanoTime()-created>60_000_000_000L)throw new IllegalStateException("Combat fixture terrain readiness timeout");return;}
            if(begun==0)begin(c);owner(c);long now=System.nanoTime();
            if(now-begun>60_000_000_000L||now-stageAt>12_000_000_000L)throw new IllegalStateException("Combat fixture timeout stage="+stage+" state="+state(observation.get())+" combat="+combat.evidence(c));
            observe();var s=observation.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
            if(!s.player().equals(playerId))throw new IllegalStateException("Combat fixture player changed");ticks++;
            combat.tick(c,c.currentScreen==null,renderAim(),-1);
            switch(stage){
                case 0->{send(c,"gamemode survival");send(c,"difficulty normal");send(c,"gamerule naturalRegeneration false");next(1,now);}
                case 1->{if(!s.mode().equals("survival")||!s.held().equals("minecraft:air")||s.health()!=20||!ready(c))return;if(!delay(s,25))return;attack(c);actionTick=s.tick();next(2,now);}
                case 2->{if(!acknowledged(c,1))return;bareHit=damage(0);near(bareHit,1,"Bare-hand vanilla damage");fistVerified=true;if(s.tick()-actionTick<25)return;send(c,"item replace entity @s hotbar.0 with minecraft:wooden_sword");next(3,now);}
                case 3->{if(!s.held().equals("minecraft:wooden_sword")||!c.player.getMainHandStack().isOf(Items.WOODEN_SWORD)||s.heldDamage()!=0||!delay(s,25))return;attack(c);actionTick=s.tick();next(4,now);}
                case 4->{if(!acknowledged(c,2)||s.heldDamage()!=1)return;woodHit=damage(1);near(woodHit,4,"Wooden sword vanilla damage");woodVerified=durabilityVerified=true;if(s.tick()-actionTick<25)return;send(c,"item replace entity @s hotbar.0 with minecraft:diamond_sword");next(5,now);}
                case 5->{if(!s.held().equals("minecraft:diamond_sword")||!c.player.getMainHandStack().isOf(Items.DIAMOND_SWORD)||s.heldDamage()!=0||!delay(s,25))return;targetToken=1;attack(c);actionTick=s.tick();next(6,now);}
                case 6->{if(!acknowledged(c,3)||s.heldDamage()!=1)return;diamondHit=damage(2);near(diamondHit,7,"Diamond sword vanilla damage");diamondVerified=true;if(s.tick()-actionTick>9)throw new IllegalStateException("Cooldown comparison missed its bounded rapid-hit window");targetToken=2;attack(c);next(7,now);}
                case 7->{if(!acknowledged(c,4)||s.heldDamage()!=2)return;quickHit=damage(3);if(quickHit<=0||quickHit>=diamondHit-.2)throw new IllegalStateException("Vanilla cooldown did not reduce rapid second-target damage: "+quickHit);cooldownVerified=true;key(c,'E');actionTick=s.tick();next(8,now);}
                case 8->{if(!(c.currentScreen instanceof InventoryScreen))return;combat.tick(c,false,renderAim(),-1);if(!inventoryAttackAttempted){combat.event(c,event(7,0));combat.event(c,event(8,0));inventoryAttackAttempted=true;}if(s.tick()-actionTick<8)return;if(hits.size()!=4||hitAck!=4)throw new IllegalStateException("Inventory permitted a world attack");inventoryVerified=true;key(c,'E');targetToken=1;send(c,"fill 1 65 -1 1 65 1 minecraft:stone");next(12,now);}
                case 9->{if(hurtAck<1||s.health()>=beforeHurt)return;bareHurt=beforeHurt-s.health();near(bareHurt,8,"Unarmored mobAttack damage");incomingVerified=true;send(c,"item replace entity @s armor.chest with minecraft:diamond_chestplate");send(c,"effect give @s minecraft:instant_health 1 4 true");actionTick=s.tick();next(10,now);}
                case 10->{if(!s.chest().equals("minecraft:diamond_chestplate")||s.armor()<=0||s.health()!=20||s.tick()-actionTick<25)return;beforeHurt=s.health();requestedHurt=2;next(11,now);}
                case 11->{if(hurtAck<2||s.health()>=beforeHurt||s.chestDamage()==0)return;armoredHurt=beforeHurt-s.health();if(armoredHurt<=0||armoredHurt>=bareHurt)throw new IllegalStateException("Minecraft armor did not reduce native damage");armorVerified=true;if(!images.containsKey("combat"))return;validateImage();rendered=true;finalState=s;complete(c,true,null);}
                case 12->{if(!c.world.getBlockState(new BlockPos(1,65,0)).isOf(Blocks.STONE))return;if(combat.aimedTargetDistance(c,renderAim())>=0||combat.event(c,event(7,0)))throw new IllegalStateException("Minecraft wall permitted actor attack");combat.event(c,event(8,0));actionTick=s.tick();next(13,now);}
                case 13->{if(s.tick()-actionTick<5)return;if(hits.size()!=4||hitAck!=4)throw new IllegalStateException("Occluded actor attack changed host health");send(c,"fill 1 65 -1 1 65 1 minecraft:air");next(14,now);}
                case 14->{if(!c.world.getBlockState(new BlockPos(1,65,0)).isAir()||combat.aimedTargetDistance(c,renderAim())<0)return;occlusionVerified=true;beforeHurt=s.health();requestedHurt=1;next(9,now);}
                default->throw new IllegalStateException("Unknown combat fixture stage");
            }
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||c.getServer()==null||!c.isIntegratedServerRunning()||!c.options.getPerspective().isFirstPerson())throw new IllegalStateException("Owned first-person integrated client required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true);begun=stageAt=System.nanoTime();
    }
    private boolean delay(State s,int duration){if(readyTick<0){readyTick=s.tick();return false;}return s.tick()-readyTick>=duration;}
    private boolean ready(MinecraftClient c){var e=combat.evidence(c);return e.get("ready").getAsBoolean()&&!e.get("pending").getAsBoolean();}
    private boolean acknowledged(MinecraftClient c,int n){return hits.size()>=n&&hitAck>=n&&ready(c);}
    private double damage(int index){return hits.get(index).get("damage_mc").getAsDouble();}
    private static void near(double value,double expected,String label){if(Math.abs(value-expected)>.01)throw new IllegalStateException(label+" differs: "+value);}
    private void attack(MinecraftClient c){combat.tick(c,true,renderAim(),-1);if(!combat.event(c,event(7,0)))throw new IllegalStateException("Combat controller did not consume aimed attack");combat.event(c,event(8,0));}
    private void owner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Combat fixture owner changed");}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Combat fixture server owner changed");
        var held=p.getMainHandStack();var chest=p.getEquippedStack(EquipmentSlot.CHEST);observation.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p.interactionManager.getGameMode().getName(),p.getPos(),p.getHealth(),Registries.ITEM.getId(held.getItem()).toString(),held.getDamage(),Registries.ITEM.getId(chest.getItem()).toString(),chest.getDamage(),p.getArmor()));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++events,System.currentTimeMillis(),kind,code,0,0,0);}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void send(MinecraftClient c,String command){owner(c);c.getNetworkHandler().sendChatCommand(command);commands.add(command);}
    private void next(int value,long now){stage=value;stageAt=now;ticks=0;readyTick=-1;}
    public String captureStage(){return !closing&&!finished&&stage==11&&armorVerified&&ticks>=5&&!queued.contains("combat")&&!images.containsKey("combat")?"combat":null;}
    public void captured(HudReadback.Completed frame){if(closing||finished)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("combat_fixture_stage")||!meta.get("combat_fixture_stage").getAsString().equals("combat")||!queued.add("combat"))return;if(!samples.offer(new Sample("combat",frame)))failure.compareAndSet(null,"Combat capture queue full");}
    private void validateImage(){var image=images.get("combat");var m=image.getAsJsonObject("metadata");if(!m.get("screen_kind").getAsString().equals("none")||m.get("frame_format").getAsInt()!=2||!m.has("world_camera")||image.get("hud_pixels").getAsLong()<1000)throw new IllegalStateException("Combat HUD pixels/world view missing");}
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();byte[] layers=f.layersBottomUp();HudLayerPixels.require(layers,f.width(),f.height());int plane=HudPixels.byteSize(f.width(),f.height());long pixels=0;for(int i=3;i<plane;i+=4)if((layers[i]&255)>8)pixels++;
        byte[] png=HudPixels.png(HudPixels.straightTopLeft(Arrays.copyOfRange(layers,0,plane),f.width(),f.height()),f.width(),f.height());String file="combat-"+sample.stage()+".png";Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);
        var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("file",file);p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.addProperty("hud_pixels",pixels);p.add("metadata",JsonParser.parseString(f.metadata()));images.put(sample.stage(),p);
    }
    private JsonObject identity(String kind,long sequence){var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind",kind);p.addProperty("run",identity.run());p.addProperty("world_id",save.id().toString());p.addProperty("target_pid",identity.targetPid());p.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));p.addProperty("patch_run",movement.surface().run());p.addProperty("patch_sha256",movement.surface().sha256());p.addProperty("seq",sequence);p.addProperty("utc_ms",System.currentTimeMillis());return p;}
    private void writeLoop(){long sequence=0;double[] health={100,100};try{while(!closing){
        var sample=samples.poll();if(sample!=null)writeSample(sample);
        var output=directory.resolve("combat.json");if(Files.exists(output,LinkOption.NOFOLLOW_LINKS)){
            if(Files.isSymbolicLink(output)||Files.size(output)>16384)throw new IOException("Combat guest fixture publication invalid");JsonObject guest;
            try{guest=JsonParser.parseString(Files.readString(output,StandardCharsets.UTF_8)).getAsJsonObject();}catch(java.nio.file.FileSystemException sharing){Thread.sleep(5);continue;}
            if(!guest.get("run").getAsString().equals(identity.run())||!guest.get("world_id").getAsString().equals(save.id().toString())||!guest.get("kind").getAsString().equals("minecome_gameplay_combat_guest_v1"))throw new IOException("Combat fixture guest identity differs");
            hurtAck=guest.get("hurt_ack").getAsLong();if(hurtAck>requestedHurt)throw new IOException("Combat fixture unexpected hurt ACK");
            if(guest.has("hit")&&!guest.get("hit").isJsonNull()){
                var hit=guest.getAsJsonObject("hit");long seq=hit.get("seq").getAsLong();if(seq>hitAck){if(seq!=hitAck+1)throw new IOException("Combat fixture skipped hit");int token=hit.get("token").getAsInt();double amount=hit.get("damage_mc").getAsDouble();if(token<1||token>2||!Double.isFinite(amount)||amount<=0||amount>20)throw new IOException("Combat fixture hit invalid");near(hit.get("damage_fraction").getAsDouble(),amount/20,"Combat damage fraction");var record=hit.deepCopy();record.addProperty("synthetic_host_health_before",health[token-1]);health[token-1]=Math.max(0,health[token-1]-amount*5);record.addProperty("synthetic_host_health_after",health[token-1]);hits.add(record);hitAck=seq;}
            }
        }
        var p=identity("minecome_gameplay_combat_host_v1",++sequence);var actors=new JsonArray();for(int token=1;token<=2;token++){var a=new JsonObject();a.addProperty("token",token);a.addProperty("x",movement.surface().centerX()+2.2);a.addProperty("y",movement.surface().centerY()-(token==1?0:1.1));a.addProperty("z",movement.surface().centerZ());a.addProperty("width",.8);a.addProperty("height",1.8);a.addProperty("health",health[token-1]);a.addProperty("max_health",100);a.addProperty("alive",health[token-1]>0);actors.add(a);}p.add("actors",actors);var hurts=new JsonArray();for(long seq=hurtAck+1;seq<=requestedHurt;seq++){var h=new JsonObject();h.addProperty("seq",seq);h.addProperty("attacker_token",1);h.addProperty("damage",8);h.addProperty("kind","melee");hurts.add(h);}p.add("hurts",hurts);p.addProperty("hit_ack",hitAck);write("host-combat",p);hostWrites++;
        var view=new JsonObject();view.addProperty("schema",1);view.addProperty("source_kind","standalone_hud_physical_view_fixture");view.addProperty("run",identity.run());view.addProperty("patch_run",movement.surface().run());view.addProperty("patch_sha256",movement.surface().sha256());view.addProperty("target_pid",identity.targetPid());view.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));view.addProperty("seq",sequence);view.addProperty("utc_ms",System.currentTimeMillis());var f=forward;view.add("forward",vector(new Vec3d(f.x,-f.z,0)));view.add("up",vector(new Vec3d(0,0,1)));write("host-view",view);viewWrites++;Thread.sleep(25);
    }}catch(Exception e){if(!closing)failure.compareAndSet(null,e.toString());}}
    private void write(String name,JsonObject value)throws IOException,InterruptedException{var temp=directory.resolve(name+"-combat-fixture.tmp");Files.writeString(temp,value.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);HudFixtureCameraFiles.replace(temp,directory.resolve(name+".json"));}
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static JsonObject state(State s){var j=new JsonObject();if(s==null)return j;j.addProperty("player_id",s.player().toString());j.addProperty("mode",s.mode());j.addProperty("health",s.health());j.addProperty("held",s.held());j.addProperty("held_damage",s.heldDamage());j.addProperty("chest",s.chest());j.addProperty("chest_damage",s.chestDamage());j.addProperty("armor",s.armor());j.addProperty("server_tick",s.tick());j.add("position",vector(s.position()));return j;}
    private void complete(MinecraftClient c,boolean passed,String error){
        if(finished)return;finished=true;try{combat.suspend(c);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_combat_fixture_v1");p.addProperty("mode","combat");p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",error);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("standalone_scripted",true);p.addProperty("synthetic_host",true);p.addProperty("native_input_verified",false);p.addProperty("live_kcd_verified",false);p.addProperty("position_writes_used",false);p.addProperty("direct_health_inventory_entity_writes",false);p.addProperty("fist_damage_verified",fistVerified);p.addProperty("wooden_sword_verified",woodVerified);p.addProperty("diamond_sword_verified",diamondVerified);p.addProperty("cooldown_verified",cooldownVerified);p.addProperty("durability_verified",durabilityVerified);p.addProperty("inventory_suppression_verified",inventoryVerified);p.addProperty("minecraft_block_occlusion_verified",occlusionVerified);p.addProperty("incoming_damage_verified",incomingVerified);p.addProperty("armor_verified",armorVerified);p.addProperty("render_pixels_verified",rendered);p.addProperty("barehand_damage",bareHit);p.addProperty("wooden_sword_damage",woodHit);p.addProperty("diamond_sword_damage",diamondHit);p.addProperty("rapid_diamond_damage",quickHit);p.addProperty("unarmored_hurt",bareHurt);p.addProperty("armored_hurt",armoredHurt);p.addProperty("host_writes",hostWrites);p.addProperty("scripted_view_writes",viewWrites);p.addProperty("last_stage",stage);p.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);var a=new JsonArray();commands.forEach(a::add);p.add("commands",a);a=new JsonArray();for(var h:hits)a.add(h.deepCopy());p.add("hits",a);a=new JsonArray();if(images.containsKey("combat"))a.add(images.get("combat").deepCopy());p.add("images",a);p.add("final_state",state(finalState==null?observation.get():finalState));p.add("combat",combat.evidence(c));
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-combat-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){combat.suspend(c);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
