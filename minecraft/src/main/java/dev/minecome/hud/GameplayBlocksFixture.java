package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.item.Items;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Scripted standalone inputs through the gameplay controller, checked against both actual worlds. */
public final class GameplayBlocksFixture {
    private static final String WITNESS="minecome-blocks-fixture.json";
    private record State(long at,Vec3d position,int base,int upper,int side,int stoneCount,String player,boolean creative,boolean pickaxeSelected){}
    private final String mode;
    private final GameplayBlocks blocks;
    private final GameplayMovement movement;
    private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;
    private final Path directory,witness;
    private final Consumer<JsonObject> completed;
    private final JsonObject expected;
    private final AtomicReference<State> observed=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>(),pendingWitness=new AtomicReference<>();
    private final AtomicBoolean observing=new AtomicBoolean();
    private volatile boolean closing,written;
    private volatile long viewWrites;
    private MinecraftServer server;
    private Object world,player;
    private UUID playerId;
    private HudVanillaUiAdapter ui;
    private BlockPos base,upper,side;
    private Vec3d target,initial,inventoryStart,beforeLate;
    private boolean terrainTarget,finished,sent,groundVerified,topVerified,sideVerified,upperBroken,sideBroken,resumeVerified;
    private boolean earlyWalking,inventoryVerified,lateWalking;
    private boolean survivalPlacementVerified,earlyReleaseVerified,survivalMiningVerified;
    private int stage,action,key,inventoryTicks;
    private long begun,stageAt,actionAt,events,firstPreservedTick;
    private JsonObject result;

