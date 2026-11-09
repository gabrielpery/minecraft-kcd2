package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ingame.InventoryScreen;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.GameRules;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Real native attacks only. Reads vanilla health and opens ordinary inventory;
 * never manufactures hurts, changes health, or writes player/NPC positions. */
public final class GameplayIncomingCombatFixture implements AutoCloseable {
    private record State(long at,int tick,UUID player,String mode,float health,boolean regeneration,Vec3d position){}
    private record Frame(String stage,HudReadback.Completed frame){}
    private static final List<String> CAPTURES=List.of("before","inventory","after");
    private final GameplayCombat combat;private final GameplayMovement movement;private final GameplayWorld save;private final Path directory;private final Consumer<JsonObject> completed;
    private final AtomicReference<State> observed=new AtomicReference<>();private final AtomicBoolean observing=new AtomicBoolean();private final AtomicReference<String> failure=new AtomicReference<>();
    private final ArrayBlockingQueue<Frame> frames=new ArrayBlockingQueue<>(3);private final Map<String,JsonObject> images=new ConcurrentHashMap<>();private final Set<String> queued=new HashSet<>();
    private final List<String> commands=new ArrayList<>();private final JsonArray points=new JsonArray();private final long created=System.nanoTime();
    private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;private GameplayAimReader.RenderSample sample;
    private volatile boolean closed,finished;private int stage;private long began,sequence,inventoryOpenedUtc,compositionAt,compositionStartUtc,compositionEndUtc,capturedFrames,compositionFrames,inventoryHeldTicks;
    private float initialHealth,finalHealth;private Vec3d inventoryPosition;private double inventoryDrift;private int positiveDamageReceipts,preInventoryDamageReceipts;private boolean readinessWritten,hitInInventory,nativeRemoved,renderVerified;private JsonObject firstReceipt,inventoryReceipt;

