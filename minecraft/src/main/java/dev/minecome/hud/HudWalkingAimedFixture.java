package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.aim.AimedStoneArena;
import dev.minecome.protocol.*;
import dev.minecome.terrain.*;
import net.minecraft.block.Block;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.math.*;
import net.minecraft.world.BlockView;

import java.util.*;
import java.util.concurrent.atomic.*;

/** Isolated fixture: scripted rays exercise vanilla actions on real blocks after walking.
 * The single labelled fixture support is outside every imported terrain cell.
 * It is neither a terrain export nor evidence of physical input or KCD rendering. */
final class HudWalkingAimedFixture implements AutoCloseable {
    private record Observation(Object world,Object player,Vec3d position,Vec3d velocity,boolean grounded,
                               long at,int supportState,boolean stonesAir,boolean importedAir) {}
    private record Settled(Observation server,double distance,double clientSpeed,double serverSpeed,double clientVertical) {}
    private record Confirmed(String label,AimedStoneArena.Result result,long at,Settled settled) {}
    private static final String[] LABELS={"bootstrap","top_place","upper_break","west_place","west_break","seed_break"};
    private static final String[] FACING_LABELS={"bootstrap","top_place","upper_break","side_place","side_break","seed_break"};
    private final MinecraftServer server;
    private final Object clientWorld,clientPlayer;
    private final UUID playerId;
    private final String save;
    private final GroundPatch patch;
    private final HudBuildRegion region;
    private final BlockPos support,seed,upper,side;
    private final boolean facingSeed;
    private final Direction sideFace;
    private final String[] labels;
    private final AimGeometry.Alignment alignment;
    private final Vec3d initialPosition;
    private final long initializedAt;
    private final AtomicReference<Observation> observation=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final AtomicInteger setupWrites=new AtomicInteger(),cleanupWrites=new AtomicInteger();
    private final List<Confirmed> confirmations=new ArrayList<>();
    private Object serverWorld,serverPlayer;
    private AimedStoneArena arena;
    private Settled dispatchedFrom;
    private long bootstrapAt,firstMovementAt,interactionsAt,cleanupAt;
    private int nextAction;
    private boolean setupRequested,prepared,queued,interactionsDone,cleanupRequested,cleaned,resumed;
    private boolean importedUnchanged,supportRestored;
    private volatile boolean closed;
    private volatile String abortCleanup="not_requested";
    private Vec3d beforeInteractions,serverBeforeInteractions,afterInteractions,serverAfterInteractions;
    private double walkBefore,walkAfter;

