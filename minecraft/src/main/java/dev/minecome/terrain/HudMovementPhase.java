package dev.minecome.terrain;

/** A grounded client prediction cannot make an unsupported server sample rest. */
final class HudMovementPhase {
    private HudMovementPhase(){}
    static String forAuthoritativeGround(String requested,boolean serverGrounded){
        return !serverGrounded && ("RESTING".equals(requested) || "WALKING".equals(requested))
                ?"LANDING":requested;
    }
}
