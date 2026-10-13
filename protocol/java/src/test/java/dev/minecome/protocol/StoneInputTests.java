package dev.minecome.protocol;

import java.io.*;
import java.net.*;
import java.nio.*;
import java.nio.file.*;
import java.util.Arrays;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.BooleanSupplier;

/** Real loopback transport fixtures, without either game or game APIs. */
final class StoneInputTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void await(BooleanSupplier condition,String message) throws Exception {
        long deadline=System.nanoTime()+4_000_000_000L;
        while(!condition.getAsBoolean() && System.nanoTime()<deadline)Thread.sleep(10);
        check(condition.getAsBoolean(),message);
    }
    private static void rejectRequest(byte[] data) throws Exception {
        try{Protocol.parseStoneInputRequest(data);throw new AssertionError("Malformed input accepted");}catch(IOException expected){checks++;}
    }
    private static void rejectResult(byte[] data) throws Exception {
        try{Protocol.parseStoneInputResult(data);throw new AssertionError("Malformed result accepted");}catch(IOException expected){checks++;}
    }
    static int run() throws Exception {
        checks=0;codec();mailbox();
        Path token=Files.createTempFile("minecome-input-",".token");Files.writeString(token,"0".repeat(64));
        String old=System.getProperty("minecome.port");
        try {
            exchangeAndReplay(token);
            rejectPeer(token,false,0,1,false,"Invalid host Hello");
            rejectPeer(token,true,1,0,false,"Invalid host Hello");
            rejectPeer(token,true,1,1,true,"Session protocol minor changed");
            incomingOverflow(token);
        } finally {
            if(old==null)System.clearProperty("minecome.port");else System.setProperty("minecome.port",old);
            Files.deleteIfExists(token);
        }
        return checks;
    }
    private static Protocol.Frame frame(int type,int minor,long sequence,byte[] payload) {
        return new Protocol.Frame(type,minor,sequence,Protocol.nowMicros(),payload);
    }
    private static void codec() throws Exception {
        for(long id:new long[]{1,Protocol.MAX_INPUT_ID})for(int action=1;action<=2;action++) {
            var request=new Protocol.StoneInputRequest(id,action);
            check(Protocol.parseStoneInputRequest(Protocol.stoneInputRequest(request)).equals(request),"ID/action exact request round trip");
            byte[] wire=Protocol.encode(frame(Protocol.STONE_INPUT_REQUEST,1,1,Protocol.stoneInputRequest(request)));
            check(Protocol.decode(wire).minor()==1 && wire[6]==1,"minor1 retained on wire");
            wire[6]=0;
            try{Protocol.decode(wire);throw new AssertionError("Input under minor0 accepted");}catch(IOException expected){checks++;}
            for(int result=1;result<=7;result++) {
                var response=new Protocol.StoneInputResult(id,action,result);
                check(Protocol.parseStoneInputResult(Protocol.stoneInputResult(response)).equals(response),"all result enums exact round trip");
            }
        }
        check(new Protocol.Frame(Protocol.HEARTBEAT,1,0,new byte[0]).minor()==0,"legacy constructor retains minor0");
        try{new Protocol.Frame(Protocol.STONE_INPUT_RESULT,1,0,new byte[0]);throw new AssertionError("Legacy new type accepted");}
        catch(IllegalArgumentException expected){checks++;}
        byte[] request=Protocol.stoneInputRequest(new Protocol.StoneInputRequest(1,1));
        for(long id:new long[]{0,-1,Protocol.MAX_INPUT_ID+1,Long.MAX_VALUE}) {
            byte[] bad=request.clone();ByteBuffer.wrap(bad).order(ByteOrder.LITTLE_ENDIAN).putLong(0,id);rejectRequest(bad);
        }
        for(int action:new int[]{0,3,-1}) {
            byte[] bad=request.clone();ByteBuffer.wrap(bad).order(ByteOrder.LITTLE_ENDIAN).putInt(8,action);rejectRequest(bad);
        }
        rejectRequest(Arrays.copyOf(request,11));rejectRequest(Arrays.copyOf(request,13));
        byte[] result=Protocol.stoneInputResult(new Protocol.StoneInputResult(1,1,1));
        for(int invalid:new int[]{0,8,-1}) {
            byte[] bad=result.clone();ByteBuffer.wrap(bad).order(ByteOrder.LITTLE_ENDIAN).putInt(12,invalid);rejectResult(bad);
        }
        rejectResult(Arrays.copyOf(result,15));rejectResult(Arrays.copyOf(result,17));
        for(int role:new int[]{Protocol.ROLE_KCD,Protocol.ROLE_MC}) {
            var hello=new Protocol.Hello(role,1,"input-peer","");
            check(Protocol.parseHello(Protocol.hello(hello)).equals(hello),"MC capability and KCD echo permitted");
        }
        try{Protocol.hello(new Protocol.Hello(Protocol.ROLE_HARNESS,1,"harness",""));throw new AssertionError("Harness capability accepted");}
        catch(IllegalArgumentException expected){checks++;}
        try{Protocol.hello(new Protocol.Hello(Protocol.ROLE_MC,4,"client",""));throw new AssertionError("Unknown capability accepted");}
        catch(IllegalArgumentException expected){checks++;}
    }
    private static BridgeClient.InputEnvelope envelope(long session,long world,long reset,long id) {
        return new BridgeClient.InputEnvelope(new Protocol.StoneInputRequest(id,1),session,world,reset,System.nanoTime());
    }
    private static void mailbox() {
        var mailbox=new StoneInputMailbox();
        for(int i=1;i<=16;i++)check(mailbox.offer(envelope(1,1,1,i)),"request queue capacity16");
        check(!mailbox.offer(envelope(1,1,1,17)),"request overflow refused");
        mailbox.clear();
        mailbox.offer(envelope(1,2,3,1));mailbox.offer(envelope(2,1,3,2));mailbox.offer(envelope(2,2,1,3));
        var current=envelope(2,2,3,4);mailbox.offer(current);
        check(mailbox.poll(2,2,3).equals(current) && mailbox.poll(2,2,3)==null,"stale session/world/reset requests discarded");
        var response=new Protocol.StoneInputResult(4,1,1);
        mailbox.offerResult(new StoneInputMailbox.ResultEntry(envelope(1,2,3,4),response));
        var expected=new StoneInputMailbox.ResultEntry(current,response);mailbox.offerResult(expected);
        check(mailbox.pollResult(2,2,3).equals(expected),"stale results cannot cross connection generations");
        for(int i=0;i<16;i++)check(mailbox.offerResult(expected),"result queue capacity16");
        check(!mailbox.offerResult(expected),"result overflow refused");
        mailbox.clear();check(mailbox.pollResult(2,2,3)==null,"reset clears pending results");
    }
    private static Protocol.Pose pose(int flags) {
        var zero=new Protocol.Vec3(0,0,0);
        return new Protocol.Pose(zero,zero,new Protocol.Quaternion(0,0,0,1),1.2,zero,1,Protocol.SPACE_KCD,flags);
    }
    private static void authenticate(Socket socket) throws Exception {
        socket.setSoTimeout(3000);
        var hello=Protocol.read(socket.getInputStream());var peer=Protocol.parseHello(hello.payload());
        if(hello.minor()!=1 || peer.capabilities()!=1 || peer.role()!=Protocol.ROLE_MC || !peer.credential().equals("0".repeat(64)))
            throw new AssertionError("Expected authenticated real MC minor1 capability1");
        Protocol.write(socket.getOutputStream(),frame(Protocol.HELLO,1,1,Protocol.hello(new Protocol.Hello(1,1,"input-fixture",""))));
    }
    private static Protocol.StoneInputResult readResult(Socket socket) throws Exception {
        while(true) {
            var incoming=Protocol.read(socket.getInputStream());
            if(incoming.minor()!=1)throw new AssertionError("Outgoing frame lost negotiated minor");
            if(incoming.type()==Protocol.STONE_INPUT_RESULT)return Protocol.parseStoneInputResult(incoming.payload());
        }
    }
    private static void exchangeAndReplay(Path token) throws Exception {
        var errors=new AtomicReference<Throwable>();var results=new ArrayBlockingQueue<Protocol.StoneInputResult>(2);
        var diagnostics=new ConcurrentLinkedQueue<String>();
        try(var listener=new ServerSocket(0,1,InetAddress.getLoopbackAddress())) {
            System.setProperty("minecome.port",Integer.toString(listener.getLocalPort()));
            Thread host=new Thread(()->{
                try(var socket=listener.accept()) {
                    authenticate(socket);var out=socket.getOutputStream();
                    Protocol.write(out,frame(Protocol.KCD_POSE,1,2,Protocol.pose(pose(3))));
                    Protocol.write(out,frame(Protocol.STONE_INPUT_REQUEST,1,3,Protocol.stoneInputRequest(new Protocol.StoneInputRequest(Protocol.MAX_INPUT_ID-1,1))));
                    results.add(readResult(socket));
                    Protocol.write(out,frame(Protocol.KCD_POSE,1,4,Protocol.pose(pose(0))));
                    Protocol.write(out,frame(Protocol.STONE_INPUT_REQUEST,1,5,Protocol.stoneInputRequest(new Protocol.StoneInputRequest(Protocol.MAX_INPUT_ID,2))));
                    results.add(readResult(socket));
                    Protocol.write(out,frame(Protocol.STONE_INPUT_REQUEST,1,6,Protocol.stoneInputRequest(new Protocol.StoneInputRequest(Protocol.MAX_INPUT_ID,2))));
                    try{while(true)Protocol.read(socket.getInputStream());}catch(EOFException expected){}
                }catch(Throwable e){errors.set(e);}
            },"stone-input-fixture");host.start();
            try(var bridge=new BridgeClient(token,"real-mc-fixture",2,diagnostics::add,true)) {
                bridge.start();
                var received=new AtomicReference<BridgeClient.InputEnvelope>();
                await(()->{if(received.get()==null)received.set(bridge.pollStoneInputRequest());return received.get()!=null;},"receive bounded input envelope");
                var first=received.get();
                check(bridge.supportsStoneInput() && bridge.stoneInputAvailability(first)==0,"fresh host flags3 permit client tick gate");
                var stale=new BridgeClient.InputEnvelope(first.request(),first.session(),first.world(),first.reset(),System.nanoTime()-1_100_000_000L);
                check(bridge.stoneInputAvailability(stale)==Protocol.INPUT_STALE,"local request age exceeds one second");
                var future=new BridgeClient.InputEnvelope(first.request(),first.session(),first.world(),first.reset(),System.nanoTime()+1_000_000_000L);
                check(bridge.stoneInputAvailability(future)==Protocol.INPUT_STALE,"future receipt timestamp rejected");
                var oldWorld=new BridgeClient.InputEnvelope(first.request(),first.session(),first.world()+1,first.reset(),first.receivedAtNanos());
                check(bridge.stoneInputAvailability(oldWorld)==Protocol.INPUT_UNAVAILABLE && !bridge.sendStoneInputResult(oldWorld,1),"stale world cannot act or send result");
                check(bridge.sendStoneInputResult(first,1),"dispatch-only accepted result queued");
                received.set(null);
                await(()->{if(received.get()==null)received.set(bridge.pollStoneInputRequest());return received.get()!=null;},"receive second unique input");
                check(bridge.stoneInputAvailability(received.get())==Protocol.INPUT_UNAVAILABLE,"fresh flags0 cannot authorize action");
                check(bridge.sendStoneInputResult(received.get(),2),"unavailable result queued");
                await(()->diagnostics.stream().anyMatch(s->s.contains("Replayed or out-of-order stone input ID")),"duplicate request ID closes session");
                check(!bridge.supportsStoneInput() && bridge.pollStoneInputRequest()==null,"disconnect clears interactive readiness and queued requests");
                check(results.poll(1,TimeUnit.SECONDS).equals(new Protocol.StoneInputResult(Protocol.MAX_INPUT_ID-1,1,1)),"wire result preserves exact large ID/action");
                check(results.poll(1,TimeUnit.SECONDS).equals(new Protocol.StoneInputResult(Protocol.MAX_INPUT_ID,2,2)),"wire unavailable result exact");
            }
            host.join(4000);check(!host.isAlive() && errors.get()==null,"interactive fixture completed: "+errors.get());
        }
    }
    private static void rejectPeer(Path token,boolean interactive,int helloMinor,int caps,boolean changeMinor,String reason) throws Exception {
        var errors=new AtomicReference<Throwable>();var diagnostics=new ConcurrentLinkedQueue<String>();
        try(var listener=new ServerSocket(0,1,InetAddress.getLoopbackAddress())) {
            System.setProperty("minecome.port",Integer.toString(listener.getLocalPort()));
            Thread host=new Thread(()->{
                try(var socket=listener.accept()) {
                    socket.setSoTimeout(3000);Protocol.read(socket.getInputStream());
                    Protocol.write(socket.getOutputStream(),frame(Protocol.HELLO,helloMinor,1,Protocol.hello(new Protocol.Hello(1,caps,"invalid-fixture",""))));
                    if(changeMinor)Protocol.write(socket.getOutputStream(),frame(Protocol.HEARTBEAT,0,2,new byte[0]));
                    try{while(true)Protocol.read(socket.getInputStream());}catch(EOFException expected){}
                }catch(Throwable e){errors.set(e);}
            });host.start();
            try(var bridge=new BridgeClient(token,"version-fixture",2,diagnostics::add,interactive)) {
                bridge.start();await(()->diagnostics.stream().anyMatch(s->s.contains(reason)),"reject mismatched negotiated minor/capability");
            }
            host.join(4000);check(!host.isAlive() && errors.get()==null,"version fixture closed: "+errors.get());
        }
    }
    private static void incomingOverflow(Path token) throws Exception {
        var errors=new AtomicReference<Throwable>();var diagnostics=new ConcurrentLinkedQueue<String>();
        try(var listener=new ServerSocket(0,1,InetAddress.getLoopbackAddress())) {
            System.setProperty("minecome.port",Integer.toString(listener.getLocalPort()));
            Thread host=new Thread(()->{
                try(var socket=listener.accept()) {
                    authenticate(socket);
                    for(int i=1;i<=17;i++)Protocol.write(socket.getOutputStream(),frame(8,1,i+1,Protocol.stoneInputRequest(new Protocol.StoneInputRequest(i,1))));
                    try{while(true)Protocol.read(socket.getInputStream());}catch(EOFException expected){}
                }catch(Throwable e){errors.set(e);}
            });host.start();
            try(var bridge=new BridgeClient(token,"overflow-fixture",2,diagnostics::add,true)) {
                bridge.start();await(()->diagnostics.stream().anyMatch(s->s.contains("request mailbox overflow")),"overflow closes instead of losing an input");
                check(bridge.pollStoneInputRequest()==null,"overflow disconnect clears mailbox");
            }
            host.join(4000);check(!host.isAlive() && errors.get()==null,"overflow fixture completed: "+errors.get());
        }
    }
}
