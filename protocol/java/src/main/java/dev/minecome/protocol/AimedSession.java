package dev.minecome.protocol;

import java.io.IOException;
import java.util.*;

/** Bounded guest-side minor2 lifecycle. No clocks from the other process are trusted. */
public final class AimedSession {
    public static final long PERMIT_LIFETIME_NANOS=500_000_000L;
    public static final int CAPACITY=16;
    public record Outbound(int type,byte[] payload) {
        public Outbound { payload=payload.clone(); }
        @Override public byte[] payload(){return payload.clone();}
    }
    public record Admitted(Protocol.AimedStoneRequest request,long capturedAtNanos) {}
    private record Permit(long issuedAt,boolean sent) {}
    private final LinkedHashMap<Long,Permit> permits=new LinkedHashMap<>();
    private final ArrayDeque<Outbound> outgoing=new ArrayDeque<>();
    private Protocol.AimedArena arena;
    private byte[] offerBytes;
    private long offeredAt,lastPermitId,lastRequestId;
    private boolean offerSent,ready;
    private Admitted pending,queued;

    public synchronized boolean offer(Protocol.AimedArena offered,long now) {
        if(arena!=null)throw new IllegalStateException("One immutable aimed offer per connection");
        arena=Objects.requireNonNull(offered);offerBytes=Protocol.aimedArena(offered);offeredAt=now;
        enqueue(Protocol.ARENA_OFFER,offerBytes);return true;
    }
    public synchronized void acknowledge(byte[] data) throws IOException {
        Protocol.parseAimedArena(data);
        if(arena==null || !offerSent || ready || !Arrays.equals(offerBytes,data))
            throw new IOException("Unexpected, duplicate or changed aimed alignment acknowledgement");
        ready=true;
    }
    public synchronized boolean ready(){return ready;}
    public synchronized Protocol.AimedArena arena(){return ready?arena:null;}
    public synchronized void checkDeadline(long now) throws IOException {
        if(arena!=null && !ready && (now-offeredAt<0 || now-offeredAt>6_000_000_000L))
            throw new IOException("Aimed alignment acknowledgement timed out");
    }
    public synchronized Protocol.AimPermit issue(long now) {
        if(!ready)return null;
        permits.entrySet().removeIf(e->now-e.getValue().issuedAt<0 || now-e.getValue().issuedAt>PERMIT_LIFETIME_NANOS);
        if(permits.size()>=CAPACITY)return null;
        if(lastPermitId==Protocol.MAX_INPUT_ID)throw new IllegalStateException("Aim permit IDs exhausted");
        var result=new Protocol.AimPermit(arena.arenaId(),++lastPermitId);
        permits.put(result.permitId(),new Permit(now,false));enqueue(Protocol.AIM_PERMIT,Protocol.aimPermit(result));return result;
    }
    /** The permit predates host capture, so its local issue time is a conservative capture timestamp. */
    public synchronized void receive(Protocol.AimedStoneRequest request,long now) throws IOException {
        if(!ready || request.arenaId()!=arena.arenaId())throw new IOException("Aimed request without matching acknowledged arena");
        if(request.requestId()<=lastRequestId)throw new IOException("Replayed or out-of-order aimed request ID");
        lastRequestId=request.requestId();
        if(request.permitId()>lastPermitId)throw new IOException("Unknown future aim permit");
        Permit permit=permits.remove(request.permitId());
        if(permit!=null && !permit.sent)throw new IOException("Aim permit was not written before request capture");
        int refused=0;
        if(permit==null || now-permit.issuedAt<0 || now-permit.issuedAt>PERMIT_LIFETIME_NANOS)refused=Protocol.AIM_STALE;
        else if(pending!=null)refused=Protocol.AIM_BUSY;
        else if(request.occlusion()==Protocol.OCCLUSION_UNAVAILABLE)refused=Protocol.AIM_UNAVAILABLE;
        if(refused!=0)enqueueResult(request,refused);
        else { pending=new Admitted(request,permit.issuedAt);queued=pending; }
    }
    public synchronized Admitted poll(){Admitted result=queued;queued=null;return result;}
    public synchronized boolean complete(Protocol.AimedStoneRequest request,int result) {
        if(pending==null || !pending.request.equals(request))return false;
        enqueueResult(request,result);pending=null;return true;
    }
    public synchronized Outbound pollOutbound(){return outgoing.pollFirst();}
    public synchronized void written(Outbound output) throws IOException {
        if(output.type==Protocol.ARENA_OFFER){
            if(arena==null || offerSent || !Arrays.equals(output.payload,offerBytes))throw new IOException("Changed aimed offer write");
            offerSent=true;
        } else if(output.type==Protocol.AIM_PERMIT){
            var sent=Protocol.parseAimPermit(output.payload);Permit permit=permits.get(sent.permitId());
            if(permit!=null)permits.put(sent.permitId(),new Permit(permit.issuedAt,true));
        }
    }
    public synchronized void clear(){arena=null;offerBytes=null;offerSent=false;ready=false;lastPermitId=lastRequestId=0;pending=queued=null;permits.clear();outgoing.clear();}
    private void enqueueResult(Protocol.AimedStoneRequest request,int result){
        enqueue(Protocol.AIMED_STONE_RESULT,Protocol.aimedStoneResult(new Protocol.AimedStoneResult(request.arenaId(),request.requestId(),request.action(),result)));
    }
    private void enqueue(int type,byte[] payload){
        if(outgoing.size()>=32)throw new IllegalStateException("Aimed output mailbox overflow");
        outgoing.addLast(new Outbound(type,payload));
    }
}
