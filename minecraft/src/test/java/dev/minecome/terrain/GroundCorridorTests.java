package dev.minecome.terrain;

import com.google.gson.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;

/** Fixed shared-anchor corridor parsing/geometry; no game is started. */
final class GroundCorridorTests {
    private static int checks;
    private interface Work {void run()throws Exception;}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Work work,String message)throws Exception{
        try{work.run();throw new AssertionError("Accepted "+message);}catch(IOException|IllegalArgumentException expected){checks++;}
    }
    static byte[] bytes(JsonObject value){return value.toString().getBytes(StandardCharsets.UTF_8);}
    static GroundCorridor flatCorridor()throws Exception{return GroundCorridor.parse(bytes(fixture("standalone_fixture",0)));}
    private static String hash(byte[] bytes)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}
    static JsonObject fixture(String source,double slope)throws Exception{
        var manifest=new JsonObject();manifest.addProperty("schema",1);manifest.addProperty("kind","minecome_ground_corridor_v1");manifest.addProperty("run","corridor-fixture");
        var tiles=new JsonArray();
        for(int tile=0;tile<2;tile++){
            var patch=new JsonObject();patch.addProperty("schema",1);patch.addProperty("run","corridor-fixture");
            patch.addProperty("grid_size",9);patch.addProperty("spacing",1);patch.addProperty("walking_area","wide");
            patch.addProperty("stable_player",true);patch.addProperty("point_count",81);patch.addProperty("valid_count",81);
            var center=new JsonObject();center.addProperty("x",100+tile*4);center.addProperty("y",200);center.addProperty("z",10);patch.add("center",center);
            var provenance=new JsonObject();provenance.addProperty("kind",source);patch.add("provenance",provenance);
            var points=new JsonArray();
            for(int row=0;row<9;row++)for(int col=0;col<9;col++){
                int x=tile*4+col-4,y=row-4;double normal=Math.sqrt(1+slope*slope);
                var point=new JsonObject();point.addProperty("index",row*9+col+1);point.addProperty("x",100+x);point.addProperty("y",200+y);
                point.addProperty("z",10+slope*x);point.addProperty("nx",-slope/normal);point.addProperty("ny",0);point.addProperty("nz",1/normal);
                point.addProperty("valid",true);point.addProperty("result","hit");points.add(point);
            }
            patch.add("points",points);var entry=new JsonObject();entry.addProperty("sha256",hash(bytes(patch)));entry.addProperty("json",patch.toString());tiles.add(entry);
        }
        manifest.add("tiles",tiles);return manifest;
    }
    private static JsonObject tile(JsonObject manifest,int index){return JsonParser.parseString(manifest.getAsJsonArray("tiles").get(index).getAsJsonObject().get("json").getAsString()).getAsJsonObject();}
    private static void replace(JsonObject manifest,int index,JsonObject tile)throws Exception{
        var entry=manifest.getAsJsonArray("tiles").get(index).getAsJsonObject();entry.addProperty("json",tile.toString());entry.addProperty("sha256",hash(bytes(tile)));
    }
    static int run()throws Exception{
        var manifest=fixture("standalone_fixture",.1);byte[] input=bytes(manifest);var surface=GroundCorridor.parse(input);
        check(surface.corridor()&&surface.wide()&&surface.sourceKind().equals("standalone_corridor_fixture"),"Explicit standalone corridor provenance");
        check(surface.centerX()==100&&surface.centerY()==200&&surface.centerZ()==10,"Original host anchor is unchanged");
        check(surface.points().size()==117&&surface.slabs().size()==96,"Overlap is deduplicated into one complete rectangle");
        check(surface.sha256().equals(hash(input))&&surface.tileHashes().size()==2,"Manifest and raw tile identities retained");
        check(Math.abs(surface.heightAt(-3.5,.5)-63.65)<1e-9&&Math.abs(surface.heightAt(6.5,.5)-64.65)<1e-9,"Second tile keeps original coordinate and height anchor");
        check(Math.abs(surface.heightAt(3.9,.5)-64.35)<1e-9&&Math.abs(surface.heightAt(4.1,.5)-64.45)<1e-9,"Crossing old boundary continues captured slope");
        check(surface.groundForFeet(4,.5,.3)==surface.heightAt(4.1,.5),"Feet spanning the seam use the higher adjacent support");
        check(surface.groundForFeet(4,.5,0)==surface.heightAt(4,.5),"Point support at exact cell boundary is defined");
        check(surface.containsFeet(7.7,3.7,.3)&&!surface.containsFeet(7.71,3.7,.3)&&!surface.containsFeet(-3.71,0,.3),"Full footprint remains inside rectangular coverage");
        check(!surface.containsFeet(Double.NaN,0,.3)&&!surface.containsFeet(0,0,-.1)&&!surface.containsFeet(0,0,Double.POSITIVE_INFINITY),"Invalid footprint queries fail closed");
        reject(()->surface.groundForFeet(7.9,0,.3),"partial-foot support outside rectangle");
        reject(()->surface.heightAt(8,0),"outside surface height lookup");
        var occupied=new HashSet<String>();for(var cell:surface.cells())check(occupied.add(cell.x()+","+cell.y()+","+cell.z()),"No duplicate collision cells");
        var live=GroundCorridor.parse(bytes(fixture("live_kcd_ground_patch",0)));
        check(live.sourceKind().equals("live_kcd_ground_corridor")&&live.cells().size()==96,"Live tile provenance remains distinct from synthetic fixture");
        reject(()->GroundPatch.parse(input,true),"corridor passed to legacy wide-patch parser");
        for(String change:List.of("hash","run","kind","count","unknown","mixed","unsupported","offset","height_anchor","overlap_height","overlap_normal","narrow","partial","tile_run")){
            var bad=manifest.deepCopy();var second=tile(bad,1);boolean rewrite=true;
            switch(change){
                case "hash" -> {bad.getAsJsonArray("tiles").get(1).getAsJsonObject().addProperty("sha256","0".repeat(64));rewrite=false;}
                case "run" -> {bad.addProperty("run","different-run");rewrite=false;}
                case "kind" -> {bad.addProperty("kind","live_ground_stream");rewrite=false;}
                case "count" -> {bad.getAsJsonArray("tiles").remove(1);rewrite=false;}
                case "unknown" -> {bad.addProperty("authority",true);rewrite=false;}
                case "mixed" -> second.getAsJsonObject("provenance").addProperty("kind","live_kcd_ground_patch");
                case "unsupported" -> second.getAsJsonObject("provenance").addProperty("kind","standalone_ground_fixture");
                case "offset" -> {second.getAsJsonObject("center").addProperty("x",105);for(var value:second.getAsJsonArray("points")){var p=value.getAsJsonObject();p.addProperty("x",p.get("x").getAsDouble()+1);}}
                case "height_anchor" -> second.getAsJsonObject("center").addProperty("z",10.1);
                case "overlap_height" -> {var p=second.getAsJsonArray("points").get(0).getAsJsonObject();p.addProperty("z",p.get("z").getAsDouble()+.01);}
                case "overlap_normal" -> second.getAsJsonArray("points").get(0).getAsJsonObject().addProperty("ny",.01);
                case "narrow" -> second.addProperty("grid_size",5);
                case "partial" -> second.getAsJsonArray("points").remove(0);
                case "tile_run" -> second.addProperty("run","another-capture");
            }
            if(rewrite)replace(bad,1,second);
            reject(()->GroundCorridor.parse(bytes(bad)),change);
        }
        String valid=manifest.toString();
        reject(()->GroundCorridor.parse(("{\"schema\":1,"+valid.substring(1)).getBytes(StandardCharsets.UTF_8)),"duplicate manifest keys");
        reject(()->GroundCorridor.parse((valid+"{}").getBytes(StandardCharsets.UTF_8)),"trailing JSON");
        reject(()->GroundCorridor.parse(new byte[]{(byte)0xc3,0x28}),"malformed UTF-8");
        reject(()->GroundCorridor.parse(new byte[GroundCorridor.MAX_BYTES+1]),"oversize manifest");
        Path file=Files.createTempFile("minecome-corridor-test-",".json");
        try{Files.write(file,input);check(GroundCorridor.read(file).sha256().equals(surface.sha256()),"Bounded file read preserves identity");}
        finally{Files.deleteIfExists(file);}
        return checks;
    }
}
