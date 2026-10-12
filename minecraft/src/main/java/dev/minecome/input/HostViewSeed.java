package dev.minecome.input;

import com.google.gson.*;
import com.google.gson.stream.*;
import java.io.*;
import java.math.*;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** One immutable starting-view snapshot. This is not continuous host camera authority. */
public final class HostViewSeed {
    public static final int MAX_BYTES = 4096;
    public static final long MAX_AGE_MILLIS = 60_000, MAX_FUTURE_SKEW_MILLIS = 50;
    private static final Set<String> FIELDS = Set.of("schema", "run", "source_kind", "patch_sha256", "target_pid",
            "target_start_filetime", "captured_utc_ms", "player", "forward", "up");
    private static final Set<String> AXES = Set.of("x", "y", "z");
    public record Vec3(double x, double y, double z) {
        double length() { return Math.hypot(Math.hypot(x, y), z); }
        Vec3 normalized() { double n = length(); return new Vec3(x / n, y / n, z / n); }
        double dot(Vec3 other) { return x * other.x + y * other.y + z * other.z; }
    }
    private final ExternalInputSessionGate.Identity identity;
    private final String sourceKind, patchSha256, sha256;
    private final long capturedUtcMillis;
    private final Vec3 player, forward, up;
    private final double yawDegrees, pitchDegrees;
    private HostViewSeed(ExternalInputSessionGate.Identity identity, String sourceKind, String patchSha256,
                         String sha256, long capturedUtcMillis, Vec3 player, Vec3 forward, Vec3 up,
                         double yawDegrees, double pitchDegrees) {
        this.identity = identity; this.sourceKind = sourceKind; this.patchSha256 = patchSha256; this.sha256 = sha256;
        this.capturedUtcMillis = capturedUtcMillis; this.player = player; this.forward = forward; this.up = up;
        this.yawDegrees = yawDegrees; this.pitchDegrees = pitchDegrees;
    }
    public String sourceKind() { return sourceKind; }
    public String sha256() { return sha256; }
    public long capturedUtcMillis() { return capturedUtcMillis; }
    public double yawDegrees() { return yawDegrees; }
    public double pitchDegrees() { return pitchDegrees; }
    public Vec3 player() { return player; }
    public Vec3 forward() { return forward; }
    public Vec3 up() { return up; }