    HudWalkingAimedFixture(MinecraftClient client,GroundPatch patch,String save){
        require(Boolean.getBoolean("minecome.hudWalkingAimedFixture") && HudPhysicalMovementMode.fixture(System.getProperties())
                && !Boolean.getBoolean("minecome.hudStreamInput"),"Explicit standalone walking/aimed fixture required");
        require(client.isOnThread() && client.player!=null && client.world!=null && client.getServer()!=null,"Fixture owner missing");
        require(save!=null && save.matches("MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
                && save.equals(client.getServer().getSaveProperties().getLevelName()),"Exact owned HUD fixture save required");
        require(patch.sourceKind().equals("standalone_ground_fixture"),"Fixture terrain provenance differs");
        require(Double.parseDouble(System.getProperty("minecome.hudPhysicalFixtureYaw","0"))==0,
                "Walking/aimed fixture requires yaw zero for its fixed adjacent support");
        this.server=client.getServer();this.clientWorld=client.world;this.clientPlayer=client.player;
        this.playerId=client.player.getUuid();this.patch=patch;this.save=save;initializedAt=System.nanoTime();
        facingSeed=HudPhysicalMovementMode.facingFixture(System.getProperties());
        require(!facingSeed || patch.wide(),"Facing fixture requires the wide terrain profile");
        labels=facingSeed?FACING_LABELS:LABELS;
        initialPosition=client.player.getPos();
        require(Math.abs(initialPosition.x)<.001 && Math.abs(initialPosition.z)<.001,"Fixture alignment must precede walking");
        int supportY=(int)Math.floor(initialPosition.y)-1;
        region=new HudBuildRegion(patch,facingSeed?HudBuildRegion.facingSupport(patch,supportY,0,1):new AimGeometry.Cell((int)patch.halfExtent(),supportY,0));
        support=pos(region.support());seed=pos(region.seed());upper=seed.up();
        sideFace=facingSeed?nearFace(cell(seed)):Direction.WEST;side=seed.offset(sideFace);
        require(region.targetRejection(cell(upper))==null && region.targetRejection(cell(side))==null,
                "Fixture top/side cells overlap protected terrain or lie outside the build region");
        var eye=client.player.getEyePos();
        alignment=new AimGeometry.Alignment(vec(eye),new Protocol.Vec3(patch.centerX(),patch.centerY(),
                patch.centerZ()+eye.y-initialPosition.y),1);
    }

    void observe(MinecraftServer source){
        if(closed || source!=server)return;
        try{
            var entity=source.getPlayerManager().getPlayer(playerId);requireServer(source,entity);
            var world=source.getOverworld();
            observation.set(new Observation(world,entity,entity.getPos(),entity.getVelocity(),entity.isOnGround(),
                    System.nanoTime(),supportState(world),stonesAir(world),importedAir(world)));
        }catch(Exception e){failure.compareAndSet(null,"Walking/aimed server observation: "+e.getMessage());}
    }

    boolean prepare(MinecraftClient client,long now){
        check(client);require(now-initializedAt<5_000_000_000L,"Walking/aimed preparation deadline");
        if(prepared)return true;
        Settled settled=settled(client);
        if(settled==null){if(arena!=null)arena.tick(client,false);return false;}
        if(!setupRequested){
            require(settled.server.supportState()==0 && supportState(client.world)==0 && stonesAir(client.world)
                    && settled.server.stonesAir() && importedAir(client.world) && settled.server.importedAir(),"Fixture support prestate is not fresh AIR");
            setupRequested=true;
            server.execute(()->{
                try{
                    if(closed)return;
                    var entity=server.getPlayerManager().getPlayer(playerId);requireServer(server,entity);var world=server.getOverworld();
                    require(supportState(world)==0 && stonesAir(world) && importedAir(world),"Fixture support prestate changed");
                    require(world.setBlockState(support,Blocks.BEDROCK.getDefaultState(),Block.NOTIFY_ALL),"Fixture support setup rejected");
                    setupWrites.incrementAndGet();
                }catch(Exception e){failure.compareAndSet(null,"Fixture support setup: "+e.getMessage());}
            });return false;
        }
        if(setupWrites.get()!=1 || supportState(client.world)!=1 || settled.server.supportState()!=1)return false;
        require(importedAir(client.world) && settled.server.importedAir(),"Fixture support changed imported terrain");
        if(arena==null)arena=new AimedStoneArena(alignment,save,region);
        arena.tick(client,true);require(!arena.failed(),"Walking/aimed bootstrap: "+arena.failure());
        if(!arena.ready())return false;
        if(!queued){
            var decision=arena.bootstrap(client,1);require(decision.queued(),"Walking/aimed bootstrap rejected: "+decision.reason());
            queued=true;dispatchedFrom=settled;return false;
        }
        if(arena.pending())return false;
        record(client,0,now);bootstrapAt=now;nextAction=1;prepared=true;return true;
    }

    void walkingStarted(long now){
        require(prepared && bootstrapAt>0 && now>bootstrapAt && firstMovementAt==0,"Bootstrap must finish before first movement");
        firstMovementAt=now;
    }

    boolean tickInteractions(MinecraftClient client,long now){
        check(client);require(prepared && firstMovementAt>0,"Walking/aimed interaction started before preparation/walking");
        if(interactionsDone)return true;
        require(now-firstMovementAt<12_000_000_000L,"Walking/aimed actions exhausted the remaining walking window");
        Settled settled=settled(client);
        arena.tick(client,settled!=null);require(!arena.failed(),"Walking/aimed action: "+arena.failure());
        if(queued){
            if(arena.pending())return false;
            record(client,nextAction,now);nextAction++;
            if(nextAction==labels.length){
                require(arena.ownedCells().isEmpty(),"Walking/aimed final owned set is not empty");
                afterInteractions=client.player.getPos();serverAfterInteractions=observation.get().position();
                interactionsAt=now;interactionsDone=true;return true;
            }
        }
        if(settled==null)return false;
        if(beforeInteractions==null){
            beforeInteractions=client.player.getPos();serverBeforeInteractions=settled.server.position();
            walkBefore=Math.min(horizontal(beforeInteractions,initialPosition),horizontal(serverBeforeInteractions,initialPosition));
            require(walkBefore>=.05,"Aimed interactions lack preceding client/server walking");
        }
        require(client.player.getPos().distanceTo(beforeInteractions)<=.01 && settled.server.position().distanceTo(serverBeforeInteractions)<=.01,
                "Player moved during settled aimed actions");
        Vec3d point=switch(nextAction){
            case 1->vec(facingSeed?facingTopAimPoint(cell(seed)):topAimPoint(patch.wide(),cell(seed)));
            case 2->Vec3d.ofCenter(upper);
            case 3->sideAimPoint(seed,sideFace);
            case 4->Vec3d.ofCenter(side);
            case 5->Vec3d.ofCenter(seed);
            default->throw new IllegalStateException("Unknown fixture action");
        };
        var eye=client.player.getEyePos();var direction=point.subtract(eye).normalize();
        var mapped=new AimGeometry.Ray(vec(eye),vec(direction),4.5);
        var ray=new AimedStoneArena.HostRay(System.nanoTime(),alignment,alignment.toKcd(mapped),AimedStoneArena.Occlusion.clear());
        int action=nextAction==1 || nextAction==3?Protocol.PLACE_STONE:Protocol.BREAK_STONE;
        var decision=arena.request(client,nextAction+1,action,ray);
        require(decision.queued(),"Walking/aimed "+labels[nextAction]+" rejected: "+decision.reason());
        queued=true;dispatchedFrom=settled;return false;
    }

    void resumed(MinecraftClient client){
        if(!interactionsDone)return;
        check(client);var settled=settled(client);if(settled==null)return;
        walkAfter=Math.max(walkAfter,Math.min(horizontal(client.player.getPos(),afterInteractions),horizontal(settled.server.position(),serverAfterInteractions)));
        if(walkAfter>=.05)resumed=true;
    }
    boolean interactionsComplete(){return interactionsDone;}

    boolean cleanup(MinecraftClient client,long now){
        check(client);require(interactionsDone && resumed,"Walking/aimed cleanup lacks complete interaction and resumed movement");
        if(cleaned)return true;
        require(!arena.pending() && arena.ownedCells().isEmpty(),"Walking/aimed cleanup retains unresolved stones");
        var settled=settled(client);if(settled==null)return false;
        require(stonesAir(client.world) && settled.server.stonesAir() && importedAir(client.world) && settled.server.importedAir(),
                "Walking/aimed final blocks or imported terrain differ");
        if(!cleanupRequested){
            require(setupWrites.get()==1 && supportState(client.world)==1 && settled.server.supportState()==1,"Fixture support changed before cleanup");
            cleanupRequested=true;cleanupAt=now;server.execute(()->removeSupport(false));return false;
        }
        require(now-cleanupAt<1_500_000_000L,"Fixture support cleanup deadline");
        if(cleanupWrites.get()!=1 || supportState(client.world)!=0 || settled.server.supportState()!=0)return false;
        importedUnchanged=true;supportRestored=true;cleaned=true;return true;
    }

    private void record(MinecraftClient client,int index,long now){
        var result=arena.lastResult();BlockPos expected=switch(index){case 0,5->seed;case 1,2->upper;case 3,4->side;default->throw new IllegalStateException();};
        require(result!=null && result.id()==index+1 && result.status().equals("confirmed") && result.clientAndServer()
                && result.target().equals(expected),"Walking/aimed action lacks exact authoritative outcome");
        if(index==0 || index==1)require(result.hit().side()==Direction.UP,"Top placement selected another face");
        if(index==3)require(result.hit().side()==sideFace,"Side placement selected another face");
        confirmations.add(new Confirmed(labels[index],result,now,dispatchedFrom));queued=false;dispatchedFrom=null;
    }

    private Settled settled(MinecraftClient client){
        var proof=observation.get();long now=System.nanoTime();
        if(proof==null || now<proof.at() || now-proof.at()>250_000_000L || client.currentScreen!=null || client.getOverlay()!=null || client.isPaused())return null;
        var velocity=client.player.getVelocity();
        double clientSpeed=Math.hypot(velocity.x,velocity.z),serverSpeed=Math.hypot(proof.velocity().x,proof.velocity().z),distance=client.player.getPos().distanceTo(proof.position());
        if(!client.player.isOnGround() || !proof.grounded() || clientSpeed>=.03 || serverSpeed>=.03 || distance>.01
                || Math.abs(velocity.y)>=.1 || Math.abs(proof.velocity().y)>=.1
                || client.options.forwardKey.isPressed() || client.options.backKey.isPressed() || client.options.leftKey.isPressed()
                || client.options.rightKey.isPressed() || client.options.jumpKey.isPressed())return null;
        return new Settled(proof,distance,clientSpeed,serverSpeed,velocity.y);
    }
    private void check(MinecraftClient client){
        require(!closed && client.isOnThread() && client.world==clientWorld && client.player==clientPlayer
                && client.getServer()==server && client.isIntegratedServerRunning() && client.player.isCreative(),"Walking/aimed client ownership changed");
        require(GroundCollision.matches(client.world,patch,false),"Walking/aimed client proxy identity changed");
        require(failure.get()==null,"Walking/aimed fixture failure: "+failure.get());
    }
    private void requireServer(MinecraftServer source,ServerPlayerEntity entity){
        require(source==server && source.getOverworld()!=null && entity!=null && entity.getUuid().equals(playerId)
                && entity.getWorld()==source.getOverworld() && entity.isCreative() && save.equals(source.getSaveProperties().getLevelName()),"Walking/aimed server ownership changed");
        if(serverWorld==null){serverWorld=source.getOverworld();serverPlayer=entity;}
        require(serverWorld==source.getOverworld() && serverPlayer==entity && GroundCollision.matches(source.getOverworld(),patch,true),"Walking/aimed server proxy ownership changed");
        for(var p:List.of(support,seed,upper,side))require(source.getOverworld().isChunkLoaded(p),"Walking/aimed chunk unavailable");
    }
    private void removeSupport(boolean abort){
        try{
            var entity=server.getPlayerManager().getPlayer(playerId);requireServer(server,entity);var world=server.getOverworld();
            if(setupWrites.get()==0){if(abort)abortCleanup="no_support_created";return;}
            if(cleanupWrites.get()==1)return;
            // Never overwrite an altered support or remove it under unresolved stones.
            if(supportState(world)!=1 || !stonesAir(world) || !importedAir(world)){
                if(abort){abortCleanup="preserved_changed_or_unresolved_cells";return;}
                throw new IllegalStateException("Fixture support/stone cleanup prestate changed");
            }
            require(world.setBlockState(support,Blocks.AIR.getDefaultState(),Block.NOTIFY_ALL),"Fixture support cleanup rejected");
            cleanupWrites.incrementAndGet();if(abort)abortCleanup="removed_owned_support";
        }catch(Exception e){if(abort)abortCleanup="preserved_after_owner_or_cleanup_failure";else failure.compareAndSet(null,"Fixture support cleanup: "+e.getMessage());}
    }
    private boolean importedAir(BlockView world){for(var c:region.importedCells())if(!world.getBlockState(pos(c)).isAir())return false;return true;}
    private boolean stonesAir(BlockView world){for(var p:List.of(seed,upper,side))if(!world.getBlockState(p).isAir())return false;return true;}
    private int supportState(BlockView world){var state=world.getBlockState(support);return state.isAir()?0:state.isOf(Blocks.BEDROCK)?1:2;}
    private static double horizontal(Vec3d a,Vec3d b){return Math.hypot(a.x-b.x,a.z-b.z);}
    private static Protocol.Vec3 vec(Vec3d p){return new Protocol.Vec3(p.x,p.y,p.z);}
    private static Vec3d vec(Protocol.Vec3 p){return new Vec3d(p.x(),p.y(),p.z());}
    /** The wide perimeter is farther away; aim inside its top face without increasing ray reach. */
    static Protocol.Vec3 topAimPoint(boolean wide,AimGeometry.Cell seed){
        return new Protocol.Vec3(seed.x()+(wide?.25:.5),seed.y()+1,seed.z()+.5);
    }
    static Direction nearFace(AimGeometry.Cell seed){
        double x=seed.x()+.5,z=seed.z()+.5;
        return Math.abs(x)>=Math.abs(z)?(x>=0?Direction.WEST:Direction.EAST):(z>=0?Direction.NORTH:Direction.SOUTH);
    }
    static Protocol.Vec3 facingTopAimPoint(AimGeometry.Cell seed){
        Direction face=nearFace(seed);
        return new Protocol.Vec3(seed.x()+(face==Direction.WEST?.25:face==Direction.EAST?.75:.5),seed.y()+1,
                seed.z()+(face==Direction.NORTH?.25:face==Direction.SOUTH?.75:.5));
    }
    private static Vec3d sideAimPoint(BlockPos seed,Direction face){
        return new Vec3d(seed.getX()+(face==Direction.WEST?0:face==Direction.EAST?1:.5),seed.getY()+.5,
                seed.getZ()+(face==Direction.NORTH?0:face==Direction.SOUTH?1:.5));
    }
    private static AimGeometry.Cell cell(BlockPos p){return new AimGeometry.Cell(p.getX(),p.getY(),p.getZ());}
    private static BlockPos pos(AimGeometry.Cell p){return new BlockPos(p.x(),p.y(),p.z());}
    private static JsonObject json(BlockPos p){var j=new JsonObject();j.addProperty("x",p.getX());j.addProperty("y",p.getY());j.addProperty("z",p.getZ());return j;}
    private static void require(boolean value,String reason){if(!value)throw new IllegalStateException(reason);}

    JsonObject evidence(){
        var e=new JsonObject();e.addProperty("kind","standalone_hud_walking_aimed_fixture_v1");e.addProperty("scripted_input",true);
        if(patch.wide()){
            e.addProperty("walking_area","wide");e.addProperty("max_host_ray_range",AimedStoneArena.MAX_HOST_RAY_RANGE);
            var point=facingSeed?facingTopAimPoint(cell(seed)):topAimPoint(true,cell(seed));var top=new JsonObject();top.addProperty("x",point.x());top.addProperty("y",point.y());top.addProperty("z",point.z());
            e.add("top_aim_point",top);
        }
        if(facingSeed){e.addProperty("facing_seed",true);e.addProperty("facing_side",sideFace.name());}
        e.addProperty("synthetic_host_rays",true);e.addProperty("physical_input_verified",false);e.addProperty("kcd_connected",false);
        e.addProperty("completed",cleaned && resumed);e.addProperty("alignment_before_movement",firstMovementAt>initializedAt);
        e.addProperty("bootstrap_before_movement",firstMovementAt>bootstrapAt && bootstrapAt>0);e.addProperty("movement_before_interactions",walkBefore>=.05);
        e.addProperty("movement_resumed_after_interactions",resumed);e.addProperty("walk_before_m",walkBefore);e.addProperty("walk_after_m",walkAfter);
        e.addProperty("patch_run",patch.run());e.addProperty("patch_sha256",patch.sha256());e.add("support",json(support));e.add("seed",json(seed));
        e.addProperty("support_fixture_setup_writes",setupWrites.get());e.addProperty("support_fixture_cleanup_writes",cleanupWrites.get());
        e.addProperty("arena_direct_block_writes",0);e.addProperty("support_client_server_prepared",prepared);
        e.addProperty("support_client_server_restored_air",supportRestored);e.addProperty("imported_cells_unchanged",importedUnchanged);
        e.addProperty("final_client_server_air",cleaned);e.addProperty("abort_cleanup",abortCleanup);
        var records=new JsonArray();
        for(var value:confirmations){
            var r=value.result();var proof=value.settled();var item=new JsonObject();
            item.addProperty("label",value.label());item.addProperty("id",r.id());item.addProperty("action",r.action());
            item.add("target",json(r.target()));item.add("hit_block",json(r.hit().block()));item.addProperty("face",r.hit().side().name());
            item.addProperty("client_and_server",r.clientAndServer());item.addProperty("confirmed",r.status().equals("confirmed"));
            item.addProperty("elapsed_from_first_movement_ms",firstMovementAt>0?(value.at()-firstMovementAt)/1_000_000:0);
            item.addProperty("client_server_distance",proof.distance());item.addProperty("client_speed",proof.clientSpeed());item.addProperty("server_speed",proof.serverSpeed());
            item.addProperty("speed_metric","horizontal_xz");item.addProperty("client_vertical_velocity",proof.clientVertical());item.addProperty("server_vertical_velocity",proof.server().velocity().y);
            item.addProperty("client_on_ground",true);item.addProperty("server_on_ground",proof.server().grounded());
            records.add(item);
        }
        e.add("confirmations",records);e.add("arena",arena==null?JsonNull.INSTANCE:arena.evidence());return e;
    }
    @Override public void close(){
        if(closed)return;closed=true;
        boolean unresolved=arena!=null && (arena.pending() || !arena.ownedCells().isEmpty());
        if(arena!=null)arena.close();
        if(!cleaned && !cleanupRequested){
            if(unresolved)abortCleanup="preserved_support_with_unresolved_stones";
            else{abortCleanup="requested";server.execute(()->removeSupport(true));}
        }
    }
}
