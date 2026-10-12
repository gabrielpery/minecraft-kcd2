package dev.minecome.hud;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.function.Consumer;

/** Independent wire fixtures and input ownership checks; no native objects or games. */
public final class HudInputTests {
    private static final long NOW = 1_800_000_000_000L;
    private static final long EXPIRES = NOW + 60_000;
    private static final String RUN = "0123456789abcdef0123456789abcdef";
    private static final int MAPPING_BYTES = 2_816;
    private static final HudInputProtocol.Identity ID =
        new HudInputProtocol.Identity(RUN, 321, 132_000_000_000_000_000L,
            654, 133_000_000_000_000_000L, EXPIRES);
    private static int checks;

    private static void check(boolean value, String reason) {
        checks++;
        if (!value) throw new AssertionError(reason);
    }

    private static void rejects(Runnable action, String reason) {
        try {
            action.run();
        } catch (IllegalArgumentException expected) {
            checks++;
            return;
        }
        throw new AssertionError("accepted " + reason);
    }

    private static ByteBuffer buffer(byte[] bytes) {
        return ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
    }

    private static int recordOffset(long sequence) {
        return 256 + (int) ((sequence - 1) % 64) * 40;
    }

    private static void record(byte[] bytes, long sequence, long captured,
                               int kind, int code, float x, float y, int value) {
        int offset = recordOffset(sequence);
        buffer(bytes).putLong(offset, sequence).putLong(offset + 8, captured)
            .putInt(offset + 16, kind).putInt(offset + 20, code)
            .putFloat(offset + 24, x).putFloat(offset + 28, y)
            .putInt(offset + 32, value).putInt(offset + 36, 0);
    }

    private static byte[] mapping(long sequence, int hostState) {
        byte[] bytes = new byte[MAPPING_BYTES];
        ByteBuffer b = buffer(bytes);
        b.put("MCHUDI01".getBytes(StandardCharsets.US_ASCII));
        b.putInt(8, 1).putInt(12, MAPPING_BYTES);
        b.position(16);
        b.put(RUN.getBytes(StandardCharsets.US_ASCII));
        b.putInt(48, 321).putInt(52, 654)
            .putLong(56, 132_000_000_000_000_000L)
            .putLong(64, 133_000_000_000_000_000L)
            .putLong(72, EXPIRES).putLong(80, sequence).putLong(88, NOW)
            .putInt(96, hostState).putInt(100, (int) Math.min(sequence, 64));
        for (long n = Math.max(1, sequence - 63); n <= sequence; n++) {
            record(bytes, n, NOW, (n & 1) == 1 ? 1 : 2, 0x31, 0, 0, 0);
        }
        return bytes;
    }

    private static HudInputProtocol.Snapshot decode(byte[] bytes, long fetched, int previousState) {
        return HudInputProtocol.decode(bytes, ID, fetched, NOW, previousState);
    }

    private static void altered(byte[] original, Consumer<ByteBuffer> mutate, String reason) {
        byte[] bytes = original.clone();
        mutate.accept(buffer(bytes));
        rejects(() -> decode(bytes, 0, 0), reason);
    }

    private static HudInputProtocol.Event event(long sequence, long captured,
                                               int kind, int code, float x, float y, int value) {
        return new HudInputProtocol.Event(sequence, captured, kind, code, x, y, value);
    }

    private static HudInputProtocol.Event key(long sequence, int kind, int code) {
        return event(sequence, NOW, kind, code, 0, 0, 0);
    }

