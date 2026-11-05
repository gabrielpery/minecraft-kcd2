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
        System.out.println("GameplayWireTests: "+checks+" checks passed; no games");
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
}