    public GameplayIncomingCombatFixture(GameplayCombat combat,GameplayMovement movement,GameplayWorld save,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayCombat")||!Boolean.getBoolean("minecome.gameplayIncomingCombatCheck"))throw new IllegalArgumentException("Explicit connected incoming combat check required");
        this.combat=Objects.requireNonNull(combat);this.movement=Objects.requireNonNull(movement);this.save=save;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();if(!save.newlyCreated())throw new IOException("Incoming native check requires a fresh owned save");
        for(String name:List.of("gameplay-incoming-combat-fixture.json","incoming-fixture-ready.json","incoming-fixture-remove.json","incoming-fixture-removed.json"))
            if(Files.exists(this.directory.resolve(name),LinkOption.NOFOLLOW_LINKS))throw new IOException("Incoming native fixture output already exists: "+name);
        var writer=new Thread(this::writeLoop,"MineComeIncomingCombatImages");writer.setDaemon(true);writer.start();
    }
    public void tick(MinecraftClient c,boolean armed,GameplayAimReader.RenderSample nativeSample){if(closed||finished)return;try{
        if(failure.get()!=null)throw new IllegalStateException(failure.get());long now=System.nanoTime();
        if(began==0){
            if(now-created>60_000_000_000L)throw new IllegalStateException("Incoming native check never armed");
            if(!armed||!movement.ready()||!combat.ready()||nativeSample==null||!nativeSample.fresh()||nativeSample.schema()!=3)return;
            begin(c);sample=nativeSample;send(c,"difficulty normal");send(c,"gamerule naturalRegeneration false");send(c,"gamemode survival");stage=1;return;
        }
        owner(c);if(!armed)throw new IllegalStateException("Incoming native input authority lost");
        if(now-began>60_000_000_000L)throw new IllegalStateException("Incoming native deadline stage="+stage+" combat="+combat.evidence(c));
        sample=nativeSample;if(sample==null||!sample.fresh()||sample.schema()!=3)return;
        observe();var s=observed.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
        if(!s.player().equals(playerId)||s.health()<=0||!c.player.isAlive())throw new IllegalStateException("Incoming native fixture player died/changed");
        var proof=combat.evidence(c);if(proof.has("failure"))throw new IllegalStateException(proof.get("failure").getAsString());
        var receipts=proof.getAsJsonArray("incoming_receipts");
        switch(stage){
            case 1->{
                if(!s.mode().equals("survival")||c.player.isCreative()||s.regeneration()||!combat.ready()||c.currentScreen!=null||!sameHealth(c,s))return;
                if(receipts.size()!=0||proof.get("hurt_ack").getAsLong()!=0)throw new IllegalStateException("Native attacker ran before readiness");
                if(s.health()!=20)throw new IllegalStateException("Fresh incoming fixture health is not20");initialHealth=s.health();
                if(!images.containsKey("before"))return;point("before",c,s);marker("incoming-fixture-ready.json","minecome_native_incoming_fixture_ready_v1");readinessWritten=true;stage=2;
            }
            case 2->{
                var damage=validateReceipts(receipts);if(damage.isEmpty())return;firstReceipt=damage.getFirst().deepCopy();
                point("first_hit",c,s);inventoryPosition=c.player.getPos();inventoryHeldTicks=movement.evidence(c).get("held_ticks").getAsLong();
                inventoryOpenedUtc=System.currentTimeMillis();key(c,'E');if(!(c.currentScreen instanceof InventoryScreen))throw new IllegalStateException("Vanilla inventory did not open");stage=3;
            }
            case 3->{
                if(!(c.currentScreen instanceof InventoryScreen))throw new IllegalStateException("Inventory closed before second native hit");
                if(c.options.forwardKey.isPressed()||c.options.backKey.isPressed()||c.options.leftKey.isPressed()||c.options.rightKey.isPressed()||c.options.jumpKey.isPressed()||movement.evidence(c).get("held_ticks").getAsLong()!=inventoryHeldTicks)
                    throw new IllegalStateException("Incoming native inventory allowed walking input");
                inventoryDrift=Math.max(inventoryDrift,c.player.getPos().distanceTo(inventoryPosition));
                var damage=validateReceipts(receipts);
                // Delivery can batch attacks already made before E opened the
                // inventory. Keep their real health effects and wait for a new
                // native attack whose original timestamp proves inventory scope.
                if(inventoryReceipt==null)for(var receipt:damage)if(receipt.get("seq").getAsLong()>firstReceipt.get("seq").getAsLong()&&
                        receipt.get("source_utc_ms").getAsLong()>=inventoryOpenedUtc-50&&receipt.get("applied_utc_ms").getAsLong()>=inventoryOpenedUtc){inventoryReceipt=receipt.deepCopy();break;}
                if(positiveDamageReceipts<2||inventoryReceipt==null)return;
                // A further genuine attack may land while the frame is being
                // captured. Require the current real receipt/health agreement,
                // not an artificial two-attack cutoff in the native game.
                if(!sameHealth(c,s)||Math.abs(s.health()-receipts.get(receipts.size()-1).getAsJsonObject().get("health_after").getAsFloat())>.01)return;
                hitInInventory=true;finalHealth=s.health();if(!images.containsKey("inventory"))return;
                point("inventory_hit",c,s);key(c,'E');send(c,"gamemode creative");stage=4;
            }
            case 4->{
                if(!s.mode().equals("creative")||!c.player.isCreative()||c.currentScreen!=null||!sameHealth(c,s))return;finalHealth=s.health();
                marker("incoming-fixture-remove.json","minecome_native_incoming_fixture_remove_v1");stage=5;
            }
            case 5->{
                String text=GameplayCombatSnapshot.read(directory.resolve("incoming-fixture-removed.json"));if(text==null)return;var ack=JsonParser.parseString(text).getAsJsonObject();
                if(!ack.get("world_id").getAsString().equals(save.id().toString())||!ack.get("removed").getAsBoolean())throw new IllegalStateException("Incoming native NPC removal not confirmed");
                if(!combat.knownActors().isEmpty()||proof.get("incoming_pending").getAsInt()!=0)return;
                nativeRemoved=true;compositionAt=now;compositionStartUtc=System.currentTimeMillis();compositionFrames=capturedFrames;stage=6;
            }
            case 6->{
                if(c.currentScreen!=null||!s.mode().equals("creative")||!sameHealth(c,s))return;
                near(s.health(),finalHealth,"Health must stay stable after native attacker removal");
                if(now-compositionAt<11_250_000_000L)return;if(compositionEndUtc==0)compositionEndUtc=System.currentTimeMillis();
                if(!images.containsKey("after"))return;point("after",c,s);renderVerified=images.keySet().containsAll(CAPTURES);finish(c,true,null);
            }
            default->throw new IllegalStateException("Unknown incoming native fixture stage");
        }
    }catch(Exception e){finish(c,false,e.toString());}}
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||c.getServer()==null||!c.isIntegratedServerRunning()||c.currentScreen!=null)throw new IllegalStateException("Owned incoming native client required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);began=System.nanoTime();observe();
    }
    private void owner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Incoming native client owner changed");}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closed||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Incoming native server owner changed");
        observed.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p.interactionManager.getGameMode().getName(),p.getHealth(),server.getGameRules().getBoolean(GameRules.NATURAL_REGENERATION),p.getPos()));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private static boolean sameHealth(MinecraftClient c,State s){return Math.abs(c.player.getHealth()-s.health())<.01;}
    private static void near(double a,double b,String label){if(Math.abs(a-b)>.01)throw new IllegalStateException(label+" differs: "+a+" / "+b);}
    private List<JsonObject> validateReceipts(JsonArray receipts){
        var damage=new ArrayList<JsonObject>();double health=initialHealth;int sequence=0,beforeInventory=0;
        for(var element:receipts){var value=element.getAsJsonObject();double before=value.get("health_before").getAsDouble(),after=value.get("health_after").getAsDouble();String result=value.get("result").getAsString();
            if(value.get("seq").getAsLong()!=++sequence||value.get("attacker_token").getAsInt()!=1||value.get("life").getAsLong()!=0||!Double.isFinite(before)||!Double.isFinite(after)||after<=0||after>before||!Set.of("damaged","absorbed","vanilla_rejected").contains(result))throw new IllegalStateException("Native Survival receipt identity/health differs: "+value);
            near(before,health,"Every native receipt must preserve health continuity");health=after;
            if(after<before){if(!result.equals("damaged")||!value.get("vanilla_accepted").getAsBoolean())throw new IllegalStateException("Native health loss lacks vanilla damage acceptance");damage.add(value);
                if(inventoryOpenedUtc>0&&value.get("source_utc_ms").getAsLong()<inventoryOpenedUtc-50)beforeInventory++;}
            else if(result.equals("damaged"))throw new IllegalStateException("Native damage receipt has no health loss");
        }
        positiveDamageReceipts=damage.size();preInventoryDamageReceipts=beforeInventory;return damage;
    }
    private void send(MinecraftClient c,String command){owner(c);c.getNetworkHandler().sendChatCommand(command);commands.add(command);}
    private void key(MinecraftClient c,int code){combat.suspend(c);movement.suspend(c);ui.apply(c,new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),1,code,0,0,0));ui.apply(c,new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),2,code,0,0,0));}
    private void marker(String name,String kind)throws IOException{var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind",kind);j.addProperty("world_id",save.id().toString());var temporary=directory.resolve(name+".tmp");Files.writeString(temporary,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);Files.move(temporary,directory.resolve(name),StandardCopyOption.ATOMIC_MOVE);}
    private void point(String label,MinecraftClient c,State s){var p=new JsonObject();p.addProperty("stage",label);p.addProperty("utc_ms",System.currentTimeMillis());p.addProperty("server_tick",s.tick());p.addProperty("server_health",s.health());p.addProperty("client_health",c.player.getHealth());p.addProperty("mode",s.mode());p.addProperty("screen",c.currentScreen==null?"none":c.currentScreen.getClass().getSimpleName());p.add("server_position",vector(s.position()));p.add("client_position",vector(c.player.getPos()));points.add(p);}
    public String captureStage(){if(closed||finished||began==0||sample==null||!sample.fresh())return null;var c=MinecraftClient.getInstance();var s=observed.get();String label=switch(stage){case 1->s!=null&&s.mode().equals("survival")&&!s.regeneration()&&sameHealth(c,s)?"before":null;case 3->hitInInventory?"inventory":null;case 6->compositionEndUtc>0?"after":null;default->null;};return label==null||queued.contains(label)||images.containsKey(label)?null:label;}
    public void captured(HudReadback.Completed frame){if(closed||finished)return;capturedFrames++;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("incoming_combat_stage"))return;String label=meta.get("incoming_combat_stage").getAsString();if(!CAPTURES.contains(label)||!queued.add(label))return;if(!frames.offer(new Frame(label,frame)))failure.compareAndSet(null,"Incoming native capture queue full");}
    private void writeLoop(){try{while(!closed){var value=frames.poll(100,TimeUnit.MILLISECONDS);if(value==null)continue;var f=value.frame();var meta=JsonParser.parseString(f.metadata()).getAsJsonObject();
        if(meta.get("frame_format").getAsInt()!=2||!meta.has("world_camera")||meta.get("screen").getAsInt()!=(value.stage().equals("inventory")?1:0))throw new IllegalStateException("Incoming native HUD/world frame differs");
        byte[] layers=f.layersBottomUp();HudLayerPixels.require(layers,f.width(),f.height());int plane=HudPixels.byteSize(f.width(),f.height());long pixels=0;for(int i=3;i<plane;i+=4)if((layers[i]&255)>8)pixels++;if(pixels<1000)throw new IllegalStateException("Incoming native HUD pixels missing");
        byte[] png=HudPixels.png(HudPixels.straightTopLeft(Arrays.copyOfRange(layers,0,plane),f.width(),f.height()),f.width(),f.height());String name="incoming-combat-"+value.stage()+".png";Files.write(directory.resolve(name),png,StandardOpenOption.CREATE_NEW);
        var image=new JsonObject();image.addProperty("stage",value.stage());image.addProperty("file",name);image.addProperty("sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));image.addProperty("hud_pixels",pixels);image.add("metadata",meta);images.put(value.stage(),image);
    }}catch(Exception e){if(!closed)failure.compareAndSet(null,e.toString());}}
    private void finish(MinecraftClient c,boolean passed,String why){if(finished)return;finished=true;try{combat.suspend(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;why=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_native_incoming_combat_fixture_v1");p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",why);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("synthetic_host",false);p.addProperty("scripted_guest_input",true);p.addProperty("physical_native_keys_verified",false);p.addProperty("direct_health_inventory_entity_writes",false);p.addProperty("position_writes_used",false);p.addProperty("velocity_writes_used",false);p.addProperty("camera_writes_used",false);p.addProperty("readiness_published",readinessWritten);p.addProperty("two_native_hits_verified",positiveDamageReceipts>=2&&hitInInventory);p.addProperty("native_hit_in_inventory_verified",hitInInventory);p.addProperty("positive_damage_receipts",positiveDamageReceipts);p.addProperty("pre_inventory_damage_receipts",preInventoryDamageReceipts);p.addProperty("inventory_hit_sequence",inventoryReceipt==null?0:inventoryReceipt.get("seq").getAsLong());p.addProperty("inventory_walking_input_absent",hitInInventory);p.addProperty("inventory_position_drift_including_knockback",inventoryDrift);p.addProperty("native_attacker_removed",nativeRemoved);p.addProperty("render_pixels_verified",renderVerified);p.addProperty("initial_health",initialHealth);p.addProperty("final_health",finalHealth);p.addProperty("inventory_opened_utc_ms",inventoryOpenedUtc);p.addProperty("native_composition_window_started_utc_ms",compositionStartUtc);p.addProperty("native_composition_window_completed_utc_ms",compositionEndUtc);p.addProperty("hud_frames_during_dwell",capturedFrames-compositionFrames);p.addProperty("elapsed_ms",began==0?0:(System.nanoTime()-began)/1_000_000L);p.addProperty("stage",stage);p.add("points",points.deepCopy());p.add("combat",combat.evidence(c));if(firstReceipt!=null)p.add("first_receipt",firstReceipt);if(inventoryReceipt!=null)p.add("inventory_receipt",inventoryReceipt);
        var list=new JsonArray();commands.forEach(list::add);p.add("commands",list);var captures=new JsonArray();for(var name:CAPTURES)if(images.containsKey(name))captures.add(images.get(name).deepCopy());p.add("images",captures);
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-incoming-combat-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    @Override public void close(){if(closed)return;closed=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){combat.suspend(c);movement.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
