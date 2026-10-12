package dev.minecome.input;

import com.google.gson.*;
import java.io.IOException;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/** Standalone transport/gate fixtures: no game classes, process calls, file capture or key injection. */
public final class ExternalInputTests {
    private static int checks;
    private static final String RUN = "0123456789abcdef0123456789abcdef";
    private static final String FILETIME = "134054567890123456";
    private static void check(boolean value, String message) {
        checks++; if (!value) throw new AssertionError(message);
    }
    private static byte[] bytes(String value) { return value.getBytes(StandardCharsets.UTF_8); }
    private static JsonObject record(String kind, long seq, long utc, long monotonic) {
        JsonObject value = new JsonObject();
        value.addProperty("schema", 1); value.addProperty("kind", kind);
        value.addProperty("source_kind", "windows_raw_input_v1"); value.addProperty("run", RUN);
        value.addProperty("seq", seq); value.addProperty("utc_ms", utc); value.addProperty("monotonic_ms", monotonic);
        value.addProperty("target_pid", 47092); value.addProperty("target_start_filetime", FILETIME);
        value.addProperty("focused", false); value.addProperty("armed", false);
        JsonObject held = new JsonObject();
        for (String key : new String[] { "forward", "back", "left", "right", "jump", "sprint" }) held.addProperty(key, false);
        value.add("held", held); value.addProperty("mouse_dx", 0); value.addProperty("mouse_dy", 0);
        if (kind.equals("end")) value.addProperty("reason", "duration");
        return value;
    }
    private static JsonObject sample(long seq, long utc, long monotonic, boolean forward, int dx, int dy) {
        var value = record("sample", seq, utc, monotonic);
        value.addProperty("focused", true); value.addProperty("armed", true);
        value.getAsJsonObject("held").addProperty("forward", forward);
        value.addProperty("mouse_dx", dx); value.addProperty("mouse_dy", dy);
        return value;
    }
    private static ExternalInputSessionGate gate() {
        return new ExternalInputSessionGate(new ExternalInputSessionGate.Identity(RUN, 47092, FILETIME));
    }
    private static void receive(ExternalInputSessionGate gate, JsonObject value, long utc, long nanos) throws IOException {
        gate.receive(bytes(value.toString()), utc, nanos);
    }
    private static void reject(String value) {
        try { ExternalInputDecoder.decode(bytes(value)); throw new AssertionError("Malformed record accepted: " + value); }
        catch (IOException expected) { checks++; }
    }
    private static void reject(JsonObject value) { reject(value.toString()); }
    private static void rejectGate(ExternalInputSessionGate gate, JsonObject value, long utc, long nanos) {
        rejectGateBytes(gate, value.toString(), utc, nanos);
    }
    private static void rejectGateBytes(ExternalInputSessionGate gate, String value, long utc, long nanos) {
        try { gate.receive(bytes(value), utc, nanos); throw new AssertionError("Invalid session input accepted"); }
        catch (IOException expected) {
            check(gate.closed(), "Bad record closes session");
            check(gate.consume(nanos, true).equals(ExternalInputSessionGate.Input.NEUTRAL), "Bad record clears held controls and mouse");
        }
    }
    private static ExternalInputSessionGate ready(long nanos) throws IOException {
        var gate = gate(); receive(gate, record("begin", 1, 1000, 0), 1000, nanos);
        receive(gate, sample(2, 1050, 50, false, 0, 0), 1050, nanos + 50_000_000L);
        return gate;
    }
    private static void rejectRecording(Path path, String content) throws IOException {
        Files.writeString(path, content);
        try { ExternalInputRecordingCheck.validate(path); throw new AssertionError("Invalid historical recording accepted"); }
        catch (IOException expected) { checks++; }
    }
    public static void main(String[] args) throws Exception {
        var begin = ExternalInputDecoder.decode(bytes(record("begin", 1, 1000, 0).toString() + "\r\n"));
        check(begin.kind() == ExternalInputRecord.Kind.BEGIN && begin.neutral(), "Valid common neutral begin contract");
        var max = sample(2, 1050, 50, false, 32767, -32767);
        max.addProperty("seq", ExternalInputDecoder.MAX_U64);
        max.addProperty("target_pid", new BigInteger("4294967295"));
        max.addProperty("target_start_filetime", ExternalInputDecoder.MAX_U64.toString());
        var decoded = ExternalInputDecoder.decode(bytes(max.toString()));
        check(decoded.sequence().equals(ExternalInputDecoder.MAX_U64) && decoded.targetPid() == 0xffff_ffffL,
                "Numeric u64 sequence and u32 PID decoded without double precision loss");
        check(decoded.mouseDx() == 32767 && decoded.mouseDy() == -32767, "Signed bounded relative mouse counts");
        for (String key : new String[] { "schema", "kind", "source_kind", "run", "seq", "utc_ms", "monotonic_ms",
                "target_pid", "target_start_filetime", "focused", "armed", "held", "mouse_dx", "mouse_dy" }) {
            var malformed = record("begin", 1, 1000, 0); malformed.remove(key); reject(malformed);
        }
        var extra = record("begin", 1, 1000, 0); extra.addProperty("counters", 0); reject(extra);
        var bad = record("begin", 1, 1000, 0); bad.addProperty("source_kind", "synthetic_input"); reject(bad);
        for (String run : new String[] { "", "0".repeat(31), "A".repeat(32), RUN + "0", "../" + RUN }) {
            bad = record("begin", 1, 1000, 0); bad.addProperty("run", run); reject(bad);
        }
        for (String filetime : new String[] { "0", "01", "-1", "+1", "1.0", "18446744073709551616" }) {
            bad = record("begin", 1, 1000, 0); bad.addProperty("target_start_filetime", filetime); reject(bad);
        }
        for (String key : new String[] { "schema", "seq", "utc_ms", "monotonic_ms", "target_pid", "mouse_dx", "mouse_dy" }) {
            bad = record("begin", 1, 1000, 0); bad.addProperty(key, "1"); reject(bad);
            bad = record("begin", 1, 1000, 0); bad.addProperty(key, 0.5); reject(bad);
        }
        bad = record("begin", 1, 1000, 0); bad.addProperty("target_start_filetime", 123); reject(bad);
        bad = record("sample", 2, 1050, 50); bad.addProperty("target_pid", 0); reject(bad);
        bad = record("sample", 2, 1050, 50); bad.addProperty("target_pid", new BigInteger("4294967296")); reject(bad);
        bad = record("sample", 2, 1050, 50); bad.addProperty("seq", 0); reject(bad);
        bad = record("sample", 2, 1050, 50); bad.addProperty("seq", ExternalInputDecoder.MAX_U64.add(BigInteger.ONE)); reject(bad);
        bad = record("sample", 2, 0, 50); reject(bad);
        bad = record("sample", 2, 1050, -1); reject(bad);
        bad = record("begin", 1, 1000, 0); bad.addProperty("focused", 0); reject(bad);
        bad = record("begin", 1, 1000, 0); bad.getAsJsonObject("held").addProperty("jump", "false"); reject(bad);
        bad = record("begin", 1, 1000, 0); bad.getAsJsonObject("held").addProperty("attack", false); reject(bad);
        bad = sample(2, 1050, 50, false, 32768, 0); reject(bad);
        bad = sample(2, 1050, 50, false, 0, -32768); reject(bad);
        bad = record("begin", 2, 1000, 0); reject(bad);
        bad = record("begin", 1, 1000, 1); reject(bad);
        bad = record("begin", 1, 1000, 0); bad.addProperty("armed", true); reject(bad);
        bad = record("end", 2, 1100, 100); bad.getAsJsonObject("held").addProperty("sprint", true); reject(bad);
        bad = record("end", 2, 1100, 100); bad.addProperty("reason", "ok"); reject(bad);
        bad = record("end", 2, 1100, 100); bad.remove("reason"); reject(bad);
        bad = sample(2, 1050, 50, true, 0, 0); bad.addProperty("focused", false); reject(bad);
        bad = sample(2, 1050, 50, false, 0, 0); bad.addProperty("focused", false); reject(bad);
        bad = sample(2, 1050, 50, false, 1, 0); bad.addProperty("armed", false); reject(bad);
        String valid = record("begin", 1, 1000, 0).toString();
        reject(valid.replace("\"schema\":1", "\"schema\":1,\"schema\":1"));
        reject(valid.replace("\"jump\":false", "\"jump\":false,\"jump\":false"));
        reject(valid.replace("\"mouse_dx\":0", "\"mouse_dx\":NaN"));
        reject(valid.replace("\"mouse_dx\":0", "\"mouse_dx\":1e999999999"));
        reject(valid.replace("\"mouse_dx\":0", "\"mouse_dx\":1e-2147483647"));
        reject(valid.replace("\"mouse_dx\":0", "\"mouse_dx\":0e-2147483647"));
        reject(valid.replace("\"mouse_dx\":0", "\"mouse_dx\":1e2147483647"));
        reject(valid.replace("\"mouse_dx\":0", "\"mouse_dx\":0e2147483647"));
        reject(valid.replace("\"schema\":1", "\"schema\":01"));
        reject("\ufeff" + valid);
        reject(valid.replace("\"focused\":false", "\"focused\":null"));
        reject(valid + "{}"); reject(valid + "\n" + valid); reject(" ".repeat(ExternalInputDecoder.MAX_RECORD_BYTES + 1));
        try { ExternalInputDecoder.decode(new byte[] { (byte) 0xc3, (byte) 0x28 }); throw new AssertionError("Bad UTF8 accepted"); }
        catch (IOException expected) { checks++; }

        var gate = ready(0);
        check(gate.consume(50_000_000L, true).active(), "Fresh released-controls sample opens gate");
        receive(gate, sample(3, 1100, 100, true, 9, -3), 1100, 100_000_000L);
        var output = gate.consume(110_000_000L, true);
        check(output.active() && output.held().forward() && output.mouseDx() == 9 && output.mouseDy() == -3, "Fresh held and mouse delivered");
        output = gate.consume(120_000_000L, true);
        check(output.held().forward() && output.mouseDx() == 0 && output.mouseDy() == 0, "Mouse delivered once while fresh held keys persist");
        check(gate.consume(400_000_000L, true).equals(ExternalInputSessionGate.Input.NEUTRAL), "Local 300ms lease expires at boundary");
        receive(gate, sample(4, 1450, 450, true, 9, 0), 1450, 450_000_000L);
        check(!gate.consume(450_000_000L, true).active(), "Expired stream cannot resurrect held or mouse without neutral re-arm");
        receive(gate, sample(5, 1500, 500, false, 0, 0), 1500, 500_000_000L);
        receive(gate, sample(6, 1550, 550, true, 2, 0), 1550, 550_000_000L);
        check(gate.consume(550_000_000L, true).held().forward(), "Fresh released-controls then fresh key sample re-arms");
        check(!gate.consume(550_000_000L, false).active(), "Local menu gate is neutral");
        receive(gate, sample(7, 1600, 600, true, 2, 0), 1600, 600_000_000L);
        check(!gate.consume(600_000_000L, true).active(), "Menu suppression cannot resume stored held controls");
        receive(gate, sample(8, 1650, 650, false, 0, 0), 1650, 650_000_000L);
        receive(gate, sample(9, 1700, 700, true, 3, 0), 1700, 700_000_000L);
        var unfocused = record("sample", 10, 1750, 750);
        receive(gate, unfocused, 1750, 750_000_000L);
        check(!gate.consume(750_000_000L, true).active(), "Focus loss resets held/mouse");
        receive(gate, sample(11, 1800, 800, true, 3, 0), 1800, 800_000_000L);
        check(!gate.consume(800_000_000L, true).active(), "Refocus requires neutral sample");
        receive(gate, record("end", 12, 1850, 850), 1850, 850_000_000L);
        check(gate.closed() && !gate.consume(850_000_000L, true).active(), "End permanently neutralizes session");
        rejectGate(gate, sample(13, 1900, 900, false, 0, 0), 1900, 900_000_000L);

        gate = ready(0); receive(gate, sample(3, 1100, 100, true, 5, 0), 1350, 100_000_000L);
        check(gate.consume(149_999_999L, true).active(), "250ms wire observation age leaves50ms local lease");
        check(!gate.consume(150_000_000L, true).active(), "Wire age plus local lease never exceeds300ms");
        gate = ready(0); receive(gate, sample(3, 1100, 100, true, 5, 0), 1100, 100_000_000L);
        receive(gate, sample(4, 1450, 450, true, 5, 0), 1450, 450_000_000L);
        check(!gate.consume(450_000_000L, true).active(), "Receive-before-consume still detects lease gap and refuses held restart");
        gate = ready(0); receive(gate, sample(3, 1100, 100, true, 7, 0), 1100, 100_000_000L);
        gate.disconnect(); check(gate.closed() && !gate.consume(100_000_000L, true).active(), "Disconnect clears controls permanently");
        gate = gate(); receive(gate, record("begin", 1, 2000, 0), 2000, 1_000_000_000L);
        receive(gate, sample(2, 2050, 50, true, 7, 0), 2050, 1_050_000_000L);
        check(!gate.consume(1_050_000_000L, true).active(), "New session does not resume previously held controls");

        rejectGate(gate(), sample(2, 1050, 50, false, 0, 0), 1050, 0);
        gate = ready(0); rejectGate(gate, sample(2, 1100, 100, false, 0, 0), 1100, 100_000_000L);
        gate = ready(0); rejectGate(gate, sample(1, 1100, 100, false, 0, 0), 1100, 100_000_000L);
        gate = ready(0); rejectGate(gate, sample(3, 1100, 49, false, 0, 0), 1100, 100_000_000L);
        gate = ready(0); rejectGate(gate, record("begin", 1, 1100, 0), 1100, 100_000_000L);
        gate = ready(0); bad = sample(3, 1100, 100, false, 0, 0); bad.addProperty("run", "f".repeat(32)); rejectGate(gate, bad, 1100, 100_000_000L);
        gate = ready(0); bad = sample(3, 1100, 100, false, 0, 0); bad.addProperty("target_pid", 47093); rejectGate(gate, bad, 1100, 100_000_000L);
        gate = ready(0); bad = sample(3, 1100, 100, false, 0, 0); bad.addProperty("target_start_filetime", "134054567890123457"); rejectGate(gate, bad, 1100, 100_000_000L);
        gate = ready(0); rejectGate(gate, sample(3, 1100, 100, false, 0, 0), 1401, 100_000_000L);
        gate = ready(0); rejectGate(gate, sample(3, 1100, 100, false, 0, 0), 1049, 100_000_000L);
        gate = ready(0); receive(gate, sample(3, 1100, 100, true, 5, 2), 1100, 100_000_000L);
        bad = sample(4, 1150, 150, false, 0, 0); bad.addProperty("focused", false);
        rejectGate(gate, bad, 1150, 150_000_000L);
        gate = ready(0); receive(gate, sample(3, 1100, 100, true, 5, 2), 1100, 100_000_000L);
        rejectGateBytes(gate, sample(4, 1150, 150, true, 0, 0).toString().replace("\"mouse_dx\":0", "\"mouse_dx\":1e-2147483647"),
                1150, 150_000_000L);
        gate = ready(0); receive(gate, sample(3, 1100, 100, true, 5, 2), 1100, 100_000_000L);
        rejectGateBytes(gate, sample(4, 1150, 150, true, 0, 0).toString().replace("\"mouse_dy\":0", "\"mouse_dy\":1e2147483647"),
                1150, 150_000_000L);
        gate = ready(0); check(!gate.consume(120_000_000_001L, true).active() && gate.closed(), "Independent120sec local session deadline");
        gate = ready(0); check(!gate.consume(-1, true).active() && gate.closed(), "Local clock regression is fail neutral");
        gate = ready(0); bad = sample(3, 1100, 100, false, 0, 0); bad.addProperty("seq", new BigInteger("9223372036854775808"));
        receive(gate, bad, 1100, 100_000_000L);
        check(gate.lastSequence().equals(new BigInteger("9223372036854775808")), "Gate retains unsigned64 ordering beyond signed long");
        rejectGate(gate, sample(4, 1150, 150, false, 0, 0), 1150, 150_000_000L);
        gate = gate(); receive(gate, record("begin", 1, 1000, 0), 1000, 0);
        for (int index = 2; index <= ExternalInputSessionGate.MAX_RECORDS; index++)
            receive(gate, record("sample", index, 1000, 0), 1000, index);
        rejectGate(gate, record("sample", ExternalInputSessionGate.MAX_RECORDS + 1, 1000, 0), 1000, 3000);

        gate = ready(0);
        receive(gate, sample(3, 1100, 100, true, 12, -5), 1100, 100_000_000L);
        receive(gate, sample(4, 1150, 150, true, 8, 2), 1150, 150_000_000L);
        output = gate.consume(150_000_000L, true);
        check(output.mouseDx() == 20 && output.mouseDy() == -3, "Two fresh receive frames accumulate relative mouse motion before consume");
        output = gate.consume(150_000_000L, true);
        check(output.mouseDx() == 0 && output.mouseDy() == 0, "Accumulated mouse sum is consumed exactly once");
        gate = ready(0);
        receive(gate, sample(3, 1100, 100, true, 20, -10), 1100, 100_000_000L);
        receive(gate, record("sample", 4, 1150, 150), 1150, 150_000_000L);
        receive(gate, sample(5, 1200, 200, false, 0, 0), 1200, 200_000_000L);
        receive(gate, sample(6, 1250, 250, false, 3, 2), 1250, 250_000_000L);
        output = gate.consume(250_000_000L, true);
        check(output.mouseDx() == 3 && output.mouseDy() == 2, "Inactive/focus reset discards old unconsumed relative motion");
        gate = ready(0);
        receive(gate, sample(3, 1100, 100, true, 20, -10), 1100, 100_000_000L);
        gate.consume(100_000_000L, false);
        receive(gate, sample(4, 1150, 150, false, 0, 0), 1150, 150_000_000L);
        receive(gate, sample(5, 1200, 200, false, 3, 2), 1200, 200_000_000L);
        output = gate.consume(200_000_000L, true);
        check(output.mouseDx() == 3 && output.mouseDy() == 2, "Local menu reset discards old unconsumed mouse");
        gate = ready(0);
        receive(gate, sample(3, 1100, 100, true, 20, -10), 1100, 100_000_000L);
        receive(gate, sample(4, 1400, 400, false, 0, 0), 1400, 400_000_000L);
        receive(gate, sample(5, 1450, 450, false, 3, 2), 1450, 450_000_000L);
        output = gate.consume(450_000_000L, true);
        check(output.mouseDx() == 3 && output.mouseDy() == 2, "Lease reset and fresh neutral barrier discard old mouse before re-arm");
        gate = ready(0);
        receive(gate, sample(3, 1100, 100, true, 20, -10), 1100, 100_000_000L);
        for (int index = 4; index <= 8; index++)
            receive(gate, sample(index, 1100 + (index - 3) * 50, 100 + (index - 3) * 50, true, 0, 0),
                    1100 + (index - 3) * 50, (100 + (index - 3) * 50) * 1_000_000L);
        output = gate.consume(400_000_000L, true);
        check(output.active() && output.mouseDx() == 0 && output.mouseDy() == 0,
                "New held samples cannot extend the earliest unconsumed mouse observation past300ms");
        gate = ready(0);
        receive(gate, sample(3, 1100, 100, true, 32760, 0), 1100, 100_000_000L);
        rejectGate(gate, sample(4, 1150, 150, true, 8, 0), 1150, 150_000_000L);
        gate = ready(0);
        receive(gate, sample(3, 1100, 100, true, 0, -32760), 1100, 100_000_000L);
        rejectGate(gate, sample(4, 1150, 150, true, 0, -8), 1150, 150_000_000L);

        Path recording = Files.createTempFile("minecome-historical-input-fixture-", ".ndjson");
        try {
            String history = record("begin", 1, 1000, 0) + "\n" + sample(2, 1050, 50, false, 0, 0) + "\n"
                    + sample(3, 1100, 100, true, 4, -2) + "\n" + record("end", 4, 1150, 150) + "\n";
            Files.writeString(recording, history);
            var result = ExternalInputRecordingCheck.validate(recording);
            check(result.records() == 4 && result.samples() == 2 && result.activeSamples() == 2 && result.run().equals(RUN),
                    "Historical checker replays exact native record shape with explicit fictional clocks");
            check(result.sha256().matches("[0-9a-f]{64}") && result.bytes() == bytes(history).length,
                    "Historical checker reports bounded content SHA256 and byte count");
            rejectRecording(recording, history.substring(0, history.length() - 1));
            rejectRecording(recording, record("begin", 1, 1000, 0) + "\n");
            rejectRecording(recording, history + "\n");
            rejectRecording(recording, history + sample(5, 1200, 200, false, 0, 0) + "\n");
            rejectRecording(recording, " ".repeat(ExternalInputRecordingCheck.MAX_BYTES) + "\n");
        } finally { Files.delete(recording); }
        System.out.println("ExternalInputTests: " + checks + " checks passed (pure decoder/session gate; no game input integration).");
    }
}
