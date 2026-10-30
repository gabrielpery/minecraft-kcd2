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
    private record Sample(byte[] rgba,int width,int height,JsonObject metadata,String name){}
    private static final Set<String> WALKING_AIMED_SAMPLE_STATES=Set.of(
            "fixture_settling","fixture_inventory_blocked","fixture_hotbar_ready","fixture_scripted_walking",
            "fixture_aimed_interactions","fixture_extended_wait","fixture_post_walk_inventory_blocked",
            "fixture_final_settling","fixture_cleanup");
    private record PublicationStage(String name,long at){}
    private final Identity identity;
    private final Path root,directory;
    private final String save;
    private final boolean genuine;
    private final int inputMode;
    private final boolean inputDelayFixture,inputPointerFixture,liveMouse,stoneBridge,stoneFixture,stoneLive,aimedStone;
    private final boolean backgroundTrial;
    private final boolean offscreenPresentation,offscreenTrial;
    private final HudGroundMovementMode.Mode groundMovementMode;
    private final boolean standalone;
    private final boolean physicalMovement,walkingAimedFixture;
    private final HudMovementSession movementSession;
    private final AtomicReference<Frame> latest=new AtomicReference<>();
    private final AtomicReference<String> terminal=new AtomicReference<>(),failure=new AtomicReference<>();
    private final AtomicReference<JsonObject> finalEvidence=new AtomicReference<>();
    private final AtomicReference<JsonArray> fixtureTargets=new AtomicReference<>();
    private final AtomicReference<JsonObject> backgroundTrialReceipt=new AtomicReference<>();
    private final AtomicReference<JsonObject> offscreenTrialReceipt=new AtomicReference<>();
    private final AtomicReference<JsonObject> pointerStageReceipt=new AtomicReference<>();
    private final AtomicBoolean ready=new AtomicBoolean(),finished=new AtomicBoolean();
    private final AtomicLong replaced=new AtomicLong(),published=new AtomicLong();
    private Thread worker;
    private volatile int producerPid;
    private volatile long producerStart,lastPublishedAt;
    private volatile PublicationStage publicationStage=new PublicationStage("not_started",System.nanoTime());
    private volatile long maxPublicationGapNanos,maxConversionNanos,maxMapWriteNanos,maxPublishedCaptureAgeMs,lastPublishedCaptureUtcMs,lastPublishedUtcMs;
    private volatile HudEvidenceWriter evidenceWriter;
    private boolean walkingAimReadyQueued,walkingAimClosedQueued;
    public HudStreamProducer(Path root,Path directory,Identity identity,String save,boolean genuine) {
        this(root,directory,identity,save,genuine,0);
    }
    public HudStreamProducer(Path root,Path directory,Identity identity,String save,boolean genuine,int inputMode) {
        if(!root.isAbsolute() || !directory.isAbsolute() || save==null || !save.matches("MineCome-HudStream-[0-9a-f-]{36}"))
            throw new IllegalArgumentException("Invalid owned stream output path/save");
        if(inputMode<0 || inputMode>2)throw new IllegalArgumentException("Invalid input mode");
        this.root=root.normalize();this.directory=directory.normalize();this.identity=identity;this.save=save;this.genuine=genuine;this.inputMode=inputMode;
        groundMovementMode=HudGroundMovementMode.mode(System.getProperties());
        physicalMovement=HudPhysicalMovementMode.require(System.getProperties());
        walkingAimedFixture=physicalMovement && HudPhysicalMovementMode.fixture(System.getProperties())
                && Boolean.getBoolean("minecome.hudWalkingAimedFixture");
        movementSession=HudMovementSession.selected(System.getProperties());
        if(physicalMovement && (!genuine || inputMode!=(HudPhysicalMovementMode.fixture(System.getProperties())?0:1)))
            throw new IllegalArgumentException("Physical movement requires genuine pixels and its exact live or standalone fixture input profile");
        standalone=Boolean.getBoolean("minecome.hudStreamStandalone");
        if(groundMovementMode!=HudGroundMovementMode.Mode.NONE && (!genuine || inputMode!=0))throw new IllegalArgumentException("Ground movement requires genuine standalone HUD pixels");
        liveMouse=Boolean.getBoolean("minecome.hudStreamLiveMouse");HudMousePolicy.enabled(inputMode!=0,inputMode==2,liveMouse);
        inputDelayFixture=inputMode==2 && Boolean.getBoolean("minecome.hudStreamInputDelayFixture");
        inputPointerFixture=inputMode==2 && Boolean.getBoolean("minecome.hudStreamInputPointerFixture");
        stoneBridge=Boolean.getBoolean("minecome.hudStoneBridge");stoneFixture=Boolean.getBoolean("minecome.hudStoneFixture");stoneLive=Boolean.getBoolean("minecome.hudStoneLive");
        aimedStone=Boolean.getBoolean("minecome.hudAimedStoneBridge");
        HudAimedStoneMode.require(aimedStone,stoneBridge,stoneLive,stoneFixture,inputMode!=0,inputMode==2);
        backgroundTrial=inputMode==2 && Boolean.getBoolean("minecome.hudStreamBackgroundTrial");
        offscreenPresentation=inputMode!=0 && Boolean.getBoolean("minecome.hudStreamOffscreenPresentation");
        offscreenTrial=inputMode==2 && Boolean.getBoolean("minecome.hudStreamOffscreenTrial");
        HudStoneMode.require(stoneBridge,stoneFixture,stoneLive,inputMode!=0,inputMode==2,offscreenPresentation,
                Boolean.getBoolean("minecome.hudStreamOffscreenTrial"),Boolean.getBoolean("minecome.hudStreamInputPointerFixture"),
                Boolean.getBoolean("minecome.hudStreamInputDelayFixture"),Boolean.getBoolean("minecome.hudStreamBackgroundTrial"),liveMouse);
    }
    public synchronized void start() {
        if(worker!=null)throw new IllegalStateException("HUD stream cannot restart");
        worker=new Thread(this::run,"MineComeHudStreamWriter");
        // A bounded worker completes its terminal record even after Minecraft's normal shutdown.
        worker.start();
    }
    public boolean isReady(){return ready.get() && failure.get()==null && !finished.get();}
    public void offerWalkingAimState(String stage,JsonObject state){
        if(!HudPhysicalMovementMode.walkingAimed(System.getProperties()) || evidenceWriter==null || !isReady())throw new IllegalStateException("Walking aimed receipt outside active profile");
        if(stage.equals("ready")){if(walkingAimReadyQueued)throw new IllegalStateException("Repeated walking aim ready receipt");walkingAimReadyQueued=true;}
        else if(stage.equals("closed")){if(walkingAimClosedQueued)throw new IllegalStateException("Repeated walking aim closure");walkingAimClosedQueued=true;}
        else throw new IllegalArgumentException("Invalid walking aim evidence stage");
        var receipt=identityReceipt(producerPid,producerStart);
        state.entrySet().forEach(entry->receipt.add(entry.getKey(),entry.getValue().deepCopy()));
        evidenceWriter.submit(directory.resolve("walking-aim-"+stage+".json"),receipt);
    }
    public boolean isFinished(){return finished.get();}
    public String failure(){return failure.get();}
    public long publishedFrames(){return published.get();}
    public int producerPid(){return producerPid;}
    public long producerStart(){return producerStart;}
    public long lastPublishedAt(){return lastPublishedAt;}
    public JsonObject diagnostics(){
        PublicationStage stage=publicationStage;var d=new JsonObject();d.addProperty("stage",stage.name());d.addProperty("stage_age_ms",(System.nanoTime()-stage.at())/1_000_000);d.addProperty("published_frames",published.get());
        d.addProperty("last_published_utc_ms",lastPublishedUtcMs);d.addProperty("last_capture_utc_ms",lastPublishedCaptureUtcMs);d.addProperty("publication_age_ms",lastPublishedAt==0?-1:(System.nanoTime()-lastPublishedAt)/1_000_000);
        d.addProperty("max_publication_gap_ms",maxPublicationGapNanos/1_000_000.0);d.addProperty("max_conversion_ms",maxConversionNanos/1_000_000.0);d.addProperty("max_mapping_write_ms",maxMapWriteNanos/1_000_000.0);d.addProperty("max_published_capture_age_ms",maxPublishedCaptureAgeMs);
        var writer=evidenceWriter;if(writer!=null)d.add("evidence_io",writer.diagnostics());return d;
    }
    private void publicationStage(String value){publicationStage=new PublicationStage(value,System.nanoTime());}
    public void offerFixtureTargets(JsonArray slots){if(inputMode!=2 || !fixtureTargets.compareAndSet(null,slots.deepCopy()))throw new IllegalStateException("Fixture targets not allowed/already queued");}
    public void offerBackgroundTrial(JsonObject evidence){if(!backgroundTrial || !backgroundTrialReceipt.compareAndSet(null,evidence.deepCopy()))throw new IllegalStateException("Background trial not allowed/already queued");}
    public void offerOffscreenTrial(JsonObject evidence){if(!offscreenTrial || !offscreenTrialReceipt.compareAndSet(null,evidence.deepCopy()))throw new IllegalStateException("Offscreen trial not allowed/already queued");}
    public void offerPointerStage(String stage,JsonObject evidence){
        if(!inputPointerFixture || !stage.matches("opened|split|split_restored|picked_up|distributed|scrolled|scroll_restored|closed_held|reopened_held|late_release|complete") || !stage.equals(evidence.get("stage").getAsString()) || !pointerStageReceipt.compareAndSet(null,evidence.deepCopy()))
            throw new IllegalStateException("Pointer stage not allowed/already queued");
    }
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
        if(groundMovementMode!=HudGroundMovementMode.Mode.NONE){
            if(HudGroundMovementMode.extensionDelayFixture(System.getProperties()))r.addProperty("ui_ground_extension_delay_fixture",true);
            if(HudPhysicalMovementMode.wide(System.getProperties()))r.addProperty("walking_area","wide");
            if(groundMovementMode==HudGroundMovementMode.Mode.EXTENSION_COUPLED)r.addProperty("walking_area","extension");
            if(groundMovementMode==HudGroundMovementMode.Mode.CORRIDOR_COUPLED)r.addProperty("walking_area","corridor");
            if(HudGroundMovementMode.corridorWalkOnly(System.getProperties()))r.addProperty("corridor_walk_only",true);
            r.addProperty(groundMovementMode==HudGroundMovementMode.Mode.EXTENSION_COUPLED?"ui_ground_extension_coupled":
                    groundMovementMode==HudGroundMovementMode.Mode.EXTENSION?"ui_ground_extension_fixture":
                    groundMovementMode==HudGroundMovementMode.Mode.CORRIDOR_COUPLED?"ui_ground_corridor_coupled":
                    groundMovementMode==HudGroundMovementMode.Mode.CORRIDOR?"ui_ground_corridor_fixture":
                    groundMovementMode==HudGroundMovementMode.Mode.FIXTURE?"ui_ground_movement_fixture":"ui_ground_movement_coupled",true);
            r.addProperty("standalone",standalone);
        }
        if(physicalMovement){
            if(HudPhysicalMovementMode.wide(System.getProperties()))r.addProperty("walking_area","wide");
            if(HudPhysicalMovementMode.corridor(System.getProperties()))r.addProperty("walking_area","corridor");
            if(HudPhysicalMovementMode.walkingAimed(System.getProperties())){r.addProperty("ui_input_walking_aimed",true);r.addProperty("scripted_input",false);}
            if(movementSession.extended())r.addProperty("movement_session",movementSession.id());
            boolean scripted=HudPhysicalMovementMode.fixture(System.getProperties());
            if(Boolean.getBoolean("minecome.hudWalkingAimedFixture"))r.addProperty("ui_walking_aimed_fixture",true);
            r.addProperty("ui_input_physical_movement",!scripted);
            if(scripted){r.addProperty("ui_physical_controller_fixture",true);r.addProperty("standalone",true);r.addProperty("scripted_input",true);r.addProperty("physical_input_verified",false);}
        }
        if(inputMode!=0){r.addProperty("ui_input_protocol",physicalMovement?2:1);r.addProperty("ui_input_live_mouse",liveMouse);r.addProperty("ui_input_fixture",inputMode==2);r.addProperty("ui_input_delay_fixture",inputDelayFixture);r.addProperty("ui_input_pointer_fixture",inputPointerFixture);r.addProperty("ui_input_stone_bridge",stoneBridge);r.addProperty("ui_input_stone_fixture",stoneFixture);r.addProperty("ui_input_stone_live",stoneLive);r.addProperty("ui_input_aimed_stone_bridge",aimedStone);r.addProperty("ui_input_background_trial",backgroundTrial);r.addProperty("ui_input_offscreen_presentation",offscreenPresentation);r.addProperty("ui_input_offscreen_trial",offscreenTrial);}return r;
    }
    private void run() {
        Kernel32 api=null;WinNT.HANDLE mapping=null,mutex=null;Pointer view=null;
        Path target=null;int pid=0,width=0,height=0,selected=0,screen=0;long start=0,sequence=0,lastCaptured=0,skippedBusy=0,staleDrops=0;
        boolean closed=false,unmapped=false,mappingClosed=false,mutexClosed=false;
        var samples=new JsonArray();var states=new LinkedHashSet<String>();String result="failed";
        var pendingSamples=new ArrayList<Sample>(8);
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
            publicationStage("initial_ready_receipt");writeJson(target.resolve("stream-ready.json"),identityReceipt(pid,start));evidenceWriter=new HudEvidenceWriter(HudStreamProducer::writeJson);ready.set(true);
            while(true) {
                publicationStage("control_mailbox");
                String end=terminal.get();
                if(end!=null){result=end;break;}
                if(evidenceWriter.failure()!=null)throw new IOException("HUD receipt writer: "+evidenceWriter.failure());
                if(System.currentTimeMillis()>=identity.expiresUtcMs() || System.nanoTime()>=deadline)throw new IOException("Immutable stream lease expired");
                var targets=fixtureTargets.getAndSet(null);
                if(targets!=null){var receipt=identityReceipt(pid,start);receipt.add("slots",targets);evidenceWriter.submit(target.resolve("fixture-targets.json"),receipt);}
                var trial=backgroundTrialReceipt.getAndSet(null);
                if(trial!=null){var receipt=identityReceipt(pid,start);receipt.add("background_trial",trial);evidenceWriter.submit(target.resolve("background-trial-ready.json"),receipt);}
                var offscreen=offscreenTrialReceipt.getAndSet(null);
                if(offscreen!=null){var receipt=identityReceipt(pid,start);receipt.add("offscreen_trial",offscreen);evidenceWriter.submit(target.resolve("offscreen-trial-ready.json"),receipt);}
                var pointer=pointerStageReceipt.getAndSet(null);
                if(pointer!=null){var receipt=identityReceipt(pid,start);receipt.add("pointer_fixture",pointer);evidenceWriter.submit(target.resolve("pointer-fixture-"+pointer.get("stage").getAsString()+".json"),receipt);}
                Frame frame=latest.getAndSet(null);
                if(frame==null){publicationStage("awaiting_frame");Thread.sleep(5);continue;}
                long now=System.currentTimeMillis();
                if(frame.capturedUtcMs()>now+250 || frame.capturedUtcMs()<now-1000){staleDrops++;continue;}
                if(width!=0 && (frame.width()!=width || frame.height()!=height))throw new IOException("Stream dimensions changed");
                publicationStage("pixel_conversion");long convertAt=System.nanoTime();byte[] rgba=HudPixels.straightTopLeft(frame.bottomUp(),frame.width(),frame.height());maxConversionNanos=Math.max(maxConversionNanos,System.nanoTime()-convertAt);
                publicationStage("mapping_mutex");
                if(!lock(api,mutex)){skippedBusy++;continue;}
                try {
                    publicationStage("mapping_write");long writeAt=System.nanoTime();
                    width=frame.width();height=frame.height();selected=frame.selectedSlot();screen=frame.screen();lastCaptured=frame.capturedUtcMs();
                    byte[] head=header(identity,pid,start,++sequence,lastCaptured,width,height,selected,screen,1);
                    view.write(HEADER_BYTES,rgba,0,rgba.length);view.write(0,head,0,head.length);
                    maxMapWriteNanos=Math.max(maxMapWriteNanos,System.nanoTime()-writeAt);
                } finally {unlock(api,mutex);}
                published.incrementAndGet();
                long publishedAt=System.nanoTime();if(lastPublishedAt!=0)maxPublicationGapNanos=Math.max(maxPublicationGapNanos,publishedAt-lastPublishedAt);lastPublishedAt=publishedAt;
                lastPublishedUtcMs=System.currentTimeMillis();lastPublishedCaptureUtcMs=frame.capturedUtcMs();maxPublishedCaptureAgeMs=Math.max(maxPublishedCaptureAgeMs,lastPublishedUtcMs-frame.capturedUtcMs());publicationStage("frame_metadata");
                JsonObject meta=JsonParser.parseString(frame.metadata()).getAsJsonObject();String stage=meta.get("state").getAsString();
                if(recordSampleState(states,stage,walkingAimedFixture)) {
                    String name="sample-"+stage+".png";
                    meta.addProperty("width",width);meta.addProperty("height",height);meta.addProperty("sequence",sequence);pendingSamples.add(new Sample(rgba,width,height,meta,name));
                }
            }
            if(result.equals("passed") && (!genuine || published.get()<30 || !states.containsAll(HudPhysicalMovementMode.fixture(System.getProperties())?
                    Set.of("fixture_inventory_blocked","fixture_scripted_walking"):Set.of("hotbar_slot0","hotbar_slot1","inventory_screen","hotbar_slot2"))))
                throw new IOException("Continuous vanilla state proof incomplete");
            if(result.equals("input_passed") || result.equals("input_completed")){
                if(!genuine || inputMode==0 || published.get()<5 || !states.contains("hotbar"))throw new IOException("Input stream vanilla proof incomplete");
                var inputProof=finalEvidence.get();
                if(inputProof==null || !inputProof.get("host_armed").getAsBoolean() ||
                        (inputProof.get("input_events_applied").getAsLong()<=0 && !(stoneLive && (aimedStone?HudAimedStoneProof.hasConfirmedLiveInteraction(inputProof):HudStoneProof.hasConfirmedLiveInteraction(inputProof)))))throw new IOException("Input stream was never armed/applied");
                if(stoneLive){if(aimedStone)HudAimedStoneProof.requireLive(inputProof);else HudStoneProof.requireLive(inputProof);}
                if(result.equals("input_passed")){
                    var proof=finalEvidence.get();
                    if(inputMode!=2 || proof==null)throw new IOException("Input fixture proof absent");
                    for(String key:List.of("input_fixture","inventory_opened","inventory_closed","selected_nine_verified","host_armed"))
                        if(!(stoneFixture && key.equals("selected_nine_verified")) && (!proof.has(key) || !proof.get(key).getAsBoolean()))throw new IOException("Input fixture proof missing: "+key);
                    if(stoneFixture){
                        if(!stoneBridge || inputPointerFixture || !offscreenTrial)throw new IOException("Combined stone fixture mode mismatch");
                        HudStoneProof.require(proof);
                    }else if(inputPointerFixture){
                        var pointer=proof.getAsJsonObject("pointer_evidence");
                        if(!proof.get("pointer_fixture").getAsBoolean() || pointer==null || proof.get("input_events_applied").getAsLong()!=43 || pointer.get("applied_sequence").getAsLong()!=43 || !"complete".equals(pointer.get("stage").getAsString()) || pointer.getAsJsonArray("stages").size()!=11)
                            throw new IOException("Pointer fixture complete phase absent");
                        for(String key:List.of("completed","right_split_verified","drag_distribution_verified","scroll_changed_verified","scroll_restored_verified","held_close_release_verified","reopened_screen_verified","late_release_consumed_verified","cursor_empty","server_inventory_verified"))
                            if(!pointer.has(key) || !pointer.get(key).getAsBoolean())throw new IOException("Pointer fixture proof missing: "+key);
                    }else if(!proof.has("server_swap_verified") || !proof.get("server_swap_verified").getAsBoolean())throw new IOException("Input fixture swap proof absent");
                    if(offscreenTrial){
                        var trial=proof.getAsJsonObject("offscreen_trial");var events=proof.getAsJsonObject("offscreen_trial_events");
                        if(trial==null || !trial.get("completed").getAsBoolean() || events==null || events.get("unfocused_events_applied").getAsLong()!=(stoneFixture?8:inputPointerFixture?43:31) || events.get("focused_events_applied").getAsLong()!=0 || events.get("focus_interruptions").getAsLong()!=0)
                            throw new IOException("Offscreen fixture lacks all expected genuinely unfocused applications");
                    }
                }
            }
        } catch(Exception e) {failure.compareAndSet(null,e.toString());result="failed";}
        finally {
            publicationStage("terminal_closed_publication");
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
            try{
                publicationStage("terminal_evidence_io");
                if(evidenceWriter!=null && (!evidenceWriter.finish(2000) || evidenceWriter.failure()!=null))throw new IOException("HUD receipt writer terminal timeout/failure");
                // These bounded samples are encoded only after the live image channel
                // is closed, so compression/disk latency cannot starve input frames.
                for(var sample:pendingSamples){
                    byte[] png=HudPixels.png(sample.rgba(),sample.width(),sample.height());Files.write(target.resolve(sample.name()),png,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
                    sample.metadata().addProperty("png_file",sample.name());sample.metadata().addProperty("png_sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)));samples.add(sample.metadata());
                }
            }catch(Exception e){failure.compareAndSet(null,e.toString());result="failed";}
            if(target!=null)try {
                var receipt=identityReceipt(pid,start);receipt.addProperty("result",failure.get()==null?result:"failed");receipt.addProperty("published_frames",published.get());
                receipt.addProperty("mailbox_replaced",replaced.get());receipt.addProperty("mutex_busy_skipped",skippedBusy);receipt.addProperty("stale_frames_dropped",staleDrops);
                receipt.addProperty("closed_published",closed);receipt.addProperty("mapping_unmapped",unmapped);receipt.addProperty("mapping_handle_closed",mappingClosed);receipt.addProperty("mutex_handle_closed",mutexClosed);
                var seen=new JsonArray();states.forEach(seen::add);receipt.add("states_seen",seen);receipt.add("samples",samples);
                receipt.addProperty("kcd_compositing_verified",false);if(failure.get()!=null)receipt.addProperty("failure",failure.get());
                receipt.add("publication_timing",diagnostics());
                if(finalEvidence.get()!=null)receipt.add("lab_evidence",finalEvidence.get());writeJson(target.resolve("stream-result.json"),receipt);
            }catch(Exception e){failure.compareAndSet(null,e.toString());}
            finished.set(true);
        }
    }
    /** One retained image per diagnostic phase; combined cleanup is its ninth and final phase. */
    static boolean recordSampleState(Set<String> states,String stage,boolean walkingAimedFixture)throws IOException{
        if(stage==null || !stage.matches("[a-z0-9_]{1,40}"))throw new IOException("Invalid sample state");
        if(walkingAimedFixture && !WALKING_AIMED_SAMPLE_STATES.contains(stage))throw new IOException("Unexpected walking/aimed sample state");
        if(states.contains(stage))return false;
        int limit=walkingAimedFixture?WALKING_AIMED_SAMPLE_STATES.size():8;
        if(states.size()>=limit)throw new IOException("Sample state bound exceeded");
        return states.add(stage);
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
    static void writeJson(Path path,JsonObject object)throws IOException {
        var serializer=new GsonBuilder();
        // Combined evidence retains both vanilla action receipts and movement
        // timing. Compact formatting preserves that proof within the same 64KiB
        // limit; it does not grant a larger transport or evidence budget.
        if((object.has("ui_walking_aimed_fixture") && object.get("ui_walking_aimed_fixture").getAsBoolean())
                || (object.has("ui_input_walking_aimed") && object.get("ui_input_walking_aimed").getAsBoolean()))serializer.serializeNulls();
        else serializer.setPrettyPrinting();
        // Closed pointer phases explicitly carry scroll_position:null; absence
        // means a malformed proof. Preserve that distinction in stage/final files.
        if(object.has("ui_input_pointer_fixture") && object.get("ui_input_pointer_fixture").getAsBoolean())serializer.serializeNulls();
        byte[] body=(serializer.create().toJson(object)+"\n").getBytes(StandardCharsets.UTF_8);
        if(body.length>65536)throw new IOException("Stream receipt byte bound exceeded");
        Path temp=path.resolveSibling(path.getFileName()+"."+UUID.randomUUID()+".tmp");
        Files.write(temp,body,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
        // Same-directory move publishes a complete new receipt; existing destinations are refused.
        Files.move(temp,path);
    }
}
