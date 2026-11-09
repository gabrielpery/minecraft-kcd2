package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.*;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.TntEntity;
import net.minecraft.entity.attribute.EntityAttributes;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.*;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Actual placement/ignition packets, vanilla TNT fuse/explosion/chain and save.
 * The fixture never edits blocks, TNT entities, fuse, velocity or player health.
 * Vanilla commands supply inventory and temporary player-only blast protection;
 * the original knockback-resistance attribute is restored before normal save.
 */
public final class GameplayTntFixture {
    private static final String WITNESS="minecome-tnt-fixture.json";
    private static final List<String> LABELS=List.of("primary","chain","fragile","resistant");
    private static final List<String> PLACEMENT=List.of("chain","fragile","resistant","primary");
    private record Primed(UUID id,UUID owner,int fuse,Vec3d position){}
    private record State(long at,int tick,UUID player,String mode,Vec3d position,int selected,
                         int tnt,int fragile,int obsidian,int flint,int damage,double resistance,
                         Map<String,String> states,List<Primed> primed){}
    private record Sample(String stage,HudReadback.Completed frame){}
    private static final class Fuse {
        final UUID id;final int first,firstTick;int last,lastTick,minimum;
        Fuse(Primed p,int tick){id=p.id();first=last=minimum=p.fuse();firstTick=lastTick=tick;}
    }
    private final String mode;private final boolean nativeMode;
    private final long created=System.nanoTime();private final GameplayBlocks blocks;
    private final GameplayMovement movement;private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;private final Path directory,witness;
    private final Consumer<JsonObject> completed;private final JsonObject expected;
    private final Map<String,BlockPos> positions=new LinkedHashMap<>();
    private final Map<UUID,Fuse> fuses=new LinkedHashMap<>();
    private final AtomicReference<State> observation=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();
    private final ArrayBlockingQueue<Sample> samples=new ArrayBlockingQueue<>(3);
    private final Map<String,JsonObject> images=new ConcurrentHashMap<>();
    private final Set<String> queued=new HashSet<>();private final List<String> commands=new ArrayList<>();
    private MinecraftServer server;private Object world,player;private UUID playerId,tntId,chainId;
    private HudVanillaUiAdapter ui;private GameplayAimReader.RenderSample nativeSample;
    private Vec3d aimTarget,initial;private volatile Vec3d forward=new Vec3d(1,0,0);
    private volatile boolean closing,finished;private boolean terrainTarget;
    private boolean placed,ignited,fuseVerified,chainVerified,fragileDestroyed,resistantPreserved,durable,ledgerRemoved,rendered,resumed;
    private int stage,ticks,placementIndex,postExplosionTick;private long begun,stageAt,events,actionAt,viewWrites,nativeStartedUtc,nativeCompletedUtc;
    private double originalResistance;private boolean protectionCaptured,protectionRestored;
    private boolean protectionRestoreRequested,restoringFailure;private long restoreRequestedAt,restoreDeadline;private String failureToReport;

