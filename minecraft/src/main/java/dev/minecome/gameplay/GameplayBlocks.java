package dev.minecome.gameplay;

import com.google.gson.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.Items;
import net.minecraft.registry.Registries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.Hand;
import net.minecraft.util.hit.*;
import net.minecraft.util.math.*;
import net.minecraft.world.*;
import java.io.IOException;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Persistent stone building through vanilla interaction packets, with server-confirmed ownership. */
public final class GameplayBlocks {
    public record Aim(long capturedUtcMs,long observedAtNanos,Vec3d origin,Vec3d direction,double range,
                      boolean obstructionKnown,double obstructionDistance,boolean terrainHit) {
        public Aim {
            if(origin==null||direction==null||!finite(origin)||!finite(direction)||!Double.isFinite(range)||range<=0||range>4.5||
                Math.abs(direction.lengthSquared()-1)>.01||!Double.isFinite(obstructionDistance)||obstructionDistance< -1||obstructionDistance>range||
                (obstructionDistance<0&&obstructionDistance!=-1)||(!obstructionKnown&&obstructionDistance!=-1)||
                (terrainHit&&(!obstructionKnown||obstructionDistance<0)))throw new IllegalArgumentException("Invalid gameplay aim");
        }
        public boolean fresh(long utc,long now){return capturedUtcMs>0&&utc>=capturedUtcMs-50&&utc-capturedUtcMs<=300&&now>=observedAtNanos&&now-observedAtNanos<=300_000_000L;}
    }
    private record Selection(BlockPos target,BlockHitResult hit,boolean ground){}
    private record Plan(long id,int action,Aim aim,Selection selection,int slot,String item,int count,boolean creative,long at){}
    private record Intent(Plan plan,long dispatchedAt){}
    private record Observation(long at,long utc,long planId,boolean admitted,String reason,int targetState,long confirmed,Set<GameplayBlocksLedger.Cell> cells){}
    private final GameplayWorld save;private final GroundSurface surface;private final HudInputProtocol.Identity identity;
    private final GameplayBlocksLedger ledger;private final GameplayBlocksFiles files;
    private final Set<GameplayBlocksLedger.Cell> serverCells=new TreeSet<>();
    private final AtomicReference<Set<GameplayBlocksLedger.Cell>> owned=new AtomicReference<>();
    private final AtomicReference<Intent> intent=new AtomicReference<>();private final AtomicReference<Observation> observation=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private volatile MinecraftServer server;private Object clientWorld,clientPlayer,serverWorld,serverPlayer;
    private volatile UUID playerId;private volatile boolean serverInitialized,closing,serverClosed;private volatile long closeAt;
    private Aim aim;private Plan pending;private boolean actions,ready,left,right,dispatched,breakCancelled;
    private long ids,serverSequence,revision,confirmed,dispatchedAt,lastDispatch,places,breaks,rejections,cancellations,groundPlaces,survivalBreaks,survivalPreservedTicks;
    private String lastResult="starting";

