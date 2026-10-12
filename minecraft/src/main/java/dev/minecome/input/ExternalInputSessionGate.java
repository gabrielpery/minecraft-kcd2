package dev.minecome.input;

import java.io.IOException;
import java.math.BigInteger;

/**
 * Pure session/lease gate for a future game-thread handoff. The caller supplies clocks;
 * the capture helper's elapsed clock is checked for ordering, never compared to this JVM's clock.
 */
public final class ExternalInputSessionGate {
    public static final long MAX_AGE_MILLIS = 300, MAX_FUTURE_SKEW_MILLIS = 50;
    /** The exact120s instant is allowed; any subsequent local monotonic instant closes the session. */
    public static final long MAX_SESSION_NANOS = 120_000_000_000L;
    public static final int MAX_RECORDS = 2500;
    public record Identity(String run, long targetPid, String targetStartFiletime) {
        public Identity {
            if (!ExternalInputDecoder.validRun(run) || targetPid < 1 || targetPid > 0xffff_ffffL
                    || !ExternalInputDecoder.validFiletime(targetStartFiletime))
                throw new IllegalArgumentException("Invalid expected external input identity");
        }
    }
    public record Input(boolean active, ExternalInputRecord.Held held, int mouseDx, int mouseDy) {
        public static final Input NEUTRAL = new Input(false, ExternalInputRecord.Held.NONE, 0, 0);
    }
    private enum Phase { NEW, OPEN, CLOSED }
    private final Identity identity;
    private Phase phase = Phase.NEW;
    private BigInteger lastSequence = BigInteger.ZERO;
    private long lastElapsed, sessionReceivedNanos, sampleReceivedNanos, sampleLeaseNanos;
    private long mouseReceivedNanos, mouseLeaseNanos;
    private int records;
    private boolean neutralBarrier = true, active;
    private ExternalInputRecord.Held held = ExternalInputRecord.Held.NONE;
    private int mouseDx, mouseDy;

    public ExternalInputSessionGate(Identity identity) { this.identity = java.util.Objects.requireNonNull(identity); }

    /** Any malformed, stale, replayed or foreign record closes this session and clears all controls. */
    public synchronized void receive(byte[] json, long utcNowMillis, long localNowNanos) throws IOException {
        try {
            ExternalInputRecord record = ExternalInputDecoder.decode(json);
            if (phase == Phase.CLOSED) throw new IOException("External input session is closed");
            if (!record.run().equals(identity.run()) || record.targetPid() != identity.targetPid()
                    || !record.targetStartFiletime().equals(identity.targetStartFiletime()))
                throw new IOException("External input run/process identity mismatch");
            long age;
            try { age = Math.subtractExact(utcNowMillis, record.utcMillis()); }
            catch (ArithmeticException e) { throw new IOException("External input UTC age overflow", e); }
            if (age < -MAX_FUTURE_SKEW_MILLIS || age > MAX_AGE_MILLIS)
                throw new IOException("External input record is stale/future");
            if (record.sequence().compareTo(lastSequence) <= 0 || record.monotonicMillis() < lastElapsed)
                throw new IOException("External input sequence/elapsed clock regressed");
            if (++records > MAX_RECORDS) throw new IOException("External input record budget exceeded");
            if (phase == Phase.NEW) {
                if (record.kind() != ExternalInputRecord.Kind.BEGIN)
                    throw new IOException("External input requires begin first");
                sessionReceivedNanos = localNowNanos; phase = Phase.OPEN;
            } else {
                if (record.kind() == ExternalInputRecord.Kind.BEGIN) throw new IOException("Repeated external input begin");
                long elapsed = localNowNanos - sessionReceivedNanos;
                if (elapsed < 0 || elapsed > MAX_SESSION_NANOS)
                    throw new IOException("External input local session deadline expired");
                long oldSampleAge = localNowNanos - sampleReceivedNanos;
                if (active && (oldSampleAge < 0 || oldSampleAge >= sampleLeaseNanos)) clear();
            }
            lastSequence = record.sequence(); lastElapsed = record.monotonicMillis();
            if (record.kind() == ExternalInputRecord.Kind.END) { close(); return; }
            if (record.kind() == ExternalInputRecord.Kind.BEGIN || !record.focused() || !record.armed()) {
                clear(); return;
            }
            // Reconnection, menu suppression, focus loss and lease expiry require a fresh
            // released-controls sample. A held control cannot spring back from old state.
            if (neutralBarrier) {
                clearControls();
                if (!record.neutral()) return;
                neutralBarrier = false;
            }
            long newLease = (MAX_AGE_MILLIS - Math.max(0, age)) * 1_000_000L;
            long mouseAge = localNowNanos - mouseReceivedNanos;
            if ((mouseDx != 0 || mouseDy != 0) && (mouseAge < 0 || mouseAge >= mouseLeaseNanos)) clearMouse();
            long accumulatedX = (long) mouseDx + record.mouseDx(), accumulatedY = (long) mouseDy + record.mouseDy();
            if (Math.abs(accumulatedX) > 32767 || Math.abs(accumulatedY) > 32767)
                throw new IOException("Unconsumed external input mouse accumulation exceeded its bound");
            if (record.mouseDx() != 0 || record.mouseDy() != 0) {
                long remaining = (mouseDx != 0 || mouseDy != 0) ? mouseLeaseNanos - mouseAge : newLease;
                mouseReceivedNanos = localNowNanos; mouseLeaseNanos = Math.min(remaining, newLease);
            }
            mouseDx = (int) accumulatedX; mouseDy = (int) accumulatedY;
            active = true; held = record.held();
            sampleReceivedNanos = localNowNanos;
            // Preserve the total 300ms observation-age bound with a local monotonic lease.
            sampleLeaseNanos = newLease;
        } catch (IOException | RuntimeException e) {
            close();
            if (e instanceof IOException io) throw io;
            throw new IOException("Invalid external input session state", e);
        }
    }

    /** localReady=false represents a menu/disarmed consumer; mouse deltas are consumed once. */
    public synchronized Input consume(long localNowNanos, boolean localReady) {
        if (phase != Phase.OPEN) return Input.NEUTRAL;
        long sessionAge = localNowNanos - sessionReceivedNanos;
        if (sessionAge < 0 || sessionAge > MAX_SESSION_NANOS) { close(); return Input.NEUTRAL; }
        long age = localNowNanos - sampleReceivedNanos;
        if (!localReady || !active || age < 0 || age >= sampleLeaseNanos) { clear(); return Input.NEUTRAL; }
        long mouseAge = localNowNanos - mouseReceivedNanos;
        if (mouseAge < 0 || mouseAge >= mouseLeaseNanos) clearMouse();
        Input result = new Input(true, held, mouseDx, mouseDy);
        clearMouse();
        return result;
    }
    /** A reconnect needs a new gate and an explicit fresh begin; this instance cannot revive. */
    public synchronized void disconnect() { close(); }
    public synchronized boolean closed() { return phase == Phase.CLOSED; }
    public synchronized BigInteger lastSequence() { return lastSequence; }
    private void clearMouse() { mouseDx = mouseDy = 0; mouseReceivedNanos = mouseLeaseNanos = 0; }
    private void clearControls() { active = false; held = ExternalInputRecord.Held.NONE; clearMouse(); }
    private void clear() { clearControls(); neutralBarrier = true; }
    private void close() { clear(); phase = Phase.CLOSED; }
}
