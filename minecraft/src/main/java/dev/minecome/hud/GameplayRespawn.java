package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.terrain.GameplayMovement;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.World;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/** Same-world vanilla death replacement, with an independently acknowledged host relocation. */
final class GameplayRespawn implements AutoCloseable {
    private record Transition(java.util.UUID playerId,Vec3d target,long epoch,long at){}
    private record Callback(ServerPlayerEntity oldPlayer,ServerPlayerEntity next,boolean alive){}
    private final GameplayMovement movement; private final GameplayBlocks blocks;
    private final GameplayWorld save; private final HudInputProtocol.Identity identity; private final Path ackFile;
    private volatile Transition transition; private volatile Callback callback; private volatile String failure,ackText; private volatile boolean closed;
    private long reboundEpoch,deathAckEpoch,respawnAckEpoch,callbackWaitAt; private volatile Object ownedClient,ownedWorld,ownedServer;
    GameplayRespawn(GameplayMovement movement,GameplayBlocks blocks,GameplayWorld save,HudInputProtocol.Identity identity,Path directory){
        this.movement=movement;this.blocks=blocks;this.save=save;this.identity=identity;ackFile=directory.resolve("respawn-ack.json");
        if(movement.nativeRespawnRequired()){var worker=new Thread(this::readLoop,"MineComeRespawnAck");worker.setDaemon(true);worker.start();}
    }
    // Fabric AFTER_RESPAWN is invoked on the integrated server thread after vanilla
    // creates the replacement and retains its UUID/network handler. See the pinned
    // PlayerManager and ServerPlayerEvents source in respawn-source-20261108.
    void serverRespawn(ServerPlayerEntity oldPlayer,ServerPlayerEntity next,boolean alive){
        if(callback!=null){failure="Overlapping gameplay respawn callbacks";return;}
        callback=new Callback(oldPlayer,next,alive);
    }
    boolean serverTick(net.minecraft.server.MinecraftServer source){
        var pending=callback;
        if(pending!=null){callback=null;completeServerRespawn(pending.oldPlayer(),pending.next(),pending.alive());}
        return closed||failure==null;
    }
    private void completeServerRespawn(ServerPlayerEntity oldPlayer,ServerPlayerEntity next,boolean alive){
        try{
            if(closed||alive||!movement.ready()||!movement.deathPending()||oldPlayer==next||oldPlayer.isAlive()||!next.isAlive()||
                    oldPlayer.getServer()!=ownedServer||next.getServer()!=ownedServer||!next.getServer().isOnThread()||
                    !oldPlayer.getUuid().equals(next.getUuid())||oldPlayer.networkHandler!=next.networkHandler||
                    oldPlayer.getServerWorld()!=next.getServerWorld()||next.getWorld().getRegistryKey()!=World.OVERWORLD||
                    !next.getServer().getSaveProperties().getLevelName().equals(save.saveName())||transition!=null||
                    next.networkHandler.player!=next||next.getServer().getPlayerManager().getPlayer(next.getUuid())!=next)
                throw new IllegalStateException("Unowned gameplay respawn callback");
            var surface=movement.surface();var spawn=oldPlayer.getSpawnPointPosition();
            // Default flat-world spawn is not captured KCD terrain. Use the captured
            // origin unless vanilla has an explicit Overworld spawn that is admitted.
            if(spawn!=null&&oldPlayer.getSpawnPointDimension()!=World.OVERWORLD)throw new IllegalStateException("Respawn dimension is not captured");
            double x=spawn==null?0:spawn.getX()+.5,z=spawn==null?0:spawn.getZ()+.5;
            double floor=surface.groundForFeet(x,z,.3);
            if(spawn!=null)floor=blocks.groundForFeet(next.getWorld(),x,spawn.getY()+.1,z,.3);
            if(!surface.containsFeet(x,z,.31)||!Double.isFinite(floor)||spawn!=null&&Math.abs(floor-spawn.getY())>1.1)
                throw new IllegalStateException("Respawn point is outside captured support");
            var destination=new Vec3d(x,floor+.05,z);
            var box=next.getBoundingBox().offset(destination.subtract(next.getPos()));
            if(!next.getServerWorld().isSpaceEmpty(next,box))throw new IllegalStateException("Respawn point has blocked headroom");
            next.teleport(next.getServerWorld(),destination.x,destination.y,destination.z,spawn==null?oldPlayer.getYaw():oldPlayer.getSpawnAngle(),0);
            long epoch=movement.respawnEpoch();
            movement.serverRespawn(oldPlayer,next,epoch);blocks.serverRespawn(oldPlayer,next);
            transition=new Transition(next.getUuid(),destination,epoch,System.nanoTime());
        }catch(Exception e){failure=e.toString();}
    }
    /** Runs before movement's identity check and before any replacement receives input. */
    boolean awaitingCallback(MinecraftClient client){
        check();
        if(ownedClient==null||client.player==ownedClient||transition!=null){callbackWaitAt=0;return false;}
        if(!(ownedClient instanceof ClientPlayerEntity old)||old.isAlive()||client.world!=ownedWorld||client.getServer()!=ownedServer||
                !client.player.isAlive()||!client.player.getUuid().equals(old.getUuid()))throw new IllegalStateException("Unowned replacement while waiting for respawn callback");
        if(callbackWaitAt==0)callbackWaitAt=System.nanoTime();
        if(System.nanoTime()-callbackWaitAt>500_000_000L)throw new IllegalStateException("Respawn callback publication deadline");
        return true;
    }
    boolean beforeTick(MinecraftClient client){
        check();if(client.player==null||client.world==null)return false;
        if(ownedClient==null){ownedClient=client.player;ownedWorld=client.world;ownedServer=client.getServer();}
        boolean replaced=false;var step=transition;
        if(client.player!=ownedClient){
            if(step==null||client.world!=ownedWorld||client.getServer()!=ownedServer||!client.player.isAlive()||
                    !client.player.getUuid().equals(step.playerId())||reboundEpoch>=step.epoch())
                throw new IllegalStateException("Unacknowledged gameplay player replacement");
            var old=(ClientPlayerEntity)ownedClient;
            movement.clientRespawn(client,old,step.epoch());blocks.clientRespawn(client,old);
            ownedClient=client.player;reboundEpoch=step.epoch();replaced=true;
        }
        acknowledge();
        if(step!=null){
            if(System.nanoTime()-step.at()>8_000_000_000L)throw new IllegalStateException("Gameplay respawn settlement deadline");
            if(reboundEpoch==step.epoch()&&!movement.respawnPending()){
                // Pinned WorldLoadingState waits for WorldRenderer.isRenderingReady.
                // The persistent HUD deliberately suppresses that terrain renderer.
                // Finish only this same-world transition after both replacements,
                // native relocation, the received destination chunk and pose agree.
                var target=step.target();
                boolean chunk=client.world.getChunkManager().getChunk(net.minecraft.util.math.MathHelper.floor(target.x)>>4,
                        net.minecraft.util.math.MathHelper.floor(target.z)>>4,net.minecraft.world.chunk.ChunkStatus.FULL,false)!=null;
                if(respawnAckEpoch==step.epoch()&&chunk&&client.player.getPos().squaredDistanceTo(target)<.04){
                    if(HudVanillaUiAdapter.transition(client.currentScreen))client.currentScreen.close();
                    if(client.currentScreen==null)transition=null;
                }
            }
        }
        return replaced;
    }
    boolean waiting(){return movement.deathPending()||movement.respawnPending()||transition!=null;}
    private void acknowledge(){
        long epoch=movement.respawnEpoch();if(epoch<=0||respawnAckEpoch==epoch||(!movement.deathPending()&&!movement.respawnPending()))return;
        if(!movement.nativeRespawnRequired()){
            if(deathAckEpoch<epoch){movement.acknowledgeDeath(epoch);deathAckEpoch=epoch;}
            if(reboundEpoch==epoch&&respawnAckEpoch<epoch&&movement.respawnPending()){movement.acknowledgeRespawn(epoch);respawnAckEpoch=epoch;}
            return;
        }
        String text=ackText;if(text==null)return;
        var action=GameplayRespawnAcknowledgement.parse(text,identity,save.id().toString(),movement.surface().run(),movement.surface().sha256(),
                epoch,deathAckEpoch,respawnAckEpoch,point(movement.respawnFromHost()),point(movement.respawnTargetHost()),System.currentTimeMillis());
        if(action==GameplayRespawnAcknowledgement.Action.DEAD){movement.acknowledgeDeath(epoch);deathAckEpoch=epoch;}
        else if(action==GameplayRespawnAcknowledgement.Action.RESPAWN&&reboundEpoch==epoch){movement.acknowledgeRespawn(epoch);respawnAckEpoch=epoch;}
    }
    private static GameplayRespawnAcknowledgement.Point point(Vec3d value){return value==null?null:new GameplayRespawnAcknowledgement.Point(value.x,value.y,value.z);}
    private void readLoop(){
        while(!closed){try{
            if(Files.exists(ackFile,LinkOption.NOFOLLOW_LINKS)){
                var attrs=Files.readAttributes(ackFile,java.nio.file.attribute.BasicFileAttributes.class,LinkOption.NOFOLLOW_LINKS);
                if(!attrs.isRegularFile()||attrs.isSymbolicLink()||attrs.size()>4096)throw new IllegalStateException("Invalid respawn acknowledgment file");
                try(var stream=Files.newInputStream(ackFile)){byte[] bytes=stream.readNBytes(4097);if(bytes.length>4096)throw new IllegalStateException("Oversized respawn acknowledgment");ackText=new String(bytes,StandardCharsets.UTF_8);}
            }
            Thread.sleep(10);
        }catch(java.nio.file.FileSystemException e){/* Atomic Windows replacement can temporarily deny sharing. Deadlines remain unchanged. */}
        catch(Exception e){if(!closed)failure=e.toString();return;}}
    }
    private void check(){if(failure!=null)throw new IllegalStateException(failure);}
    JsonObject evidence(){var j=new JsonObject();j.addProperty("native_required",movement.nativeRespawnRequired());j.addProperty("death_ack_epoch",deathAckEpoch);j.addProperty("respawn_ack_epoch",respawnAckEpoch);j.addProperty("client_rebound_epoch",reboundEpoch);j.addProperty("pending",waiting());if(failure!=null)j.addProperty("failure",failure);return j;}
    public void close(){closed=true;}
}
