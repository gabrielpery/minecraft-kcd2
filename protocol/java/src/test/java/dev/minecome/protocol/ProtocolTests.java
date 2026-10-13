package dev.minecome.protocol;

import java.io.*;
import java.nio.*;
import java.util.*;

public final class ProtocolTests {
    private static int checks;
    private static void check(boolean condition,String name) { checks++; if(!condition)throw new AssertionError(name); }
    private static void reject(byte[] wire,String name) throws Exception {
        try { Protocol.decode(wire); throw new AssertionError("Accepted "+name); } catch(IOException expected){checks++;}
    }
    private static void close(double a,double b) { check(Math.abs(a-b)<1e-9,"coordinate round trip"); }
    public static void main(String[] args) throws Exception {
        var hello=new Protocol.Hello(2,0,"MineCome λ","0".repeat(64));
        byte[] wire=Protocol.encode(new Protocol.Frame(1,1,123,Protocol.hello(hello)));
        check(wire[0]=='M' && wire[4]==1 && wire[8]==1 && wire[16]==1,"little-endian header offsets");
        check(Protocol.parseHello(Protocol.decode(wire).payload()).equals(hello),"UTF-8 Hello round trip");
        var helloBoundary=new Protocol.Hello(1,0,"λ".repeat(64),"a".repeat(128));
        check(Protocol.parseHello(Protocol.hello(helloBoundary)).equals(helloBoundary),"Hello UTF-8 byte bounds");
        for(String invalidName:List.of("","a".repeat(129),"\uD800")) {
            try{Protocol.hello(new Protocol.Hello(1,0,invalidName,""));throw new AssertionError("Invalid Hello name accepted");}
            catch(IllegalArgumentException expected){checks++;}
        }
        try{Protocol.hello(new Protocol.Hello(1,0,"host","a".repeat(129)));throw new AssertionError("Long credential accepted");}
        catch(IllegalArgumentException expected){checks++;}
        byte[] emptyName=ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN).putInt(1).putInt(0).putShort((short)0).putShort((short)0).array();
        try{Protocol.parseHello(emptyName);throw new AssertionError("Empty wire name accepted");}catch(IOException expected){checks++;}
        byte[] malformedName=ByteBuffer.allocate(13).order(ByteOrder.LITTLE_ENDIAN).putInt(1).putInt(0).putShort((short)1).putShort((short)0).put((byte)0x80).array();
        try{Protocol.parseHello(malformedName);throw new AssertionError("Malformed UTF-8 accepted");}catch(IOException expected){checks++;}
        var fragmented=new Protocol.Reader();
        var queue=new ByteArrayOutputStream();
        InputStream incremental=new InputStream(){int offset; public int available(){return queue.size()-offset;}
            public int read(){byte[] b=queue.toByteArray(); return offset<b.length?Byte.toUnsignedInt(b[offset++]):-1;}};
        Protocol.Frame frame=null;
        for(int i=0;i<wire.length;i++){queue.write(wire[i]);frame=fragmented.poll(incremental); if(i<wire.length-1)check(frame==null,"fragmented frame delayed");}
        check(frame!=null && frame.sequence()==1,"fragmented frame assembled");
        byte[] bad=wire.clone(); bad[0]=0; reject(bad,"magic");
        bad=wire.clone(); bad[4]=2; reject(bad,"major version");
        bad=wire.clone(); bad[6]=3; reject(bad,"unsupported minor version");
        bad=wire.clone(); bad[10]=1; reject(bad,"reserved flags");
        bad=wire.clone(); ByteBuffer.wrap(bad).order(ByteOrder.LITTLE_ENDIAN).putInt(12,65537);reject(bad,"oversize");
        bad=wire.clone(); ByteBuffer.wrap(bad).order(ByteOrder.LITTLE_ENDIAN).putLong(16,0);reject(bad,"zero sequence");
        reject(Arrays.copyOf(wire,wire.length-1),"truncated payload");
        var p=new Protocol.Pose(new Protocol.Vec3(10,20,30),new Protocol.Vec3(11,22,33),new Protocol.Quaternion(0,0,0,1),
                1.2,new Protocol.Vec3(100,200,300),2,1,15);
        check(Protocol.pose(p).length==128,"pose size");
        check(Protocol.parsePose(Protocol.pose(p)).equals(p),"pose round trip");
        byte[] invalid=Protocol.pose(p);ByteBuffer.wrap(invalid).order(ByteOrder.LITTLE_ENDIAN).putDouble(0,Double.NaN);
        try{Protocol.parsePose(invalid);throw new AssertionError("NaN accepted");}catch(IOException expected){checks++;}
        var event=new Protocol.BlockEvent(2,-2147483648,64,2147483647,"minecraft:stone");
        check(Protocol.parseBlockEvent(Protocol.blockEvent(event)).equals(event),"block event integer bounds");
        var pathId=new Protocol.BlockEvent(1,0,0,0,"minecraft:folder/stone");
        check(Protocol.parseBlockEvent(Protocol.blockEvent(pathId)).equals(pathId),"registry path slash valid");
        try{Protocol.blockEvent(new Protocol.BlockEvent(1,0,0,0,"mine/craft:stone"));throw new AssertionError("namespace slash accepted");}
        catch(IllegalArgumentException expected){checks++;}
        try{Protocol.toMinecraft(p.player(),p.kcdOrigin(),Double.NaN);throw new AssertionError("NaN scale accepted");}
        catch(IllegalArgumentException expected){checks++;}
        try{new Protocol.Pose(p.player(),p.camera(),p.orientation(),p.verticalFov(),p.kcdOrigin(),1,1,16);throw new AssertionError("unknown pose flag accepted");}
        catch(IllegalArgumentException expected){checks++;}
        Random r=new Random(42); var origin=new Protocol.Vec3(512,600,23);
        for(int i=0;i<1000;i++){
            var v=new Protocol.Vec3(r.nextDouble()*1e5,r.nextDouble()*1e5,r.nextDouble()*1e5);
            var back=Protocol.toKcd(Protocol.toMinecraft(v,origin,2.5),origin,2.5);
            close(v.x(),back.x());close(v.y(),back.y());close(v.z(),back.z());
        }
        double half=Math.sqrt(0.5);
        var kcdNorthCamera=new Protocol.Quaternion(half,0,0,half);
        var mcNorthCamera=Protocol.toMinecraftOrientation(kcdNorthCamera);
        close(mcNorthCamera.x(),0);close(mcNorthCamera.y(),0);close(mcNorthCamera.z(),0);close(mcNorthCamera.w(),1);
        var restored=Protocol.toKcdOrientation(Protocol.toMinecraftOrientation(p.orientation()));
        close(restored.x(),p.orientation().x());close(restored.y(),p.orientation().y());
        close(restored.z(),p.orientation().z());close(restored.w(),p.orientation().w());
        checks+=AimedProtocolTests.run();
        checks+=StoneInputTests.run();
        checks+=BridgeClientTests.run();
        System.out.println("PASS Java protocol: "+checks+" checks");
    }
}
