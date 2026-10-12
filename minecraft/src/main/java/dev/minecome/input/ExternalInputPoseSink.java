package dev.minecome.input;

import java.io.*;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Audit-only scalar poses. The daemon owns every output filesystem operation; no game APIs enter it. */
public final class ExternalInputPoseSink implements AutoCloseable {
    public static final int MAX_RECORDS = 512, MAX_BYTES = 1_048_576, MAX_LINE_BYTES = 4096, QUEUE_CAPACITY = 64;
    public static final long PERIOD_NANOS = 100_000_000L, MAX_SERVER_AGE_NANOS = 250_000_000L;
    private static final int END_RESERVE = 4096;
    public record Vec3(double x, double y, double z) {
        public Vec3 { if (!finite(x, y, z)) throw new IllegalArgumentException("Nonfinite pose vector"); }
    }
    public record Context(ExternalInputSessionGate.Identity input, String patchRun, String patchSha256,
                          String viewSeedSha256, String groundSourceKind, boolean fixture, String save, String world,
                          Vec3 center, Vec3 initialMcBaseline) {
        public Context {
            Objects.requireNonNull(input); Objects.requireNonNull(center); Objects.requireNonNull(initialMcBaseline);
            if (!patchRun.matches("[A-Za-z0-9_-]{1,128}") || !patchSha256.matches("[0-9a-f]{64}") ||
                    !viewSeedSha256.matches("[0-9a-f]{64}") || !Set.of("standalone_fixture", "live_kcd_ground_patch").contains(groundSourceKind) ||
                    (!fixture && groundSourceKind.equals("standalone_fixture")) ||
                    !world.equals(UUID.fromString(world).toString()) || !save.equals("MineCome-ExternalInput-" + world) ||
                    Math.abs(center.x()) > 10_000_000 || Math.abs(center.y()) > 10_000_000 || Math.abs(center.z()) > 10_000_000 ||
                    Math.abs(initialMcBaseline.x()) > 2 || Math.abs(initialMcBaseline.z()) > 2 ||
                    initialMcBaseline.y() < 52 || initialMcBaseline.y() > 76)
                throw new IllegalArgumentException("Invalid external pose context");
        }
    }
    public record Motion(double x, double y, double z, double vx, double vy, double vz,
                         boolean onGround, boolean proxySupport, double yaw, double pitch) {
        public Motion {
            if (!finite(x, y, z, vx, vy, vz, yaw, pitch) || Math.abs(x) > 2 || Math.abs(z) > 2 || y < 52 || y > 76 ||
                    Math.abs(vx) > 4 || Math.abs(vy) > 4 || Math.abs(vz) > 4 || pitch < -90 || pitch > 90)
                throw new IllegalArgumentException("Invalid external pose motion");
            yaw = wrapYaw(yaw);
        }
    }
    private record Packet(byte[] bytes, boolean terminal) {}
    private final Path projectRoot, requested;
    private final Context context;
    private final byte[] begin;
    private final ArrayBlockingQueue<Packet> queue = new ArrayBlockingQueue<>(QUEUE_CAPACITY);
    private final AtomicBoolean ready = new AtomicBoolean(), finished = new AtomicBoolean();
    private final AtomicReference<IOException> failure = new AtomicReference<>();
    private Thread worker;
    private long sequence = 1, lastServerSequence, lastSampleNanos;
    private BigInteger lastWatermark = BigInteger.ZERO;
    private int bytes;
    private boolean sampled, endQueued;

    /** Syntax/scalars only; start() performs path validation, CREATE_NEW, write and close on its daemon. */
    public ExternalInputPoseSink(Path projectRoot, Path requested, Context context, long utcMillis) throws IOException {
        if (projectRoot == null || requested == null || !projectRoot.isAbsolute() || !requested.isAbsolute() ||
                requested.getFileName() == null || !requested.getFileName().toString().matches("[A-Za-z0-9_.-]{1,80}"))
            throw new IOException("External pose output requires absolute project/new-file paths");
        this.projectRoot = projectRoot.normalize(); this.requested = requested.normalize(); this.context = Objects.requireNonNull(context);
        begin = line(prefix("begin", 1, utcMillis) + ",\"center\":" + vector(context.center()) +
                ",\"anchor_mc\":{\"x\":0,\"y\":64,\"z\":0},\"initial_mc_baseline\":" + vector(context.initialMcBaseline()) +
                ",\"view_kind\":\"vanilla_player_yaw_pitch\"}");
        bytes = begin.length;
    }
    public synchronized void start() {
        if (worker != null) throw new IllegalStateException("External pose sink cannot restart");
        worker = new Thread(this::write, "MineComeExternalInputPoseSink"); worker.setDaemon(true); worker.start();
    }
    public boolean isReady() { return ready.get() && failure.get() == null; }
    /** True only after the terminal record was flushed and the output was closed (or a failure ended the worker). */
    public boolean isFinished() { return finished.get(); }
    public IOException failure() { return failure.get(); }
    public synchronized long records() { return sequence; }
    public synchronized int byteCount() { return bytes; }

