package dev.minecome.gameplay;

import com.google.gson.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.GroundSurface;
import dev.minecome.terrain.GameplayTerrain;
import net.minecraft.block.Blocks;
import net.minecraft.block.BlockState;
import net.minecraft.block.ShapeContext;
import net.minecraft.block.entity.FurnaceBlockEntity;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.component.DataComponentTypes;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.Items;
import net.minecraft.item.BlockItem;
import net.minecraft.item.ItemPlacementContext;
import net.minecraft.registry.Registries;
import net.minecraft.screen.CraftingScreenHandler;
import net.minecraft.screen.FurnaceScreenHandler;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.util.Hand;
import net.minecraft.util.hit.*;
import net.minecraft.util.math.*;
import net.minecraft.util.shape.VoxelShape;
import net.minecraft.world.*;
import java.io.IOException;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Persistent bounded building through vanilla interaction packets, with server-confirmed block states. */
public final class GameplayBlocks {
    private static final int WORKSTATION_USE=2;
    private static final int TNT_IGNITE=3;
    public record Aim(long capturedUtcMs,long observedAtNanos,Vec3d origin,Vec3d direction,double range,
                      boolean obstructionKnown,double obstructionDistance,boolean terrainHit,Vec3d cameraOrigin) {
        public Aim(long capturedUtcMs,long observedAtNanos,Vec3d origin,Vec3d direction,double range,
                boolean obstructionKnown,double obstructionDistance,boolean terrainHit){
            this(capturedUtcMs,observedAtNanos,origin,direction,range,obstructionKnown,obstructionDistance,terrainHit,origin);
        }
        public Aim {
            if(origin==null||direction==null||cameraOrigin==null||!finite(origin)||!finite(direction)||!finite(cameraOrigin)||cameraOrigin.squaredDistanceTo(origin)>16.00000001||!Double.isFinite(range)||range<=0||range>4.5||
                Math.abs(direction.lengthSquared()-1)>.01||!Double.isFinite(obstructionDistance)||obstructionDistance< -1||obstructionDistance>range||
                (obstructionDistance<0&&obstructionDistance!=-1)||(!obstructionKnown&&obstructionDistance!=-1)||
                (terrainHit&&(!obstructionKnown||obstructionDistance<0)))throw new IllegalArgumentException("Invalid gameplay aim");
        }
        public boolean fresh(long utc,long now){return capturedUtcMs>0&&utc>=capturedUtcMs-50&&utc-capturedUtcMs<=300&&now>=observedAtNanos&&now-observedAtNanos<=300_000_000L;}
    }
    private record Selection(BlockPos target,BlockHitResult hit,boolean ground){}
    private record Plan(long id,int action,Aim aim,Selection selection,int slot,String item,int count,boolean creative,String expectedState,long at){}
    private record Intent(Plan plan,long dispatchedAt){}
    private record Observation(long at,long utc,long planId,boolean admitted,String reason,String targetState,long confirmed,Map<GameplayBlocksLedger.Cell,String> cells){}
    private final GameplayWorld save;private volatile GroundSurface surface;private final HudInputProtocol.Identity identity;
    private final GameplayBlocksLedger ledger;private final GameplayBlocksFiles files;
    private final Map<GameplayBlocksLedger.Cell,String> serverCells=new TreeMap<>();
    private final Map<GameplayBlocksLedger.Cell,FurnaceBlockEntity> serverFurnaces=new HashMap<>();
    private final AtomicReference<Map<GameplayBlocksLedger.Cell,String>> owned=new AtomicReference<>();
    private final boolean worldBlocks;
    private final GameplayCameraCollision cameraCollision=new GameplayCameraCollision();
    private final GameplayFoodUse foodUse=new GameplayFoodUse();
    private final GameplayRangedUse rangedUse=new GameplayRangedUse();
    private final GameplayTnt tnt;
    private final AtomicReference<Intent> intent=new AtomicReference<>();private final AtomicReference<Observation> observation=new AtomicReference<>();
    private final AtomicReference<String> failure=new AtomicReference<>();
    private volatile MinecraftServer server;private Object clientWorld,clientPlayer,serverWorld,serverPlayer;
    private volatile UUID playerId;private volatile boolean serverInitialized,closing,serverClosed;private volatile long closeAt;
    private volatile long serverRespawns,clientRespawns;
    private Aim aim;private Plan pending;private boolean actions,ready,left,right,dispatched,breakCancelled;
    private long ids,serverSequence,revision,confirmed,dispatchedAt,lastDispatch,places,breaks,rejections,cancellations,groundPlaces,survivalBreaks,survivalPreservedTicks,craftingOpens,furnaceOpens,tntIgnitions;
    private String lastResult="starting";