    public static HostViewSeed read(Path path, ExternalInputSessionGate.Identity expected, String patchSha256,
                                    boolean fixture, double centerX, double centerY, double centerZ, long utcNowMillis) throws IOException {
        try (var input = Files.newInputStream(path)) {
            return parse(input.readNBytes(MAX_BYTES + 1), expected, patchSha256, fixture, centerX, centerY, centerZ, utcNowMillis);
        }
    }
    public static HostViewSeed parse(byte[] bytes, ExternalInputSessionGate.Identity expected, String patchSha256,
                                     boolean fixture, double centerX, double centerY, double centerZ, long utcNowMillis) throws IOException {
        if (bytes == null || bytes.length == 0 || bytes.length > MAX_BYTES) throw new IOException("Invalid view seed byte count");
        final String text;
        try {
            text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException e) { throw new IOException("Invalid view seed UTF8", e); }
        if (text.startsWith("\ufeff")) throw new IOException("View seed BOM unsupported");
        try (var reader = new JsonReader(new StringReader(text))) {
            reader.setLenient(false);
            var value = object(readJson(reader, 0, new int[] { 0 }), "view seed");
            if (reader.peek() != JsonToken.END_DOCUMENT) throw new IOException("Trailing view seed content");
            exactKeys(value, FIELDS);
            if (!integer(value, "schema").equals(BigInteger.ONE)) throw new IOException("View seed schema mismatch");
            long pid = boundedInteger(value, "target_pid", BigInteger.ONE, BigInteger.valueOf(0xffff_ffffL)).longValueExact();
            var identity = new ExternalInputSessionGate.Identity(string(value, "run"), pid, string(value, "target_start_filetime"));
            String kind = string(value, "source_kind"), hash = string(value, "patch_sha256");
            long captured = boundedInteger(value, "captured_utc_ms", BigInteger.ONE, BigInteger.valueOf(Long.MAX_VALUE)).longValueExact();
            Vec3 player = vector(value, "player"), forward = vector(value, "forward"), up = vector(value, "up");
            if (forward.length() < 0.99 || forward.length() > 1.01 || up.length() < 0.99 || up.length() > 1.01)
                throw new IOException("View seed forward/up must be unit vectors within0.01");
            Vec3 f = forward.normalized(), u = up.normalized();
            if (Math.abs(f.dot(u)) > 0.01) throw new IOException("View seed forward/up are not orthogonal");
            double horizontal = Math.hypot(f.x(), f.y());
            if (horizontal < 0.01) throw new IOException("Near-vertical view seed unsupported");
            // Camera up with zero roll is world+Z projected perpendicular to normalized forward.
            Vec3 noRollUp = new Vec3(-f.x() * f.z(), -f.y() * f.z(), 1 - f.z() * f.z()).normalized();
            double upDot = Math.max(-1, Math.min(1, u.dot(noRollUp)));
            if (upDot < Math.cos(Math.toRadians(1))) throw new IOException("View seed camera roll exceeds1degree");
            // KCD(fx,fy,fz)->MC(fx,fz,-fy); MC yaw0 faces+Z and positivepitch looks down.
            double yaw = Math.toDegrees(Math.atan2(-f.x(), -f.y()));
            double pitch = -Math.toDegrees(Math.atan2(f.z(), horizontal));
            String contentHash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
            var seed = new HostViewSeed(identity, kind, hash, contentHash, captured, player, forward, up, yaw, pitch);
            seed.revalidate(expected, patchSha256, fixture, centerX, centerY, centerZ, utcNowMillis);
            return seed;
        } catch (IllegalArgumentException | IllegalStateException | ArithmeticException | NoSuchAlgorithmException e) {
            throw new IOException("Invalid view seed: " + e.getMessage(), e);
        }
    }
    /** Rechecks immutable identity/origin and capture age immediately before the one initial teleport. */
    public void revalidate(ExternalInputSessionGate.Identity expected, String expectedPatchSha, boolean fixture,
                           double centerX, double centerY, double centerZ, long utcNowMillis) throws IOException {
        if (!identity.equals(expected)) throw new IOException("View seed run/process identity mismatch");
        if (expectedPatchSha == null || !expectedPatchSha.matches("[0-9a-f]{64}") || !patchSha256.equals(expectedPatchSha))
            throw new IOException("View seed patch SHA256 mismatch");
        if (!sourceKind.equals(fixture ? "standalone_fixture" : "live_kcd_view_seed"))
            throw new IOException("View seed source kind/fixture mode mismatch");
        if (!Double.isFinite(centerX) || !Double.isFinite(centerY) || !Double.isFinite(centerZ) ||
                Math.hypot(Math.hypot(player.x() - centerX, player.y() - centerY), player.z() - centerZ) > 0.1)
            throw new IOException("View seed player is outside0.1m of sampled ground origin");
        final long age;
        try { age = Math.subtractExact(utcNowMillis, capturedUtcMillis); }
        catch (ArithmeticException e) { throw new IOException("View seed capture age overflow", e); }
        if (age < -MAX_FUTURE_SKEW_MILLIS || age > MAX_AGE_MILLIS) throw new IOException("View seed is stale/future");
    }
    private static JsonElement readJson(JsonReader reader, int depth, int[] count) throws IOException {
        if (depth > 2 || ++count[0] > 64) throw new IOException("View seed JSON nesting/member bound exceeded");
        return switch (reader.peek()) {
            case BEGIN_OBJECT -> {
                reader.beginObject(); var value = new JsonObject();
                while (reader.hasNext()) {
                    String name = reader.nextName();
                    if (value.has(name)) throw new IOException("Duplicate view seed field: " + name);
                    value.add(name, readJson(reader, depth + 1, count));
                }
                reader.endObject(); yield value;
            }
            case NUMBER -> {
                String text = reader.nextString();
                if (text.length() > 64 || !text.matches("-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"))
                    throw new IOException("Invalid view seed number");
                BigDecimal value = new BigDecimal(text);
                if (value.precision() > 32 || Math.abs((long) value.scale()) > 32 || !Double.isFinite(value.doubleValue()))
                    throw new IOException("View seed numeric precision/scale/finite bound exceeded");
                yield new JsonPrimitive(value);
            }
            case STRING -> new JsonPrimitive(reader.nextString());
            default -> throw new IOException("Unexpected view seed JSON value");
        };
    }
    private static JsonObject object(JsonElement value, String name) throws IOException {
        if (value == null || !value.isJsonObject()) throw new IOException(name + " must be an object"); return value.getAsJsonObject();
    }
    private static void exactKeys(JsonObject value, Set<String> keys) throws IOException {
        if (!value.keySet().equals(keys)) throw new IOException("Unexpected/missing view seed fields");
    }
    private static String string(JsonObject value, String name) throws IOException {
        JsonElement item = value.get(name);
        if (item == null || !item.isJsonPrimitive() || !item.getAsJsonPrimitive().isString()) throw new IOException(name + " must be a string");
        return item.getAsString();
    }
    private static BigDecimal number(JsonObject value, String name) throws IOException {
        JsonElement item = value.get(name);
        if (item == null || !item.isJsonPrimitive() || !item.getAsJsonPrimitive().isNumber()) throw new IOException(name + " must be a number");
        return item.getAsBigDecimal();
    }
    private static BigInteger integer(JsonObject value, String name) throws IOException {
        try { return number(value, name).toBigIntegerExact(); }
        catch (ArithmeticException e) { throw new IOException(name + " must be integral", e); }
    }
    private static BigInteger boundedInteger(JsonObject value, String name, BigInteger min, BigInteger max) throws IOException {
        BigInteger result = integer(value, name);
        if (result.compareTo(min) < 0 || result.compareTo(max) > 0) throw new IOException(name + " exceeds its bound"); return result;
    }
    private static Vec3 vector(JsonObject value, String name) throws IOException {
        var vector = object(value.get(name), name); exactKeys(vector, AXES);
        double x = number(vector, "x").doubleValue(), y = number(vector, "y").doubleValue(), z = number(vector, "z").doubleValue();
        if (!Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(z) || Math.abs(x) > 10_000_000 || Math.abs(y) > 10_000_000 || Math.abs(z) > 10_000_000)
            throw new IOException("View seed vector finite/coordinate bound exceeded");
        return new Vec3(x, y, z);
    }
}
