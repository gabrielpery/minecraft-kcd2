package dev.minecome.hud;

import java.io.*;
import java.util.zip.*;

/** Pure bounded conversion/PNG encoding. Input is OpenGL bottom-up premultiplied RGBA8. */
public final class HudPixels {
    public static final int MAX_WIDTH = 1920, MAX_HEIGHT = 1080, MAX_FRAMES = 3;
    private HudPixels() {}
    public static int byteSize(int width, int height) {
        if (width < 1 || width > MAX_WIDTH || height < 1 || height > MAX_HEIGHT)
            throw new IllegalArgumentException("HUD dimensions outside1..1920x1..1080");
        return Math.multiplyExact(Math.multiplyExact(width, height), 4);
    }
    /** No discarded alpha or world-colour reconstruction: transparent pixels become exact zero. */
    public static byte[] straightTopLeft(byte[] bottomUp, int width, int height) {
        int size = byteSize(width, height);
        if (bottomUp.length != size) throw new IllegalArgumentException("Incorrect HUD RGBA byte count");
        byte[] topDown = new byte[size];
        int row = width * 4;
        for (int y = 0; y < height; y++) for (int x = 0; x < row; x += 4) {
            int source = (height - 1 - y) * row + x, destination = y * row + x, alpha = bottomUp[source + 3] & 255;
            topDown[destination + 3] = (byte) alpha;
            if (alpha != 0) for (int c = 0; c < 3; c++)
                topDown[destination + c] = (byte) Math.min(255, ((bottomUp[source + c] & 255) * 255 + alpha / 2) / alpha);
        }
        return topDown;
    }
    /** Original minimal PNG encoder: RGBA8, top-left rows, filter0, standard zlib/CRC. */
    public static byte[] png(byte[] rgba, int width, int height) throws IOException {
        if (rgba.length != byteSize(width, height)) throw new IllegalArgumentException("Incorrect PNG RGBA byte count");
        var compressed = new ByteArrayOutputStream();
        try (var deflater = new DeflaterOutputStream(compressed)) {
            for (int y = 0; y < height; y++) { deflater.write(0); deflater.write(rgba, y * width * 4, width * 4); }
        }
        if (compressed.size() > rgba.length + height + 65536) throw new IOException("PNG compression exceeded bounded output");
        var output = new ByteArrayOutputStream();
        output.write(new byte[] {(byte)137,80,78,71,13,10,26,10});
        var headerBytes = new ByteArrayOutputStream();
        try (var header = new DataOutputStream(headerBytes)) { header.writeInt(width); header.writeInt(height); header.write(new byte[] {8,6,0,0,0}); }
        chunk(output, "IHDR", headerBytes.toByteArray()); chunk(output, "IDAT", compressed.toByteArray()); chunk(output, "IEND", new byte[0]);
        return output.toByteArray();
    }
    private static void chunk(OutputStream output, String kind, byte[] bytes) throws IOException {
        byte[] type = kind.getBytes(java.nio.charset.StandardCharsets.US_ASCII); var data = new DataOutputStream(output);
        data.writeInt(bytes.length); data.write(type); data.write(bytes);
        var crc = new CRC32(); crc.update(type); crc.update(bytes); data.writeInt((int) crc.getValue());
    }
}