    /** False means throttled/stale/reused observation; no state or sequence is committed. */
    public synchronized boolean sample(long nowNanos, long utcMillis, Motion client, Motion server,
                                       long serverSequence, long serverReceivedAtNanos, BigInteger dispatchWatermark,
                                       boolean force) throws IOException {
        checkFailure();
        if (endQueued || !ready.get()) return false;
        long age = nowNanos - serverReceivedAtNanos;
        if (age < 0 || age > MAX_SERVER_AGE_NANOS || serverSequence < 1 || serverSequence <= lastServerSequence) return false;
        if (dispatchWatermark == null || dispatchWatermark.signum() < 0 || dispatchWatermark.compareTo(ExternalInputDecoder.MAX_U64) > 0 ||
                dispatchWatermark.compareTo(lastWatermark) < 0) throw new IOException("Invalid/regressing input dispatch watermark");
        if (sampled && (nowNanos < lastSampleNanos || (!force && nowNanos - lastSampleNanos < PERIOD_NANOS))) return false;
        String body = prefix("sample", sequence + 1, utcMillis) + ",\"server_seq\":" + serverSequence + ",\"server_age_ns\":" + age +
                ",\"input_dispatch_watermark\":" + quote(dispatchWatermark.toString()) + ",\"client\":" + motion(client) +
                ",\"server\":" + motion(server) + ",\"kcd_target\":" + target(context, server) + "}";
        offer(line(body), false);
        lastServerSequence = serverSequence; lastWatermark = dispatchWatermark; lastSampleNanos = nowNanos; sampled = true;
        return true;
    }
    /** Queues one reserved terminal record. The game thread polls isFinished()/failure() instead of waiting. */
    public synchronized void finish(long utcMillis, String result, String reason) throws IOException {
        if (endQueued || finished.get()) return;
        if (!Set.of("passed", "failed", "stopped").contains(result)) throw new IllegalArgumentException("Invalid pose result");
        if (result.equals("passed") && failure.get() != null) throw failure.get();
        if (result.equals("passed") && !sampled) throw new IOException("Passed pose output requires a committed final sample");
        String message = Objects.requireNonNull(reason);
        if (message.codePointCount(0, message.length()) > 160) message = message.substring(0, message.offsetByCodePoints(0, 160));
        byte[] end = line(prefix("end", sequence + 1, utcMillis) + ",\"result\":" + quote(result) + ",\"reason\":" + quote(message) +
                ",\"last_server_seq\":" + lastServerSequence + ",\"last_input_dispatch_watermark\":" + quote(lastWatermark.toString()) + "}");
        offer(end, true); endQueued = true;
    }
    /** Signal-only best-effort terminal; never opens, flushes, closes or joins on the caller. */
    @Override public synchronized void close() {
        try { finish(System.currentTimeMillis(), "stopped", "Pose writer closed before explicit lab result"); }
        catch (IOException error) { failure.compareAndSet(null, error); }
    }
    /** Pure test/controller wait only. Never call from a Minecraft tick/lifecycle callback. */
    public boolean awaitFinished(long millis) throws InterruptedException {
        if (millis < 1 || millis > 1000) throw new IllegalArgumentException("Wait must be1..1000ms");
        Thread thread; synchronized (this) { thread = worker; }
        if (thread == null || thread == Thread.currentThread()) return false;
        thread.join(millis); return finished.get() && !thread.isAlive();
    }
    private void checkFailure() throws IOException { if (failure.get() != null) throw failure.get(); }
    private void offer(byte[] record, boolean terminal) throws IOException {
        if (sequence >= (terminal ? MAX_RECORDS : MAX_RECORDS - 1) || bytes + record.length > MAX_BYTES - (terminal ? 0 : END_RESERVE))
            throw new IOException("External pose record/byte budget exhausted");
        if ((!terminal && queue.size() >= QUEUE_CAPACITY - 1) || !queue.offer(new Packet(record, terminal)))
            throw new IOException("External pose output mailbox overflow");
        sequence++; bytes += record.length;
    }
    private void write() {
        try {
            Path root = projectRoot.toRealPath(), evidence = projectRoot.resolve("runtime/evidence").toRealPath();
            Path parent = requested.getParent().toRealPath();
            if (!Files.isDirectory(root) || !Files.isDirectory(evidence) || !evidence.startsWith(root) || evidence.equals(root) || !parent.startsWith(evidence))
                throw new IOException("External pose output escapes resolved runtime/evidence");
            Path target = parent.resolve(requested.getFileName());
            try (var output = new BufferedOutputStream(Files.newOutputStream(target, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE), 4096)) {
                output.write(begin); output.flush(); ready.set(true);
                while (true) {
                    Packet packet = queue.take(); output.write(packet.bytes()); output.flush();
                    if (packet.terminal()) break;
                }
            }
        } catch (IOException error) { failure.compareAndSet(null, error); }
        catch (InterruptedException error) { Thread.currentThread().interrupt(); failure.compareAndSet(null, new IOException("Pose output interrupted", error)); }
        catch (RuntimeException error) { failure.compareAndSet(null, new IOException("Pose output failed", error)); }
        finally { finished.set(true); }
    }
    private String prefix(String kind, long recordSequence, long utcMillis) {
        if (utcMillis < 1) throw new IllegalArgumentException("Invalid pose UTC timestamp");
        var id = context.input();
        return "{\"schema\":1,\"kind\":" + quote(kind) + ",\"source_kind\":\"external_input_mc_pose_v1\",\"audit_only\":true," +
                "\"follower_eligible\":false,\"control_ownership_verified\":false,\"kcd_movement_applied\":false,\"coordinate_space\":\"patch_space\"," +
                "\"run\":" + quote(id.run()) + ",\"target_pid\":" + id.targetPid() + ",\"target_start_filetime\":" + quote(id.targetStartFiletime()) +
                ",\"patch_run\":" + quote(context.patchRun()) + ",\"patch_sha256\":" + quote(context.patchSha256()) +
                ",\"view_seed_sha256\":" + quote(context.viewSeedSha256()) + ",\"ground_source_kind\":" + quote(context.groundSourceKind()) +
                ",\"fixture\":" + context.fixture() + ",\"save\":" + quote(context.save()) + ",\"world\":" + quote(context.world()) +
                ",\"seq\":" + recordSequence + ",\"utc_ms\":" + utcMillis;
    }
    private static byte[] line(String body) throws IOException {
        byte[] record = (body + "\n").getBytes(StandardCharsets.UTF_8);
        if (record.length > MAX_LINE_BYTES) throw new IOException("External pose line exceeds4096bytes"); return record;
    }
    private static String vector(Vec3 value) { return "{\"x\":" + value.x() + ",\"y\":" + value.y() + ",\"z\":" + value.z() + "}"; }
    private static String motion(Motion m) {
        return "{\"x\":" + m.x() + ",\"y\":" + m.y() + ",\"z\":" + m.z() + ",\"vx\":" + m.vx() + ",\"vy\":" + m.vy() +
                ",\"vz\":" + m.vz() + ",\"on_ground\":" + m.onGround() + ",\"proxy_support\":" + m.proxySupport() +
                ",\"yaw\":" + m.yaw() + ",\"pitch\":" + m.pitch() + "}";
    }
    private static String target(Context c, Motion m) {
        double yaw = Math.toRadians(m.yaw()), pitch = Math.toRadians(m.pitch()), cosine = Math.cos(pitch);
        return "{\"x\":" + (c.center().x() + m.x()) + ",\"y\":" + (c.center().y() - m.z()) + ",\"z\":" + (c.center().z() + m.y() - 64) +
                ",\"forward\":" + vector(new Vec3(-Math.sin(yaw) * cosine, -Math.cos(yaw) * cosine, -Math.sin(pitch))) + "}";
    }
    private static double wrapYaw(double yaw) { double result = yaw % 360; if (result >= 180) result -= 360; if (result < -180) result += 360; return result; }
    private static boolean finite(double... values) { for (double value : values) if (!Double.isFinite(value)) return false; return true; }
    private static String quote(String value) {
        var text = new StringBuilder("\"");
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"' -> text.append("\\\""); case '\\' -> text.append("\\\\"); case '\n' -> text.append("\\n"); case '\r' -> text.append("\\r"); case '\t' -> text.append("\\t");
                default -> { if (c < 32) text.append(String.format(Locale.ROOT, "\\u%04x", (int) c)); else text.append(c); }
            }
        }
        return text.append('"').toString();
    }
}
