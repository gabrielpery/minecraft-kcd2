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
        System.out.println("GameplayBlocksTests: "+checks+" checks passed; no game calls");
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
    }
}
