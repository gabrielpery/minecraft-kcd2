package dev.minecome.terrain;

/** Stops scripted input while client catch-up ticks outrun an authoritative server observation. */
final class GroundCorridorSync {
    private long lastSequence=-1,waitSequence,waitStarted;
    private boolean waiting;
    private long pausedTicks,sameSnapshotTicks,expiredInputReleases;
    private double maxDistance;
    boolean pause(long now,long serverSequence,GroundMovementSequence.Motion client,GroundMovementSequence.Motion server){
        if(serverSequence<=0 || serverSequence<lastSequence || !client.finite() || !server.finite())
            throw new IllegalStateException("Invalid corridor synchronization observation");
        if(serverSequence==lastSequence)sameSnapshotTicks++;
        lastSequence=serverSequence;
        double horizontal=client.distance(server);
        maxDistance=Math.max(maxDistance,Math.hypot(horizontal,client.y()-server.y()));
        if(maxDistance>1)throw new IllegalStateException("Corridor client/server movement disagreement");
        if(!waiting && horizontal>.35){waiting=true;waitSequence=serverSequence;waitStarted=now;}
        if(!waiting)return false;
        if(now<waitStarted || now-waitStarted>1_000_000_000L)
            throw new IllegalStateException("Corridor positions did not synchronize within1s with controls released");
        if(serverSequence>waitSequence && horizontal<=.15){waiting=false;return false;}
        pausedTicks++;return true;
    }
    long pausedTicks(){return pausedTicks;}
    long sameSnapshotTicks(){return sameSnapshotTicks;}
    /** Drop a late synthetic key hold before vanilla can consume it; never extend its lease. */
    boolean dropExpiredInput(long now,long lastTickAt,long leaseUntil,boolean held){
        if(!held || leaseUntil==0 || now<=leaseUntil)return false;
        if(lastTickAt==0 || now<lastTickAt || now-lastTickAt>250_000_000L)
            throw new IllegalStateException("HUD movement held-input lease expired after client stall");
        expiredInputReleases++;return true;
    }
    long expiredInputReleases(){return expiredInputReleases;}
    double maxDistance(){return maxDistance;}
}