    private static void headerAndIdentity() {
        byte[] empty = mapping(0, 0);
        var initial = decode(empty, 0, 0);
        check(initial.lastSequence() == 0 && initial.hostState() == 0 && initial.events().isEmpty(),
            "waiting mapping contains no events");
        check(initial.heartbeat() == NOW, "heartbeat decoded exactly");
        check(decode(mapping(0, 1), 0, 0).hostState() == 1, "waiting advances to armed");
        check(decode(mapping(0, 2), 0, 0).hostState() == 2, "waiting may close");
        check(decode(mapping(0, 2), 0, 1).hostState() == 2, "armed may close");
        check(decode(mapping(0, 2), 0, 2).events().isEmpty(), "closed polls remain terminal");
        rejects(() -> decode(new byte[MAPPING_BYTES - 1], 0, 0), "short mapping");
        rejects(() -> decode(new byte[MAPPING_BYTES + 1], 0, 0), "oversized mapping");
        for (int offset : new int[]{0, 7, 16, 31, 47}) {
            altered(empty, b -> b.put(offset, (byte) '!'), "changed magic/run at " + offset);
        }
        altered(empty, b -> b.put(16, (byte) 'A'), "uppercase run");
        for (int offset : new int[]{8, 12, 48, 52}) {
            altered(empty, b -> b.putInt(offset, b.getInt(offset) + 1), "changed immutable u32 at " + offset);
        }
        for (int offset : new int[]{56, 64, 72}) {
            altered(empty, b -> b.putLong(offset, b.getLong(offset) + 1), "changed immutable u64 at " + offset);
        }
        altered(empty, b -> b.putInt(96, -1), "unsigned invalid host state");
        altered(empty, b -> b.putInt(96, 3), "unknown host state");
        altered(empty, b -> b.putInt(100, 1), "nonzero retention without events");
        altered(empty, b -> b.putLong(80, -1), "unrepresentable sequence");
        rejects(() -> decode(empty, -1, 0), "negative fetched cursor");
        rejects(() -> decode(empty, 1, 0), "fetched cursor ahead of host");
        rejects(() -> decode(empty, 0, 1), "armed regresses to waiting");
        rejects(() -> decode(empty, 0, 2), "closed regresses to waiting");
        rejects(() -> decode(mapping(0, 1), 0, 2), "closed re-arms");
        rejects(() -> decode(mapping(1, 0), 0, 0), "waiting host publishes events");
        for (int offset = 104; offset < 128; offset++) {
            final int at = offset;
            altered(empty, b -> b.put(at, (byte) 1), "host reserved byte " + offset);
        }
        for (int offset = 156; offset < 256; offset++) {
            final int at = offset;
            altered(empty, b -> b.put(at, (byte) 1), "guest reserved byte " + offset);
        }
        rejects(() -> new HudInputProtocol.Identity("BAD", 321, 1, 654, 2, EXPIRES), "invalid identity run");
        rejects(() -> new HudInputProtocol.Identity(RUN, 0, 1, 654, 2, EXPIRES), "zero producer PID");
        rejects(() -> new HudInputProtocol.Identity(RUN, 321, 1, 0, 2, EXPIRES), "zero target PID");
        rejects(() -> new HudInputProtocol.Identity(RUN, 321, 0, 654, 2, EXPIRES), "zero producer FILETIME");
        rejects(() -> new HudInputProtocol.Identity(RUN, 321, 1, 654, 0, EXPIRES), "zero target FILETIME");
        rejects(() -> new HudInputProtocol.Identity(RUN, 321, 1, 654, 2, 0), "zero identity expiry");
    }

    private static void acknowledgement() {
        byte[] bytes = mapping(1, 1);
        for (int offset : new int[]{128, 136, 148, 152}) {
            altered(bytes, b -> b.putInt(offset, 1), "waiting guest has nonzero acknowledgement " + offset);
        }
        for (int guestState : new int[]{1, 2}) {
            byte[] ready = bytes.clone();
            ByteBuffer b = buffer(ready);
            b.putLong(128, 1).putLong(136, NOW).putInt(144, guestState).putInt(148, 1).putInt(152, 8);
            check(decode(ready, 0, 0).lastSequence() == 1, "valid guest acknowledgement state " + guestState);
            altered(ready, a -> a.putLong(128, 2), "acknowledgement exceeds host sequence");
            altered(ready, a -> a.putLong(128, -1), "unsigned invalid acknowledgement sequence");
            altered(ready, a -> a.putLong(136, 0), "ready/closed lacks tick timestamp");
            altered(ready, a -> a.putLong(136, NOW + 101), "acknowledgement too far in future");
            altered(ready, a -> a.putInt(148, 2), "unknown guest screen");
            altered(ready, a -> a.putInt(152, 9), "invalid selected slot");
            altered(ready, a -> a.putInt(152, -1), "negative selected slot");
            b.putLong(136, NOW - 1000);
            check(decode(ready, 0, 0).lastSequence() == 1,
                "ack age belongs to owning worker; decoder retains valid historical acknowledgement");
        }
        altered(bytes, b -> b.putInt(144, 3), "unknown guest state");
    }

