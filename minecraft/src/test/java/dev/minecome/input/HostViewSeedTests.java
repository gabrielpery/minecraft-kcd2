package dev.minecome.input;

import com.google.gson.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/** Pure starting-view/origin fixtures. No Minecraft classes, process checks or game calls. */
public final class HostViewSeedTests {
    private static int checks;
    private static final String RUN = "0123456789abcdef0123456789abcdef", HASH = "a".repeat(64);
    private static final ExternalInputSessionGate.Identity ID = new ExternalInputSessionGate.Identity(RUN, 1, "1");
    private static void check(boolean value, String message) { checks++; if (!value) throw new AssertionError(message); }
    private static JsonObject vector(double x, double y, double z) {
        var value = new JsonObject(); value.addProperty("x", x); value.addProperty("y", y); value.addProperty("z", z); return value;
    }
    private static JsonObject seed(double fx, double fy, double fz, double ux, double uy, double uz) {
        var value = new JsonObject(); value.addProperty("schema", 1); value.addProperty("run", RUN);
        value.addProperty("source_kind", "standalone_fixture"); value.addProperty("patch_sha256", HASH);
        value.addProperty("target_pid", 1); value.addProperty("target_start_filetime", "1"); value.addProperty("captured_utc_ms", 1000);
        value.add("player", vector(0, 0, 0)); value.add("forward", vector(fx, fy, fz)); value.add("up", vector(ux, uy, uz));
        return value;
    }
    private static JsonObject seed() { return seed(0, -1, 0, 0, 0, 1); }
    private static byte[] bytes(String value) { return value.getBytes(StandardCharsets.UTF_8); }
    private static HostViewSeed parse(JsonObject value, long now) throws IOException {
        return HostViewSeed.parse(bytes(value.toString()), ID, HASH, true, 0, 0, 0, now);
    }
    private static void reject(String value) {
        try { HostViewSeed.parse(bytes(value), ID, HASH, true, 0, 0, 0, 1000); throw new AssertionError("Malformed view seed accepted"); }
        catch (IOException expected) { checks++; }
    }
    private static void reject(JsonObject value) { reject(value.toString()); }
    private static void rejectContext(HostViewSeed seed, ExternalInputSessionGate.Identity id, String hash, boolean fixture,
                                      double cx, double cy, double cz, long now) {
        try { seed.revalidate(id, hash, fixture, cx, cy, cz, now); throw new AssertionError("Invalid view context accepted"); }
        catch (IOException expected) { checks++; }
    }
    private static void orientation(JsonObject fixture, double yaw, double pitch, String label) throws IOException {
        var view = parse(fixture, 1000);
        check(Math.abs(view.yawDegrees() - yaw) < 0.000001 && Math.abs(view.pitchDegrees() - pitch) < 0.000001, label);
    }
    public static void main(String[] args) throws Exception {
        orientation(seed(), 0, 0, "KCD-Y maps MC+Z yaw0");
        orientation(seed(1, 0, 0, 0, 0, 1), -90, 0, "KCD+X maps MC+X yaw-90");
        orientation(seed(-1, 0, 0, 0, 0, 1), 90, 0, "KCD-X maps MC-X yaw90");
        check(Math.abs(Math.abs(parse(seed(0, 1, 0, 0, 0, 1), 1000).yawDegrees()) - 180) < 0.000001,
                "KCD+Y maps MC-Z yaw180 boundary");
        double diagonal = Math.sqrt(0.5);
        orientation(seed(-diagonal, -diagonal, 0, 0, 0, 1), 45, 0, "Diagonal coordinate mapping yaw45");
        orientation(seed(diagonal, diagonal, 0, 0, 0, 1), -135, 0, "Opposite diagonal mapping yaw-135");
        orientation(seed(0, -Math.sqrt(0.75), 0.5, 0, 0.5, Math.sqrt(0.75)), 0, -30, "KCD upward camera becomes negative Minecraft pitch");
        orientation(seed(0, -Math.sqrt(0.75), -0.5, 0, -0.5, Math.sqrt(0.75)), 0, 30, "Downward camera becomes positive Minecraft pitch");
        orientation(seed(-0.6963642403200189, -0.696364240320019, 0.17364817766693033,
                0.12278780396897282, 0.12278780396897285, 0.984807753012208), 45, -10,
                "Root's independent fixture golden yaw45 pitch-10");
        var view = parse(seed(), 1000);
        check(view.sourceKind().equals("standalone_fixture") && view.sha256().matches("[0-9a-f]{64}") && view.capturedUtcMillis() == 1000,
                "Seed preserves immutable provenance and exact content SHA256");
        orientation(seed(0, -1.005, 0, 0, 0, 0.995), 0, 0, "Unit tolerance vectors normalized for orientation");
        orientation(seed(0, -1, 0, Math.sin(Math.toRadians(0.5)), 0, Math.cos(Math.toRadians(0.5))), 0, 0,
                "Roll below1degree accepted without changing yaw/pitch");
        reject(seed(0, -1, 0, Math.sin(Math.toRadians(2)), 0, Math.cos(Math.toRadians(2))));
        reject(seed(0, -1, 0, 0, 0, -1));
        reject(seed(0, -1, 0, 0, 0.02, Math.sqrt(1 - 0.02 * 0.02)));
        reject(seed(0, -0.98, 0, 0, 0, 1)); reject(seed(0, -1.02, 0, 0, 0, 1));
        reject(seed(0, -1, 0, 0, 0, 0.98)); reject(seed(0, -1, 0, 0, 0, 1.02));
        reject(seed(0, 0, 0, 0, 0, 1)); reject(seed(0, 0, 1, 1, 0, 0));
        reject(seed(0.009, 0, Math.sqrt(1 - 0.009 * 0.009), -Math.sqrt(1 - 0.009 * 0.009), 0, 0.009));
        var outside = seed(); outside.add("player", vector(0.071, 0.071, 0)); reject(outside);
        var edge = seed(); edge.add("player", vector(0.1, 0, 0)); parse(edge, 1000); checks++;
        var extreme = seed(); extreme.add("player", vector(10_000_001, 0, 0)); reject(extreme);
        view.revalidate(ID, HASH, true, 0, 0, 0, 61_000); checks++;
        view.revalidate(ID, HASH, true, 0, 0, 0, 950); checks++;
        rejectContext(view, ID, HASH, true, 0, 0, 0, 61_001);
        rejectContext(view, ID, HASH, true, 0, 0, 0, 949);
        rejectContext(view, ID, HASH, true, 0.11, 0, 0, 1000);
        rejectContext(view, ID, HASH, true, Double.NaN, 0, 0, 1000);
        rejectContext(view, new ExternalInputSessionGate.Identity("f".repeat(32), 1, "1"), HASH, true, 0, 0, 0, 1000);
        rejectContext(view, new ExternalInputSessionGate.Identity(RUN, 2, "1"), HASH, true, 0, 0, 0, 1000);
        rejectContext(view, new ExternalInputSessionGate.Identity(RUN, 1, "2"), HASH, true, 0, 0, 0, 1000);
        rejectContext(view, ID, "b".repeat(64), true, 0, 0, 0, 1000);
        rejectContext(view, ID, HASH.toUpperCase(), true, 0, 0, 0, 1000);
        rejectContext(view, ID, HASH, false, 0, 0, 0, 1000);
        var live = seed(); live.addProperty("source_kind", "live_kcd_view_seed");
        HostViewSeed.parse(bytes(live.toString()), ID, HASH, false, 0, 0, 0, 1000); checks++;
        reject(live);
        for (String key : new String[] { "schema", "run", "source_kind", "patch_sha256", "target_pid", "target_start_filetime",
                "captured_utc_ms", "player", "forward", "up" }) {
            var missing = seed(); missing.remove(key); reject(missing);
        }
        var malformed = seed(); malformed.addProperty("extra", 1); reject(malformed);
        malformed = seed(); malformed.getAsJsonObject("up").addProperty("extra", 1); reject(malformed);
        for (String key : new String[] { "schema", "target_pid", "captured_utc_ms" }) {
            malformed = seed(); malformed.addProperty(key, "1"); reject(malformed);
            malformed = seed(); malformed.addProperty(key, 0.5); reject(malformed);
        }
        malformed = seed(); malformed.addProperty("target_start_filetime", 1); reject(malformed);
        malformed = seed(); malformed.addProperty("target_start_filetime", "01"); reject(malformed);
        malformed = seed(); malformed.addProperty("run", RUN.toUpperCase()); reject(malformed);
        malformed = seed(); malformed.addProperty("source_kind", "other"); reject(malformed);
        malformed = seed(); malformed.addProperty("target_pid", 0); reject(malformed);
        malformed = seed(); malformed.addProperty("captured_utc_ms", 0); reject(malformed);
        String valid = seed().toString();
        reject(valid.replace("\"schema\":1", "\"schema\":1,\"schema\":1"));
        reject(valid.replace("\"x\":0.0", "\"x\":0.0,\"x\":0.0"));
        reject(valid.replace("\"captured_utc_ms\":1000", "\"captured_utc_ms\":1e-2147483647"));
        reject(valid.replace("\"captured_utc_ms\":1000", "\"captured_utc_ms\":0e2147483647"));
        reject(valid.replace("\"x\":0.0", "\"x\":NaN"));
        reject(valid.replace("\"x\":0.0", "\"x\":{\"x\":{\"x\":0}}"));
        reject(valid + "{}"); reject("\ufeff" + valid); reject(" ".repeat(HostViewSeed.MAX_BYTES + 1));
        try { HostViewSeed.parse(new byte[] { (byte) 0xc3, (byte) 0x28 }, ID, HASH, true, 0, 0, 0, 1000); throw new AssertionError("Bad UTF8 accepted"); }
        catch (IOException expected) { checks++; }
        Path file = Files.createTempFile("minecome-view-seed-fixture-", ".json");
        try {
            Files.writeString(file, valid); var fromFile = HostViewSeed.read(file, ID, HASH, true, 0, 0, 0, 1000);
            check(fromFile.sha256().equals(view.sha256()), "Bounded file read matches strict byte parser hash");
            Files.writeString(file, " ".repeat(HostViewSeed.MAX_BYTES + 1));
            try { HostViewSeed.read(file, ID, HASH, true, 0, 0, 0, 1000); throw new AssertionError("Oversized view file accepted"); }
            catch (IOException expected) { checks++; }
        } finally { Files.delete(file); }
        System.out.println("HostViewSeedTests: " + checks + " checks passed (standalone initial-view seed only).");
    }
}
