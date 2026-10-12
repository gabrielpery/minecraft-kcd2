package dev.minecome.protocol;

import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.BooleanSupplier;

/** Real loopback sockets, synthetic peers only. Never launches or touches either game. */
final class BridgeClientTests {
    private static int checks;
    private static void check(boolean value,String message) { checks++; if(!value) throw new AssertionError(message); }
    private static void await(BooleanSupplier condition,long timeoutMillis,String message) throws Exception {
        long deadline=System.nanoTime()+timeoutMillis*1_000_000L;
        while(!condition.getAsBoolean() && System.nanoTime()-deadline<0) Thread.sleep(10);
        check(condition.getAsBoolean(),message);
    }
    static int run() throws Exception {
        checks=0;
        Path token=Files.createTempFile("minecome-protocol-test-",".token");
        Files.writeString(token,"0".repeat(64));
        String previousPort=System.getProperty("minecome.port");
        try {
            generationMailbox();
            overflowAndWorldReset(token);
            freshnessAndGoodbye(token);
            slowHandshakeDeadline(token);
        } finally {
            if(previousPort==null)System.clearProperty("minecome.port");else System.setProperty("minecome.port",previousPort);
            Files.deleteIfExists(token);
        }
        return checks;
    }
    private static Protocol.Frame frame(int type,long sequence,byte[] payload) {
        return new Protocol.Frame(type,sequence,Protocol.nowMicros(),payload);
    }
    private static void generationMailbox() {
        BlockEventMailbox mailbox=new BlockEventMailbox();
        var event=new Protocol.BlockEvent(1,1,2,3,"minecraft:stone");
        for(int i=0;i<128;i++)check(mailbox.offer(new BlockEventMailbox.Entry(1,1,1,event)),"bounded queue accepts capacity");
        check(!mailbox.offer(new BlockEventMailbox.Entry(1,1,1,event)),"overflow rejected without silently replacing oldest removal");
        check(mailbox.pending()==128,"event queue stays bounded");
        mailbox.clear();
        check(mailbox.pending()==0 && mailbox.droppedCount()==129,"reset accounts for dropped queued events and overflow");
        // These model an offer racing after reset has already drained the old queue.
        mailbox.offer(new BlockEventMailbox.Entry(1,1,1,event));
        mailbox.offer(new BlockEventMailbox.Entry(2,1,1,event));
        mailbox.offer(new BlockEventMailbox.Entry(2,2,1,event));
        var current=new BlockEventMailbox.Entry(2,2,2,event);mailbox.offer(current);
        check(mailbox.poll(2,2,2).equals(current),"late old session/world/reset entries cannot leak into new session");
        check(mailbox.droppedCount()==132 && mailbox.pending()==0,"all stale generations discarded");
    }
    private static Protocol.Pose fixturePose(int space) {
        return new Protocol.Pose(new Protocol.Vec3(1,2,3),new Protocol.Vec3(1,2,4),new Protocol.Quaternion(0,0,0,1),
                1.2,new Protocol.Vec3(0,0,0),1,space,Protocol.HAS_PLAYER|Protocol.HAS_CAMERA);
    }
    private static void authenticateFixture(Socket socket) throws Exception {
        socket.setSoTimeout(3000);
        Protocol.Frame hello=Protocol.read(socket.getInputStream());
        if(hello.type()!=Protocol.HELLO || !Protocol.parseHello(hello.payload()).credential().equals("0".repeat(64)))
            throw new AssertionError("Fixture did not receive authenticated Hello first");
        Protocol.write(socket.getOutputStream(),frame(Protocol.HELLO,1,Protocol.hello(new Protocol.Hello(1,0,"reset-fixture",""))));
    }
    private static void overflowAndWorldReset(Path token) throws Exception {
        var errors=new AtomicReference<Throwable>();
        var reference=new AtomicReference<BridgeClient>();
        var overflowTriggered=new AtomicBoolean();
        var diagnostics=new ConcurrentLinkedQueue<String>();
        var secondEvent=new AtomicReference<Protocol.BlockEvent>();
        var thirdEvent=new AtomicReference<Protocol.BlockEvent>();
        var secondSawPose=new AtomicBoolean();
        var thirdSawStalePose=new AtomicBoolean();
        var firstClosed=new CountDownLatch(1);
        var thirdClosed=new CountDownLatch(1);
        try(ServerSocket listener=new ServerSocket(0,3,InetAddress.getByName("127.0.0.1"))) {
            listener.setSoTimeout(6000);
            System.setProperty("minecome.port",Integer.toString(listener.getLocalPort()));
            Thread host=new Thread(()->{
                try {
                    try(Socket socket=listener.accept()) {
                        authenticateFixture(socket);
                        try {
                            while(true)if(Protocol.read(socket.getInputStream()).type()==Protocol.BLOCK_EVENT)
                                throw new AssertionError("Overflowed session sent queued event instead of resetting");
                        }catch(EOFException expected){firstClosed.countDown();}
                    }
                    try(Socket socket=listener.accept()) {
                        authenticateFixture(socket);
                        Protocol.write(socket.getOutputStream(),frame(Protocol.KCD_POSE,2,Protocol.pose(fixturePose(Protocol.SPACE_KCD))));
                        try {
                            while(true) {
                                Protocol.Frame incoming=Protocol.read(socket.getInputStream());
                                if(incoming.type()==Protocol.BLOCK_EVENT) {
                                    var event=Protocol.parseBlockEvent(incoming.payload());
                                    if(event.x()!=777)throw new AssertionError("Old event replayed after overflow");
                                    secondEvent.set(event);
                                } else if(incoming.type()==Protocol.MC_POSE)secondSawPose.set(true);
                            }
                        }catch(EOFException expected){}
                    }
                    try(Socket socket=listener.accept()) {
                        authenticateFixture(socket);socket.setSoTimeout(100);
                        Protocol.write(socket.getOutputStream(),frame(Protocol.KCD_POSE,2,Protocol.pose(fixturePose(Protocol.SPACE_KCD))));
                        while(thirdClosed.getCount()!=0) {
                            try {
                                Protocol.Frame incoming=Protocol.read(socket.getInputStream());
                                if(incoming.type()==Protocol.MC_POSE)thirdSawStalePose.set(true);
                                else if(incoming.type()==Protocol.BLOCK_EVENT)thirdEvent.set(Protocol.parseBlockEvent(incoming.payload()));
                            }catch(SocketTimeoutException expected){}catch(EOFException expected){break;}
                        }
                    }
                }catch(Throwable t){errors.set(t);}
            },"MineCome-test-overflow-and-world-reset");host.setDaemon(true);host.start();
            try(BridgeClient client=new BridgeClient(token,"test",3,message->{
                diagnostics.add(message);
                // Runs before the socket worker can drain: deterministically fill all 128 slots.
                if(message.startsWith("Connected to") && overflowTriggered.compareAndSet(false,true)) {
                    for(int i=0;i<129;i++)reference.get().blockEvent(new Protocol.BlockEvent(1,i,2,3,"minecraft:stone"));
                }
            })) {
                reference.set(client);client.start();
                await(()->firstClosed.getCount()==0,3000,"queue overflow closes authenticated TCP session");
                await(()->client.status().session()==2 && client.latestHostPose()!=null,4000,"overflow reconnects and reauthenticates with fresh host state");
                check(client.status().droppedEvents()==129 && client.status().sentEvents()==0,"overflow drops full old generation with no false sent count");
                check(diagnostics.stream().anyMatch(s->s.contains("queue overflow")),"overflow reset is visible in diagnostics");
                var addition=new Protocol.BlockEvent(1,777,2,3,"minecraft:stone");
                check(client.blockEvent(addition),"new session accepts fresh observed event");
                await(()->addition.equals(secondEvent.get()),2000,"fresh event arrives on second socket without old replay");
                await(()->client.lastSentBlockEvent()!=null && client.lastSentBlockEvent().session()==2,2000,"socket receipt carries authenticated session identity");
                client.publish(fixturePose(Protocol.SPACE_MC));
                await(secondSawPose::get,2000,"fixture saw outgoing pose before world reset");
                client.resetWorldState();
                check(!client.connected() && client.latestHostPose()==null,"world reset immediately invalidates connection and host pose");
                await(()->client.status().session()==3 && client.latestHostPose()!=null,4000,"world reset performs fresh handshake and pose exchange");
                check(client.status().world()==1 && client.status().resets()==2,"world and overflow reset generations accounted");
                Thread.sleep(150);
                check(!thirdSawStalePose.get(),"world reset clears outgoing pose before new session");
                var removal=new Protocol.BlockEvent(2,777,2,3,"minecraft:stone");
                check(client.blockEvent(removal),"new world session accepts new removal");
                await(()->removal.equals(thirdEvent.get()),2000,"removal arrives after world reset");
                check(errors.get()==null,"loopback reset fixture has no peer errors");
            }finally{thirdClosed.countDown();host.interrupt();host.join(1500);}
            check(!host.isAlive() && errors.get()==null,"loopback reset fixture terminates cleanly");
        }
    }
    private static void freshnessAndGoodbye(Path token) throws Exception {
        var errors=new AtomicReference<Throwable>();
        var diagnostics=new ConcurrentLinkedQueue<String>();
        var sendGoodbye=new CountDownLatch(1);
        try(ServerSocket listener=new ServerSocket(0,1,InetAddress.getByName("127.0.0.1"))) {
            System.setProperty("minecome.port",Integer.toString(listener.getLocalPort()));
            Thread host=new Thread(()->{
                try(Socket socket=listener.accept()) {
                    socket.setSoTimeout(3000);
                    Protocol.Frame hello=Protocol.read(socket.getInputStream());
                    if(hello.type()!=Protocol.HELLO || !Protocol.parseHello(hello.payload()).credential().equals("0".repeat(64)))
                        throw new AssertionError("Fixture did not receive authenticated Hello first");
                    OutputStream out=socket.getOutputStream();
                    Protocol.write(out,frame(Protocol.HELLO,1,Protocol.hello(new Protocol.Hello(1,0,"fixture",""))));
                    var pose=new Protocol.Pose(new Protocol.Vec3(1,2,3),new Protocol.Vec3(1,2,4),new Protocol.Quaternion(0,0,0,1),
                            1.2,new Protocol.Vec3(0,0,0),1,Protocol.SPACE_KCD,3);
                    Protocol.write(out,frame(Protocol.KCD_POSE,2,Protocol.pose(pose)));
                    long sequence=3;
                    while(!sendGoodbye.await(150,TimeUnit.MILLISECONDS))
                        Protocol.write(out,frame(Protocol.HEARTBEAT,sequence++,new byte[0]));
                    Protocol.write(out,frame(Protocol.GOODBYE,sequence,new byte[]{1}));
                    Thread.sleep(200);
                }catch(Throwable t){errors.set(t);}
            },"MineCome-test-valid-and-bad-goodbye");host.setDaemon(true);host.start();
            try(BridgeClient client=new BridgeClient(token,"test",3,diagnostics::add)) {
                client.start();
                await(()->client.latestHostPose()!=null,3000,"fresh authenticated host pose exposed");
                await(()->client.latestHostPose()==null,2000,"heartbeat-only peer cannot retain stale pose");
                check(client.connected(),"heartbeat-only connection stays alive while pose expires");
                sendGoodbye.countDown();
                await(()->diagnostics.stream().anyMatch(s->s.contains("GOODBYE payload must be empty")),2000,"nonempty Goodbye rejected");
            }finally{sendGoodbye.countDown();host.join(2000);}
            check(!host.isAlive() && errors.get()==null,"loopback fixture completed without server errors");
        }
    }
    private static void slowHandshakeDeadline(Path token) throws Exception {
        var diagnostics=new ConcurrentLinkedQueue<String>();
        try(ServerSocket listener=new ServerSocket(0,1,InetAddress.getByName("127.0.0.1"))) {
            System.setProperty("minecome.port",Integer.toString(listener.getLocalPort()));
            Thread host=new Thread(()->{
                try(Socket socket=listener.accept()) {
                    socket.setSoTimeout(3000);Protocol.read(socket.getInputStream());
                    byte[] hello=Protocol.encode(frame(Protocol.HELLO,1,Protocol.hello(new Protocol.Hello(1,0,"fixture",""))));
                    for(int i=0;i<8;i++) {socket.getOutputStream().write(hello[i]);socket.getOutputStream().flush();Thread.sleep(1000);}
                }catch(IOException | InterruptedException expected) { /* The tested deadline closes this slow peer. */ }
            },"MineCome-test-slow-hello");host.setDaemon(true);host.start();
            try(BridgeClient client=new BridgeClient(token,"test",3,diagnostics::add)) {
                long started=System.nanoTime();client.start();
                await(()->diagnostics.stream().anyMatch(s->s.contains("HELLO handshake timed out (6 s)")),7500,
                        "slow fragmented Hello has absolute six-second deadline");
                check(System.nanoTime()-started<TimeUnit.MILLISECONDS.toNanos(7500),"drip-feed cannot extend handshake deadline");
                check(!client.connected() && client.latestHostPose()==null,"no usable state before handshake");
            }finally{host.interrupt();host.join(1500);}
        }
    }
}
