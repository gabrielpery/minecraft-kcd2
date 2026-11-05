package dev.minecome.gameplay;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;

/** Constant-space latest server snapshot; all ongoing disk work stays off game threads. */
final class GameplayBlocksFiles {
    private record Frame(long revision,Set<GameplayBlocksLedger.Cell> cells,String json){}
    private final GameplayBlocksLedger ledger;private final Path output;
    private final AtomicReference<Frame> latest=new AtomicReference<>();
    private volatile boolean closing,finished;private volatile String failure;private volatile long writes,persistedRevision;
    GameplayBlocksFiles(Path root,Path evidence,GameplayBlocksLedger ledger)throws IOException {
        this.ledger=ledger;var directory=evidence.toRealPath();if(!directory.startsWith(root.toRealPath().resolve("runtime/evidence")))throw new IOException("Block output outside evidence");
        output=directory.resolve("gameplay-blocks.json");if(Files.exists(output))throw new IOException("Block output already exists");persistedRevision=ledger.initialRevision;
        var worker=new Thread(this::run,"MineComeGameplayBlocksFiles");worker.setDaemon(true);worker.start();
    }
    void publish(long revision,Set<GameplayBlocksLedger.Cell> cells,String json){if(json.length()>GameplayBlocksLedger.MAX_BYTES)throw new IllegalArgumentException("Block snapshot too large");latest.set(new Frame(revision,Set.copyOf(cells),json));}
    void close(){closing=true;}boolean finished(){return finished;}String failure(){return failure;}long writes(){return writes;}long persistedRevision(){return persistedRevision;}
    static void atomic(Path path,String json)throws IOException,InterruptedException {
        var temp=path.resolveSibling(path.getFileName()+".tmp");Files.writeString(temp,json,StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
        long start=System.nanoTime();while(true){try{Files.move(temp,path,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);return;}
            catch(AccessDeniedException error){if(System.nanoTime()-start>=100_000_000L)throw error;Thread.sleep(5);}}
    }
    private void run(){try{while(true){var frame=latest.getAndSet(null);if(frame!=null){
        if(frame.revision()!=persistedRevision){ledger.persist(frame.revision(),frame.cells());persistedRevision=frame.revision();}
        atomic(output,frame.json());writes++;
    }if(closing&&latest.get()==null)break;Thread.sleep(10);}}catch(Exception error){failure=error.toString();}finally{finished=true;}}
}
