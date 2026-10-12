package dev.minecome.hud;

import com.google.gson.*;
import javax.imageio.ImageIO;
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** Pure synthetic pixels test encoding/ownership/bounds; it does not claim vanilla live rendering. */
public final class HudExportTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private interface Operation{void run()throws Exception;}
    private static void rejects(Operation op)throws Exception{try{op.run();throw new AssertionError("Invalid HUD input accepted");}catch(IOException|IllegalArgumentException expected){checks++;}}
    private static byte[] pixels(){byte[] bytes=new byte[16*8*4];bytes[0]=(byte)255;bytes[3]=(byte)255;bytes[4]=60;bytes[5]=30;bytes[7]=(byte)128;return bytes;}
    private static void ready(HudOutput output)throws Exception{
        output.start();long deadline=System.nanoTime()+1_000_000_000L;while(!output.isReady()&&!output.isFinished()&&System.nanoTime()<deadline)Thread.sleep(2);
        check(output.isReady()&&output.failure()==null,"Daemon validated new confined directory");
    }
    public static void main(String[] args)throws Exception{
        check(HudPixels.byteSize(1920,1080)==8_294_400,"Maximum bounded raw frame");
        rejects(()->HudPixels.byteSize(1921,1080));rejects(()->HudPixels.byteSize(1,0));rejects(()->HudPixels.straightTopLeft(new byte[1],1,1));
        byte[] mapped=HudPixels.straightTopLeft(new byte[]{64,32,0,(byte)128,1,2,3,0},1,2);
        check(Arrays.equals(Arrays.copyOfRange(mapped,0,4),new byte[4]),"Bottom-up rows flipped; transparentRGB zeroed");
        check((mapped[4]&255)==128&&(mapped[5]&255)==64&&(mapped[7]&255)==128,"PremultipliedRGB normalized to straight with alpha retained");
        byte[] png=HudPixels.png(mapped,1,2);var image=ImageIO.read(new ByteArrayInputStream(png));
        check(image.getWidth()==1&&image.getHeight()==2&&image.getRGB(0,0)==0,"PNG dimensions/orientation/transparency");
        check(image.getRGB(0,1)==0x80804000,"PNG exactRGBA8 roundtrip");
        Path root=Files.createTempDirectory("minecome-hud-tests-").toAbsolutePath();Path evidence=Files.createDirectories(root.resolve("runtime/evidence/run"));
        String run="a".repeat(32),save="MineCome-Hud-01234567-89ab-4cde-8fab-0123456789ab";
        try{
            Path directory=evidence.resolve("hud");var output=new HudOutput(root,directory,run,save);ready(output);
            rejects(()->output.finish("passed"));
            for(int id=1;id<=3;id++){
                byte[] rgba=pixels();var frame=new HudOutput.Frame(id,16,8,rgba,"{\"test_fixture_pixels\":true}");Arrays.fill(rgba,(byte)99);
                check(frame.rgba()[0]==(byte)255,"Queued frame owns a copy");byte[] returned=frame.rgba();returned[0]=0;check(frame.rgba()[0]==(byte)255,"Pixel accessor cannot mutate queued frame");
                output.offer(frame);
            }
            output.finish("passed");check(output.awaitFinished(1000),"Passed terminal waits for actual daemon close");check(output.failure()==null&&output.written()==3,"Exactly three bounded files committed");
            JsonObject manifest=JsonParser.parseString(Files.readString(directory.resolve("hud-export.json"))).getAsJsonObject();
            check(manifest.get("alpha_mode").getAsString().equals("straight_rgba8")&&manifest.get("origin").getAsString().equals("top_left"),"Explicit native compositor pixel contract");
            check(!manifest.get("kcd_compositing_verified").getAsBoolean(),"Capture does not claim host compositor proof");
            for(JsonElement element:manifest.getAsJsonArray("frame_records")){
                JsonObject frame=element.getAsJsonObject();byte[] raw=Files.readAllBytes(directory.resolve(frame.get("rgba_file").getAsString()));
                check(raw.length==16*8*4&&frame.get("row_pitch").getAsInt()==64,"Exact contiguous rawRGBA layout");
                check(frame.get("rgba_sha256").getAsString().equals(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(raw))),"Manifest pins exact raw bytes");
                var decoded=ImageIO.read(directory.resolve(frame.get("png_file").getAsString()).toFile());check(decoded.getRGB(0,0)==0xffff0000,"Raw and PNG pixel agreement");
                check(frame.get("transparent_pixels").getAsInt()==126&&frame.get("partial_alpha_pixels").getAsInt()==1,"Independent alpha statistics");
            }
            rejects(()->output.offer(new HudOutput.Frame(3,16,8,pixels(),"{}")));
            var existing=new HudOutput(root,directory,run,save);existing.start();check(existing.awaitFinished(1000)&&existing.failure()!=null,"Existing output directory refused");
            var outside=new HudOutput(root,root.resolve("escaped"),run,save);outside.start();check(outside.awaitFinished(1000)&&outside.failure()!=null,"Resolved output confinement enforced");
            check(!Files.exists(root.resolve("escaped")),"No outside output mutation");
            System.out.println("HudExportTests: "+checks+" checks passed (pure encoding/output fixtures; no live rendering)");
        }finally{try(var paths=Files.walk(root)){for(Path path:paths.sorted(Comparator.reverseOrder()).toList())Files.deleteIfExists(path);}}
    }
}
