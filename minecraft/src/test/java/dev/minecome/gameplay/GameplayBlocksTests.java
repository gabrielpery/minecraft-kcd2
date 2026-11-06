package dev.minecome.gameplay;

import com.google.gson.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.*;
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
        System.out.println("GameplayBlocksTests: "+checks+" checks passed; no game calls");
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
            long deadline=System.nanoTime()+1_000_000_000L;while(reader.worldView()==null&&reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            var camera=reader.worldView();check(camera!=null&&reader.current()!=null&&reader.failure()==null,"World-block reader publishes matching aim and camera");
            check(camera.origin().squaredDistanceTo(new net.minecraft.util.math.Vec3d(2.5,65.62,.5))<1e-15,"World camera origin uses native coordinate transform");
            check(camera.forward().squaredDistanceTo(new net.minecraft.util.math.Vec3d(1,0,0))<1e-15&&camera.up().squaredDistanceTo(new net.minecraft.util.math.Vec3d(0,1,0))<1e-15,"World camera basis uses same transform as aiming");
            check(Math.abs(camera.verticalFovRadians()-1.2)<1e-12,"World camera retains actual vertical FOV");
            Thread.sleep(320);check(reader.worldView()==null&&reader.current()==null&&reader.failure()==null,"Expired camera cannot keep world blocks rendered at a stale view");
        }
        Path legacyView=Files.createDirectories(root.resolve("runtime/evidence/world-camera-legacy"));
        write(legacyView.resolve("gameplay-aim.json"),aimJson(id,save,System.currentTimeMillis()));
        try(var reader=new GameplayAimReader(legacyView,id,SURFACE,world,true)){
            long deadline=System.nanoTime()+1_000_000_000L;while(reader.failure()==null&&System.nanoTime()<deadline)Thread.sleep(2);
            check(reader.failure()!=null&&reader.worldView()==null,"World renderer rejects legacy aim without camera/FOV instead of guessing");
        }
    }
}
