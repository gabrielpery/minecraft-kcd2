package dev.minecome.hud;

import com.google.gson.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;

/** Pure protocol, held-input and original-capture freshness tests; no games or synthetic native input. */
public final class HudPhysicalMovementTests {
    private static int checks;
    private static final String RUN="a".repeat(32),PATCH="b".repeat(32),HASH="c".repeat(64);
    private static final long NOW=1_800_000_000_000L;
    private static final HudInputProtocol.Identity ID=new HudInputProtocol.Identity(RUN,1,11,2,22,NOW+100000);
    private interface Work{void run()throws Exception;}
    private static void check(boolean b,String why){checks++;if(!b)throw new AssertionError(why);}
    private static void reject(Work work,String why)throws Exception{
        try{work.run();throw new AssertionError("Accepted "+why);}catch(java.io.IOException|IllegalArgumentException expected){checks++;}
    }
    private static Properties mode(){
        var p=new Properties();
        for(String key:List.of("hudPhysicalMovement","hudStreamLab","hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation"))p.setProperty("minecome."+key,"true");
        for(String key:List.of("groundPatchFile","movementTraceFile","hudHostViewFile"))p.setProperty("minecome."+key,"absolute-file");
        return p;
    }
    private static JsonObject vector(double x,double y,double z){var v=new JsonObject();v.addProperty("x",x);v.addProperty("y",y);v.addProperty("z",z);return v;}
    private static JsonObject view(long seq,long utc){
        var v=new JsonObject();v.addProperty("schema",1);v.addProperty("source_kind","live_kcd_hud_view_v1");v.addProperty("run",RUN);
        v.addProperty("patch_run",PATCH);v.addProperty("patch_sha256",HASH);v.addProperty("target_pid",2);v.addProperty("target_start_filetime","22");
        v.addProperty("seq",seq);v.addProperty("utc_ms",utc);v.add("forward",vector(0,-1,0));v.add("up",vector(0,0,1));return v;
    }
    private static byte[] bytes(JsonObject v){return v.toString().getBytes(StandardCharsets.UTF_8);}
    private static HudMovementView parse(JsonObject v)throws Exception{return HudMovementView.parse(bytes(v),ID,PATCH,HASH,NOW);}
    private static void modes()throws Exception{
        check(!HudPhysicalMovementMode.require(new Properties()),"Legacy defaults unchanged");
        check(HudPhysicalMovementMode.require(mode()),"Explicit complete movement profile accepted");
        for(String key:List.of("hudStreamLab","hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation","groundPatchFile","movementTraceFile","hudHostViewFile")){
            var p=mode();p.remove("minecome."+key);reject(()->HudPhysicalMovementMode.require(p),"missing "+key);
        }
        for(String key:List.of("hudStreamStandalone","hudGroundMovementFixture","hudGroundMovementCoupled","hudStreamInputFixture",
                "hudStreamInputPointerFixture","hudStreamInputDelayFixture","hudStreamBackgroundTrial","hudStreamOffscreenTrial","hudStoneBridge",
                "hudStoneFixture","hudStoneLive","hudAimedStoneBridge","groundMovementLab","externalInputLab","externalInputFixture",
                "aimedStoneLab","aimedBridgeLab","hudAimedBridgeLab","hudExportLab","interactiveStoneLab","smokeWorld","dynamicBridgeSmoke")){
            var p=mode();p.setProperty("minecome."+key,"true");reject(()->HudPhysicalMovementMode.require(p),"conflict "+key);
        }
    }
    private static void wire()throws Exception{
        for(int key:List.of(0x57,0x41,0x53,0x44,0x20)){
            var event=new HudInputProtocol.Event(1,NOW,1,key,0,0,0);
            reject(()->HudInputProtocol.validateEvent(event,NOW,true),"legacy movement key");
            HudInputProtocol.validateEvent(event,NOW,true,true);checks++;
            var gate=new HudInputGate(true);gate.apply(event,NOW);check(gate.heldKeyCount()==1,"v2 strict hold");
            reject(()->gate.apply(new HudInputProtocol.Event(2,NOW,1,key,0,0,0),NOW),"duplicate movement down");
            gate.apply(new HudInputProtocol.Event(2,NOW,2,key,0,0,0),NOW);check(gate.heldKeyCount()==0,"v2 balanced release");
        }
        reject(()->HudInputProtocol.validateEvent(new HudInputProtocol.Event(1,NOW,1,0x10,0,0,0),NOW,true,true),"v2 unsupported shift");
        byte[] bytes=new byte[2816];var b=ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
        b.put("MCHUDI02".getBytes(StandardCharsets.US_ASCII));b.putInt(8,2).putInt(12,2816);
        b.position(16);b.put(RUN.getBytes(StandardCharsets.US_ASCII));b.putInt(48,1).putInt(52,2).putLong(56,11).putLong(64,22).putLong(72,ID.expires());
        b.putLong(80,1).putLong(88,NOW).putInt(96,1).putInt(100,1);
        b.putLong(256,1).putLong(264,NOW).putInt(272,1).putInt(276,0x57);
        check(HudInputProtocol.decode(bytes,ID,0,NOW,0,true).events().size()==1,"v2 exact same-sized mapping decoded");
        reject(()->HudInputProtocol.decode(bytes,ID,0,NOW,0),"v1 cannot accept v2 header");
        b.putInt(8,1);reject(()->HudInputProtocol.decode(bytes,ID,0,NOW,0,true),"mixed magic version");
        b.putInt(8,2);b.putLong(264,NOW-251);reject(()->HudInputProtocol.decode(bytes,ID,0,NOW,0,true),"v2 retains250ms edge freshness");
    }
    private static void holds(){
        long now=1_000_000_000L;var gate=new HudMovementKeys();
        check(!gate.event(1,0x57,now,false) && !gate.started(),"unready down cannot start");
        gate.authority(now,true);check(!gate.down(0x57,now),"held raw input cannot resume after authority returns");
        gate.event(2,0x57,now,true);gate.authority(now,true);
        check(gate.event(1,0x57,now,true) && gate.down(0x57,now),"fresh down after neutral starts");
        gate.suspend();check(!gate.down(0x57,now),"inventory suspend immediately neutralizes");
        gate.authority(now+1,true);check(!gate.down(0x57,now+1),"inventory close does not restore held movement");
        gate.event(2,0x57,now+2,true);gate.authority(now+2,true);
        check(gate.event(1,0x57,now+3,true),"fresh release and down resume within original window");
        check(!gate.down(0x57,now+2+HudMovementKeys.HOLD_LEASE_NS),"stale input lease releases before tick");
        gate.authority(now+200_000_000,true);check(!gate.down(0x57,now+200_000_000),"heartbeat cannot resume stale held key");
        gate.event(2,0x57,now+200_000_000,true);gate.authority(now+200_000_000,true);gate.event(1,0x20,now+200_000_000,true);
        check(gate.down(0x20,now+200_000_000),"space uses same held lease");
        gate.authority(now+HudMovementKeys.ACTIVE_NS,true);
        check(gate.ended() && gate.neutral(now+HudMovementKeys.ACTIVE_NS),"fixed5s lifetime releases without renewal");
        gate.event(2,0x20,now+HudMovementKeys.ACTIVE_NS,true);gate.authority(now+HudMovementKeys.ACTIVE_NS,true);
        check(!gate.event(1,0x57,now+HudMovementKeys.ACTIVE_NS,true),"terminal cannot reactivate");
        gate.close();check(gate.rawCount()==0,"disconnect close releases raw bookkeeping");
        gate=new HudMovementKeys();gate.authority(now,true);gate.event(1,0x57,now,true);
        check(!gate.down(0x57,now-1) && gate.ended(),"monotonic regression ends movement");
    }
    private static void views()throws Exception{
        var parsed=parse(view(1,NOW));
        check(parsed.sequence()==1 && parsed.yaw()==0 && parsed.pitch()==0,"KCD negativeY converts Minecraft yaw0");
        check(parsed.fresh(NOW+300) && !parsed.fresh(NOW+301),"camera lease anchored to source timestamp");
        check(!parsed.fresh(NOW-51),"camera cannot run before allowed clock skew");
        var v=view(2,NOW);v.add("forward",vector(1,0,0));check(parse(v).yaw()==-90,"fresh camera updates yaw basis");
        for(String field:List.of("schema","source_kind","run","patch_run","patch_sha256","target_pid","target_start_filetime","seq","utc_ms","forward","up")){
            var bad=view(1,NOW);bad.remove(field);reject(()->parse(bad),"missing view "+field);
        }
        for(String field:List.of("run","patch_run","patch_sha256","target_start_filetime","source_kind")){
            var bad=view(1,NOW);bad.addProperty(field,"wrong");reject(()->parse(bad),"wrong view "+field);
        }
        var bad=view(1,NOW);bad.addProperty("extra",1);var extra=bad;reject(()->parse(extra),"unknown view field");
        reject(()->parse(view(0,NOW)),"zero sequence");reject(()->parse(view(1,NOW+51)),"future source time");
        bad=view(1,NOW);bad.add("forward",vector(0,0,0));var zero=bad;reject(()->parse(zero),"zero camera direction");
        bad=view(1,NOW);bad.add("up",vector(0,-1,0));var parallel=bad;reject(()->parse(parallel),"parallel forward up");
        String duplicate=view(1,NOW).toString().replace("\"schema\":1","\"schema\":1,\"schema\":1");
        reject(()->HudMovementView.parse(duplicate.getBytes(StandardCharsets.UTF_8),ID,PATCH,HASH,NOW),"duplicate JSON field");
        reject(()->HudMovementView.parse(new byte[4097],ID,PATCH,HASH,NOW),"oversize camera");
    }
    private static void waitFor(BooleanSupplier condition)throws Exception{
        long end=System.nanoTime()+3_000_000_000L;while(!condition.getAsBoolean()&&System.nanoTime()<end)Thread.sleep(10);
        check(condition.getAsBoolean(),"worker reached bounded expected state");
    }
    private static void reader()throws Exception{
        Path root=Files.createTempDirectory("minecome-view-test-").toRealPath(),file=root.resolve("view.json");
        try{
            var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH);
            try(reader){
                long utc=System.currentTimeMillis();Files.write(file,bytes(view(1,utc)));reader.start();
                waitFor(()->reader.current(System.currentTimeMillis(),System.nanoTime())!=null);
                var sample=reader.current(System.currentTimeMillis(),System.nanoTime());check(sample!=null,"initial live source accepted");
                waitFor(()->reader.current(System.currentTimeMillis(),System.nanoTime())==null);
                check(reader.failure()==null,"unchanged bytes simply expire without renewal");
                var replacement=view(1,System.currentTimeMillis());Path temp=root.resolve("next.json");Files.write(temp,bytes(replacement));
                Files.move(temp,file,StandardCopyOption.REPLACE_EXISTING);
                waitFor(()->reader.failure()!=null);
                check(reader.current(System.currentTimeMillis(),System.nanoTime())==null,"same sequence cannot renew source lease");
            }
            reject(()->new HudMovementViewReader(root.getParent().resolve("outside.json"),root,ID,PATCH,HASH),"camera parent outside evidence");
        }finally{try(var paths=Files.walk(root)){for(Path path:paths.sorted(Comparator.reverseOrder()).toList())Files.delete(path);}}
    }
    private static void readerRaces()throws Exception{
        Path root=Files.createTempDirectory("minecome-view-race-").toRealPath(),file=root.resolve("view.json");
        try{
            var mode=new AtomicInteger();var reads=new AtomicInteger();long utc=System.currentTimeMillis();
            byte[] original=bytes(view(1,utc));
            HudMovementViewReader.FileReader source=path->{
                reads.incrementAndGet();
                if(mode.get()==1)throw new FileSystemException(path.toString(),null,"The process cannot access the file because it is being used by another process");
                if(mode.get()==2)throw new NoSuchFileException(path.toString());
                return original;
            };
            try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,source)){
                mode.set(1);reader.start();
                waitFor(()->reads.get()>=2);
                check(reader.failure()==null && reader.current(utc,System.nanoTime())==null,"transient initial sharing denial grants no camera authority");
                mode.set(0);waitFor(()->reader.current(System.currentTimeMillis(),System.nanoTime())!=null);
                var first=reader.current(System.currentTimeMillis(),System.nanoTime());
                var firstDiagnostic=reader.inspect(utc,System.nanoTime());
                check(firstDiagnostic.current()==first && firstDiagnostic.diagnostics().get("sample_sequence").getAsLong()==1 &&
                        firstDiagnostic.diagnostics().get("source_utc_ms").getAsLong()==utc,"diagnostics bind exact immutable accepted source");
                final int beforeMissing=reads.get();mode.set(2);waitFor(()->reads.get()>=beforeMissing+2);
                var retained=reader.current(System.currentTimeMillis(),System.nanoTime());
                check(retained==first && reader.failure()==null,"atomic replacement absence retains exact original sample/deadline during bounded retry");
                check(reader.current(utc+301,System.nanoTime())==null,"read retry cannot renew an old capture timestamp");
                mode.set(0);final int recoveredAfter=reads.get();
                waitFor(()->reads.get()>recoveredAfter);
                check(reader.current(utc,first.deadlineNs()-1)==first,"same-byte recovery keeps exact original monotonic deadline");
                check(reader.current(utc,first.deadlineNs())==null,"same-byte recovery cannot extend original monotonic deadline");
                var expired=reader.inspect(utc+301,first.deadlineNs());
                check(expired.current()==null && !expired.diagnostics().get("active_sample_available").getAsBoolean() &&
                        expired.diagnostics().get("sample_deadline_ns").getAsLong()==first.deadlineNs() &&
                        expired.diagnostics().get("source_age_ms").getAsLong()==301,
                        "rejection diagnostic preserves original sequence UTC age and monotonic expiry");
                mode.set(1);waitFor(()->reader.failure()!=null);
                check(reader.failure().contains("retry deadline") && reader.current(utc,System.nanoTime())==null,"persistent sharing violation is terminal after bounded retry");
                var terminal=reader.diagnostics(System.currentTimeMillis(),System.nanoTime());
                check(terminal.get("sample_sequence").getAsLong()==1 && terminal.get("io_faults").getAsLong()>=3 &&
                        terminal.get("failure").getAsString().contains("retry deadline"),"terminal diagnostics survive sample cleanup");
            }
            var counter=new AtomicInteger();
            byte[] fresh=bytes(view(2,System.currentTimeMillis()));
            try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,path->{
                if(counter.incrementAndGet()==1)throw new FileSystemException(path.toString(),null,"sharing violation");
                return fresh;
            })){
                reader.start();waitFor(()->reader.current(System.currentTimeMillis(),System.nanoTime())!=null);
                check(reader.current(System.currentTimeMillis(),System.nanoTime()).view().sequence()==2,"fresh replacement is parsed normally after transient fault");
            }
            for(String content:List.of("{broken",view(1,utc).toString().replace(RUN,"d".repeat(32)))){
                var count=new AtomicInteger();
                try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,path->{count.incrementAndGet();return content.getBytes(StandardCharsets.UTF_8);})){
                    reader.start();waitFor(()->reader.failure()!=null);
                    check(count.get()==1 && !reader.failure().contains("retry deadline"),"malformed/schema identity data is fatal without I/O retry");
                }
            }
            var invalidReads=new AtomicInteger();
            try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,path->{invalidReads.incrementAndGet();throw new java.io.IOException("Invalid camera file");})){
                reader.start();waitFor(()->reader.failure()!=null);
                check(invalidReads.get()==1,"invalid file/reparse contract is not retried as sharing failure");
            }
            var release=new CountDownLatch(1);var blockingReads=new AtomicInteger();long startUtc=System.currentTimeMillis();
            byte[] firstBytes=bytes(view(1,startUtc));var latest=new AtomicReference<byte[]>(firstBytes);
            try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,path->{
                int count=blockingReads.incrementAndGet();
                if(count==2){
                    try{if(!release.await(1,TimeUnit.SECONDS))throw new java.io.IOException("test reader release deadline");}
                    catch(InterruptedException e){throw new java.io.IOException(e);}
                    latest.set(bytes(view(2,System.currentTimeMillis())));
                }
                return latest.get();
            })){
                reader.start();waitFor(()->blockingReads.get()>=2);
                var before=reader.diagnostics(startUtc,System.nanoTime());
                long deadline=before.get("sample_deadline_ns").getAsLong();
                var stalled=reader.inspect(startUtc+301,deadline);
                check(stalled.current()==null && stalled.diagnostics().get("stage").getAsString().equals("reading") &&
                        stalled.diagnostics().get("sample_sequence").getAsLong()==1,
                        "blocked worker cannot keep old camera authority; diagnostics distinguish read delay");
                release.countDown();
                waitFor(()->{var value=reader.current(System.currentTimeMillis(),System.nanoTime());return value!=null&&value.view().sequence()==2;});
                var recovered=reader.diagnostics(System.currentTimeMillis(),System.nanoTime());
                check(recovered.get("sample_sequence").getAsLong()==2 && recovered.get("read_attempts").getAsLong()>=2 &&
                        recovered.get("parse_publish_duration_ms").getAsDouble()>=0 &&
                        recovered.get("last_read_duration_ms").getAsDouble()>=0,"fresh recovery records observed read and publish timing");
            }finally{release.countDown();}
        }finally{Files.delete(root);}
    }
    public static void main(String[] args)throws Exception{modes();wire();holds();views();reader();readerRaces();checks+=dev.minecome.terrain.HudMovementBoundaryTests.run();System.out.println("HudPhysicalMovementTests: "+checks+" checks passed");}
}
