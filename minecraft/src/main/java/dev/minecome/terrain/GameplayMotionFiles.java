package dev.minecome.terrain;

import com.google.gson.JsonObject;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.concurrent.atomic.AtomicReference;

/** Constant-space latest observations; no disk operations in ongoing game callbacks. */
final class GameplayMotionFiles {
    private final Path directory,pose;
    private final GameplayTerrainBinding binding;
    private final AtomicReference<String> latest=new AtomicReference<>(),ready=new AtomicReference<>();
    private volatile boolean closing,finished;
    private volatile String failure;
    private volatile GameplayTerrainBinding.Position checkpoint;
    private Thread worker;private long writes;
    GameplayMotionFiles(Path root,Path directory,GameplayTerrainBinding binding)throws IOException{
        this.directory=directory.toRealPath();
        if(!this.directory.startsWith(root.toRealPath().resolve("runtime/evidence")))throw new IOException("Movement files must stay in owned evidence");
        pose=this.directory.resolve("gameplay-pose.json");this.binding=binding;
        if(Files.exists(pose)||Files.exists(this.directory.resolve("gameplay-movement-ready.json")))throw new IOException("Movement output already exists");
    }
    void start(){worker=new Thread(this::run,"MineComeGameplayMotionFiles");worker.setDaemon(true);worker.start();}
    void pose(JsonObject json){String text=json.toString();int bound=Boolean.getBoolean("minecome.gameplayWorldBlocks")?20480:4096;if(text.length()>bound)throw new IllegalArgumentException("Pose bound");latest.set(text);}
    void ready(JsonObject json){ready.compareAndSet(null,json.toString());}
    void close(GameplayTerrainBinding.Position position){checkpoint=position;closing=true;}
    boolean finished(){return finished;}
    String failure(){return failure;}
    long writes(){return writes;}
    private boolean write(Path destination,String text)throws IOException,InterruptedException{
        Path temp=directory.resolve(destination.getFileName()+".tmp");
        Files.writeString(temp,text,StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
        long started=System.nanoTime();
        while(true){
            try{Files.move(temp,destination,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);return true;}
            catch(AccessDeniedException denied){
                long elapsed=System.nanoTime()-started;
                if(elapsed<0||elapsed>=100_000_000L)return false;
                // Only this file worker waits. Never refresh captured UTC or
                // sequence while retrying the same already-serialized bytes.
                Thread.sleep(5);
            }
        }
    }
    private void run(){
        try{
            while(true){
                String signal=ready.getAndSet(null);if(signal!=null&&!write(directory.resolve("gameplay-movement-ready.json"),signal))ready.compareAndSet(null,signal);
                String value=latest.getAndSet(null);if(value!=null){if(write(pose,value))writes++;else latest.compareAndSet(null,value);}
                if(closing){if(checkpoint!=null)binding.checkpoint(checkpoint);break;}
                Thread.sleep(10);
            }
        }catch(Exception e){failure=e.toString();}finally{finished=true;}
    }
}
