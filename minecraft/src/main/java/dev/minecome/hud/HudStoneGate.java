package dev.minecome.hud;

import dev.minecome.protocol.Protocol;

/** Pure preconditions for the explicit HUD-owned single-cell stone bridge. */
final class HudStoneGate {
    record Decision(int result, String reason) {}
    record State(boolean owner, boolean armed, boolean clearScreen, boolean creative,
                 boolean chunksLoaded, boolean inReach, boolean support,
                 boolean freshServer, boolean agreedCell, boolean selectedAgrees,
                 boolean selectedStone, boolean air, boolean stone, boolean pending) {}

    static int evaluate(int action, State state) {
        return decide(action, state).result();
    }

    static Decision decide(int action, State state) {
        if (action != Protocol.PLACE_STONE && action != Protocol.BREAK_STONE)
            throw new IllegalArgumentException("Unknown stone action");
        if (!state.owner()) return unavailable("owner");
        if (!state.armed()) return unavailable("not_armed");
        if (!state.clearScreen()) return unavailable("screen_open");
        if (!state.creative()) return unavailable("not_creative");
        if (!state.chunksLoaded()) return unavailable("chunks_unavailable");
        if (!state.inReach()) return unavailable("out_of_reach");
        if (!state.support()) return unavailable("support_unavailable");
        if (!state.freshServer()) return unavailable("server_observation_not_fresh");
        if (!state.agreedCell()) return unavailable("client_server_cell_disagree");
        if (state.pending()) return new Decision(Protocol.INPUT_BUSY, "pending_action");
        if (action == Protocol.PLACE_STONE) {
            if (!state.selectedAgrees()) return unavailable("selected_inventory_disagrees");
            if (!state.selectedStone()) return unavailable("selected_item_not_stone");
            return state.air() ? new Decision(0, "permitted") : new Decision(Protocol.INPUT_OCCUPIED, "target_occupied");
        }
        return state.stone() ? new Decision(0, "permitted") : state.air()
                ? new Decision(Protocol.INPUT_ABSENT, "target_absent") : new Decision(Protocol.INPUT_OCCUPIED, "target_not_stone");
    }
    private static Decision unavailable(String reason) { return new Decision(Protocol.INPUT_UNAVAILABLE, reason); }

    /** Caller obtains a monotonic timestamp after acquiring its immutable observation. */
    static boolean freshObservation(long observationEpoch, long expectedEpoch, long observedAt, long now) {
        return observationEpoch == expectedEpoch && now >= observedAt && now - observedAt <= 250_000_000L;
    }
}
