package dev.minecome.hud;

import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Pure, bounded reverse-input wire validation; no native or game calls. */
public final class HudInputProtocol {
    public static final int MAPPING_BYTES=2816, HEADER_BYTES=256, CAPACITY=64, RECORD_BYTES=40;
    public record Identity(String run,int producerPid,long producerStart,int targetPid,long targetStart,long expires) {
        public Identity {
            if(run==null || !run.matches("[0-9a-f]{32}") || producerPid<=0 || producerStart<=0 || targetPid<=0 || targetStart<=0 || expires<=0)
                throw new IllegalArgumentException("Invalid input identity");
        }
        public String mapping(){return "Local\\MineComeHudInput_"+run;}
        public String mutex(){return "Local\\MineComeHudInputLock_"+run;}
    }
    public record Event(long sequence,long capturedUtcMs,int kind,int code,float x,float y,int value) {}
    public record Snapshot(long lastSequence,long heartbeat,int hostState,List<Event> events) {}
    private HudInputProtocol(){}
    public static void validateEvent(Event e,long now,boolean fresh) {
        if(e.sequence()<=0 || e.capturedUtcMs()<=0 || e.kind()<1 || e.kind()>6 || !Float.isFinite(e.x()) || !Float.isFinite(e.y()) || e.x()<0 || e.x()>1 || e.y()<0 || e.y()>1)
            throw new IllegalArgumentException("Invalid input record");
        if(fresh && (e.capturedUtcMs()<now-250 || e.capturedUtcMs()>now+100))throw new IllegalArgumentException("Stale/future input event");
        if(e.kind()<=2) {
            if(!((e.code()>=0x31 && e.code()<=0x39) || e.code()==0x45 || e.code()==0x1b) || e.x()!=0 || e.y()!=0 || e.value()!=0)
                throw new IllegalArgumentException("Invalid input key");
        }else if(e.kind()==3) {
            if(e.code()!=0 || e.value()!=0)throw new IllegalArgumentException("Invalid pointer move");
        }else if(e.kind()==4 || e.kind()==5) {
            if(e.code()<0 || e.code()>1 || e.value()!=0)throw new IllegalArgumentException("Invalid pointer button");
        }else if(e.code()!=0 || e.value()==0 || e.value()< -16 || e.value()>16)throw new IllegalArgumentException("Invalid pointer wheel");
    }
    public static Snapshot decode(byte[] bytes,Identity id,long lastFetched,long now,int previousHostState) {
        if(bytes.length!=MAPPING_BYTES || lastFetched<0 || previousHostState<0 || previousHostState>2 || now<=250 || now>Long.MAX_VALUE-180_000 || now>=id.expires())
            throw new IllegalArgumentException("Invalid input mapping/time/lease");
        var b=ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
        if(!new String(bytes,0,8,StandardCharsets.US_ASCII).equals("MCHUDI01") || b.getInt(8)!=1 || b.getInt(12)!=MAPPING_BYTES ||
                !new String(bytes,16,32,StandardCharsets.US_ASCII).equals(id.run()) || b.getInt(48)!=id.producerPid() || b.getInt(52)!=id.targetPid() ||
                b.getLong(56)!=id.producerStart() || b.getLong(64)!=id.targetStart() || b.getLong(72)!=id.expires())throw new IllegalArgumentException("Input mapping identity differs");
        for(int i=104;i<128;i++)if(bytes[i]!=0)throw new IllegalArgumentException("Nonzero host reserved bytes");
        for(int i=156;i<256;i++)if(bytes[i]!=0)throw new IllegalArgumentException("Nonzero guest reserved bytes");
        long last=b.getLong(80),heartbeat=b.getLong(88);int state=b.getInt(96),retained=b.getInt(100);
        if(last<lastFetched || last<0 || last-lastFetched>CAPACITY || retained!=(int)Math.min(last,CAPACITY) || state<previousHostState || state<0 || state>2 || (state==0 && last!=0))
            throw new IllegalArgumentException("Input state/sequence/overflow differs");
        // Waiting owns no input. A real fresh heartbeat must return before arming,
        // but startup scheduling gaps do not consume the only activation.
        if(heartbeat<=0 || heartbeat>now+100 || (state==1 && heartbeat<now-250))throw new IllegalArgumentException("Stale/future host heartbeat");
        long acknowledged=b.getLong(128),ackTime=b.getLong(136);int guest=b.getInt(144),screen=b.getInt(148),slot=b.getInt(152);
        if(guest<0 || guest>2 || screen<0 || screen>1 || slot<0 || slot>8 || acknowledged<0 || acknowledged>last ||
                (guest==0 && (acknowledged!=0 || ackTime!=0 || screen!=0 || slot!=0)) || (guest!=0 && (ackTime<=0 || ackTime>now+100)))
            throw new IllegalArgumentException("Invalid guest acknowledgement");
        var events=new ArrayList<Event>();
        long first=last-retained+1;
        for(int i=0;i<retained;i++) {
            long seq=first+i;int at=HEADER_BYTES+(int)((seq-1)%CAPACITY)*RECORD_BYTES;
            var event=new Event(b.getLong(at),b.getLong(at+8),b.getInt(at+16),b.getInt(at+20),b.getFloat(at+24),b.getFloat(at+28),b.getInt(at+32));
            if(event.sequence()!=seq || b.getInt(at+36)!=0)throw new IllegalArgumentException("Missing/replaced input sequence or reserved record");
            validateEvent(event,now,state!=2 && seq>lastFetched);
            if(state==1 && seq>lastFetched)events.add(event);
        }
        return new Snapshot(last,heartbeat,state,List.copyOf(events));
    }
}
