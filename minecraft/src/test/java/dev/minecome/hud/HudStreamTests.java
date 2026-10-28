package dev.minecome.hud;

import com.google.gson.*;
import com.sun.jna.Pointer;
import com.sun.jna.platform.win32.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;

/** Binary contract plus actual Windows named-object lifecycle; no Minecraft or KCD launched. */
public final class HudStreamTests {
    private static int checks;
    private static void check(boolean value,String reason){checks++;if(!value)throw new AssertionError(reason);}
    private static void rejects(Runnable action,String reason){try{action.run();throw new AssertionError(reason);}catch(IllegalArgumentException expected){checks++;}}
    private static void waitFor(java.util.function.BooleanSupplier done,String reason)throws Exception {long limit=System.nanoTime()+3_000_000_000L;while(!done.getAsBoolean() && System.nanoTime()<limit)Thread.sleep(5);check(done.getAsBoolean(),reason);}
    private static HudStreamProducer producer(Path root,Path parent,String child,HudStreamProducer.Identity id){return new HudStreamProducer(root,parent.resolve(child),id,"MineCome-HudStream-"+UUID.randomUUID(),false);}
    private static HudStreamProducer.Frame frame(long time){return new HudStreamProducer.Frame(2,1,new byte[]{64,0,0,(byte)128,0,0,0,0},time,1,0,"{\"state\":\"fixture\"}");}
    public static void main(String[] args)throws Exception {
        sampleStates();
        var layout=HudStreamLayout.configured();
        check(layout.width()==1280 && layout.height()==720 && layout.guiScale()==2,"stream default1280x720 GUI2");
        check(layout.width()/layout.guiScale()==640 && layout.height()/layout.guiScale()==360,"vanilla logical canvas independent of host fit");
        check(new HudStreamLayout(1920,1080,4).guiScale()==4,"bounded explicit GUI scale");
        rejects(()->new HudStreamLayout(1921,1080,2),"oversized capture");
        rejects(()->new HudStreamLayout(640,480,3),"GUI scale below vanilla minimum canvas");
        rejects(()->new HudStreamLayout(1280,720,0),"automatic GUI scale refused");
        var id=new HudStreamProducer.Identity("0123456789abcdef0123456789abcdef",123,0x0102030405060708L,1_800_000_000_000L);
        byte[] bytes=HudStreamProducer.header(id,456,0x1122334455667788L,9,1_700_000_000_000L,2,1,3,1,1);
        var b=ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
        check(bytes.length==256,"header size");check(new String(bytes,0,8,java.nio.charset.StandardCharsets.US_ASCII).equals("MCHUDS01"),"magic");
        check(b.getInt(8)==1 && b.getInt(12)==256,"schema/layout");check(b.getInt(48)==456 && b.getInt(52)==123,"PIDs");
        check(b.getLong(56)==0x1122334455667788L && b.getLong(64)==id.targetStart(),"exact FILETIMEs");
        check(b.getLong(72)==id.expiresUtcMs() && b.getLong(80)==9 && b.getLong(88)==1_700_000_000_000L,"lease/sequence/time");
        check(b.getInt(96)==2 && b.getInt(100)==1 && b.getInt(104)==8 && b.getInt(108)==8,"dimensions");
        check(b.getInt(112)==1 && b.getInt(116)==1 && b.getInt(120)==3 && b.getInt(124)==1,"format/state/slot/screen");
        for(int i=128;i<256;i++)check(bytes[i]==0,"zero reserved bytes");
        var waiting=ByteBuffer.wrap(HudStreamProducer.header(id,456,88,0,0,0,0,0,0,0)).order(ByteOrder.LITTLE_ENDIAN);
        check(waiting.getLong(80)==0 && waiting.getLong(88)==0 && waiting.getInt(96)==0 && waiting.getInt(108)==0,"waiting fields zero");
        rejects(()->new HudStreamProducer.Identity("BAD",1,1,1),"invalid run");rejects(()->new HudStreamProducer.Identity(id.run(),0,1,1),"zero pid");
        rejects(()->HudStreamProducer.header(id,1,1,0,1,1,1,0,0,1),"zero frame sequence");
        rejects(()->new HudStreamProducer.Frame(1,1,new byte[3],1,0,0,"{}"),"incorrect pixels");
        rejects(()->new HudStreamProducer.Frame(1,1,new byte[4],1,9,0,"{}"),"invalid selected slot");
        Path root=Path.of("..").toAbsolutePath().normalize(), evidence=root.resolve("runtime/evidence");Files.createDirectories(evidence);
        Path parent=Files.createDirectory(evidence.resolve("hud-stream-java-tests-"+UUID.randomUUID()));
        var liveId=new HudStreamProducer.Identity(UUID.randomUUID().toString().replace("-",""),123,123456789,System.currentTimeMillis()+30_000);
        var p=producer(root,parent,"success",liveId);p.start();waitFor(p::isReady,"worker ready");
        JsonObject ready=JsonParser.parseString(Files.readString(parent.resolve("success/stream-ready.json"))).getAsJsonObject();
        check(ready.get("producer_pid").getAsInt()==ProcessHandle.current().pid(),"actual producer pid");
        Kernel32 api=Kernel32.INSTANCE;
        var creation=new WinBase.FILETIME();check(api.GetProcessTimes(api.GetCurrentProcess(),creation,new WinBase.FILETIME(),new WinBase.FILETIME(),new WinBase.FILETIME()),"native process time");
        long actual=(Integer.toUnsignedLong(creation.dwHighDateTime)<<32)|Integer.toUnsignedLong(creation.dwLowDateTime);
        check(ready.get("producer_start_filetime").getAsString().equals(Long.toUnsignedString(actual)),"exact native producer time");
        WinNT.HANDLE map=api.OpenFileMapping(WinNT.FILE_MAP_READ,false,liveId.mappingName());check(map!=null,"mapping opens");
        Pointer view=api.MapViewOfFile(map,WinNT.FILE_MAP_READ,0,0,HudStreamProducer.MAPPING_BYTES);check(view!=null,"mapping view opens");
        // Opening via CreateMutex is a fixture API convenience; it must already exist.
        WinNT.HANDLE mutex=api.CreateMutex(null,false,liveId.mutexName());check(api.GetLastError()==WinError.ERROR_ALREADY_EXISTS,"mutex exists");
        try {
            check(api.WaitForSingleObject(mutex,5)==WinBase.WAIT_OBJECT_0,"reader owns mutex");
            try {check(view.getInt(116)==0,"initial waiting state");}finally{api.ReleaseMutex(mutex);}
            p.offer(frame(System.currentTimeMillis()));waitFor(()->p.publishedFrames()==1,"first publication");
            check(api.WaitForSingleObject(mutex,5)==WinBase.WAIT_OBJECT_0,"read lock");
            try {
                check(view.getInt(116)==1 && view.getLong(80)==1,"published frame identity");
                check((view.getByte(256)&255)==128 && (view.getByte(259)&255)==128,"worker straight-alpha conversion");
                check(view.getByte(260)==0 && view.getByte(263)==0,"zero alpha pixels clear");
            }finally{api.ReleaseMutex(mutex);}
            var collision=producer(root,parent,"collision",liveId);collision.start();waitFor(collision::isFinished,"collision ends");
            check(collision.failure()!=null && collision.failure().contains("existing"),"existing mapping refused");
            check(api.WaitForSingleObject(mutex,5)==WinBase.WAIT_OBJECT_0,"busy fixture lock");
            try {p.offer(frame(System.currentTimeMillis()));Thread.sleep(70);check(p.publishedFrames()==1,"busy producer skips bounded wait");}finally{api.ReleaseMutex(mutex);}
            p.offer(frame(System.currentTimeMillis()-2000));Thread.sleep(70);check(p.publishedFrames()==1,"stale capture dropped");
            p.offer(frame(System.currentTimeMillis()));waitFor(()->p.publishedFrames()==2,"resume after busy");
            p.finish("fixture",null);check(p.awaitFinished(3000),"worker finishes");check(p.failure()==null,"worker success");
            check(view.getInt(116)==2 && view.getLong(80)==2,"closed retains final sequence");
            var result=JsonParser.parseString(Files.readString(parent.resolve("success/stream-result.json"))).getAsJsonObject();
            check(result.get("closed_published").getAsBoolean() && result.get("mapping_handle_closed").getAsBoolean() && result.get("mutex_handle_closed").getAsBoolean(),"terminal cleanup receipt");
            check(result.get("published_frames").getAsInt()==2 && result.get("samples").getAsJsonArray().size()==1,"bounded samples and actual frame count");
        }finally{p.close();p.awaitFinished(3000);api.UnmapViewOfFile(view);api.CloseHandle(mutex);api.CloseHandle(map);}
        var noMapping=api.OpenFileMapping(WinNT.FILE_MAP_READ,false,liveId.mappingName());check(noMapping==null,"all mapping handles released");if(noMapping!=null)api.CloseHandle(noMapping);
        mouseModeReceipts(root,parent);
        stoneModeReceipts(root,parent);
        System.out.println("HudStreamTests: "+checks+" checks passed; original Win32 transport fixture, no games launched; evidence="+parent);
    }
    private static void mouseModeReceipts(Path root,Path parent)throws Exception {
        String previous=System.getProperty("minecome.hudStreamLiveMouse");
        try{
            for(int variant=0;variant<3;variant++){
                boolean live=variant==2;int mode=variant==1?2:1;
                if(live)System.setProperty("minecome.hudStreamLiveMouse","true");else System.clearProperty("minecome.hudStreamLiveMouse");
                String child="mouse-mode-"+variant;var id=new HudStreamProducer.Identity(UUID.randomUUID().toString().replace("-",""),123,123456789,System.currentTimeMillis()+10_000);
                var producer=new HudStreamProducer(root,parent.resolve(child),id,"MineCome-HudStream-"+UUID.randomUUID(),false,mode);
                try{
                    producer.start();waitFor(producer::isReady,"mouse mode receipt worker ready");
                    var ready=JsonParser.parseString(Files.readString(parent.resolve(child+"/stream-ready.json"))).getAsJsonObject();
                    check(ready.get("ui_input_live_mouse").getAsJsonPrimitive().isBoolean() && ready.get("ui_input_live_mouse").getAsBoolean()==live,"ready receipt records explicit live mouse mode");
                    check(ready.get("ui_input_fixture").getAsBoolean()==(mode==2),"fixture identity stays separate from live opt-in");
                    check(!ready.get("ui_input_stone_live").getAsBoolean() && !ready.get("ui_input_stone_bridge").getAsBoolean(),"ordinary input does not opt into stone live mode");
                    producer.finish("fixture",null);check(producer.awaitFinished(3000) && producer.failure()==null,"transport-only mode check closes normally");
                    var terminal=JsonParser.parseString(Files.readString(parent.resolve(child+"/stream-result.json"))).getAsJsonObject();
                    check(terminal.get("ui_input_live_mouse").getAsBoolean()==live && terminal.get("result").getAsString().equals("fixture"),"terminal keeps mode without claiming actual game input");
                }finally{producer.close();producer.awaitFinished(3000);}
            }
            var id=new HudStreamProducer.Identity(UUID.randomUUID().toString().replace("-",""),123,123456789,System.currentTimeMillis()+10_000);
            String save="MineCome-HudStream-"+UUID.randomUUID();
            rejects(()->new HudStreamProducer(root,parent.resolve("invalid-ordinary"),id,save,false,0),"forced live mouse rejects non-input producer");
            rejects(()->new HudStreamProducer(root,parent.resolve("invalid-fixture"),id,save,false,2),"forced live mouse rejects fixture producer");
            check(!Files.exists(parent.resolve("invalid-ordinary")) && !Files.exists(parent.resolve("invalid-fixture")),"invalid forced modes create no output/session");
        }finally{if(previous==null)System.clearProperty("minecome.hudStreamLiveMouse");else System.setProperty("minecome.hudStreamLiveMouse",previous);}
    }
    private static void sampleStates()throws Exception {
        var combined=new HashSet<String>();
        for(String phase:List.of("settling","inventory_blocked","hotbar_ready","scripted_walking","aimed_interactions",
                "extended_wait","post_walk_inventory_blocked","final_settling","cleanup")){
            String stage="fixture_"+phase;
            check(HudStreamProducer.recordSampleState(combined,stage,true),"Complete combined sequence retains one image per observed phase including cleanup");
            check(!HudStreamProducer.recordSampleState(combined,stage,true),"Repeated phase does not retain additional pixels");
        }
        check(combined.size()==9,"Combined evidence remains bounded to exactly nine possible states");
        try{HudStreamProducer.recordSampleState(combined,"fixture_unknown",true);throw new AssertionError("Accepted unknown combined phase");}
        catch(java.io.IOException expected){checks++;}
        check(combined.size()==9,"Rejected combined phase is never retained");
        var regular=new HashSet<String>();
        for(int i=0;i<8;i++)check(HudStreamProducer.recordSampleState(regular,"state_"+i,false),"Existing mode preserves eight-image budget");
        try{HudStreamProducer.recordSampleState(regular,"state_8",false);throw new AssertionError("Accepted ninth ordinary state");}
        catch(java.io.IOException expected){checks++;}
        check(regular.size()==8,"Ordinary over-budget state is rejected before retention");
        for(String invalid:List.of("../escape","","X")){
            try{HudStreamProducer.recordSampleState(new HashSet<>(),invalid,false);throw new AssertionError("Accepted malformed state");}
            catch(java.io.IOException expected){checks++;}
        }
    }
    private static void stoneModeReceipts(Path root,Path parent)throws Exception {
        String[] properties={"minecome.hudStoneBridge","minecome.hudStoneFixture","minecome.hudStoneLive","minecome.hudStreamLiveMouse","minecome.hudStreamOffscreenPresentation","minecome.hudStreamOffscreenTrial"};
        var previous=new HashMap<String,String>();for(String key:properties)previous.put(key,System.getProperty(key));
        try{
            for(boolean live:new boolean[]{false,true}){
                for(String key:properties)System.clearProperty(key);
                System.setProperty("minecome.hudStoneBridge","true");System.setProperty("minecome.hudStreamOffscreenPresentation","true");
                System.setProperty(live?"minecome.hudStoneLive":"minecome.hudStoneFixture","true");
                System.setProperty(live?"minecome.hudStreamLiveMouse":"minecome.hudStreamOffscreenTrial","true");
                String child=live?"stone-live-mode":"stone-fixture-mode";
                var id=new HudStreamProducer.Identity(UUID.randomUUID().toString().replace("-",""),123,123456789,System.currentTimeMillis()+10_000);
                var producer=new HudStreamProducer(root,parent.resolve(child),id,"MineCome-HudStream-"+UUID.randomUUID(),false,live?1:2);
                try{
                    producer.start();waitFor(producer::isReady,"stone mode transport ready");
                    var ready=JsonParser.parseString(Files.readString(parent.resolve(child+"/stream-ready.json"))).getAsJsonObject();
                    check(ready.get("ui_input_stone_bridge").getAsBoolean(),"stone bridge opt-in emitted");
                    check(ready.get("ui_input_stone_live").getAsJsonPrimitive().isBoolean() && ready.get("ui_input_stone_live").getAsBoolean()==live,"live stone mode remains explicit");
                    check(ready.get("ui_input_stone_fixture").getAsBoolean()!=live && ready.get("ui_input_fixture").getAsBoolean()!=live,"standalone identity remains separate");
                    producer.finish("fixture",null);check(producer.awaitFinished(3000) && producer.failure()==null,"stone marker transport closes without claiming games");
                    var terminal=JsonParser.parseString(Files.readString(parent.resolve(child+"/stream-result.json"))).getAsJsonObject();
                    check(terminal.get("ui_input_stone_live").getAsBoolean()==live && terminal.get("result").getAsString().equals("fixture"),"terminal retains stone marker");
                }finally{producer.close();producer.awaitFinished(3000);}
            }
            System.setProperty("minecome.hudStoneFixture","true");
            var id=new HudStreamProducer.Identity(UUID.randomUUID().toString().replace("-",""),123,123456789,System.currentTimeMillis()+10_000);
            rejects(()->new HudStreamProducer(root,parent.resolve("invalid-stone-mixed"),id,"MineCome-HudStream-"+UUID.randomUUID(),false,1),"mixed fixture/live stone producer refused");
            check(!Files.exists(parent.resolve("invalid-stone-mixed")),"mixed stone modes create no output or session");
        }finally{for(String key:properties){if(previous.get(key)==null)System.clearProperty(key);else System.setProperty(key,previous.get(key));}}
    }
}
