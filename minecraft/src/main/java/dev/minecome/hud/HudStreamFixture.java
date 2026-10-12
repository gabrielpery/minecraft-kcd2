package dev.minecome.hud;

import java.nio.file.Path;
import java.util.UUID;

/** Original transport fixture only. Its synthetic pixels never claim Minecraft/game evidence. */
public final class HudStreamFixture {
    public static void main(String[] args)throws Exception {
        if(args.length!=6)throw new IllegalArgumentException("Expected root|NEW-directory|run|targetPid|targetFILETIME|expiryUtcMs");
        var id=new HudStreamProducer.Identity(args[2],Integer.parseInt(args[3]),Long.parseUnsignedLong(args[4]),Long.parseLong(args[5]));
        var producer=new HudStreamProducer(Path.of(args[0]),Path.of(args[1]),id,"MineCome-HudStream-"+UUID.randomUUID(),false);producer.start();
        long readyDeadline=System.nanoTime()+5_000_000_000L;
        while(!producer.isReady() && !producer.isFinished() && System.nanoTime()<readyDeadline)Thread.sleep(5);
        if(!producer.isReady())throw new IllegalStateException("Fixture producer not ready: "+producer.failure());
        long began=System.nanoTime();int frame=0;
        while(System.nanoTime()-began<8_000_000_000L && producer.isReady()) {
            long elapsed=System.nanoTime()-began;
            if(elapsed<3_000_000_000L || elapsed>=4_300_000_000L) {
                byte[] rgba=new byte[32*18*4];for(int i=0;i<rgba.length;i+=4){rgba[i]=(byte)++frame;rgba[i+3]=(byte)255;}
                producer.offer(new HudStreamProducer.Frame(32,18,rgba,System.currentTimeMillis(),elapsed<4_300_000_000L?0:1,0,"{\"state\":\"transport_fixture\",\"genuine_vanilla_ui\":false}"));
            }
            Thread.sleep(50);
        }
        producer.finish("fixture",null);
        if(!producer.awaitFinished(3000) || producer.failure()!=null)throw new IllegalStateException("Fixture termination: "+producer.failure());
        System.out.println("HUD_STREAM_FIXTURE_PASS frames="+producer.publishedFrames()+" genuineMinecraftPixels=false");
    }
}
