package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ingame.InventoryScreen;
import net.minecraft.item.Items;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Connected acceptance: a real native camera ray, vanilla melee/bow input and
 * native health/ACK, then ordinary inventory and walking input. This fixture
 * never writes a camera/host snapshot, health, position, inventory or NPC.
 * Its external native helper owns one isolated test NPC and removes it afterward.
 */
public final class GameplayNativeCombatFixture implements AutoCloseable {
    private record State(long at,int tick,UUID player,Vec3d position,Vec3d velocity,String mode,String held,int damage,int arrows,boolean using,int useTicks){}
    private record Frame(String stage,HudReadback.Completed frame){}
    private final boolean projectileCheck=Boolean.getBoolean("minecome.gameplayProjectileCheck");
    private final List<String> CAPTURES=projectileCheck?List.of("before","hit","scenery","inventory","walking","after"):List.of("before","hit","inventory","walking","after");
    private boolean sceneryVerified;private JsonObject sceneryProof;
    private final GameplayCombat combat;private final GameplayBlocks blocks;private final GameplayMovement movement;private final GameplayWorld save;
    private final Path directory;private final Consumer<JsonObject> completed;private final long created=System.nanoTime();
    private final AtomicReference<State> observed=new AtomicReference<>();private final AtomicReference<String> failure=new AtomicReference<>();private final AtomicBoolean observing=new AtomicBoolean();
    private final ArrayBlockingQueue<Frame> queue=new ArrayBlockingQueue<>(6);private final Map<String,JsonObject> images=new ConcurrentHashMap<>();private final Set<String> queued=new HashSet<>();
    private final List<String> commands=new ArrayList<>();private final JsonArray points=new JsonArray();
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;private GameplayAimReader.RenderSample sample;
    private long began,stageAt,sequence,compositionDwellAt,compositionWindowStartUtc,compositionWindowEndUtc;private int stage,ticks,readyTick=-1,held;private volatile boolean closed,finished;
    private int targetToken;private double beforeHealth,afterHealth,maximum,actualDamage,walkDistance,inventoryNativeHorizontalDrift;private Vec3d inventoryStart,inventoryEyeStart,walkStart,eyeStart;
    private boolean nativeHitVerified,durabilityVerified,inventoryVerified,walkVerified,renderVerified;private JsonObject initialCombat;

