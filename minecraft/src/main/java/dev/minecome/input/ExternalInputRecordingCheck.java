package dev.minecome.input;

import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** Offline native-writer/Java-codec agreement check, never a live input or game-control proof. */
public final class ExternalInputRecordingCheck {
    public static final int MAX_BYTES = 1_048_576;
    public record Result(String run, long targetPid, String targetStartFiletime, String sha256,
                         int bytes, int records, int samples, int activeSamples) {}
    private ExternalInputRecordingCheck() {}

    public static Result validate(Path path) throws IOException {
        byte[] bytes;
        try (var input = Files.newInputStream(path)) { bytes = input.readNBytes(MAX_BYTES + 1); }
        if (bytes.length == 0 || bytes.length > MAX_BYTES || bytes[bytes.length - 1] != '\n')
            throw new IOException("Historical input must be a nonempty complete-LF recording <=1MiB");
        ExternalInputSessionGate gate = null;
        ExternalInputRecord first = null, last = null;
        int start = 0, records = 0, samples = 0, activeSamples = 0;
        for (int index = 0; index < bytes.length; index++) {
            if (bytes[index] != '\n') continue;
            if (++records > ExternalInputSessionGate.MAX_RECORDS || index == start)
                throw new IOException("Historical input empty line/record budget exceeded");
            byte[] line = Arrays.copyOfRange(bytes, start, index + 1); start = index + 1;
            ExternalInputRecord record = ExternalInputDecoder.decode(line);
            if (first == null) {
                first = record;
                gate = new ExternalInputSessionGate(new ExternalInputSessionGate.Identity(record.run(),
                        record.targetPid(), record.targetStartFiletime()));
            }
            final long fictionalNanos;
            try { fictionalNanos = Math.multiplyExact(record.monotonicMillis(), 1_000_000L); }
            catch (ArithmeticException e) { throw new IOException("Historical elapsed clock overflow", e); }
            // Recorded UTC is deliberately used as 'now'; this proves historical agreement
            // only. The recorded elapsed clock supplies a fictional local monotonic timeline.
            gate.receive(line, record.utcMillis(), fictionalNanos);
            var delivered = gate.consume(fictionalNanos, true);
            if (record.kind() == ExternalInputRecord.Kind.SAMPLE) { samples++; if (delivered.active()) activeSamples++; }
            if ((record.kind() != ExternalInputRecord.Kind.SAMPLE || !record.focused() || !record.armed())
                    && !delivered.equals(ExternalInputSessionGate.Input.NEUTRAL))
                throw new IOException("Historical inactive record delivered non-neutral input");
            last = record;
        }
        if (first == null || last.kind() != ExternalInputRecord.Kind.END || !gate.closed()
                || !gate.consume(0, true).equals(ExternalInputSessionGate.Input.NEUTRAL))
            throw new IOException("Historical input requires one neutral terminal end");
        final String hash;
        try { hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)); }
        catch (NoSuchAlgorithmException e) { throw new IOException("Missing SHA256 implementation", e); }
        return new Result(first.run(), first.targetPid(), first.targetStartFiletime(), hash,
                bytes.length, records, samples, activeSamples);
    }

    public static void main(String[] args) throws IOException {
        if (args.length != 1) throw new IllegalArgumentException("Expected exactly one recording path");
        Result result = validate(Path.of(args[0]));
        System.out.println("HISTORICAL_INPUT_RECORDING_VALIDATED run=" + result.run() + " records=" + result.records()
                + " samples=" + result.samples() + " active_samples=" + result.activeSamples()
                + " bytes=" + result.bytes() + " sha256=" + result.sha256()
                + " (offline recorded clocks; no live input/game-control verification)");
    }
}
