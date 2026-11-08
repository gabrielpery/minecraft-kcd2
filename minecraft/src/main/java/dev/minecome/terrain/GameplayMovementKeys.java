package dev.minecome.terrain;

import java.util.HashSet;
import java.util.Set;
import java.util.ArrayDeque;

/** Renewable authority, without a diagnostic play-duration limit. */
public final class GameplayMovementKeys {
    public static final long LEASE_NS=150_000_000L;
    private final Set<Integer> raw=new HashSet<>(),held=new HashSet<>();
    private final boolean tickJump;
    private final ArrayDeque<Boolean> jumpEdges=new ArrayDeque<>();
    private boolean sampledJump;
    private long until;private boolean neutral=true,closed;
    public GameplayMovementKeys(){this(false);}
    public GameplayMovementKeys(boolean tickJump){this.tickJump=tickJump;}
    public static boolean movement(int key){return key=='W'||key=='A'||key=='S'||key=='D'||key==0x20||key==0x10||key==0x11;}
    public void authority(long now,boolean allowed){expire(now);if(!allowed){suspend();return;}if(raw.isEmpty())neutral=false;if(!closed)until=now+LEASE_NS;}
    public boolean event(int kind,int key,long now,boolean allowed){
        if(!movement(key)||(kind!=1&&kind!=2))throw new IllegalArgumentException("Not a movement edge");expire(now);
        if(kind==2){raw.remove(key);boolean accepted=held.remove(key);if(tickJump&&key==0x20&&accepted)queueJump(false);if(raw.isEmpty()&&allowed&&!closed&&now<until)neutral=false;return false;}
        boolean edge=raw.add(key);if(!allowed||closed||neutral||now>=until)return false;held.add(key);if(tickJump&&key==0x20&&edge)queueJump(true);return true;
    }
    private void queueJump(boolean down){if(jumpEdges.size()>=8){suspend();return;}jumpEdges.addLast(down);}
    /** Vanilla reads one rising jump edge per client tick, including sub-frame native taps. */
    public void tick(long now){expire(now);if(tickJump&&!jumpEdges.isEmpty())sampledJump=jumpEdges.removeFirst();}
    public void suspend(){held.clear();jumpEdges.clear();sampledJump=false;neutral=true;until=0;}
    public void expire(long now){if((!held.isEmpty()||sampledJump||!jumpEdges.isEmpty())&&(now>=until||now<until-LEASE_NS))suspend();}
    public boolean down(int key,long now){expire(now);return tickJump&&key==0x20?sampledJump:held.contains(key);}
    public boolean neutral(long now){expire(now);return held.isEmpty()&&!sampledJump;}
    /** Diagnostic only; observing a held edge must not renew or expire its lease. */
    boolean heldInput(){return !held.isEmpty()||sampledJump;}
    public void close(){closed=true;suspend();raw.clear();}
}