    public GameplayNativeCombatFixture(GameplayCombat combat,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayWorldBlocks")||!Boolean.getBoolean("minecome.gameplayCombat")||!Boolean.getBoolean("minecome.gameplayCombatCheck"))throw new IllegalArgumentException("Explicit connected combat check required");
        this.combat=combat;this.blocks=blocks;this.movement=movement;this.save=save;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();if(!save.newlyCreated()||Files.exists(this.directory.resolve("gameplay-native-combat-fixture.json")))throw new IOException("Native combat check requires fresh owned save and output");
        var writer=new Thread(this::writeLoop,"MineComeNativeCombatImages");writer.setDaemon(true);writer.start();
    }
    public void tick(MinecraftClient c,boolean armed,GameplayAimReader.RenderSample nativeSample){if(closed||finished)return;try{
        if(failure.get()!=null)throw new IllegalStateException(failure.get());long now=System.nanoTime();
        if(began==0){
            if(now-created>90_000_000_000L)throw new IllegalStateException("Native combat never armed");
            if(!armed||!movement.ready()||!blocks.ready()||!combat.ready()||nativeSample==null||!nativeSample.fresh()||nativeSample.schema()!=3||nativeSample.perspective()!=0)return;
            sample=nativeSample;begin(c);send(c,"gamemode survival");send(c,"item replace entity @s hotbar.0 with minecraft:"+(projectileCheck?"bow":"diamond_sword"));if(projectileCheck)send(c,"item replace entity @s hotbar.1 with minecraft:arrow 4");key(c,'1');next(1,now);return;
        }
        owner(c);if(!armed)throw new IllegalStateException("Native combat input authority lost");
        if(now-began>45_000_000_000L||now-stageAt>15_000_000_000L)throw new IllegalStateException("Native combat deadline stage="+stage+" state="+combat.evidence(c));
        sample=nativeSample;
        if(sample==null||!sample.fresh()||sample.schema()!=3||sample.perspective()!=0){release(c);return;}
        observe();var s=observed.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;ticks++;
        if(walkStart!=null&&c.player.getPos().subtract(walkStart).horizontalLength()>1)throw new IllegalStateException("Native combat walk exceeded one metre");
        switch(stage){
            case 1->{
                if(!s.mode().equals("survival")||!s.held().equals(projectileCheck?"minecraft:bow":"minecraft:diamond_sword")||s.damage()!=0||!c.player.getMainHandStack().isOf(projectileCheck?Items.BOW:Items.DIAMOND_SWORD)||!combat.ready())return;
                if(readyTick<0){readyTick=s.tick();return;}if(s.tick()-readyTick<25)return;
                if(combat.aimedTargetDistance(c,sample.aim())<0)return;
                var actors=combat.knownActors();if(actors.size()!=1||actors.get(0).token()!=1)throw new IllegalStateException("Native combat fixture target is not isolated token1");
                var target=aimedActor(c);if(target==null)return;targetToken=target.token();beforeHealth=target.health();maximum=target.maxHealth();
                if(beforeHealth<=maximum*.35)throw new IllegalStateException("Fixture NPC cannot survive one diamond sword hit");
                if(!images.containsKey("before"))return;initialCombat=combat.evidence(c);point("before",c,s);
                if(projectileCheck){bowPress(c);next(20,now);return;}
                if(!combat.event(c,event(7,0)))throw new IllegalStateException("Native ray did not consume actor attack");combat.event(c,event(8,0));next(2,now);
            }
            case 2->{
                var proof=combat.evidence(c);
                if(proof.get("attacks_dispatched").getAsLong()==1&&proof.get("outgoing_hits").getAsLong()==0&&!proof.get("pending").getAsBoolean()&&
                        (proof.get("server_rejected").getAsLong()>0||proof.get("rejected").getAsLong()>0))
                    throw new IllegalStateException("Native combat primary attack was rejected: "+(proof.has("last_rejection")?proof.get("last_rejection"):proof));
                if(proof.get("outgoing_hits").getAsLong()!=1||proof.get("hit_ack").getAsLong()!=1||proof.get("pending").getAsBoolean()||s.damage()!=1)return;
                var target=actor(targetToken);if(target==null||target.health()>=beforeHealth)return;afterHealth=target.health();actualDamage=proof.get("server_applied_damage").getAsDouble();
                if(Math.abs(actualDamage-7)>.01||Math.abs((beforeHealth-afterHealth)/maximum-actualDamage/20)>.02)throw new IllegalStateException("Native NPC health differs from vanilla sword damage: before="+beforeHealth+", after="+afterHealth+", max="+maximum+", MC="+actualDamage);
                nativeHitVerified=durabilityVerified=true;if(!images.containsKey("hit"))return;point("hit",c,s);inventoryStart=c.player.getPos();inventoryEyeStart=sample.aim().origin();key(c,'E');next(3,now);
            }
            case 3->{
                if(!(c.currentScreen instanceof InventoryScreen))return;if(ticks==2)movementKey(c,'W',true);if(ticks==8)release(c);
                if(c.player.getPos().distanceTo(inventoryStart)>.03||s.position().distanceTo(inventoryStart)>.05)throw new IllegalStateException("Native combat inventory allowed movement");
                // Native idle animation can bob vertically; horizontal travel
                // must remain well below the smallest accepted walking step.
                inventoryNativeHorizontalDrift=Math.max(inventoryNativeHorizontalDrift,sample.aim().origin().subtract(inventoryEyeStart).horizontalLength());
                if(inventoryNativeHorizontalDrift>.08)throw new IllegalStateException("Native camera moved horizontally in inventory: "+inventoryNativeHorizontalDrift);
                if(ticks>=12&&images.containsKey("inventory")){release(c);inventoryVerified=true;point("inventory",c,s);key(c,'E');next(4,now);}
            }
            case 20->{if(!s.using()||s.useTicks()<25)return;blocks.event(c,event(8,1));next(21,now);}
            case 21->{
                var proof=combat.evidence(c).getAsJsonObject("projectiles");
                if(proof.get("impacts").getAsLong()!=1||proof.get("pending").getAsBoolean()||s.damage()!=1||s.arrows()!=3)return;
                var target=actor(targetToken);if(target==null||target.health()>=beforeHealth)return;
                afterHealth=target.health();actualDamage=proof.get("damage").getAsDouble();
                if(actualDamage<=0||actualDamage>20||Math.abs((beforeHealth-afterHealth)/maximum-actualDamage/20)>.02)throw new IllegalStateException("Native NPC health differs from vanilla arrow damage");
                nativeHitVerified=durabilityVerified=true;if(!images.containsKey("hit"))return;point("hit",c,s);
                var remove=new JsonObject();remove.addProperty("schema",1);remove.addProperty("kind","minecome_native_projectile_fixture_remove_v1");remove.addProperty("world_id",save.id().toString());remove.addProperty("actor_token",targetToken);
                var requestFile=directory.resolve("projectile-fixture-remove.json");var temporary=directory.resolve("projectile-fixture-remove.json.tmp");
                Files.writeString(temporary,remove.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
                Files.move(temporary,requestFile,StandardCopyOption.ATOMIC_MOVE);next(22,now);
            }
            case 22->{
                var file=directory.resolve("projectile-fixture-removed.json");if(!Files.exists(file))return;
                var ack=JsonParser.parseString(Files.readString(file)).getAsJsonObject();
                if(!ack.get("world_id").getAsString().equals(save.id().toString())||!ack.get("removed").getAsBoolean())throw new IllegalStateException("Owned native NPC removal not confirmed");
                if(!combat.knownActors().isEmpty()||!delayAfter(s,4))return;bowPress(c);next(23,now);
            }
            case 23->{if(!s.using()||s.useTicks()<3)return;blocks.event(c,event(8,1));next(24,now);}
            case 24->{
                var proof=combat.evidence(c).getAsJsonObject("projectiles");
                if(proof.get("scenery_hits").getAsLong()!=1||proof.get("pending").getAsBoolean()||s.damage()!=2||s.arrows()!=2)return;
                if(proof.get("impacts").getAsLong()!=1)throw new IllegalStateException("Scenery arrow changed native NPC damage");
                sceneryVerified=true;sceneryProof=proof.deepCopy();if(!images.containsKey("scenery"))return;
                point("scenery",c,s);inventoryStart=c.player.getPos();inventoryEyeStart=sample.aim().origin();key(c,'E');next(3,now);
            }
            case 4->{if(c.currentScreen==null&&ticks>=5&&s.velocity().horizontalLength()<.004){walkStart=c.player.getPos();eyeStart=sample.aim().origin();movementKey(c,'S',true);next(5,now);}}
            case 5->{if(ticks>=5||c.player.getPos().subtract(walkStart).horizontalLength()>=.25){release(c);next(6,now);}}
            case 6->{
                if(ticks<20||s.velocity().horizontalLength()>.004||c.player.getVelocity().horizontalLength()>.004||!images.containsKey("walking"))return;
                var delta=c.player.getPos().subtract(walkStart);var nativeDelta=sample.aim().origin().subtract(eyeStart);walkDistance=delta.horizontalLength();
                if(walkDistance<.15||walkDistance>1||c.player.getPos().distanceTo(s.position())>.05||nativeDelta.horizontalLength()<.1||delta.subtract(nativeDelta).horizontalLength()>.25)throw new IllegalStateException("Native combat walk/camera mismatch: "+delta+" / "+nativeDelta);
                walkVerified=true;
                // ReShade emits native composition counters every five seconds.
                // Keep the post-walk HUD visible across two complete samples;
                // the script requires both counters to advance in this window.
                if(compositionDwellAt==0){compositionDwellAt=now;compositionWindowStartUtc=System.currentTimeMillis();}
                if(now-compositionDwellAt<11_250_000_000L)return;
                if(compositionWindowEndUtc==0)compositionWindowEndUtc=System.currentTimeMillis();
                if(!images.containsKey("after"))return;point("after",c,s);renderVerified=images.keySet().containsAll(CAPTURES);finish(c,true,null);
            }
            default->throw new IllegalStateException("Unknown native combat stage");
        }
    }catch(Exception e){finish(c,false,e.toString());}}
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||c.getServer()==null||!c.isIntegratedServerRunning()||c.currentScreen!=null)throw new IllegalStateException("Owned native combat world required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);began=stageAt=System.nanoTime();observe();
    }
    private GameplayCombatProtocol.Actor actor(int token){for(var a:combat.knownActors())if(a.token()==token)return a;return null;}
    private GameplayCombatProtocol.Actor aimedActor(MinecraftClient c){
        var ray=sample.aim();var end=ray.origin().add(ray.direction().multiply(Math.min(ray.range(),c.player.getEntityInteractionRange())));GameplayCombatProtocol.Actor best=null;double distance=Double.MAX_VALUE;
        for(var a:combat.knownActors())if(a.alive()){
            var p=GameplayCombatProtocol.toMinecraft(new GameplayCombatProtocol.Point(a.x(),a.y(),a.z()),movement.surface());double half=a.width()/2.;
            var hit=new Box(p.x()-half,p.y(),p.z()-half,p.x()+half,p.y()+a.height(),p.z()+half).raycast(ray.origin(),end);
            if(hit.isPresent()&&hit.get().distanceTo(ray.origin())<distance){best=a;distance=hit.get().distanceTo(ray.origin());}
        }return best;
    }
    private void owner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Native combat owner changed");}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closed||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Native combat server owner changed");
        var held=p.getMainHandStack();observed.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p.getPos(),p.getVelocity(),p.interactionManager.getGameMode().getName(),Registries.ITEM.getId(held.getItem()).toString(),held.getDamage(),p.getInventory().count(Items.ARROW),p.isUsingItem(),p.getItemUseTime()));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void send(MinecraftClient c,String command){owner(c);c.getNetworkHandler().sendChatCommand(command);commands.add(command);}
    private void bowPress(MinecraftClient c){blocks.tick(c,true);blocks.event(c,event(7,1));if(!c.player.isUsingItem())throw new IllegalStateException("Connected bow draw did not start: "+blocks.evidence(c).get("ranged_use"));}
    private boolean delayAfter(State s,int duration){if(readyTick<0){readyTick=s.tick();return false;}return s.tick()-readyTick>=duration;}
    private void key(MinecraftClient c,int code){if(code=='E'){combat.suspend(c);blocks.suspend(c);movement.suspend(c);}ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void movementKey(MinecraftClient c,int code,boolean down){movement.event(c,event(down?1:2,code),System.nanoTime());held=down?code:0;}
    private void release(MinecraftClient c){if(held!=0)movementKey(c,held,false);}
    private void next(int value,long now){stage=value;ticks=0;readyTick=-1;stageAt=now;}
    private void point(String label,MinecraftClient c,State s){var p=new JsonObject();p.addProperty("stage",label);p.addProperty("server_tick",s.tick());p.add("client_position",vector(c.player.getPos()));p.add("server_position",vector(s.position()));p.add("native_eye",vector(sample.aim().origin()));p.add("native_camera",vector(sample.view().origin()));p.add("native_direction",vector(sample.aim().direction()));p.addProperty("native_sample_utc_ms",sample.aim().capturedUtcMs());p.addProperty("held_damage",s.damage());points.add(p);}
    public String captureStage(){if(closed||finished||began==0||sample==null||!sample.fresh())return null;var c=MinecraftClient.getInstance();
        boolean moving=c.player==player&&c.player.getVelocity().horizontalLength()>.04;
        String name=switch(stage){case 1->readyTick>=0&&targetToken>0?"before":null;case 2,21->nativeHitVerified?"hit":null;case 24->sceneryVerified?"scenery":null;case 3->ticks>=10?"inventory":null;case 5,6->moving&&!images.containsKey("walking")?"walking":walkVerified&&compositionWindowEndUtc>0?"after":null;default->null;};
        return name==null||queued.contains(name)||images.containsKey(name)?null:name;
    }
    public void captured(HudReadback.Completed frame){if(closed||finished)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("native_combat_stage"))return;String stage=meta.get("native_combat_stage").getAsString();if(!CAPTURES.contains(stage)||stage.equals("scenery")&&meta.get("projectile_render_count").getAsInt()<1||!queued.add(stage))return;if(!queue.offer(new Frame(stage,frame)))failure.compareAndSet(null,"Native combat capture queue full");}
    private void writeLoop(){try{while(!closed){var f=queue.poll(100,TimeUnit.MILLISECONDS);if(f==null)continue;var frame=f.frame();var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();boolean inventory=f.stage().equals("inventory");
        if(meta.get("frame_format").getAsInt()!=2||!meta.has("world_camera")||meta.get("screen").getAsInt()!=(inventory?1:0))throw new IllegalStateException("Native combat HUD/world capture differs: "+f.stage());
        byte[] layers=frame.layersBottomUp();HudLayerPixels.require(layers,frame.width(),frame.height());int plane=HudPixels.byteSize(frame.width(),frame.height());long pixels=0;for(int i=3;i<plane;i+=4)if((layers[i]&255)>8)pixels++;if(pixels<1000)throw new IllegalStateException("Native combat HUD pixels missing");
        byte[] png=HudPixels.png(HudPixels.straightTopLeft(Arrays.copyOfRange(layers,0,plane),frame.width(),frame.height()),frame.width(),frame.height());String file="native-combat-"+f.stage()+".png";Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);
        var p=new JsonObject();p.addProperty("stage",f.stage());p.addProperty("file",file);p.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));p.addProperty("hud_pixels",pixels);p.add("metadata",meta);        if(f.stage().equals("scenery")){long worldPixels=0,depthPixels=0;var raw=java.nio.ByteBuffer.wrap(layers).order(java.nio.ByteOrder.LITTLE_ENDIAN);for(int i=0;i<plane;i+=4)if((layers[plane+i+3]&255)>8){worldPixels++;float depth=raw.getFloat(plane*2+i);if(Float.isFinite(depth)&&depth>0&&depth<1)depthPixels++;}if(worldPixels<1||depthPixels<1)throw new IllegalStateException("Native scenery arrow pixels/depth missing");byte[] worldPng=HudPixels.png(HudPixels.straightTopLeft(Arrays.copyOfRange(layers,plane,plane*2),frame.width(),frame.height()),frame.width(),frame.height());String worldFile="native-combat-scenery-world.png";Files.write(directory.resolve(worldFile),worldPng,StandardOpenOption.CREATE_NEW);p.addProperty("world_file",worldFile);p.addProperty("world_sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(worldPng)));p.addProperty("world_pixels",worldPixels);p.addProperty("world_depth_pixels",depthPixels);}
        images.put(f.stage(),p);
    }}catch(Exception e){if(!closed)failure.compareAndSet(null,e.toString());}}
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private void finish(MinecraftClient c,boolean passed,String why){if(finished)return;finished=true;try{release(c);combat.suspend(c);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;why=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_native_combat_fixture_v1");p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",why);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("scripted_guest_input",true);p.addProperty("synthetic_host",false);p.addProperty("physical_native_keys_verified",false);p.addProperty("position_writes_used",false);p.addProperty("velocity_writes_used",false);p.addProperty("camera_writes_used",false);p.addProperty("direct_health_inventory_entity_writes",false);
        p.addProperty("projectile_check",projectileCheck);p.addProperty("native_projectile_scenery_verified",sceneryVerified);if(sceneryProof!=null)p.add("scenery_proof",sceneryProof);p.addProperty("native_health_damage_verified",nativeHitVerified);p.addProperty("durability_verified",durabilityVerified);p.addProperty("inventory_suppression_verified",inventoryVerified);p.addProperty("native_walking_verified",walkVerified);p.addProperty("render_pixels_verified",renderVerified);p.addProperty("target_token",targetToken);p.addProperty("native_health_before",beforeHealth);p.addProperty("native_health_after",afterHealth);p.addProperty("native_max_health",maximum);p.addProperty("vanilla_damage",actualDamage);p.addProperty("walk_distance",walkDistance);p.addProperty("elapsed_ms",began==0?0:(System.nanoTime()-began)/1_000_000);p.addProperty("stage",stage);p.add("points",points.deepCopy());if(initialCombat!=null)p.add("initial_combat",initialCombat);p.add("combat",combat.evidence(c));
        p.addProperty("inventory_native_eye_horizontal_drift",inventoryNativeHorizontalDrift);p.addProperty("inventory_native_eye_horizontal_limit",.08);p.addProperty("native_composition_window_started_utc_ms",compositionWindowStartUtc);p.addProperty("native_composition_window_completed_utc_ms",compositionWindowEndUtc);
        var a=new JsonArray();commands.forEach(a::add);p.add("commands",a);var captures=new JsonArray();for(var name:CAPTURES)if(images.containsKey(name))captures.add(images.get(name).deepCopy());p.add("images",captures);
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-native-combat-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    @Override public void close(){if(closed)return;closed=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){release(c);combat.suspend(c);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
