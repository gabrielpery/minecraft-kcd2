package dev.minecome.terrain;

final class GroundCorridorSyncTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static GroundMovementSequence.Motion at(double x){return new GroundMovementSequence.Motion(x,64,.5,0,0,0,true,true);}
    private static void reject(Runnable action,String message){try{action.run();throw new AssertionError(message);}catch(IllegalStateException expected){checks++;}}
    static int run(){
        var sync=new GroundCorridorSync();
        check(!sync.pause(0,1,at(.5),at(.5)),"Matching observations do not delay input");
        check(!sync.pause(50_000_000,1,at(.7),at(.5)),"Ordinary one-tick packet latency is admitted");
        check(sync.pause(100_000_000,1,at(.9),at(.5)),"Catch-up ticks pause before the unchanged1m failure bound");
        check(sync.pause(150_000_000,1,at(.95),at(.95)),"Re-reading a snapshot cannot acknowledge synchronization");
        check(sync.pause(200_000_000,2,at(1.1),at(.8)),"Advancing server still must catch the actual client position");
        check(!sync.pause(250_000_000,3,at(1.1),at(1.05)),"Fresh agreeing server observation resumes the existing phase");
        check(sync.pausedTicks()==3&&sync.sameSnapshotTicks()==3&&sync.maxDistance()>=.39,"Pause and maximum observed disagreement evidence survives recovery");
        var stuck=new GroundCorridorSync();stuck.pause(0,1,at(.9),at(.5));
        reject(()->stuck.pause(1_000_000_001L,2,at(.9),at(.5)),"A server that stays behind fails despite releasing input");
        var divergence=new GroundCorridorSync();
        reject(()->divergence.pause(0,1,at(1.51),at(.5)),"Real divergence still fails at1m");
        var rollback=new GroundCorridorSync();rollback.pause(100,2,at(.5),at(.5));
        reject(()->rollback.pause(101,1,at(.5),at(.5)),"Server sequence rollback is invalid");
        var clock=new GroundCorridorSync();clock.pause(100,1,at(.9),at(.5));
        reject(()->clock.pause(99,2,at(.9),at(.5)),"Waiting clock rollback is invalid");
        var input=new GroundCorridorSync();
        check(!input.dropExpiredInput(151_000_000L,1_000_000L,151_000_000L,true),"Original150ms lease remains valid at its deadline");
        check(input.dropExpiredInput(151_000_001L,1_000_000L,151_000_000L,true),"Expired scripted hold is dropped before vanilla can consume it");
        check(!input.dropExpiredInput(152_000_000L,1_000_000L,0,false)&&input.expiredInputReleases()==1,"Released inputs do not retain or renew the old lease");
        check(input.dropExpiredInput(251_000_000L,1_000_000L,151_000_000L,true),"Late hold can be dropped only within the unchanged250ms scheduling bound");
        reject(()->input.dropExpiredInput(251_000_001L,1_000_000L,151_000_000L,true),"Hard stall still fails instead of extending the scheduling bound");
        return checks;
    }
}
