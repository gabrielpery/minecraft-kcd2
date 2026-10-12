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
