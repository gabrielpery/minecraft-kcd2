package dev.minecome.terrain;

import com.google.gson.*;
import dev.minecome.protocol.AimGeometry.Cell;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.UUID;

/** Geometry and profile boundaries for the wider fixed capture; no game bootstrap. */
final class WideWalkingTests {
    private static int checks;
    private interface Work {void run() throws Exception;}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Work work,String message)throws Exception{
        try{work.run();throw new AssertionError("Accepted "+message);}catch(IOException|IllegalArgumentException expected){checks++;}
    }
    private static byte[] bytes(JsonObject value){return value.toString().getBytes(StandardCharsets.UTF_8);}
    private static JsonObject patch(int grid){
        var root=new JsonObject();root.addProperty("schema",1);root.addProperty("run","wide-fixture");
        root.addProperty("grid_size",grid);root.addProperty("spacing",1);
        if(grid==9)root.addProperty("walking_area","wide");
        root.addProperty("point_count",grid*grid);root.addProperty("valid_count",grid*grid);
        var center=new JsonObject();center.addProperty("x",100);center.addProperty("y",200);center.addProperty("z",10);root.add("center",center);
        var points=new JsonArray();int half=(grid-1)/2;
        for(int row=0;row<grid;row++)for(int col=0;col<grid;col++){
            var p=new JsonObject();p.addProperty("index",row*grid+col+1);p.addProperty("x",100+col-half);p.addProperty("y",200+row-half);
            p.addProperty("z",10);p.addProperty("nx",0);p.addProperty("ny",0);p.addProperty("nz",1);points.add(p);
        }
        root.add("points",points);return root;
    }
    public static int run()throws Exception{
        var data=patch(9);var wide=GroundPatch.parse(bytes(data),true);
        check(wide.gridSize()==9&&wide.slabs().size()==64&&wide.cells().size()==64,"Complete 8x8 collision footprint");
        check(wide.heightAt(-3.5,-3.5)==64&&wide.heightAt(3.5,3.5)==64,"New outer corners retain fixed vertical anchor");
        check(wide.containsFeet(3.7,-3.7,.3)&&!wide.containsFeet(3.71,0,.3),"Feet stay inside the expanded capture");
        var region=new HudBuildRegion(wide,new dev.minecome.protocol.AimGeometry.Cell(4,63,0));
        double[][] directions={{1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,1},{-1,-1},{1,-1},{-.18414674699306488,-.9681517481803894}};
        Cell[] expected={new Cell(4,63,-1),new Cell(-5,63,-1),new Cell(-1,63,4),new Cell(-1,63,-5),
                new Cell(1,63,4),new Cell(-5,63,1),new Cell(-5,63,-2),new Cell(1,63,-5),new Cell(-1,63,-5)};
        for(int i=0;i<directions.length;i++){
            double x=directions[i][0],z=directions[i][1];
            var support=HudBuildRegion.facingSupport(wide,63,x,z);
            check(support.equals(expected[i]),"Facing support follows cardinal/diagonal/live heading "+i);
            check(support.equals(HudBuildRegion.facingSupport(wide,63,7*x,7*z)),"Heading magnitude does not change deterministic support "+i);
            var facing=new HudBuildRegion(wide,support);
            double cx=support.x()+.5,cz=support.z()+.5,radius=Math.hypot(cx,cz);
            check(radius<=Math.sqrt(4.5*4.5+1.5*1.5) && (cx*x+cz*z)/(radius*Math.hypot(x,z))>.89,
                    "Facing support retains bounded reach and stays near captured heading "+i);
            check(support.y()==63 && !facing.isImported(support) && !facing.isImported(facing.seed()),
                    "Facing support preserves initial height and imported terrain ownership "+i);
        }
        reject(()->HudBuildRegion.facingSupport(wide,63,0,0),"zero heading");
        reject(()->HudBuildRegion.facingSupport(wide,63,Double.NaN,1),"NaN heading");
        reject(()->HudBuildRegion.facingSupport(wide,63,1,Double.POSITIVE_INFINITY),"infinite heading");
        reject(()->HudBuildRegion.facingSupport(null,63,1,0),"missing heading patch");
        var narrowRegion=new HudBuildRegion(GroundPatch.parse(bytes(patch(5))),new Cell(2,63,0));
        check(narrowRegion.support().equals(new Cell(2,63,0)),"Narrow fixed support remains unchanged");
        check(region.seed().x()==4&&region.isImported(new dev.minecome.protocol.AimGeometry.Cell(3,63,0)),"Wide live build support stays beside protected imported ground");
        check(region.targetRejection(new dev.minecome.protocol.AimGeometry.Cell(4,65,0))==null
                &&region.targetRejection(new dev.minecome.protocol.AimGeometry.Cell(3,64,0))==null,
                "Wide fixture top and facing-side targets remain separate from protected imported cells");
        reject(()->new HudBuildRegion(wide,new dev.minecome.protocol.AimGeometry.Cell(2,63,0)),"old lab support cannot overwrite newly covered terrain");
        reject(()->GroundPatch.parse(bytes(data)),"wide capture without opt-in");
        reject(()->GroundPatch.parse(bytes(patch(5)),true),"narrow capture in wide profile");
        var missing=data.deepCopy();missing.remove("walking_area");reject(()->GroundPatch.parse(bytes(missing),true),"missing wide marker");
        var narrow=patch(5);narrow.addProperty("walking_area","wide");reject(()->GroundPatch.parse(bytes(narrow)),"marker cannot enlarge narrow profile");
        var partial=data.deepCopy();partial.getAsJsonArray("points").remove(80);reject(()->GroundPatch.parse(bytes(partial),true),"missing far-corner point");
        var discontinuity=data.deepCopy();discontinuity.getAsJsonArray("points").get(80).getAsJsonObject().addProperty("z",10.6);
        reject(()->GroundPatch.parse(bytes(discontinuity),true),"new outer edge still enforces step-height limit");
        var sloped=data.deepCopy();for(int i=0;i<81;i++)sloped.getAsJsonArray("points").get(i).getAsJsonObject().addProperty("z",10+.1*(i%9));
        check(Math.abs(GroundPatch.parse(bytes(sloped),true).heightAt(3.5,3.5)-64.75)<1e-8,"Wider tiles preserve host-to-Minecraft axis mapping");
        var origin=new MovementTraceSink.Motion(0,64,0,0,-.0784,0,true,true,true);
        var gate=new HudMovementBoundary(wide,origin);
        check(gate.check(new MovementTraceSink.Motion(0,64,2.2,0,-.0784,0,true,true,true),1,0,false,0,.13001,.42001,true).allow(),"Vanilla movement past old boundary has braking support");
        check(!gate.check(new MovementTraceSink.Motion(0,64,3.4,0,-.0784,.117,true,true,true),1,0,false,0,.13001,.42001,true).allow(),"New edge still reserves full braking distance");
        check(!gate.check(new MovementTraceSink.Motion(0,64.4,0,0,-.0784,0,true,true,true),0,0,true,0,.13001,.42001,false).allow(),"Wider area does not increase vertical authority");
        reject(()->new MovementTraceSink.Motion(0,64,2.2,0,0,0,true,true),"legacy motion retains old axis limit");
        reject(()->new MovementTraceSink.Motion(0,64,4.1,0,0,0,true,true,true),"wide motion still bounded");
        Path root=Files.createTempDirectory("minecome-wide-trace-");Path path=root.resolve("wide.ndjson");String id=UUID.randomUUID().toString();
        var context=new MovementTraceSink.Context("wide-fixture","a".repeat(64),"standalone_ground_fixture","MineCome-HudStream-"+id,id,
                100,200,10,MovementTraceSink.Profile.HUD_PHYSICAL_EXTENDED_FIXTURE,0,64,0,true);
        try(var sink=MovementTraceSink.open(path,root,context,1000,1000)){
            var far=new MovementTraceSink.Motion(0,64,2.2,0,0,0,true,true,true);
            check(sink.sample(1000,1000,"WALKING",far,far,1,1000,true),"Wide trace accepts matching client/server beyond old edge");
            reject(()->sink.sample(2000,2000,"WALKING",new MovementTraceSink.Motion(0,64,0,0,0,0,true,true),far,2,2000,true),"trace rejects mixed area authority");
            sink.finish(2000,"passed","PASSED","fixture");
        }
        check(Files.readAllLines(path).stream().allMatch(line->JsonParser.parseString(line).getAsJsonObject().get("walking_area").getAsString().equals("wide")),"Every trace record binds wide scope");
        Files.delete(path);Files.delete(root);
        return checks;
    }
}
