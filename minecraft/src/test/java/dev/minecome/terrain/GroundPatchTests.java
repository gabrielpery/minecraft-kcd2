package dev.minecome.terrain;

import com.google.gson.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

/** Pure validation/geometry/decision tests. No Minecraft bootstrap or either game. */
public final class GroundPatchTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static byte[] bytes(JsonObject object){return object.toString().getBytes(StandardCharsets.UTF_8);}
    private static JsonObject fixture() {
        JsonObject root=new JsonObject();root.addProperty("schema",1);root.addProperty("run","fixture-1");
        root.addProperty("grid_size",5);root.addProperty("spacing",1);
        root.addProperty("stable_player",true);root.addProperty("point_count",25);root.addProperty("valid_count",25);
        JsonObject center=new JsonObject();center.addProperty("x",100);center.addProperty("y",200);center.addProperty("z",10);root.add("center",center);
        JsonObject provenance=new JsonObject();provenance.addProperty("kind","standalone_fixture");root.add("provenance",provenance);
        JsonArray points=new JsonArray();
        for(int row=0;row<5;row++)for(int col=0;col<5;col++) {
            JsonObject point=new JsonObject();point.addProperty("index",row*5+col+1);point.addProperty("x",100+col-2);point.addProperty("y",200+row-2);
            point.addProperty("z",10);point.addProperty("nx",0);point.addProperty("ny",0);point.addProperty("nz",1);
            point.addProperty("valid",true);point.addProperty("result","hit");points.add(point);
        }
        root.add("points",points);return root;
    }
    private static JsonObject point(JsonObject root,int index){return root.getAsJsonArray("points").get(index).getAsJsonObject();}
    private static void reject(JsonObject value,String message)throws Exception{reject(bytes(value),message);}
    private static void reject(byte[] data,String message)throws Exception {
        try{GroundPatch.parse(data);throw new AssertionError("Accepted "+message);}catch(IOException expected){checks++;}
    }
    public static void main(String[] args)throws Exception {
        GroundPatch patch=GroundPatch.parse(bytes(fixture()));
        check(patch.points().size()==25 && patch.slabs().size()==16,"complete5x5 grid yields16 cells");
        check(patch.sourceKind().equals("standalone_fixture") && patch.sha256().length()==64,"fixture provenance/hash kept explicit");
        check(patch.heightAt(0.5,0.5)==64 && patch.groundForFeet(0.5,0.5,0.3)==64,"flat surface anchored at64");
        for(var slab:patch.slabs()) {
            check(slab.maxX()-slab.minX()==1 && slab.maxZ()-slab.minZ()==1,"one-meter horizontal tile");
            check(slab.maxY()-slab.minY()==0.5,"approximate slab thickness0.5");
        }
        for(var cell:patch.cells())check(cell.minY()>=0 && cell.maxY()<=1 && cell.maxY()>cell.minY(),"cell-local vertical shape bounds");
        check(patch.containsFeet(1.5,1.5,0.5) && !patch.containsFeet(1.501,0,0.5),"footprint stays inside finite patch");
        JsonObject slope=fixture();
        for(int row=0;row<5;row++)for(int col=0;col<5;col++)point(slope,row*5+col).addProperty("z",10+0.1*(col-2)+0.2*(row-2));
        GroundPatch inclined=GroundPatch.parse(bytes(slope));
        check(Math.abs(inclined.heightAt(0.5,0.5)-63.95)<1e-8,"KCD+Y maps toMC-Z and four corners are averaged");
        check(Math.abs(inclined.heightAt(-0.5,-0.5)-64.05)<1e-8,"opposite signed tile height");
        check(inclined.cells().size()>16 && inclined.cells().size()<=32,"slabs crossing vertical cell boundary split correctly");
        JsonObject bad=fixture();point(bad,24).addProperty("index",1);reject(bad,"duplicate/missing index");
        bad=fixture();point(bad,0).addProperty("index",0);reject(bad,"index0");
        bad=fixture();point(bad,0).addProperty("x",99);reject(bad,"off-grid coordinate");
        bad=fixture();point(bad,0).addProperty("valid",false);reject(bad,"invalid hit");
        bad=fixture();point(bad,0).addProperty("result","no_hit");reject(bad,"missing host ground");
        bad=fixture();point(bad,0).addProperty("nz",-1);reject(bad,"downward normal");
        bad=fixture();point(bad,0).addProperty("nx",2);reject(bad,"non-unit normal");
        bad=fixture();point(bad,0).addProperty("z",10.6);reject(bad,"adjacent height discontinuity");
        bad=fixture();point(bad,0).addProperty("z",19);reject(bad,"height bound");
        bad=fixture();bad.addProperty("stable_player",false);reject(bad,"host moved during sampling");
        bad=fixture();bad.addProperty("valid_count",24);reject(bad,"partial summary");
        bad=fixture();bad.addProperty("spacing",2);reject(bad,"wrong grid spacing");
        bad=fixture();point(bad,0).addProperty("z","10");reject(bad,"quoted numeric input");
        bad=fixture();bad.getAsJsonArray("points").remove(24);reject(bad,"partial points array");
        String json=fixture().toString();
        reject(json.replace("\"schema\":1","\"schema\":1,\"schema\":1").getBytes(StandardCharsets.UTF_8),"duplicate JSON key");
        reject((json+" {}").getBytes(StandardCharsets.UTF_8),"trailing JSON value");
        reject(json.replaceFirst("\"z\":10","\"z\":1e999").getBytes(StandardCharsets.UTF_8),"overflowing numeric exponent");
        reject(new byte[]{(byte)0xc3,(byte)0x28},"malformed UTF8");reject(new byte[GroundPatch.MAX_BYTES+1],"oversize file");
        sequence(patch);
        checks+=MovementTraceSinkTests.run();
        checks+=WideWalkingTests.run();
        System.out.println("GroundPatchTests: "+checks+" checks passed (no Minecraft/game bootstrap)");
    }
    private static GroundMovementSequence.Motion ground(double x){return new GroundMovementSequence.Motion(x,64,0.5,0,0,0,true,true);}
    private static void sequence(GroundPatch patch) {
        var sequence=new GroundMovementSequence(patch,0);
        check(!sequence.update(0,ground(0.5),ground(0.5),1).forward(),"initial ground does not immediately walk");
        check(!sequence.update(1_999_000_000L,ground(0.5),ground(0.5),1).forward(),"wait full stable2s");
        check(sequence.update(2_000_000_000L,ground(0.5),ground(0.5),1).forward(),"stable actual client/server starts vanilla held input");
        for(int i=1;i<=6;i++)sequence.update(2_000_000_000L+i*50_000_000L,ground(0.5-i*0.15),ground(0.5-i*0.15),1);
        check(sequence.phase()==GroundMovementSequence.Phase.RESTING,"walk input bounded to six ticks");
        sequence.update(2_350_000_000L,ground(-0.4),ground(-0.4),1);
        check(sequence.update(3_350_000_000L,ground(-0.4),ground(-0.4),1).jump(),"jump begins after released movement and stable rest");
        var air=new GroundMovementSequence.Motion(-0.4,64.5,0.5,0,0.2,0,false,false);
        check(!sequence.update(3_400_000_000L,air,air,1).forward(),"jump never holds forward");
        sequence.update(3_450_000_000L,air,air,1);sequence.update(4_000_000_000L,ground(-0.4),ground(-0.4),1);
        sequence.update(4_600_000_000L,ground(-0.4),ground(-0.4),1);
        check(sequence.phase()==GroundMovementSequence.Phase.PASSED && sequence.clientAir() && sequence.serverAir() &&
                sequence.clientLand() && sequence.serverLand(),"independent client/server air and land evidence required");
        var missing=new GroundMovementSequence(patch,0);
        var unsupported=new GroundMovementSequence.Motion(0.5,64,0.5,0,0,0,true,false);
        missing.update(0,ground(0.5),unsupported,0);missing.update(20_100_000_000L,ground(0.5),unsupported,0);
        check(missing.phase()==GroundMovementSequence.Phase.FAILED,"client-only ground cannot pass");
        var edge=new GroundMovementSequence(patch,0);edge.update(0,ground(1.6),ground(1.6),0);
        check(edge.phase()==GroundMovementSequence.Phase.FAILED,"stop before leaving finite coverage");
        var correction=new GroundMovementSequence(patch,0);correction.update(0,ground(0.5),ground(0.5),1);
        correction.update(2_000_000_000L,ground(0.5),ground(0.5),1);correction.update(2_050_000_000L,ground(0.5),ground(0.5),2);
        check(correction.phase()==GroundMovementSequence.Phase.FAILED,"post-handoff vanilla correction is reported as failure");
        var velocity=new GroundMovementSequence(patch,0);
        var approaching=new GroundMovementSequence.Motion(1.3,64,0.5,0.2,0,0,true,true);velocity.update(0,approaching,approaching,0);
        check(velocity.phase()==GroundMovementSequence.Phase.FAILED,"velocity lookahead prevents crossing patch edge");
    }
}
