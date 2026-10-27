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
    private static List<JsonObject> samples(Path file) throws IOException {
        return Files.readAllLines(file).stream().map(line->JsonParser.parseString(line).getAsJsonObject())
                .filter(value->value.get("kind").getAsString().equals("sample")).toList();
    }
    private static void phaseLockedSampling(Path root,Path run,MovementTraceSink.Context physical,
                                            MovementTraceSink.Context fixture,MovementTraceSink.Context hud) throws Exception {
        for(var profile:List.of(physical,fixture)){
            Path path=run.resolve("phase-locked-"+profile.profile()+".ndjson");
            try(var sink=MovementTraceSink.open(path,root,profile,-1_000_000_000L,1000)){
                check(!sink.sample(-700_000_000L,1000,"SETTLING",motion(0),motion(0),1,-1_000_000_000L,true),"Stale first sample cannot establish the physical cadence");
                try{sink.sample(-650_000_000L,-1,"SETTLING",motion(0),motion(0),1,-650_000_000L,true);throw new AssertionError("Invalid UTC accepted");}
                catch(IllegalArgumentException expected){checks++;}
                long anchor=-600_000_000L;
                check(sink.sample(anchor,1000,"SETTLING",motion(0),motion(0),1,anchor,true),"First successful physical sample anchors the cadence at its actual negative clock");
                check(!sink.sample(anchor+50_000_000L,1050,"RESTING",motion(0),motion(0),2,anchor+50_000_000L,false),"Rejected initial attempts did not anchor an earlier slot");
                check(sink.sample(anchor+149_000_000L,1149,"WALKING",motion(.1),motion(.1),2,anchor+119_000_000L,false),"Late invocation emits its one fresh observation");
                check(!sink.sample(anchor+199_000_000L,1199,"WALKING",motion(.2),motion(.2),3,anchor+199_000_000L,false),"Same elapsed slot cannot emit a catch-up sample");
                check(sink.sample(anchor+200_000_000L,1200,"WALKING",motion(.2),motion(.2),3,anchor+180_000_000L,false),"Next original boundary stays due only51ms after the late sample");
                long before=sink.records();
                check(sink.sample(anchor+549_000_000L,1549,"RESTING",motion(.3),motion(.3),4,anchor+549_000_000L,false),"A long pause skips missed slots");
                check(sink.records()==before+1,"One invocation never backfills a burst of missed samples");
                check(!sink.sample(anchor+550_000_000L,1550,"RESTING",motion(.3),motion(.3),5,anchor+550_000_000L,false),"Skipped slots cannot be recovered by the following callback");
                check(!sink.sample(anchor+548_000_000L,1548,"PASSED",motion(.3),motion(.3),5,anchor+548_000_000L,true),"Forced sample cannot regress the actual observation clock");
                check(!sink.sample(anchor+900_000_000L,1900,"RESTING",motion(.3),motion(.3),5,anchor+649_000_000L,false),"A due physical slot preserves the250ms freshness bound");
                check(sink.sample(anchor+900_000_000L,1900,"RESTING",motion(.3),motion(.3),5,anchor+650_000_000L,false),"Rejected stale slot is not consumed; exact250ms age remains valid");
                check(!sink.sample(anchor+910_000_000L,1910,"PASSED",motion(.3),motion(.3),5,anchor+910_000_000L,true),"Forced final still requires a new server sequence");
                check(sink.sample(anchor+950_000_000L,1950,"PASSED",motion(.3),motion(.3),6,anchor+940_000_000L,true),"Fresh forced final can finish between ordinary boundaries");
                check(!sink.sample(anchor+950_000_000L,1950,"PASSED",motion(.3),motion(.3),7,anchor+950_000_000L,true),"Forced samples cannot duplicate actual monotonic time");
                check(!sink.sample(anchor+950_000_000L,1950,"RESTING",motion(.3),motion(.3),7,anchor+950_000_000L,false),"Forced final cannot be followed by a same-time ordinary duplicate");
                sink.finish(1950,"passed","PASSED","Synthetic phase-locked schedule check");
            }
            var records=samples(path);
            check(records.size()==6,"Delayed, skipped and forced physical samples remain bounded");
            check(records.get(1).get("monotonic_ns").getAsLong()==-451_000_000L && records.get(1).get("server_age_ns").getAsLong()==30_000_000L,
                    "Phase locking never rewrites actual emission or server observation times");
            float previous=-1;
            long firstSource=records.getFirst().get("monotonic_ns").getAsLong()-records.getFirst().get("server_age_ns").getAsLong();
            for(var record:records){
                float sourceMs=(float)((record.get("monotonic_ns").getAsLong()-record.get("server_age_ns").getAsLong()-firstSource)/1_000_000.0);
                check(sourceMs>previous,"Float32 buffered source times remain strictly increasing across shorter physical intervals");previous=sourceMs;
            }
            Path forced=run.resolve("forced-slot-"+profile.profile()+".ndjson");
            try(var sink=MovementTraceSink.open(forced,root,profile,0,1000)){
                check(sink.sample(0,1000,"SETTLING",motion(0),motion(0),1,0,true),"Forced-slot anchor accepted");
                check(sink.sample(150_000_000L,1150,"RESTING",motion(0),motion(0),2,150_000_000L,true),"Force consumes its current elapsed slot");
                check(!sink.sample(160_000_000L,1160,"RESTING",motion(0),motion(0),3,160_000_000L,false),"Force does not leave an ordinary sample due in the same slot");
                check(sink.sample(200_000_000L,1200,"RESTING",motion(0),motion(0),3,200_000_000L,false),"Force does not move the original cadence to250ms");
            }
            Path overflow=run.resolve("clock-overflow-"+profile.profile()+".ndjson");
            try(var sink=MovementTraceSink.open(overflow,root,profile,Long.MIN_VALUE+100,1000)){
                check(!sink.sample(Long.MIN_VALUE+100,1000,"SETTLING",motion(0),motion(0),1,Long.MAX_VALUE-100,true),"Wrapped positive server age cannot make a future observation fresh");
                check(sink.sample(Long.MIN_VALUE+100,1000,"SETTLING",motion(0),motion(0),1,Long.MIN_VALUE+100,true),"Valid extreme negative clock can establish an anchor");
                check(!sink.sample(Long.MAX_VALUE-100,1100,"PASSED",motion(0),motion(0),2,Long.MAX_VALUE-100,true),"Overflowing anchor interval fails closed even for a forced sample");
                check(sink.sample(Long.MIN_VALUE+100_000_100L,1100,"RESTING",motion(0),motion(0),2,Long.MIN_VALUE+100_000_100L,false),"Overflow rejection leaves the valid anchor and server sequence intact");
            }
            Path upper=run.resolve("clock-upper-"+profile.profile()+".ndjson");
            try(var sink=MovementTraceSink.open(upper,root,profile,Long.MAX_VALUE-150_000_000L,1000)){
                check(sink.sample(Long.MAX_VALUE-150_000_000L,1000,"SETTLING",motion(0),motion(0),1,Long.MAX_VALUE-150_000_000L,true),"Near-maximum clock anchors without adding a deadline");
                check(sink.sample(Long.MAX_VALUE-50_000_000L,1100,"RESTING",motion(0),motion(0),2,Long.MAX_VALUE-50_000_000L,false),"Anchor-relative boundary near Long.MAX_VALUE remains valid");
                check(sink.sample(Long.MAX_VALUE,1150,"PASSED",motion(0),motion(0),3,Long.MAX_VALUE,true),"Final sample near clock maximum does not overflow a next-slot calculation");
            }
        }
        for(var legacy:List.of(context(),hud)){
            Path path=run.resolve("legacy-cadence-"+legacy.profile()+".ndjson");
            try(var sink=MovementTraceSink.open(path,root,legacy,0,1000)){
                check(sink.sample(0,1000,"SETTLING",motion(0),motion(0),1,0,true),"Legacy initial sample unchanged");
                check(sink.sample(149_000_000L,1149,"RESTING",motion(0),motion(0),2,149_000_000L,false),"Legacy late sample accepted");
                check(!sink.sample(200_000_000L,1200,"RESTING",motion(0),motion(0),3,200_000_000L,false),"Legacy profile still requires100ms since actual prior sample");
                check(sink.sample(249_000_000L,1249,"RESTING",motion(0),motion(0),3,249_000_000L,false),"Legacy next deadline remains relative to actual emission");
                check(sink.sample(249_000_000L,1249,"PASSED",motion(0),motion(0),4,249_000_000L,true),"Legacy forced-snapshot semantics remain unchanged");
            }
        }
    }
    private static List<Long> jitteredSamples(Path root,Path path,MovementTraceSink.Context profile) throws Exception {
        List<Long> emitted=new ArrayList<>();long at=0,serverSeq=1;
        long[] intervals={47_000_000L,56_000_000L,49_000_000L,53_000_000L,48_000_000L,55_000_000L};
        try(var sink=MovementTraceSink.open(path,root,profile,0,1000)){
            check(sink.sample(0,1000,"SETTLING",motion(0),motion(0),serverSeq++,0,true),"Synthetic jitter comparison anchors at zero");emitted.add(0L);
            for(int tick=0;;tick++){
                at+=intervals[tick%intervals.length];if(at>6_000_000_000L)break;
                long before=sink.records();
                if(sink.sample(at,1000+at/1_000_000,"RESTING",motion(.1),motion(.1),serverSeq++,at-5_000_000L,false))emitted.add(at);
                check(sink.records()-before<=1,"Jittered tick emits at most one actual sample");
            }
            sink.finish(7000,"stopped","STOPPED","SYNTHETIC jitter comparison; not gameplay latency evidence");
        }
        return emitted;
    }
    private static void samplingComparisonAndBudget(Path root,Path run,MovementTraceSink.Context physical,
                                                     MovementTraceSink.Context fixture) throws Exception {
        var legacy=jitteredSamples(root,run.resolve("synthetic-jitter-legacy.ndjson"),context());
        var locked=jitteredSamples(root,run.resolve("synthetic-jitter-locked.ndjson"),physical);
        var lockedFixture=jitteredSamples(root,run.resolve("synthetic-jitter-fixture.ndjson"),fixture);
        check(locked.equals(lockedFixture),"Physical and standalone fixture use exactly the same phase-locked cadence");
        long legacyDrift=legacy.getLast()-(legacy.size()-1)*MovementTraceSink.PERIOD_NS;
        long lockedDrift=locked.getLast()-(locked.size()-1)*MovementTraceSink.PERIOD_NS;
        check(locked.size()==60 && locked.size()>legacy.size(),"Jittered physical schedule retains all60elapsed slots without synthetic backfill");
        check(lockedDrift<=56_000_000L && legacyDrift>lockedDrift+50_000_000L,"Phase locking bounds lateness to one callback rather than accumulating it");
        for(int i=1;i<locked.size();i++)check(locked.get(i)/MovementTraceSink.PERIOD_NS==i,"Each synthetic sample occupies its original elapsed slot");
        System.out.printf(Locale.ROOT,"SYNTHETIC_TRACE_CADENCE duration_ms=6000 legacy_samples=%d locked_samples=%d legacy_drift_ms=%.3f locked_drift_ms=%.3f game_calls=false%n",
                legacy.size(),locked.size(),legacyDrift/1_000_000.0,lockedDrift/1_000_000.0);
        for(var base:List.of(physical,fixture)){
            var full=new MovementTraceSink.Context("0123456789abcdef0123456789abcdef".repeat(4),"d".repeat(64),base.sourceKind(),base.save(),base.world(),
                    123.45678901234567,2041.2345678901234,56.159265358979324,base.profile(),0,64.43802833557129,0);
            Path path=run.resolve("full-six-seconds-"+base.profile()+".ndjson");
            long anchor=-12_345_678_901_234_567L,utc=1_799_999_999_000L;
            try(var sink=MovementTraceSink.open(path,root,full,anchor,utc)){
                var origin=new MovementTraceSink.Motion(0,full.anchorY(),0,0,0,0,true,true);
                check(sink.sample(anchor,utc,"SETTLING",origin,origin,1,anchor,true),"Six-second trace starts with its precise stationary anchor");
                for(int i=1;i<60;i++){
                    long at=anchor+i*MovementTraceSink.PERIOD_NS+7_654_321L;
                    var client=new MovementTraceSink.Motion(.4234567890123456+i*.000001,64.43802833557129,-.6256789012345678,
                            .01234567890123456,-.0784000015258789,-.02345678901234567,true,true);
                    var server=new MovementTraceSink.Motion(.4123456789012345+i*.000001,64.43802833557129,-.6123456789012345,
                            .01123456789012345,-.0784000015258789,-.02234567890123456,true,true);
                    check(sink.sample(at,utc+i*100L+7,"WALKING",client,server,i+1,at-50_000_000L,false),"Realistic long-double physical record fits its scheduled six-second slot");
                }
                check(sink.sample(anchor+6_000_000_000L,utc+6000,"PASSED",origin,origin,61,anchor+6_000_000_000L,true),"Six-second final source snapshot is retained");
                check(sink.byteCount()<=MovementTraceSink.MAX_BYTES-MovementTraceSink.END_RESERVE,"Full six-second samples preserve the original end reserve");
                sink.finish(utc+6000,"passed","PASSED","Synthetic six-second phase-locked budget check");
                check(sink.records()==63 && sink.byteCount()<=MovementTraceSink.MAX_BYTES,"Full physical trace fits200records/64KiB including begin,61samples and end");
                System.out.printf(Locale.ROOT,"SYNTHETIC_TRACE_BUDGET profile=%s run_chars=%d samples=61 records=%d bytes=%d limit=%d game_calls=false%n",
                        base.profile(),full.run().length(),sink.records(),sink.byteCount(),MovementTraceSink.MAX_BYTES);
            }
            var records=Files.readAllLines(path);
            check(JsonParser.parseString(records.get(records.size()-2)).getAsJsonObject().get("phase").getAsString().equals("PASSED") &&
                    JsonParser.parseString(records.getLast()).getAsJsonObject().get("kind").getAsString().equals("end"),"Fresh forced final precedes its reserved termination record");
            Path exhausted=run.resolve("phase-locked-exhausted-"+base.profile()+".ndjson");
            try(var sink=MovementTraceSink.open(exhausted,root,full,0,1000)){
                boolean bounded=false;
                for(int i=0;i<=MovementTraceSink.MAX_RECORDS;i++){
                    try{sink.sample(i*MovementTraceSink.PERIOD_NS,1000+i*100L,"RESTING",motion(.1),motion(.1),i+1,i*MovementTraceSink.PERIOD_NS,false);}
                    catch(IOException expected){bounded=true;break;}
                }
                check(bounded,"Physical phase locking cannot bypass the original record/byte bound");
                sink.finish(25000,"failed","FAILED","Original end reserve remains available after physical sampling budget exhaustion");
                check(sink.records()<=MovementTraceSink.MAX_RECORDS && sink.byteCount()<=MovementTraceSink.MAX_BYTES,"Exhausted physical stream still writes its bounded final cleanup record");
            }
        }
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
            var fixture=new MovementTraceSink.Context("fixture-physical-patch","c".repeat(64),"standalone_ground_fixture",hudSave,world,0,0,10,
                    MovementTraceSink.Profile.HUD_PHYSICAL_FIXTURE,0,64.375,0);
            Path fixtureFile=root.resolve("physical-fixture.ndjson");
            try(var sink=MovementTraceSink.open(fixtureFile,root,fixture,0,1000)){sink.finish(1001,"stopped","STOPPED","Fixture provenance test");}
            var fixtureRecords=Files.readAllLines(fixtureFile);
            check(fixtureRecords.size()==2 && fixtureRecords.stream().allMatch(line->line.contains("\"source_kind\":\"standalone_hud_physical_movement_fixture\"")),"Scripted physical traces retain distinct source on every record");
            for(var profile:List.of(MovementTraceSink.Profile.HUD_PHYSICAL,MovementTraceSink.Profile.HUD_COUPLED)){
                try{new MovementTraceSink.Context("run","a".repeat(64),"standalone_ground_fixture",hudSave,world,0,0,10,profile);throw new AssertionError("Fixture entered live profile");}
                catch(IllegalArgumentException expected){checks++;}
            }
            try{new MovementTraceSink.Context("run","a".repeat(64),"live_kcd_ground_patch",hudSave,world,0,0,10,MovementTraceSink.Profile.HUD_PHYSICAL_FIXTURE);throw new AssertionError("Live patch silently became fixture");}
            catch(IllegalArgumentException expected){checks++;}
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
            // Actual27Oct failure: prediction had reached the lower slab, but
            // the fresh server sample was still .0784m into its descent with
            // onGround=true and proxySupport=false. Keep that observation;
            // only its active phase changes, so the receiver can validate air.
            var lowerClient=new MovementTraceSink.Motion(.06919256889657938,63.95803165435791,-.3960609344536225,
                    .0038621057757496193,-.0784000015258789,-.022106842496170793,true,true);
            var descendingServer=new MovementTraceSink.Motion(.06494849673784928,64.03399337768555,-.3717677016414737,
                    0,-.0784000015258789,0,true,false);
            check(lowerClient.onGround() && lowerClient.proxySupport() && descendingServer.onGround() && !descendingServer.proxySupport(),
                    "Regression reproduces client landing before authoritative slab support");
            Path phaseFile=run.resolve("physical-phase-regression.ndjson");
            try(var sink=MovementTraceSink.open(phaseFile,root,fixture,0,1000)){
                int serverSeq=1;
                for(String requested:List.of("RESTING","WALKING")){
                    String corrected=HudMovementPhase.forAuthoritativeGround(requested,descendingServer.onGround() && descendingServer.proxySupport());
                    check(corrected.equals("LANDING"),"Neutral and held input both classify unsupported server descent as landing");
                    long at=serverSeq*100_000_000L;
                    check(sink.sample(at,1000+serverSeq*100L,corrected,lowerClient,descendingServer,serverSeq,at,false),
                            "Corrected landing is emitted without dropping the authoritative source point");
                    serverSeq++;
                }
                sink.finish(1300,"stopped","STOPPED","Standalone phase regression complete");
            }
            var phaseLines=Files.readAllLines(phaseFile);
            for(int i=1;i<=2;i++){
                var value=JsonParser.parseString(phaseLines.get(i)).getAsJsonObject();
                var savedServer=value.getAsJsonObject("server");
                check(value.get("phase").getAsString().equals("LANDING") && savedServer.get("on_ground").getAsBoolean() &&
                        !savedServer.get("proxy_support").getAsBoolean(),"Landing label preserves actual conflicting ground/support flags");
                check(savedServer.get("y").getAsDouble()==descendingServer.y() && savedServer.get("vy").getAsDouble()==descendingServer.vy() &&
                        value.getAsJsonObject("client").get("y").getAsDouble()==lowerClient.y(),
                        "Phase correction neither snaps the server to client feet nor rewrites descent velocity");
            }
            var airborne=new MovementTraceSink.Motion(.1,64.1,-.4,0,-.08,0,false,true);
            check(HudMovementPhase.forAuthoritativeGround("RESTING",airborne.onGround() && airborne.proxySupport()).equals("LANDING"),
                    "Proxy proximity cannot make an airborne authoritative sample rest");
            for(String phase:List.of("RESTING","WALKING")){
                check(HudMovementPhase.forAuthoritativeGround(phase,true).equals(phase),"Supported authoritative active phase is unchanged");
                check(HudMovementPhase.forAuthoritativeGround(phase,false).equals("LANDING"),"Existing sampled-height ground failure also remains landing");
            }
            for(String phase:List.of("SETTLING","PASSED","JUMPING","LANDING","FAILED","STOPPED"))
                check(HudMovementPhase.forAuthoritativeGround(phase,false).equals(phase),"Explicit anchor, completion and non-ground phases are preserved");
            try{new MovementTraceSink.Context("run","a".repeat(64),"live_kcd_ground_patch",hudSave,world,100,200,10,MovementTraceSink.Profile.HUD_COUPLED,0,64.375,0);throw new AssertionError("Coupled anchor changed");}
            catch(IllegalArgumentException expected){checks++;}
            try{new MovementTraceSink.Context("run","a".repeat(64),"live_kcd_ground_patch",hudSave,world,100,200,10,MovementTraceSink.Profile.HUD_PHYSICAL,.5,64,0);throw new AssertionError("Physical horizontal hop accepted");}
            catch(IllegalArgumentException expected){checks++;}
            phaseLockedSampling(root,run,physical,fixture,hud);
            samplingComparisonAndBudget(root,run,physical,fixture);
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
