package dev.minecome.hud;

import java.io.IOException;
import java.nio.file.*;

/** Fixture-only atomic replacement; a transient Windows reader cannot retimestamp a sample. */
final class HudFixtureCameraFiles {
    static final long RETRY_NS=100_000_000L;
    private HudFixtureCameraFiles(){}
    static void replace(Path temporary,Path target)throws IOException,InterruptedException{
        long started=System.nanoTime();
        while(true){
            try{
                Files.move(temporary,target,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
                return;
            }catch(AccessDeniedException denied){
                long elapsed=System.nanoTime()-started;
                if(elapsed<0 || elapsed>=RETRY_NS)throw new IOException("Fixture camera atomic replacement denied for100ms",denied);
                // Retry the exact already-written bytes. Sequence/source UTC and
                // reader300ms lease stay unchanged throughout this bounded wait.
                Thread.sleep(5);
            }
        }
    }
}
