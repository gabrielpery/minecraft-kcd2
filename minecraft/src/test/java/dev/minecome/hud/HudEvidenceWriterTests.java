package dev.minecome.hud;

import com.google.gson.JsonObject;
import java.io.IOException;
import java.nio.file.Path;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** A deliberately blocked evidence sink must not block the publication caller. */
public final class HudEvidenceWriterTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void rejected(Runnable action){boolean rejected=false;try{action.run();}catch(IllegalStateException expected){rejected=true;}check(rejected,"queue must reject");}
    public static void main(String[] args)throws Exception{
        var entered=new CountDownLatch(1);var release=new CountDownLatch(1);var thread=new AtomicReference<Thread>();var firstValue=new AtomicInteger(-1);
        var writer=new HudEvidenceWriter((path,body)->{
            thread.set(Thread.currentThread());entered.countDown();
            try{if(!release.await(5,TimeUnit.SECONDS))throw new IOException("test release timeout");}catch(InterruptedException e){throw new IOException(e);}
            firstValue.compareAndSet(-1,body.get("value").getAsInt());
        });
        try{
            var original=new JsonObject();original.addProperty("value",7);writer.submit(Path.of("first.json"),original);
            check(entered.await(5,TimeUnit.SECONDS),"sink entered");original.addProperty("value",99);
            check(thread.get()!=Thread.currentThread(),"evidence I/O has its own thread");
            for(int i=0;i<4;i++)writer.submit(Path.of("queued-"+i+".json"),original);
            check(writer.diagnostics().get("queued").getAsInt()==4,"bounded queue remains writable while sink blocked");
            rejected(()->writer.submit(Path.of("overflow.json"),original));
            check(writer.diagnostics().get("completed").getAsLong()==0,"sink still blocked while caller progresses");
            check(!writer.finish(1),"blocked sink has a bounded unsuccessful join");
            release.countDown();check(writer.finish(2000),"bounded writer stops after drain");
            check(writer.failure()==null,"successful I/O has no failure");check(firstValue.get()==7,"receipt ownership copied before caller mutation");
            check(writer.diagnostics().get("completed").getAsLong()==5,"all accepted receipts drained");check(writer.diagnostics().get("stopped").getAsBoolean(),"thread stopped");
            rejected(()->writer.submit(Path.of("closed.json"),original));
        }finally{release.countDown();writer.finish(2000);}
        var failed=new HudEvidenceWriter((path,body)->{throw new IOException("controlled evidence failure");});
        failed.submit(Path.of("failed.json"),new JsonObject());check(failed.finish(2000),"failed sink stops");
        check(failed.failure()!=null && failed.failure().contains("controlled evidence failure"),"I/O failure observable to publisher");
        rejected(()->failed.submit(Path.of("after-failure.json"),new JsonObject()));
        System.out.println("HudEvidenceWriterTests: "+checks+" checks passed; blocked I/O isolation and bounded lifecycle; no games launched.");
    }
}
