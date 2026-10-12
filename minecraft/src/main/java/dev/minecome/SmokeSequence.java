package dev.minecome;

/** Test choreography only; each action is performed by vanilla Minecraft, never simulated here. */
public final class SmokeSequence {
    public enum Action { NONE,GIVE_STONE,PLACE_STONE,CHECK_PLACEMENT,BREAK_STONE,CHECK_REMOVAL,FAIL }
    public enum Phase { WAIT_FOR_HOST,WARMUP,AFTER_GIVE,AFTER_PLACE,AWAIT_PLACEMENT,HOLDING,AFTER_BREAK,AWAIT_REMOVAL,DONE,FAILED }
    private Phase phase=Phase.WAIT_FOR_HOST;
    private final long holdNanos;
    private long enteredAt,session;
    private boolean failureReported;
    private String failure="";
    public SmokeSequence(long holdNanos) {
        if(holdNanos<0)throw new IllegalArgumentException("Negative smoke hold time");this.holdNanos=holdNanos;
    }
    public Phase phase(){return phase;}
    public String failure(){return failure;}
    public Action update(long now,boolean hostReady,boolean connected,long currentSession) {
        if(phase==Phase.WARMUP && (!connected || currentSession!=session))enter(Phase.WAIT_FOR_HOST,now);
        else if(phase!=Phase.WAIT_FOR_HOST && phase!=Phase.DONE && phase!=Phase.FAILED && (!connected || currentSession!=session))
            fail("Authenticated bridge session changed during smoke interactions");
        if(phase==Phase.FAILED){if(!failureReported){failureReported=true;return Action.FAIL;}return Action.NONE;}
        switch(phase) {
            case WAIT_FOR_HOST -> {if(hostReady && connected){session=currentSession;enter(Phase.WARMUP,now);}}
            case WARMUP -> {if(hostReady && now-enteredAt>=5_000_000_000L){enter(Phase.AFTER_GIVE,now);return Action.GIVE_STONE;}}
            case AFTER_GIVE -> {if(hostReady && now-enteredAt>=1_000_000_000L){enter(Phase.AFTER_PLACE,now);return Action.PLACE_STONE;}}
            case AFTER_PLACE -> {if(now-enteredAt>=2_000_000_000L){enter(Phase.AWAIT_PLACEMENT,now);return Action.CHECK_PLACEMENT;}}
            case AWAIT_PLACEMENT,AWAIT_REMOVAL -> {if(now-enteredAt>=6_000_000_000L)fail("Vanilla server confirmation timed out");}
            case HOLDING -> {if(now-enteredAt>=holdNanos){enter(Phase.AFTER_BREAK,now);return Action.BREAK_STONE;}}
            case AFTER_BREAK -> {if(now-enteredAt>=2_000_000_000L){enter(Phase.AWAIT_REMOVAL,now);return Action.CHECK_REMOVAL;}}
            default -> {}
        }
        return Action.NONE;
    }
    public void confirmPlacement(long now,boolean clientAndServerStone) {
        if(phase!=Phase.AWAIT_PLACEMENT)return;
        if(clientAndServerStone)enter(Phase.HOLDING,now);else fail("Vanilla client/server did not confirm stone placement");
    }
    public void confirmRemoval(boolean clientAndServerAir) {
        if(phase!=Phase.AWAIT_REMOVAL)return;
        if(clientAndServerAir)phase=Phase.DONE;else fail("Vanilla client/server did not confirm stone removal");
    }
    public void fail(String reason){if(phase!=Phase.DONE && phase!=Phase.FAILED){failure=reason;phase=Phase.FAILED;}}
    private void enter(Phase next,long now){phase=next;enteredAt=now;}
}
