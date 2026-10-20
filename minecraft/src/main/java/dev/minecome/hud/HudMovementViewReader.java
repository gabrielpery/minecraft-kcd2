package dev.minecome.hud;

import com.google.gson.JsonObject;
import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.Arrays;

/** File reads stay off the game thread; repeated bytes cannot refresh a camera lease. */
public final class HudMovementViewReader implements AutoCloseable {
    public record Sample(HudMovementView view,long deadlineNs,long observedUtcMs,long observedAtNs,long publishedAtNs){}
    public record Inspection(Sample current,JsonObject diagnostics){}
    static final long READ_RETRY_NS=100_000_000L;
    static final long POLL_MS=5;
    @FunctionalInterface interface FileReader {byte[] read(Path path)throws IOException;}
    private final Path file;private final HudInputProtocol.Identity identity;private final String patchRun,patchHash;
    private final FileReader fileReader;
    private volatile Sample sample;private volatile String failure;private volatile boolean closing;private Thread worker;
    // Diagnostic snapshots never participate in freshness/authority decisions.
    private volatile Sample lastAccepted;
    private volatile String stage="not_started",lastIoError="";
    private volatile long stageAtNs=System.nanoTime(),lastPollNs,maxPollGapNs,readAttempts,ioFaults,lastReadUtcMs,lastReadNs,lastReadDurationNs,maxReadDurationNs;
    public HudMovementViewReader(Path file,Path evidenceRoot,HudInputProtocol.Identity identity,String patchRun,String patchHash)throws IOException{
        this(file,evidenceRoot,identity,patchRun,patchHash,HudMovementViewReader::readFile);
    }
    HudMovementViewReader(Path file,Path evidenceRoot,HudInputProtocol.Identity identity,String patchRun,String patchHash,FileReader fileReader)throws IOException{
        if(!file.isAbsolute() || !file.normalize().getParent().toRealPath().startsWith(evidenceRoot.toRealPath()))
            throw new IOException("Camera file escapes owned evidence");
        this.file=file.normalize();this.identity=identity;this.patchRun=patchRun;this.patchHash=patchHash;this.fileReader=fileReader;
    }
    public void start(){if(worker!=null)throw new IllegalStateException("Camera reader already started");worker=new Thread(this::run,"MineComeHudMovementView");worker.setDaemon(true);worker.start();}
    public Sample current(long utc,long now){Sample value=sample;return value!=null && now<value.deadlineNs() && value.view().fresh(utc)?value:null;}
    public String failure(){return failure;}
    public JsonObject diagnostics(long utc,long now){
        return inspect(utc,now).diagnostics();
    }
    /** The rejection and its sample metadata use one immutable snapshot. */
    public Inspection inspect(long utc,long now){
        Sample active=sample;
        boolean available=active!=null && now<active.deadlineNs() && active.view().fresh(utc);
        return new Inspection(available?active:null,diagnostics(utc,now,active!=null?active:lastAccepted,available));
    }
    private JsonObject diagnostics(long utc,long now,Sample value,boolean available){
        var e=new JsonObject();
        e.addProperty("captured_utc_ms",utc);e.addProperty("monotonic_ns",now);e.addProperty("poll_interval_ms",POLL_MS);
        e.addProperty("source_max_age_ms",HudMovementView.MAX_AGE_MS);e.addProperty("read_retry_limit_ms",READ_RETRY_NS/1_000_000);
        e.addProperty("stage",stage);e.addProperty("stage_age_ms",(now-stageAtNs)/1_000_000.0);
        e.addProperty("worker_alive",worker!=null&&worker.isAlive());e.addProperty("closing",closing);e.addProperty("failure",failure);
        e.addProperty("read_attempts",readAttempts);e.addProperty("io_faults",ioFaults);e.addProperty("last_io_error",lastIoError);
        e.addProperty("last_poll_age_ms",lastPollNs==0?-1:(now-lastPollNs)/1_000_000.0);e.addProperty("max_poll_gap_ms",maxPollGapNs/1_000_000.0);
        e.addProperty("last_read_utc_ms",lastReadUtcMs);e.addProperty("last_read_age_ms",lastReadNs==0?-1:(now-lastReadNs)/1_000_000.0);
        e.addProperty("last_read_duration_ms",lastReadDurationNs/1_000_000.0);e.addProperty("max_read_duration_ms",maxReadDurationNs/1_000_000.0);
        e.addProperty("active_sample_available",available);
        if(value!=null){
            e.addProperty("sample_sequence",value.view().sequence());e.addProperty("source_utc_ms",value.view().utcMs());
            e.addProperty("source_age_ms",utc-value.view().utcMs());e.addProperty("observed_utc_ms",value.observedUtcMs());
            e.addProperty("observed_source_age_ms",value.observedUtcMs()-value.view().utcMs());
            e.addProperty("observed_monotonic_ns",value.observedAtNs());e.addProperty("published_monotonic_ns",value.publishedAtNs());
            e.addProperty("parse_publish_duration_ms",(value.publishedAtNs()-value.observedAtNs())/1_000_000.0);
            e.addProperty("sample_deadline_ns",value.deadlineNs());e.addProperty("remaining_lease_ms",(value.deadlineNs()-now)/1_000_000.0);
        }
        return e;
    }
    private void stage(String value){stageAtNs=System.nanoTime();stage=value;}
    private void run(){
        byte[] previous=null;long sequence=0,lastUtc=0,readFailedAt=-1;
        try{
            while(!closing){
                long poll=System.nanoTime();if(lastPollNs!=0)maxPollGapNs=Math.max(maxPollGapNs,poll-lastPollNs);lastPollNs=poll;
                byte[] bytes=null;
                try{
                    stage("reading");readAttempts++;
                    bytes=fileReader.read(file);readFailedAt=-1;
                    lastReadNs=System.nanoTime();lastReadUtcMs=System.currentTimeMillis();lastReadDurationNs=lastReadNs-poll;
                    maxReadDurationNs=Math.max(maxReadDurationNs,lastReadDurationNs);
                }catch(FileSystemException e){
                    ioFaults++;lastIoError=e.toString();stage("retrying_filesystem");
                    // Windows atomic replacement can briefly deny read sharing.
                    // Retry only I/O, never parsing/identity, and never republish
                    // the previous sample or change its original source deadline.
                    if(!(e instanceof NoSuchFileException && previous==null)){
                        long now=System.nanoTime();
                        if(readFailedAt<0)readFailedAt=now;
                        if(now<readFailedAt || now-readFailedAt>=READ_RETRY_NS)
                            throw new IOException("Camera filesystem read retry deadline",e);
                    }
                }
                if(bytes!=null){
                    if(!Arrays.equals(previous,bytes)){
                        stage("parsing");
                        long utc=System.currentTimeMillis(),now=System.nanoTime();
                        var view=HudMovementView.parse(bytes,identity,patchRun,patchHash,utc);
                        if(view.sequence()<=sequence || view.utcMs()<lastUtc)throw new IOException("Camera snapshot sequence/time regressed or replaced");
                        sequence=view.sequence();lastUtc=view.utcMs();previous=bytes;
                        long remaining=Math.max(0,HudMovementView.MAX_AGE_MS-Math.max(0,utc-view.utcMs()));
                        var accepted=new Sample(view,now+remaining*1_000_000L,utc,now,System.nanoTime());
                        lastAccepted=accepted;sample=accepted;
                    }
                }
                stage("waiting");Thread.sleep(POLL_MS);
            }
        }catch(InterruptedException e){if(!closing){Thread.currentThread().interrupt();failure="Camera reader interrupted";}}
        catch(Exception e){failure=e.toString();}
        finally{sample=null;stage("stopped");}
    }
    private static byte[] readFile(Path file)throws IOException{
        var attributes=Files.readAttributes(file,BasicFileAttributes.class,LinkOption.NOFOLLOW_LINKS);
        if(attributes.isSymbolicLink() || !attributes.isRegularFile())throw new IOException("Invalid camera file");
        try(var in=Files.newInputStream(file)){return in.readNBytes(HudMovementView.MAX_BYTES+1);}
    }
    @Override public void close(){closing=true;sample=null;if(worker!=null)worker.interrupt();}
}
