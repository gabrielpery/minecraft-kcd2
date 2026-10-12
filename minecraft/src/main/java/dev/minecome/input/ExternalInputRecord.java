package dev.minecome.input;

import java.math.BigInteger;

/** Immutable transport data only. No Minecraft, Windows or engine API access. */
public record ExternalInputRecord(Kind kind, String run, long targetPid, String targetStartFiletime,
                                  BigInteger sequence, long utcMillis, long monotonicMillis,
                                  boolean focused, boolean armed, Held held, int mouseDx, int mouseDy,
                                  String reason) {
    public enum Kind { BEGIN, SAMPLE, END }
    public record Held(boolean forward, boolean back, boolean left, boolean right,
                       boolean jump, boolean sprint) {
        public static final Held NONE = new Held(false, false, false, false, false, false);
        public boolean neutral() { return equals(NONE); }
    }
    public boolean neutral() { return held.neutral() && mouseDx == 0 && mouseDy == 0; }
}
