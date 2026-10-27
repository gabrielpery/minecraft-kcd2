package dev.minecome.terrain;

/** Final proof is evaluated only after both actual observations stay settled. */
final class HudMovementCompletion {
    static final long STABLE_NS=500_000_000L;
    enum Result { WAITING,PASSED,INSUFFICIENT_WALK }
    private long stableAt=-1;
    Result update(long now,boolean settled,double clientWalk,double serverWalk){
        if(now<0 || !Double.isFinite(clientWalk) || !Double.isFinite(serverWalk) || clientWalk<0 || serverWalk<0)
            throw new IllegalArgumentException("Invalid final walking observation");
        if(!settled){stableAt=-1;return Result.WAITING;}
        if(stableAt<0 || now<stableAt)stableAt=now;
        if(now-stableAt<STABLE_NS)return Result.WAITING;
        return clientWalk>=.15 && serverWalk>=.15?Result.PASSED:Result.INSUFFICIENT_WALK;
    }
}