    public GameplayBlocks(Path root,GameplayWorld save,GroundSurface surface,HudInputProtocol.Identity identity,Path evidenceDirectory)throws IOException {
        this.save=save;this.surface=surface;this.identity=identity;ledger=new GameplayBlocksLedger(save,surface);
        serverCells.addAll(ledger.initial);owned.set(Set.copyOf(serverCells));revision=ledger.initialRevision;files=new GameplayBlocksFiles(root,evidenceDirectory,ledger);
    }
    public void aim(Aim next){aim=next;}
    public boolean ready(){return ready&&!closing&&failure.get()==null;}
    public Set<BlockPos> ownedBlocks(){var result=new HashSet<BlockPos>();for(var c:owned.get())result.add(pos(c));return Set.copyOf(result);}
    private void check(){if(files.failure()!=null)failure.compareAndSet(null,files.failure());if(failure.get()!=null)throw new IllegalStateException(failure.get());}
    public void tick(MinecraftClient client,boolean enabled){
        if(closing)return;check();if(client.world==null||client.player==null||client.getServer()==null||client.interactionManager==null)return;
        if(clientWorld==null){if(!client.isOnThread()||client.world.getRegistryKey()!=World.OVERWORLD||!client.isIntegratedServerRunning())throw new IllegalStateException("Block controller requires owned overworld");
            clientWorld=client.world;clientPlayer=client.player;playerId=client.player.getUuid();if(server!=null&&server!=client.getServer())throw new IllegalStateException("Block server changed");server=client.getServer();}
        requireClient(client);long now=System.nanoTime();var observed=observation.get();
        ready=serverInitialized&&observed!=null&&now-observed.at()<250_000_000L;
        actions=ready&&enabled&&client.currentScreen==null&&client.getOverlay()==null&&!client.isPaused();
        if(!actions)suspend(client);
        if(pending!=null){
            if(!dispatched){
                if(!actions||(!left&&pending.action()==0&&!pending.creative()))finish(client,"cancelled_before_dispatch",false);
                else if(observed!=null&&observed.planId()==pending.id()&&now-observed.at()<=250_000_000L){
                    if(!observed.admitted())finish(client,observed.reason(),false);else dispatch(client,now);
                }
            }else{
                if(observed!=null&&observed.confirmed()==pending.id()){
                    int expected=pending.action()==1?1:0;
                    if(state(client.world,pending.selection().target())==expected){if(pending.action()==1){places++;if(pending.selection().ground())groundPlaces++;}else{breaks++;if(!pending.creative())survivalBreaks++;}finish(client,"confirmed",true);}
                }
                if(pending!=null&&pending.action()==0&&!pending.creative()){
                    if(!actions||!left||!sameCurrentTarget(client,pending)){if(!breakCancelled){client.interactionManager.cancelBlockBreaking();breakCancelled=true;}}
                    else client.interactionManager.updateBlockBreakingProgress(pending.selection().target(),pending.selection().hit().getSide());
                }
            }
            if(pending!=null&&now-pending.at()>(pending.action()==0&&!pending.creative()&&!breakCancelled?30_000_000_000L:2_000_000_000L))finish(client,"vanilla_rejected_or_cancelled",false);
        }
        if(actions&&pending==null&&now-lastDispatch>=250_000_000L){if(left)queue(client,0);else if(right)queue(client,1);}
    }
    public void event(MinecraftClient client,HudInputProtocol.Event event){
        if(event.kind()!=7&&event.kind()!=8)throw new IllegalArgumentException("Expected world button edge");if(event.code()<0||event.code()>1)throw new IllegalArgumentException("World button");
        if(closing)return;boolean down=event.kind()==7;if(event.code()==0)left=down;else right=down;
        if(down&&actions&&pending==null)queue(client,event.code());
        if(!down&&event.code()==0&&dispatched&&pending!=null&&pending.action()==0&&!pending.creative()&&client.interactionManager!=null){client.interactionManager.cancelBlockBreaking();breakCancelled=true;}
    }
    public void suspend(MinecraftClient client){actions=false;left=false;right=false;if(client.interactionManager!=null&&pending!=null&&pending.action()==0&&dispatched&&!breakCancelled){client.interactionManager.cancelBlockBreaking();breakCancelled=true;}}
    private void queue(MinecraftClient client,int action){
        var current=aim;long now=System.nanoTime();lastDispatch=now;if(current==null||!current.fresh(System.currentTimeMillis(),now)){rejections++;lastResult="aim_stale";return;}
        try{
            var selected=select(client.world,client.player,current,action,owned.get());
            if(action==1&&(owned.get().size()>=GameplayBlocksLedger.MAX_BLOCKS||!client.player.getMainHandStack().isOf(Items.STONE))){rejections++;lastResult="stone_stack_or_capacity";return;}
            int slot=client.player.getInventory().selectedSlot;var stack=client.player.getInventory().getStack(slot);
            pending=new Plan(++ids,action,current,selected,slot,Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount(),client.player.isCreative(),now);
            dispatched=false;breakCancelled=false;intent.set(new Intent(pending,0));lastResult="awaiting_server";
        }catch(IllegalArgumentException rejected){rejections++;lastResult=rejected.getMessage();}
    }
    private void dispatch(MinecraftClient client,long now){
        try{
            var p=pending;if(!p.aim().fresh(System.currentTimeMillis(),now))throw new IllegalArgumentException("aim_expired_before_dispatch");
            var selected=select(client.world,client.player,p.aim(),p.action(),owned.get());
            if(!same(selected,p.selection())||!sameStack(client.player,p))throw new IllegalArgumentException("selection_or_stack_changed");
            boolean accepted=p.action()==1?client.interactionManager.interactBlock(client.player,Hand.MAIN_HAND,p.selection().hit()).isAccepted():client.interactionManager.attackBlock(p.selection().target(),p.selection().hit().getSide());
            if(!accepted){finish(client,"vanilla_dispatch_rejected",false);return;}
            dispatched=true;dispatchedAt=System.nanoTime();lastDispatch=dispatchedAt;intent.set(new Intent(p,dispatchedAt));lastResult="awaiting_confirmation";
        }catch(IllegalArgumentException rejected){finish(client,rejected.getMessage(),false);}
    }
    private boolean sameCurrentTarget(MinecraftClient client,Plan p){try{return aim!=null&&aim.fresh(System.currentTimeMillis(),System.nanoTime())&&select(client.world,client.player,aim,0,owned.get()).target().equals(p.selection().target());}catch(IllegalArgumentException e){return false;}}
    /** Preserve this admitted hold across MinecraftClient's ordinary attack-key cancellation. */
    public boolean needsVanillaBreakPreserved(MinecraftClient client){
        if(closing||!actions||!left||!dispatched||breakCancelled||pending==null||pending.action()!=0||pending.creative()||clientWorld==null||
            client.world!=clientWorld||client.player!=clientPlayer||client.getServer()!=server||!client.isOnThread()||client.currentScreen!=null||client.getOverlay()!=null||client.isPaused())return false;
        var observed=observation.get();long now=System.nanoTime();
        if(observed==null||now<observed.at()||now-observed.at()>250_000_000L||!sameStack(client.player,pending)||!sameCurrentTarget(client,pending))return false;
        survivalPreservedTicks++;return true;
    }
    private void finish(MinecraftClient client,String reason,boolean success){if(pending!=null&&pending.action()==0&&client.interactionManager!=null)client.interactionManager.cancelBlockBreaking();
        if(!success){rejections++;if(reason.contains("cancel"))cancellations++;}lastResult=reason;pending=null;intent.set(null);dispatched=false;breakCancelled=false;}
    private Selection select(World world,PlayerEntity player,Aim ray,int action,Set<GameplayBlocksLedger.Cell> cells){
        if(!ray.obstructionKnown()||!ray.fresh(System.currentTimeMillis(),System.nanoTime()))throw new IllegalArgumentException("aim_unavailable");
        if(ray.origin().distanceTo(player.getEyePos())>.35)throw new IllegalArgumentException("eye_disagrees");
        var end=ray.origin().add(ray.direction().multiply(ray.range()));
        var hit=world.raycast(new RaycastContext(ray.origin(),end,RaycastContext.ShapeType.OUTLINE,RaycastContext.FluidHandling.NONE,player));
        if(hit.getType()==HitResult.Type.BLOCK){
            if(!cells.contains(cell(hit.getBlockPos()))||!world.getBlockState(hit.getBlockPos()).isOf(Blocks.STONE))throw new IllegalArgumentException("unowned_target");
            double distance=hit.getPos().distanceTo(ray.origin());
            if(ray.obstructionDistance()>=0&&ray.obstructionDistance()<distance-.05)throw new IllegalArgumentException("native_obstruction");
            var target=action==1?hit.getBlockPos().offset(hit.getSide()):hit.getBlockPos();validateTarget(world,player,target,action,cells);
            return new Selection(target.toImmutable(),hit,false);
        }
        if(action==0||!ray.terrainHit()||ray.obstructionDistance()<0)throw new IllegalArgumentException("no_owned_stone_hit");
        var point=ray.origin().add(ray.direction().multiply(ray.obstructionDistance()));
        if(!surface.containsFeet(point.x,point.z,.001)||Math.abs(surface.heightAt(point.x,point.z)-point.y)>.65)throw new IllegalArgumentException("terrain_hit_outside_capture");
        var target=BlockPos.ofFloored(point);validateTarget(world,player,target,1,cells);
        // Inspected Yarn1.21.1 ItemPlacementContext replaces a clicked AIR cell;
        // PlayerInteractBlock's usual reach/collision/mode checks remain vanilla.
        // This user-placed block can overlap the sampled slab; breaking it restores AIR.
        return new Selection(target,new BlockHitResult(point,Direction.UP,target,false),true);
    }
    private void validateTarget(World world,PlayerEntity player,BlockPos target,int action,Set<GameplayBlocksLedger.Cell> cells){
        if(!GameplayBlocksLedger.allowed(surface,cell(target))||!world.isChunkLoaded(target)||!player.canInteractWithBlockAt(target,0))throw new IllegalArgumentException("outside_build_coverage_or_reach");
        if(action==1){if(!world.getBlockState(target).isAir()||cells.contains(cell(target)))throw new IllegalArgumentException("occupied_target");
            if(new Box(target).intersects(player.getBoundingBox()))throw new IllegalArgumentException("player_occupies_target");}
        else if(!cells.contains(cell(target))||!world.getBlockState(target).isOf(Blocks.STONE))throw new IllegalArgumentException("unowned_target");
    }
    /** Called only on END_SERVER_TICK, including the short orderly-shutdown drain. */
    public void observe(MinecraftServer source){
        if(serverClosed)return;
        try{
            if(!source.isOnThread())throw new IllegalStateException("Block observation requires server thread");
            if(!source.getSaveProperties().getLevelName().equals(save.saveName()))return;
            if(server==null)server=source;if(server!=source)throw new IllegalStateException("Block server changed");
            var world=source.getOverworld();if(serverWorld==null)serverWorld=world;if(serverWorld!=world)throw new IllegalStateException("Block world changed");
            if(!serverInitialized){
                if(serverCells.stream().anyMatch(c->!world.isChunkLoaded(pos(c))))return;
                boolean reconciled=false;for(var c:new ArrayList<>(serverCells)){int s=state(world,pos(c));if(s==0){serverCells.remove(c);reconciled=true;}else if(s!=1)throw new IllegalStateException("Saved owned stone changed type");}
                if(reconciled)revision++;owned.set(Set.copyOf(serverCells));serverInitialized=true;
            }
            var request=intent.get();long planId=0;boolean admitted=false;String reason="no_request";int targetState=-1;
            if(playerId!=null){var player=source.getPlayerManager().getPlayer(playerId);if(player==null||player.getWorld()!=world)throw new IllegalStateException("Block player changed");
                if(serverPlayer==null)serverPlayer=player;if(serverPlayer!=player)throw new IllegalStateException("Block player identity changed");
                if(request!=null){var plan=request.plan();planId=plan.id();targetState=state(world,plan.selection().target());
                    if(request.dispatchedAt()==0){try{var selected=select(world,player,plan.aim(),plan.action(),Set.copyOf(serverCells));
                        admitted=same(selected,plan.selection())&&sameStack(player,plan);reason=admitted?"admitted":"server_selection_or_stack_changed";
                    }catch(IllegalArgumentException rejected){reason=rejected.getMessage();}}
                    else if(confirmed<plan.id()&&targetState==(plan.action()==1?1:0)){
                        if(plan.action()==1)serverCells.add(cell(plan.selection().target()));else serverCells.remove(cell(plan.selection().target()));revision++;confirmed=plan.id();owned.set(Set.copyOf(serverCells));
                    }
                }
            }
            // Vanilla remains authoritative even if another allowed action (for
            // example a later command integration) removes an owned stone.
            boolean reconciled=false;
            for(var c:new ArrayList<>(serverCells)){
                if(!world.isChunkLoaded(pos(c)))throw new IllegalStateException("Owned stone chunk unloaded");
                int value=state(world,pos(c));
                if(value==0){serverCells.remove(c);reconciled=true;}
                else if(value!=1)throw new IllegalStateException("Owned stone changed to unsupported block");
            }
            if(reconciled){revision++;owned.set(Set.copyOf(serverCells));}
            long utc=System.currentTimeMillis(),now=System.nanoTime();var cells=Set.copyOf(serverCells);
            observation.set(new Observation(now,utc,planId,admitted,reason,targetState,confirmed,cells));publish(utc,cells);
            if(closing&&now-closeAt>=150_000_000L){serverClosed=true;files.close();}
        }catch(Exception error){failure.compareAndSet(null,error.toString());if(closing){serverClosed=true;files.close();}}
    }
    private void publish(long utc,Set<GameplayBlocksLedger.Cell> cells){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_blocks_v1");j.addProperty("run",identity.run());j.addProperty("world_id",save.id().toString());
        j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("patch_run",surface.run());j.addProperty("patch_sha256",surface.sha256());
        j.addProperty("seq",++serverSequence);j.addProperty("utc_ms",utc);j.addProperty("revision",revision);j.add("blocks",GameplayBlocksLedger.blocks(cells));files.publish(revision,cells,j.toString());
    }
    public boolean terrainCellAllowed(BlockView world,BlockPos position,boolean serverSide){
        if(world.getBlockState(position).isAir())return true;if(!world.getBlockState(position).isOf(Blocks.STONE))return false;
        var c=cell(position);if(owned.get().contains(c))return true;var p=intent.get();return p!=null&&p.plan().action()==1&&p.plan().selection().target().equals(position);
    }
    public double groundForFeet(BlockView world,double x,double y,double z,double half){
        double result=surface.groundForFeet(x,z,half);var candidates=new HashSet<>(owned.get());var p=intent.get();if(p!=null&&p.plan().action()==1)candidates.add(cell(p.plan().selection().target()));
        for(var c:candidates)if(c.y()+1<=y+.2&&x+half>c.x()&&x-half<c.x()+1&&z+half>c.z()&&z-half<c.z()+1&&world.getBlockState(pos(c)).isOf(Blocks.STONE))result=Math.max(result,c.y()+1);
        return result;
    }
    public void close(MinecraftClient client){if(closing)return;suspend(client);closing=true;closeAt=System.nanoTime();if(server==null||!serverInitialized){serverClosed=true;files.close();}}
    public boolean cleanupComplete(){return closing&&serverClosed&&files.finished()&&files.failure()==null;}
    public JsonObject evidence(MinecraftClient client){var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_blocks_controller_v1");j.addProperty("run",identity.run());j.addProperty("world_id",save.id().toString());
        j.addProperty("ready",ready);j.addProperty("revision",revision);j.addProperty("owned_count",owned.get().size());j.add("blocks",GameplayBlocksLedger.blocks(owned.get()));
        j.addProperty("places",places);j.addProperty("breaks",breaks);j.addProperty("ground_places",groundPlaces);j.addProperty("rejections",rejections);j.addProperty("cancellations",cancellations);j.addProperty("last_result",lastResult);
        j.addProperty("survival_breaks",survivalBreaks);j.addProperty("survival_preserved_ticks",survivalPreservedTicks);
        j.addProperty("pending",pending!=null);j.addProperty("snapshot_writes",files.writes());j.addProperty("persisted_revision",files.persistedRevision());j.addProperty("cleanup_complete",cleanupComplete());j.addProperty("controls_released",!left&&!right);
        j.addProperty("minecraft_blocks_removed_on_stop",0);j.addProperty("failure",failure.get()!=null?failure.get():files.failure());return j;}
    private void requireClient(MinecraftClient c){if(!c.isOnThread()||c.world!=clientWorld||c.player!=clientPlayer||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Block client owner changed");}
    private static boolean same(Selection a,Selection b){return a.target().equals(b.target())&&a.hit().getBlockPos().equals(b.hit().getBlockPos())&&a.hit().getSide()==b.hit().getSide()&&a.ground()==b.ground()&&a.hit().getPos().squaredDistanceTo(b.hit().getPos())<1e-8;}
    private static boolean sameStack(PlayerEntity p,Plan plan){var stack=p.getInventory().getStack(plan.slot());return p.getInventory().selectedSlot==plan.slot()&&Registries.ITEM.getId(stack.getItem()).toString().equals(plan.item())&&stack.getCount()==plan.count();}
    private static boolean finite(Vec3d v){return Double.isFinite(v.x)&&Double.isFinite(v.y)&&Double.isFinite(v.z);}
    private static int state(BlockView world,BlockPos p){return world.getBlockState(p).isAir()?0:world.getBlockState(p).isOf(Blocks.STONE)?1:2;}
    private static GameplayBlocksLedger.Cell cell(BlockPos p){return new GameplayBlocksLedger.Cell(p.getX(),p.getY(),p.getZ());}
    private static BlockPos pos(GameplayBlocksLedger.Cell c){return new BlockPos(c.x(),c.y(),c.z());}
}
