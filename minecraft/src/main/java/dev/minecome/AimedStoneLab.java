package dev.minecome;

import com.google.gson.*;
import com.sun.jna.platform.win32.Kernel32;
import com.sun.jna.platform.win32.WinBase;
import dev.minecome.aim.AimedStoneArena;
import dev.minecome.protocol.AimGeometry;
import dev.minecome.protocol.Protocol;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.GameMenuScreen;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.resource.DataConfiguration;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.*;
import net.minecraft.world.gen.GeneratorOptions;
import net.minecraft.world.gen.WorldPresets;
import net.minecraft.world.level.LevelInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;

/** Opt-in, standalone real-Minecraft fixture. It never creates a transport or accesses KCD. */
public final class AimedStoneLab {
    private static final Logger LOG=LoggerFactory.getLogger("MineComeAimedStone");
    private static final AimGeometry.Alignment ALIGNMENT=new AimGeometry.Alignment(new Protocol.Vec3(0,0,0),new Protocol.Vec3(0,0,0),1);
    private static final int PLACE=Protocol.PLACE_STONE,BREAK=Protocol.BREAK_STONE;
    private record Step(String name,Vec3d eye,BlockPos aimedCell,BlockPos expectedCell,Direction face,int action,boolean dispatch,boolean allowed,String rayMode,boolean turn) {}
    private record TeleportProof(long number,Vec3d eye) {}
    private final String run,save;
    private final Path directory;
    private final AimedStoneArena arena=new AimedStoneArena(ALIGNMENT);
    private final JsonArray checks=new JsonArray(),teleports=new JsonArray();
    private final AtomicReference<TeleportProof> teleportProof=new AtomicReference<>();
    private final AtomicReference<String> serverFailure=new AtomicReference<>();
    private final AtomicReference<Set<BlockPos>> finalAir=new AtomicReference<>();
    private final AtomicReference<Set<BlockPos>> cancelledOwnedProof=new AtomicReference<>();
    private final Set<BlockPos> everPlaced=new LinkedHashSet<>();
    private final long initializedAt=System.nanoTime();
    private final int producerPid;
    private final String producerStart;
    private Object worldIdentity,serverIdentity;
    private boolean started,inventoryGiven,bootstrapQueued,bootstrapConfirmed,finished,stopping;
    private Boolean previousPause;
    private Integer previousFps;
    private long worldAt,inventoryAt,stepAt,teleportNumber,requestId;
    private int stepIndex;
    private List<Step> steps;
    private Step current;
    private AimedStoneArena.Selection selected;
    private AimedStoneArena.HostRay selectedRay;
    private long selectionAge;
    private boolean teleported,queued;
    private boolean finalReadRequested;
    private String failure="";