    private static void ringAndFreshness() {
        byte[] one = mapping(1, 1);
        var first = decode(one, 0, 0);
        check(first.events().size() == 1 && first.events().get(0).sequence() == 1,
            "first event emitted once");
        check(decode(one, 1, 1).events().isEmpty(), "repeat poll never replays event");
        altered(one, b -> b.putInt(100, 0), "missing retained count");
        altered(one, b -> b.putInt(100, 2), "excess retained count");
        altered(one, b -> b.putLong(256, 2), "missing first record sequence");
        altered(one, b -> b.putInt(292, 1), "record reserved word");
        List<HudInputProtocol.Event> full = decode(mapping(64, 1), 0, 1).events();
        check(full.size() == 64 && full.get(0).sequence() == 1 && full.get(63).sequence() == 64,
            "all ring slots read in sequence order");
        byte[] wrapped = mapping(65, 1);
        var afterWrap = decode(wrapped, 1, 1);
        check(afterWrap.events().size() == 64 && afterWrap.events().get(0).sequence() == 2
            && afterWrap.events().get(63).sequence() == 65, "wrapped ring has continuous ordered events");
        check(decode(wrapped, 64, 1).events().get(0).sequence() == 65, "rollover record in slot zero");
        rejects(() -> decode(wrapped, 0, 1), "unconsumed ring overflow");
        byte[] wrongRetained = wrapped.clone();
        buffer(wrongRetained).putInt(100, 63);
        rejects(() -> decode(wrongRetained, 1, 1), "incomplete wrapped retention");
        byte[] corruptedOld = wrapped.clone();
        buffer(corruptedOld).putInt(recordOffset(2) + 36, 1);
        rejects(() -> decode(corruptedOld, 64, 1), "consumed retained record still structurally validated");
        byte[] consumedOld = wrapped.clone();
        for (long sequence = 2; sequence <= 64; sequence++) {
            buffer(consumedOld).putLong(recordOffset(sequence) + 8, NOW - 10_000);
        }
        check(decode(consumedOld, 64, 1).events().size() == 1, "old consumed records do not expire fresh input");
        check(decode(consumedOld, 65, 1).events().isEmpty(), "idle poll ignores consumed event age");
        byte[] closed = mapping(1, 2);
        buffer(closed).putLong(264, NOW - 10_000);
        check(decode(closed, 0, 1).events().isEmpty(), "closed host never applies pending records");
        for (long stamp : new long[]{NOW - 250, NOW + 100}) {
            byte[] boundary = one.clone();
            buffer(boundary).putLong(88, stamp).putLong(264, stamp);
            check(decode(boundary, 0, 1).events().size() == 1, "inclusive freshness boundary " + stamp);
        }
        for (long stamp : new long[]{0, -1, NOW - 251, NOW + 101, Long.MAX_VALUE}) {
            altered(one, b -> b.putLong(88, stamp), "invalid/stale heartbeat " + stamp);
            altered(one, b -> b.putLong(264, stamp), "invalid/stale new capture " + stamp);
        }
        rejects(() -> HudInputProtocol.decode(one, ID, 0, EXPIRES, 1), "lease expires at exact deadline");
    }

    private static void recordValidation() {
        byte[] one = mapping(1, 1);
        for (int code : new int[]{0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x45, 0x1b}) {
            for (int kind : new int[]{1, 2}) {
                byte[] bytes = one.clone();
                record(bytes, 1, NOW, kind, code, 0, 0, 0);
                check(decode(bytes, 0, 1).events().get(0).code() == code, "allowed key " + code + "/" + kind);
            }
        }
        for (int code : new int[]{0, 0x30, 0x3a, 0x41, 0x46, -1}) {
            altered(one, b -> b.putInt(276, code), "unsupported key code " + code);
        }
        for (int kind : new int[]{0, 7, -1}) altered(one, b -> b.putInt(272, kind), "unsupported kind " + kind);
        altered(one, b -> b.putFloat(280, 0.5f), "key carries pointer x");
        altered(one, b -> b.putFloat(284, 0.5f), "key carries pointer y");
        altered(one, b -> b.putInt(288, 1), "non-wheel value");
        for (int kind : new int[]{3, 4, 5, 6}) {
            byte[] mouse = one.clone();
            record(mouse, 1, NOW, kind, 0, 0, 1, kind == 6 ? 1 : 0);
            check(decode(mouse, 0, 1).events().get(0).kind() == kind, "mouse kind at canvas boundary " + kind);
            for (float coordinate : new float[]{Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, -0.01f, 1.01f}) {
                altered(mouse, b -> b.putFloat(280, coordinate), "invalid pointer x " + kind + "/" + coordinate);
                altered(mouse, b -> b.putFloat(284, coordinate), "invalid pointer y " + kind + "/" + coordinate);
            }
            altered(mouse, b -> b.putInt(276, 2), "invalid mouse code " + kind);
        }
        for (int kind : new int[]{4, 5}) {
            byte[] right = one.clone();
            record(right, 1, NOW, kind, 1, 0.25f, 0.75f, 0);
            check(decode(right, 0, 1).events().get(0).code() == 1, "right mouse button " + kind);
        }
        for (int notches : new int[]{-16, -1, 1, 16}) {
            byte[] wheel = one.clone();
            record(wheel, 1, NOW, 6, 0, 0.5f, 0.5f, notches);
            check(decode(wheel, 0, 1).events().get(0).value() == notches, "bounded wheel " + notches);
        }
        for (int notches : new int[]{-17, 0, 17}) {
            byte[] wheel = one.clone();
            record(wheel, 1, NOW, 6, 0, 0.5f, 0.5f, notches);
            rejects(() -> decode(wheel, 0, 1), "invalid wheel " + notches);
        }
    }

