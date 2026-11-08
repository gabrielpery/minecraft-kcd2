package dev.minecome.gameplay;

import com.google.gson.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.*;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Vec3d;
import net.minecraft.util.shape.VoxelShapes;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;

/** Persistent ownership and bounded worker tests; actual vanilla actions run in GameplayBlocksFixture. */
public final class GameplayBlocksTests {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Action action,String message)throws Exception{
        try{action.run();throw new AssertionError(message);}catch(IOException|IllegalArgumentException expected){checks++;}
    }
    private static final GroundSurface SURFACE=new GroundSurface(){
        public String run(){return "blocks-fixture";}public String sourceKind(){return "fixture";}public String sha256(){return "a".repeat(64);}
        public double centerX(){return 100;}public double centerY(){return 200;}public double centerZ(){return 50;}
        public List<GroundPatch.Point> points(){return List.of();}public List<GroundPatch.Slab> slabs(){return List.of();}public List<GroundPatch.Cell> cells(){return List.of();}
        public double heightAt(double x,double z){return 64;}public double groundForFeet(double x,double z,double r){return 64;}
        public boolean containsFeet(double x,double z,double margin){return x-margin>=-4&&x+margin<=4&&z-margin>=-4&&z+margin<=4;}
        public boolean wide(){return true;}
    };
    private static void write(Path path,JsonObject json)throws IOException{Files.writeString(path,json.toString());}
    public static void main(String[] args)throws Exception{
        Path root=Files.createTempDirectory("minecome-gameplay-blocks-").toRealPath();
        var save=GameplayWorld.prepare(root.resolve("instance/saves"),root);
        var ledger=new GameplayBlocksLedger(save,SURFACE);
        check(ledger.initial.isEmpty()&&ledger.initialRevision==0,"Fresh ownership starts empty without seeding blocks");
        var low=new GameplayBlocksLedger.Cell(-4,56,-4);var high=new GameplayBlocksLedger.Cell(3,80,3);
        var cells=Set.of(low,high,new GameplayBlocksLedger.Cell(2,64,0));
        ledger.persist(1,cells);
        var reopened=new GameplayBlocksLedger(save,SURFACE);
        check(reopened.initial.equals(cells)&&reopened.initialRevision==1,"Ownership survives a new controller without resetting");
        check(GameplayBlocksLedger.blocks(cells).get(0).getAsJsonObject().get("x").getAsInt()==-4,"Canonical order is stable");
        check(GameplayBlocksLedger.allowed(SURFACE,low)&&GameplayBlocksLedger.allowed(SURFACE,high),"Whole boundary cells are supported");
        for(var outside:List.of(new GameplayBlocksLedger.Cell(-5,64,0),new GameplayBlocksLedger.Cell(4,64,0),new GameplayBlocksLedger.Cell(0,55,0),new GameplayBlocksLedger.Cell(0,81,0)))
            check(!GameplayBlocksLedger.allowed(SURFACE,outside),"Outside building coverage rejected");
        reject(()->reopened.persist(0,cells),"Revision cannot go backward");
        reject(()->reopened.persist(1,Set.of()),"Same revision cannot silently change the ledger");
        reopened.persist(2,Set.of(low));
        check(new GameplayBlocksLedger(save,SURFACE).initial.equals(Set.of(low)),"Breaking removes ownership from persistent ledger");
        var good=JsonParser.parseString(Files.readString(ledger.path)).getAsJsonObject();
        for(String field:List.of("world_id","patch_run","patch_sha256","kind")){
            var changed=good.deepCopy();changed.addProperty(field,"foreign");write(ledger.path,changed);
            reject(()->new GameplayBlocksLedger(save,SURFACE),"Foreign identity rejected: "+field);
        }
        for(String field:List.of("schema","revision")){
            var changed=good.deepCopy();changed.addProperty(field,1.5);write(ledger.path,changed);
            reject(()->new GameplayBlocksLedger(save,SURFACE),"Fractional numeric identity/revision rejected");
            changed.addProperty(field,"1");write(ledger.path,changed);
            reject(()->new GameplayBlocksLedger(save,SURFACE),"String numeric identity/revision rejected");
        }
        var changed=good.deepCopy();changed.getAsJsonArray("blocks").add(changed.getAsJsonArray("blocks").get(0).deepCopy());write(ledger.path,changed);
        reject(()->new GameplayBlocksLedger(save,SURFACE),"Duplicate ownership rejected");
        changed=good.deepCopy();changed.getAsJsonArray("blocks").get(0).getAsJsonObject().addProperty("state","minecraft:dirt");write(ledger.path,changed);
        reject(()->new GameplayBlocksLedger(save,SURFACE),"Unimplemented block types rejected");
        changed=good.deepCopy();changed.getAsJsonArray("blocks").get(0).getAsJsonObject().addProperty("x",4);write(ledger.path,changed);
        reject(()->new GameplayBlocksLedger(save,SURFACE),"Stored cells must remain inside capture");
        changed=good.deepCopy();for(int i=0;i<64;i++)changed.getAsJsonArray("blocks").add(new JsonObject());write(ledger.path,changed);
        reject(()->new GameplayBlocksLedger(save,SURFACE),"More than64 cells rejected before parsing entries");
        Files.writeString(ledger.path," ".repeat(GameplayBlocksLedger.MAX_BYTES+1));
        reject(()->new GameplayBlocksLedger(save,SURFACE),"Oversized ledger rejected");
        write(ledger.path,good);var retained=new GameplayBlocksLedger(save,SURFACE);
        Files.writeString(ledger.path,good+" ");
        reject(()->retained.persist(3,Set.of()),"Concurrent external edits preserved instead of overwritten");
        write(ledger.path,good);

        Path evidence=Files.createDirectories(root.resolve("runtime/evidence/block-writer"));
        var workerLedger=new GameplayBlocksLedger(save,SURFACE);
        var worker=new GameplayBlocksFiles(root,evidence,workerLedger);
        // Thousands of faster-than-consumer publications replace one latest slot.
        for(int i=3;i<=1002;i++)worker.publish(i,Set.of(high),"{\"revision\":"+i+"}");
        worker.close();long deadline=System.nanoTime()+3_000_000_000L;
        while(!worker.finished()&&System.nanoTime()<deadline)Thread.sleep(5);
        check(worker.finished()&&worker.failure()==null,"Writer drains and finishes cleanly");
        check(worker.persistedRevision()==1002,"Last confirmed revision reaches persistent ownership");
        check(Files.readString(evidence.resolve("gameplay-blocks.json")).equals("{\"revision\":1002}"),"Last server frame survives overwrite pressure");
        var finalLedger=new GameplayBlocksLedger(save,SURFACE);
        check(finalLedger.initialRevision==1002&&finalLedger.initial.equals(Set.of(high)),"Final file and saved ledger agree");
        check(worker.writes()<1000,"Latest-value worker coalesces excess publication");
        reject(()->new GameplayBlocksFiles(root,evidence,finalLedger),"Existing session output never adopted");
        Path outside=Files.createDirectories(root.resolve("outside-evidence"));
        reject(()->new GameplayBlocksFiles(root,outside,finalLedger),"Session output stays in evidence directory");
        aimTests(root,save);
        terrainLedgerTests(root);
        worldBlockStateTests(root);
        cameraVisibilityTests();
        cameraCollisionTests();
        System.out.println("GameplayBlocksTests: "+checks+" checks passed; no game calls");
    }
    private static void cameraCollisionTests()throws Exception{
        var producer=new GameplayCameraCollision();
        var empty=producer.capture(Map.of());
        check(empty.complete()&&empty.generation()==1&&empty.boxes().isEmpty(),"An observed empty owned set explicitly clears camera obstacles");
        check(producer.capture(Map.of())==empty,"Unchanged actual geometry reuses its immutable snapshot");
        var cube=producer.capture(Map.of(new BlockPos(-1,64,-2),VoxelShapes.fullCube()));
        check(cube.complete()&&cube.generation()==2&&cube.boxes().equals("fff00400ffe000000410fff0"),"Signed sixteenths retain exact negative x/z and Minecraft height");
        var origin=cube.json(SURFACE).getAsJsonObject("origin");
        check(origin.get("x").getAsDouble()==100&&origin.get("y").getAsDouble()==200&&origin.get("z").getAsDouble()==-14,"Fixed native origin preserves x / negative z / y coordinate mapping");
        check(cube.json(SURFACE).keySet().equals(Set.of("generation","complete","origin","boxes")),"Collision payload exposes only the agreed bounded wire fields");
        var slab=producer.capture(Map.of(new BlockPos(-1,64,-2),VoxelShapes.cuboid(0,0,0,1,.5,1)));
        check(slab.complete()&&slab.generation()==3&&slab.boxes().equals("fff00400ffe000000408fff0"),"Bottom slab keeps its empty upper half rather than becoming a cube");
        var stair=VoxelShapes.union(VoxelShapes.cuboid(0,0,0,1,.5,1),VoxelShapes.cuboid(.5,.5,0,1,1,1));
        var stairs=producer.capture(Map.of(BlockPos.ORIGIN,stair));
        check(stairs.complete()&&stairs.boxes().length()==48,"Two stair volumes retain their step geometry");
        var post=VoxelShapes.cuboid(.375,0,.375,.625,1,.625);
        var fence=producer.capture(Map.of(BlockPos.ORIGIN,post));
        check(fence.complete()&&fence.boxes().equals("000600000006000a0010000a"),"Fence camera post preserves narrow geometry and surrounding gaps");
        var ordered=new LinkedHashMap<BlockPos,net.minecraft.util.shape.VoxelShape>();ordered.put(new BlockPos(2,0,0),post);ordered.put(new BlockPos(-2,0,0),post);
        var firstOrder=producer.capture(ordered);var reversed=new LinkedHashMap<BlockPos,net.minecraft.util.shape.VoxelShape>();reversed.put(new BlockPos(-2,0,0),post);reversed.put(new BlockPos(2,0,0),post);
        check(producer.capture(reversed)==firstOrder,"Map enumeration order cannot change collision generation");
        var duplicated=new LinkedHashMap<BlockPos,net.minecraft.util.shape.VoxelShape>();duplicated.put(BlockPos.ORIGIN,VoxelShapes.fullCube());duplicated.put(new BlockPos(1,0,0),VoxelShapes.fullCube().offset(-1,0,0));
        check(producer.capture(duplicated).boxes().length()==24,"Equivalent world-space geometry is deduplicated before transport");
        var incomplete=producer.capture(Map.of(BlockPos.ORIGIN,VoxelShapes.cuboid(0,0,0,.1,1,1)));
        check(!incomplete.complete()&&incomplete.boxes().isEmpty(),"Off-grid camera shape fails closed instead of rounding into a different obstacle");
        check(producer.unavailable()==incomplete,"Repeated unavailable observations do not churn generations");
        check(!producer.capture(Map.of(new BlockPos(2047,0,0),VoxelShapes.fullCube())).complete(),"Signed-sixteenth upper overflow fails closed");
        check(!producer.capture(Map.of(new BlockPos(-2049,0,0),VoxelShapes.fullCube())).complete(),"Signed-sixteenth lower overflow fails closed");
        check(!producer.capture(Map.of(BlockPos.ORIGIN,VoxelShapes.cuboid(0,0,0,2.0625,1,1))).complete(),"Overlarge camera box fails closed consistently with native bounds");
        check(producer.capture(Map.of(new BlockPos(-2048,0,0),VoxelShapes.fullCube())).complete(),"Exact signed-sixteenth minimum is representable");
        var tooMany=new HashMap<BlockPos,net.minecraft.util.shape.VoxelShape>();for(int i=0;i<65;i++)tooMany.put(new BlockPos(i,0,0),VoxelShapes.fullCube());
        check(!producer.capture(tooMany).complete(),"Unbounded owned set cannot be partially serialized");
        var manyParts=VoxelShapes.empty();for(int i=0;i<513;i++)manyParts=VoxelShapes.union(manyParts,VoxelShapes.cuboid(i*.125,0,0,i*.125+.0625,.0625,.0625));
        check(!producer.capture(Map.of(BlockPos.ORIGIN,manyParts)).complete(),"Over512 actual boxes collapse the whole camera set rather than dropping distant boxes");
        var recovered=producer.capture(Map.of(BlockPos.ORIGIN,VoxelShapes.fullCube()));
        check(recovered.complete()&&recovered.generation()>incomplete.generation(),"A complete fresh geometry set recovers with a new generation");
        var cleared=producer.capture(Map.of());check(cleared.complete()&&cleared.generation()==recovered.generation()+1&&cleared.boxes().isEmpty(),"Mining the final obstacle publishes a new complete empty generation");
        reject(()->new GameplayCameraCollision.Snapshot(0,true,""),"Zero collision generation rejected");
        reject(()->new GameplayCameraCollision.Snapshot(1,true,"ffff"),"Partial packed box rejected");
        reject(()->new GameplayCameraCollision.Snapshot(1,false,cube.boxes()),"Incomplete collision cannot smuggle partial obstacles");
    }
    private static void cameraVisibilityTests()throws Exception{
        var eye=new Vec3d(0,.75,.5);var camera=new Vec3d(-2,.75,.5);var target=new Vec3d(3,.75,.5);
        var ray=new GameplayBlocks.Aim(1,1,eye,new Vec3d(1,0,0),4.5,true,-1,false,camera);
        var near=new BlockPos(-1,0,0);var cube=VoxelShapes.fullCube();
        check(GameplayBlocks.cameraOccludes(ray,target,near,cube),"Back-view camera cannot target through an owned block behind the eye");
        check(!GameplayBlocks.cameraOccludes(ray,target,new BlockPos(3,0,0),cube),"The selected block's visible face at the endpoint is not its own occluder");
        check(!GameplayBlocks.cameraOccludes(ray,target,new BlockPos(4,0,0),cube),"Blocks beyond the selected surface do not reject a visible hit");
        check(!GameplayBlocks.cameraOccludes(ray,target,near,VoxelShapes.cuboid(0,0,0,1,.5,1)),"A bottom slab leaves the actual upper sightline clear");
        check(GameplayBlocks.cameraOccludes(ray,target,near,VoxelShapes.cuboid(0,.5,0,1,1,1)),"A top slab occludes that same sightline");
        check(!GameplayBlocks.cameraOccludes(ray,target,near,VoxelShapes.cuboid(.375,0,.65,.625,1.5,.85)),"A fence-sized post beside the ray does not act as a full block");
        check(GameplayBlocks.cameraOccludes(ray,target,near,VoxelShapes.cuboid(.375,0,.375,.625,1.5,.625)),"A fence post on the actual ray blocks the hidden target");
        var inside=new GameplayBlocks.Aim(1,1,eye,new Vec3d(1,0,0),4.5,true,-1,false,new Vec3d(-.5,.75,.5));
        check(GameplayBlocks.cameraOccludes(inside,target,near,cube),"A camera inside an owned shape cannot see through its outer face");
        var front=new GameplayBlocks.Aim(1,1,eye,new Vec3d(-1,0,0),4.5,true,-1,false,new Vec3d(2,.75,.5));
        check(GameplayBlocks.cameraOccludes(front,new Vec3d(-3,.75,.5),new BlockPos(1,0,0),cube),"Front-view camera cannot target behind a nearer owned block between camera and eye");
        var first=new GameplayBlocks.Aim(1,1,eye,new Vec3d(1,0,0),4.5,true,-1,false);
        check(first.cameraOrigin().equals(eye)&&!GameplayBlocks.cameraOccludes(first,target,new BlockPos(1,0,0),cube),"Legacy first-person aims preserve the existing eye-ray obstruction behavior");
        check(ray.range()==4.5&&target.distanceTo(camera)>ray.range()&&target.distanceTo(eye)<ray.range(),"Camera offset does not shorten or extend authoritative eye reach");
        reject(()->new GameplayBlocks.Aim(1,1,eye,new Vec3d(1,0,0),4.5001,true,-1,false,camera),"Displaced cameras cannot extend eye reach beyond4.5m");
    }
    private static void worldBlockStateTests(Path root)throws Exception{
        for(var state:List.of("minecraft:stone","minecraft:dirt","minecraft:oak_planks","minecraft:bricks",
                "minecraft:red_concrete","minecraft:blue_wool","minecraft:oak_log[axis=x]","minecraft:oak_log[axis=y]","minecraft:oak_log[axis=z]"))
            check(GameplayBlocksPalette.supportsState(state),"Supported canonical world block state: "+state);
        for(var state:List.of("minecraft:air","minecraft:water","minecraft:sand","minecraft:glass","minecraft:grass_block",
                "minecraft:oak_stairs[facing=north]","minecraft:oak_log","minecraft:oak_log[axis=q]","minecraft:oak_log[axis=X]",
                "minecraft:oak_log[axis=x,axis=y]","minecraft:dirt[snowy=false]","minecraft:stone ","stone","foreign:stone"))
            check(!GameplayBlocksPalette.supportsState(state),"Unsupported or noncanonical world state rejected: "+state);
        check(GameplayBlocksPalette.supportsBlock("minecraft:oak_log")&&!GameplayBlocksPalette.supportsBlock("minecraft:oak_log[axis=x]"),"Block item policy distinguishes registry ID from placed state");
        for(var type:List.of("bottom","top","double"))for(var material:List.of("oak","brick"))
            check(GameplayBlocksPalette.supportsState("minecraft:"+material+"_slab[type="+type+",waterlogged=false]"),"Dry slab state supported: "+material+" "+type);
        for(var facing:List.of("north","south","east","west"))for(var half:List.of("bottom","top"))
            for(var shape:List.of("straight","inner_left","inner_right","outer_left","outer_right"))
                check(GameplayBlocksPalette.supportsState("minecraft:oak_stairs[facing="+facing+",half="+half+",shape="+shape+",waterlogged=false]"),"Canonical dry stair orientation/corner supported");
        for(var invalid:List.of("minecraft:oak_slab","minecraft:oak_slab[type=bottom]","minecraft:oak_slab[type=bottom,waterlogged=true]",
                "minecraft:oak_slab[type=double,waterlogged=true]","minecraft:oak_slab[type=middle,waterlogged=false]",
                "minecraft:oak_slab[waterlogged=false,type=bottom]","minecraft:oak_slab[type=bottom,waterlogged=false,extra=false]",
                "minecraft:oak_stairs","minecraft:oak_stairs[facing=up,half=bottom,shape=straight,waterlogged=false]",
                "minecraft:oak_stairs[facing=north,half=double,shape=straight,waterlogged=false]",
                "minecraft:oak_stairs[facing=north,half=bottom,shape=straight,waterlogged=true]",
                "minecraft:oak_stairs[facing=north,half=bottom,shape=curved,waterlogged=false]",
                "minecraft:oak_stairs[facing=north,half=bottom,shape=straight]",
                "minecraft:oak_stairs[facing=north,half=bottom,shape=straight,waterlogged=false,extra=false]",
                "minecraft:oak_stairs[half=bottom,facing=north,shape=straight,waterlogged=false]"))
            check(!GameplayBlocksPalette.supportsState(invalid),"Malformed, noncanonical or wet shape rejected: "+invalid);
        check(GameplayBlocksPalette.supportsBlock("minecraft:oak_slab")&&GameplayBlocksPalette.supportsBlock("minecraft:brick_stairs")&&
            !GameplayBlocksPalette.supportsBlock("minecraft:oak_slab[type=bottom,waterlogged=false]"),"Shape item policy uses bare registry IDs");
        var fence="minecraft:oak_fence[east=false,north=true,south=false,waterlogged=false,west=true]";
        var wall="minecraft:cobblestone_wall[east=none,north=low,south=tall,up=false,waterlogged=false,west=none]";
        for(var wood:List.of("oak","spruce","birch","jungle","acacia","dark_oak","mangrove","cherry","bamboo","crimson","warped","nether_brick")){
            var id="minecraft:"+wood+"_fence";
            check(GameplayBlocksPalette.supportsBlock(id)&&GameplayBlocksPalette.blockIds().contains(id),"Fence item is in the supported palette: "+id);
            check(GameplayBlocksPalette.supportsState(id+fence.substring(fence.indexOf('['))),"Connected dry fence state supported: "+id);
        }
        for(var material:List.of("cobblestone","mossy_cobblestone","brick","granite","diorite","andesite","stone_brick","mossy_stone_brick","sandstone","red_sandstone")){
            var id="minecraft:"+material+"_wall";
            check(GameplayBlocksPalette.supportsBlock(id)&&GameplayBlocksPalette.blockIds().contains(id),"Wall item is in the supported palette: "+id);
            check(GameplayBlocksPalette.supportsState(id+wall.substring(wall.indexOf('['))),"Low/tall dry wall state supported: "+id);
        }
        for(var state:List.of(
                "minecraft:oak_fence[east=false,north=false,south=false,waterlogged=false,west=false]",
                "minecraft:oak_fence[east=true,north=true,south=true,waterlogged=false,west=true]",
                "minecraft:cobblestone_wall[east=none,north=none,south=none,up=true,waterlogged=false,west=none]",
                "minecraft:cobblestone_wall[east=low,north=none,south=none,up=false,waterlogged=false,west=low]",
                "minecraft:cobblestone_wall[east=tall,north=tall,south=tall,up=true,waterlogged=false,west=tall]"))
            check(GameplayBlocksPalette.supportsState(state),"Disconnected, straight and fully connected dry states remain serializable");
        for(var invalid:List.of("minecraft:oak_fence","minecraft:cobblestone_wall",fence.replace("waterlogged=false","waterlogged=true"),
                wall.replace("waterlogged=false","waterlogged=true"),fence.replace(",waterlogged=false",""),wall.replace(",up=false",""),
                fence.replace("north=true","north=low"),wall.replace("north=low","north=true"),wall.replace("south=tall","south=full"),
                fence.replace("east=false,north=true","north=true,east=false"),wall.replace("up=false,waterlogged=false","waterlogged=false,up=false"),
                fence.replace("north=true","north=true,north=false"),wall.replace("up=false","up=false,up=true"),
                fence.replace("west=true]","west=true,extra=false]"),wall.replace("up=false","up=False"),
                fence.replace("oak_fence","oak_fence_gate"),fence.replace("oak_fence","iron_bars")))
            check(!GameplayBlocksPalette.supportsState(invalid),"Wet, incomplete, noncanonical or foreign connected shape rejected: "+invalid);
        check(!GameplayBlocksPalette.supportsBlock(fence)&&!GameplayBlocksPalette.supportsBlock(wall)&&
            !GameplayBlocksPalette.supportsBlock("minecraft:oak_fence_gate"),"Connected items use bare supported registry IDs, excluding gates");
        var save=GameplayWorld.prepare(root.resolve("world-blocks-instance/saves"),root);
        var a=new GameplayBlocksLedger.Cell(0,64,0);var b=new GameplayBlocksLedger.Cell(1,64,0);var c=new GameplayBlocksLedger.Cell(2,64,0);
        var legacy=new GameplayBlocksLedger(save,SURFACE);legacy.persist(1,Set.of(a));
        var ledger=new GameplayBlocksLedger(save,SURFACE,true);
        check(ledger.initialStates.equals(Map.of(a,"minecraft:stone")),"World renderer adopts existing stone ledger without migration");
        var mixed=Map.of(a,"minecraft:dirt",b,"minecraft:oak_log[axis=x]",c,"minecraft:bricks");ledger.persist(2,mixed);
        var reopened=new GameplayBlocksLedger(save,SURFACE,true);
        check(reopened.initialStates.equals(mixed)&&reopened.initialRevision==2,"Material and log orientation survive ownership reopen");
        check(GameplayBlocksLedger.blocks(mixed).get(1).getAsJsonObject().get("state").getAsString().equals("minecraft:oak_log[axis=x]"),"Canonical snapshot retains actual state instead of replacing with stone");
        reject(()->new GameplayBlocksLedger(save,SURFACE),"Legacy stone renderer cannot silently adopt nonstone world");
        var rotated=Map.of(a,"minecraft:dirt",b,"minecraft:oak_log[axis=z]",c,"minecraft:bricks");reopened.persist(3,rotated);
        check(new GameplayBlocksLedger(save,SURFACE,true).initialStates.equals(rotated),"State-only ownership revision persists with unchanged positions");
        reject(()->reopened.persist(4,Map.of(a,"minecraft:water")),"Checkpoint rejects unsupported fluid state");
        reject(()->reopened.persist(4,Map.of(a,"minecraft:oak_log[axis=q]")),"Checkpoint rejects malformed state properties");
        var good=JsonParser.parseString(Files.readString(reopened.path)).getAsJsonObject();
        var changed=good.deepCopy();changed.getAsJsonArray("blocks").get(0).getAsJsonObject().addProperty("state","minecraft:oak_log[axis=q]");write(reopened.path,changed);
        reject(()->new GameplayBlocksLedger(save,SURFACE,true),"Malformed saved block properties rejected before world attachment");
        write(reopened.path,good);
        var workerLedger=new GameplayBlocksLedger(save,SURFACE,true);var evidence=Files.createDirectories(root.resolve("runtime/evidence/world-block-writer"));
        var worker=new GameplayBlocksFiles(root,evidence,workerLedger);worker.publish(4,Map.of(b,"minecraft:oak_log[axis=y]"),"{\"revision\":4}");worker.close();
        long deadline=System.nanoTime()+3_000_000_000L;while(!worker.finished()&&System.nanoTime()<deadline)Thread.sleep(5);
        check(worker.finished()&&worker.failure()==null&&worker.persistedRevision()==4,"Mixed-state worker drains without game-thread IO");
        check(new GameplayBlocksLedger(save,SURFACE,true).initialStates.equals(Map.of(b,"minecraft:oak_log[axis=y]")),"Worker persists removal and orientation atomically");
        var shapeLedger=new GameplayBlocksLedger(save,SURFACE,true);
        var shaped=Map.of(a,"minecraft:oak_slab[type=top,waterlogged=false]",b,"minecraft:brick_stairs[facing=west,half=bottom,shape=outer_left,waterlogged=false]");
        shapeLedger.persist(5,shaped);
        check(new GameplayBlocksLedger(save,SURFACE,true).initialStates.equals(shaped),"Slab half and stair facing/corner survive saved ownership reopen");
        reject(()->shapeLedger.persist(6,Map.of(a,"minecraft:oak_slab[type=bottom,waterlogged=true]")),"Saved ownership cannot adopt waterlogged shapes");
        var connected=Map.of(a,fence,b,wall);shapeLedger.persist(6,connected);
        var connectedLedger=new GameplayBlocksLedger(save,SURFACE,true);
        check(connectedLedger.initialStates.equals(connected)&&connectedLedger.initialRevision==6,"Fence connections and wall post/heights survive saved ownership reopen");
        var neighborChanged=Map.of(a,fence.replace("north=true","north=false"),b,wall.replace("south=tall","south=none").replace("up=false","up=true"));
        connectedLedger.persist(7,neighborChanged);
        check(new GameplayBlocksLedger(save,SURFACE,true).initialStates.equals(neighborChanged),"Neighbor-driven connection/post changes persist without changing cell ownership");
        reject(()->connectedLedger.persist(8,Map.of(a,fence.replace("waterlogged=false","waterlogged=true"))),"Connected checkpoint rejects wet fence");
        reject(()->connectedLedger.persist(8,Map.of(b,wall.replace("waterlogged=false","waterlogged=true"))),"Connected checkpoint rejects wet wall");
    }
    private static void terrainLedgerTests(Path root)throws Exception{
        var seed=GameplayTerrain.initial(tile(0));var grown=seed.admit(1,0,tile(1));
        var cell=new GameplayBlocksLedger.Cell(7,64,0);
        check(!GameplayBlocksLedger.allowed(seed,cell)&&GameplayBlocksLedger.allowed(grown,cell),"Block permission opens only on actually admitted terrain");
        check(!GameplayBlocksLedger.allowed(grown,new GameplayBlocksLedger.Cell(7,64,7)),"An unadmitted corner remains closed for blocks");
        check(!GameplayBlocksLedger.allowed(grown,new GameplayBlocksLedger.Cell(12,64,0)),"New outer terrain frontier remains closed for blocks");
        var save=GameplayWorld.prepare(root.resolve("expanded-instance/saves"),root);var ledger=new GameplayBlocksLedger(save,seed);
        reject(()->ledger.persist(1,Set.of(cell)),"Old ledger surface cannot claim expanded blocks");
        ledger.surface=grown;ledger.persist(1,Set.of(cell));
        check(new GameplayBlocksLedger(save,grown).initial.equals(Set.of(cell)),"Expanded block ownership reopens with admitted saved coverage");
        reject(()->new GameplayBlocksLedger(save,seed),"Missing saved tile cannot silently adopt expanded block ownership");
        var reopened=new GameplayBlocksLedger(save,grown);reopened.persist(2,Set.of());
        check(new GameplayBlocksLedger(save,grown).initial.isEmpty(),"Removing expanded-terrain block persists normally");
    }
    private static GroundPatch tile(int tx)throws IOException{
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("run",String.format("%032x",tx+1));j.addProperty("grid_size",9);j.addProperty("spacing",1);j.addProperty("walking_area","wide");
        var center=new JsonObject();center.addProperty("x",120+8*tx);center.addProperty("y",2040);center.addProperty("z",56);j.add("center",center);
        var provenance=new JsonObject();provenance.addProperty("kind","standalone_fixture");j.add("provenance",provenance);var points=new JsonArray();
        for(int row=0;row<9;row++)for(int col=0;col<9;col++){var p=new JsonObject();p.addProperty("index",row*9+col+1);p.addProperty("x",120+8*tx+col-4);p.addProperty("y",2040+row-4);p.addProperty("z",56);p.addProperty("nx",0);p.addProperty("ny",0);p.addProperty("nz",1);points.add(p);}j.add("points",points);
        return GroundPatch.parse(j.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8),true);
    }
    private static JsonObject aimJson(HudInputProtocol.Identity id,GameplayWorld save,long utc){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_aim_v1");j.addProperty("run",id.run());j.addProperty("world_id",save.id().toString());
        j.addProperty("patch_run",SURFACE.run());j.addProperty("patch_sha256",SURFACE.sha256());j.addProperty("target_pid",id.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(id.targetStart()));
        j.addProperty("seq",1);j.addProperty("utc_ms",utc);j.add("origin",JsonParser.parseString("{\"x\":102.5,\"y\":199.5,\"z\":51.62}"));
        j.add("direction",JsonParser.parseString("{\"x\":1,\"y\":0,\"z\":0}"));j.addProperty("range",4.5);j.addProperty("known",true);j.addProperty("distance",-1);j.addProperty("terrain_hit",false);return j;
    }
    private static void aimTests(Path root,GameplayWorld save)throws Exception{
        long now=System.currentTimeMillis();var id=new HudInputProtocol.Identity("b".repeat(32),12,345,34,678,now+60_000);
        var valid=aimJson(id,save,now);String world=save.id().toString();
        GameplayAimReader.parse(valid.toString(),id,world,SURFACE,now);checks++;
        var view=valid.deepCopy();view.addProperty("schema",2);view.addProperty("kind","minecome_gameplay_aim_v2");
        view.add("up",JsonParser.parseString("{\"x\":0,\"y\":0,\"z\":1}"));view.addProperty("vertical_fov",1.2);
        check(GameplayAimReader.parse(view.toString(),id,world,SURFACE,now).get("schema").getAsInt()==2,"World-block aim v2 accepts exact orthogonal camera/FOV");
        for(double bad:List.of(0.0,.05,Math.PI,4.0)){
            var changed=view.deepCopy();changed.addProperty("vertical_fov",bad);reject(()->GameplayAimReader.parse(changed.toString(),id,world,SURFACE,now),"Invalid vertical FOV rejected");
        }
        var missingUp=view.deepCopy();missingUp.remove("up");reject(()->GameplayAimReader.parse(missingUp.toString(),id,world,SURFACE,now),"World camera cannot omit up basis");
        var nonunitUp=view.deepCopy();nonunitUp.getAsJsonObject("up").addProperty("z",2);reject(()->GameplayAimReader.parse(nonunitUp.toString(),id,world,SURFACE,now),"Nonunit up rejected");
        var parallelUp=view.deepCopy();parallelUp.add("up",view.get("direction").deepCopy());reject(()->GameplayAimReader.parse(parallelUp.toString(),id,world,SURFACE,now),"Parallel camera basis rejected");
        var textFov=view.deepCopy();textFov.addProperty("vertical_fov","1.2");reject(()->GameplayAimReader.parse(textFov.toString(),id,world,SURFACE,now),"String camera FOV rejected");
        for(String key:List.of("kind","run","world_id","patch_run","patch_sha256","target_start_filetime")){
            var j=valid.deepCopy();j.addProperty(key,"foreign");reject(()->GameplayAimReader.parse(j.toString(),id,world,SURFACE,now),"Foreign aim identity rejected: "+key);
        }
        var pid=valid.deepCopy();pid.addProperty("target_pid",35);reject(()->GameplayAimReader.parse(pid.toString(),id,world,SURFACE,now),"Foreign native process rejected");
        var fraction=valid.deepCopy();fraction.addProperty("seq",1.5);reject(()->GameplayAimReader.parse(fraction.toString(),id,world,SURFACE,now),"Fractional sequence rejected");
        var vector=valid.deepCopy();vector.getAsJsonObject("direction").addProperty("x",2);reject(()->GameplayAimReader.parse(vector.toString(),id,world,SURFACE,now),"Nonunit native direction rejected");
        String duplicate=valid.toString().replaceFirst("\\{","{\"seq\":1,");
        reject(()->GameplayAimReader.parse(duplicate,id,world,SURFACE,now),"Duplicate aim keys rejected");
        String duplicateVector=valid.toString().replace("\"direction\":{","\"direction\":{\"x\":1,");
        reject(()->GameplayAimReader.parse(duplicateVector,id,world,SURFACE,now),"Duplicate vector keys rejected");
        var unknown=valid.deepCopy();unknown.addProperty("known",false);unknown.addProperty("terrain_hit",true);unknown.addProperty("distance",2);
        reject(()->GameplayAimReader.parse(unknown.toString(),id,world,SURFACE,now),"Terrain hit requires known native ray");
        var unknownHit=valid.deepCopy();unknownHit.addProperty("known",false);unknownHit.addProperty("distance",2);
        reject(()->GameplayAimReader.parse(unknownHit.toString(),id,world,SURFACE,now),"Unknown native ray cannot claim a measured hit distance");
        var clearTerrain=valid.deepCopy();clearTerrain.addProperty("terrain_hit",true);
        reject(()->GameplayAimReader.parse(clearTerrain.toString(),id,world,SURFACE,now),"Clear ray cannot classify a terrain hit");
        var future=valid.deepCopy();future.addProperty("utc_ms",now+51);
        reject(()->GameplayAimReader.parse(future.toString(),id,world,SURFACE,now),"Future source timestamp rejected");
        var nonBoolean=valid.deepCopy();nonBoolean.addProperty("known","true");
        reject(()->GameplayAimReader.parse(nonBoolean.toString(),id,world,SURFACE,now),"Native result flag requires boolean");

        Path directory=Files.createDirectories(root.resolve("runtime/evidence/aim-reader"));Path file=directory.resolve("gameplay-aim.json");
        var fresh=aimJson(id,save,System.currentTimeMillis());write(file,fresh);
        try(var reader=new GameplayAimReader(directory,id,SURFACE,world)){
            long deadline=System.nanoTime()+2_000_000_000L;GameplayBlocks.Aim sample;
            while((sample=reader.current())==null&&reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            check(sample!=null&&reader.failure()==null,"Reader publishes exact native sample");
            check(sample.origin().squaredDistanceTo(new net.minecraft.util.math.Vec3d(2.5,65.62,.5))<1e-15,"Native origin maps into persistent Minecraft coordinates");
            check(sample.direction().squaredDistanceTo(new net.minecraft.util.math.Vec3d(1,0,0))<1e-15,"Native direction maps without an eye-height guess");
            check(sample.fresh(sample.capturedUtcMs()+300,sample.observedAtNanos()+300_000_000L),"Exact freshness boundary accepted");
            check(!sample.fresh(sample.capturedUtcMs()+301,sample.observedAtNanos()+10_000_000L),"Old source time expires even with a new read");
            check(!sample.fresh(sample.capturedUtcMs(),sample.observedAtNanos()+300_000_001L),"Old local observation expires independently");
            check(!sample.fresh(sample.capturedUtcMs()-51,sample.observedAtNanos()),"Future source sample not accepted");
            Thread.sleep(320);check(reader.current()==null&&reader.failure()==null,"Repeated unchanged file cannot refresh source freshness");
            var stale=aimJson(id,save,fresh.get("utc_ms").getAsLong());stale.addProperty("seq",2);GameplayBlocksFiles.atomic(file,stale.toString());
            Thread.sleep(30);check(reader.current()==null&&reader.failure()==null,"A new sequence cannot revive an old source observation");
            var next=aimJson(id,save,System.currentTimeMillis());next.addProperty("seq",3);GameplayBlocksFiles.atomic(file,next.toString());
            deadline=System.nanoTime()+1_000_000_000L;while(reader.current()==null&&reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            check(reader.current()!=null&&reader.failure()==null,"Fresh replacement restores availability");
            var repeated=aimJson(id,save,System.currentTimeMillis());repeated.addProperty("seq",3);repeated.addProperty("range",4);GameplayBlocksFiles.atomic(file,repeated.toString());
            deadline=System.nanoTime()+1_000_000_000L;while(reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            check(reader.failure()!=null&&reader.current()==null,"Mutated same-sequence snapshot fails closed without reusing its previous sample");
        }
        Path closingDirectory=Files.createDirectories(root.resolve("runtime/evidence/aim-closing"));
        write(closingDirectory.resolve("gameplay-aim.json"),aimJson(id,save,System.currentTimeMillis()));
        var closing=new GameplayAimReader(closingDirectory,id,SURFACE,world);closing.close();
        Thread.sleep(20);check(closing.current()==null,"Closing never exposes a concurrently finishing read");

        Path viewDirectory=Files.createDirectories(root.resolve("runtime/evidence/world-camera-reader"));
        view.addProperty("utc_ms",System.currentTimeMillis());write(viewDirectory.resolve("gameplay-aim.json"),view);
        try(var reader=new GameplayAimReader(viewDirectory,id,SURFACE,world,true)){
            long deadline=System.nanoTime()+1_000_000_000L;while(reader.worldSample()==null&&reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            var sample=reader.worldSample();check(sample!=null&&sample.aim().equals(reader.current())&&reader.failure()==null,"World-block reader publishes matching aim and camera");var camera=sample.view();
            check(sample.schema()==2&&sample.perspective()==0,"Legacy camera retains first person without claiming perspective acknowledgment");
            check(camera.origin().squaredDistanceTo(new net.minecraft.util.math.Vec3d(2.5,65.62,.5))<1e-15,"World camera origin uses native coordinate transform");
            check(camera.forward().squaredDistanceTo(new net.minecraft.util.math.Vec3d(1,0,0))<1e-15&&camera.up().squaredDistanceTo(new net.minecraft.util.math.Vec3d(0,1,0))<1e-15,"World camera basis uses same transform as aiming");
            check(Math.abs(camera.verticalFovRadians()-1.2)<1e-12,"World camera retains actual vertical FOV");
            Thread.sleep(320);check(reader.worldSample()==null&&reader.current()==null&&reader.failure()==null,"Expired camera cannot keep world blocks rendered at a stale view");
        }
        Path legacyView=Files.createDirectories(root.resolve("runtime/evidence/world-camera-legacy"));
        write(legacyView.resolve("gameplay-aim.json"),aimJson(id,save,System.currentTimeMillis()));
        try(var reader=new GameplayAimReader(legacyView,id,SURFACE,world,true)){
            long deadline=System.nanoTime()+1_000_000_000L;while(reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            check(reader.failure()!=null&&reader.worldSample()==null,"World renderer rejects legacy aim without camera/FOV instead of guessing");
        }
        perspectiveAimTests(root,save,id,view);
    }
    private static JsonObject perspectiveAim(JsonObject view,int mode){
        var j=view.deepCopy();j.addProperty("schema",3);j.addProperty("kind","minecome_gameplay_aim_v3");j.addProperty("perspective",mode);
        j.add("camera_origin",j.get("origin").deepCopy());j.add("camera_direction",j.get("direction").deepCopy());j.add("camera_up",j.remove("up"));
        if(mode!=0)j.getAsJsonObject("camera_origin").addProperty("x",mode==1?100:105);
        if(mode==2){j.getAsJsonObject("camera_direction").addProperty("x",-1);j.getAsJsonObject("direction").addProperty("x",-1);}
        return j;
    }
    private static void perspectiveAimTests(Path root,GameplayWorld save,HudInputProtocol.Identity id,JsonObject view)throws Exception{
        String world=save.id().toString();long now=System.currentTimeMillis();
        for(int mode=0;mode<3;mode++){
            var j=perspectiveAim(view,mode);j.addProperty("utc_ms",now);
            check(GameplayAimReader.parse(j.toString(),id,world,SURFACE,now).get("perspective").getAsInt()==mode,"First/back/front acknowledged camera accepted");
            var expected=new net.minecraft.client.option.Perspective[]{net.minecraft.client.option.Perspective.FIRST_PERSON,net.minecraft.client.option.Perspective.THIRD_PERSON_BACK,net.minecraft.client.option.Perspective.THIRD_PERSON_FRONT};
            check(dev.minecome.hud.GameplayPerspective.acknowledged(mode)==expected[mode],"Acknowledged wire mode selects the exact vanilla perspective");
            if(mode!=0){j.add("camera_origin",j.get("origin").deepCopy());GameplayAimReader.parse(j.toString(),id,world,SURFACE,now);checks++;}
        }
        var valid=perspectiveAim(view,1);valid.addProperty("utc_ms",now);
        // Crosshair target parallax may make the interaction ray differ from the
        // view direction. Neither direction may overwrite the other on import.
        valid.add("direction",JsonParser.parseString("{\"x\":0.8,\"y\":0.6,\"z\":0}"));
        GameplayAimReader.parse(valid.toString(),id,world,SURFACE,now);checks++;
        for(String field:List.of("camera_origin","camera_direction","camera_up","perspective")){
            var j=valid.deepCopy();j.remove(field);reject(()->GameplayAimReader.parse(j.toString(),id,world,SURFACE,now),"Schema3 requires separate camera field: "+field);
        }
        var legacyUp=valid.deepCopy();legacyUp.add("up",legacyUp.get("camera_up").deepCopy());reject(()->GameplayAimReader.parse(legacyUp.toString(),id,world,SURFACE,now),"Schema3 does not admit ambiguous legacy up field");
        for(double mode:List.of(-1.,3.,1.5)){
            var j=valid.deepCopy();j.addProperty("perspective",mode);reject(()->GameplayAimReader.parse(j.toString(),id,world,SURFACE,now),"Unknown/fractional acknowledged perspective rejected");
        }
        var textMode=valid.deepCopy();textMode.addProperty("perspective","1");reject(()->GameplayAimReader.parse(textMode.toString(),id,world,SURFACE,now),"Perspective requires integer wire type");
        var boundary=valid.deepCopy();boundary.getAsJsonObject("camera_origin").addProperty("x",98.5);GameplayAimReader.parse(boundary.toString(),id,world,SURFACE,now);checks++;
        boundary.getAsJsonObject("camera_origin").addProperty("x",98.4999);reject(()->GameplayAimReader.parse(boundary.toString(),id,world,SURFACE,now),"Camera outside four metre eye bound rejected");
        var first=perspectiveAim(view,0);first.addProperty("utc_ms",now);first.getAsJsonObject("camera_origin").addProperty("x",102.61);
        reject(()->GameplayAimReader.parse(first.toString(),id,world,SURFACE,now),"First person cannot hide a displaced third-person camera");
        var wrongFirst=perspectiveAim(view,0);wrongFirst.addProperty("utc_ms",now);wrongFirst.getAsJsonObject("camera_direction").addProperty("x",-1);
        reject(()->GameplayAimReader.parse(wrongFirst.toString(),id,world,SURFACE,now),"First person camera must agree with eye direction");
        for(String field:List.of("camera_direction","camera_up")){
            var j=valid.deepCopy();j.getAsJsonObject(field).addProperty(field.equals("camera_up")?"z":"x",2);reject(()->GameplayAimReader.parse(j.toString(),id,world,SURFACE,now),"Camera basis remains unit: "+field);
        }
        var parallel=valid.deepCopy();parallel.add("camera_up",parallel.get("camera_direction").deepCopy());reject(()->GameplayAimReader.parse(parallel.toString(),id,world,SURFACE,now),"Separate camera basis must remain orthogonal");
        var huge=valid.deepCopy();huge.getAsJsonObject("camera_origin").addProperty("z",new java.math.BigDecimal("1e999"));reject(()->GameplayAimReader.parse(huge.toString(),id,world,SURFACE,now),"Nonfinite camera values rejected");
        String duplicate=valid.toString().replace("\"camera_origin\":{","\"camera_origin\":{\"x\":100,");reject(()->GameplayAimReader.parse(duplicate,id,world,SURFACE,now),"Separate camera duplicate vector keys rejected");
        Path directory=Files.createDirectories(root.resolve("runtime/evidence/perspective-camera-reader"));var file=directory.resolve("gameplay-aim.json");
        valid.addProperty("utc_ms",System.currentTimeMillis());write(file,valid);
        try(var reader=new GameplayAimReader(directory,id,SURFACE,world,true)){
            long deadline=System.nanoTime()+1_000_000_000L;while(reader.worldSample()==null&&reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            var sample=reader.worldSample();check(sample!=null&&reader.failure()==null&&sample.perspective()==1&&sample.schema()==3,"Reader imports acknowledged third-back perspective");
            check(sample.aim().equals(reader.current())&&sample.aim().origin().squaredDistanceTo(new net.minecraft.util.math.Vec3d(2.5,65.62,.5))<1e-15,"Interaction origin retains player eye rather than displaced camera");
            check(sample.view().origin().squaredDistanceTo(new net.minecraft.util.math.Vec3d(0,65.62,.5))<1e-15,"Render camera imports distinct displaced origin");
            check(sample.aim().cameraOrigin().equals(sample.view().origin()),"Controller visibility and renderer retain the same admitted displaced camera");
            check(sample.aim().direction().squaredDistanceTo(new net.minecraft.util.math.Vec3d(.8,0,-.6))<1e-15&&sample.view().forward().squaredDistanceTo(new net.minecraft.util.math.Vec3d(1,0,0))<1e-15,"Eye ray and render ray retain their distinct mapped directions");
            var front=perspectiveAim(view,2);front.addProperty("seq",2);front.addProperty("utc_ms",System.currentTimeMillis());GameplayBlocksFiles.atomic(file,front.toString());
            deadline=System.nanoTime()+1_000_000_000L;while((sample=reader.worldSample())!=null&&sample.perspective()!=2&&reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            check(sample!=null&&sample.perspective()==2&&sample.view().origin().x==5&&sample.aim().origin().x==2.5&&sample.view().forward().x==-1,"Mode/camera/interaction publish atomically during front transition");
            Thread.sleep(320);check(reader.worldSample()==null&&reader.current()==null&&reader.failure()==null,"Perspective camera obeys unchanged dual freshness deadlines");
            front.addProperty("utc_ms",System.currentTimeMillis());GameplayBlocksFiles.atomic(file,front.toString());
            deadline=System.nanoTime()+1_000_000_000L;while(reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            check(reader.failure()!=null&&reader.current()==null&&reader.worldSample()==null,"Same-sequence perspective replay invalidates all published view/aim state");
        }
    }
}
