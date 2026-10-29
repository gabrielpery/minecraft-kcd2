package dev.minecome.terrain;

import com.google.gson.JsonParser;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/** File contract checks only; these do not claim an observed game or KCD follower. */
final class CorridorMovementTraceTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Runnable action){try{action.run();throw new AssertionError("Invalid corridor trace contract admitted");}catch(IllegalArgumentException expected){checks++;}}
    private static MovementTraceSink.Motion motion(double x,double y,double z){
        return new MovementTraceSink.Motion(x,y,z,0,0,0,true,true,false,true);
    }
    private static MovementTraceSink.Context context(String world,String source){
        return new MovementTraceSink.Context("c".repeat(128),"d".repeat(64),source,"MineCome-HudStream-"+world,world,
                120.17870330810547,2040.6510009765625,56.29341506958008,MovementTraceSink.Profile.HUD_CORRIDOR_COUPLED);
    }
    static int run(Path root,Path run,String world) throws Exception {
        var context=context(world,"live_kcd_ground_corridor");
        for(String source:List.of("standalone_corridor_fixture","live_kcd_ground_patch","hud_corridor_coupled"))
            reject(()->context(world,source));
        reject(()->new MovementTraceSink.Context(context.run(),context.patchSha256(),context.sourceKind(),context.save(),world,
                context.centerX(),context.centerY(),context.centerZ(),context.profile(),0,64,0,true));
        reject(()->motion(-3.50001,64,0));reject(()->motion(7.50001,64,0));
        reject(()->motion(0,64,-3.50001));reject(()->motion(0,64,3.50001));
        reject(()->motion(0,57.89999,0));reject(()->motion(0,67.50001,0));
        check(motion(-3.5,57.9,-3.5).corridor()&&motion(7.5,67.5,3.5).corridor(),"Exact corridor inset and ray/jump bounds remain admitted");
        Path file=run.resolve("corridor-coupled.ndjson");
        try(var sink=MovementTraceSink.open(file,root,context,0,1000)){
            var crossed=motion(5.9,65.1,.5);
            check(!sink.sample(0,1000,"SETTLING",crossed,crossed,1,-250_000_001L,true),"Corridor keeps original250ms server freshness");
            for(int i=0;i<=200;i++){
                long now=i*100_000_000L;
                String phase=i==0?"SETTLING":i<80?"WALKING":i<120?"RETURNING":i<200?"RETURN_REST":"PASSED";
                check(sink.sample(now,1000+i*100L,phase,crossed,crossed,i+1,now,false),"Full20s contract admits fresh advancing observations");
            }
            check(!sink.sample(20_100_000_000L,21100,"PASSED",crossed,crossed,201,20_100_000_000L,true),"Completion cannot replay server sequence");
            try{sink.sample(20_100_000_000L,21100,"PASSED",new MovementTraceSink.Motion(.5,64,.5,0,0,0,true,true),crossed,202,20_100_000_000L,true);throw new AssertionError("Legacy motion entered corridor trace");}
            catch(IllegalArgumentException expected){checks++;}
            sink.finish(21000,"passed","PASSED","Contract-only20s sequence with return phases");
            check(sink.records()==203&&sink.byteCount()>MovementTraceSink.MAX_BYTES&&sink.byteCount()<=MovementTraceSink.CORRIDOR_MAX_BYTES,
                    "Corridor budget covers20s without expanding legacy record or byte limits");
        }
        var lines=Files.readAllLines(file);
        for(String line:lines){
            var record=JsonParser.parseString(line).getAsJsonObject();
            check(record.get("source_kind").getAsString().equals("hud_corridor_coupled")&&record.get("walking_area").getAsString().equals("corridor")&&
                    record.get("patch_sha256").getAsString().equals(context.patchSha256()),"Every corridor record binds exact profile, area and manifest");
        }
        var begin=JsonParser.parseString(lines.getFirst()).getAsJsonObject();
        check(begin.getAsJsonObject("anchor_mc").get("y").getAsDouble()==64&&
                begin.getAsJsonObject("center").get("x").getAsDouble()==context.centerX(),"Trace preserves immutable first-tile and Minecraft anchors");
        var walkContext=new MovementTraceSink.Context(context.run(),context.patchSha256(),context.sourceKind(),context.save(),world,
                context.centerX(),context.centerY(),context.centerZ(),MovementTraceSink.Profile.HUD_CORRIDOR_WALK_COUPLED);
        var walkFile=run.resolve("corridor-walk-coupled.ndjson");
        try(var sink=MovementTraceSink.open(walkFile,root,walkContext,0,1000)){
            var m=motion(5.9,65.1,.5);
            for(String phase:List.of("JUMPING","LANDING")){
                try{sink.sample(0,1000,phase,m,m,1,0,true);throw new AssertionError("Walk-only trace accepted jump phase");}
                catch(IllegalArgumentException expected){checks++;}
            }
            int i=0;
            for(String phase:List.of("WALKING","RETURNING","RETURN_REST","PASSED")){
                long now=i*100_000_000L;
                check(sink.sample(now,1000+i*100L,phase,m,m,++i,now,false),"Walk-only publishes each supported phase using real observation contract");
            }
            sink.finish(1400,"passed","PASSED","Contract-only walking sequence");
        }
        for(String line:Files.readAllLines(walkFile)){
            var record=JsonParser.parseString(line).getAsJsonObject();
            check(record.get("source_kind").getAsString().equals("hud_corridor_walk_coupled")&&record.get("walking_area").getAsString().equals("corridor"),
                    "Walk-only source identity cannot be mistaken for full-jump diagnostic");
        }
        var legacy=new MovementTraceSink.Context("legacy","e".repeat(64),"live_kcd_ground_patch",context.save(),world,0,0,0,MovementTraceSink.Profile.HUD_COUPLED);
        for(boolean fixture:new boolean[]{false,true}){
            var profile=MovementTraceSink.Profile.physical(fixture,dev.minecome.hud.HudMovementSession.EXTENDED,true);
            String provenance=fixture?"standalone_corridor_fixture":"live_kcd_ground_corridor";
            var physical=new MovementTraceSink.Context(context.run(),context.patchSha256(),provenance,context.save(),world,
                    context.centerX(),context.centerY(),context.centerZ(),profile,0,64.375,0,false);
            reject(()->MovementTraceSink.Profile.physical(fixture,dev.minecome.hud.HudMovementSession.SHORT,true));
            reject(()->new MovementTraceSink.Context(context.run(),context.patchSha256(),fixture?"live_kcd_ground_corridor":"standalone_corridor_fixture",context.save(),world,
                    context.centerX(),context.centerY(),context.centerZ(),profile,0,64.375,0,false));
            Path physicalFile=run.resolve("physical-corridor-"+fixture+".ndjson");
            try(var sink=MovementTraceSink.open(physicalFile,root,physical,0,1000)){
                var initial=motion(0,64.375,0);var outward=motion(5.8,64.375,0);
                check(sink.sample(0,1000,"SETTLING",initial,initial,1,0,true),"Physical corridor records actual settled anchor without fixed64 reset");
                check(sink.sample(100_000_000L,1100,"WALKING",outward,outward,2,100_000_000L,false),"Physical corridor trace admits observed crossing");
                var deep=motion(0,57.9,0);
                try{sink.sample(200_000_000L,1200,"WALKING",deep,deep,3,200_000_000L,true);throw new AssertionError("Relative vertical bound widened by raw corridor range");}
                catch(IllegalArgumentException expected){checks++;}
                try{sink.sample(200_000_000L,1200,"RETURNING",initial,initial,3,200_000_000L,true);throw new AssertionError("Physical source claimed scripted return phase");}
                catch(IllegalArgumentException expected){checks++;}
                check(sink.sample(16_000_000_000L,17000,"PASSED",initial,initial,3,16_000_000_000L,true),"Physical corridor supports existing16s maximum final fresh sample");
                sink.finish(17000,"passed","PASSED","Contract-only physical corridor fixture");
            }
            for(String line:Files.readAllLines(physicalFile)){
                var record=JsonParser.parseString(line).getAsJsonObject();
                check(record.get("walking_area").getAsString().equals("corridor")&&record.get("source_kind").getAsString().equals(fixture?
                        "standalone_hud_physical_movement_corridor_fixture":"live_kcd_hud_physical_movement_corridor"),"Physical corridor source cannot be confused with scripted native follower or live input");
                if(record.get("kind").getAsString().equals("begin"))check(record.getAsJsonObject("anchor_mc").get("y").getAsDouble()==64.375,"Physical corridor anchor retains actual settled height");
            }
        }
        try(var sink=MovementTraceSink.open(run.resolve("legacy-return-rejected.ndjson"),root,legacy,0,1000)){
            var m=new MovementTraceSink.Motion(.5,64,.5,0,0,0,true,true);
            try{sink.sample(0,1000,"RETURNING",m,m,1,0,true);throw new AssertionError("Legacy trace accepted corridor-only return phase");}
            catch(IllegalArgumentException expected){checks++;}
        }
        return checks;
    }
}
