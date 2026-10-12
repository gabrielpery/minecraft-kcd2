package dev.minecome.protocol;

import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Socket ownership belongs exclusively to this daemon; immutable mailboxes cross threads. */
public final class BridgeClient implements AutoCloseable {
    private final Path tokenFile;
    private final String name;
    private final int role;
    private final int port;
    private final int minor,capabilities;
    private final Consumer<String> diagnostics;
    private final AtomicReference<Protocol.Pose> latestOutgoing = new AtomicReference<>();
    private record HostSnapshot(Protocol.Pose pose,long receivedAtNanos,long world,long reset) {}
    private final AtomicReference<HostSnapshot> latestIncoming = new AtomicReference<>();
    private final BlockEventMailbox events = new BlockEventMailbox();
    private final StoneInputMailbox inputs=new StoneInputMailbox();
    private final AtomicLong receivedPoses = new AtomicLong();
    private final AtomicLong sessionGeneration=new AtomicLong(),worldGeneration=new AtomicLong(),resetGeneration=new AtomicLong();
    private volatile long activeWorldGeneration,activeResetGeneration;
    public record Status(boolean connected,long session,long world,int pendingEvents,long queuedEvents,long sentEvents,long droppedEvents,long resets,long receivedPoses) {}
    public record SentBlockEvent(Protocol.BlockEvent event,long sequence,long session) {}
    public record InputEnvelope(Protocol.StoneInputRequest request,long session,long world,long reset,long receivedAtNanos) {}
    private final AtomicReference<SentBlockEvent> lastSentBlockEvent=new AtomicReference<>();
    private volatile boolean running, connected;
    private volatile Socket currentSocket;
    private Thread worker;
    public BridgeClient(Path tokenFile, String name, int role, Consumer<String> diagnostics) {
        this(tokenFile,name,role,diagnostics,false);
    }
    public BridgeClient(Path tokenFile,String name,int role,Consumer<String> diagnostics,boolean interactiveStone) {
        this.tokenFile=tokenFile; this.name=name; this.role=role; this.diagnostics=diagnostics;
        if (role!=Protocol.ROLE_MC && role!=Protocol.ROLE_HARNESS) throw new IllegalArgumentException("Client role must be Minecraft or Harness");
        if(interactiveStone && role!=Protocol.ROLE_MC)throw new IllegalArgumentException("Stone input requires the real Minecraft role");
        this.minor=interactiveStone?1:0;this.capabilities=interactiveStone?Protocol.CAP_STONE_INPUT:0;
        Protocol.hello(new Protocol.Hello(role,capabilities,name,""));
        this.port=Integer.getInteger("minecome.port",Protocol.PORT);
        if (port<1 || port>65535) throw new IllegalArgumentException("minecome.port must be 1..65535");
    }
    public synchronized void start() {
        if (running) return;
        running=true; worker=new Thread(this::run,"MineCome-local-bridge"); worker.setDaemon(true); worker.start();
    }
    public boolean connected() { return connected && activeWorldGeneration==worldGeneration.get() && activeResetGeneration==resetGeneration.get(); }
    public Status status() {
        return new Status(connected(),sessionGeneration.get(),worldGeneration.get(),events.pending(),events.queuedCount(),
                events.sentCount(),events.droppedCount(),resetGeneration.get(),receivedPoses.get());
    }
    /** A successful socket write is diagnostic evidence, not an acknowledgement from the host/sink. */
    public SentBlockEvent lastSentBlockEvent() { return lastSentBlockEvent.get(); }
    public long receivedPoses() { return receivedPoses.get(); }
    public boolean supportsStoneInput(){return minor==1 && connected();}
    public InputEnvelope pollStoneInputRequest(){return inputs.poll(sessionGeneration.get(),worldGeneration.get(),resetGeneration.get());}
    /** Runs on the client tick. Zero means the request may proceed to the lab's vanilla checks. */
    public int stoneInputAvailability(InputEnvelope envelope) {
        if(!supportsStoneInput() || !StoneInputMailbox.matches(envelope,sessionGeneration.get(),worldGeneration.get(),resetGeneration.get()))
            return Protocol.INPUT_UNAVAILABLE;
        long age=System.nanoTime()-envelope.receivedAtNanos();
        if(age<0 || age>TimeUnit.SECONDS.toNanos(1))return Protocol.INPUT_STALE;
        Protocol.Pose pose=latestHostPose();
        return pose!=null && (pose.flags()&(Protocol.HAS_PLAYER|Protocol.HAS_CAMERA))==3?0:Protocol.INPUT_UNAVAILABLE;
    }
    public boolean sendStoneInputResult(InputEnvelope envelope,int result) {
        var request=envelope.request();
        var entry=new StoneInputMailbox.ResultEntry(envelope,new Protocol.StoneInputResult(request.requestId(),request.action(),result));
        if(!supportsStoneInput() || !StoneInputMailbox.matches(envelope,sessionGeneration.get(),worldGeneration.get(),resetGeneration.get()))return false;
        if(!inputs.offerResult(entry)){requestReconnect("Stone input result mailbox overflow; reconnecting");return false;}
        return true;
    }
    /** Heartbeats keep a connection alive, but must not make an old pose usable as current state. */
    public Protocol.Pose latestHostPose() {
        HostSnapshot snapshot=latestIncoming.get();
        return connected() && snapshot!=null && snapshot.world()==worldGeneration.get() && snapshot.reset()==resetGeneration.get()
                && System.nanoTime()-snapshot.receivedAtNanos()<=TimeUnit.SECONDS.toNanos(1)
                ? snapshot.pose():null;
    }
    public void publish(Protocol.Pose pose) {
        if (pose.space()!=Protocol.SPACE_MC) throw new IllegalArgumentException("Outgoing pose must use Minecraft coordinate space");
        latestOutgoing.set(pose);
    }
    public boolean blockEvent(Protocol.BlockEvent event) {
        Protocol.blockEvent(event);
        if(!connected()){events.rejected();return false;}
        var entry=new BlockEventMailbox.Entry(sessionGeneration.get(),worldGeneration.get(),resetGeneration.get(),event);
        if(!events.offer(entry)) {
            requestReconnect("Block event queue overflow; resetting transient host session");return false;
        }
        return true;
    }
    /** v1 has no world reset packet. A new authenticated TCP session is the reset boundary. */
    public void resetWorldState() {
        worldGeneration.incrementAndGet();latestOutgoing.set(null);
        requestReconnect("Minecraft world/dimension changed; clearing event baseline and reconnecting");
    }
    private void requestReconnect(String reason) {
        resetGeneration.incrementAndGet();connected=false;latestIncoming.set(null);events.clear();inputs.clear();
        diagnostics.accept(reason);
        Socket socket=currentSocket;
        if(socket!=null)try{socket.close();}catch(IOException ignored){}
    }
    private void run() {
        String lastFailure="";
        while (running) {
            try (Socket socket=new Socket()) {
                long sessionWorld=worldGeneration.get(),sessionReset=resetGeneration.get();
                String token=Files.readString(tokenFile).trim();
                if (!token.matches("[0-9a-f]{64}")) throw new IOException("Token file must contain exactly 64 lowercase hexadecimal characters: "+tokenFile);
                currentSocket=socket;
                socket.connect(new InetSocketAddress("127.0.0.1",port),1000);
                socket.setTcpNoDelay(true); socket.setSoTimeout(1000);
                InputStream in=socket.getInputStream(); OutputStream out=socket.getOutputStream();
                long tx=1, rx=0;
                Protocol.write(out,new Protocol.Frame(Protocol.HELLO,minor,tx++,Protocol.nowMicros(),
                        Protocol.hello(new Protocol.Hello(role,capabilities,name,token))));
                Protocol.Reader reader=new Protocol.Reader();
                Protocol.Frame hello=readHandshake(reader,in);
                if (hello.type()!=Protocol.HELLO) throw new IOException("Host did not send Hello first");
                Protocol.Hello peer=Protocol.parseHello(hello.payload());
                if (peer.role()!=Protocol.ROLE_KCD || !peer.credential().isEmpty() || hello.minor()!=minor || peer.capabilities()!=capabilities)
                    throw new IOException("Invalid host Hello identity/version/capabilities");
                if(sessionWorld!=worldGeneration.get() || sessionReset!=resetGeneration.get())throw new IOException("Session reset during handshake");
                long session=sessionGeneration.incrementAndGet();
                activeWorldGeneration=sessionWorld;activeResetGeneration=sessionReset;
                rx=hello.sequence(); connected=true; lastFailure="";
                diagnostics.accept("Connected to "+peer.name()+" at 127.0.0.1:"+port);
                long lastRx=System.nanoTime(), lastSend=lastRx, poseSend=0,lastInputId=0;
                while (running) {
                    if(!connected())throw new IOException("Session reset requested");
                    long now=System.nanoTime();
                    Protocol.Frame received;
                    int batch=0;
                    while (batch++<128 && (received=reader.poll(in))!=null) {
                        if(received.minor()!=minor)throw new IOException("Session protocol minor changed");
                        if (Long.compareUnsigned(received.sequence(),rx)<=0) throw new IOException("Replayed or out-of-order sequence");
                        rx=received.sequence(); lastRx=now;
                        switch (received.type()) {
                            case Protocol.KCD_POSE -> {
                                Protocol.Pose p=Protocol.parsePose(received.payload());
                                if (p.space()!=Protocol.SPACE_KCD) throw new IOException("Host pose uses wrong coordinate space");
                                latestIncoming.set(new HostSnapshot(p,now,sessionWorld,sessionReset));
                                if (receivedPoses.incrementAndGet()==1) diagnostics.accept("First host pose received and validated");
                            }
                            case Protocol.HEARTBEAT -> {
                                if (received.payload().length!=0) throw new IOException("Heartbeat payload must be empty");
                            }
                            case Protocol.ERROR -> throw new IOException("Host reported an error");
                            case Protocol.GOODBYE -> {
                                if (received.payload().length!=0) throw new IOException("GOODBYE payload must be empty");
                                throw new EOFException("Host closed session");
                            }
                            case Protocol.STONE_INPUT_REQUEST -> {
                                if(capabilities!=Protocol.CAP_STONE_INPUT)throw new IOException("Stone input was not negotiated");
                                var request=Protocol.parseStoneInputRequest(received.payload());
                                if(request.requestId()<=lastInputId)throw new IOException("Replayed or out-of-order stone input ID");
                                lastInputId=request.requestId();
                                if(!inputs.offer(new InputEnvelope(request,session,sessionWorld,sessionReset,System.nanoTime())))
                                    throw new IOException("Stone input request mailbox overflow");
                            }
                            default -> throw new IOException("Unexpected host message type "+received.type());
                        }
                    }
                    if (now-lastRx>TimeUnit.SECONDS.toNanos(6)) throw new IOException("Host heartbeat timed out (6 s)");
                    Protocol.Pose p=latestOutgoing.get();
                    if (p!=null && now-poseSend>=TimeUnit.MILLISECONDS.toNanos(50)) {
                        Protocol.write(out,new Protocol.Frame(Protocol.MC_POSE,minor,tx++,Protocol.nowMicros(),Protocol.pose(p))); poseSend=now; lastSend=now;
                    }
                    BlockEventMailbox.Entry entry;
                    int sentEvents=0;
                    while (sentEvents++<128 && (entry=events.poll(session,sessionWorld,sessionReset))!=null) {
                        if(!connected()){events.rejected();throw new IOException("Session reset before event write");}
                        Protocol.BlockEvent event=entry.event();long sequence=tx++;
                        try { Protocol.write(out,new Protocol.Frame(Protocol.BLOCK_EVENT,minor,sequence,Protocol.nowMicros(),Protocol.blockEvent(event))); }
                        catch(IOException failure){events.rejected();throw failure;}
                        events.sent();lastSentBlockEvent.set(new SentBlockEvent(event,sequence,session));
                        diagnostics.accept("Block event socket write session="+session+" sequence="+sequence+" op="+event.operation()+
                                " xyz="+event.x()+","+event.y()+","+event.z()+" id="+event.blockId());
                        lastSend=now;
                    }
                    StoneInputMailbox.ResultEntry inputResult;
                    int sentResults=0;
                    while(sentResults++<StoneInputMailbox.CAPACITY && (inputResult=inputs.pollResult(session,sessionWorld,sessionReset))!=null) {
                        if(!connected())throw new IOException("Session reset before input result write");
                        var result=inputResult.result();
                        Protocol.write(out,new Protocol.Frame(Protocol.STONE_INPUT_RESULT,minor,tx++,Protocol.nowMicros(),Protocol.stoneInputResult(result)));
                        diagnostics.accept("Stone input result socket write request="+result.requestId()+" action="+result.action()+" result="+result.result());
                        lastSend=now;
                    }
                    if (now-lastSend>=TimeUnit.SECONDS.toNanos(1)) {
                        Protocol.write(out,new Protocol.Frame(Protocol.HEARTBEAT,minor,tx++,Protocol.nowMicros(),new byte[0])); lastSend=now;
                    }
                    Thread.sleep(10);
                }
                Protocol.write(out,new Protocol.Frame(Protocol.GOODBYE,minor,tx,Protocol.nowMicros(),new byte[0]));
            } catch (IOException | InterruptedException e) {
                String failure=e.getClass().getSimpleName()+": "+e.getMessage();
                if (running && !failure.equals(lastFailure)) { diagnostics.accept("Disconnected: "+failure); lastFailure=failure; }
            } finally {
                connected=false; currentSocket=null; latestIncoming.set(null); events.clear();inputs.clear();
            }
            if (running) {
                try { Thread.sleep(1000); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); break; }
            }
        }
    }
    private Protocol.Frame readHandshake(Protocol.Reader reader,InputStream in) throws IOException,InterruptedException {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(6);
        while (running) {
            Protocol.Frame frame=reader.poll(in);
            if (frame!=null) return frame;
            if (System.nanoTime()-deadline>=0) throw new IOException("HELLO handshake timed out (6 s)");
            Thread.sleep(10);
        }
        throw new EOFException("Client stopped during handshake");
    }
    @Override public synchronized void close() {
        running=false;
        if (worker!=null) {
            try { worker.join(100); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
        }
        Socket socket=currentSocket;
        if (socket!=null) try { socket.close(); } catch (IOException ignored) {}
        if (worker!=null) worker.interrupt();
    }
}
