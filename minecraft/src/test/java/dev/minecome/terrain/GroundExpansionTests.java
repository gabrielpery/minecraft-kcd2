package dev.minecome.terrain;

import com.google.gson.*;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.shape.VoxelShapes;
import net.minecraft.world.BlockView;
import java.io.IOException;
import java.lang.reflect.Proxy;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;

/** The admission path uses real collision shape maps without starting a game. */
public final class GroundExpansionTests {
    private static int checks;
    private interface Work {void run()throws Exception;}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Work work,String message)throws Exception {
        try{work.run();throw new AssertionError("Accepted "+message);}catch(IOException|IllegalArgumentException expected){checks++;}
    }
    private static byte[] bytes(JsonObject value){return value.toString().getBytes(StandardCharsets.UTF_8);}
    private static String hash(byte[] bytes)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}
    static JsonObject fixture(String source,double slope)throws Exception {
        var manifest=GroundCorridorTests.fixture(source,slope);
        manifest.addProperty("kind","minecome_ground_extension_v1");
        var third=tile(manifest,1);
        third.getAsJsonObject("center").addProperty("x",108);
        for(var value:third.getAsJsonArray("points")) {
            var point=value.getAsJsonObject();point.addProperty("x",point.get("x").getAsDouble()+4);
            point.addProperty("z",point.get("z").getAsDouble()+4*slope);
        }
        var entry=new JsonObject();entry.addProperty("sha256",hash(bytes(third)));entry.addProperty("json",third.toString());
        manifest.getAsJsonArray("tiles").add(entry);return manifest;
    }
    private static JsonObject tile(JsonObject manifest,int index) {
        return JsonParser.parseString(manifest.getAsJsonArray("tiles").get(index).getAsJsonObject().get("json").getAsString()).getAsJsonObject();
    }
    private static void replace(JsonObject manifest,int index,JsonObject tile)throws Exception {
        var entry=manifest.getAsJsonArray("tiles").get(index).getAsJsonObject();entry.addProperty("json",tile.toString());entry.addProperty("sha256",hash(bytes(tile)));
    }
    private static BlockView world() {
        return (BlockView)Proxy.newProxyInstance(BlockView.class.getClassLoader(),new Class<?>[]{BlockView.class},
                (proxy,method,args)->{throw new AssertionError("Unexpected game-world API call: "+method.getName());});
    }
    public static void main(String[] args)throws Exception {
        var manifest=fixture("standalone_fixture",.1);byte[] input=bytes(manifest);
        var plan=GroundExpansion.parse(input);var initial=plan.initial();var expanded=plan.expanded();
        check(plan.sha256().equals(hash(input))&&expanded.sha256().equals(plan.sha256()),"Plan and final surface preserve raw input identity");
        check(plan.tileHashes().size()==3&&plan.tileHashes().subList(0,2).equals(initial.tileHashes()),"Original tile digests remain the exact prefix");
        check(initial.centerX()==expanded.centerX()&&initial.centerY()==expanded.centerY()&&initial.centerZ()==expanded.centerZ(),"Original world anchor never moves");
        check(initial.slabs().size()==96&&expanded.slabs().size()==128&&expanded.points().size()==153,"Only one extra four-metre strip is admitted");
        check(expanded.slabs().subList(0,initial.slabs().size()).equals(initial.slabs()),"Existing slabs retain exact values/order");
        check(expanded.cells().subList(0,initial.cells().size()).equals(initial.cells()),"Existing protected cells retain exact values/order");
        check(expanded.sourceKind().equals("standalone_ground_extension_fixture")&&expanded.corridor()&&expanded.wide(),"Explicit expanded provenance");
        check(!initial.containsFeet(9.5,0,.3)&&expanded.containsFeet(9.5,0,.3),"Destination was unavailable in the old generation");
        check(Math.abs(expanded.heightAt(9.5,.5)-64.95)<1e-9,"New terrain uses original height anchor");
        check(expanded.groundForFeet(8,0,.3)==expanded.heightAt(8.1,0),"Feet spanning old/new seam use highest neighboring support");
        check(expanded.groundForFeet(8,0,0)==expanded.heightAt(8,0),"Zero-width support query at seam is defined");
        check(expanded.containsFeet(11.7,3.7,.3)&&!expanded.containsFeet(11.71,3.7,.3),"Full-footprint right limit enforced");
        check(!expanded.containsFeet(Double.NaN,0,.3)&&!expanded.containsFeet(0,0,-1)&&!expanded.containsFeet(0,0,Double.POSITIVE_INFINITY),"Invalid footprint rejected");
        reject(()->expanded.groundForFeet(11.9,0,.3),"partial-foot support beyond extension");
        reject(()->expanded.heightAt(12,0),"height beyond extension");
        var keys=new HashSet<String>();for(var cell:expanded.cells())check(keys.add(cell.x()+","+cell.y()+","+cell.z()),"One immutable shape per imported cell");
        check(GroundExpansion.parse(bytes(fixture("live_kcd_ground_patch",0))).expanded().sourceKind().equals("live_kcd_ground_extension"),"Live capture provenance remains distinct");
        for(String change:List.of("hash","run","kind","count","unknown","mixed","provenance","unsupported","offset","height_anchor","overlap_height","overlap_normal","narrow","partial","tile_run")) {
            var bad=manifest.deepCopy();var third=tile(bad,2);boolean rewrite=true;
            switch(change) {
                case "hash" -> {bad.getAsJsonArray("tiles").get(2).getAsJsonObject().addProperty("sha256","0".repeat(64));rewrite=false;}
                case "run" -> {bad.addProperty("run","different-run");rewrite=false;}
                case "kind" -> {bad.addProperty("kind","minecome_ground_corridor_v1");rewrite=false;}
                case "count" -> {bad.getAsJsonArray("tiles").remove(2);rewrite=false;}
                case "unknown" -> {bad.addProperty("authority",true);rewrite=false;}
                case "mixed" -> third.getAsJsonObject("provenance").addProperty("kind","live_kcd_ground_patch");
                case "provenance" -> third.getAsJsonObject("provenance").addProperty("game_pid",321);
                case "unsupported" -> third.getAsJsonObject("provenance").addProperty("kind","not_a_capture");
                case "offset" -> {third.getAsJsonObject("center").addProperty("x",109);for(var v:third.getAsJsonArray("points")){var p=v.getAsJsonObject();p.addProperty("x",p.get("x").getAsDouble()+1);}}
                case "height_anchor" -> third.getAsJsonObject("center").addProperty("z",10.1);
                case "overlap_height" -> {var p=third.getAsJsonArray("points").get(0).getAsJsonObject();p.addProperty("z",p.get("z").getAsDouble()+.01);}
                case "overlap_normal" -> third.getAsJsonArray("points").get(0).getAsJsonObject().addProperty("ny",.01);
                case "narrow" -> third.addProperty("grid_size",5);
                case "partial" -> third.getAsJsonArray("points").remove(0);
                case "tile_run" -> third.addProperty("run","another-capture");
            }
            if(rewrite)replace(bad,2,third);
            reject(()->GroundExpansion.parse(bytes(bad)),change);
        }
        String valid=manifest.toString();
        reject(()->GroundExpansion.parse(("{\"schema\":1,"+valid.substring(1)).getBytes(StandardCharsets.UTF_8)),"duplicate manifest key");
        reject(()->GroundExpansion.parse((valid+"{}").getBytes(StandardCharsets.UTF_8)),"trailing JSON");
        reject(()->GroundExpansion.parse(new byte[]{(byte)0xc3,0x28}),"malformed UTF-8");
        reject(()->GroundExpansion.parse(new byte[GroundExpansion.MAX_BYTES+1]),"oversize input");
        Path file=Files.createTempFile("minecome-extension-test-",".json");
        try{Files.write(file,input);check(GroundExpansion.read(file).sha256().equals(plan.sha256()),"Bounded read retains plan identity");}
        finally{Files.deleteIfExists(file);}
        GroundCollision.clear();
        try {
            var flat=GroundExpansion.parse(bytes(fixture("standalone_fixture",0)));var before=flat.initial();var after=flat.expanded();
            var client=world();var server=world();var stranger=world();var empty=VoxelShapes.empty();
            var oldPosition=new BlockPos(6,63,0);var newPosition=new BlockPos(9,63,0);
            GroundCollision.install(client,before,false);GroundCollision.install(server,before,true);
            var oldShape=GroundCollision.merge(client,oldPosition,empty);long queries=GroundCollision.queries(false);
            check(GroundCollision.merge(client,newPosition,empty)==empty,"Unadmitted extension contributes no collision");
            check(!GroundCollision.replace(stranger,before,after,false)&&!GroundCollision.replace(client,before,after,true),"Wrong world/side cannot publish");
            check(GroundCollision.matches(client,before,false)&&GroundCollision.matches(server,before,true),"Rejected publication preserves both owners");
            reject(()->GroundCollision.replace(client,after,before,false),"backward terrain eviction");
            reject(()->GroundCollision.replace(client,before,before,false),"non-additive generation");
            check(GroundCollision.replace(server,before,after,true),"Server owning-thread publication succeeds");
            check(GroundCollision.matches(client,before,false)&&GroundCollision.matches(server,after,true),"Server publication leaves client unchanged until its turn");
            check(GroundCollision.replace(client,before,after,false),"Client owning-thread publication succeeds");
            check(GroundCollision.queries(false)==queries,"Publication preserves query history");
            check(!GroundCollision.merge(client,newPosition,empty).isEmpty()&&!GroundCollision.merge(server,newPosition,empty).isEmpty(),"Both worlds expose admitted new terrain");
            var retained=GroundCollision.merge(client,oldPosition,empty);
            check(oldShape.getBoundingBox().equals(retained.getBoundingBox()),"Existing collision remains exact after admission");
            check(!GroundCollision.replace(client,before,after,false),"Stale predecessor cannot republish");
            check(!GroundCollision.clear(client,before.run(),before.sha256(),false),"Old generation cannot clear successor");
            check(GroundCollision.matches(client,after,false)&&GroundCollision.matches(server,after,true),"Stale operations preserve final owners");
            check(GroundCollision.clear(client,after.run(),after.sha256(),false)&&GroundCollision.clear(server,after.run(),after.sha256(),true),"Exact successor owners clean up");
        } finally {GroundCollision.clear();}
        System.out.println("GROUND_EXPANSION_TESTS_PASS checks="+checks);
    }
}
