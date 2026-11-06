package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Real placement followed by ordinary key-driven client/server stepping and fence collision.
 * The standalone fixture never writes positions, velocity or block states directly.
 */
public final class GameplayShapeWalkingFixture {
    private record Placement(BlockPos cell,String item,float yaw){}
    private record State(long at,Vec3d position,Vec3d velocity,float yaw,boolean grounded,boolean flying,
                         String item,int slot,List<String> states,double support){}
    private final GameplayBlocks blocks;private final GameplayMovement movement;private final GameplayWorld save;
    private final HudInputProtocol.Identity identity;private final Path directory;private final Consumer<JsonObject> completed;
    private final AtomicReference<State> observed=new AtomicReference<>();private final AtomicBoolean observing=new AtomicBoolean();
    private final AtomicReference<String> failure=new AtomicReference<>();private final AtomicReference<JsonObject> pendingResult=new AtomicReference<>();
    private final List<Placement> placements=new ArrayList<>();private final List<String> commands=new ArrayList<>();private final List<JsonObject> points=new ArrayList<>();
    private final Set<Integer> held=new HashSet<>();private MinecraftServer server;private Object world,player;private UUID playerId;private HudVanillaUiAdapter ui;
    private long begun,stageAt,actionAt,sequence;private int stage,ticks,index;private double ground;private Vec3d inventoryStart;
    private boolean slabVerified,stairVerified,inventoryVerified,descentVerified,fenceVerified,jumpVerified,finished;
    private double jumpPeak;private JsonObject result;private volatile boolean closing,written;private volatile float yaw=-90;private volatile long viewWrites;

