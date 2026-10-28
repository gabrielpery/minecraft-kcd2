package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.terrain.*;
import net.minecraft.client.MinecraftClient;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.Vec3d;
import java.io.IOException;
import java.nio.file.*;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

/** Scripted game-thread edges through the actual movement controller; never physical-input proof. */
final class HudPhysicalMovementFixture implements AutoCloseable {
    private record Observation(Vec3d position,long at){}
    private final HudPhysicalMovement movement;
    private final HudVanillaUiAdapter ui;
    private final MinecraftServer server;
    private final UUID player;
    private final AtomicReference<Observation> observed=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final Thread camera;
    private final JsonArray pulses=new JsonArray();
    private final int[] codes;
    private final boolean extended;
    private volatile boolean closing,cameraStopped;
    private volatile long views;
    private long at,started,firstMovementAt,sequence,inventoryFrames,walkingFrames,closingAt,postWalkInventoryFrames;
    private int stage,pulse;
    private Vec3d origin,serverOrigin,previous,serverPrevious,postWalkOrigin,postWalkServerOrigin;
    private double inventoryClientMax,inventoryServerMax,postWalkInventoryClientMax,postWalkInventoryServerMax;
    private boolean finished,postWalkInventoryOpened,postWalkInventoryClosed;

    HudPhysicalMovementFixture(MinecraftClient client,HudPhysicalMovement movement,Path patchFile,
                               Path viewFile,HudInputProtocol.Identity identity)throws IOException{
        if(!HudPhysicalMovementMode.fixture(System.getProperties()) || Boolean.getBoolean("minecome.hudStreamInput"))
            throw new IllegalArgumentException("Scripted physical controller fixture requires its separate standalone mode");
        this.movement=movement;extended=movement.session().extended();codes=extended?new int[]{0x57,0x57,0x53,0x57,0x53}:new int[]{0x57,0x57,0x53};
        ui=new HudVanillaUiAdapter(client,false);server=client.getServer();player=client.player.getUuid();
        var patch=GroundPatch.read(patchFile);
        if(!patch.sourceKind().equals("standalone_ground_fixture"))throw new IOException("Fixture patch provenance differs");
        double yaw=Double.parseDouble(System.getProperty("minecome.hudPhysicalFixtureYaw","0"));
        if(!Double.isFinite(yaw) || yaw < -180 || yaw > 180)throw new IllegalArgumentException("Fixture yaw outside finite180 degrees");
        Path parent=viewFile.toAbsolutePath().normalize().getParent().toRealPath();
        Path evidence=client.runDirectory.toPath().toAbsolutePath().normalize().getParent().getParent().resolve("runtime/evidence").toRealPath();
        if(!viewFile.isAbsolute() || !parent.startsWith(evidence) || Files.exists(viewFile,LinkOption.NOFOLLOW_LINKS))
            throw new IOException("Fixture camera requires a fresh owned evidence file");
        camera=new Thread(()->publishViews(viewFile,identity,patch,yaw),"MineComeScriptedPhysicalCamera");camera.setDaemon(true);camera.start();
    }
    void observe(MinecraftServer source){
        if(source!=server || closing)return;
        var entity=source.getPlayerManager().getPlayer(player);
        if(entity!=null)observed.set(new Observation(entity.getPos(),System.nanoTime()));
    }
    String phase(){return switch(stage){case 0->"settling";case 1->"inventory_blocked";case 2->"hotbar_ready";case 3,4->"scripted_walking";case 5->"final_settling";case 7->"extended_wait";case 8->"post_walk_inventory_blocked";default->"cleanup";};}
    void captured(String phase){if(phase.equals("inventory_blocked"))inventoryFrames++;if(phase.equals("scripted_walking"))walkingFrames++;if(phase.equals("post_walk_inventory_blocked"))postWalkInventoryFrames++;}
    boolean finished(){return finished;}
    boolean inventoryCaptured(){return inventoryFrames>=2;}
    private Observation observation(long now){
        var value=observed.get();
        now=System.nanoTime(); // A new server sample may post after the outer tick captured its timestamp.
        if(value==null || now<value.at() || now-value.at()>250_000_000L)throw new IllegalStateException("Fixture server observation stale");
        return value;
    }
    void tick(MinecraftClient client,long now)throws IOException{
        if(failure.get()!=null)throw new IOException(failure.get());
        if(!client.isOnThread() || client.getServer()!=server || client.player==null || !client.player.getUuid().equals(player))
            throw new IllegalStateException("Fixture game-thread/world identity changed");
        if(stage==0){
            if(!movement.inputReady(now))return;
            origin=client.player.getPos();serverOrigin=observation(now).position();previous=origin;serverPrevious=serverOrigin;started=now;
            movement.activate(now);
            movement.suspend(client);key(client,0x45,true,now);key(client,0x45,false,now);
            if(!HudVanillaUiAdapter.inventory(client.currentScreen))throw new IllegalStateException("Fixture Creative inventory did not open");
            movement.authority(client,now,true);key(client,0x57,true,now);stage=1;at=now;return;
        }
        if(now-started>(extended?24_000_000_000L:12_000_000_000L))throw new IllegalStateException("Scripted physical fixture session deadline");
        if(stage==1){
            movement.authority(client,now,true);
            inventoryClientMax=Math.max(inventoryClientMax,client.player.getPos().distanceTo(origin));
            inventoryServerMax=Math.max(inventoryServerMax,observation(now).position().distanceTo(serverOrigin));
            if(inventoryClientMax>.01 || inventoryServerMax>.01 || client.options.forwardKey.isPressed())
                throw new IllegalStateException("Scripted W moved client/server while actual Creative inventory was open");
            if(now-at<800_000_000L)return;
            key(client,0x57,false,now);key(client,0x1b,true,now);key(client,0x1b,false,now);
            if(client.currentScreen!=null)throw new IllegalStateException("Fixture inventory did not close");
            stage=2;at=now;return;
        }
        if(stage==2){
            movement.authority(client,now,true);
            if(now-at<300_000_000L)return;
            key(client,codes[pulse],true,now);if(firstMovementAt==0)firstMovementAt=now;stage=3;at=now;return;
        }
        if(stage==3){
            movement.authority(client,now,true);
            if(now-at<150_000_000L)return;
            key(client,codes[pulse],false,now);stage=4;at=now;return;
        }
        if(stage==4){
            movement.authority(client,now,true);
            if(now-at<500_000_000L)return;
            Vec3d position=client.player.getPos(),serverPosition=observation(now).position();
            double step=Math.hypot(position.x-previous.x,position.z-previous.z);
            double serverStep=Math.hypot(serverPosition.x-serverPrevious.x,serverPosition.z-serverPrevious.z);
            if(step<.05 || serverStep<.05 || position.distanceTo(serverPosition)>.1)throw new IllegalStateException("Scripted pulse"+(pulse+1)+" lacks matching client/server movement after fresh release/down");
            var proof=new JsonObject();proof.addProperty("key",codes[pulse]==0x57?"W":"S");proof.addProperty("step_m",step);proof.addProperty("server_step_m",serverStep);
            if(extended)proof.addProperty("elapsed_from_first_movement_ms",(now-firstMovementAt)/1_000_000);
            proof.addProperty("client_x",position.x);proof.addProperty("client_y",position.y);proof.addProperty("client_z",position.z);
            proof.addProperty("server_x",serverPosition.x);proof.addProperty("server_y",serverPosition.y);proof.addProperty("server_z",serverPosition.z);
            proof.addProperty("client_server_distance",position.distanceTo(serverPosition));pulses.add(proof);previous=position;serverPrevious=serverPosition;
            ++pulse;
            if(extended && pulse==3){stage=7;return;}
            if(pulse<codes.length){key(client,codes[pulse],true,now);stage=3;at=now;return;}
            stage=5;return;
        }
        if(stage==7){
            movement.authority(client,now,true);
            if(now-firstMovementAt<6_000_000_000L)return;
            postWalkOrigin=client.player.getPos();postWalkServerOrigin=observation(now).position();
            movement.suspend(client);key(client,0x45,true,now);key(client,0x45,false,now);
            if(!HudVanillaUiAdapter.inventory(client.currentScreen))throw new IllegalStateException("Extended fixture inventory did not reopen after walking");
            postWalkInventoryOpened=true;movement.authority(client,now,true);key(client,0x57,true,now);stage=8;at=now;return;
        }
        if(stage==8){
            movement.authority(client,now,true);
            postWalkInventoryClientMax=Math.max(postWalkInventoryClientMax,client.player.getPos().distanceTo(postWalkOrigin));
            postWalkInventoryServerMax=Math.max(postWalkInventoryServerMax,observation(now).position().distanceTo(postWalkServerOrigin));
            if(postWalkInventoryClientMax>.01 || postWalkInventoryServerMax>.01 || client.options.forwardKey.isPressed())
                throw new IllegalStateException("Extended fixture moved while post-walk inventory was open");
            if(now-at<800_000_000L)return;
            key(client,0x57,false,now);key(client,0x1b,true,now);key(client,0x1b,false,now);
            if(client.currentScreen!=null)throw new IllegalStateException("Extended fixture post-walk inventory did not close");
            postWalkInventoryClosed=true;stage=2;at=now;return;
        }
        if(stage==5){
            movement.authority(client,now,true);
            if(!movement.completed())return;
            if(inventoryFrames<2 || walkingFrames<2)throw new IllegalStateException("Fixture lacks captured inventory/walking HUD frames");
            if(extended && (!postWalkInventoryOpened || !postWalkInventoryClosed || postWalkInventoryFrames<2))
                throw new IllegalStateException("Extended fixture lacks post-walk inventory capture proof");
            movement.close(client);ui.releaseAndClose(client);close();stage=6;closingAt=now;return;
        }
        if(stage==6){
            if(!movement.cleanupComplete() || !cameraStopped){if(now-closingAt>1_500_000_000L)throw new IllegalStateException("Fixture cleanup1.5s deadline");return;}
            finished=true;
        }
    }
    private void key(MinecraftClient client,int code,boolean down,long now)throws IOException{
        var event=new HudInputProtocol.Event(++sequence,System.currentTimeMillis(),down?1:2,code,0,0,0);
        HudInputProtocol.validateEvent(event,System.currentTimeMillis(),true,true);
        if(HudMovementKeys.movement(code))movement.event(client,event,now);
        else{if(down)movement.suspend(client);ui.apply(client,event);}
    }
    JsonObject evidence(MinecraftClient client){
        var e=new JsonObject();e.addProperty("kind","standalone_hud_physical_controller_fixture_v1");e.addProperty("scripted_input",true);
        if(extended){
            e.addProperty("movement_session","extended");e.addProperty("post_walk_inventory_opened",postWalkInventoryOpened);e.addProperty("post_walk_inventory_closed",postWalkInventoryClosed);
            e.addProperty("post_walk_inventory_frames",postWalkInventoryFrames);e.addProperty("post_walk_inventory_client_max_displacement",postWalkInventoryClientMax);
            e.addProperty("post_walk_inventory_server_max_displacement",postWalkInventoryServerMax);
        }
        e.addProperty("physical_input_verified",false);e.addProperty("kcd_compositing_verified",false);e.addProperty("completed",finished);
        e.addProperty("inventory_client_max_displacement",inventoryClientMax);e.addProperty("inventory_server_max_displacement",inventoryServerMax);
        e.addProperty("inventory_frames",inventoryFrames);e.addProperty("walking_hud_frames",walkingFrames);e.addProperty("synthetic_camera_samples",views);
        e.addProperty("camera_worker_stopped",cameraStopped);e.add("pulses",pulses.deepCopy());e.add("physical_movement",movement.evidence(client));return e;
    }
    private void publishViews(Path path,HudInputProtocol.Identity identity,GroundPatch patch,double yaw){
        Path temp=path.resolveSibling(path.getFileName()+".fixture.tmp");long deadline=System.nanoTime()+30_000_000_000L;
        try{
            while(!closing && System.nanoTime()<deadline){
                var v=new JsonObject();v.addProperty("schema",1);v.addProperty("source_kind","standalone_hud_physical_view_fixture");
                v.addProperty("run",identity.run());v.addProperty("patch_run",patch.run());v.addProperty("patch_sha256",patch.sha256());
                v.addProperty("target_pid",identity.targetPid());v.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));
                v.addProperty("seq",++views);v.addProperty("utc_ms",System.currentTimeMillis());
                var forward=new JsonObject();forward.addProperty("x",-Math.sin(Math.toRadians(yaw)));forward.addProperty("y",-Math.cos(Math.toRadians(yaw)));forward.addProperty("z",0);
                var up=new JsonObject();up.addProperty("x",0);up.addProperty("y",0);up.addProperty("z",1);v.add("forward",forward);v.add("up",up);
                Files.writeString(temp,v.toString(),StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
                HudFixtureCameraFiles.replace(temp,path);Thread.sleep(50);
            }
            if(!closing)failure.compareAndSet(null,"Fixture camera30s deadline");
        }catch(InterruptedException e){if(!closing){Thread.currentThread().interrupt();failure.compareAndSet(null,"Fixture camera interrupted");}}
        catch(Exception e){failure.compareAndSet(null,"Fixture camera: "+e);}
        finally{try{Files.deleteIfExists(temp);}catch(IOException e){failure.compareAndSet(null,e.toString());}cameraStopped=true;}
    }
    @Override public void close(){closing=true;camera.interrupt();}
}
