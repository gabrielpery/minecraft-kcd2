package dev.minecome.hud;

import com.google.gson.*;
import com.sun.jna.Pointer;
import com.sun.jna.platform.win32.*;
import java.io.IOException;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Protocol/HUD_STREAM.md. Native operations and pixel conversion are confined to one worker. */
public final class HudStreamProducer implements AutoCloseable {
    public static final int HEADER_BYTES=256, MAPPING_BYTES=HEADER_BYTES+1920*1080*4;
    public record Identity(String run,int targetPid,long targetStart,long expiresUtcMs) {
        public Identity {
            if(run==null || !run.matches("[0-9a-f]{32}") || targetPid<=0 || targetStart<=0 || expiresUtcMs<=0)
                throw new IllegalArgumentException("Invalid HUD stream identity");
        }
        public String mappingName(){return "Local\\MineComeHud_"+run;}
        public String mutexName(){return "Local\\MineComeHudLock_"+run;}
    }
    /** Ownership of bottomUp transfers to the mailbox; no caller may mutate it afterward. */
    public record Frame(int width,int height,byte[] bottomUp,long capturedUtcMs,int selectedSlot,int screen,String metadata) {
        public Frame {
            if(bottomUp.length!=HudPixels.byteSize(width,height) || capturedUtcMs<=0 || selectedSlot<0 || selectedSlot>8 || screen<0 || screen>1 || metadata==null || metadata.length()>16384)
                throw new IllegalArgumentException("Invalid stream frame");
        }
    }
    private final Identity identity;
    private final Path root,directory;
    private final String save;
    private final boolean genuine;
    private final int inputMode;
    private final boolean inputDelayFixture;
    private final AtomicReference<Frame> latest=new AtomicReference<>();
    private final AtomicReference<String> terminal=new AtomicReference<>(),failure=new AtomicReference<>();
    private final AtomicReference<JsonObject> finalEvidence=new AtomicReference<>();
    private final AtomicReference<JsonArray> fixtureTargets=new AtomicReference<>();
    private final AtomicBoolean ready=new AtomicBoolean(),finished=new AtomicBoolean();
    private final AtomicLong replaced=new AtomicLong(),published=new AtomicLong();
    private Thread worker;
    private volatile int producerPid;
    private volatile long producerStart,lastPublishedAt;
    public HudStreamProducer(Path root,Path directory,Identity identity,String save,boolean genuine) {
        this(root,directory,identity,save,genuine,0);
    }
    public HudStreamProducer(Path root,Path directory,Identity identity,String save,boolean genuine,int inputMode) {
        if(!root.isAbsolute() || !directory.isAbsolute() || save==null || !save.matches("MineCome-HudStream-[0-9a-f-]{36}"))
            throw new IllegalArgumentException("Invalid owned stream output path/save");
        if(inputMode<0 || inputMode>2)throw new IllegalArgumentException("Invalid input mode");
        this.root=root.normalize();this.directory=directory.normalize();this.identity=identity;this.save=save;this.genuine=genuine;this.inputMode=inputMode;
        inputDelayFixture=inputMode==2 && Boolean.getBoolean("minecome.hudStreamInputDelayFixture");
    }
    public synchronized void start() {
        if(worker!=null)throw new IllegalStateException("HUD stream cannot restart");
        worker=new Thread(this::run,"MineComeHudStreamWriter");
        // A bounded worker completes its terminal record even after Minecraft's normal shutdown.
        worker.start();
    }
    public boolean isReady(){return ready.get() && failure.get()==null && !finished.get();}
    public boolean isFinished(){return finished.get();}
    public String failure(){return failure.get();}
    public long publishedFrames(){return published.get();}
    public int producerPid(){return producerPid;}
    public long producerStart(){return producerStart;}
    public long lastPublishedAt(){return lastPublishedAt;}
    public void offerFixtureTargets(JsonArray slots){if(inputMode!=2 || !fixtureTargets.compareAndSet(null,slots.deepCopy()))throw new IllegalStateException("Fixture targets not allowed/already queued");}
    public void offer(Frame frame) {
        if(!isReady() || terminal.get()!=null)return;
        if(latest.getAndSet(frame)!=null)replaced.incrementAndGet();
    }
    public void finish(String result,JsonObject evidence) {
        if(!Set.of("passed","failed","stopped","fixture","input_passed","input_completed","input_cancelled").contains(result))throw new IllegalArgumentException("Invalid stream result");
        if(evidence!=null)finalEvidence.compareAndSet(null,evidence.deepCopy());
        terminal.compareAndSet(null,result);
    }
    @Override public void close(){finish("stopped",null);}
    /** Fixtures only; never invoked by the game/render thread. */
    public boolean awaitFinished(long millis)throws InterruptedException {
        if(millis<1 || millis>5000)throw new IllegalArgumentException("Bounded worker wait required");
        Thread value; synchronized(this){value=worker;} if(value==null)return false;value.join(millis);return finished.get();
    }
    public static byte[] header(Identity id,int producerPid,long producerStart,long sequence,long captured,int width,int height,int selected,int screen,int state) {
        if(producerPid<=0 || producerStart<=0 || sequence<0 || captured<0 || state<0 || state>2 || selected<0 || selected>8 || screen<0 || screen>1)
            throw new IllegalArgumentException("Invalid header fields");
        int size=(width==0 && height==0 && state!=1)?0:HudPixels.byteSize(width,height);
        if(state==1 && (sequence==0 || captured==0))throw new IllegalArgumentException("Frame identity required");
        var b=ByteBuffer.allocate(HEADER_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.put("MCHUDS01".getBytes(StandardCharsets.US_ASCII)).putInt(1).putInt(HEADER_BYTES);
        b.put(id.run().getBytes(StandardCharsets.US_ASCII)).putInt(producerPid).putInt(id.targetPid());
        b.putLong(producerStart).putLong(id.targetStart()).putLong(id.expiresUtcMs()).putLong(sequence).putLong(captured);
        b.putInt(width).putInt(height).putInt(width*4).putInt(size).putInt(1).putInt(state).putInt(selected).putInt(screen);
        return b.array();
    }
    private JsonObject identityReceipt(int pid,long start) {
        var r=new JsonObject();r.addProperty("schema",1);r.addProperty("run",identity.run());r.addProperty("pid",pid);r.addProperty("producer_pid",pid);
        r.addProperty("producer_start_filetime",Long.toUnsignedString(start));r.addProperty("target_pid",identity.targetPid());
        r.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));r.addProperty("expires_utc_ms",identity.expiresUtcMs());
        r.addProperty("mapping",identity.mappingName());r.addProperty("mapping_name",identity.mappingName());r.addProperty("mutex_name",identity.mutexName());r.addProperty("mapping_bytes",MAPPING_BYTES);
        r.addProperty("save",save);r.addProperty("source_kind",genuine?"minecraft_vanilla_ui_stream_v1":"standalone_transport_fixture");
        if(inputMode!=0){r.addProperty("ui_input_protocol",1);r.addProperty("ui_input_fixture",inputMode==2);r.addProperty("ui_input_delay_fixture",inputDelayFixture);}return r;
    }
    private void run() {
        Kernel32 api=null;WinNT.HANDLE mapping=null,mutex=null;Pointer view=null;
        Path target=null;int pid=0,width=0,height=0,selected=0,screen=0;long start=0,sequence=0,lastCaptured=0,skippedBusy=0,staleDrops=0;
        boolean closed=false,unmapped=false,mappingClosed=false,mutexClosed=false;
        var samples=new JsonArray();var states=new LinkedHashSet<String>();String result="failed";
        try {
            long remaining=identity.expiresUtcMs()-System.currentTimeMillis();
            if(remaining<=0 || remaining>180_000)throw new IOException("Initial stream lease outside 1..180000ms");
            long deadline=System.nanoTime()+remaining*1_000_000L;
            Path realRoot=root.toRealPath(),evidence=root.resolve("runtime/evidence").toRealPath(),parent=directory.getParent().toRealPath();
            if(!evidence.startsWith(realRoot) || !parent.startsWith(evidence) || parent.equals(realRoot))throw new IOException("Stream output escapes runtime/evidence");
            target=parent.resolve(directory.getFileName());Files.createDirectory(target);
            // Signatures/constants inspected in Minecraft's cached JNA 5.14.0 platform jar.
            // JNA exposes MapViewOfFile length as int; fixed 8,294,656 bytes fits exactly.
            api=Kernel32.INSTANCE;pid=api.GetCurrentProcessId();
            var creation=new WinBase.FILETIME();
            if(!api.GetProcessTimes(api.GetCurrentProcess(),creation,new WinBase.FILETIME(),new WinBase.FILETIME(),new WinBase.FILETIME()))throw nativeFailure(api,"GetProcessTimes");
            start=(Integer.toUnsignedLong(creation.dwHighDateTime)<<32)|Integer.toUnsignedLong(creation.dwLowDateTime);
            producerPid=pid;producerStart=start;
            mapping=api.CreateFileMapping(WinBase.INVALID_HANDLE_VALUE,null,WinNT.PAGE_READWRITE,0,MAPPING_BYTES,identity.mappingName());
            int mappingError=api.GetLastError();
            if(mapping==null || mappingError==WinError.ERROR_ALREADY_EXISTS)throw new IOException("CreateFileMapping failed/existing: "+mappingError);
            mutex=api.CreateMutex(null,false,identity.mutexName());int mutexError=api.GetLastError();
            if(mutex==null || mutexError==WinError.ERROR_ALREADY_EXISTS)throw new IOException("CreateMutex failed/existing: "+mutexError);
            view=api.MapViewOfFile(mapping,WinNT.FILE_MAP_ALL_ACCESS,0,0,MAPPING_BYTES);
            if(view==null)throw nativeFailure(api,"MapViewOfFile");
            if(!lock(api,mutex))throw new IOException("Fresh mutex unexpectedly busy");
            try {view.clear(MAPPING_BYTES);view.write(0,header(identity,pid,start,0,0,0,0,0,0,0),0,HEADER_BYTES);}
            finally {unlock(api,mutex);}
            writeJson(target.resolve("stream-ready.json"),identityReceipt(pid,start));ready.set(true);
            while(true) {
                String end=terminal.get();
                if(end!=null){result=end;break;}
                if(System.currentTimeMillis()>=identity.expiresUtcMs() || System.nanoTime()>=deadline)throw new IOException("Immutable stream lease expired");
                var targets=fixtureTargets.getAndSet(null);
                if(targets!=null){var receipt=identityReceipt(pid,start);receipt.add("slots",targets);writeJson(target.resolve("fixture-targets.json"),receipt);}
                Frame frame=latest.getAndSet(null);
                if(frame==null){Thread.sleep(5);continue;}
                long now=System.currentTimeMillis();
                if(frame.capturedUtcMs()>now+250 || frame.capturedUtcMs()<now-1000){staleDrops++;continue;}
                if(width!=0 && (frame.width()!=width || frame.height()!=height))throw new IOException("Stream dimensions changed");
                byte[] rgba=HudPixels.straightTopLeft(frame.bottomUp(),frame.width(),frame.height());
                if(!lock(api,mutex)){skippedBusy++;continue;}
                try {
                    width=frame.width();height=frame.height();selected=frame.selectedSlot();screen=frame.screen();lastCaptured=frame.capturedUtcMs();
                    byte[] head=header(identity,pid,start,++sequence,lastCaptured,width,height,selected,screen,1);
                    view.write(HEADER_BYTES,rgba,0,rgba.length);view.write(0,head,0,head.length);
                } finally {unlock(api,mutex);}
                published.incrementAndGet();
                lastPublishedAt=System.nanoTime();
                JsonObject meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();String stage=meta.get("state").getAsString();
                if(!stage.matches("[a-z0-9_]{1,40}"))throw new IOException("Invalid sample state");
                if(states.add(stage)) {
                    if(states.size()>8)throw new IOException("Sample state bound exceeded");
                    String name="sample-"+stage+".png";byte[] png=HudPixels.png(rgba,width,height);
                    Files.write(target.resolve(name),png,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
                    meta.addProperty("png_file",name);meta.addProperty("png_sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));
                    meta.addProperty("width",width);meta.addProperty("height",height);meta.addProperty("sequence",sequence);samples.add(meta);
                }
            }
            if(result.equals("passed") && (!genuine || published.get()<30 || !states.containsAll(Set.of("hotbar_slot0","hotbar_slot1","inventory_screen","hotbar_slot2"))))
                throw new IOException("Continuous vanilla state proof incomplete");
            if(result.equals("input_passed") || result.equals("input_completed")){
                if(!genuine || inputMode==0 || published.get()<5 || !states.contains("hotbar"))throw new IOException("Input stream vanilla proof incomplete");
                var inputProof=finalEvidence.get();
                if(inputProof==null || !inputProof.get("host_armed").getAsBoolean() || inputProof.get("input_events_applied").getAsLong()<=0)throw new IOException("Input stream was never armed/applied");
                if(result.equals("input_passed")){
                    var proof=finalEvidence.get();
                    if(inputMode!=2 || proof==null)throw new IOException("Input fixture proof absent");
                    for(String key:List.of("input_fixture","server_swap_verified","inventory_opened","inventory_closed","selected_nine_verified","host_armed"))
                        if(!proof.has(key) || !proof.get(key).getAsBoolean())throw new IOException("Input fixture proof missing: "+key);
                }
            }
        } catch(Exception e) {failure.compareAndSet(null,e.toString());result="failed";}
        finally {
            ready.set(false);latest.set(null);
            if(api!=null && view!=null && mutex!=null)try {
                // Three bounded attempts; never wait indefinitely to close a foreign-owned mutex.
                for(int attempt=0;attempt<3 && !closed;attempt++)if(lock(api,mutex))try {
                    byte[] head=header(identity,pid,start,sequence,lastCaptured,width,height,selected,screen,2);view.write(0,head,0,head.length);closed=true;
                }finally {unlock(api,mutex);}
                if(closed)Thread.sleep(150);
            }catch(Exception e){failure.compareAndSet(null,e.toString());}
            if(api!=null) {
                if(view!=null)unmapped=api.UnmapViewOfFile(view);else unmapped=true;
                if(mutex!=null)mutexClosed=api.CloseHandle(mutex);else mutexClosed=true;
                if(mapping!=null)mappingClosed=api.CloseHandle(mapping);else mappingClosed=true;
            }
            if(!closed || !unmapped || !mappingClosed || !mutexClosed) {failure.compareAndSet(null,"Terminal closed/handle cleanup incomplete");result="failed";}
            if(target!=null)try {
                var receipt=identityReceipt(pid,start);receipt.addProperty("result",failure.get()==null?result:"failed");receipt.addProperty("published_frames",published.get());
                receipt.addProperty("mailbox_replaced",replaced.get());receipt.addProperty("mutex_busy_skipped",skippedBusy);receipt.addProperty("stale_frames_dropped",staleDrops);
                receipt.addProperty("closed_published",closed);receipt.addProperty("mapping_unmapped",unmapped);receipt.addProperty("mapping_handle_closed",mappingClosed);receipt.addProperty("mutex_handle_closed",mutexClosed);
                var seen=new JsonArray();states.forEach(seen::add);receipt.add("states_seen",seen);receipt.add("samples",samples);
                receipt.addProperty("kcd_compositing_verified",false);if(failure.get()!=null)receipt.addProperty("failure",failure.get());
                if(finalEvidence.get()!=null)receipt.add("lab_evidence",finalEvidence.get());writeJson(target.resolve("stream-result.json"),receipt);
            }catch(Exception e){failure.compareAndSet(null,e.toString());}
            finished.set(true);
        }
    }
    private static IOException nativeFailure(Kernel32 api,String operation){return new IOException(operation+" failed: "+api.GetLastError());}
    private static boolean lock(Kernel32 api,WinNT.HANDLE mutex)throws IOException {
        int result=api.WaitForSingleObject(mutex,5);
        if(result==WinBase.WAIT_OBJECT_0)return true;
        if(result==WinError.WAIT_TIMEOUT)return false;
        if(result==WinBase.WAIT_ABANDONED){api.ReleaseMutex(mutex);throw new IOException("Abandoned stream mutex");}
        throw new IOException("Stream mutex wait failed: "+result);
    }
    private static void unlock(Kernel32 api,WinNT.HANDLE mutex)throws IOException {if(!api.ReleaseMutex(mutex))throw nativeFailure(api,"ReleaseMutex");}
    private static void writeJson(Path path,JsonObject object)throws IOException {
        byte[] body=(new GsonBuilder().setPrettyPrinting().create().toJson(object)+"\n").getBytes(StandardCharsets.UTF_8);
        if(body.length>65536)throw new IOException("Stream receipt byte bound exceeded");
        Path temp=path.resolveSibling(path.getFileName()+"."+UUID.randomUUID()+".tmp");
        Files.write(temp,body,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
        // Same-directory move publishes a complete new receipt; existing destinations are refused.
        Files.move(temp,path);
    }
}
