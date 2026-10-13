package dev.minecome.protocol;

import java.io.*;
import java.net.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.BooleanSupplier;

final class AimedProtocolTests {
    private static int checks;
    private interface Checked { void run() throws Exception; }
    private static void check(boolean value,String name){checks++;if(!value)throw new AssertionError(name);}
    private static void reject(Checked call,String name) throws Exception {
        try{call.run();throw new AssertionError("Accepted "+name);}catch(IOException|IllegalArgumentException|IllegalStateException expected){checks++;}
    }
    static int run() throws Exception { codecs();lifecycle();transport();return checks; }
    private static Protocol.AimedArena arena(){
        return new Protocol.AimedArena(Protocol.MAX_INPUT_ID,new Protocol.Vec3(-10,-58.38,2),new Protocol.Vec3(120,2040,56),1,
                new Protocol.Cell(-8,-60,2),new Protocol.Cell(-10,-62,0),new Protocol.Cell(-6,-58,4));
    }
    private static Protocol.AimedStoneRequest request(long id,long permit,int occlusion){
        return new Protocol.AimedStoneRequest(arena().arenaId(),id,permit,2,occlusion,arena().kcdAnchor(),new Protocol.Vec3(1,0,0),4.5,occlusion==2?3.25:0);
    }
    private static void codecs() throws Exception {
        var golden=new LinkedHashMap<String,byte[]>();
        Path fixture=Files.exists(Path.of("tests/fixtures/aim_protocol.txt"))?Path.of("tests/fixtures/aim_protocol.txt"):Path.of("../tests/fixtures/aim_protocol.txt");
        for(String line:Files.readAllLines(fixture))if(!line.isBlank() && !line.startsWith("#")){String[] bits=line.split(" ");golden.put(bits[0],HexFormat.of().parseHex(bits[1]));}
        byte[] offer=Protocol.aimedArena(arena());
        byte[] permit=Protocol.aimPermit(new Protocol.AimPermit(Protocol.MAX_INPUT_ID,Protocol.MAX_INPUT_ID-1));
        byte[] request=Protocol.aimedStoneRequest(request(Protocol.MAX_INPUT_ID-2,Protocol.MAX_INPUT_ID-1,2));
        byte[] result=Protocol.aimedStoneResult(new Protocol.AimedStoneResult(Protocol.MAX_INPUT_ID,Protocol.MAX_INPUT_ID-2,2,1));
        check(Arrays.equals(offer,golden.get("arena")),"cross-language arena bytes");
        check(Arrays.equals(permit,golden.get("permit")),"cross-language permit bytes");
        check(Arrays.equals(request,golden.get("request")),"cross-language request bytes");
        check(Arrays.equals(result,golden.get("result")),"cross-language result bytes");
        check(Protocol.parseAimedArena(offer).equals(arena()),"arena roundtrip");
        check(Protocol.parseAimPermit(permit).permitId()==Protocol.MAX_INPUT_ID-1,"permit exact integer");
        check(Protocol.parseAimedStoneRequest(request).requestId()==Protocol.MAX_INPUT_ID-2,"request exact integer");
        check(Protocol.parseAimedStoneResult(result).result()==Protocol.AIM_CONFIRMED,"result has distinct confirmed meaning");
        for(int type=1;type<=14;type++)for(int minor=0;minor<=2;minor++){
            final int t=type,m=minor;boolean valid=type<=7 || (minor==1 && type<=9) || (minor==2 && type>=10);
            if(valid)check(Protocol.decode(Protocol.encode(new Protocol.Frame(type,minor,1,0,new byte[0]))).type()==type,"version type accepted");
            else reject(()->new Protocol.Frame(t,m,1,0,new byte[0]),"version type mismatch");
        }
        for(int role=1;role<=3;role++)for(int caps=0;caps<=4;caps++){
            final int r=role,c=caps;boolean valid=caps==0 || (role!=3 && (caps==1 || caps==2));
            if(valid)check(Protocol.parseHello(Protocol.hello(new Protocol.Hello(role,caps,"fixture",""))).capabilities()==caps,"exclusive Hello capabilities");
            else reject(()->Protocol.hello(new Protocol.Hello(r,c,"fixture","")),"combined/unknown capabilities or harness");
        }
        for(int size=0;size<100;size++){final int n=size;reject(()->Protocol.parseAimedArena(Arrays.copyOf(offer,n)),"arena truncated");}
        reject(()->Protocol.parseAimedArena(Arrays.copyOf(offer,101)),"arena trailing");
        for(long id:new long[]{0,-1,Protocol.MAX_INPUT_ID+1}){byte[] bad=offer.clone();ByteBuffer.wrap(bad).order(ByteOrder.LITTLE_ENDIAN).putLong(0,id);reject(()->Protocol.parseAimedArena(bad),"invalid arena ID");}
        for(int offset:new int[]{64,68,72,76,80,84,88,92,96}){
            byte[] invalid=offer.clone();ByteBuffer.wrap(invalid).order(ByteOrder.LITTLE_ENDIAN).putInt(offset,0x7fffffff);
            reject(()->Protocol.parseAimedArena(invalid),"invalid arena ID/cell bounds");
        }
        for(int offset:new int[]{8,16,24,32,40,48,56})for(double value:new double[]{Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY,10_000_001}){
            byte[] invalid=offer.clone();ByteBuffer.wrap(invalid).order(ByteOrder.LITTLE_ENDIAN).putDouble(offset,value);
            reject(()->Protocol.parseAimedArena(invalid),"invalid arena finite/bounded number");
        }
        for(int size=0;size<96;size++){final int n=size;reject(()->Protocol.parseAimedStoneRequest(Arrays.copyOf(request,n)),"request truncated");}
        reject(()->Protocol.parseAimedStoneRequest(Arrays.copyOf(request,97)),"request trailing");
        for(int offset:new int[]{0,8,16})for(long value:new long[]{0,-1,Protocol.MAX_INPUT_ID+1}){
            byte[] invalid=request.clone();ByteBuffer.wrap(invalid).order(ByteOrder.LITTLE_ENDIAN).putLong(offset,value);
            reject(()->Protocol.parseAimedStoneRequest(invalid),"invalid exact request ID");
        }
        for(int offset:new int[]{24,28}){
            byte[] invalid=request.clone();ByteBuffer.wrap(invalid).order(ByteOrder.LITTLE_ENDIAN).putInt(offset,3);
            reject(()->Protocol.parseAimedStoneRequest(invalid),"invalid action/occlusion");
        }
        for(int offset:new int[]{32,40,48,56,64,72,80,88}){
            byte[] invalid=request.clone();ByteBuffer.wrap(invalid).order(ByteOrder.LITTLE_ENDIAN).putDouble(offset,Double.NaN);
            reject(()->Protocol.parseAimedStoneRequest(invalid),"nonfinite ray");
        }
        for(double value:new double[]{0,-1,4.50001}){byte[] invalid=request.clone();ByteBuffer.wrap(invalid).order(ByteOrder.LITTLE_ENDIAN).putDouble(80,value);reject(()->Protocol.parseAimedStoneRequest(invalid),"ray range");}
        byte[] invalidDirection=request.clone();ByteBuffer.wrap(invalidDirection).order(ByteOrder.LITTLE_ENDIAN).putDouble(56,.99);reject(()->Protocol.parseAimedStoneRequest(invalidDirection),"nonunit ray");
        byte[] badClear=request.clone();ByteBuffer.wrap(badClear).order(ByteOrder.LITTLE_ENDIAN).putInt(28,1);reject(()->Protocol.parseAimedStoneRequest(badClear),"clear with nonzero obstruction");
        for(int code=1;code<=10;code++)check(Protocol.parseAimedStoneResult(Protocol.aimedStoneResult(new Protocol.AimedStoneResult(1,2,1,code))).result()==code,"all aimed terminal codes");
        reject(()->new Protocol.AimedStoneResult(1,2,1,0),"zero result");reject(()->new Protocol.AimedStoneResult(1,2,1,11),"unknown result");
    }
    private static AimedSession ready(long now) throws Exception {
        AimedSession gate=new AimedSession();gate.offer(arena(),now);var offer=gate.pollOutbound();gate.written(offer);gate.acknowledge(offer.payload());return gate;
    }
    private static Protocol.AimPermit issue(AimedSession gate,long now) throws Exception {
        var permit=gate.issue(now);gate.written(gate.pollOutbound());return permit;
    }
    private static int result(AimedSession gate) throws Exception {return Protocol.parseAimedStoneResult(gate.pollOutbound().payload()).result();}
    private static void lifecycle() throws Exception {
        long time=-9_000_000_000L; // nanoTime has no requirement to be positive.
        AimedSession gate=new AimedSession();check(!gate.ready() && gate.issue(time)==null,"no permits before alignment");
        reject(()->gate.receive(request(1,1,1),time),"request before ACK");
        gate.offer(arena(),time);reject(()->gate.acknowledge(Protocol.aimedArena(arena())),"ACK before offer socket write");
        reject(()->gate.offer(arena(),time),"offer replacement");gate.written(gate.pollOutbound());
        byte[] changed=Protocol.aimedArena(arena());ByteBuffer.wrap(changed).order(ByteOrder.LITTLE_ENDIAN).putDouble(32,120.125);
        reject(()->gate.acknowledge(changed),"changed echoed alignment");gate.acknowledge(Protocol.aimedArena(arena()));
        reject(()->gate.acknowledge(Protocol.aimedArena(arena())),"duplicate ACK");
        var permit=issue(gate,time);gate.receive(request(1,permit.permitId(),1),time+100);
        var admitted=gate.poll();check(admitted!=null && admitted.capturedAtNanos()==time,"original permit timestamp retained, including negative nanoTime");
        check(gate.poll()==null,"single request dequeue");
        var busyPermit=issue(gate,time+100);gate.receive(request(2,busyPermit.permitId(),1),time+200);check(result(gate)==Protocol.AIM_BUSY,"one in-flight action");
        check(!gate.complete(request(999,permit.permitId(),1),1),"mismatched result refused");check(gate.complete(admitted.request(),1),"terminal result for original request");check(result(gate)==1,"terminal confirmation distinct from dispatch");check(!gate.complete(admitted.request(),1),"duplicate completion refused");
        gate.receive(request(3,permit.permitId(),1),time+300);check(result(gate)==Protocol.AIM_STALE,"permit cannot be reused");
        reject(()->gate.receive(request(3,permit.permitId(),1),time+400),"replayed request ID");
        var old=issue(gate,time+500);gate.receive(request(4,old.permitId(),1),time+500+AimedSession.PERMIT_LIFETIME_NANOS+1);check(result(gate)==Protocol.AIM_STALE,"transport delay charged to permit age");
        var unavailable=issue(gate,time+600);gate.receive(request(5,unavailable.permitId(),0),time+700);check(result(gate)==Protocol.AIM_UNAVAILABLE,"unknown host obstruction cannot act");
        reject(()->gate.receive(request(6,1000,1),time+800),"unissued permit");
        gate.clear();check(!gate.ready() && gate.poll()==null && gate.pollOutbound()==null,"disconnect reset clears all work");
        AimedSession timeout=new AimedSession();timeout.offer(arena(),time);reject(()->timeout.checkDeadline(time+6_000_000_001L),"alignment deadline");
        AimedSession bounded=ready(time);for(int i=0;i<16;i++)check(issue(bounded,time)!=null,"bounded permit accepted");check(bounded.issue(time)==null,"permit capacity16");
        check(issue(bounded,time+AimedSession.PERMIT_LIFETIME_NANOS+1)!=null,"expired permit slots reclaimed");
        AimedSession unsent=ready(time);var queued=unsent.issue(time);reject(()->unsent.receive(request(1,queued.permitId(),1),time),"capture cannot precede permit write");
    }
    private static void await(BooleanSupplier condition,String name) throws Exception {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(4);while(!condition.getAsBoolean() && System.nanoTime()<deadline)Thread.sleep(5);check(condition.getAsBoolean(),name);
    }
    private static Protocol.Frame frame(int type,long seq,byte[] payload){return new Protocol.Frame(type,2,seq,0,payload);}
    private static Protocol.Frame readType(Socket socket,int type) throws Exception {
        for(int i=0;i<100;i++){var message=Protocol.read(socket.getInputStream());if(message.type()==type)return message;}throw new AssertionError("Missing type "+type);
    }
    private static void transport() throws Exception {
        String previous=System.getProperty("minecome.port");Path token=Files.createTempFile("minecome-aim-test-",".token");Files.writeString(token,"0".repeat(64));
        try(ServerSocket server=new ServerSocket(0,1,InetAddress.getByName("127.0.0.1"))){
            System.setProperty("minecome.port",Integer.toString(server.getLocalPort()));AtomicReference<Throwable> error=new AtomicReference<>();
            Thread host=new Thread(()->{try(Socket socket=server.accept()){
                socket.setSoTimeout(4000);var hello=Protocol.read(socket.getInputStream());var identity=Protocol.parseHello(hello.payload());
                if(hello.minor()!=2 || identity.capabilities()!=2 || identity.role()!=2)throw new AssertionError("Expected real-MC opt-in minor2");
                Protocol.write(socket.getOutputStream(),frame(Protocol.HELLO,1,Protocol.hello(new Protocol.Hello(1,2,"aim-fixture",""))));
                Protocol.write(socket.getOutputStream(),frame(Protocol.KCD_POSE,2,Protocol.pose(new Protocol.Pose(new Protocol.Vec3(120,2040,54),arena().kcdAnchor(),new Protocol.Quaternion(0,0,0,1),1,new Protocol.Vec3(0,0,0),1,1,11))));
                var offer=readType(socket,Protocol.ARENA_OFFER);if(!Arrays.equals(offer.payload(),Protocol.aimedArena(arena())))throw new AssertionError("Offer changed");
                Protocol.write(socket.getOutputStream(),frame(Protocol.ARENA_ACK,3,offer.payload()));
                var permit=Protocol.parseAimPermit(readType(socket,Protocol.AIM_PERMIT).payload());
                Protocol.write(socket.getOutputStream(),frame(Protocol.AIMED_STONE_REQUEST,4,Protocol.aimedStoneRequest(request(1,permit.permitId(),1))));
                var result=Protocol.parseAimedStoneResult(readType(socket,Protocol.AIMED_STONE_RESULT).payload());if(result.result()!=1 || result.requestId()!=1)throw new AssertionError("Bad terminal result");
                Protocol.write(socket.getOutputStream(),frame(Protocol.GOODBYE,5,new byte[0]));
            }catch(Throwable failure){error.set(failure);}},"aimed-test-host");host.start();
            var logs=new CopyOnWriteArrayList<String>();
            try(BridgeClient bridge=new BridgeClient(token,"fixture",Protocol.ROLE_MC,logs::add,BridgeClient.Mode.AIMED_STONE)){
                bridge.start();await(bridge::connected,"minor2 authenticated");long session=bridge.status().session();
                check(!bridge.blockEvent(new Protocol.BlockEvent(1,-8,-60,2,"minecraft:stone")),"minor2 events refused before alignment ACK");
                check(bridge.offerAimedArena(arena()),"offer queued through actual socket");await(bridge::aimedArenaReady,"exact ACK marks alignment ready");
                check(bridge.issueAimPermit()!=null,"permit queued through socket");AtomicReference<BridgeClient.AimedEnvelope> input=new AtomicReference<>();
                await(()->{if(input.get()==null)input.set(bridge.pollAimedStoneRequest());return input.get()!=null;},"request arrives with generation envelope");
                check(bridge.aimedInputAvailability(input.get())==0 && input.get().session()==session,"fresh matched request available on client thread");
                check(bridge.sendAimedStoneResult(input.get(),Protocol.AIM_CONFIRMED),"terminal result queued");
                await(()->bridge.lastHostGoodbyeSession()==session,"explicit peer GOODBYE retained");
                await(()->!bridge.connected(),"graceful close drops readiness");check(!bridge.aimedArenaReady() && bridge.pollAimedStoneRequest()==null,"disconnect clears arena and queue");
                check(!bridge.sendAimedStoneResult(input.get(),1),"old session cannot emit terminal result");
            }
            host.join(4500);check(!host.isAlive(),"bounded host fixture ended");if(error.get()!=null)throw new AssertionError("Aimed socket fixture failed",error.get());
        }finally{Files.deleteIfExists(token);if(previous==null)System.clearProperty("minecome.port");else System.setProperty("minecome.port",previous);}
    }
}