    public GameplayTntFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
                              HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        nativeMode=mode.equals("tnt-native");
        if(!Set.of("tnt","tnt-resume","tnt-native").contains(mode)||!Boolean.getBoolean("minecome.gameplayWorldBlocks")||
            (nativeMode?Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayTntCheck"):!Boolean.getBoolean("minecome.gameplayStandalone")))
            throw new IllegalArgumentException("Explicit WorldBlocks TNT fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();witness=save.directory().resolve(WITNESS);
        if(!nativeMode&&Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-tnt-fixture.json")))throw new IOException("TNT fixture output exists");
        if(!mode.equals("tnt-resume")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("TNT fixture needs a new owned save");expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)throw new IOException("Missing TNT witness");
            var proof=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(proof.get("schema").getAsInt()!=1||!proof.get("kind").getAsString().equals("minecome_gameplay_tnt_witness_v1")||!proof.get("world_id").getAsString().equals(save.id().toString())||!proof.get("save").getAsString().equals(save.saveName()))throw new IOException("TNT witness identity differs");
            expected=proof.getAsJsonObject("state");var cells=proof.getAsJsonObject("positions");for(String label:LABELS){var v=cells.getAsJsonObject(label);positions.put(label,new BlockPos(v.get("x").getAsInt(),v.get("y").getAsInt(),v.get("z").getAsInt()));}
            tntId=UUID.fromString(proof.get("tnt_id").getAsString());chainId=UUID.fromString(proof.get("chain_tnt_id").getAsString());
        }
        var worker=new Thread(this::writeLoop,"MineComeGameplayTntFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||restoringFailure||begun==0)return;try{owner(c);if(!nativeMode)movement.authority(c,System.nanoTime(),true);refreshAim(c);}catch(Exception e){complete(c,false,e.toString());}}
    public GameplayWorldRenderer.View view(){
        var c=MinecraftClient.getInstance();if(begun==0||closing||finished||c.player!=player)return null;
        var eye=c.player.getEyePos();var target=Vec3d.ofCenter(positions.get("primary"));var f=target.subtract(eye).normalize();var right=f.crossProduct(new Vec3d(0,1,0)).normalize();
        return new GameplayWorldRenderer.View(eye,f,right.crossProduct(f).normalize(),Math.toRadians(70));
    }
    public GameplayBlocks.Aim renderAim(){return null;}
    /** Omit owned block geometry only for the isolated TNT pixel capture. */
    public boolean isolateTntRender(){return !closing&&!finished&&expected==null&&(stage==6||stage==7||stage==8)&&!images.containsKey("primed");}
    public void tick(MinecraftClient c,boolean armed,GameplayAimReader.RenderSample sample){
        if(!nativeMode)throw new IllegalStateException("Native TNT overload used by standalone fixture");if(closing||finished)return;
        if(restoringFailure){finishFailureRestore(c);return;}
        if(begun==0){if(System.nanoTime()-created>90_000_000_000L){complete(c,false,"Native TNT never armed");return;}if(!armed||sample==null||!sample.fresh()||sample.schema()!=3||sample.perspective()!=0)return;}
        else if(!armed){complete(c,false,"Native TNT authority lost");return;}
        nativeSample=sample;if(sample==null||!sample.fresh()||sample.perspective()!=0)return;tick(c);
    }
    public void tick(MinecraftClient c){
        if(closing||finished)return;if(restoringFailure){finishFailureRestore(c);return;}try{
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);owner(c);
            long now=System.nanoTime();if(now-begun>90_000_000_000L||now-stageAt>25_000_000_000L)throw new IllegalStateException("TNT timeout stage="+stage+" placement="+placementIndex+" state="+state(observation.get())+" blocks="+blocks.evidence(c));
            observe();var s=observation.get();if(s==null||now<s.at()||now-s.at()>500_000_000L)return;
            if(!s.player().equals(playerId))throw new IllegalStateException("TNT observed owner differs");ticks++;refreshAim(c);
            if(expected!=null){resume(c,s);return;}observeFuse(s);create(c,s,now);
        }catch(Exception e){complete(c,false,e.toString());}
    }
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.world==null||c.player==null||c.getServer()==null||!c.isIntegratedServerRunning()||!c.options.getPerspective().isFirstPerson())throw new IllegalStateException("Owned first-person integrated client required");
        save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true);initial=c.player.getPos();
        if(positions.isEmpty()){
            if(nativeMode){var f=nativeSample.view().forward();var flat=new Vec3d(f.x,0,f.z);if(flat.lengthSquared()<.1)throw new IllegalStateException("Native TNT view too vertical");forward=flat.normalize();}
            // Leave room for the vanilla priming impulse inside the captured patch.
            // A chain cell centred at 3.5 on the standalone +/-4 patch has only
            // 0.01 m beyond the TNT half-width, so its ordinary motion pauses there.
            var center=initial.add(forward.multiply(1.3));int x=MathHelper.floor(center.x),z=MathHelper.floor(center.z);
            int dx=Math.abs(forward.x)>=Math.abs(forward.z)?(forward.x>=0?1:-1):0;int dz=dx==0?(forward.z>=0?1:-1):0;
            positions.put("primary",ground(x,z));positions.put("chain",ground(x+dx,z+dz));positions.put("fragile",ground(x-dz,z+dx));
            // Keep the surviving block beside the farther TNT cell so it remains
            // in the unchanged native camera's vertical view after the blast.
            positions.put("resistant",nativeMode?ground(x+dx+dz,z+dz-dx):ground(x+dz,z-dx));
            for(var pos:positions.values())if(c.player.getEyePos().distanceTo(Vec3d.ofCenter(pos))>4.5)throw new IllegalStateException("TNT setup outside vanilla reach");
        }
        begun=stageAt=System.nanoTime();
    }
    private BlockPos ground(int x,int z){double cx=x+.5,cz=z+.5;if(!movement.surface().containsFeet(cx,cz,.3))throw new IllegalStateException("TNT target lacks terrain");return BlockPos.ofFloored(cx,movement.surface().heightAt(cx,cz),cz);}
    private void create(MinecraftClient c,State s,long now)throws IOException{
        switch(stage){
            case 0->{
                if(!s.mode().equals("creative")||s.tnt()!=0||s.fragile()!=0||s.obsidian()!=0||s.flint()!=0||!s.primed().isEmpty()||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("Unexpected new TNT world");
                originalResistance=s.resistance();if(!Double.isFinite(originalResistance)||originalResistance<0||originalResistance>1)throw new IllegalStateException("Unknown blast protection baseline");protectionCaptured=true;
                send(c,"gamemode survival");send(c,"item replace entity @s hotbar.0 with minecraft:tnt 2");send(c,"item replace entity @s hotbar.1 with minecraft:white_wool");send(c,"item replace entity @s hotbar.2 with minecraft:obsidian");send(c,"item replace entity @s hotbar.3 with minecraft:flint_and_steel");send(c,"attribute @s minecraft:generic.explosion_knockback_resistance base set 1");next(1,now);
            }
            case 1->{if(!s.mode().equals("survival")||s.tnt()!=2||s.fragile()!=1||s.obsidian()!=1||s.flint()!=1||s.damage()!=0||s.resistance()!=1)return;next(2,now);}
            case 2->{if(placementIndex==PLACEMENT.size()){placed=true;key(c,'4');aimTarget=Vec3d.ofCenter(positions.get("primary"));terrainTarget=false;next(5,now);break;}key(c,'1'+slot(PLACEMENT.get(placementIndex)));next(3,now);}
            case 3->{
                String label=PLACEMENT.get(placementIndex);if(s.selected()!=slot(label)||!c.player.getMainHandStack().isOf(item(label)))return;
                var pos=positions.get(label);terrainTarget=true;aimTarget=new Vec3d(pos.getX()+.5,movement.surface().heightAt(pos.getX()+.5,pos.getZ()+.5),pos.getZ()+.5);refreshAim(c);edge(c,7);edge(c,8);actionAt=now;next(4,now);
            }
            case 4->{
                if(s.at()<=actionAt||blocks.evidence(c).get("pending").getAsBoolean())return;
                String label=PLACEMENT.get(placementIndex);if(!placedState(s.states().get(label),label)||!blocks.ownedBlocks().contains(positions.get(label)))throw new IllegalStateException("TNT setup placement failed: "+label+" "+state(s));
                placementIndex++;next(2,now);
            }
            case 5->{
                if(s.selected()!=3||!c.player.getMainHandStack().isOf(Items.FLINT_AND_STEEL)||s.damage()!=0)return;
                if(s.tnt()!=0||s.fragile()!=0||s.obsidian()!=0||blocks.ownedBlocks().size()!=4)throw new IllegalStateException("Survival TNT setup did not consume stacks");
                refreshAim(c);edge(c,7);edge(c,8);actionAt=now;next(6,now);
            }
            case 6->{
                if(s.at()<=actionAt||s.primed().size()!=1||s.damage()!=1||!s.states().get("primary").equals("minecraft:air"))return;
                var first=s.primed().getFirst();if(!first.owner().equals(playerId))throw new IllegalStateException("TNT ignition lost player attribution");tntId=first.id();ignited=true;durable=true;aimTarget=null;
                send(c,"gamemode creative");next(7,now);
            }
            case 7->{if(!s.mode().equals("creative")||s.resistance()!=1)return;next(8,now);}
            case 8->{
                if(s.position().distanceTo(initial)>.15)throw new IllegalStateException("Fixture blast protection failed to hold player position");
                if(!s.primed().isEmpty()||!destroyed(s)||!blocks.ownedBlocks().equals(Set.of(positions.get("resistant"))))return;
                var t=blocks.evidence(c).getAsJsonObject("tnt");if(t==null||t.get("explosions").getAsInt()<2||t.get("active").getAsInt()!=0)return;
                var first=fuses.get(tntId);if(first==null||first.first<60||first.first>80||first.first-first.minimum<10||chainId==null)throw new IllegalStateException("Missing vanilla fuse or chain observations");
                fuseVerified=true;chainVerified=true;fragileDestroyed=true;resistantPreserved=true;ledgerRemoved=true;validateImage("primed");rendered=true;
                postExplosionTick=s.tick();if(nativeMode)nativeStartedUtc=System.currentTimeMillis();next(9,now);
            }
            case 9->{
                if(!destroyed(s)||!s.primed().isEmpty()||!blocks.ownedBlocks().equals(Set.of(positions.get("resistant"))))throw new IllegalStateException("Exploded TNT reappeared");
                if(s.tick()-postExplosionTick<40||!images.containsKey("after")||nativeMode&&System.currentTimeMillis()-nativeStartedUtc<11250)return;
                validateImage("after");if(nativeMode)nativeCompletedUtc=System.currentTimeMillis();requestProtectionRestore(c);next(10,now);
            }
            case 10->{if(s.resistance()!=originalResistance)return;protectionRestored=true;if(!destroyed(s)||!s.primed().isEmpty())throw new IllegalStateException("Final TNT state differs");if(!nativeMode)writeWitness(s);complete(c,true,null);}
            default->throw new IllegalStateException("Unknown TNT stage");
        }
    }
    private void observeFuse(State s){
        for(var p:s.primed()){
            if(!p.owner().equals(playerId)||p.fuse()<1||p.fuse()>80)throw new IllegalStateException("Unexpected TNT owner/fuse");
            var f=fuses.get(p.id());if(f==null){if(fuses.size()>=2)throw new IllegalStateException("Unexpected extra primed TNT");f=new Fuse(p,s.tick());fuses.put(p.id(),f);
                if(tntId!=null&&!p.id().equals(tntId)){if(p.fuse()>29)throw new IllegalStateException("Chain TNT did not use vanilla shortened fuse");chainId=p.id();}
            }else if(s.tick()>f.lastTick){if(p.fuse()>f.last||f.last-p.fuse()>s.tick()-f.lastTick+1)throw new IllegalStateException("TNT fuse changed outside normal ticks");f.last=p.fuse();f.lastTick=s.tick();f.minimum=Math.min(f.minimum,p.fuse());}
        }
    }
    private void resume(MinecraftClient c,State s){
        if(!destroyed(s)||!s.primed().isEmpty()||!blocks.ownedBlocks().equals(Set.of(positions.get("resistant"))))throw new IllegalStateException("Saved TNT destruction/obsidian state differs");
        var actual=state(s);for(String key:List.of("player_id","mode","tnt_count","fragile_count","obsidian_count","flint_count","flint_damage","blast_resistance","states"))if(!actual.get(key).equals(expected.get(key)))throw new IllegalStateException("Saved TNT state differs: "+key);
        if(!movement.evidence(c).get("resume_position_restored").getAsBoolean()||!images.containsKey("resumed"))return;
        validateImage("resumed");resumed=true;fragileDestroyed=true;resistantPreserved=true;ledgerRemoved=true;rendered=true;protectionRestored=true;complete(c,true,null);
    }
    private boolean destroyed(State s){return s.states().get("primary").equals("minecraft:air")&&s.states().get("chain").equals("minecraft:air")&&s.states().get("fragile").equals("minecraft:air")&&s.states().get("resistant").equals("minecraft:obsidian");}
    private static int slot(String label){return label.equals("fragile")?1:label.equals("resistant")?2:0;}
    private static Item item(String label){return label.equals("fragile")?Items.WHITE_WOOL:label.equals("resistant")?Items.OBSIDIAN:Items.TNT;}
    private static boolean placedState(String name,String label){return label.equals("fragile")?name.equals("minecraft:white_wool"):label.equals("resistant")?name.equals("minecraft:obsidian"):name.startsWith("minecraft:tnt[");}
    private void refreshAim(MinecraftClient c){if(aimTarget==null||c.currentScreen!=null)return;var eye=c.player.getEyePos();var delta=aimTarget.subtract(eye);double range=delta.length();if(range<=0||range>4.5)throw new IllegalStateException("TNT target outside vanilla reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,terrainTarget?range:-1,terrainTarget));}
    private void owner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("TNT fixture owner changed");}
    private static int count(PlayerEntity p,Item item){int n=0;for(int i=0;i<p.getInventory().size();i++){var s=p.getInventory().getStack(i);if(s.isOf(item))n+=s.getCount();}return n;}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{
        if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);var w=server.getOverworld();if(!server.isOnThread()||p==null||p.getWorld()!=w||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("TNT server owner changed");
        var states=new LinkedHashMap<String,String>();positions.forEach((label,pos)->states.put(label,GameplayBlocks.stateName(w.getBlockState(pos))));
        var primed=new ArrayList<Primed>();for(var t:w.getEntitiesByClass(TntEntity.class,new Box(positions.get("primary")).expand(16),e->!e.isRemoved())){var owner=t.getOwner();if(owner==null)throw new IllegalStateException("Unattributed TNT in owned fixture");primed.add(new Primed(t.getUuid(),owner.getUuid(),t.getFuse(),t.getPos()));}primed.sort(Comparator.comparing(e->e.id().toString()));
        int damage=-1;for(int i=0;i<p.getInventory().size();i++)if(p.getInventory().getStack(i).isOf(Items.FLINT_AND_STEEL))damage=p.getInventory().getStack(i).getDamage();
        observation.set(new State(System.nanoTime(),server.getTicks(),p.getUuid(),p.interactionManager.getGameMode().getName(),p.getPos(),p.getInventory().selectedSlot,count(p,Items.TNT),count(p,Items.WHITE_WOOL),count(p,Items.OBSIDIAN),count(p,Items.FLINT_AND_STEEL),damage,p.getAttributeInstance(EntityAttributes.GENERIC_EXPLOSION_KNOCKBACK_RESISTANCE).getBaseValue(),Map.copyOf(states),List.copyOf(primed)));
    }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++events,System.currentTimeMillis(),kind,code,0,0,0);}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private void edge(MinecraftClient c,int kind){blocks.event(c,event(kind,1));}
    private void send(MinecraftClient c,String command){owner(c);c.getNetworkHandler().sendChatCommand(command);commands.add(command);}
    private void next(int value,long now){stage=value;stageAt=now;ticks=0;}
    public String captureStage(){
        if(closing||finished||begun==0||ticks<2||nativeMode&&(nativeSample==null||!nativeSample.fresh()))return null;
        var s=observation.get();String name=expected!=null?"resumed":(stage==7||stage==8)&&s!=null&&!s.primed().isEmpty()&&tntId!=null?"primed":stage==9?"after":null;
        return name==null||queued.contains(name)||images.containsKey(name)?null:name;
    }
    public void captured(HudReadback.Completed frame){
        if(closing||finished)return;var meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();if(!meta.has("tnt_fixture_stage"))return;String name=meta.get("tnt_fixture_stage").getAsString();
        if(!Set.of("primed","after","resumed").contains(name)||name.equals("primed")&&meta.get("tnt_render_count").getAsInt()<1||!queued.add(name))return;
        if(!samples.offer(new Sample(name,frame)))failure.compareAndSet(null,"TNT capture queue full");
    }
    private void validateImage(String name){
        var image=images.get(name);if(image==null)throw new IllegalStateException("Missing TNT image "+name);var meta=image.getAsJsonObject("metadata");
        if(meta.get("frame_format").getAsInt()!=2||!meta.get("screen_kind").getAsString().equals("none")||image.get("hud_pixels").getAsLong()<1000||!meta.has("world_camera"))throw new IllegalStateException("TNT capture format/ownership differs");
        if(name.equals("primed")){
            if(meta.get("tnt_render_count").getAsInt()<1||meta.get("rendered_world_blocks").getAsInt()!=0||meta.get("dropped_item_render_count").getAsInt()!=0||meta.get("projectile_render_count").getAsInt()!=0||meta.get("player_pixels").getAsBoolean()||image.get("world_pixels").getAsLong()<1||image.get("world_with_depth_pixels").getAsLong()<1)throw new IllegalStateException("Isolated real TNT colour/depth pixels missing");
            boolean found=false;for(var entry:meta.getAsJsonArray("tnt")){var t=entry.getAsJsonObject();UUID id=UUID.fromString(t.get("id").getAsString());if(!fuses.containsKey(id)||t.get("fuse").getAsInt()<1||t.get("fuse").getAsInt()>80)throw new IllegalStateException("Rendered TNT not observed on server");if(id.equals(tntId))found=true;}if(!found)throw new IllegalStateException("Primed TNT UUID missing from captured frame");
        }else if(meta.get("tnt_render_count").getAsInt()!=0||meta.get("rendered_world_blocks").getAsInt()!=1||image.get("world_with_depth_pixels").getAsLong()<1)throw new IllegalStateException("Post-explosion render retained TNT or lost resistant block");
    }
    private void writeSample(Sample sample)throws Exception{
        var f=sample.frame();byte[] layers=f.layersBottomUp();HudLayerPixels.require(layers,f.width(),f.height());int plane=HudPixels.byteSize(f.width(),f.height());long hud=0,worldPixels=0,depthPixels=0;var raw=ByteBuffer.wrap(layers).order(ByteOrder.LITTLE_ENDIAN);
        for(int i=0;i<plane;i+=4){if((layers[i+3]&255)>8)hud++;float depth=raw.getFloat(plane*2+i);if(!Float.isFinite(depth)||depth<0||depth>1)throw new IllegalStateException("Invalid TNT world depth");if((layers[plane+i+3]&255)>8){worldPixels++;if(depth>0&&depth<1)depthPixels++;}}
        var p=new JsonObject();p.addProperty("stage",sample.stage());p.addProperty("width",f.width());p.addProperty("height",f.height());p.addProperty("hud_pixels",hud);p.addProperty("world_pixels",worldPixels);p.addProperty("world_with_depth_pixels",depthPixels);
        for(int layer=0;layer<2;layer++){String file="tnt-"+sample.stage()+(layer==1?"-world":"")+".png";byte[] png=HudPixels.png(HudPixels.straightTopLeft(Arrays.copyOfRange(layers,plane*layer,plane*(layer+1)),f.width(),f.height()),f.width(),f.height());Files.write(directory.resolve(file),png,StandardOpenOption.CREATE_NEW);p.addProperty(layer==0?"file":"world_file",file);p.addProperty(layer==0?"sha256":"world_sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));}
        p.add("metadata",JsonParser.parseString(f.metadata()));images.put(sample.stage(),p);
    }
    private static JsonObject vector(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private JsonObject positions(){var j=new JsonObject();positions.forEach((label,pos)->{var p=new JsonObject();p.addProperty("x",pos.getX());p.addProperty("y",pos.getY());p.addProperty("z",pos.getZ());j.add(label,p);});return j;}
    private static JsonObject state(State s){
        var j=new JsonObject();if(s==null)return j;j.addProperty("player_id",s.player().toString());j.addProperty("mode",s.mode());j.addProperty("tnt_count",s.tnt());j.addProperty("fragile_count",s.fragile());j.addProperty("obsidian_count",s.obsidian());j.addProperty("flint_count",s.flint());j.addProperty("flint_damage",s.damage());j.addProperty("blast_resistance",s.resistance());j.addProperty("primed_count",s.primed().size());j.addProperty("server_tick",s.tick());j.add("position",vector(s.position()));var cells=new JsonObject();s.states().forEach(cells::addProperty);j.add("states",cells);return j;
    }
    private void writeWitness(State s)throws IOException{var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_tnt_witness_v1");p.addProperty("world_id",save.id().toString());p.addProperty("save",save.saveName());p.addProperty("tnt_id",tntId.toString());p.addProperty("chain_tnt_id",chainId.toString());p.add("state",state(s));p.add("positions",positions());save.verifyOwnership();Files.writeString(witness,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}
    private boolean sameOwner(MinecraftClient c){return c.isOnThread()&&c.player==player&&c.world==world&&c.getServer()==server&&c.isIntegratedServerRunning()&&c.getNetworkHandler()!=null;}
    private boolean requestProtectionRestore(MinecraftClient c){
        if(!protectionCaptured||protectionRestored||!sameOwner(c))return false;
        if(!protectionRestoreRequested){send(c,"attribute @s minecraft:generic.explosion_knockback_resistance base set "+Double.toString(originalResistance));protectionRestoreRequested=true;restoreRequestedAt=System.nanoTime();}
        return true;
    }
    private void finishFailureRestore(MinecraftClient c){
        long now=System.nanoTime();if(sameOwner(c)){observe();var s=observation.get();if(s!=null&&s.at()>restoreRequestedAt&&s.player().equals(playerId)&&s.resistance()==originalResistance)protectionRestored=true;}
        if(protectionRestored||!sameOwner(c)||now>=restoreDeadline)complete(c,false,failureToReport);
    }
    private void complete(MinecraftClient c,boolean passed,String error){
        if(finished)return;
        if(!passed&&!restoringFailure)try{if(requestProtectionRestore(c)){failureToReport=error;restoringFailure=true;restoreDeadline=System.nanoTime()+2_000_000_000L;movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);return;}}catch(Exception ignored){}
        finished=true;try{movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("kind","minecome_gameplay_tnt_fixture_v1");p.addProperty("mode",mode);p.addProperty("result",passed?"passed":"failed");p.addProperty("failure",error);p.addProperty("world_id",save.id().toString());p.addProperty("actual_minecraft",true);p.addProperty("standalone_scripted",!nativeMode);p.addProperty("native_input_verified",false);p.addProperty("live_kcd_verified",false);p.addProperty("live_kcd_connected",nativeMode);p.addProperty("scripted_aiming",true);p.addProperty("scripted_mouse_input",true);p.addProperty("native_camera_preserved",nativeMode);p.addProperty("direct_world_inventory_entity_writes",false);p.addProperty("position_writes_used",false);p.addProperty("fuse_writes_used",false);p.addProperty("fixture_player_protection_commands",protectionCaptured);p.addProperty("protection_restored",protectionRestored);
        p.addProperty("protection_restore_requested",protectionRestoreRequested);p.addProperty("tnt_placement_verified",placed);p.addProperty("ignition_verified",ignited);p.addProperty("fuse_verified",fuseVerified);p.addProperty("chain_reaction_verified",chainVerified);p.addProperty("fragile_destruction_verified",fragileDestroyed);p.addProperty("resistant_preservation_verified",resistantPreserved);p.addProperty("tool_durability_verified",durable);p.addProperty("ledger_removal_verified",ledgerRemoved);p.addProperty("render_pixels_verified",rendered);p.addProperty("resume_verified",resumed);p.addProperty("scripted_view_writes",viewWrites);p.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);p.addProperty("last_stage",stage);p.addProperty("placement_count",placementIndex);p.addProperty("native_tnt_started_utc_ms",nativeStartedUtc);p.addProperty("native_tnt_completed_utc_ms",nativeCompletedUtc);p.addProperty("tnt_id",tntId==null?null:tntId.toString());p.addProperty("chain_tnt_id",chainId==null?null:chainId.toString());
        var seen=new JsonArray();for(var f:fuses.values()){var v=new JsonObject();v.addProperty("id",f.id.toString());v.addProperty("first_fuse",f.first);v.addProperty("minimum_fuse",f.minimum);v.addProperty("first_tick",f.firstTick);v.addProperty("last_tick",f.lastTick);seen.add(v);}p.add("observed_tnt",seen);var a=new JsonArray();commands.forEach(a::add);p.add("commands",a);a=new JsonArray();for(String label:List.of("primed","after","resumed"))if(images.containsKey(label))a.add(images.get(label).deepCopy());p.add("images",a);p.add("positions",positions());p.add("final_state",state(observation.get()));p.add("blocks",blocks.evidence(c));p.add("movement",movement.evidence(c));
        try{save.verifyOwnership();Files.writeString(directory.resolve("gameplay-tnt-fixture.json"),p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}catch(Exception e){p.addProperty("result","failed");p.addProperty("failure",e.toString());}completed.accept(p);
    }
    private void writeLoop(){long seq=0;try{while(!closing){var sample=samples.poll();if(sample!=null)writeSample(sample);if(nativeMode){Thread.sleep(25);continue;}
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("source_kind","standalone_hud_physical_view_fixture");p.addProperty("run",identity.run());p.addProperty("patch_run",movement.surface().run());p.addProperty("patch_sha256",movement.surface().sha256());p.addProperty("target_pid",identity.targetPid());p.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));p.addProperty("seq",++seq);p.addProperty("utc_ms",System.currentTimeMillis());var f=forward;p.add("forward",vector(new Vec3d(f.x,-f.z,0)));p.add("up",vector(new Vec3d(0,0,1)));Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,p.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
    }}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;var c=MinecraftClient.getInstance();try{requestProtectionRestore(c);}catch(Exception ignored){}closing=true;if(c.isOnThread()&&c.player==player){movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
