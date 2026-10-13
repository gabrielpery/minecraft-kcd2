package dev.minecome.hud;

import dev.minecome.protocol.Protocol;

/** State matrix exercises ownership, UI, selected inventory, and one-cell scope. */
public final class HudStoneGateTests {
    private static int checks;
    private static void check(boolean value, String message) { checks++; if (!value) throw new AssertionError(message); }
    private static HudStoneGate.State state(boolean[] fields) {
        return new HudStoneGate.State(fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6],
                fields[7], fields[8], fields[9], fields[10], fields[11], fields[12], fields[13]);
    }
    public static void main(String[] args) {
        boolean[] air = {true,true,true,true,true,true,true,true,true,true,true,true,false,false};
        boolean[] stone = air.clone(); stone[11] = false; stone[12] = true;
        check(HudStoneGate.evaluate(Protocol.PLACE_STONE, state(air)) == 0, "selected stone places only into owned air");
        check(HudStoneGate.evaluate(Protocol.BREAK_STONE, state(stone)) == 0, "owned stone can be broken");
        check(HudStoneGate.evaluate(Protocol.PLACE_STONE, state(stone)) == Protocol.INPUT_OCCUPIED, "no replacement");
        check(HudStoneGate.evaluate(Protocol.BREAK_STONE, state(air)) == Protocol.INPUT_ABSENT, "no fabricated absent break");
        for (int index = 0; index < 9; index++) {
            boolean[] noPlace = air.clone(), noBreak = stone.clone(); noPlace[index] = false; noBreak[index] = false;
            check(HudStoneGate.evaluate(Protocol.PLACE_STONE, state(noPlace)) == Protocol.INPUT_UNAVAILABLE, "placement prerequisite " + index);
            check(HudStoneGate.evaluate(Protocol.BREAK_STONE, state(noBreak)) == Protocol.INPUT_UNAVAILABLE, "break prerequisite " + index);
            String[] reasons = {"owner", "not_armed", "screen_open", "not_creative", "chunks_unavailable", "out_of_reach",
                    "support_unavailable", "server_observation_not_fresh", "client_server_cell_disagree"};
            check(HudStoneGate.decide(Protocol.PLACE_STONE, state(noPlace)).reason().equals(reasons[index]), "diagnostic identifies missing prerequisite " + index);
        }
        for (int index = 9; index <= 10; index++) {
            boolean[] noPlace = air.clone(), mayBreak = stone.clone(); noPlace[index] = false; mayBreak[index] = false;
            check(HudStoneGate.evaluate(Protocol.PLACE_STONE, state(noPlace)) == Protocol.INPUT_UNAVAILABLE, "placement requires current selected stone agreement " + index);
            check(HudStoneGate.evaluate(Protocol.BREAK_STONE, state(mayBreak)) == 0, "dirt selection may still break stone " + index);
        }
        boolean[] other = stone.clone(); other[12] = false;
        check(HudStoneGate.evaluate(Protocol.PLACE_STONE, state(other)) == Protocol.INPUT_OCCUPIED, "cannot overwrite another block");
        check(HudStoneGate.evaluate(Protocol.BREAK_STONE, state(other)) == Protocol.INPUT_OCCUPIED, "cannot destroy another block");
        boolean[] busyAir = air.clone(), busyStone = stone.clone(); busyAir[13] = true; busyStone[13] = true;
        check(HudStoneGate.evaluate(Protocol.PLACE_STONE, state(busyAir)) == Protocol.INPUT_BUSY, "only one pending placement");
        check(HudStoneGate.evaluate(Protocol.BREAK_STONE, state(busyStone)) == Protocol.INPUT_BUSY, "only one pending break");
        busyAir[1] = false;
        check(HudStoneGate.evaluate(Protocol.PLACE_STONE, state(busyAir)) == Protocol.INPUT_UNAVAILABLE, "expired activation takes priority over busy");
        check(HudStoneGate.decide(Protocol.PLACE_STONE, state(air)).reason().equals("permitted"), "accepted gate is explicit");
        check(HudStoneGate.freshObservation(1, 1, 100, 100), "same-instant snapshot fresh");
        check(HudStoneGate.freshObservation(1, 1, 100, 250_000_100L), "250ms inclusive freshness boundary");
        check(!HudStoneGate.freshObservation(1, 1, 100, 250_000_101L), "older server observation rejected");
        check(!HudStoneGate.freshObservation(1, 1, 101, 100), "future observation remains rejected");
        check(HudStoneGate.freshObservation(1, 1, 101, 102), "clock read after acquired snapshot avoids tick-entry race");
        check(!HudStoneGate.freshObservation(1, 2, 100, 100), "old epoch remains rejected");
        for (int action : new int[]{-1, 0, 3, Integer.MAX_VALUE}) {
            try { HudStoneGate.evaluate(action, state(air)); throw new AssertionError("Invalid action allowed"); }
            catch (IllegalArgumentException expected) { checks++; }
        }
        System.out.println("HudStoneGateTests: " + checks + " checks passed");
    }
}
