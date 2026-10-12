package dev.minecome.hud;

import com.sun.jna.Pointer;
import com.sun.jna.platform.win32.*;
import java.nio.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Worker-only Win32 input mapping reader. Every acknowledgement originates on a client tick. */
public final class HudInputReader implements AutoCloseable {
    public record Acknowledgement(long sequence,long utcMs,int state,int screen,int selected) {
        public Acknowledgement {
            if(sequence<0 || utcMs<=0 || state<1 || state>2 || screen<0 || screen>1 || selected<0 || selected>8)throw new IllegalArgumentException("Invalid client acknowledgement");
        }
    }
    private final HudInputProtocol.Identity identity;
    private final ArrayBlockingQueue<HudInputProtocol.Event> queue=new ArrayBlockingQueue<>(64);
    private final AtomicReference<Acknowledgement> acknowledgement=new AtomicReference<>();
    private final AtomicReference<String> reason=new AtomicReference<>();
    private final AtomicBoolean stopping=new AtomicBoolean(),finished=new AtomicBoolean();
    private volatile int hostState;
    private volatile long heartbeat,observedAt;
    private volatile boolean connected;
    private volatile boolean cleanupComplete,closedAcknowledgementPublished;
    private Thread worker;
    public HudInputReader(HudInputProtocol.Identity identity){this.identity=identity;}
    public synchronized void start(){if(worker!=null)throw new IllegalStateException("Input reader cannot restart");worker=new Thread(this::read,"MineComeHudInputReader");worker.start();}
    public HudInputProtocol.Event poll(){return queue.poll();}
    public void acknowledge(Acknowledgement value){acknowledgement.set(value);}
    public int hostState(){return hostState;}
    public boolean connected(){return connected;}
    public long heartbeat(){return heartbeat;}
    public long observedAt(){return observedAt;}
    public String reason(){return reason.get();}
    public boolean isClosed(){return reason.get()!=null || stopping.get();}
    public boolean isFinished(){return finished.get();}
    public boolean cleanupComplete(){return cleanupComplete;}
    public boolean closedAcknowledgementPublished(){return closedAcknowledgementPublished;}
    @Override public void close(){stopping.set(true);}
    private void read(){
        Kernel32 api=Kernel32.INSTANCE;WinNT.HANDLE producer=null,target=null,mapping=null,mutex=null;Pointer view=null;long lastFetched=0;int state=0;
        try {
            long remaining=identity.expires()-System.currentTimeMillis();if(remaining<=0 || remaining>180_000)throw new IllegalStateException("Input initial lease out of bounds");
            long deadline=System.nanoTime()+remaining*1_000_000L;
            producer=api.OpenProcess(WinNT.PROCESS_QUERY_LIMITED_INFORMATION|WinNT.SYNCHRONIZE,false,identity.producerPid());
            target=api.OpenProcess(WinNT.PROCESS_QUERY_LIMITED_INFORMATION|WinNT.SYNCHRONIZE,false,identity.targetPid());
            if(producer==null || target==null || creation(api,producer)!=identity.producerStart() || creation(api,target)!=identity.targetStart())throw new IllegalStateException("Input peer process identity differs");
            long initial=System.nanoTime();
            while(!stopping.get()) {
                long now=System.currentTimeMillis(),mono=System.nanoTime();
                if(now>=identity.expires() || mono>=deadline)throw new IllegalStateException("Input immutable lease expired");
                if(api.WaitForSingleObject(producer,0)!=WinError.WAIT_TIMEOUT || api.WaitForSingleObject(target,0)!=WinError.WAIT_TIMEOUT)throw new IllegalStateException("Input peer exited");
                if(mapping==null) {
                    mapping=api.OpenFileMapping(WinNT.FILE_MAP_ALL_ACCESS,false,identity.mapping());
                    if(mapping==null){if(mono-initial>60_000_000_000L)throw new IllegalStateException("Input mapping 60s readiness timeout");Thread.sleep(5);continue;}
                    mutex=api.OpenMutex(WinNT.SYNCHRONIZE|WinNT.MUTEX_MODIFY_STATE,false,identity.mutex());
                    if(mutex==null){
                        int error=api.GetLastError();
                        if(error!=WinError.ERROR_FILE_NOT_FOUND)throw new IllegalStateException("Input mutex unavailable: "+error);
                        if(!api.CloseHandle(mapping))throw new IllegalStateException("Input startup mapping handle close failed");mapping=null;
                        if(mono-initial>60_000_000_000L)throw new IllegalStateException("Input mutex 60s readiness timeout");
                        Thread.sleep(5);continue;
                    }
                    view=api.MapViewOfFile(mapping,WinNT.FILE_MAP_ALL_ACCESS,0,0,HudInputProtocol.MAPPING_BYTES);
                    if(view==null)throw new IllegalStateException("Input mapping view unavailable");
                }
                if(!lock(api,mutex)){Thread.sleep(2);continue;}
                byte[] bytes;try {bytes=view.getByteArray(0,HudInputProtocol.MAPPING_BYTES);}finally{unlock(api,mutex);}
                var snapshot=HudInputProtocol.decode(bytes,identity,lastFetched,now,state);state=snapshot.hostState();
                heartbeat=snapshot.heartbeat();observedAt=mono;hostState=state;connected=true;
                if(state==2){reason.compareAndSet(null,"host_closed");break;}
                for(var event:snapshot.events())if(!queue.offer(event))throw new IllegalStateException("Input client mailbox overflow");
                lastFetched=snapshot.lastSequence();
                var ack=acknowledgement.get();
                if(ack!=null){
                    if(now-ack.utcMs()>250)throw new IllegalStateException("Client tick acknowledgement stale");
                    if(ack.sequence()>lastFetched)throw new IllegalStateException("Client acknowledgement exceeds host sequence");
                    if(lock(api,mutex))try{writeAck(view,ack);}finally{unlock(api,mutex);}
                }
                Thread.sleep(5);
            }
        }catch(Exception e){reason.compareAndSet(null,e.toString());}
        finally {
            if(reason.get()==null)reason.set("guest_closed");queue.clear();
            // Give the client a bounded opportunity to release real controls and supply
            // its own closed acknowledgement. Never manufacture a client timestamp.
            long waitUntil=System.nanoTime()+250_000_000L;
            while(acknowledgement.get()!=null && acknowledgement.get().state()!=2 && System.nanoTime()<waitUntil)try{Thread.sleep(5);}catch(InterruptedException ignored){break;}
            var ack=acknowledgement.get();
            if(view!=null && mutex!=null && ack!=null && ack.state()==2 && ack.sequence()<=lastFetched)try{if(lock(api,mutex))try{writeAck(view,ack);closedAcknowledgementPublished=true;}finally{unlock(api,mutex);}}catch(Exception ignored){}
            boolean unmap=view==null || api.UnmapViewOfFile(view),closeMutex=mutex==null || api.CloseHandle(mutex),closeMap=mapping==null || api.CloseHandle(mapping);
            boolean closeTarget=target==null || api.CloseHandle(target),closeProducer=producer==null || api.CloseHandle(producer);
            cleanupComplete=unmap && closeMutex && closeMap && closeTarget && closeProducer;
            finished.set(true);
        }
    }
    private static long creation(Kernel32 api,WinNT.HANDLE process){
        var time=new WinBase.FILETIME();if(!api.GetProcessTimes(process,time,new WinBase.FILETIME(),new WinBase.FILETIME(),new WinBase.FILETIME()))throw new IllegalStateException("Input GetProcessTimes failed");
        return (Integer.toUnsignedLong(time.dwHighDateTime)<<32)|Integer.toUnsignedLong(time.dwLowDateTime);
    }
    private static boolean lock(Kernel32 api,WinNT.HANDLE mutex){int result=api.WaitForSingleObject(mutex,5);if(result==WinBase.WAIT_OBJECT_0)return true;if(result==WinError.WAIT_TIMEOUT)return false;if(result==WinBase.WAIT_ABANDONED)api.ReleaseMutex(mutex);throw new IllegalStateException("Input mutex failed/abandoned: "+result);}
    private static void unlock(Kernel32 api,WinNT.HANDLE mutex){if(!api.ReleaseMutex(mutex))throw new IllegalStateException("Input mutex release failed");}
    private static void writeAck(Pointer view,Acknowledgement ack){var bytes=ByteBuffer.allocate(128).order(ByteOrder.LITTLE_ENDIAN).putLong(ack.sequence()).putLong(ack.utcMs()).putInt(ack.state()).putInt(ack.screen()).putInt(ack.selected()).array();view.write(128,bytes,0,bytes.length);}
}
