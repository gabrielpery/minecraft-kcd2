package dev.minecome.hud;

import com.google.gson.*;
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Owned daemon writes only copied scalar metadata/pixels; CREATE_NEW files in a NEW evidence directory. */
public final class HudOutput implements AutoCloseable {
    public record Frame(int id, int width, int height, byte[] rgba, String metadataJson) {
        public Frame {
            if (id < 1 || id > HudPixels.MAX_FRAMES || rgba.length != HudPixels.byteSize(width, height) || metadataJson.length() > 16384)
                throw new IllegalArgumentException("Invalid bounded HUD frame");
            rgba = rgba.clone();
        }
        @Override public byte[] rgba() { return rgba.clone(); }
    }
    private record Message(Frame frame, String result) {}
    private static final long MAX_OUTPUT_BYTES = 64L * 1024 * 1024;
    private final Path root, directory;
    private final String run, save;
    private final ArrayBlockingQueue<Message> queue = new ArrayBlockingQueue<>(4);
    private final AtomicReference<IOException> failure = new AtomicReference<>();
    private final AtomicBoolean ready = new AtomicBoolean(), finished = new AtomicBoolean();
    private final AtomicInteger written = new AtomicInteger();
    private Thread worker;
    private int offered;
    private boolean ended;
    public HudOutput(Path root, Path directory, String run, String save) {
        if (!root.isAbsolute() || !directory.isAbsolute() || !run.matches("[0-9a-f]{32}") || !save.matches("MineCome-Hud-[0-9a-f-]{36}"))
            throw new IllegalArgumentException("Invalid HUD output identity/path");
        this.root = root.normalize(); this.directory = directory.normalize(); this.run = run; this.save = save;
    }
    public synchronized void start() {
        if (worker != null) throw new IllegalStateException("HUD output cannot restart");
        worker = new Thread(this::write, "MineComeHudOutput"); worker.setDaemon(true); worker.start();
    }
    public boolean isReady() { return ready.get() && failure.get() == null; }
    public boolean isFinished() { return finished.get(); }
    public IOException failure() { return failure.get(); }
    public int written() { return written.get(); }
    public synchronized void offer(Frame frame) throws IOException {
        if (!isReady() || ended || frame.id() != offered + 1 || offered >= HudPixels.MAX_FRAMES || !queue.offer(new Message(frame, null)))
            throw new IOException("HUD output not ready/order/mailbox limit");
        offered++;
    }
    public synchronized void finish(String result) throws IOException {
        if (ended) return;
        if (!Set.of("passed", "failed", "stopped").contains(result) || (result.equals("passed") && offered != HudPixels.MAX_FRAMES))
            throw new IOException("Invalid HUD terminal proof");
        if (!queue.offer(new Message(null, result))) throw new IOException("HUD terminal mailbox overflow");
        ended = true;
    }
    @Override public void close() { try { finish("stopped"); } catch (IOException e) { failure.compareAndSet(null, e); } }
    /** Standalone tests only, never called on a game/render thread. */
    public boolean awaitFinished(long millis) throws InterruptedException {
        if (millis < 1 || millis > 1000) throw new IllegalArgumentException("HUD test wait1..1000ms");
        Thread thread; synchronized (this) { thread = worker; } if (thread == null) return false;
        thread.join(millis); return finished.get() && !thread.isAlive();
    }
    private void write() {
        try {
            Path realRoot = root.toRealPath(), evidence = root.resolve("runtime/evidence").toRealPath(), parent = directory.getParent().toRealPath();
            if (!evidence.startsWith(realRoot) || !parent.startsWith(evidence) || evidence.equals(realRoot))
                throw new IOException("HUD output escapes resolved runtime/evidence");
            Path target = parent.resolve(directory.getFileName()); Files.createDirectory(target);
            ready.set(true); long bytes = 0; JsonArray frames = new JsonArray();
            while (true) {
                Message message = queue.take();
                if (message.frame() == null) {
                    JsonObject manifest = new JsonObject();
                    manifest.addProperty("schema",1); manifest.addProperty("source_kind","minecraft_vanilla_ui_v1");
                    manifest.addProperty("run",run); manifest.addProperty("world",save.substring("MineCome-Hud-".length())); manifest.addProperty("save",save);
                    manifest.addProperty("minecraft_version","1.21.1"); manifest.addProperty("yarn_mappings","1.21.1+build.3");
                    manifest.addProperty("capture_backend","opengl_three_pixel_pack_buffers"); manifest.addProperty("alpha_mode","straight_rgba8");
                    manifest.addProperty("pixel_format","rgba8"); manifest.addProperty("origin","top_left");
                    manifest.addProperty("vanilla_render_path",true); manifest.addProperty("world_render_suppressed",true);
                    manifest.addProperty("hand_render_suppressed",true); manifest.addProperty("graphics_mode","fast");
                    manifest.addProperty("ordinary_alpha_blend","source_over"); manifest.addProperty("kcd_compositing_verified",false);
                    manifest.addProperty("result",message.result()); manifest.addProperty("frames",written.get()); manifest.add("frame_records",frames);
                    byte[] body = (new GsonBuilder().setPrettyPrinting().create().toJson(manifest)+"\n").getBytes(java.nio.charset.StandardCharsets.UTF_8);
                    if (body.length > 65536 || bytes + body.length > MAX_OUTPUT_BYTES) throw new IOException("HUD manifest/output budget");
                    Files.write(target.resolve("hud-export.json"),body,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE); break;
                }
                Frame frame = message.frame(); byte[] png = HudPixels.png(frame.rgba,frame.width(),frame.height());
                if (bytes + frame.rgba.length + png.length > MAX_OUTPUT_BYTES - 65536) throw new IOException("HUD output64MiB budget exhausted");
                String prefix = String.format(Locale.ROOT,"hud-%04d",frame.id());
                Files.write(target.resolve(prefix+".rgba"),frame.rgba,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
                Files.write(target.resolve(prefix+".png"),png,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
                bytes += frame.rgba.length + png.length;
                JsonObject meta = JsonParser.parseString(frame.metadataJson()).getAsJsonObject();
                meta.addProperty("frame_id",frame.id()); meta.addProperty("width",frame.width()); meta.addProperty("height",frame.height());
                meta.addProperty("row_pitch",frame.width()*4); meta.addProperty("rgba_file",prefix+".rgba"); meta.addProperty("png_file",prefix+".png");
                meta.addProperty("rgba_sha256",sha256(frame.rgba)); meta.addProperty("png_sha256",sha256(png));
                int zero = 0, partial = 0, opaque = 0;
                for (int i=3;i<frame.rgba.length;i+=4) { int a=frame.rgba[i]&255; if(a==0)zero++;else if(a==255)opaque++;else partial++; }
                meta.addProperty("transparent_pixels",zero); meta.addProperty("partial_alpha_pixels",partial); meta.addProperty("opaque_pixels",opaque);
                if (frame.id() <= 2 && (zero == 0 || zero < frame.width()*frame.height()/2 || opaque + partial == 0))
                    throw new IOException("HUD frame lacks transparent background/genuine visible UI");
                frames.add(meta); written.incrementAndGet();
            }
        } catch (IOException e) { failure.compareAndSet(null,e); }
        catch (Exception e) { failure.compareAndSet(null,new IOException("HUD output daemon failed",e)); }
        finally { finished.set(true); }
    }
    private static String sha256(byte[] bytes) throws NoSuchAlgorithmException { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)); }
}
