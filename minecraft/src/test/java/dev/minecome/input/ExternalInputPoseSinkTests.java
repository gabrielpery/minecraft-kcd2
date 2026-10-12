package dev.minecome.input;

import com.google.gson.*;
import java.io.IOException;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Standalone scalar/output lifecycle checks; no Minecraft, process or input APIs. */
public final class ExternalInputPoseSinkTests {
    private static int checks;
    private static final String WORLD = "01234567-89ab-4cde-8fab-0123456789ab";
    private static final ExternalInputSessionGate.Identity INPUT = new ExternalInputSessionGate.Identity(
            "0123456789abcdef0123456789abcdef", 47092, "134054567890123456");
    private static final ExternalInputPoseSink.Motion MOTION = new ExternalInputPoseSink.Motion(
            0.5, 64, 0.5, 0, 0, 0, true, true, 45, -10);
    private static void check(boolean value, String message) {
        checks++; if (!value) throw new AssertionError(message);
    }
    private static void near(double value, double expected, String message) { check(Math.abs(value - expected) < 1e-12, message); }
    private interface Throwing { void run() throws Exception; }
    private static void rejects(Throwing action, String message) throws Exception {
        try { action.run(); throw new AssertionError(message); }
        catch (IOException | IllegalArgumentException expected) { checks++; }
    }
    private static ExternalInputPoseSink.Context context(String groundKind, boolean fixture) {
        return new ExternalInputPoseSink.Context(INPUT, "patch-1", "a".repeat(64), "b".repeat(64), groundKind, fixture,
                "MineCome-ExternalInput-" + WORLD, WORLD, new ExternalInputPoseSink.Vec3(100, 200, 56),
                new ExternalInputPoseSink.Vec3(0.5, 64, 0.5));
    }
    private static ExternalInputPoseSink start(Path root, Path output) throws Exception {
        var sink = new ExternalInputPoseSink(root, output, context("standalone_fixture", true), 1000);
        sink.start();
        long deadline = System.nanoTime() + 2_000_000_000L;
        while (!sink.isReady() && !sink.isFinished() && System.nanoTime() < deadline) Thread.sleep(2);
        check(sink.isReady() && sink.failure() == null, "Daemon validated new evidence output and wrote BEGIN");
        return sink;
    }
    private static void stopped(ExternalInputPoseSink sink) throws Exception {
        check(sink.awaitFinished(1000), "Terminal worker flushed and closed within bounded test wait");
        check(sink.failure() == null, "Normal terminal has no daemon write failure");
    }
    private static List<JsonObject> records(Path output) throws Exception {
        byte[] bytes = Files.readAllBytes(output);
        check(bytes.length > 0 && bytes[bytes.length - 1] == '\n', "Complete terminal LF");
        check(bytes.length <= ExternalInputPoseSink.MAX_BYTES, "Whole recording byte bound");
        List<JsonObject> result = new ArrayList<>();
        for (String line : Files.readAllLines(output, StandardCharsets.UTF_8)) {
            check(line.getBytes(StandardCharsets.UTF_8).length + 1 <= ExternalInputPoseSink.MAX_LINE_BYTES, "Individual output line bound");
            result.add(JsonParser.parseString(line).getAsJsonObject());
        }
        return result;
    }
    private static void workerReject(Path root, Path output) throws Exception {
        var sink = new ExternalInputPoseSink(root, output, context("standalone_fixture", true), 1000);
        sink.start(); check(sink.awaitFinished(1000), "Bad destination fails on daemon within bounded wait");
        check(sink.failure() != null && !sink.isReady(), "Destination failure never signals READY");
    }
    private static void waitFlushed(ExternalInputPoseSink sink, Path output) throws Exception {
        long deadline = System.nanoTime() + 1_000_000_000L;
        while (Files.size(output) < sink.byteCount() && System.nanoTime() < deadline) Thread.sleep(2);
        if (sink.failure() != null) throw sink.failure();
        if (Files.size(output) != sink.byteCount()) throw new AssertionError("Bounded test writer did not drain queued records");
    }
    public static void main(String[] args) throws Exception {
        Path root = Files.createTempDirectory("minecome-pose-tests-").toAbsolutePath();
        Path evidence = Files.createDirectories(root.resolve("runtime/evidence/test"));
        try {
            rejects(() -> context("synthetic", true), "Unknown ground provenance accepted");
            rejects(() -> context("standalone_fixture", false), "Fixture terrain accepted for physical mode");
            check(context("live_kcd_ground_patch", false).groundSourceKind().equals("live_kcd_ground_patch"), "Live ground context allowed");
            rejects(() -> new ExternalInputPoseSink(root, Path.of("relative.ndjson"), context("standalone_fixture", true), 1000), "Relative output accepted");
            workerReject(root, root.resolve("outside.ndjson"));
            Path existing = evidence.resolve("existing.ndjson"); Files.writeString(existing, "owned-original\n");
            workerReject(root, existing); check(Files.readString(existing).equals("owned-original\n"), "CREATE_NEW preserves prior files");

            Path output = evidence.resolve("pose.ndjson"); var sink = start(root, output);
            rejects(() -> sink.finish(1001, "passed", "No sample"), "Passed END without sample accepted");
            check(sink.records() == 1, "Rejected premature passed END consumes no sequence");
            check(!sink.sample(1_000_000_000, 1001, MOTION, MOTION, 1, 749_999_999, BigInteger.ZERO, true), "Observation older than250ms rejected");
            check(!sink.sample(1_000_000_000, 1001, MOTION, MOTION, 1, 1_000_000_001, BigInteger.ZERO, true), "Future monotonic observation rejected");
            check(sink.sample(1_000_000_000, 1001, MOTION, MOTION, 1, 750_000_000, BigInteger.ZERO, true), "Exact250ms boundary accepted");
            check(!sink.sample(1_100_000_000, 1100, MOTION, MOTION, 1, 1_100_000_000, BigInteger.ZERO, true), "Repeated server sample rejected");
            check(!sink.sample(1_050_000_000, 1050, MOTION, MOTION, 2, 1_050_000_000, BigInteger.ONE, false), "Ordinary sample rate bounded10Hz");
            check(sink.sample(1_100_000_000, 1100, MOTION, MOTION, 2, 1_100_000_000, ExternalInputDecoder.MAX_U64, false), "Unconsumed throttled sequence remains available; exactu64 watermark accepted");
            rejects(() -> sink.sample(1_200_000_000, 1200, MOTION, MOTION, 3, 1_200_000_000, BigInteger.ZERO, true), "Regressing dispatch watermark accepted");
            sink.finish(1200, "passed", "Audit only\n\"quoted\"\\reason"); stopped(sink);
            check(!sink.sample(1_300_000_000, 1300, MOTION, MOTION, 3, 1_300_000_000, ExternalInputDecoder.MAX_U64, true), "No append after terminal");
            var lines = records(output); check(lines.size() == 4 && sink.records() == 4, "BEGIN,two samples,END only");
            Set<String> common = Set.of("schema", "kind", "source_kind", "audit_only", "follower_eligible", "control_ownership_verified",
                    "kcd_movement_applied", "coordinate_space", "run", "target_pid", "target_start_filetime", "patch_run", "patch_sha256",
                    "view_seed_sha256", "ground_source_kind", "fixture", "save", "world", "seq", "utc_ms");
            for (int i = 0; i < lines.size(); i++) {
                var value = lines.get(i); check(value.get("seq").getAsLong() == i + 1, "Consecutive record sequence");
                check(value.get("audit_only").getAsBoolean() && !value.get("follower_eligible").getAsBoolean() &&
                        !value.get("control_ownership_verified").getAsBoolean() && !value.get("kcd_movement_applied").getAsBoolean(), "No authority or KCD movement claim");
                Set<String> expected = new HashSet<>(common);
                expected.addAll(i == 0 ? Set.of("center", "anchor_mc", "initial_mc_baseline", "view_kind") : i == 3 ?
                        Set.of("result", "reason", "last_server_seq", "last_input_dispatch_watermark") :
                        Set.of("server_seq", "server_age_ns", "input_dispatch_watermark", "client", "server", "kcd_target"));
                check(value.keySet().equals(expected), "Exact record fields; no invented input ACK/epoch/lease");
            }
            near(lines.get(0).getAsJsonObject("initial_mc_baseline").get("x").getAsDouble(), 0.5, "Actual MC baseline exposes spawn offset");
            var target = lines.get(1).getAsJsonObject("kcd_target"); near(target.get("x").getAsDouble(), 100.5, "Patch-spaceX mapping");
            near(target.get("y").getAsDouble(), 199.5, "Patch-spaceY mapping reverses MCZ"); near(target.get("z").getAsDouble(), 56, "Patch-spaceZ anchor64");
            var forward = target.getAsJsonObject("forward"); near(forward.get("x").getAsDouble(), -0.6963642403200189, "Yaw45 pitch-10 forwardX");
            near(forward.get("y").getAsDouble(), -0.696364240320019, "Yaw45 pitch-10 forwardY"); near(forward.get("z").getAsDouble(), 0.17364817766693033, "Yaw45 pitch-10 forwardZ");
            check(lines.get(2).get("input_dispatch_watermark").getAsString().equals("18446744073709551615"), "u64 watermark retained as exact decimal string");
            check(lines.get(3).get("last_server_seq").getAsLong() == 2 && lines.get(3).get("last_input_dispatch_watermark").getAsString().equals(ExternalInputDecoder.MAX_U64.toString()), "END identifies committed final sample");
            check(lines.get(3).get("reason").getAsString().equals("Audit only\n\"quoted\"\\reason"), "Reason JSON escaping round-trips");

            rejects(() -> new ExternalInputPoseSink.Motion(2.01, 64, 0, 0, 0, 0, true, true, 0, 0), "Horizontal motion boundary accepted");
            rejects(() -> new ExternalInputPoseSink.Motion(0, 64, 0, 0, 4.01, 0, true, true, 0, 0), "Velocity boundary accepted");
            rejects(() -> new ExternalInputPoseSink.Motion(0, 64, 0, 0, 0, 0, true, true, Double.NaN, 0), "Nonfinite camera accepted");
            near(new ExternalInputPoseSink.Motion(0, 64, 0, 0, 0, 0, true, true, 540, 90).yaw(), -180, "Yaw normalized without changing direction");

            Path boundedOutput = evidence.resolve("bounded.ndjson"); var bounded = start(root, boundedOutput);
            for (int i = 1; i <= ExternalInputPoseSink.MAX_RECORDS - 2; i++) {
                check(bounded.sample(i * 100_000_000L, 2000 + i, MOTION, MOTION, i, i * 100_000_000L, BigInteger.valueOf(i), true), "Bounded sample committed");
                if (i % 16 == 0) waitFlushed(bounded, boundedOutput); // Test-only IO; no game-thread wait API added.
            }
            rejects(() -> bounded.sample(99_000_000_000L, 3000, MOTION, MOTION, 600, 99_000_000_000L, BigInteger.valueOf(600), true), "Reserved terminal record was spent by sample");
            bounded.finish(3000, "failed", "Record budget exhausted"); stopped(bounded);
            check(records(boundedOutput).size() == ExternalInputPoseSink.MAX_RECORDS, "Reserved END survives sample record limit");

            Path closedOutput = evidence.resolve("closed.ndjson"); var closed = start(root, closedOutput); closed.close(); stopped(closed);
            var closedLines = records(closedOutput); check(closedLines.size() == 2 && closedLines.get(1).get("result").getAsString().equals("stopped"), "Signal-only close records stopped terminal");
            System.out.println("ExternalInputPoseSinkTests: " + checks + " checks passed (standalone audit output only)");
        } finally {
            try (var paths = Files.walk(root)) { for (Path file : paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(file); }
        }
    }
}
