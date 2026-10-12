package dev.minecome.protocol;

import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.atomic.AtomicLong;

/** Generation tags prevent a late producer offer from leaking into a newer session/world. */
final class BlockEventMailbox {
    record Entry(long session,long world,long reset,Protocol.BlockEvent event) {}
    private final ArrayBlockingQueue<Entry> entries=new ArrayBlockingQueue<>(128);
    private final AtomicLong queued=new AtomicLong(),sent=new AtomicLong(),dropped=new AtomicLong();
    boolean offer(Entry entry) {
        if(!entries.offer(entry)){dropped.incrementAndGet();return false;}
        queued.incrementAndGet();return true;
    }
    Entry poll(long session,long world,long reset) {
        Entry entry;
        for(int i=0;i<128 && (entry=entries.poll())!=null;i++) {
            if(entry.session()==session && entry.world()==world && entry.reset()==reset)return entry;
            dropped.incrementAndGet();
        }
        return null;
    }
    void clear() { for(int i=0;i<128 && entries.poll()!=null;i++)dropped.incrementAndGet(); }
    void rejected() { dropped.incrementAndGet(); }
    void sent() { sent.incrementAndGet(); }
    int pending() { return entries.size(); }
    long queuedCount() { return queued.get(); }
    long sentCount() { return sent.get(); }
    long droppedCount() { return dropped.get(); }
}