    public GameplayShapeWalkingFixture(String mode,GameplayBlocks blocks,GameplayMovement movement,GameplayWorld save,
            HudInputProtocol.Identity identity,Path directory,Consumer<JsonObject> completed)throws IOException{
        if(!mode.equals("shape-walking")||!Boolean.getBoolean("minecome.gameplayStandalone")||!Boolean.getBoolean("minecome.gameplayWorldBlocks"))throw new IllegalArgumentException("Explicit standalone world-block walking fixture required");
        this.blocks=blocks;this.movement=movement;this.save=save;this.identity=identity;this.directory=directory.toRealPath();this.completed=completed;
        save.verifyOwnership();if(!save.newlyCreated()||Files.exists(this.directory.resolve("host-view.json"))||Files.exists(this.directory.resolve("gameplay-shape-walking-fixture.json")))throw new IOException("New isolated shape-walking fixture required");
        var worker=new Thread(this::writeLoop,"MineComeShapeWalkingFixture");worker.setDaemon(true);worker.start();
    }
    public void beforeTick(MinecraftClient c){if(closing||finished||begun==0||result!=null)return;try{requireOwner(c);movement.authority(c,System.nanoTime(),true);if(stage<=2)refreshPlacementAim(c);}catch(Exception e){complete(c,false,e.toString());}}
    public GameplayWorldRenderer.View view(){var c=MinecraftClient.getInstance();if(begun==0||closing||finished||c.player!=player)return null;var f=new Vec3d(-Math.sin(Math.toRadians(yaw)),0,Math.cos(Math.toRadians(yaw)));return new GameplayWorldRenderer.View(c.player.getEyePos(),f,new Vec3d(0,1,0),Math.toRadians(70));}
    public GameplayBlocks.Aim renderAim(){var v=view();return v==null?null:new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),v.origin(),v.forward(),4.5,true,-1,false);}
    public void tick(MinecraftClient c){if(closing||finished)return;try{
        if(result!=null){movement.suspend(c);blocks.suspend(c);if(written||failure.get()!=null){if(failure.get()!=null){result.addProperty("result","failed");result.addProperty("failure",failure.get());}finished=true;completed.accept(result.deepCopy());}return;}
        if(failure.get()!=null)throw new IllegalStateException(failure.get());if(!movement.ready()||!blocks.ready())return;if(begun==0)begin(c);requireOwner(c);
        long now=System.nanoTime();if(now-begun>65_000_000_000L||now-stageAt>14_000_000_000L)throw new IllegalStateException("Shape walking deadline stage="+stage+" index="+index+" movement="+movement.evidence(c));
        observe();var s=observed.get();if(s==null||now-s.at()>500_000_000L)return;ticks++;
        if(c.player.getAbilities().flying||s.flying()||c.player.isFallFlying())throw new IllegalStateException("Walking unexpectedly enabled flight");
        if(Math.abs(c.player.getZ())>.04||Math.abs(s.position().z)>.04)throw new IllegalStateException("Walking strayed from the controlled two-wide path");
        switch(stage){
            case 0->{prepare(c);next(1,now);}
            case 1->{var p=placements.get(index);if(s.slot()!=0||c.player.getInventory().selectedSlot!=0||!s.item().equals("minecraft:"+p.item())||!Registries.ITEM.getId(c.player.getMainHandStack().getItem()).toString().equals(s.item())||Math.abs(MathHelper.wrapDegrees(s.yaw()-yaw))>.2||Math.abs(MathHelper.wrapDegrees(c.player.getYaw()-yaw))>.2)return;
                refreshPlacementAim(c);blocks.event(c,event(7,1));blocks.event(c,event(8,1));actionAt=now;next(2,now);}
            case 2->{if(s.at()<=actionAt||now-actionAt<300_000_000L||blocks.evidence(c).get("pending").getAsBoolean())return;
                for(int i=0;i<=index;i++){var p=placements.get(i);if(!s.states().get(i).startsWith("minecraft:"+p.item()+"[")||!GameplayBlocks.stateName(c.world.getBlockState(p.cell())).equals(s.states().get(i)))throw new IllegalStateException("Walking fixture placement differs: "+s.states()+" controller="+blocks.evidence(c));}
                if(blocks.ownedBlocks().size()!=index+1)throw new IllegalStateException("Walking fixture ownership differs");index++;if(index<placements.size()){next(0,now);}else{index--;yaw=-90;key(c,'9');next(3,now);}}
            case 3->{if(Math.abs(MathHelper.wrapDegrees(s.yaw()+90))>.2)return;keys(c,c.player.getX()<1.05&&ticks%6==1?new int[]{'W'}:new int[0]);
                if(c.player.getX()>=1.05&&settled(c,s)){requireHeight(c,s,ground+.5,"bottom slab");slabVerified=true;point("standing_on_bottom_slab",c,s);next(4,now);}}
            case 4->{keys(c,c.player.getX()<1.95&&ticks%6==1?new int[]{'W'}:new int[0]);
                if(c.player.getX()>=1.95&&settled(c,s)){requireHeight(c,s,ground+1,"stair tread");stairVerified=true;point("standing_on_stair",c,s);keys(c);movement.suspend(c);key(c,'E');inventoryStart=s.position();next(5,now);}}
            case 5->{if(!HudVanillaUiAdapter.inventory(c.currentScreen))throw new IllegalStateException("Inventory did not open on stair");keys(c,ticks>=5&&ticks<=15?new int[]{'W'}:new int[0]);
                if(ticks>=24){if(inventoryStart.distanceTo(s.position())>.025||inventoryStart.distanceTo(c.player.getPos())>.025)throw new IllegalStateException("Inventory W moved off the stair");inventoryVerified=true;keys(c);key(c,'E');point("inventory_suppressed_on_stair",c,s);next(6,now);}}
            case 6->{keys(c,c.player.getX()>.2&&ticks%6==1?new int[]{'S'}:new int[0]);if(c.player.getX()<=.2&&settled(c,s)){requireHeight(c,s,ground,"ground after descent");descentVerified=true;point("descended_to_ground",c,s);yaw=90;next(7,now);}}
            case 7->{if(Math.abs(MathHelper.wrapDegrees(s.yaw()-90))>.2)return;keys(c,ticks%6==1?new int[]{'W'}:new int[0]);if(ticks>=48){if(c.player.getX()< -1.15||s.position().x< -1.15||c.player.getX()>-1.0||s.position().x>-1.0)throw new IllegalStateException("Fence did not stop normal walking at its actual narrow collision shape");requireHeight(c,s,ground,"fence stop");fenceVerified=true;point("stopped_by_fence",c,s);keys(c);jumpPeak=ground;next(8,now);}}
            case 8->{keys(c,ticks<=2?new int[]{0x20}:ticks<=20?new int[]{'W'}:new int[0]);jumpPeak=Math.max(jumpPeak,Math.min(c.player.getY(),s.position().y));if(c.player.getX()<-1.15||s.position().x<-1.15)throw new IllegalStateException("Ordinary jump crossed the 1.5-block fence");
                if(ticks>=32&&settled(c,s)){if(jumpPeak<ground+.7)throw new IllegalStateException("Fence check did not actually jump");requireHeight(c,s,ground,"fence landing");jumpVerified=true;point("fence_jump_blocked_and_landed",c,s);complete(c,true,null);}}
            default->throw new IllegalStateException("Unknown shape-walking stage");
        }
    }catch(Exception e){complete(c,false,e.toString());}}
    private void begin(MinecraftClient c)throws IOException{
        if(!c.isOnThread()||c.player==null||c.world==null||!c.isIntegratedServerRunning()||c.getServer()==null)throw new IllegalStateException("Owned integrated client required");save.verifyOwnership();world=c.world;player=c.player;server=c.getServer();playerId=c.player.getUuid();ui=new HudVanillaUiAdapter(c,true,true);
        ground=movement.surface().heightAt(0,0);int y=(int)Math.rint(ground);if(Math.abs(ground-y)>1e-8||Math.abs(ground-movement.surface().heightAt(2.5,.5))>1e-8||Math.abs(ground-movement.surface().heightAt(-1.5,-.5))>1e-8)throw new IllegalStateException("Flat integer fixture ground required");
        for(int z:new int[]{-1,0})placements.add(new Placement(new BlockPos(-2,y,z),"oak_fence",90));
        // The stair's high half faces the slab, giving two ordinary 0.5m steps.
        for(int z:new int[]{-1,0})placements.add(new Placement(new BlockPos(2,y,z),"oak_stairs",90));
        for(int z:new int[]{-1,0})placements.add(new Placement(new BlockPos(1,y,z),"oak_slab",-90));
        begun=stageAt=System.nanoTime();
    }
    private void prepare(MinecraftClient c){var p=placements.get(index);yaw=p.yaw();command(c,"item replace entity @s hotbar.0 with minecraft:"+p.item());key(c,'1');}
    private void refreshPlacementAim(MinecraftClient c){if(placements.isEmpty())return;var p=placements.get(index);var eye=c.player.getEyePos();var target=new Vec3d(p.cell().getX()+.5,ground,p.cell().getZ()+.5);var delta=target.subtract(eye);if(delta.length()>4.5)throw new IllegalStateException("Walking fixture placement outside reach");blocks.aim(new GameplayBlocks.Aim(System.currentTimeMillis(),System.nanoTime(),eye,delta.normalize(),4.5,true,delta.length(),true));}
    private static boolean settled(MinecraftClient c,State s){return c.player.isOnGround()&&s.grounded()&&c.player.getVelocity().horizontalLength()<.004&&s.velocity().horizontalLength()<.004&&c.player.getPos().distanceTo(s.position())<.04;}
    private void requireHeight(MinecraftClient c,State s,double y,String name){double support=blocks.groundForFeet(c.world,c.player.getX(),c.player.getY(),c.player.getZ(),.3);if(Math.abs(c.player.getY()-y)>.015||Math.abs(s.position().y-y)>.015||Math.abs(support-y)>.015||Math.abs(s.support()-y)>.015)throw new IllegalStateException(name+" feet/support differ: client="+c.player.getY()+" server="+s.position().y+" support="+support+" server_support="+s.support());}
    private void point(String name,MinecraftClient c,State s){var p=new JsonObject();p.addProperty("stage",name);p.add("client_position",json(c.player.getPos()));p.add("server_position",json(s.position()));p.addProperty("client_grounded",c.player.isOnGround());p.addProperty("server_grounded",s.grounded());p.addProperty("client_support_y",blocks.groundForFeet(c.world,c.player.getX(),c.player.getY(),c.player.getZ(),.3));p.addProperty("server_support_y",s.support());points.add(p);}
    private void observe(){if(!observing.compareAndSet(false,true))return;server.execute(()->{try{if(closing||finished)return;var p=server.getPlayerManager().getPlayer(playerId);if(!server.isOnThread()||p==null||p.getWorld()!=server.getOverworld()||!save.saveName().equals(server.getSaveProperties().getLevelName()))throw new IllegalStateException("Shape walking server owner changed");var states=new ArrayList<String>();for(var placement:placements)states.add(GameplayBlocks.stateName(server.getOverworld().getBlockState(placement.cell())));observed.set(new State(System.nanoTime(),p.getPos(),p.getVelocity(),p.getYaw(),p.isOnGround(),p.getAbilities().flying,Registries.ITEM.getId(p.getMainHandStack().getItem()).toString(),p.getInventory().selectedSlot,List.copyOf(states),blocks.groundForFeet(server.getOverworld(),p.getX(),p.getY(),p.getZ(),.3)));}catch(Exception e){failure.compareAndSet(null,e.toString());}finally{observing.set(false);}});}
    private void requireOwner(MinecraftClient c){if(!c.isOnThread()||c.world!=world||c.player!=player||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Shape walking fixture owner changed");}
    private void next(int value,long now){stage=value;stageAt=now;ticks=0;}
    private void keys(MinecraftClient c,int... values){var desired=new HashSet<Integer>();for(int v:values)desired.add(v);for(int v:new HashSet<>(held))if(!desired.contains(v)){movement.event(c,event(2,v),System.nanoTime());held.remove(v);}for(int v:desired)if(held.add(v))movement.event(c,event(1,v),System.nanoTime());}
    private void key(MinecraftClient c,int code){ui.apply(c,event(1,code));ui.apply(c,event(2,code));}
    private HudInputProtocol.Event event(int kind,int code){return new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),kind,code,0,0,0);}
    private void command(MinecraftClient c,String command){keys(c);movement.suspend(c);key(c,0xbf);if(!HudVanillaUiAdapter.chat(c.currentScreen))throw new IllegalStateException("Shape walking chat absent");command.codePoints().forEach(cp->ui.apply(c,event(9,cp)));if(!ui.chatText(c).equals("/"+command))throw new IllegalStateException("Shape walking chat differs");ui.apply(c,event(10,13));ui.apply(c,event(11,13));if(c.currentScreen!=null)throw new IllegalStateException("Command did not submit");commands.add("/"+command);}
    private void complete(MinecraftClient c,boolean passed,String error){if(result!=null||finished)return;try{keys(c);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}catch(Exception e){passed=false;error=e.toString();}var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_shape_walking_fixture_v1");j.addProperty("mode","shape-walking");j.addProperty("result",passed?"passed":"failed");j.addProperty("failure",error);j.addProperty("world_id",save.id().toString());j.addProperty("player_id",playerId==null?null:playerId.toString());j.addProperty("actual_minecraft",true);j.addProperty("standalone_scripted",true);j.addProperty("native_input_verified",false);j.addProperty("live_kcd_verified",false);j.addProperty("direct_command_api_used",false);j.addProperty("position_writes_used",false);j.addProperty("velocity_writes_used",false);j.addProperty("block_state_writes_used",false);j.addProperty("slab_walking_verified",slabVerified);j.addProperty("stair_walking_verified",stairVerified);j.addProperty("inventory_suppression_verified",inventoryVerified);j.addProperty("descent_verified",descentVerified);j.addProperty("fence_blocking_verified",fenceVerified);j.addProperty("fence_jump_blocked_verified",jumpVerified);j.addProperty("jump_peak_y",jumpPeak);j.addProperty("ground_y",ground);j.addProperty("stage",stage);j.addProperty("elapsed_ms",begun==0?0:(System.nanoTime()-begun)/1_000_000);j.addProperty("scripted_view_writes",viewWrites);var a=new JsonArray();points.forEach(a::add);j.add("positions",a);a=new JsonArray();commands.forEach(a::add);j.add("submitted_commands",a);j.add("movement",movement.evidence(c));j.add("blocks",blocks.evidence(c));result=j;pendingResult.set(j.deepCopy());}
    private static JsonObject json(Vec3d v){var j=new JsonObject();j.addProperty("x",v.x);j.addProperty("y",v.y);j.addProperty("z",v.z);return j;}
    private void writeLoop(){long seq=0;try{while(!closing){var proof=pendingResult.getAndSet(null);if(proof!=null){Files.writeString(directory.resolve("gameplay-shape-walking-fixture.json"),proof.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);written=true;}var j=new JsonObject();j.addProperty("schema",1);j.addProperty("source_kind","standalone_hud_physical_view_fixture");j.addProperty("run",identity.run());j.addProperty("patch_run",movement.surface().run());j.addProperty("patch_sha256",movement.surface().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("seq",++seq);j.addProperty("utc_ms",System.currentTimeMillis());double a=Math.toRadians(yaw);j.add("forward",json(new Vec3d(-Math.sin(a),-Math.cos(a),0)));j.add("up",json(new Vec3d(0,0,1)));Path temp=directory.resolve("host-view-fixture.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);if(HudFixtureCameraFiles.replace(temp,directory.resolve("host-view.json")))viewWrites++;Thread.sleep(25);}}catch(Exception e){failure.compareAndSet(null,e.toString());}}
    public void close(){if(closing)return;closing=true;var c=MinecraftClient.getInstance();if(c.isOnThread()&&c.player==player){keys(c);movement.suspend(c);blocks.suspend(c);if(ui!=null)ui.releaseAndClose(c);}}
}
