package dev.minecome.protocol;

import java.util.concurrent.ArrayBlockingQueue;

/** Generation filtering also covers an offer racing a disconnect/clear. */
final class StoneInputMailbox {
    static final int CAPACITY=16;
    record ResultEntry(BridgeClient.InputEnvelope envelope,Protocol.StoneInputResult result) {}
    private final ArrayBlockingQueue<BridgeClient.InputEnvelope> requests=new ArrayBlockingQueue<>(CAPACITY);
    private final ArrayBlockingQueue<ResultEntry> results=new ArrayBlockingQueue<>(CAPACITY);
    boolean offer(BridgeClient.InputEnvelope envelope){return requests.offer(envelope);}
    boolean offerResult(ResultEntry entry){return results.offer(entry);}
    BridgeClient.InputEnvelope poll(long session,long world,long reset) {
        BridgeClient.InputEnvelope e;
        while((e=requests.poll())!=null)if(matches(e,session,world,reset))return e;
        return null;
    }
    ResultEntry pollResult(long session,long world,long reset) {
        ResultEntry e;
        while((e=results.poll())!=null)if(matches(e.envelope(),session,world,reset))return e;
        return null;
    }
    static boolean matches(BridgeClient.InputEnvelope e,long session,long world,long reset) {
        return e.session()==session && e.world()==world && e.reset()==reset;
    }
    void clear(){requests.clear();results.clear();}
}