    public GameplayBlocksFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
                                 HudInputProtocol.Identity identity,Path evidenceDirectory,Consumer<JsonObject> completed)throws IOException {
        if(!Set.of("blocks","blocks-resume","blocks-survival").contains(mode)||!Boolean.getBoolean("minecome.gameplayStandalone"))
            throw new IllegalArgumentException("Explicit standalone blocks fixture required");
        this.mode=mode;this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.completed=completed;
        save.verifyOwnership();directory=evidenceDirectory.toRealPath();witness=save.directory().resolve(WITNESS);
        if(Files.exists(directory.resolve("host-view.json"))||Files.exists(directory.resolve("gameplay-blocks-fixture.json")))
            throw new IOException("Blocks fixture output already exists");
        if(!mode.equals("blocks-resume")){
            if(!save.newlyCreated()||Files.exists(witness,LinkOption.NOFOLLOW_LINKS))throw new IOException("First blocks fixture needs a new owned save");
            expected=null;
        }else{
            if(save.newlyCreated()||Files.isSymbolicLink(witness)||!Files.isRegularFile(witness,LinkOption.NOFOLLOW_LINKS)||Files.size(witness)>16384)
                throw new IOException("Blocks resume requires its saved witness");
            expected=JsonParser.parseString(Files.readString(witness,StandardCharsets.UTF_8)).getAsJsonObject();
            if(expected.get("schema").getAsInt()!=1||!expected.get("kind").getAsString().equals("minecome_gameplay_blocks_witness_v1")||
                !expected.get("world_id").getAsString().equals(save.id().toString()))throw new IOException("Blocks witness belongs to another save");
        }
        Thread worker=new Thread(this::writeLoop,"MineComeGameplayBlocksFixture");worker.setDaemon(true);worker.start();
    }

    public void beforeTick(MinecraftClient client){
        if(closing||finished||begun==0||result!=null)return;
        try{requireOwner(client);movement.authority(client,System.nanoTime(),true);refreshAim(client);}
        catch(Exception e){complete(client,false,e.toString());}
    }
    public void tick(MinecraftClient client){
        if(closing||finished)return;
        try{
            if(result!=null){
                movement.suspend(client);blocks.suspend(client);
                if(written||failure.get()!=null){if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}finished=true;completed.accept(result.deepCopy());}
                return;
            }
            if(failure.get()!=null)throw new IllegalStateException(failure.get());
            if(!movement.ready()||!blocks.ready())return;
            if(begun==0)begin(client);
            requireOwner(client);long now=System.nanoTime();
            if(now-begun>25_000_000_000L)throw new IllegalStateException("Blocks fixture timed out: stage="+stage+", action="+action+", controller="+blocks.evidence(client));
            observe();State state=observed.get();if(state==null||now-state.at()>500_000_000L)return;
            if(!state.player().equals(playerId.toString()))throw new IllegalStateException("Fixture server player changed");
            if(initial==null)initial=state.position();
            refreshAim(client);
            if(mode.equals("blocks-survival")){survival(client,state,now);return;}
            if(expected!=null){resume(client,state,now);return;}
            create(client,state,now);
        }catch(Exception e){complete(client,false,e.toString());}
    }
    private void begin(MinecraftClient client)throws IOException{
        if(!client.isOnThread()||client.player==null||client.world==null||client.getServer()==null||!client.isIntegratedServerRunning())
            throw new IllegalStateException("Blocks fixture requires its integrated client");
        save.verifyOwnership();world=client.world;player=client.player;server=client.getServer();playerId=client.player.getUuid();ui=new HudVanillaUiAdapter(client,true);
        if(!movement.surface().containsFeet(2.5,.5,.3))throw new IllegalStateException("Blocks fixture needs wide terrain");
        base=expected==null?BlockPos.ofFloored(2.5,movement.surface().heightAt(2.5,.5),.5):position(expected.getAsJsonObject("base"));
        upper=base.up();side=base.west();begun=stageAt=System.nanoTime();
        if(expected==null){
            if(!client.player.isCreative()||client.player.getInventory().getStack(0).getCount()!=0)throw new IllegalStateException("New fixture state was not empty Creative");
            // Same vanilla command packet entry used by the persistence fixture.
            client.getNetworkHandler().sendChatCommand("give @s minecraft:stone 64");
            if(mode.equals("blocks-survival")){
                client.getNetworkHandler().sendChatCommand("give @s minecraft:iron_pickaxe 1");
                client.getNetworkHandler().sendChatCommand("gamemode survival");
            }
        }
    }
    private void survival(MinecraftClient c,State s,long now){
        var proof=blocks.evidence(c);
        if(stage>0&&(s.creative()||c.player.isCreative()))throw new IllegalStateException("Mining fixture left actual Survival mode");
        switch(stage){
            case 0 -> {
                if(s.creative()||c.player.isCreative()||s.stoneCount()!=64||!c.player.getMainHandStack().isOf(Items.STONE)||c.player.getMainHandStack().getCount()!=64||!c.player.getInventory().getStack(1).isOf(Items.IRON_PICKAXE))return;
                if(!matches(c,s,0,0,0)||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("Survival fixture cells already occupied");
                next(now);
            }
            case 1 -> {
                if(!runAction(c,s,now))return;
                if(s.stoneCount()!=63||c.player.getMainHandStack().getCount()!=63)throw new IllegalStateException("Survival placement did not consume one actual stone");
                groundVerified=survivalPlacementVerified=true;sent=false;
                ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),1,'2',0,0,0));
                ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),2,'2',0,0,0));
                target=new Vec3d(base.getX(),base.getY()+.5,base.getZ()+.5);terrainTarget=false;refreshAim(c);next(now);
            }
            case 2 -> {
                if(!s.pickaxeSelected()||!c.player.getMainHandStack().isOf(Items.IRON_PICKAXE))return;
                firstPreservedTick=proof.get("survival_preserved_ticks").getAsLong();worldEdge(c,7,0);actionAt=now;next(now);
            }
            case 3 -> {
                if(!matches(c,s,1,0,0))throw new IllegalStateException("Partial held mining unexpectedly removed stone");
                if(proof.get("survival_preserved_ticks").getAsLong()>=firstPreservedTick+2){worldEdge(c,8,0);next(now);}
                else if(now-actionAt>3_000_000_000L)throw new IllegalStateException("Admitted Survival mining was not preserved across vanilla ticks: "+proof);
            }
            case 4 -> {
                if(!matches(c,s,1,0,0)||!blocks.ownedBlocks().equals(Set.of(base)))throw new IllegalStateException("Released Survival attack removed or lost the stone");
                if(proof.get("pending").getAsBoolean())return;
                if(proof.get("cancellations").getAsLong()<1||!proof.get("controls_released").getAsBoolean())throw new IllegalStateException("Early release did not cancel the admitted attack");
                earlyReleaseVerified=true;worldEdge(c,7,0);actionAt=now;next(now);
            }
            case 5 -> {
                if(s.at()>actionAt&&matches(c,s,0,0,0)&&blocks.ownedBlocks().isEmpty()&&!proof.get("pending").getAsBoolean()){
                    worldEdge(c,8,0);
                    if(proof.get("survival_breaks").getAsLong()!=1||s.stoneCount()!=63||proof.get("survival_preserved_ticks").getAsLong()<=firstPreservedTick+2)
                        throw new IllegalStateException("Held Survival mining lacked actual vanilla completion proof");
                    survivalMiningVerified=true;complete(c,true,null);
                }else if(now-actionAt>6_000_000_000L)throw new IllegalStateException("Held iron-pickaxe attack did not remove actual server stone: "+proof);
            }
            default -> throw new IllegalStateException("Unexpected Survival fixture stage");
        }
    }
    private void create(MinecraftClient c,State s,long now){
        double elapsed=(now-stageAt)/1e9;
        switch(stage){
            case 0 -> {
                if(s.stoneCount()!=64||!c.player.getMainHandStack().isOf(Items.STONE)||c.player.getMainHandStack().getCount()!=64)return;
                if(s.base()!=0||s.upper()!=0||s.side()!=0||!blocks.ownedBlocks().isEmpty())throw new IllegalStateException("Fixture build cells already occupied");
                next(now);
            }
            case 1 -> {
                movement.authority(c,now,true);setKey(c,elapsed<.2?'S':0);
                if(elapsed>=.7){if(initial.distanceTo(s.position())<.15)throw new IllegalStateException("Early actual server walking absent");earlyWalking=true;next(now);}
            }
            case 2 -> {
                if(runAction(c,s,now)){
                    if(action==0)groundVerified=true;if(action==1)topVerified=true;if(action==2)upperBroken=true;if(action==3)sideVerified=true;if(action==4)sideBroken=true;
                    action++;sent=false;actionAt=0;if(action==5)next(now);
                }
            }
            case 3 -> {
                setKey(c,0);movement.suspend(c);blocks.suspend(c);toggleInventory(c);next(now);
            }
            case 4 -> {
                if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Actual inventory failed to open");
                if(elapsed<.3)return;
                if(inventoryStart==null)inventoryStart=s.position();
                movement.authority(c,now,true);setKey(c,elapsed<1.0?'W':0);
                if(!sent){worldEdge(c,7,0);worldEdge(c,8,0);sent=true;}
                inventoryTicks++;
                if(elapsed>=1.3){
                    if(inventoryTicks<5||inventoryStart.distanceTo(s.position())>.025||!matches(c,s,1,0,0))throw new IllegalStateException("Inventory allowed world movement or block breaking");
                    inventoryVerified=true;setKey(c,0);toggleInventory(c);beforeLate=s.position();sent=false;next(now);
                }
            }
            case 5 -> {
                movement.authority(c,now,true);setKey(c,elapsed>=.4&&elapsed<.6?'W':0);
                if(elapsed>=1.1){
                    if(beforeLate.distanceTo(s.position())<.15||!matches(c,s,1,0,0)||!blocks.ownedBlocks().equals(Set.of(base)))throw new IllegalStateException("Later walking or retained base block failed");
                    lateWalking=true;complete(c,true,null);
                }
            }
            default -> throw new IllegalStateException("Unexpected blocks fixture stage");
        }
    }
    private boolean runAction(MinecraftClient c,State s,long now){
        boolean place=action==0||action==1||action==3;
        if(!sent){
            target=switch(action){
                case 0 -> new Vec3d(2.5,movement.surface().heightAt(2.5,.5),.5);
                case 1 -> new Vec3d(base.getX()+.5,base.getY()+1,base.getZ()+.5);
                case 2 -> new Vec3d(upper.getX(),upper.getY()+.5,upper.getZ()+.5);
                case 3 -> new Vec3d(base.getX(),base.getY()+.5,base.getZ()+.5);
                case 4 -> new Vec3d(side.getX(),side.getY()+.5,side.getZ()+.5);
                default -> throw new IllegalStateException("Unexpected block action");};
            terrainTarget=action==0;refreshAim(c);worldEdge(c,7,place?1:0);worldEdge(c,8,place?1:0);actionAt=now;sent=true;return false;
        }
        int desiredUpper=action==1?1:0,desiredSide=action==3?1:0;
        if(s.at()<=actionAt||now-actionAt<200_000_000L||blocks.evidence(c).get("pending").getAsBoolean())return false;
        if(matches(c,s,1,desiredUpper,desiredSide)&&blocks.ownedBlocks().size()==1+desiredUpper+desiredSide)return true;
        if(now-actionAt>3_000_000_000L)throw new IllegalStateException("Actual block action failed: action="+action+", controller="+blocks.evidence(c));
        return false;
    }
    private void resume(MinecraftClient c,State s,long now){
        if(!resumeVerified){
            if(!expected.get("player_id").getAsString().equals(playerId.toString())||!matches(c,s,1,0,0)||!blocks.ownedBlocks().equals(Set.of(base)))
                throw new IllegalStateException("Saved owned base stone did not survive reopen");
            if(!movement.evidence(c).get("resume_position_restored").getAsBoolean()||initial.distanceTo(vector(expected.getAsJsonObject("position")))>.04)
                throw new IllegalStateException("Saved walking position did not resume");
            if(s.stoneCount()!=expected.get("stone_count").getAsInt())throw new IllegalStateException("Saved stone inventory differs");
            resumeVerified=true;target=new Vec3d(base.getX(),base.getY()+.5,base.getZ()+.5);terrainTarget=false;refreshAim(c);
            worldEdge(c,7,0);worldEdge(c,8,0);actionAt=now;return;
        }
        if(now-actionAt>3_000_000_000L)throw new IllegalStateException("Resumed block could not be broken: "+blocks.evidence(c));
        if(s.at()>actionAt&&now-actionAt>=300_000_000L&&matches(c,s,0,0,0)&&blocks.ownedBlocks().isEmpty()&&!blocks.evidence(c).get("pending").getAsBoolean())complete(c,true,null);
    }
    private void next(long now){stage++;stageAt=now;}
    private void refreshAim(MinecraftClient c){
        if(target==null)return;Vec3d eye=c.player.getEyePos(),delta=target.subtract(eye);double distance=delta.length();
        if(distance<=0||distance>4.5)throw new IllegalStateException("Fixture target outside real player reach: "+distance);
        blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,terrainTarget?distance:-1,terrainTarget));
    }
    private void worldEdge(MinecraftClient c,int kind,int button){blocks.event(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),kind,button,0,0,0));}
    private void setKey(MinecraftClient c,int desired){
        if(desired==key)return;long now=System.nanoTime();
        if(key!=0)movement.event(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),2,key,0,0,0),now);
        key=desired;if(key!=0)movement.event(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),1,key,0,0,0),now);
    }
    private void toggleInventory(MinecraftClient c){ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),1,'E',0,0,0));ui.apply(c,new HudInputProtocol.Event(++events,System.currentTimeMillis(),2,'E',0,0,0));}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Blocks fixture owner changed");}
    private void observe(){
        if(!observing.compareAndSet(false,true))return;
        server.execute(()->{try{
            if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);var w=server.getOverworld();
            if(!server.isOnThread()||p==null||p.getWorld()!=w||!server.getSaveProperties().getLevelName().equals(save.saveName()))throw new IllegalStateException("Blocks fixture server owner changed");
            int count=0;for(int i=0;i<p.getInventory().size();i++)if(p.getInventory().getStack(i).isOf(Items.STONE))count+=p.getInventory().getStack(i).getCount();
            observed.set(new State(System.nanoTime(),p.getPos(),state(w.getBlockState(base)),state(w.getBlockState(upper)),state(w.getBlockState(side)),count,p.getUuid().toString(),p.isCreative(),p.getMainHandStack().isOf(Items.IRON_PICKAXE)));
        }catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});
    }
    private boolean matches(MinecraftClient c,State s,int b,int u,int d){return s.base()==b&&s.upper()==u&&s.side()==d&&state(c.world.getBlockState(base))==b&&state(c.world.getBlockState(upper))==u&&state(c.world.getBlockState(side))==d;}
    private static int state(net.minecraft.block.BlockState s){return s.isAir()?0:s.isOf(Blocks.STONE)?1:2;}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private static Vec3d vector(JsonObject j){return new Vec3d(j.get("x").getAsDouble(),j.get("y").getAsDouble(),j.get("z").getAsDouble());}
    private static BlockPos position(JsonObject j){return new BlockPos(j.get("x").getAsInt(),j.get("y").getAsInt(),j.get("z").getAsInt());}
    private void complete(MinecraftClient c,boolean passed,String error){
        if(result!=null||finished)return;
        try{setKey(c,0);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_blocks_fixture_v1");j.addProperty("mode",mode);
        j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);j.addProperty("standalone_scripted",true);j.addProperty("actual_minecraft",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);
        j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);
        j.addProperty("ground_placement_verified",groundVerified);j.addProperty("top_placement_verified",topVerified);j.addProperty("side_placement_verified",sideVerified);j.addProperty("upper_break_verified",upperBroken);j.addProperty("side_break_verified",sideBroken);
        j.addProperty("early_walking_verified",earlyWalking);j.addProperty("inventory_suppression_verified",inventoryVerified);j.addProperty("inventory_ticks",inventoryTicks);j.addProperty("later_walking_verified",lateWalking);j.addProperty("resume_verified",resumeVerified);j.addProperty("scripted_view_writes",viewWrites);
        j.addProperty("survival_placement_verified",survivalPlacementVerified);j.addProperty("early_release_verified",earlyReleaseVerified);j.addProperty("survival_mining_verified",survivalMiningVerified);
        j.add("blocks",blocks.evidence(c));j.add("movement",movement.evidence(c));if(base!=null)j.add("base",json(Vec3d.of(base)));
        State s=observed.get();if(s!=null){j.add("server_position",json(s.position()));j.addProperty("stone_count",s.stoneCount());j.addProperty("server_creative",s.creative());}
        if(passed&&mode.equals("blocks")){var w=new JsonObject();w.addProperty("schema",1);w.addProperty("kind","minecome_gameplay_blocks_witness_v1");w.addProperty("world_id",save.id().toString());w.addProperty("player_id",playerId.toString());w.add("base",json(Vec3d.of(base)));w.add("position",json(s.position()));w.addProperty("stone_count",s.stoneCount());pendingWitness.set(w);}
        result=j;pendingResult.set(j.deepCopy());
    }
    private void writeLoop(){long sequence=0;try{
        while(!closing){
            JsonObject proof=pendingResult.getAndSet(null);if(proof!=null){var w=pendingWitness.getAndSet(null);if(w!=null){save.verifyOwnership();Files.writeString(witness,w.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}Files.writeString(directory.resolve("gameplay-blocks-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}
            var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++sequence);j.addProperty("utc_ms",System.currentTimeMillis());
            j.add("forward",json(new Vec3d(1,0,0)));j.add("up",json(new Vec3d(0,0,1)));
            Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
            if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);
        }
    }catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){setKey(c,0);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
