package dev.minecome.terrain;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayWorld;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Additive geometry, hole/frontier coverage, and save/reopen invariants; no game process. */
public final class GameplayTerrainTests {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Action action,String message)throws Exception{try{action.run();throw new AssertionError(message);}catch(IOException|IllegalArgumentException expected){checks++;}}
    public static void main(String[] args)throws Exception{
        String baseRaw=patch(0,0).toString();GroundPatch base=parse(baseRaw);var initial=GameplayTerrain.initial(base);
        check(initial.generation()==0&&initial.tileCount()==1&&initial.base()==base,"Initial capture identity retained");
        check(initial.cells().equals(base.cells())&&initial.slabs().equals(base.slabs()),"Base geometry retained byte-for-value");
        check(initial.run().equals(base.run())&&initial.sha256().equals(base.sha256()),"Protocol identity remains base");
        check(initial.containsFeet(3.5,0,.3)&&!initial.containsFeet(3.8,0,.3),"Uncaptured frontier remains closed");
        String eastRaw=patch(1,0).toString();var east=initial.admit(1,0,parse(eastRaw));
        check(east.generation()==1&&east.hasTile(1,0)&&east.isSuccessorOf(initial),"One adjacent tile admitted");
        check(east.cells().subList(0,initial.cells().size()).equals(initial.cells())&&east.slabs().subList(0,initial.slabs().size()).equals(initial.slabs()),"Admission never recomputes old collision");
        check(east.containsFeet(4,0,.3)&&east.containsFeet(11.69,0,.31)&&!east.containsFeet(11.71,0,.31),"Former seam opens and new boundary brakes");
        check(east.run().equals(initial.run())&&east.sha256().equals(initial.sha256())&&!east.digest().equals(initial.digest()),"Coverage digest changes without rebasing wire identity");
        check(Math.abs(east.heightAt(8,.5)-(64+.01*8.5-.02*.5))<1e-12,"East terrain height stays on original Minecraft anchor");
        var south=east.admit(0,1,parse(patch(0,1).toString()));
        check(south.containsFeet(0,8,.3)&&!south.containsFeet(8,8,.3),"Nonrectangular coverage keeps missing corner closed");
        check(!south.containsFeet(3.9,4.1,.3),"Footprint crossing an uncovered corner is rejected");
        check(south.containsFeet(0,4,.3),"South shared edge opens");
        check(Math.abs(south.heightAt(.5,8)-(64+.01*.5-.02*8.5))<1e-12,"Native negative Y becomes positive Minecraft Z");
        var corner=south.admit(1,1,parse(patch(1,1).toString()));
        check(corner.containsFeet(4,4,.3)&&corner.containsFeet(8,8,.3),"Filling the corner admits crossing footprint");
        var ring=initial;for(var c:List.of(new int[]{1,0},new int[]{2,0},new int[]{2,1},new int[]{2,2},new int[]{1,2},new int[]{0,2},new int[]{0,1}))ring=ring.admit(c[0],c[1],parse(patch(c[0],c[1]).toString()));
        check(ring.containsFeet(0,0,.31)&&ring.containsFeet(16,16,.31)&&!ring.containsRectangle(-.31,-.31,16.31,16.31),"Covered corners do not authorize a braking path across an interior hole");
        var filled=ring.admit(1,1,parse(patch(1,1).toString()));check(filled.containsRectangle(-.31,-.31,16.31,16.31),"Fully covered braking envelope accepted");
        var west=initial.admit(-1,0,parse(patch(-1,0).toString()));
        check(west.containsFeet(-8,0,.3)&&!west.containsFeet(-12,0,.3),"Negative tile coordinates preserve bounds");
        check(!east.isSuccessorOf(west),"Equal generation in another branch cannot become successor");
        reject(()->initial.admit(2,0,parse(patch(2,0).toString())),"Disconnected capture rejected");
        reject(()->east.admit(1,0,parse(eastRaw)),"Duplicate tile rejected");
        reject(()->initial.admit(9,0,parse(patch(9,0).toString())),"Offset bound enforced");
        var changed=patch(1,0);changed.getAsJsonObject("center").addProperty("z",56.1);
        for(var p:changed.getAsJsonArray("points"))p.getAsJsonObject().addProperty("z",p.getAsJsonObject().get("z").getAsDouble()+.1);
        String shifted=changed.toString();reject(()->initial.admit(1,0,parse(shifted)),"Capture cannot move vertical anchor");
        changed=patch(1,0);changed.getAsJsonArray("points").get(0).getAsJsonObject().addProperty("z",56.2);String seam=changed.toString();
        reject(()->initial.admit(1,0,parse(seam)),"Changed edge geometry rejected");
        changed=patch(1,0);changed.getAsJsonObject("provenance").addProperty("kind","live_kcd_ground_patch");String source=changed.toString();
        reject(()->initial.admit(1,0,parse(source)),"Mixed live/fixture captures rejected");
        reject(()->south.groundForFeet(4,4,.3),"No partial footprint ground authority across hole");
        check(!south.containsFeet(Double.NaN,0,.3)&&!south.containsFeet(0,0,-1),"Invalid coverage query rejected");

        Path root=Files.createTempDirectory("minecome-gameplay-terrain-").toRealPath();var save=GameplayWorld.prepare(root.resolve("runtime/instance/saves"),root);
        Path terrain=Files.createDirectory(save.directory().resolve("minecome-terrain"));Path original=terrain.resolve("ground-patch.json");Files.writeString(original,baseRaw);
        var store=GameplayTerrainStore.open(save,base);var start=store.surface();var next=start.admit(1,0,parse(eastRaw));store.persist(start,next,eastRaw);
        check(store.surface()==next,"Persist publishes exact admitted immutable candidate");
        var reopened=GameplayTerrainStore.open(save,base);check(reopened.surface().generation()==1&&reopened.surface().digest().equals(next.digest())&&reopened.surface().cells().equals(next.cells()),"Coverage and exact collision restore after reopen");
        check(Files.readString(original).equals(baseRaw),"Original capture bytes remain untouched");
        reject(()->store.persist(start,next,eastRaw),"Stale predecessor cannot overwrite current coverage");
        var second=next.admit(0,1,parse(patch(0,1).toString()));reject(()->store.persist(next,second,eastRaw),"Candidate raw capture must match admitted digest");
        String good=Files.readString(store.path());Files.writeString(store.path(),good+" ");reject(()->store.persist(next,second,patch(0,1).toString()),"External coverage edits preserved");Files.writeString(store.path(),good);
        for(String field:List.of("world_id","patch_run","patch_sha256","digest","kind")){
            var j=JsonParser.parseString(good).getAsJsonObject();j.addProperty(field,"foreign");Files.writeString(store.path(),j.toString());reject(()->GameplayTerrainStore.open(save,base),"Stored identity rejected: "+field);
        }
        var j=JsonParser.parseString(good).getAsJsonObject();j.addProperty("generation",.5);Files.writeString(store.path(),j.toString());reject(()->GameplayTerrainStore.open(save,base),"Fractional generation rejected");
        Files.writeString(store.path(),good.replace("\"generation\":1","\"generation\":1,\"generation\":1"));reject(()->GameplayTerrainStore.open(save,base),"Duplicate metadata keys rejected");
        j=JsonParser.parseString(good).getAsJsonObject();j.getAsJsonArray("tiles").get(0).getAsJsonObject().addProperty("sha256","a".repeat(64));Files.writeString(store.path(),j.toString());reject(()->GameplayTerrainStore.open(save,base),"Saved tile digest mismatch rejected");
        Files.writeString(store.path(),good);var cap=GameplayTerrain.initial(base);
        for(int z=0;z<8;z++)for(int x=0;x<8;x++)if(x!=0||z!=0)cap=cap.admit(x,z,parse(patch(x,z).toString()));
        check(cap.tileCount()==64&&cap.generation()==63,"Bounded64-tile coverage admitted");final var full=cap;
        reject(()->full.admit(8,0,parse(patch(8,0).toString())),"65th tile refused");
        System.out.println("GameplayTerrainTests: "+checks+" checks passed; no games");
    }
    private static GroundPatch parse(String raw)throws IOException{return GroundPatch.parse(raw.getBytes(StandardCharsets.UTF_8),true);}
    static JsonObject patch(int tx,int tz){
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("run",String.format("%032x",10000+(tx+8)*20+tz+8));p.addProperty("grid_size",9);p.addProperty("spacing",1);p.addProperty("walking_area","wide");
        var c=new JsonObject();c.addProperty("x",120+8*tx);c.addProperty("y",2040-8*tz);c.addProperty("z",56);p.add("center",c);var provenance=new JsonObject();provenance.addProperty("kind","standalone_fixture");p.add("provenance",provenance);
        var points=new JsonArray();double length=Math.sqrt(1+.01*.01+.02*.02);
        for(int row=0;row<9;row++)for(int col=0;col<9;col++){double x=8*tx+col-4,y=-8*tz+row-4;var q=new JsonObject();q.addProperty("index",row*9+col+1);q.addProperty("x",120+x);q.addProperty("y",2040+y);q.addProperty("z",56+.01*x+.02*y);q.addProperty("nx",-.01/length);q.addProperty("ny",-.02/length);q.addProperty("nz",1/length);points.add(q);}p.add("points",points);return p;
    }
}
