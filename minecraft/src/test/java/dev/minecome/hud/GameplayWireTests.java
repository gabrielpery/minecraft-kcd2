package dev.minecome.hud;

import dev.minecome.gameplay.GameplayMode;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.Properties;

public final class GameplayWireTests {
    private static int checks;
    private static void check(boolean ok){checks++;if(!ok)throw new AssertionError("Gameplay wire check "+checks);}
    private static void rejects(Runnable call){boolean rejected=false;try{call.run();}catch(IllegalArgumentException e){rejected=true;}check(rejected);}
    public static void main(String[] args){
        String run="0123456789abcdef0123456789abcdef";
        var stream=new HudStreamProducer.Identity(run,12,56,100_000);
        byte[] legacy=HudStreamProducer.header(stream,11,34,1,1000,320,240,0,0,1);
        byte[] gameplay=HudStreamProducer.header(stream,11,34,1,1000,320,240,0,0,1,3);
        check(new String(legacy,0,8,StandardCharsets.US_ASCII).equals("MCHUDS01"));
        check(new String(gameplay,0,8,StandardCharsets.US_ASCII).equals("MCHUDS03"));
        check(ByteBuffer.wrap(gameplay).order(ByteOrder.LITTLE_ENDIAN).getInt(8)==3);
        rejects(()->HudStreamProducer.header(stream,11,34,1,1000,320,240,0,0,1,2));
        var id=new HudInputProtocol.Identity(run,11,34,12,56,100_000);
        var b=ByteBuffer.allocate(HudInputProtocol.MAPPING_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.put("MCHUDI03".getBytes(StandardCharsets.US_ASCII)).putInt(3).putInt(HudInputProtocol.MAPPING_BYTES);
        b.put(run.getBytes(StandardCharsets.US_ASCII)).putInt(11).putInt(12).putLong(34).putLong(56).putLong(100_000);
        b.putLong(0).putLong(1000).putInt(1).putInt(0);
        check(HudInputProtocol.decode(b.array(),id,0,1000,0,false,true).hostState()==1);
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,false));
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,true));
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1251,0,false,true));
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,true,true));
        b.put(7,(byte)'4');b.putInt(8,4);
        check(HudInputProtocol.decode(b.array(),id,0,1000,0,true,true).hostState()==1);
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,false,true));
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,true,false));
        b.putLong(80,1);b.putInt(100,1);
        b.position(HudInputProtocol.HEADER_BYTES);b.putLong(1).putLong(1000).putInt(1).putInt(0x57);
        check(HudInputProtocol.decode(b.array(),id,0,1000,0,true,true).events().getFirst().code()==0x57);
        rejects(()->HudInputProtocol.validateEvent(new HudInputProtocol.Event(1,1000,1,0x57,0,0,0),1000,true,false));
        b.putLong(80,0);b.putInt(100,0);
        b.put(7,(byte)'1');b.putInt(8,1);
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,false,true));
        check(HudInputProtocol.decode(b.array(),id,0,1000,0,false).hostState()==1);
        Properties p=new Properties();p.setProperty("minecome.gameplay","true");
        p.setProperty("minecome.gameplayStandalone","true");p.setProperty("minecome.gameplayFixture","create");
        GameplayMode.requireExclusive(p);check(true);
        p.setProperty("minecome.hudStreamLab","true");rejects(()->GameplayMode.requireExclusive(p));
        check(GameplayMode.MAX_LEASE_MS==86_400_000L);
        worldButtons(id);
        chat(id);
        nativeViewAdmission();
        cameraCaptureCadence();
        System.out.println("GameplayWireTests: "+checks+" checks passed; no games");
    }
    private static void cameraCaptureCadence(){
        var cadence=new GameplayCaptureCadence();long start=1_000_000_000L;
        check(cadence.ready(start,0));cadence.captured(start,1000);
        check(!cadence.ready(start+24_999_999L,1020));
        check(cadence.ready(start+25_000_000L,1020)); // Fresh view wins before the next ordinary HUD capture.
        check(!cadence.ready(start+25_000_000L,1000));
        check(!cadence.ready(start+25_000_000L,999)); // Regressed camera cannot request the faster cadence.
        check(!cadence.ready(start+25_000_000L,0)); // UI-only/missing camera keeps the existing cadence.
        check(cadence.ready(start+50_000_000L,0));
        // Simulate a busy readback: checking readiness consumes neither the
        // camera identity nor the interval; the following frame can retry.
        check(cadence.ready(start+26_000_000L,1020));cadence.captured(start+26_000_000L,1020);
        check(!cadence.ready(start+50_000_000L,1030));
        check(cadence.ready(start+51_000_000L,1030));
        check(!cadence.ready(start+75_999_999L,1020));
        check(cadence.ready(start+76_000_000L,1020));cadence.captured(start+76_000_000L,0);
        check(!cadence.ready(start+101_000_000L,1020)); // Missing-camera capture cannot make the old view new again.
        check(cadence.ready(start+101_000_000L,1030));
        check(!cadence.ready(start+75_000_000L,1030)); // Monotonic clock regression never bypasses the gate.
    }
    private static void nativeViewAdmission(){
        var origin=net.minecraft.util.math.Vec3d.ZERO;
        var direction=new net.minecraft.util.math.Vec3d(1,0,0);
        var up=new net.minecraft.util.math.Vec3d(0,1,0);
        var tick=new dev.minecome.gameplay.GameplayAimReader.RenderSample(
            new dev.minecome.gameplay.GameplayBlocks.Aim(1000,1_000_000_000L,origin,direction,4.5,true,-1,false),
            new GameplayWorldRenderer.View(origin,direction,up,1.2),1,3);
        var newer=new dev.minecome.gameplay.GameplayAimReader.RenderSample(
            new dev.minecome.gameplay.GameplayBlocks.Aim(1020,1_020_000_000L,origin,direction,4.5,true,-1,false),
            new GameplayWorldRenderer.View(origin,direction,up,1.2),2,3);
        var admission=new GameplayNativeViewAdmission();
        var applied=new java.util.concurrent.atomic.AtomicReference<dev.minecome.gameplay.GameplayAimReader.RenderSample>();
        admission.admit(tick,1005,1_005_000_000L,applied::set);
        check(admission.current()==tick&&applied.get().perspective()==1);
        // Native publication arrives between ticks: the next render must use it
        // immediately, with matching perspective/aim and the original source age.
        admission.beginFrame(newer,1025,1_025_000_000L,applied::set);
        check(admission.current()==newer&&applied.get()==newer&&applied.get().perspective()==2);
        check(admission.frame(1049,1_049_000_000L)==newer&&admission.frame(1049,1_049_000_000L).aim().capturedUtcMs()==1020);
        boolean blocked=false;try{admission.admit(tick,1030,1_030_000_000L,applied::set);}catch(IllegalStateException e){blocked=true;}
        check(blocked&&applied.get()==newer&&admission.frame(1049,1_049_000_000L)==newer);
        check(admission.frame(1321,1_050_000_000L)==null); // Original UTC expires even inside a frame.
        check(admission.frame(1050,1_320_000_001L)==null); // Independent monotonic expiry remains.
        admission.endFrame();check(admission.frame(1050,1_050_000_000L)==null);
        admission.beginFrame(newer,1321,1_321_000_000L,applied::set);
        check(admission.current()==null&&applied.get()==null&&admission.frame(1321,1_321_000_000L)==null);
        admission.endFrame();admission.admit(tick,1005,1_005_000_000L,applied::set);
        admission.beginFrame(null,1010,1_010_000_000L,applied::set);
        check(admission.current()==null&&applied.get()==null&&admission.frame(1010,1_010_000_000L)==null);
        admission.endFrame();admission.admit(tick,1005,1_005_000_000L,applied::set);
        boolean rejected=false;try{admission.beginFrame(newer,1025,1_025_000_000L,s->{throw new IllegalStateException("client application failed");});}catch(IllegalStateException e){rejected=true;}
        check(rejected&&admission.current()==tick&&admission.frame(1025,1_025_000_000L)==null);
    }
    private static void worldButtons(HudInputProtocol.Identity id){
        var b=ByteBuffer.allocate(HudInputProtocol.MAPPING_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.put("MCHUDI05".getBytes(StandardCharsets.US_ASCII)).putInt(5).putInt(HudInputProtocol.MAPPING_BYTES);
        b.put(id.run().getBytes(StandardCharsets.US_ASCII)).putInt(id.producerPid()).putInt(id.targetPid()).putLong(id.producerStart()).putLong(id.targetStart()).putLong(id.expires());
        b.putLong(2).putLong(1000).putInt(1).putInt(2);
        b.position(HudInputProtocol.HEADER_BYTES);
        b.putLong(1).putLong(1000).putInt(7).putInt(1).putFloat(0).putFloat(0).putInt(0).putInt(0);
        b.putLong(2).putLong(1000).putInt(8).putInt(1).putFloat(0).putFloat(0).putInt(0).putInt(0);
        var snapshot=HudInputProtocol.decode(b.array(),id,0,1000,0,true,true,true);
        check(snapshot.events().size()==2&&snapshot.events().getFirst().kind()==7&&snapshot.events().getLast().kind()==8);
        for(boolean movement:new boolean[]{false,true})for(boolean gameplay:new boolean[]{false,true}){
            rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,movement,gameplay,false));
            if(!movement||!gameplay)rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,movement,gameplay,true));
        }
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1251,0,true,true,true));
        for(int code=0;code<2;code++)for(int kind=7;kind<=8;kind++){
            var event=new HudInputProtocol.Event(1,1000,kind,code,0,0,0);
            HudInputProtocol.validateEvent(event,1250,true,true,true);check(true);
            rejects(()->HudInputProtocol.validateEvent(event,1251,true,true,true));
            rejects(()->HudInputProtocol.validateEvent(event,1000,true,true,false));
        }
        for(var event:new HudInputProtocol.Event[]{
            new HudInputProtocol.Event(1,1000,7,2,0,0,0),new HudInputProtocol.Event(1,1000,7,0,.1f,0,0),
            new HudInputProtocol.Event(1,1000,8,1,0,.1f,0),new HudInputProtocol.Event(1,1000,8,1,0,0,1),
            new HudInputProtocol.Event(1,1000,9,0,0,0,0),new HudInputProtocol.Event(1,1000,7,-1,0,0,0)})
            rejects(()->HudInputProtocol.validateEvent(event,1000,true,true,true));
        var gate=new HudInputGate(true,true);
        gate.apply(new HudInputProtocol.Event(1,1000,7,0,0,0,0),1000);
        gate.apply(new HudInputProtocol.Event(2,1000,4,0,.5f,.5f,0),1000);
        check(gate.heldButtonCount()==2); // Inventory and world channels cannot consume each other's release.
        gate.apply(new HudInputProtocol.Event(3,1000,8,0,0,0,0),1000);check(gate.heldButtonCount()==1);
        rejects(()->gate.apply(new HudInputProtocol.Event(4,1000,8,0,0,0,0),1000));
        gate.apply(new HudInputProtocol.Event(4,1000,5,0,.5f,.5f,0),1000);check(gate.heldButtonCount()==0);
        gate.apply(new HudInputProtocol.Event(5,1000,7,1,0,0,0),1000);
        rejects(()->gate.apply(new HudInputProtocol.Event(6,1000,7,1,0,0,0),1000));
        rejects(()->gate.apply(new HudInputProtocol.Event(7,1000,8,1,0,0,0),1000));
        gate.apply(new HudInputProtocol.Event(6,1000,1,'W',0,0,0),1000);
        gate.releaseAll();check(gate.heldButtonCount()==0&&gate.heldKeyCount()==0&&gate.sequence()==6);
        for(var old:new HudInputGate[]{new HudInputGate(),new HudInputGate(true)})rejects(()->old.apply(new HudInputProtocol.Event(1,1000,7,0,0,0,0),1000));
        b.putInt(96,2);
        check(HudInputProtocol.decode(b.array(),id,0,3000,1,true,true,true).events().isEmpty());
    }
    private static void chat(HudInputProtocol.Identity id){
        var b=ByteBuffer.allocate(HudInputProtocol.MAPPING_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.put("MCHUDI06".getBytes(StandardCharsets.US_ASCII)).putInt(6).putInt(HudInputProtocol.MAPPING_BYTES);
        b.put(id.run().getBytes(StandardCharsets.US_ASCII)).putInt(id.producerPid()).putInt(id.targetPid()).putLong(id.producerStart()).putLong(id.targetStart()).putLong(id.expires());
        b.putLong(3).putLong(1000).putInt(1).putInt(3);
        b.putLong(128,3).putLong(136,1000).putInt(144,1).putInt(148,2);
        b.position(HudInputProtocol.HEADER_BYTES);
        b.putLong(1).putLong(1000).putInt(9).putInt(0x1f642).putFloat(0).putFloat(0).putInt(0).putInt(0);
        b.putLong(2).putLong(1000).putInt(10).putInt(13).putFloat(0).putFloat(0).putInt(0).putInt(0);
        b.putLong(3).putLong(1000).putInt(11).putInt(13).putFloat(0).putFloat(0).putInt(0).putInt(0);
        var snapshot=HudInputProtocol.decode(b.array(),id,0,1000,0,true,true,true,true);
        check(snapshot.events().size()==3&&snapshot.events().getFirst().code()==0x1f642&&snapshot.events().getLast().kind()==11);
        check(HudInputProtocol.decode(b.array(),id,3,1000,1,true,true,true,true).events().isEmpty());
        for(boolean movement:new boolean[]{false,true})for(boolean gameplay:new boolean[]{false,true})for(boolean blocks:new boolean[]{false,true}){
            rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,movement,gameplay,blocks,false));
            if(!movement||!gameplay||!blocks)rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,movement,gameplay,blocks,true));
        }
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1251,0,true,true,true,true));
        b.putInt(148,3);rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,true,true,true,true));b.putInt(148,2);
        b.putInt(HudInputProtocol.HEADER_BYTES+36,1);rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,true,true,true,true));b.putInt(HudInputProtocol.HEADER_BYTES+36,0);
        for(int code:new int[]{0x20,'/','T',0x7e,0xa0,0xd7ff,0xe000,0x1f642,0x10ffff}){
            var e=new HudInputProtocol.Event(1,1000,9,code,0,0,0);
            HudInputProtocol.validateEvent(e,1000,true,true,true,true);check(Character.codePointAt(GameplayChatInput.characters(code),0)==code);
            rejects(()->HudInputProtocol.validateEvent(e,1000,true,true,true));
        }
        for(int code:new int[]{-1,0,0x1f,0x7f,0x80,0x9f,0xd800,0xdbff,0xdc00,0xdfff,0x110000,Integer.MAX_VALUE}){
            rejects(()->GameplayChatInput.characters(code));
            rejects(()->HudInputProtocol.validateEvent(new HudInputProtocol.Event(1,1000,9,code,0,0,0),1000,true,true,true,true));
        }
        for(int code:new int[]{8,9,13,27,35,36,37,38,39,40,46})for(int kind:new int[]{10,11}){
            HudInputProtocol.validateEvent(new HudInputProtocol.Event(1,1000,kind,code,0,0,0),1000,true,true,true,true);check(GameplayChatInput.glfw(code)>=256);
        }
        for(int code:new int[]{0,16,17,18,32,45,47,65,0xbf}){
            rejects(()->GameplayChatInput.glfw(code));
            rejects(()->HudInputProtocol.validateEvent(new HudInputProtocol.Event(1,1000,10,code,0,0,0),1000,true,true,true,true));
        }
        for(int code:new int[]{0x54,0xbf,0x10,0x11,0x74})for(int kind:new int[]{1,2}){
            var event=new HudInputProtocol.Event(1,1000,kind,code,0,0,0);
            HudInputProtocol.validateEvent(event,1000,true,true,true,true);check(true);
            rejects(()->HudInputProtocol.validateEvent(event,1000,true,true,true));
        }
        for(var event:new HudInputProtocol.Event[]{new HudInputProtocol.Event(1,1000,9,'a',.1f,0,0),new HudInputProtocol.Event(1,1000,9,'a',0,0,1),
                new HudInputProtocol.Event(1,1000,10,8,0,.1f,0),new HudInputProtocol.Event(1,1000,11,8,0,0,1),new HudInputProtocol.Event(1,1000,12,8,0,0,0)})
            rejects(()->HudInputProtocol.validateEvent(event,1000,true,true,true,true));
        var gate=new HudInputGate(true,true,true);
        gate.apply(new HudInputProtocol.Event(1,1000,10,8,0,0,0),1000);
        gate.apply(new HudInputProtocol.Event(2,1000,10,8,0,0,0),1000);check(gate.heldKeyCount()==1); // Native bounded editor repeat.
        gate.apply(new HudInputProtocol.Event(3,1000,9,'W',0,0,0),1000);check(gate.heldKeyCount()==1&&gate.heldButtonCount()==0);
        gate.apply(new HudInputProtocol.Event(4,1000,11,8,0,0,0),1000);check(gate.heldKeyCount()==0);
        rejects(()->gate.apply(new HudInputProtocol.Event(5,1000,11,8,0,0,0),1000));
        gate.apply(new HudInputProtocol.Event(5,1000,1,27,0,0,0),1000);
        gate.apply(new HudInputProtocol.Event(6,1000,10,27,0,0,0),1000);check(gate.heldKeyCount()==2); // Distinct world/editor key channels.
        rejects(()->gate.apply(new HudInputProtocol.Event(7,1000,10,27,0,0,0),1000));
        gate.apply(new HudInputProtocol.Event(7,1000,2,27,0,0,0),1000);
        gate.apply(new HudInputProtocol.Event(8,1000,11,27,0,0,0),1000);check(gate.heldKeyCount()==0);
        gate.apply(new HudInputProtocol.Event(9,1000,10,13,0,0,0),1000);
        rejects(()->gate.apply(new HudInputProtocol.Event(10,1000,10,13,0,0,0),1000));
        rejects(()->gate.apply(new HudInputProtocol.Event(11,1000,9,'a',0,0,0),1000));
        gate.releaseAll();check(gate.sequence()==9&&gate.heldKeyCount()==0&&gate.heldButtonCount()==0);
        // F5 is a balanced world-key request, not a repeatable editor key.
        gate.apply(new HudInputProtocol.Event(10,1000,1,0x74,0,0,0),1000);
        check(gate.heldKeyCount()==1);
        rejects(()->gate.apply(new HudInputProtocol.Event(11,1000,1,0x74,0,0,0),1000));
        gate.apply(new HudInputProtocol.Event(11,1000,2,0x74,0,0,0),1000);
        check(gate.heldKeyCount()==0);
        rejects(()->gate.apply(new HudInputProtocol.Event(12,1000,2,0x74,0,0,0),1000));
        gate.apply(new HudInputProtocol.Event(12,1000,1,0x74,0,0,0),1000);
        gate.releaseAll();check(gate.heldKeyCount()==0&&gate.sequence()==12);
        for(var legacy:new HudInputGate[]{new HudInputGate(),new HudInputGate(true),new HudInputGate(true,true)})
            rejects(()->legacy.apply(new HudInputProtocol.Event(1,1000,1,0x74,0,0,0),1000));
        rejects(()->new HudInputReader(id,true,true,false,true));
        var ack=new HudInputReader.Acknowledgement(3,1000,1,2,0);
        new HudInputReader(id,true,true,true,true).acknowledge(ack);check(true);
        rejects(()->new HudInputReader(id,true,true,true).acknowledge(ack));
        b.putInt(96,2);check(HudInputProtocol.decode(b.array(),id,0,3000,1,true,true,true,true).events().isEmpty());
    }
}