    public GameplayBlocks(Path root,GameplayWorld save,GroundSurface surface,HudInputProtocol.Identity identity,Path evidenceDirectory)throws IOException {
        this(root,save,surface,identity,evidenceDirectory,false);
    }
    public GameplayBlocks(Path root,GameplayWorld save,GroundSurface surface,HudInputProtocol.Identity identity,Path evidenceDirectory,boolean worldBlocks)throws IOException {
        this.save=save;this.surface=surface;this.identity=identity;this.worldBlocks=worldBlocks;ledger=new GameplayBlocksLedger(save,surface,worldBlocks);
        serverCells.putAll(ledger.initialStates);owned.set(Map.copyOf(serverCells));revision=ledger.initialRevision;files=new GameplayBlocksFiles(root,evidenceDirectory,ledger);
        tnt=new GameplayTnt(this,save,surface);
    }
    public void aim(Aim next){aim=next;}
    /** Called while gameplay is paused, after both collision owners attach the same additive coverage. */
    public void terrain(GroundSurface next){
        var before=surface;
        if(closing||next==null||!before.run().equals(next.run())||!before.sha256().equals(next.sha256())||
            before.centerX()!=next.centerX()||before.centerY()!=next.centerY()||before.centerZ()!=next.centerZ()||
            !(before instanceof GameplayTerrain old)||!(next instanceof GameplayTerrain grown)||(grown!=old&&!grown.isSuccessorOf(old))||
            owned.get().keySet().stream().anyMatch(c->!GameplayBlocksLedger.allowed(next,c)))throw new IllegalArgumentException("Block terrain identity or owned coverage changed");
        ledger.surface=next;surface=next;tnt.terrain(next);
    }
    public boolean ready(){return ready&&!closing&&failure.get()==null;}
    boolean worldBlocksEnabled(){return worldBlocks;}
    public GameplayTnt tnt(){return tnt;}
    UUID tntPlayerId(){return playerId;}
    boolean tntClientOwned(BlockPos position){return GameplayBlocksPalette.tntState(owned.get().get(cell(position)));}
    boolean tntOwnedCell(World source,BlockPos position){return tntOwnedCell(source,position,true);}
    boolean tntOwnedCell(World source,BlockPos position,boolean onlyTnt){
        if(server==null||!server.isOnThread()||source!=serverWorld||!serverInitialized)return false;
        var state=serverCells.get(cell(position));if(state!=null)return !onlyTnt||GameplayBlocksPalette.tntState(state);
        var request=intent.get();return onlyTnt&&request!=null&&request.dispatchedAt()>0&&request.plan().action()==1&&
            request.plan().selection().target().equals(position)&&GameplayBlocksPalette.tntState(request.plan().expectedState());
    }
    UUID tntIgniter(World source,BlockPos position,net.minecraft.entity.LivingEntity igniter){
        if(!tntOwnedCell(source,position))return null;
        if(igniter==serverPlayer&&igniter!=null)return igniter.getUuid();
        return null;
    }
    /** Explicit same-world replacement, called only from the owned AFTER_RESPAWN coordinator. */
    public void serverRespawn(ServerPlayerEntity oldPlayer,ServerPlayerEntity newPlayer){
        if(server==null||!server.isOnThread()||closing||!serverInitialized||oldPlayer!=serverPlayer||oldPlayer==newPlayer||
                oldPlayer==null||newPlayer==null||oldPlayer.isAlive()||!newPlayer.isAlive()||oldPlayer.getServer()!=server||newPlayer.getServer()!=server||
                oldPlayer.getWorld()!=serverWorld||newPlayer.getWorld()!=serverWorld||!oldPlayer.getUuid().equals(playerId)||!newPlayer.getUuid().equals(playerId)||
                oldPlayer.networkHandler!=newPlayer.networkHandler||serverRespawns!=clientRespawns)
            throw new IllegalStateException("Block respawn ownership changed");
        intent.set(null);observation.set(null);serverPlayer=newPlayer;serverRespawns++;
    }
    /** Does not reload the ledger or reinstall terrain/furnaces. No old action crosses replacement. */
    public void clientRespawn(MinecraftClient client,ClientPlayerEntity oldPlayer){
        if(!client.isOnThread()||closing||oldPlayer!=clientPlayer||oldPlayer==client.player||oldPlayer==null||oldPlayer.isAlive()||
                client.player==null||!client.player.isAlive()||client.world!=clientWorld||client.getServer()!=server||!client.isIntegratedServerRunning()||
                oldPlayer.getWorld()!=clientWorld||client.player.getWorld()!=clientWorld||!oldPlayer.getUuid().equals(playerId)||!client.player.getUuid().equals(playerId)||
                serverRespawns!=clientRespawns+1)throw new IllegalStateException("Block client respawn ownership changed");
        foodUse.suspend(client);rangedUse.suspend(client);actions=false;left=false;right=false;aim=null;pending=null;intent.set(null);dispatched=false;breakCancelled=false;
        ready=false;clientPlayer=client.player;clientRespawns=serverRespawns;lastResult="respawn_rebound";
    }
    public Set<BlockPos> ownedBlocks(){var result=new HashSet<BlockPos>();for(var c:owned.get().keySet())result.add(pos(c));return Set.copyOf(result);}
    /** Render-thread snapshot: never invent state from a palette or expose predicted unconfirmed blocks. */
    public Map<BlockPos,BlockState> ownedBlockStates(MinecraftClient client){
        if(!ready()||client.world!=clientWorld||client.player!=clientPlayer||!client.isOnThread())return Map.of();
        var result=new HashMap<BlockPos,BlockState>();
        for(var entry:owned.get().entrySet()){var position=pos(entry.getKey());var state=client.world.getBlockState(position);
            if(entry.getValue().equals(stateName(state)))result.put(position,state);}
        return Map.copyOf(result);
    }
    /** Called by the pose publisher on END_SERVER_TICK, after observe reconciles
     * confirmed ownership. Never read a client world or predict placement here. */
    public GameplayCameraCollision.Snapshot cameraCollision(MinecraftServer source,ServerPlayerEntity player){
        if(source==null||!source.isOnThread())throw new IllegalStateException("Camera collision requires server thread");
        if(!worldBlocks||closing||serverClosed||!serverInitialized||source!=server||source.getOverworld()!=serverWorld||
                player==null||player!=serverPlayer||player.getWorld()!=serverWorld)return cameraCollision.unavailable();
        var shapes=new HashMap<BlockPos,VoxelShape>();var world=source.getOverworld();var context=ShapeContext.of(player);
        for(var entry:serverCells.entrySet()){
            var position=pos(entry.getKey());if(!world.isChunkLoaded(position))return cameraCollision.unavailable();
            var state=world.getBlockState(position);
            if(!entry.getValue().equals(stateName(state))||!supported(state))return cameraCollision.unavailable();
            shapes.put(position,state.getCameraCollisionShape(world,position,context));
        }
        return cameraCollision.capture(shapes);
    }
    /** Read-only render selection, with the same reach, shape and obstruction checks as mining. */
    public BlockHitResult hoveredBlock(MinecraftClient client,Aim ray){
        if(!ready()||!actions||ray==null||!client.isOnThread()||client.world!=clientWorld||client.player!=clientPlayer||
            client.getServer()!=server||!client.isIntegratedServerRunning()||client.currentScreen!=null||client.getOverlay()!=null||client.isPaused())return null;
        var observed=observation.get();long now=System.nanoTime();
        if(observed==null||now<observed.at()||now-observed.at()>250_000_000L)return null;
        var confirmed=owned.get();
        try{
            var selected=select(client.world,client.player,ray,0,confirmed.keySet());
            return stateName(client.world.getBlockState(selected.target())).equals(confirmed.get(cell(selected.target())))?selected.hit():null;
        }catch(IllegalArgumentException rejected){return null;}
    }
    private void check(){if(files.failure()!=null)failure.compareAndSet(null,files.failure());if(tnt.failure()!=null)failure.compareAndSet(null,tnt.failure());if(failure.get()!=null)throw new IllegalStateException(failure.get());}
    public void tick(MinecraftClient client,boolean enabled){
        if(closing)return;check();if(client.world==null||client.player==null||client.getServer()==null||client.interactionManager==null)return;
        if(clientWorld==null){if(!client.isOnThread()||client.world.getRegistryKey()!=World.OVERWORLD||!client.isIntegratedServerRunning())throw new IllegalStateException("Block controller requires owned overworld");
            clientWorld=client.world;clientPlayer=client.player;playerId=client.player.getUuid();if(server!=null&&server!=client.getServer())throw new IllegalStateException("Block server changed");server=client.getServer();}
        requireClient(client);tnt.client(client);long now=System.nanoTime();var observed=observation.get();
        ready=serverInitialized&&observed!=null&&now-observed.at()<250_000_000L;
        actions=ready&&enabled&&client.player.isAlive()&&client.currentScreen==null&&client.getOverlay()==null&&!client.isPaused();
        if(!actions)suspend(client);
        if(pending!=null){
            if(!dispatched){
                if(!actions||(!left&&pending.action()==0&&!pending.creative()))finish(client,"cancelled_before_dispatch",false);
                else if(observed!=null&&observed.planId()==pending.id()&&now-observed.at()<=250_000_000L){
                    if(!observed.admitted())finish(client,observed.reason(),false);else dispatch(client,now);
                }
            }else{
                if(observed!=null&&observed.confirmed()==pending.id()){
                    if(expectedStateMatches(pending,state(client.world,pending.selection().target()))){if(pending.action()==1){places++;if(pending.selection().ground())groundPlaces++;}else if(pending.action()==WORKSTATION_USE){if(GameplayBlocksPalette.furnaceState(pending.expectedState()))furnaceOpens++;else craftingOpens++;}else if(pending.action()==TNT_IGNITE)tntIgnitions++;else{breaks++;if(!pending.creative())survivalBreaks++;}finish(client,"confirmed",true);}
                }
                if(pending!=null&&pending.action()==0&&!pending.creative()){
                    if(!actions||!left||!sameCurrentTarget(client,pending)){if(!breakCancelled){client.interactionManager.cancelBlockBreaking();breakCancelled=true;}}
                    else client.interactionManager.updateBlockBreakingProgress(pending.selection().target(),pending.selection().hit().getSide());
                }
            }
            if(pending!=null&&now-pending.at()>(pending.action()==0&&!pending.creative()&&!breakCancelled?30_000_000_000L:2_000_000_000L))finish(client,"vanilla_rejected_or_cancelled",false);
        }
        foodUse.tick(client,actions&&pending==null);
        rangedUse.tick(client,actions&&pending==null&&foodAuthority(client));
        if(actions&&pending==null&&now-lastDispatch>=250_000_000L){if(left)queue(client,0);else if(right)queue(client,1);}
    }
    public void event(MinecraftClient client,HudInputProtocol.Event event){
        if(event.kind()!=7&&event.kind()!=8)throw new IllegalArgumentException("Expected world button edge");if(event.code()<0||event.code()>1)throw new IllegalArgumentException("World button");
        if(closing)return;boolean down=event.kind()==7;
        // Vanilla block use precedes food use unless sneaking with a held item.
        // A valid workstation hit opens its actual handler even while holding food.
        boolean workstationPress=down&&event.code()==1&&actions&&pending==null&&!left&&workstationTarget(client);
        if(!workstationPress&&foodUse.event(client,event,actions&&pending==null&&!left&&foodAuthority(client))){right=false;return;}
        if(!workstationPress&&rangedUse.event(client,event,actions&&pending==null&&!left&&foodAuthority(client))){right=false;return;}
        if(workstationPress){foodUse.suspend(client);rangedUse.suspend(client);}
        if(down&&event.code()==0){foodUse.suspend(client);rangedUse.suspend(client);}
        if(event.code()==0)left=down;else right=down;
        if(down&&actions&&pending==null)queue(client,event.code());
        if(!down&&event.code()==0&&dispatched&&pending!=null&&pending.action()==0&&!pending.creative()&&client.interactionManager!=null){client.interactionManager.cancelBlockBreaking();breakCancelled=true;}
    }
    public void suspend(MinecraftClient client){actions=false;left=false;right=false;foodUse.suspend(client);rangedUse.suspend(client);if(client.interactionManager!=null&&pending!=null&&pending.action()==0&&dispatched&&!breakCancelled){client.interactionManager.cancelBlockBreaking();breakCancelled=true;}}
    /** Recheck input/owner authority before vanilla has an opportunity to continue a held meal. */
    public void beforeTick(MinecraftClient client,boolean enabled){boolean allowed=enabled&&actions&&pending==null&&foodAuthority(client);foodUse.tick(client,allowed);rangedUse.tick(client,allowed);}
    public boolean interceptVanillaItemStop(MinecraftClient client,boolean authorityFresh){boolean allowed=authorityFresh&&actions&&pending==null&&foodAuthority(client);return rangedUse.interceptVanillaStop(client,allowed)||foodUse.preserve(client,allowed);}
    private boolean foodAuthority(MinecraftClient client){
        if(closing||!ready()||!client.isOnThread()||client.world!=clientWorld||client.player!=clientPlayer||client.getServer()!=server||!client.isIntegratedServerRunning())return false;
        var observed=observation.get();long now=System.nanoTime();return observed!=null&&now>=observed.at()&&now-observed.at()<=250_000_000L;
    }
    private void queue(MinecraftClient client,int action){
        var current=aim;long now=System.nanoTime();lastDispatch=now;if(current==null||!current.fresh(System.currentTimeMillis(),now)){rejections++;lastResult="aim_stale";return;}
        try{
            if(action==1&&workstationTarget(client))action=WORKSTATION_USE;
            else if(action==1&&tntTarget(client))action=TNT_IGNITE;
            var selected=select(client.world,client.player,current,action,owned.get().keySet());
            if(action==1&&!owned.get().containsKey(cell(selected.target()))&&owned.get().size()>=GameplayBlocksLedger.MAX_BLOCKS){rejections++;lastResult="block_capacity";return;}
            var expected=action==1?placementState(client.player,selected):action==WORKSTATION_USE?state(client.world,selected.target()):"minecraft:air";
            int slot=client.player.getInventory().selectedSlot;var stack=client.player.getInventory().getStack(slot);
            pending=new Plan(++ids,action,current,selected,slot,Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount(),client.player.isCreative(),expected,now);
            dispatched=false;breakCancelled=false;intent.set(new Intent(pending,0));lastResult="awaiting_server";
        }catch(IllegalArgumentException rejected){rejections++;lastResult=rejected.getMessage();}
    }
    private void dispatch(MinecraftClient client,long now){
        try{
            var p=pending;if(!p.aim().fresh(System.currentTimeMillis(),now))throw new IllegalArgumentException("aim_expired_before_dispatch");
            var selected=select(client.world,client.player,p.aim(),p.action(),owned.get().keySet());
            if(!same(selected,p.selection())||!sameStack(client.player,p)||(p.action()==1&&!placementState(client.player,selected).equals(p.expectedState()))||
                (p.action()==WORKSTATION_USE&&!expectedStateMatches(p,state(client.world,selected.target()))))throw new IllegalArgumentException("selection_or_stack_changed");
            // Pinned CraftingTableBlock/AbstractFurnaceBlock.onUse return SUCCESS
            // on the client and open their actual server handlers. interactBlock
            // sends the ordinary packet; recipes, fuel and slots remain vanilla.
            // Source: runtime/evidence/{crafting,furnace}-source-20261108/.
            boolean accepted=p.action()!=0?client.interactionManager.interactBlock(client.player,Hand.MAIN_HAND,p.selection().hit()).isAccepted():client.interactionManager.attackBlock(p.selection().target(),p.selection().hit().getSide());
            if(!accepted){finish(client,"vanilla_dispatch_rejected",false);return;}
            dispatched=true;dispatchedAt=System.nanoTime();lastDispatch=dispatchedAt;intent.set(new Intent(p,dispatchedAt));lastResult="awaiting_confirmation";
        }catch(IllegalArgumentException rejected){finish(client,rejected.getMessage(),false);}
    }
    private boolean sameCurrentTarget(MinecraftClient client,Plan p){try{return aim!=null&&aim.fresh(System.currentTimeMillis(),System.nanoTime())&&select(client.world,client.player,aim,0,owned.get().keySet()).target().equals(p.selection().target());}catch(IllegalArgumentException e){return false;}}
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
        if(action==WORKSTATION_USE&&(!worldBlocks||!blockUseAllowed(player)||player.currentScreenHandler!=player.playerScreenHandler))throw new IllegalArgumentException("workstation_unavailable");
        if(action==TNT_IGNITE&&(!worldBlocks||!tnt.canPrime()||!ignitionItem(player)||player.currentScreenHandler!=player.playerScreenHandler))throw new IllegalArgumentException("tnt_ignition_unavailable");
        if(!ray.obstructionKnown()||!ray.fresh(System.currentTimeMillis(),System.nanoTime()))throw new IllegalArgumentException("aim_unavailable");
        if(ray.origin().distanceTo(player.getEyePos())>.35)throw new IllegalArgumentException("eye_disagrees");
        var end=ray.origin().add(ray.direction().multiply(ray.range()));
        var hit=world.raycast(new RaycastContext(ray.origin(),end,RaycastContext.ShapeType.OUTLINE,RaycastContext.FluidHandling.NONE,player));
        if(hit.getType()==HitResult.Type.BLOCK&&!terrainPrecedesBlock(action,ray,hit.getPos().distanceTo(ray.origin()))){
            if(!cells.contains(cell(hit.getBlockPos()))||!supported(world.getBlockState(hit.getBlockPos())))throw new IllegalArgumentException("unowned_target");
            double distance=hit.getPos().distanceTo(ray.origin());
            if(ray.obstructionDistance()>=0&&ray.obstructionDistance()<distance-.05)throw new IllegalArgumentException("native_obstruction");
            requireCameraVisibility(world,player,ray,hit.getPos(),cells);
            if(action==WORKSTATION_USE&&!workstation(world.getBlockState(hit.getBlockPos())))throw new IllegalArgumentException("not_supported_workstation");
            if(action==TNT_IGNITE&&!world.getBlockState(hit.getBlockPos()).isOf(Blocks.TNT))throw new IllegalArgumentException("not_owned_tnt");
            if(action==1&&worldBlocks&&workstation(world.getBlockState(hit.getBlockPos()))&&blockUseAllowed(player))throw new IllegalArgumentException("workstation_action_changed");
            // Vanilla chooses the replaceable hit cell for a slab merge, otherwise
            // its adjacent cell. Never assume every placement offsets a full cube.
            var target=action==1?new ItemPlacementContext(player,Hand.MAIN_HAND,player.getMainHandStack(),hit).getBlockPos():hit.getBlockPos();validateTarget(world,player,target,action,cells);
            return new Selection(target.toImmutable(),hit,false);
        }
        if(action!=1||!ray.terrainHit()||ray.obstructionDistance()<0)throw new IllegalArgumentException("no_owned_block_hit");
        var point=ray.origin().add(ray.direction().multiply(ray.obstructionDistance()));
        requireCameraVisibility(world,player,ray,point,cells);
        if(!surface.containsFeet(point.x,point.z,.001)||Math.abs(surface.heightAt(point.x,point.z)-point.y)>.65)throw new IllegalArgumentException("terrain_hit_outside_capture");
        var target=BlockPos.ofFloored(point);
        var groundHit=new BlockHitResult(point,Direction.UP,target,false);
        if(worldBlocks&&player.getMainHandStack().getItem() instanceof BlockItem item){
            var context=new ItemPlacementContext(player,Hand.MAIN_HAND,player.getMainHandStack(),groundHit);
            var candidate=item.getBlock().getPlacementState(context);
            var component=player.getMainHandStack().get(DataComponentTypes.BLOCK_STATE);
            if(candidate!=null&&component!=null)candidate=component.applyToState(candidate);
            if(candidate!=null&&supported(candidate)){
                var shape=candidate.getOutlineShape(world,target,ShapeContext.of(player));
                // A fractional heightfield can cover an entire bottom slab in
                // the floored cell. Keep vanilla half/facing and obstruction
                // rules; use the next grid cell only for a buried candidate.
                double ground=Math.max(point.y,surface.heightAt(point.x,point.z));
                if(!shape.isEmpty()&&shape.getMax(Direction.Axis.Y)<1&&target.getY()+shape.getMax(Direction.Axis.Y)<=ground+.05){
                    target=target.up();
                    if(target.getY()+shape.getMax(Direction.Axis.Y)<=ground+.05)throw new IllegalArgumentException("terrain_covers_placement");
                    groundHit=new BlockHitResult(new Vec3d(point.x,target.getY(),point.z),Direction.UP,target,false);
                }
            }
        }
        validateTarget(world,player,target,1,cells);
        // Inspected Yarn1.21.1 ItemPlacementContext replaces a clicked AIR cell;
        // PlayerInteractBlock's usual reach/collision/mode checks remain vanilla.
        // This user-placed block can overlap the sampled slab; breaking it restores AIR.
        return new Selection(target,groundHit,true);
    }
    /** Placement uses the nearest known surface. A farther Minecraft block must
     * not hide captured ground; the normal ground branch still validates its
     * coverage, height, camera visibility, reach and placement collision. */
    static boolean terrainPrecedesBlock(int action,Aim ray,double blockDistance){
        return action==1&&ray.terrainHit()&&ray.obstructionKnown()&&ray.obstructionDistance()>=0&&
            Double.isFinite(blockDistance)&&ray.obstructionDistance()<blockDistance-.05;
    }
    private boolean workstationTarget(MinecraftClient client){
        if(!worldBlocks||aim==null||client.player==null||client.world==null)return false;
        try{select(client.world,client.player,aim,WORKSTATION_USE,owned.get().keySet());return true;}
        catch(IllegalArgumentException rejected){return false;}
    }
    private boolean tntTarget(MinecraftClient client){
        if(!worldBlocks||aim==null||client.player==null||client.world==null||!ignitionItem(client.player))return false;
        try{select(client.world,client.player,aim,TNT_IGNITE,owned.get().keySet());return true;}
        catch(IllegalArgumentException rejected){return false;}
    }
    private static boolean ignitionItem(PlayerEntity player){var stack=player.getMainHandStack();return stack.isOf(Items.FLINT_AND_STEEL)||stack.isOf(Items.FIRE_CHARGE);}
    private static boolean workstation(BlockState state){return state.isOf(Blocks.CRAFTING_TABLE)||state.isOf(Blocks.FURNACE);}
    private static boolean expectedStateMatches(Plan plan,String actual){
        return plan.expectedState().equals(actual)||(plan.action()==WORKSTATION_USE&&GameplayBlocksPalette.sameFurnace(plan.expectedState(),actual));
    }
    /** Pinned interactBlockInternal cancels block use only while sneaking with
     * an item in either hand; sneaking with both hands empty still uses a workstation. */
    private static boolean blockUseAllowed(PlayerEntity player){
        return !player.shouldCancelInteraction()||(player.getMainHandStack().isEmpty()&&player.getOffHandStack().isEmpty());
    }
    private void requireCameraVisibility(World world,PlayerEntity player,Aim ray,Vec3d target,Set<GameplayBlocksLedger.Cell> cells){
        if(!worldBlocks||ray.cameraOrigin().squaredDistanceTo(ray.origin())<1e-12)return;
        var context=ShapeContext.of(player);
        for(var cell:cells){var position=pos(cell);
            if(!world.isChunkLoaded(position))continue;
            var shape=world.getBlockState(position).getOutlineShape(world,position,context);
            if(cameraOccludes(ray,target,position,shape))throw new IllegalArgumentException("camera_obstruction");
        }
    }
    /** Pinned Yarn1.21.1 VoxelShape.raycast tests the actual voxel boxes and
     * reports a start inside solid geometry. Use the same outline shape as the
     * renderer, not a cell-sized cube (slabs/fence gaps must remain visible).
     * This rejects hidden eye hits; it never extends the 4.5m eye interaction ray. */
    static boolean cameraOccludes(Aim ray,Vec3d target,BlockPos position,VoxelShape shape){
        if(ray.cameraOrigin().squaredDistanceTo(ray.origin())<1e-12)return false;
        var hit=shape.raycast(ray.cameraOrigin(),target,position);
        return hit!=null&&(hit.isInsideBlock()||hit.getPos().distanceTo(ray.cameraOrigin())<target.distanceTo(ray.cameraOrigin())-.0001);
    }
    private void validateTarget(World world,PlayerEntity player,BlockPos target,int action,Set<GameplayBlocksLedger.Cell> cells){
        if(!GameplayBlocksLedger.allowed(surface,cell(target))||!world.isChunkLoaded(target)||!player.canInteractWithBlockAt(target,0))throw new IllegalArgumentException("outside_build_coverage_or_reach");
        if(action==1){if(!world.getBlockState(target).isAir()&&(!cells.contains(cell(target))||!supported(world.getBlockState(target))))throw new IllegalArgumentException("occupied_target");}
        else if(!cells.contains(cell(target))||!supported(world.getBlockState(target)))throw new IllegalArgumentException("unowned_target");
        if(world.getBlockState(target).isOf(Blocks.FURNACE)&&!(world.getBlockEntity(target) instanceof FurnaceBlockEntity))throw new IllegalArgumentException("missing_vanilla_furnace");
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
                if(serverCells.keySet().stream().anyMatch(c->!world.isChunkLoaded(pos(c))))return;
                boolean reconciled=false;for(var entry:new ArrayList<>(serverCells.entrySet())){var s=state(world,pos(entry.getKey()));
                    if(s.equals("minecraft:air")){serverCells.remove(entry.getKey());reconciled=true;}
                    else{
                        // Vanilla may tick fuel after the last ownership snapshot
                        // but before saving the world. Only LIT can differ on reopen.
                        if(!s.equals(entry.getValue())){
                            if(!GameplayBlocksPalette.sameFurnace(entry.getValue(),s))throw new IllegalStateException("Saved owned block state changed outside session");
                            serverCells.put(entry.getKey(),s);reconciled=true;
                        }
                        if(GameplayBlocksPalette.furnaceState(s))retainFurnace(world,entry.getKey());
                    }}
                if(reconciled)revision++;owned.set(Map.copyOf(serverCells));serverInitialized=true;
            }
            var request=intent.get();long planId=0;boolean admitted=false;String reason="no_request",targetState="unknown";
            if(playerId!=null){var player=source.getPlayerManager().getPlayer(playerId);if(player==null||player.getWorld()!=world)throw new IllegalStateException("Block player changed");
                if(serverPlayer==null)serverPlayer=player;if(serverPlayer!=player)throw new IllegalStateException("Block player identity changed");
                foodUse.observe(player);
                rangedUse.observe(player);
                if(request!=null){var plan=request.plan();planId=plan.id();targetState=state(world,plan.selection().target());
                    if(request.dispatchedAt()==0){try{var selected=select(world,player,plan.aim(),plan.action(),Set.copyOf(serverCells.keySet()));
                        admitted=same(selected,plan.selection())&&sameStack(player,plan)&&(plan.action()!=1||placementState(player,selected).equals(plan.expectedState()))&&
                            (plan.action()!=WORKSTATION_USE||expectedStateMatches(plan,targetState));reason=admitted?"admitted":"server_selection_or_stack_changed";
                    }catch(IllegalArgumentException rejected){reason=rejected.getMessage();}}
                    else if(confirmed<plan.id()&&expectedStateMatches(plan,targetState)&&(plan.action()!=TNT_IGNITE||tnt.primedAt(world,plan.selection().target(),plan.at()))){
                        if(plan.action()==WORKSTATION_USE){
                            if(plan.expectedState().equals("minecraft:crafting_table")?player.currentScreenHandler instanceof CraftingScreenHandler:player.currentScreenHandler instanceof FurnaceScreenHandler)confirmed=plan.id();
                        }else{
                            if(plan.action()==1)serverCells.put(cell(plan.selection().target()),targetState);else{serverCells.remove(cell(plan.selection().target()));serverFurnaces.remove(cell(plan.selection().target()));}revision++;confirmed=plan.id();owned.set(Map.copyOf(serverCells));
                        }
                    }
                }
            }
            // Vanilla remains authoritative even if another allowed action (for
            // example a command) removes or changes an already-owned block.
            boolean reconciled=false;
            for(var entry:new ArrayList<>(serverCells.entrySet())){
                var c=entry.getKey();if(!world.isChunkLoaded(pos(c)))throw new IllegalStateException("Owned block chunk unloaded");
                var value=state(world,pos(c));
                if(value.equals("minecraft:air")){serverCells.remove(c);serverFurnaces.remove(c);reconciled=true;}
                else if(!supported(world.getBlockState(pos(c))))throw new IllegalStateException("Owned block changed to unsupported block");
                else{
                    boolean furnace=GameplayBlocksPalette.furnaceState(value);
                    if((furnace||GameplayBlocksPalette.furnaceState(entry.getValue()))&&!GameplayBlocksPalette.sameFurnace(entry.getValue(),value))throw new IllegalStateException("Owned furnace identity changed");
                    if(furnace)retainFurnace(world,c);
                    if(!value.equals(entry.getValue())){serverCells.put(c,value);reconciled=true;}
                }
            }
            if(reconciled){revision++;owned.set(Map.copyOf(serverCells));}
            tnt.observe(source);
            long utc=System.currentTimeMillis(),now=System.nanoTime();var cells=Map.copyOf(serverCells);
            observation.set(new Observation(now,utc,planId,admitted,reason,targetState,confirmed,cells));publish(utc,cells);
            if(closing&&now-closeAt>=150_000_000L){serverClosed=true;files.close();}
        }catch(Exception error){failure.compareAndSet(null,error.toString());if(closing){serverClosed=true;files.close();}}
    }
    private void retainFurnace(World world,GameplayBlocksLedger.Cell cell){
        if(!(world.getBlockEntity(pos(cell)) instanceof FurnaceBlockEntity furnace))throw new IllegalStateException("Owned furnace block entity missing");
        var previous=serverFurnaces.putIfAbsent(cell,furnace);
        if(previous!=null&&previous!=furnace)throw new IllegalStateException("Owned furnace block entity replaced");
    }
    private void publish(long utc,Map<GameplayBlocksLedger.Cell,String> cells){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_blocks_v1");j.addProperty("run",identity.run());j.addProperty("world_id",save.id().toString());
        j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));j.addProperty("patch_run",surface.run());j.addProperty("patch_sha256",surface.sha256());
        j.addProperty("seq",++serverSequence);j.addProperty("utc_ms",utc);j.addProperty("revision",revision);j.add("blocks",GameplayBlocksLedger.blocks(cells));files.publish(revision,cells,j.toString());
    }
    public boolean terrainCellAllowed(BlockView world,BlockPos position,boolean serverSide){
        if(world.getBlockState(position).isAir())return true;if(!supported(world.getBlockState(position)))return false;
        var c=cell(position);if(owned.get().containsKey(c))return true;var p=intent.get();return p!=null&&p.plan().action()==1&&p.plan().selection().target().equals(position)&&p.plan().expectedState().equals(state(world,position));
    }
    public double groundForFeet(BlockView world,double x,double y,double z,double half){
        double result=surface.groundForFeet(x,z,half);var candidates=new HashSet<>(owned.get().keySet());var p=intent.get();if(p!=null&&p.plan().action()==1)candidates.add(cell(p.plan().selection().target()));
        for(var c:candidates){var position=pos(c);var state=world.getBlockState(position);
            if(x+half<=c.x()||x-half>=c.x()+1||z+half<=c.z()||z-half>=c.z()+1||!supported(state))continue;
            // Same vanilla collision boxes used by the player, including the
            // captured ground union. Stairs can support different heights within
            // one cell; a slab's empty half is not a full-cube support surface.
            for(var box:state.getCollisionShape(world,position).getBoundingBoxes())
                if(c.y()+box.maxY<=y+.2&&x+half>c.x()+box.minX&&x-half<c.x()+box.maxX&&z+half>c.z()+box.minZ&&z-half<c.z()+box.maxZ)
                    result=Math.max(result,c.y()+box.maxY);
        }
        return result;
    }
    public void close(MinecraftClient client){if(closing)return;suspend(client);tnt.close();closing=true;closeAt=System.nanoTime();if(server==null||!serverInitialized){serverClosed=true;files.close();}}
    public boolean cleanupComplete(){return closing&&serverClosed&&files.finished()&&files.failure()==null&&tnt.cleanupComplete();}
    public JsonObject evidence(MinecraftClient client){var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_blocks_controller_v1");j.addProperty("run",identity.run());j.addProperty("world_id",save.id().toString());
        j.addProperty("ready",ready);j.addProperty("revision",revision);j.addProperty("owned_count",owned.get().size());j.add("blocks",GameplayBlocksLedger.blocks(owned.get()));
        j.addProperty("places",places);j.addProperty("breaks",breaks);j.addProperty("ground_places",groundPlaces);j.addProperty("rejections",rejections);j.addProperty("cancellations",cancellations);j.addProperty("last_result",lastResult);
        j.addProperty("survival_breaks",survivalBreaks);j.addProperty("survival_preserved_ticks",survivalPreservedTicks);
        j.addProperty("crafting_opens",craftingOpens);j.addProperty("furnace_opens",furnaceOpens);
        j.addProperty("tnt_ignitions",tntIgnitions);j.add("tnt",tnt.evidence());
        j.addProperty("server_respawns",serverRespawns);j.addProperty("client_respawns",clientRespawns);
        j.add("food_use",foodUse.evidence(client));
        j.add("ranged_use",rangedUse.evidence());
        j.addProperty("world_blocks",worldBlocks);
        j.addProperty("pending",pending!=null);j.addProperty("snapshot_writes",files.writes());j.addProperty("persisted_revision",files.persistedRevision());j.addProperty("cleanup_complete",cleanupComplete());j.addProperty("controls_released",!left&&!right);
        j.addProperty("minecraft_blocks_removed_on_stop",0);j.addProperty("failure",failure.get()!=null?failure.get():files.failure());return j;}
    private void requireClient(MinecraftClient c){if(!c.isOnThread()||c.world!=clientWorld||c.player!=clientPlayer||c.getServer()!=server||!c.isIntegratedServerRunning())throw new IllegalStateException("Block client owner changed");}
    private static boolean same(Selection a,Selection b){return a.target().equals(b.target())&&a.hit().getBlockPos().equals(b.hit().getBlockPos())&&a.hit().getSide()==b.hit().getSide()&&a.ground()==b.ground()&&a.hit().getPos().squaredDistanceTo(b.hit().getPos())<1e-8;}
    private static boolean sameStack(PlayerEntity p,Plan plan){var stack=p.getInventory().getStack(plan.slot());return p.getInventory().selectedSlot==plan.slot()&&Registries.ITEM.getId(stack.getItem()).toString().equals(plan.item())&&stack.getCount()==plan.count();}
    private static boolean finite(Vec3d v){return Double.isFinite(v.x)&&Double.isFinite(v.y)&&Double.isFinite(v.z);}
    private boolean supported(BlockState state){return worldBlocks?GameplayBlocksPalette.supportsState(stateName(state)):state.isOf(Blocks.STONE);}
    private String placementState(PlayerEntity player,Selection selected){
        var stack=player.getMainHandStack();
        if(!(stack.getItem() instanceof BlockItem item)||(!worldBlocks&&!stack.isOf(Items.STONE))||
            (worldBlocks&&!GameplayBlocksPalette.supportsBlock(Registries.BLOCK.getId(item.getBlock()).toString())))throw new IllegalArgumentException("unsupported_block_item");
        // Pinned ItemPlacementContext/BlockItem placement: replacement, half,
        // facing, stair neighbors and collision stay under vanilla control.
        // See runtime/evidence/block-shapes-source-20261106.
        var context=new ItemPlacementContext(player,Hand.MAIN_HAND,stack,selected.hit());
        if(!context.canPlace())throw new IllegalArgumentException("occupied_target");
        var state=item.getBlock().getPlacementState(context);
        if(state==null||!state.canPlaceAt(player.getWorld(),context.getBlockPos())||!player.getWorld().canPlace(state,context.getBlockPos(),ShapeContext.of(player)))throw new IllegalArgumentException("vanilla_placement_collision");
        // Pinned BlockItem.placeFromNbt applies BLOCK_STATE after ordinary
        // placement (runtime/evidence/world-blocks-source-20261106/BlockItem.txt).
        // Predict that same vanilla override, including command-created log axes.
        var component=stack.get(DataComponentTypes.BLOCK_STATE);
        if(state!=null&&component!=null)state=component.applyToState(state);
        if(!context.getBlockPos().equals(selected.target())||state==null||!supported(state))throw new IllegalArgumentException("unsupported_placement_state");
        // Command-created state components can change geometry after vanilla's
        // initial collision check; never admit an overridden shape inside an entity.
        if(!player.getWorld().canPlace(state,selected.target(),ShapeContext.of(player)))throw new IllegalArgumentException("vanilla_placement_collision");
        return stateName(state);
    }
    private static String state(BlockView world,BlockPos p){return stateName(world.getBlockState(p));}
    public static String stateName(BlockState state){
        if(state.isAir())return "minecraft:air";
        var name=new StringBuilder(Registries.BLOCK.getId(state.getBlock()).toString());
        if(!state.getEntries().isEmpty()){
            var values=new TreeMap<String,String>();
            for(var entry:state.getEntries().entrySet())values.put(entry.getKey().getName(),propertyName(entry.getKey(),entry.getValue()));
            name.append('[');boolean first=true;for(var entry:values.entrySet()){if(!first)name.append(',');first=false;name.append(entry.getKey()).append('=').append(entry.getValue());}name.append(']');
        }
        return name.toString();
    }
    @SuppressWarnings({"rawtypes","unchecked"})
    private static String propertyName(net.minecraft.state.property.Property property,Comparable value){return property.name(value);}
    private static GameplayBlocksLedger.Cell cell(BlockPos p){return new GameplayBlocksLedger.Cell(p.getX(),p.getY(),p.getZ());}
    private static BlockPos pos(GameplayBlocksLedger.Cell c){return new BlockPos(c.x(),c.y(),c.z());}
}
