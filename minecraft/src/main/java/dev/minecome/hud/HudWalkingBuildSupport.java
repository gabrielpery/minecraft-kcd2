package dev.minecome.hud;

import com.google.gson.JsonObject;
import dev.minecome.protocol.AimGeometry;
import dev.minecome.terrain.*;
import net.minecraft.block.*;
import net.minecraft.client.MinecraftClient;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.math.BlockPos;
import net.minecraft.world.BlockView;
import java.util.UUID;
import java.util.concurrent.atomic.*;

/** One explicitly owned lab support beside imported ground; never a terrain edit. */
final class HudWalkingBuildSupport {
    private record Observation(long at,int support,boolean otherwiseAir){}
    private final GroundSurface patch;
    private final String save;
    private final MinecraftServer server;
    private final Object clientWorld,clientPlayer;
    private final UUID playerId;
    private final HudBuildRegion region;
    private final BlockPos support;
    private final HudPhysicalMovement.BuildHeading heading;
    private final AtomicReference<Observation> observation=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicInteger writes=new AtomicInteger();
    private Object serverWorld,serverPlayer;
    private volatile boolean requested,prepared,cleanupRequested,cleaned;

    HudWalkingBuildSupport(MinecraftClient client,GroundSurface patch,String save,HudPhysicalMovement.BuildHeading heading){
        require(Boolean.getBoolean("minecome.hudWalkingAimed") && client.isOnThread() && client.player!=null && client.getServer()!=null,"Live walking build owner required");
        require(save.matches("MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") && save.equals(client.getServer().getSaveProperties().getLevelName()),"Exact walking HUD save required");
        require(patch.sourceKind().equals(patch.corridor()?"live_kcd_ground_corridor":"live_kcd_ground_patch") && GroundCollision.matches(client.world,patch,false),"Exact live imported ground required");
        this.patch=patch;this.save=save;server=client.getServer();clientWorld=client.world;clientPlayer=client.player;playerId=client.player.getUuid();
        require(Math.abs(client.player.getX())<.001 && Math.abs(client.player.getZ())<.001,"Build support must precede walking");
        this.heading=patch.wide()&&!patch.corridor()?heading:null;
        require(!patch.wide() || patch.corridor() || heading!=null,"Fresh host heading required for wide build support");
        int supportY=(int)Math.floor(client.player.getY())-1;
        var cell=patch.corridor()?HudBuildRegion.corridorSupport(patch,supportY):this.heading==null?new AimGeometry.Cell(2,supportY,0):HudBuildRegion.facingSupport((GroundPatch)patch,supportY,heading.forwardX(),heading.forwardZ());
        region=new HudBuildRegion(patch,cell);support=pos(region.support());
    }
    HudBuildRegion region(){return region;}
    GroundSurface patch(){return patch;}
    boolean ready(){return prepared && !cleanupRequested;}
    boolean cleaned(){return cleaned;}
    void observe(MinecraftServer source){
        if(source!=server || cleaned)return;
        try{
            requireServer();var w=source.getOverworld();int state=state(w);
            if(prepared && !cleanupRequested)require(state==1,"Owned build support changed");
            observation.set(new Observation(System.nanoTime(),state,otherwiseAir(w)));
        }catch(Exception e){failure.compareAndSet(null,e.getMessage());}
    }
    boolean prepare(MinecraftClient client){
        check(client);if(prepared)return true;
        var seen=fresh();if(seen==null)return false;
        if(!requested){
            require(seen.support()==0 && seen.otherwiseAir() && state(client.world)==0 && otherwiseAir(client.world),"Build region is not fresh AIR");
            requested=true;server.execute(()->{
                try{requireServer();var w=server.getOverworld();require(state(w)==0 && otherwiseAir(w),"Support prestate changed");
                    require(w.setBlockState(support,Blocks.BEDROCK.getDefaultState(),Block.NOTIFY_ALL),"Support setup refused");writes.incrementAndGet();
                }catch(Exception e){failure.compareAndSet(null,e.getMessage());}
            });return false;
        }
        prepared=writes.get()==1 && seen.support()==1 && state(client.world)==1;
        return prepared;
    }
    boolean cleanup(MinecraftClient client){
        check(client);if(cleaned)return true;
        var seen=fresh();if(seen==null)return false;
        require(seen.otherwiseAir() && otherwiseAir(client.world),"Preserving build support: unresolved or foreign cells remain");
        if(!cleanupRequested){
            require(prepared && seen.support()==1 && state(client.world)==1,"Preserving changed build support");
            cleanupRequested=true;server.execute(()->{
                try{requireServer();var w=server.getOverworld();require(state(w)==1 && otherwiseAir(w),"Support cleanup prestate changed");
                    require(w.setBlockState(support,Blocks.AIR.getDefaultState(),Block.NOTIFY_ALL),"Support cleanup refused");writes.incrementAndGet();
                }catch(Exception e){failure.compareAndSet(null,e.getMessage());}
            });return false;
        }
        cleaned=writes.get()==2 && seen.support()==0 && state(client.world)==0;return cleaned;
    }
    private Observation fresh(){var value=observation.get();long now=System.nanoTime();return value!=null && now>=value.at() && now-value.at()<=250_000_000L?value:null;}
    private void check(MinecraftClient c){
        require(c.isOnThread() && c.world==clientWorld && c.player==clientPlayer && c.getServer()==server && c.isIntegratedServerRunning() && GroundCollision.matches(c.world,patch,false),"Walking build client identity changed");
        require(failure.get()==null,"Walking build support: "+failure.get());
    }
    private void requireServer(){
        var w=server.getOverworld();var p=server.getPlayerManager().getPlayer(playerId);
        require(save.equals(server.getSaveProperties().getLevelName()) && p!=null && p.getWorld()==w && p.isCreative() && GroundCollision.matches(w,patch,true),"Walking build server identity changed");
        if(serverWorld==null){serverWorld=w;serverPlayer=p;}
        require(serverWorld==w && serverPlayer==p && w.isChunkLoaded(support),"Walking build server owner changed");
    }
    private boolean otherwiseAir(BlockView w){
        for(var p:region.importedCells())if(!w.getBlockState(pos(p)).isAir())return false;
        var lo=region.minimum();var hi=region.maximumInclusive();
        for(int x=lo.x();x<=hi.x();x++)for(int y=lo.y();y<=hi.y();y++)for(int z=lo.z();z<=hi.z();z++){
            var p=new BlockPos(x,y,z);if(!p.equals(support) && !w.getBlockState(p).isAir())return false;
        }
        return true;
    }
    private int state(BlockView w){var s=w.getBlockState(support);return s.isAir()?0:s.isOf(Blocks.BEDROCK)?1:2;}
    private static BlockPos pos(AimGeometry.Cell p){return new BlockPos(p.x(),p.y(),p.z());}
    private static void require(boolean b,String reason){if(!b)throw new IllegalStateException(reason);}
    JsonObject evidence(){
        var e=new JsonObject();e.addProperty("patch_run",patch.run());e.addProperty("patch_sha256",patch.sha256());e.addProperty("prepared",prepared);e.addProperty("cleanup_complete",cleaned);e.addProperty("direct_support_writes",writes.get());e.addProperty("failure",failure.get());
        var selection=new JsonObject();selection.addProperty("mode",patch.corridor()?"corridor_side_perimeter":heading==null?"narrow_fixed":"host_view_perimeter");
        if(heading!=null){selection.addProperty("view_seq",heading.viewSequence());selection.addProperty("yaw",heading.yaw());selection.addProperty("forward_x",heading.forwardX());selection.addProperty("forward_z",heading.forwardZ());}
        var cell=new JsonObject();cell.addProperty("x",support.getX());cell.addProperty("y",support.getY());cell.addProperty("z",support.getZ());selection.add("support",cell);e.add("selection",selection);return e;
    }
}
