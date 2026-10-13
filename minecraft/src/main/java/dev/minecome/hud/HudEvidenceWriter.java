package dev.minecome.hud;

import com.google.gson.JsonObject;
import java.io.IOException;
import java.nio.file.Path;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

/** Bounded cold-path receipt I/O; never owns the image mapping or a game API. */
final class HudEvidenceWriter {
    @FunctionalInterface interface Writer { void write(Path path,JsonObject body)throws IOException; }
    private record Request(Path path,JsonObject body){}
    private record Stage(String name,long at){}
    private final ArrayBlockingQueue<Request> pending=new ArrayBlockingQueue<>(4);
    private final AtomicReference<String> failure=new AtomicReference<>();
    private final Writer sink;
    private final Thread worker;
    private volatile boolean stopping;
    private volatile Stage stage=new Stage("waiting",System.nanoTime());
    private volatile long submitted,completed,maxWriteNanos;
    HudEvidenceWriter(Writer sink){this.sink=sink;worker=new Thread(this::run,"MineComeHudEvidenceWriter");worker.setDaemon(true);worker.start();}
    void submit(Path path,JsonObject body){
        if(stopping || failure.get()!=null || !pending.offer(new Request(path,body.deepCopy())))throw new IllegalStateException("HUD receipt queue closed/full/failed");submitted++;
    }
    String failure(){return failure.get();}
    boolean finish(long timeoutMs)throws InterruptedException {if(timeoutMs<1 || timeoutMs>2000)throw new IllegalArgumentException("Bounded receipt join required");stopping=true;worker.join(timeoutMs);return !worker.isAlive();}
    JsonObject diagnostics(){Stage observed=stage;var value=new JsonObject();value.addProperty("submitted",submitted);value.addProperty("completed",completed);value.addProperty("queued",pending.size());value.addProperty("stage",observed.name());value.addProperty("stage_age_ms",(System.nanoTime()-observed.at())/1_000_000);value.addProperty("max_write_ms",maxWriteNanos/1_000_000.0);value.addProperty("stopped",!worker.isAlive());if(failure.get()!=null)value.addProperty("failure",failure.get());return value;}
    private void run(){
        try{
            while(!stopping || !pending.isEmpty()){
                Request request=pending.poll(50,TimeUnit.MILLISECONDS);if(request==null)continue;
                long began=System.nanoTime();stage=new Stage(request.path().getFileName().toString(),began);
                sink.write(request.path(),request.body());maxWriteNanos=Math.max(maxWriteNanos,System.nanoTime()-began);completed++;
                stage=new Stage("waiting",System.nanoTime());
            }
        }catch(Exception e){failure.compareAndSet(null,e.toString());}
        finally{stage=new Stage("stopped",System.nanoTime());}
    }
}
