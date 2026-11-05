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
        b.put(7,(byte)'1');b.putInt(8,1);
        rejects(()->HudInputProtocol.decode(b.array(),id,0,1000,0,false,true));
        check(HudInputProtocol.decode(b.array(),id,0,1000,0,false).hostState()==1);
        Properties p=new Properties();p.setProperty("minecome.gameplay","true");
        p.setProperty("minecome.gameplayStandalone","true");p.setProperty("minecome.gameplayFixture","create");
        GameplayMode.requireExclusive(p);check(true);
        p.setProperty("minecome.hudStreamLab","true");rejects(()->GameplayMode.requireExclusive(p));
        check(GameplayMode.MAX_LEASE_MS==86_400_000L);
        System.out.println("GameplayWireTests: "+checks+" checks passed; no games");
    }
}