    private AimedStoneLab(String run,Path directory) throws Exception {
        this.run=run;this.directory=directory;
        save="MineCome-AimedStone-"+UUID.fromString(run.substring(0,8)+"-"+run.substring(8,12)+"-"+run.substring(12,16)+"-"+run.substring(16,20)+"-"+run.substring(20));
        var api=Kernel32.INSTANCE;producerPid=api.GetCurrentProcessId();
        var creation=new WinBase.FILETIME();
        if(!api.GetProcessTimes(api.GetCurrentProcess(),creation,new WinBase.FILETIME(),new WinBase.FILETIME(),new WinBase.FILETIME()))throw new IllegalStateException("Cannot identify actual Java process");
        producerStart=Long.toUnsignedString((Integer.toUnsignedLong(creation.dwHighDateTime)<<32)|Integer.toUnsignedLong(creation.dwLowDateTime));
        write("aimed-ready.json",identity());
    }
    public static void initialize() {
        if(!Boolean.getBoolean("minecome.aimedStoneLab"))return;
        try {
            String run=System.getProperty("minecome.aimedStoneRun","");
            if(!run.matches("[0-9a-f]{32}"))throw new IllegalArgumentException("Explicit aimed fixture run required");
            Path directory=Path.of(System.getProperty("minecome.aimedStoneDirectory","")).toAbsolutePath().normalize();
            Path root=MinecraftClient.getInstance().runDirectory.toPath().toAbsolutePath().normalize().getParent().getParent();
            if(!directory.startsWith(root.resolve("runtime/evidence")) || !Files.isDirectory(directory))throw new IllegalArgumentException("Existing workspace evidence directory required");
            var lab=new AimedStoneLab(run,directory);
            ClientTickEvents.END_CLIENT_TICK.register(lab::tick);
            ClientLifecycleEvents.CLIENT_STOPPING.register(lab::stopping);
            LOG.info("AIMED_STONE_INITIALIZED run={} standaloneActualMinecraft=true syntheticHostRays=true kcdConnected=false",run);
        }catch(Exception e){throw new IllegalStateException("Cannot initialize isolated aimed stone fixture",e);}
    }
    private void tick(MinecraftClient client) {
        if(stopping)return;
        try { advance(client); }
        catch(Exception e){fail(client,e.getClass().getSimpleName()+": "+e.getMessage());}
    }
    private void advance(MinecraftClient client) throws Exception {
        long now=System.nanoTime();
        if(Files.exists(directory.resolve("stop.request"))){fail(client,"Controller requested standalone stop");return;}
        if(now-initializedAt>150_000_000_000L){fail(client,"150-second standalone deadline reached");return;}
        if(!started && client.currentScreen!=null && client.getOverlay()==null)create(client);
        if(client.world==null || client.player==null || !client.isIntegratedServerRunning()) {
            if(worldIdentity!=null)fail(client,"Owned Minecraft world disconnected");return;
        }
        if(!owned(client)) {fail(client,"Owned save/server/world identity changed");return;}
        if(worldIdentity==null){worldIdentity=client.world;serverIdentity=client.getServer();worldAt=now;}
        if(client.currentScreen instanceof GameMenuScreen)client.setScreen(null);
        if(client.currentScreen!=null || client.getOverlay()!=null)return;
        if(serverFailure.get()!=null){fail(client,serverFailure.get());return;}
        if(!inventoryGiven) {
            if(now-worldAt<2_000_000_000L || !client.player.isOnGround())return;
            var stone=new ItemStack(Blocks.STONE,64);int slot=client.player.getInventory().selectedSlot;
            client.player.getInventory().setStack(slot,stone);client.interactionManager.clickCreativeStack(stone,36+slot);
            inventoryGiven=true;inventoryAt=now;
        }
        arena.tick(client);
        if(arena.failed()){fail(client,"Aimed arena failed: "+arena.failure());return;}
        if(!arena.ready() || now-inventoryAt<500_000_000L)return;
        if(!bootstrapQueued) {
            var decision=arena.bootstrap(client,++requestId);
            require(decision.queued(),"Vanilla bootstrap refused: "+decision.reason());
            bootstrapQueued=true;stepAt=now;return;
        }
        if(!bootstrapConfirmed) {
            if(arena.pending()) {require(now-stepAt<5_000_000_000L,"Bootstrap confirmation deadline");return;}
            var result=arena.lastResult();
            require(result!=null && result.id()==requestId && result.status().equals("confirmed") && result.clientAndServer(),"Bootstrap lacks client/server proof");
            bootstrapConfirmed=true;steps=steps(arena.seedCell());
            everPlaced.add(arena.seedCell());
            LOG.info("AIMED_STONE_READY run={} save={} seed={} scenarios={}",run,save,arena.seedCell(),steps.size());
        }
        if(stepIndex>=steps.size()) {
            require(!arena.pending(),"Pending action remains at completion");
            require(arena.ownedCells().isEmpty(),"Confirmed owned stones remain at completion");
            if(!finalReadRequested){
                finalReadRequested=true;var cells=Set.copyOf(everPlaced);var server=client.getServer();
                server.execute(()->{try{
                    require(server==serverIdentity && save.equals(server.getSaveProperties().getLevelName()),"Final cleanup server identity differs");
                    var world=server.getOverworld();for(var cell:cells)require(world.isChunkLoaded(cell) && world.getBlockState(cell).isAir(),"Final authoritative cleanup incomplete");
                    finalAir.set(cells);
                }catch(Exception e){serverFailure.set(e.getMessage());}});return;
            }
            if(finalAir.get()==null)return;
            require(finalAir.get().equals(everPlaced) && everPlaced.size()==4,"Final authoritative cleanup cells differ");
            for(var cell:everPlaced)require(client.world.isChunkLoaded(cell) && client.world.getBlockState(cell).isAir(),"Final client cleanup incomplete");
            finish(client,"passed");return;
        }
        if(current==null) {
            current=steps.get(stepIndex);stepAt=now;teleported=false;queued=false;selected=null;
            requestTeleport(client,current.eye(),center(current.aimedCell()));return;
        }
        require(now-stepAt<6_000_000_000L,"Scenario deadline: "+current.name());
        if(!teleported) {
            var proof=teleportProof.get();
            if(proof==null || proof.number()!=teleportNumber || client.player.getEyePos().squaredDistanceTo(proof.eye())>0.0025)return;
            client.player.setVelocity(Vec3d.ZERO);
            var record=new JsonObject();record.addProperty("scenario",current.name());record.addProperty("client_server_eye_agreed",true);record.add("eye",vector(client.player.getEyePos()));teleports.add(record);
            teleported=true;return;
        }
        if(selected==null) {
            var ray=ray(client,current);selectedRay=ray;selectionAge=System.nanoTime()-ray.capturedAtNanos();
            selected=arena.select(client,current.action(),ray);
            require(selected.allowed()==current.allowed(),current.name()+": selection="+selected.allowed()+" reason="+selected.reason());
            if(!current.allowed())require(selected.reason().equals(expectedRejection(current.rayMode())),current.name()+": unrelated rejection: "+selected.reason());
            if(selected.allowed()) {
                require(selected.target().equals(current.expectedCell()),current.name()+": wrong immutable target "+selected.target());
                require(selected.hit().side()==current.face(),current.name()+": wrong vanilla face "+selected.hit().side());
            }
            if(current.name().equals("cancel_before_dispatch")) {
                var ownedBefore=arena.ownedCells();int confirmations=arena.evidence().getAsJsonArray("confirmations").size();
                var decision=arena.request(client,++requestId,current.action(),ray);
                require(decision.queued(),"Cancellation case must first queue a valid vanilla action");
                // No further client tick/dispatch occurs between queueing and revocation.
                arena.tick(client,false);
                var result=arena.lastResult();
                require(!arena.pending() && result.id()==requestId && result.status().equals("rejected")
                        && result.reason().equals("actions_disabled_before_dispatch") && !result.clientAndServer(),"Revoked action was not cancelled");
                require(arena.ownedCells().equals(ownedBefore) && arena.evidence().getAsJsonArray("confirmations").size()==confirmations,"Cancellation changed confirmed ownership");
                var server=client.getServer();server.execute(()->{
                    try {
                        require(server==serverIdentity && server.getOverworld()!=null,"Cancellation authoritative world changed");
                        for(BlockPos cell:ownedBefore)require(server.getOverworld().isChunkLoaded(cell)
                                && server.getOverworld().getBlockState(cell).isOf(Blocks.STONE),"Cancelled action mutated authoritative cell");
                        cancelledOwnedProof.set(ownedBefore);
                    }catch(Exception e){serverFailure.set(e.getMessage());}
                });
                return;
            }
            if(!current.dispatch()) {
                AimedStoneArena.Result result=null;
                if(!selected.allowed() && !current.rayMode().equals("view_origin_over_limit")) {
                    var ownedBefore=arena.ownedCells();int confirmations=arena.evidence().getAsJsonArray("confirmations").size();
                    var decision=arena.request(client,++requestId,current.action(),ray);result=arena.lastResult();
                    require(!decision.queued() && decision.reason().equals(selected.reason()) && result.id()==requestId && result.status().equals("rejected") && !arena.pending(),"Refused selection entered vanilla dispatch");
                    require(arena.ownedCells().equals(ownedBefore) && arena.evidence().getAsJsonArray("confirmations").size()==confirmations,"Refused request mutated confirmed ownership");
                    if(current.name().equals("miss")) {
                        var replay=arena.request(client,requestId,current.action(),ray);
                        require(!replay.queued() && replay.reason().equals("request_id_not_increasing") && !arena.pending() && arena.ownedCells().equals(ownedBefore),"Rejected request ID was reused");
                    }
                }
                record(current,selected,result);next();return;
            }
            var decision=arena.request(client,++requestId,current.action(),ray);
            require(decision.queued(),current.name()+": request refused: "+decision.reason());queued=true;
            if(current.turn()) {
                // Deliberately change view AFTER submission; the queued immutable ray must not retarget.
                client.player.setYaw(client.player.getYaw()+90);client.player.setPitch(35);
            }
            return;
        }
        if(current.name().equals("cancel_before_dispatch")) {
            var proof=cancelledOwnedProof.get();if(proof==null)return;
            require(proof.equals(arena.ownedCells()),"Cancelled action ownership changed after server read");
            for(BlockPos cell:proof)require(client.world.isChunkLoaded(cell) && client.world.getBlockState(cell).isOf(Blocks.STONE),"Cancelled action mutated client cell");
            record(current,selected,arena.lastResult());next();return;
        }
        if(queued && !arena.pending()) {
            var result=arena.lastResult();
            require(result!=null && result.id()==requestId && result.status().equals("confirmed") && result.clientAndServer(),current.name()+": no authoritative confirmation: "+result);
            require(result.target().equals(selected.target()) && result.hit().block().equals(selected.hit().block()) && result.hit().side()==selected.hit().side(),current.name()+": queued ray retargeted after dispatch");
            if(result.action()==PLACE)everPlaced.add(result.target());
            record(current,selected,result);next();
        }
    }
    private void next(){stepIndex++;current=null;}
    private void create(MinecraftClient client) {
        started=true;
        require(client.world==null && !client.isIntegratedServerRunning(),"Refusing already open world");
        require(!Files.exists(client.runDirectory.toPath().resolve("saves").resolve(save)),"Refusing existing save");
        previousPause=client.options.pauseOnLostFocus;previousFps=client.options.getMaxFps().getValue();
        client.options.pauseOnLostFocus=false;client.options.getMaxFps().setValue(60);
        GameRules rules=new GameRules();rules.get(GameRules.DO_MOB_SPAWNING).set(false,null);rules.get(GameRules.SPAWN_CHUNK_RADIUS).set(0,null);
        LevelInfo info=new LevelInfo(save,GameMode.CREATIVE,false,Difficulty.PEACEFUL,true,rules,DataConfiguration.SAFE_MODE);
        client.createIntegratedServerLoader().createAndStart(save,info,new GeneratorOptions(42,false,false),
                registries->registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder(),client.currentScreen);
    }
    private boolean owned(MinecraftClient client) {
        return started && client.player!=null && client.world!=null && client.interactionManager!=null && client.getServer()!=null && client.isIntegratedServerRunning() &&
                save.equals(client.getServer().getSaveProperties().getLevelName()) && client.world.getRegistryKey()==World.OVERWORLD &&
                (worldIdentity==null || client.world==worldIdentity) && (serverIdentity==null || client.getServer()==serverIdentity);
    }
    private void requestTeleport(MinecraftClient client,Vec3d eye,Vec3d lookAt) {
        var server=client.getServer();var playerId=client.player.getUuid();long number=++teleportNumber;
        double eyeHeight=client.player.getEyeY()-client.player.getY();
        Vec3d d=lookAt.subtract(eye).normalize();
        float yaw=(float)Math.toDegrees(Math.atan2(-d.x,d.z)),pitch=(float)-Math.toDegrees(Math.asin(d.y));
        server.execute(()->{
            try {
                var world=server.getOverworld();var player=server.getPlayerManager().getPlayer(playerId);
                require(server==serverIdentity && save.equals(server.getSaveProperties().getLevelName()) && player!=null && player.getWorld()==world,"Server fixture teleport identity changed");
                require(player.isCreative(),"Fixture player is not Creative");
                player.getAbilities().flying=true;player.sendAbilitiesUpdate();
                player.teleport(world,eye.x,eye.y-eyeHeight,eye.z,yaw,pitch);player.setVelocity(Vec3d.ZERO);player.fallDistance=0;
                teleportProof.set(new TeleportProof(number,player.getEyePos()));
            }catch(Exception e){serverFailure.set("Fixture teleport failed: "+e.getMessage());}
        });
    }
    private AimedStoneArena.HostRay ray(MinecraftClient client,Step step) {
        Vec3d eye=client.player.getEyePos(),target=center(step.aimedCell());
        // Fixture-only captured view origins. The actual client/server player,
        // fixed alignment and original resulting ray remain unchanged.
        double viewOffset=switch(step.rayMode()){
            case "view_origin_measured" -> .17794543;
            case "view_origin_boundary" -> .25;
            case "view_origin_over_limit" -> .250001;
            default -> 0;
        };
        eye=eye.add(viewOffset,0,0);
        Vec3d direction=step.rayMode().equals("miss")?new Vec3d(0,1,0):target.subtract(eye).normalize();
        var mcRay=new AimGeometry.Ray(protocol(eye),protocol(direction),4.5);
        var occlusion=switch(step.rayMode()) {
            case "occluded" -> AimedStoneArena.Occlusion.hit(0.25);
            case "unavailable" -> AimedStoneArena.Occlusion.unavailable();
            default -> AimedStoneArena.Occlusion.clear();
        };
        long captured=System.nanoTime()-(step.rayMode().equals("stale")?2_000_000_000L:0);
        var host=ALIGNMENT.toKcd(mcRay);
        if(step.rayMode().equals("origin_mismatch"))host=new AimGeometry.Ray(new Protocol.Vec3(host.origin().x()+1,host.origin().y(),host.origin().z()),host.direction(),host.range());
        var alignment=step.rayMode().equals("alignment_changed")?new AimGeometry.Alignment(new Protocol.Vec3(1,0,0),new Protocol.Vec3(0,0,0),1):ALIGNMENT;
        return new AimedStoneArena.HostRay(captured,alignment,host,occlusion);
    }
    private static String expectedRejection(String mode) {
        return switch(mode){case "miss"->"ray_miss";case "floor"->"unowned_hit";case "occluded"->"host_obstructed";case "unavailable"->"host_obstruction_unavailable";case "stale"->"ray_stale";case "origin_mismatch","view_origin_over_limit"->"ray_origin_disagrees_with_eye";case "alignment_changed"->"alignment_changed";default->throw new IllegalArgumentException("Unspecified rejection case");};
    }
    private static List<Step> steps(BlockPos s) {
        var result=new ArrayList<Step>();BlockPos top=s.up(2),east=top.east();
        result.add(action("column_middle",s,new Vec3d(2.5,3,.5),s,s.up(),Direction.UP,PLACE,false));
        result.add(action("column_top",s,new Vec3d(2.5,4,.5),s.up(),top,Direction.UP,PLACE,false));
        result.add(action("remove_seed",s,new Vec3d(-2,1.62,.5),s,s,Direction.WEST,BREAK,false));
        result.add(action("remove_middle",s,new Vec3d(-2,1.62,.5),s.up(),s.up(),Direction.WEST,BREAK,false));
        result.add(selection("face_down",s,new Vec3d(.5,1.62,.5),top,top,Direction.DOWN,true,"clear"));
        result.add(selection("face_up",s,new Vec3d(.5,5,.5),top,top,Direction.UP,true,"clear"));
        result.add(selection("face_north",s,new Vec3d(.5,2.5,-2),top,top,Direction.NORTH,true,"clear"));
        result.add(selection("face_south",s,new Vec3d(.5,2.5,3),top,top,Direction.SOUTH,true,"clear"));
        result.add(selection("face_west",s,new Vec3d(-2,2.5,.5),top,top,Direction.WEST,true,"clear"));
        result.add(selection("face_east",s,new Vec3d(3,2.5,.5),top,top,Direction.EAST,true,"clear"));
        result.add(action("place_east",s,new Vec3d(3.5,2.5,.5),top,east,Direction.EAST,PLACE,false));
        result.add(selection("nearest",s,new Vec3d(4,2.5,.5),top,east,Direction.EAST,true,"clear"));
        result.add(selection("miss",s,new Vec3d(-2,2.5,.5),top,null,null,false,"miss"));
        result.add(selection("unowned_floor",s,new Vec3d(-2,1.62,.5),s.down(),null,null,false,"floor"));
        result.add(selection("host_occluded",s,new Vec3d(-2,2.5,.5),top,null,null,false,"occluded"));
        result.add(selection("host_occlusion_unavailable",s,new Vec3d(-2,2.5,.5),top,null,null,false,"unavailable"));
        result.add(selection("stale_ray",s,new Vec3d(-2,2.5,.5),top,null,null,false,"stale"));
        result.add(selection("origin_mismatch",s,new Vec3d(-2,2.5,.5),top,null,null,false,"origin_mismatch"));
        result.add(selection("alignment_changed",s,new Vec3d(-2,2.5,.5),top,null,null,false,"alignment_changed"));
        result.add(selection("view_origin_measured",s,new Vec3d(-2,2.5,.5),top,top,Direction.WEST,true,"view_origin_measured"));
        result.add(selection("view_origin_boundary",s,new Vec3d(-2,2.5,.5),top,top,Direction.WEST,true,"view_origin_boundary"));
        result.add(selection("view_origin_over_limit",s,new Vec3d(-2,2.5,.5),top,null,null,false,"view_origin_over_limit"));
        result.add(selection("cancel_before_dispatch",s,new Vec3d(4,2.5,.5),top,east,Direction.EAST,true,"clear"));
        result.add(action("turn_while_pending",s,new Vec3d(4,2.5,.5),top,east,Direction.EAST,BREAK,true));
        result.add(action("cleanup_top",s,new Vec3d(-2,2.5,.5),top,top,Direction.WEST,BREAK,false));
        return List.copyOf(result);
    }
    private static Step action(String name,BlockPos seed,Vec3d eye,BlockPos aim,BlockPos expected,Direction face,int action,boolean turn) {
        return new Step(name,eye.add(seed.getX(),seed.getY(),seed.getZ()),aim,expected,face,action,true,true,"clear",turn);
    }
    private static Step selection(String name,BlockPos seed,Vec3d eye,BlockPos aim,BlockPos expected,Direction face,boolean allowed,String mode) {
        return new Step(name,eye.add(seed.getX(),seed.getY(),seed.getZ()),aim,expected,face,BREAK,false,allowed,mode,false);
    }
    private void record(Step step,AimedStoneArena.Selection selection,AimedStoneArena.Result result) {
        var record=new JsonObject();record.addProperty("name",step.name());record.addProperty("passed",true);record.addProperty("selection_allowed",selection.allowed());record.addProperty("reason",selection.reason());
        record.addProperty("vanilla_dispatch",step.dispatch());record.addProperty("client_and_server_confirmed",result!=null && result.clientAndServer());
        record.addProperty("view_turned_after_queue",step.turn());
        record.addProperty("rejected_request_checked",!selection.allowed() && !step.rayMode().equals("view_origin_over_limit"));record.addProperty("rejected_id_replay_checked",step.name().equals("miss"));
        if(step.name().equals("cancel_before_dispatch")) {
            record.addProperty("queued_then_cancelled",true);record.addProperty("cancellation_reason",result.reason());
            record.addProperty("client_server_cells_unchanged",true);
        }
        var rayRecord=new JsonObject();rayRecord.add("host_origin",protocolVector(selectedRay.hostRay().origin()));rayRecord.add("host_direction",protocolVector(selectedRay.hostRay().direction()));rayRecord.addProperty("host_range",selectedRay.hostRay().range());
        rayRecord.add("minecraft_anchor",protocolVector(selectedRay.alignment().minecraftAnchor()));rayRecord.add("host_anchor",protocolVector(selectedRay.alignment().kcdAnchor()));rayRecord.addProperty("blocks_per_host_unit",selectedRay.alignment().blocksPerUnit());
        rayRecord.addProperty("age_at_selection_ns",selectionAge);
        rayRecord.addProperty("occlusion_kind",selectedRay.occlusion().kind().name());rayRecord.addProperty("host_obstruction_distance",selectedRay.occlusion().distance());record.add("synthetic_ray",rayRecord);
        if(result!=null){record.addProperty("request_id",result.id());record.addProperty("action",result.action());}
        if(selection.hit()!=null){record.addProperty("face",selection.hit().side().getName());record.add("hit_block",position(selection.hit().block()));}
        if(selection.target()!=null)record.add("target",position(selection.target()));
        checks.add(record);LOG.info("AIMED_STONE_CHECK name={} selection={} vanillaDispatch={} clientServer={} reason={}",step.name(),selection.allowed(),step.dispatch(),result!=null && result.clientAndServer(),selection.reason());
    }
    private JsonObject identity() {
        var r=new JsonObject();r.addProperty("schema",1);r.addProperty("kind","minecome_aimed_stone_fixture_v1");r.addProperty("run",run);r.addProperty("save",save);
        r.addProperty("producer_pid",producerPid);r.addProperty("producer_start_filetime",producerStart);r.addProperty("synthetic_host_rays",true);r.addProperty("kcd_connected",false);return r;
    }
    private void finish(MinecraftClient client,String result) throws Exception {
        if(finished || stopping)return;
        try {
            restore(client);
            var receipt=identity();receipt.addProperty("result",result);receipt.addProperty("failure",failure);receipt.add("checks",checks);receipt.add("fixture_teleports",teleports);
            receipt.addProperty("bootstrap_confirmed",bootstrapConfirmed);receipt.addProperty("options_restored",true);receipt.addProperty("world_block_writes",false);
            require(previousPause==null || client.options.pauseOnLostFocus==previousPause,"Pause option restoration failed");
            require(previousFps==null || client.options.getMaxFps().getValue().equals(previousFps),"FPS option restoration failed");
            var cleanup=new JsonArray();if(finalAir.get()!=null)for(var cell:finalAir.get())cleanup.add(position(cell));
            receipt.add("final_client_server_air_cells",cleanup);
            receipt.add("arena",arena.evidence());write("aimed-stone.json",receipt);
            finished=true;
            LOG.info("AIMED_STONE_TERMINAL run={} result={} checks={} failure={}",run,result,checks.size(),failure);
        }catch(Exception e){
            LOG.error("Aimed terminal evidence failed; Minecraft will still close normally",e);throw e;
        }finally{
            stopping=true;client.scheduleStop();
        }
    }
    private void fail(MinecraftClient client,String reason) {
        if(stopping)return;failure=reason;LOG.error("AIMED_STONE_FAIL: {}",reason);
        try {finish(client,"failed");}catch(Exception e){restore(client);stopping=true;client.scheduleStop();LOG.error("Cannot preserve failed aimed fixture receipt",e);}
    }
    private void stopping(MinecraftClient client) {
        if(!finished){failure="Minecraft stopped before fixture completion";try{finish(client,"failed");}catch(Exception e){LOG.error("Cannot preserve stopped aimed fixture",e);}}
        restore(client);
    }
    private void restore(MinecraftClient client) {
        if(previousPause!=null)client.options.pauseOnLostFocus=previousPause;
        if(previousFps!=null)client.options.getMaxFps().setValue(previousFps);
    }
    private void write(String name,JsonObject value) throws Exception {
        Path temporary=directory.resolve(name+".tmp");
        Files.writeString(temporary,new GsonBuilder().serializeNulls().setPrettyPrinting().create().toJson(value),StandardOpenOption.CREATE_NEW);
        Files.move(temporary,directory.resolve(name),StandardCopyOption.ATOMIC_MOVE);
    }
    private static void require(boolean value,String reason){if(!value)throw new IllegalStateException(reason);}
    private static Vec3d center(BlockPos p){return new Vec3d(p.getX()+.5,p.getY()+.5,p.getZ()+.5);}
    private static Protocol.Vec3 protocol(Vec3d v){return new Protocol.Vec3(v.x,v.y,v.z);}
    private static JsonObject vector(Vec3d v){var r=new JsonObject();r.addProperty("x",v.x);r.addProperty("y",v.y);r.addProperty("z",v.z);return r;}
    private static JsonObject position(BlockPos v){var r=new JsonObject();r.addProperty("x",v.getX());r.addProperty("y",v.getY());r.addProperty("z",v.getZ());return r;}
    private static JsonObject protocolVector(Protocol.Vec3 v){return vector(new Vec3d(v.x(),v.y(),v.z()));}
}
