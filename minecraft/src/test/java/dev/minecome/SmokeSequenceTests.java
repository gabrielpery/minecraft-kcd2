package dev.minecome;

/** Deterministic tests for test timing and safety; gameplay actions still run only in vanilla. */
public final class SmokeSequenceTests {
    private static int checks;
    private static final long SECOND=1_000_000_000L;
    private static void check(boolean condition,String message){checks++;if(!condition)throw new AssertionError(message);}
    private static SmokeSequence.Action tick(SmokeSequence sequence,long seconds){return sequence.update(seconds*SECOND,true,true,1);}
    public static void main(String[] args) {
        SmokeSequence sequence=new SmokeSequence(15*SECOND);
        check(sequence.update(0,false,true,1)==SmokeSequence.Action.NONE,"no interactions without fresh host state");
        check(tick(sequence,1)==SmokeSequence.Action.NONE,"fresh host begins warmup without interacting");
        check(tick(sequence,5)==SmokeSequence.Action.NONE,"five-second warmup is measured from host state");
        check(tick(sequence,6)==SmokeSequence.Action.GIVE_STONE,"inventory follows five-second warmup");
        check(tick(sequence,7)==SmokeSequence.Action.PLACE_STONE,"placement occurs six seconds after fresh host state");
        check(tick(sequence,8)==SmokeSequence.Action.NONE,"allow vanilla placement packet processing");
        check(tick(sequence,9)==SmokeSequence.Action.CHECK_PLACEMENT,"read real placement after two seconds");
        check(tick(sequence,13)==SmokeSequence.Action.NONE,"wait for server confirmation without breaking");
        sequence.confirmPlacement(13*SECOND,true);
        check(tick(sequence,27)==SmokeSequence.Action.NONE,"stone stays visible fourteen seconds after confirmation");
        check(tick(sequence,28)==SmokeSequence.Action.BREAK_STONE,"break after fifteen seconds from confirmation");
        check(tick(sequence,30)==SmokeSequence.Action.CHECK_REMOVAL,"read real removal after two seconds");
        sequence.confirmRemoval(true);
        check(sequence.phase()==SmokeSequence.Phase.DONE,"both confirmations complete smoke");
        check(sequence.update(31*SECOND,false,false,2)==SmokeSequence.Action.NONE,"finished smoke never repeats on reconnect");

        SmokeSequence warmup=new SmokeSequence(15*SECOND);
        tick(warmup,1);
        check(warmup.update(4*SECOND,false,false,1)==SmokeSequence.Action.NONE,"pre-interaction disconnect safely restarts wait");
        check(warmup.phase()==SmokeSequence.Phase.WAIT_FOR_HOST,"warmup reset does not mutate world");
        check(warmup.update(5*SECOND,true,true,2)==SmokeSequence.Action.NONE,"new session starts fresh warmup");
        check(warmup.update(9*SECOND,true,true,2)==SmokeSequence.Action.NONE,"new session cannot inherit old timer");
        check(warmup.update(10*SECOND,true,true,2)==SmokeSequence.Action.GIVE_STONE,"new session gets full warmup");

        SmokeSequence interrupted=new SmokeSequence(15*SECOND);
        tick(interrupted,0);tick(interrupted,5);tick(interrupted,6);tick(interrupted,8);
        interrupted.confirmPlacement(8*SECOND,true);
        check(interrupted.update(9*SECOND,true,true,2)==SmokeSequence.Action.FAIL,"session change after placement fails instead of claiming pass");
        check(interrupted.update(10*SECOND,true,true,2)==SmokeSequence.Action.NONE,"failure cleanup action issued once");
        interrupted.confirmRemoval(true);
        check(interrupted.phase()==SmokeSequence.Phase.FAILED,"late server confirmation cannot revive failed run");

        SmokeSequence timeout=new SmokeSequence(15*SECOND);
        tick(timeout,0);tick(timeout,5);tick(timeout,6);tick(timeout,8);tick(timeout,14);
        check(timeout.phase()==SmokeSequence.Phase.FAILED,"missing authoritative confirmation fails after six seconds");
        check(tick(timeout,15)==SmokeSequence.Action.FAIL,"timeout produces cleanup action");
        SmokeSequence disagreement=new SmokeSequence(15*SECOND);
        tick(disagreement,0);tick(disagreement,5);tick(disagreement,6);tick(disagreement,8);
        disagreement.confirmPlacement(8*SECOND,false);
        check(disagreement.phase()==SmokeSequence.Phase.FAILED,"client/server disagreement cannot pass");
        check(tick(disagreement,9)==SmokeSequence.Action.FAIL,"failed placement never reaches timed break");
        System.out.println("SmokeSequenceTests: "+checks+" checks passed");
    }
}
