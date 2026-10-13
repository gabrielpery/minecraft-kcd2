package dev.minecome.hud;

import com.google.gson.*;
import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Files;
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
        pointerNullReceipts();
        System.out.println("HudEvidenceWriterTests: "+checks+" checks passed; blocked I/O isolation and bounded lifecycle; no games launched.");
    }
    private static void pointerNullReceipts()throws Exception{
        Path directory=Files.createTempDirectory("minecome-pointer-receipt-");
        Path closed=directory.resolve("pointer-fixture-closed_held.json"),complete=directory.resolve("stream-result.json"),open=directory.resolve("pointer-fixture-opened.json"),ordinary=directory.resolve("ordinary.json");
        var actual=new HudEvidenceWriter(HudStreamProducer::writeJson);
        try{
            var phase=new JsonObject();phase.addProperty("stage","closed_held");phase.addProperty("inventory_open",false);phase.add("scroll_position",JsonNull.INSTANCE);
            var receipt=new JsonObject();receipt.addProperty("ui_input_pointer_fixture",true);receipt.add("pointer_fixture",phase);actual.submit(closed,receipt);
            var terminal=new JsonObject();terminal.addProperty("ui_input_pointer_fixture",true);var lab=new JsonObject();lab.add("pointer_evidence",phase.deepCopy());terminal.add("lab_evidence",lab);actual.submit(complete,terminal);
            var opened=receipt.deepCopy();opened.getAsJsonObject("pointer_fixture").addProperty("scroll_position",0.25);actual.submit(open,opened);
            var normal=receipt.deepCopy();normal.addProperty("ui_input_pointer_fixture",false);actual.submit(ordinary,normal);
            check(actual.finish(2000) && actual.failure()==null,"production receipt writer drains real serialized files");
            var saved=JsonParser.parseString(Files.readString(closed)).getAsJsonObject().getAsJsonObject("pointer_fixture");
            check(saved.has("scroll_position") && saved.get("scroll_position").isJsonNull(),"closed pointer receipt preserves required explicit null on disk");
            var finalPhase=JsonParser.parseString(Files.readString(complete)).getAsJsonObject().getAsJsonObject("lab_evidence").getAsJsonObject("pointer_evidence");
            check(finalPhase.has("scroll_position") && finalPhase.get("scroll_position").isJsonNull(),"nested terminal pointer proof preserves required null");
            check(JsonParser.parseString(Files.readString(open)).getAsJsonObject().getAsJsonObject("pointer_fixture").get("scroll_position").getAsDouble()==0.25,"open pointer receipt keeps numeric scroll position");
            check(!JsonParser.parseString(Files.readString(ordinary)).getAsJsonObject().getAsJsonObject("pointer_fixture").has("scroll_position"),"ordinary mode serialization is unchanged");
        }finally{actual.finish(2000);try(var files=Files.list(directory)){for(Path path:files.toList())Files.delete(path);}Files.delete(directory);}
    }
}
