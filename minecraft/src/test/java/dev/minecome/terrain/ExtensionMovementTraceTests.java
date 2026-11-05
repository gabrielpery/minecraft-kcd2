package dev.minecome.terrain;

import com.google.gson.JsonParser;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/** Contract-only extension framing; no native or Minecraft acceptance is inferred. */
final class ExtensionMovementTraceTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Runnable action){try{action.run();throw new AssertionError("Invalid extension trace contract admitted");}catch(IllegalArgumentException expected){checks++;}}
    private static MovementTraceSink.Motion motion(double x,double y,double z) {
        return new MovementTraceSink.Motion(x,y,z,0,0,0,true,true,false,false,true);
    }
    private static MovementTraceSink.Context context(String world,String source) {
        return new MovementTraceSink.Context("e".repeat(128),"a".repeat(64),source,"MineCome-HudStream-"+world,world,
                120.17870330810547,2040.6510009765625,56.29341506958008,MovementTraceSink.Profile.HUD_EXTENSION_WALK_COUPLED);
    }
    static int run(Path root,Path run,String world)throws Exception {
        var context=context(world,"live_kcd_ground_extension");
        for(String source:List.of("standalone_ground_extension_fixture","live_kcd_ground_corridor","live_kcd_ground_patch","hud_extension_walk_coupled"))
            reject(()->context(world,source));
        reject(()->new MovementTraceSink.Context(context.run(),context.patchSha256(),context.sourceKind(),context.save(),world,
                context.centerX(),context.centerY(),context.centerZ(),context.profile(),0,64,0,true));
        reject(()->motion(-3.50001,64,0));reject(()->motion(11.50001,64,0));
        reject(()->motion(0,64,-3.50001));reject(()->motion(0,64,3.50001));
        reject(()->motion(0,57.89999,0));reject(()->motion(0,67.50001,0));
        reject(()->new MovementTraceSink.Motion(9.5,64,0,0,0,0,true,true,false,true));
        reject(()->new MovementTraceSink.Motion(9.5,64,0,0,0,0,true,true,true,false,true));
        reject(()->new MovementTraceSink.Motion(9.5,64,0,0,0,0,true,true,false,true,true));
        check(motion(-3.5,57.9,-3.5).extension()&&motion(11.5,67.5,3.5).extension(),"Only explicit extension admits its exact rectangle");
        Path file=run.resolve("extension-coupled.ndjson");
        try(var sink=MovementTraceSink.open(file,root,context,0,1000)) {
            var crossed=motion(9.5,65.1,.5);
            check(!sink.sample(0,1000,"SETTLING",crossed,crossed,1,-250_000_001L,true),"Extension retains 250ms server freshness");
            for(String phase:List.of("JUMPING","LANDING")) {
                try{sink.sample(0,1000,phase,crossed,crossed,1,0,true);throw new AssertionError("Extension accepted jump phase");}
                catch(IllegalArgumentException expected){checks++;}
            }
            for(int i=0;i<=200;i++) {
                long now=i*100_000_000L;
                String phase=i==0?"SETTLING":i<80?"WALKING":i<120?"RETURNING":i<200?"RETURN_REST":"PASSED";
                check(sink.sample(now,1000+i*100L,phase,crossed,crossed,i+1,now,false),"Fresh advancing observations fit the existing 20s scripted budget");
            }
            check(!sink.sample(20_100_000_000L,21100,"PASSED",crossed,crossed,201,20_100_000_000L,true),"Extension cannot replay server sequence");
            var old=new MovementTraceSink.Motion(5.5,65.1,.5,0,0,0,true,true,false,true);
            try{sink.sample(20_100_000_000L,21100,"PASSED",old,old,202,20_100_000_000L,true);throw new AssertionError("Corridor motion entered extension trace");}
            catch(IllegalArgumentException expected){checks++;}
            sink.finish(21000,"passed","PASSED","Contract-only extension walking and return");
            check(sink.records()==203&&sink.byteCount()>MovementTraceSink.MAX_BYTES&&sink.byteCount()<=MovementTraceSink.CORRIDOR_MAX_BYTES,
                    "Extension fits existing 256-record/256KiB scripted profile");
        }
        for(String line:Files.readAllLines(file)) {
            var record=JsonParser.parseString(line).getAsJsonObject();
            check(record.get("source_kind").getAsString().equals("hud_extension_walk_coupled")&&record.get("walking_area").getAsString().equals("extension")&&
                    record.get("patch_sha256").getAsString().equals(context.patchSha256()),"Every record retains explicit extension identity");
            if(record.get("kind").getAsString().equals("begin"))check(record.getAsJsonObject("anchor_mc").get("y").getAsDouble()==64&&
                    record.getAsJsonObject("center").get("x").getAsDouble()==context.centerX(),"Original coordinate anchor survives handoff framing");
        }
        var oldContext=new MovementTraceSink.Context(context.run(),context.patchSha256(),"live_kcd_ground_corridor",context.save(),world,
                context.centerX(),context.centerY(),context.centerZ(),MovementTraceSink.Profile.HUD_CORRIDOR_WALK_COUPLED);
        try(var sink=MovementTraceSink.open(run.resolve("extension-not-corridor.ndjson"),root,oldContext,0,1000)) {
            var m=motion(9.5,64,0);
            try{sink.sample(0,1000,"WALKING",m,m,1,0,true);throw new AssertionError("Extension motion entered old corridor profile");}
            catch(IllegalArgumentException expected){checks++;}
        }
        physical(root,run,world,context);
        return checks;
    }
    private static void physical(Path root,Path run,String world,MovementTraceSink.Context base)throws Exception {
        for(boolean fixture:new boolean[]{false,true}) {
            var profile=MovementTraceSink.Profile.physical(fixture,dev.minecome.hud.HudMovementSession.EXTENDED,false,true);
            String source=fixture?"standalone_ground_extension_fixture":"live_kcd_ground_extension";
            var context=new MovementTraceSink.Context(base.run(),base.patchSha256(),source,base.save(),world,
                    base.centerX(),base.centerY(),base.centerZ(),profile,0,64.375,0,false);
            reject(()->MovementTraceSink.Profile.physical(fixture,dev.minecome.hud.HudMovementSession.SHORT,false,true));
            reject(()->MovementTraceSink.Profile.physical(fixture,dev.minecome.hud.HudMovementSession.EXTENDED,true,true));
            reject(()->new MovementTraceSink.Context(base.run(),base.patchSha256(),fixture?"live_kcd_ground_extension":"standalone_ground_extension_fixture",
                    base.save(),world,base.centerX(),base.centerY(),base.centerZ(),profile,0,64.375,0,false));
            reject(()->new MovementTraceSink.Context(base.run(),base.patchSha256(),source,base.save(),world,
                    base.centerX(),base.centerY(),base.centerZ(),profile,0,64.375,0,true));
            Path file=run.resolve("physical-extension-"+fixture+".ndjson");
            try(var sink=MovementTraceSink.open(file,root,context,0,1000)) {
                for(int i=0;i<=160;i++) {
                    long now=i*100_000_000L;
                    // Contract-only fresh samples through a simulated600ms
                    // admission pause. No physical input or game is claimed.
                    double x=i<40?i*.1:i<46?4:i<100?Math.min(9.5,4+(i-46)*.11):9.5;
                    var m=motion(x,64.375,0);
                    String phase=i==0?"SETTLING":i==160?"PASSED":i>=40&&i<46?"RESTING":"WALKING";
                    check(!sink.sample(now,1000+i*100L,phase,m,m,i+1,now-250_000_001L,true),"Extension physical server lease still rejects stale observations");
                    check(sink.sample(now,1000+i*100L,phase,m,m,i+1,now,false),"Extension physical fresh observations continue across held-input admission pause");
                }
                var crossed=motion(9.5,64.375,0);
                check(!sink.sample(16_100_000_000L,17100,"RESTING",crossed,crossed,161,16_100_000_000L,true),"Physical extension cannot replay authoritative observations");
                try{sink.sample(16_100_000_000L,17100,"RETURNING",crossed,crossed,162,16_100_000_000L,true);throw new AssertionError("Physical extension claimed scripted return");}
                catch(IllegalArgumentException expected){checks++;}
                var tooLow=motion(9.5,57.9,0);
                try{sink.sample(16_100_000_000L,17100,"LANDING",tooLow,tooLow,162,16_100_000_000L,true);throw new AssertionError("Extension widened relative vertical authority");}
                catch(IllegalArgumentException expected){checks++;}
                var wrong=new MovementTraceSink.Motion(5,64.375,0,0,0,0,true,true,false,true);
                try{sink.sample(16_100_000_000L,17100,"RESTING",wrong,wrong,162,16_100_000_000L,true);throw new AssertionError("Old corridor motion relabelled extension");}
                catch(IllegalArgumentException expected){checks++;}
                sink.finish(17000,"passed","PASSED","Contract-only bounded physical extension");
                check(sink.records()==163&&sink.records()<MovementTraceSink.MAX_RECORDS&&sink.byteCount()<=MovementTraceSink.CORRIDOR_MAX_BYTES,
                        "Physical extension retains existing200record and256KiB budget for16second maximum");
            }
            for(String line:Files.readAllLines(file)) {
                var record=JsonParser.parseString(line).getAsJsonObject();
                check(record.get("source_kind").getAsString().equals(fixture?"standalone_hud_physical_movement_extension_fixture":"live_kcd_hud_physical_movement_extension")&&
                        record.get("walking_area").getAsString().equals("extension")&&record.get("patch_sha256").getAsString().equals(base.patchSha256()),
                        "Physical extension keeps stable plan and distinguishes live from fixture on every record");
                if(record.get("kind").getAsString().equals("begin"))check(record.getAsJsonObject("anchor_mc").get("y").getAsDouble()==64.375&&
                        record.getAsJsonObject("center").get("x").getAsDouble()==base.centerX(),"Physical extension never reanchors on admission");
            }
        }
    }
}
