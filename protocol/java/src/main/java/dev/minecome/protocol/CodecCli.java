package dev.minecome.protocol;

import java.nio.file.*;

/** Cross-language test client. Synthetic state is explicitly marked in the console. */
public final class CodecCli {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) throw new IllegalArgumentException("Usage: CodecCli TOKEN_FILE [seconds=5]");
        int seconds=args.length>1?Integer.parseInt(args[1]):5;
        if (seconds<1 || seconds>120) throw new IllegalArgumentException("Duration must be 1..120 seconds");
        try (BridgeClient client=new BridgeClient(Path.of(args[0]),"java-codec-harness",Protocol.ROLE_HARNESS,System.out::println)) {
            client.publish(new Protocol.Pose(new Protocol.Vec3(10,64,-20),new Protocol.Vec3(10,65.62,-20),
                    new Protocol.Quaternion(0,0,0,1),Math.toRadians(70),new Protocol.Vec3(0,0,0),1,
                    Protocol.SPACE_MC,Protocol.HAS_PLAYER|Protocol.HAS_CAMERA));
            client.start();
            long deadline=System.nanoTime()+seconds*1_000_000_000L;
            boolean event=false;
            while (System.nanoTime()<deadline) {
                if (client.connected() && !event) {
                    client.blockEvent(new Protocol.BlockEvent(1,10,64,-19,"minecraft:stone")); event=true;
                }
                Thread.sleep(100);
            }
            System.out.println("Synthetic harness received host poses: "+client.receivedPoses());
            if (client.receivedPoses()==0) throw new IllegalStateException("No host pose received");
        }
    }
}
