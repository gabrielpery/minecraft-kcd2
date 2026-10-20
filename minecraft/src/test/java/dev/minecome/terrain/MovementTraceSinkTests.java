package dev.minecome.terrain;

import com.google.gson.*;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;

/** Bounded file fixtures only; no Minecraft classes or host setters. */
final class MovementTraceSinkTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static MovementTraceSink.Context context() {
        String world="ab32daa1-3972-4454-be0e-6d010ac2fd60";
        return new MovementTraceSink.Context("fixture-trace","a".repeat(64),"standalone_fixture","MineCome-Ground-"+world,world,100,200,10);
    }
    private static MovementTraceSink.Motion motion(double x){return new MovementTraceSink.Motion(x,64,0.5,0,0,0,true,true);}
    private static MovementTraceSink.Context hudContext(String save,String world,String source){
        return new MovementTraceSink.Context("actual-patch-run","b".repeat(64),source,save,world,100,200,10,MovementTraceSink.Profile.HUD_COUPLED);
    }
    private static void rejectedOpen(Path target,Path root) throws Exception {
        try(var ignored=MovementTraceSink.open(target,root,context(),0,1000)){throw new AssertionError("Unsafe path accepted");}
        catch(IOException expected){checks++;}
    }
    static int run() throws Exception {
        checks=0;Path temp=Files.createTempDirectory("minecome-trace-fixture-");
        try {
            Path root=Files.createDirectory(temp.resolve("evidence"));Path run=Files.createDirectory(root.resolve("run"));
            Path file=run.resolve("movement.ndjson");
            try(var sink=MovementTraceSink.open(file,root,context(),0,1000)) {
                check(Files.readAllLines(file).size()==1,"begin flushed immediately for read-only peer");
                rejectedOpen(file,root);
                check(sink.sample(100_000_000,1100,"WALKING",motion(0.4),motion(0.5),1,100_000_000,false),"fresh advancing server sample accepted");
                check(!sink.sample(150_000_000,1150,"WALKING",motion(0.3),motion(0.4),2,150_000_000,false),"limit normal samples to10Hz");
                check(!sink.sample(200_000_000,1200,"WALKING",motion(0.3),motion(0.4),1,200_000_000,false),"duplicate server sequence never emitted");
                check(!sink.sample(300_000_000,1300,"WALKING",motion(0.3),motion(0.4),2,1,false),"server older250ms never emitted");
                check(!sink.sample(300_000_000,1300,"WALKING",motion(0.3),motion(0.4),2,400_000_000,false),"future server timestamp never emitted");
                check(sink.sample(200_000_000,1200,"RESTING",motion(0.3),motion(0.4),2,200_000_000,false),"throttled sequences were not consumed");
                check(!sink.sample(210_000_000,1210,"PASSED",motion(0.3),motion(0.4),2,210_000_000,true),"forced final snapshot still needs advancing server sequence");
                check(!sink.sample(600_000_000,1600,"PASSED",motion(0.3),motion(0.4),3,300_000_000,true),"forced final snapshot cannot bypass server freshness");
                check(sink.sample(650_000_000,1650,"PASSED",motion(0.3),motion(0.4),3,650_000_000,true),"healthy next fresh server observation supplies final snapshot");
                sink.finish(1700,"passed","PASSED","quote\" newline\n snowman☃");
                check(sink.closed() && !sink.sample(500_000_000,1500,"PASSED",motion(0.3),motion(0.4),3,500_000_000,true),"no samples after termination");
            }
            List<String> lines=Files.readAllLines(file);check(lines.size()==5,"exact begin/sample/sample/final/end contract");
            for(int i=0;i<lines.size();i++) {
                JsonObject value=JsonParser.parseString(lines.get(i)).getAsJsonObject();
                check(value.get("schema").getAsInt()==1 && value.get("seq").getAsLong()==i+1,"record schema/sequence strictly increasing");
                check(value.get("world").getAsString().equals(context().world()) && value.get("run").getAsString().equals(context().run()),"immutable own world/run identity repeated");
                check(value.get("utc_ms").getAsLong()>=1000,"UTC timestamps available for another process");
            }
            JsonObject sample=JsonParser.parseString(lines.get(1)).getAsJsonObject();
            check(sample.getAsJsonObject("server").get("x").getAsDouble()==0.5 && sample.getAsJsonObject("client").get("x").getAsDouble()==0.4,"client prediction and authoritative server remain distinct");
            check(JsonParser.parseString(lines.get(3)).getAsJsonObject().get("phase").getAsString().equals("PASSED"),"trace ends with a fresh final motion observation before termination");
            check(JsonParser.parseString(lines.get(4)).getAsJsonObject().get("reason").getAsString().equals("quote\" newline\n snowman☃"),"JSON escaping preserves reason without injecting records");
            rejectedOpen(temp.resolve("outside.ndjson"),root);rejectedOpen(Path.of("relative.ndjson"),root);
            rejectedOpen(root.resolve("run").resolve("../../outside.ndjson"),root);
            check(!Files.exists(temp.resolve("outside.ndjson")),"unsafe path checks never create outside files");
            Path bounded=run.resolve("bounded.ndjson");
            try(var sink=MovementTraceSink.open(bounded,root,context(),0,1000)) {
                boolean exhausted=false;
                for(int i=1;i<=MovementTraceSink.MAX_RECORDS+1;i++) {
                    try{sink.sample(i*100_000_000L,1000+i*100L,"RESTING",motion(0.5),motion(0.5),i,i*100_000_000L,false);}
                    catch(IOException expected){exhausted=true;break;}
                }
                check(exhausted,"sample stream cannot exceed byte/record budget");
                sink.finish(50_000,"failed","FAILED","Reserved end remains writable after sample-budget exhaustion");
                check(sink.records()<=MovementTraceSink.MAX_RECORDS && sink.byteCount()<=MovementTraceSink.MAX_BYTES,"full contract stays within200records/64KiB");
            }
            var boundedLines=Files.readAllLines(bounded);
            check(JsonParser.parseString(boundedLines.get(boundedLines.size()-1)).getAsJsonObject().get("kind").getAsString().equals("end"),"final termination capacity reserved");
            try{motion(Double.NaN);throw new AssertionError("NaN motion accepted");}catch(IllegalArgumentException expected){checks++;}
            try{motion(2.001);throw new AssertionError("Beyond-patch motion accepted");}catch(IllegalArgumentException expected){checks++;}
            Path stopped=run.resolve("stopped.ndjson");
            try(var sink=MovementTraceSink.open(stopped,root,context(),0,1000)) {}
            var stoppedLines=Files.readAllLines(stopped);
            check(stoppedLines.size()==2 && JsonParser.parseString(stoppedLines.get(1)).getAsJsonObject().get("result").getAsString().equals("stopped"),"implicit close has explicit termination contract");
            String world=context().world(),hudSave="MineCome-HudStream-"+world;
            check(context().profile()==MovementTraceSink.Profile.GROUND,"Legacy context retains explicit Ground default");
            var hud=hudContext(hudSave,world,"live_kcd_ground_patch");
            check(hud.profile()==MovementTraceSink.Profile.HUD_COUPLED && hud.save().equals(hudSave),"HUD profile binds exact canonical save");
            try{new MovementTraceSink.Context("run","a".repeat(64),"live_kcd_ground_patch",hudSave,world,100,200,10);throw new AssertionError("Legacy constructor accepted HUD save");}
            catch(IllegalArgumentException expected){checks++;}
            try{hudContext(context().save(),world,"live_kcd_ground_patch");throw new AssertionError("HUD profile accepted Ground save");}
            catch(IllegalArgumentException expected){checks++;}
            try{hudContext(hudSave,world,"standalone_fixture");throw new AssertionError("HUD profile accepted synthetic provenance");}
            catch(IllegalArgumentException expected){checks++;}
            try{hudContext(hudSave,world.toUpperCase(),"live_kcd_ground_patch");throw new AssertionError("Noncanonical HUD world accepted");}
            catch(IllegalArgumentException expected){checks++;}
            try{hudContext(hudSave,"bb32daa1-3972-4454-be0e-6d010ac2fd60","live_kcd_ground_patch");throw new AssertionError("HUD save/world mismatch accepted");}
            catch(IllegalArgumentException expected){checks++;}
            Path hudFile=run.resolve("hud-movement.ndjson");
            try(var sink=MovementTraceSink.open(hudFile,root,hud,0,1000)){
                check(sink.sample(0,1000,"SETTLING",motion(.5),motion(.5),1,0,true),"HUD forced initial observation flushed during settling");
                check(sink.sample(2_000_000_000L,3000,"WALKING",motion(.4),motion(.5),2,2_000_000_000L,false),"HUD begins follower-eligible grounded phase only after settling");
                check(!sink.sample(2_050_000_000L,3050,"PASSED",motion(.3),motion(.3),2,2_000_000_000L,true),"HUD final phase cannot replay the last server observation");
                check(!sink.sample(2_500_000_000L,3500,"PASSED",motion(.3),motion(.3),3,2_200_000_000L,true),"HUD forced completion keeps original250ms age bound");
                check(sink.sample(2_550_000_000L,3550,"PASSED",motion(.3),motion(.3),3,2_550_000_000L,true),"HUD final phase uses advancing fresh server sequence");
                sink.finish(3550,"passed","PASSED","Movement ends before UI sequence");
                byte[] closedBytes=Files.readAllBytes(hudFile);
                check(!sink.sample(22_550_000_000L,23550,"PASSED",motion(.3),motion(.3),4,22_550_000_000L,true),"Later20s UI cannot append to closed movement trace");
                check(Arrays.equals(closedBytes,Files.readAllBytes(hudFile)),"UI-time append refusal preserves exact closed trace bytes");
            }
            var hudLines=Files.readAllLines(hudFile);
            check(hudLines.size()==5,"HUD profile retains existing begin/sample/sample/final/end format");
            for(String line:hudLines){
                var value=JsonParser.parseString(line).getAsJsonObject();
                check(value.get("run").getAsString().equals("actual-patch-run") && value.get("patch_sha256").getAsString().equals("b".repeat(64)) &&
                        value.get("save").getAsString().equals(hudSave) && value.get("world").getAsString().equals(world),"HUD trace preserves immutable captured patch and owned world identities");
            }
            var physical=new MovementTraceSink.Context("physical-patch","c".repeat(64),"live_kcd_ground_patch",hudSave,world,100,200,10,
                    MovementTraceSink.Profile.HUD_PHYSICAL,0,64.375,0);
            Path physicalFile=run.resolve("physical.ndjson");
            try(var sink=MovementTraceSink.open(physicalFile,root,physical,0,1000)){
                var origin=new MovementTraceSink.Motion(0,64.375,0,0,0,0,true,true);
                check(sink.sample(0,1000,"SETTLING",origin,origin,1,0,true),"Physical exact grounded anchor recorded before movement");
                check(!sink.sample(1,1000,"PASSED",origin,origin,1,0,true),"Physical completion cannot reuse initial observation");
                check(sink.sample(200_000_000,1200,"PASSED",origin,origin,2,200_000_000,true),"Physical final proof uses fresh advancing sample");
                sink.finish(1200,"passed","PASSED","Physical walk complete");
            }
            var physicalLines=Files.readAllLines(physicalFile);
            check(JsonParser.parseString(physicalLines.getFirst()).getAsJsonObject().getAsJsonObject("anchor_mc").get("y").getAsDouble()==64.375,
                    "Physical trace preserves actual settled terrain Y instead of fixed64");
            for(String line:physicalLines)check(JsonParser.parseString(line).getAsJsonObject().get("source_kind").getAsString().equals("live_kcd_hud_physical_movement"),
                    "Physical trace cannot masquerade as earlier scripted profile");
            try{new MovementTraceSink.Context("run","a".repeat(64),"live_kcd_ground_patch",hudSave,world,100,200,10,MovementTraceSink.Profile.HUD_COUPLED,0,64.375,0);throw new AssertionError("Coupled anchor changed");}
            catch(IllegalArgumentException expected){checks++;}
            try{new MovementTraceSink.Context("run","a".repeat(64),"live_kcd_ground_patch",hudSave,world,100,200,10,MovementTraceSink.Profile.HUD_PHYSICAL,.5,64,0);throw new AssertionError("Physical horizontal hop accepted");}
            catch(IllegalArgumentException expected){checks++;}
        } finally {
            // Only this fresh fixture directory is cleaned, using its resolved path.
            Path ownedRoot=temp.toRealPath();
            try(var paths=Files.walk(ownedRoot)) {
                for(Path path:paths.sorted(Comparator.reverseOrder()).toList()) {
                    if(!path.toAbsolutePath().normalize().startsWith(ownedRoot))throw new IOException("Fixture cleanup escaped its owned directory");
                    Files.delete(path);
                }
            }
        }
        return checks;
    }
}
