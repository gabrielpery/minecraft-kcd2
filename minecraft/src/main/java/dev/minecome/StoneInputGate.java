package dev.minecome;

import dev.minecome.protocol.Protocol;

/** Pure checks shared by the live client tick and deterministic tests. Zero permits dispatch. */
final class StoneInputGate {
    record State(boolean lab,boolean creative,boolean chunksLoaded,boolean inReach,boolean solidSupport,
                 boolean stone,boolean air,boolean busy) {}
    static int evaluate(int action,State state) {
        if(action!=Protocol.PLACE_STONE && action!=Protocol.BREAK_STONE)throw new IllegalArgumentException("Invalid action");
        if(!state.lab() || !state.creative() || !state.chunksLoaded() || !state.inReach() || !state.solidSupport())
            return Protocol.INPUT_UNAVAILABLE;
        if(state.busy())return Protocol.INPUT_BUSY;
        if(action==Protocol.PLACE_STONE)return state.air()?0:Protocol.INPUT_OCCUPIED;
        return state.stone()?0:(state.air()?Protocol.INPUT_ABSENT:Protocol.INPUT_OCCUPIED);
    }
}