    private static void clientGate() {
        var gate = new HudInputGate();
        gate.apply(key(1, 1, 0x31), NOW);
        check(gate.sequence() == 1 && gate.heldKeyCount() == 1, "key down owned by client gate");
        rejects(() -> gate.apply(key(1, 1, 0x31), NOW), "duplicate sequence");
        rejects(() -> gate.apply(key(3, 2, 0x31), NOW), "sequence gap");
        rejects(() -> gate.apply(key(2, 1, 0x31), NOW), "duplicate held key down");
        check(gate.sequence() == 1 && gate.heldKeyCount() == 1, "rejections do not commit state");
        gate.apply(key(2, 2, 0x31), NOW);
        check(gate.sequence() == 2 && gate.heldKeyCount() == 0, "matched key up releases");
        rejects(() -> gate.apply(key(3, 2, 0x31), NOW), "unmatched key up");
        gate.apply(event(3, NOW, 4, 0, 0.25f, 0.75f, 0), NOW);
        check(gate.heldButtonCount() == 1, "mouse button owned");
        rejects(() -> gate.apply(event(4, NOW, 4, 0, 0.25f, 0.75f, 0), NOW), "duplicate button down");
        rejects(() -> gate.apply(event(4, NOW, 5, 1, 0.25f, 0.75f, 0), NOW), "unmatched other button up");
        gate.apply(event(4, NOW, 5, 0, 0.25f, 0.75f, 0), NOW);
        check(gate.heldButtonCount() == 0 && gate.sequence() == 4, "matched mouse release");
        gate.apply(event(5, NOW, 3, 0, 0.5f, 0.5f, 0), NOW);
        gate.apply(event(6, NOW, 6, 0, 0.5f, 0.5f, -1), NOW);
        check(gate.sequence() == 6 && gate.heldKeyCount() == 0 && gate.heldButtonCount() == 0,
            "pointer/wheel advance sequence without retained controls");
        for (long captured : new long[]{NOW - 251, NOW + 101, 0, Long.MAX_VALUE}) {
            rejects(() -> gate.apply(event(7, captured, 1, 0x45, 0, 0, 0), NOW),
                "stale/future input on application " + captured);
        }
        gate.apply(event(7, NOW - 250, 1, 0x45, 0, 0, 0), NOW);
        gate.apply(event(8, NOW + 100, 4, 1, 0, 1, 0), NOW);
        check(gate.heldKeyCount() == 1 && gate.heldButtonCount() == 1, "application age boundaries inclusive");
        gate.releaseAll();
        check(gate.heldKeyCount() == 0 && gate.heldButtonCount() == 0 && gate.sequence() == 8,
            "release clears both control sets without rewinding cursor");
        gate.releaseAll();
        check(gate.sequence() == 8, "release is idempotent");
        rejects(() -> gate.apply(key(9, 2, 0x45), NOW), "releaseAll invalidates former held key");
        rejects(() -> gate.apply(event(9, NOW, 5, 1, 0, 1, 0), NOW), "releaseAll invalidates former held button");
        gate.apply(key(9, 1, 0x39), NOW);
        check(gate.sequence() == 9, "gate cursor continues only at the next sequence");
    }

    public static void main(String[] args) {
        headerAndIdentity();
        acknowledgement();
        ringAndFreshness();
        recordValidation();
        clientGate();
        System.out.println("HudInputTests: " + checks + " checks passed; pure reverse-input contract/gate; no games launched.");
    }
}
