package dev.minecome.hud;

import java.util.HashSet;
import java.util.Set;

/** Effective movement holds are separate from the strict raw edge/sequence gate. */
public final class HudMovementKeys {
    public static final long ACTIVE_NS=5_000_000_000L,SETTLE_NS=1_000_000_000L,HOLD_LEASE_NS=150_000_000L;
    private final Set<Integer> raw=new HashSet<>(),held=new HashSet<>();
    private long started=-1,leaseUntil;
    private boolean neutralRequired=true,ended;
    public static boolean movement(int key){return key==0x57 || key==0x41 || key==0x53 || key==0x44 || key==0x20;}
    public void authority(long now,boolean ready){
        expire(now);
        if(!ready){suspend();return;}
        if(raw.isEmpty())neutralRequired=false;
        if(!ended)leaseUntil=now+HOLD_LEASE_NS;
    }
    /** True means a fresh down was accepted as movement, not merely consumed for balancing. */
    public boolean event(int kind,int key,long now,boolean ready){
        if(!movement(key) || (kind!=1 && kind!=2))throw new IllegalArgumentException("Not a movement edge");
        expire(now);
        if(kind==2){
            raw.remove(key);held.remove(key);
            // The final balanced release can establish neutral in the same
            // input batch as a fresh press. It still needs current authority;
            // a heartbeat alone can never restore a key held at suspension.
            if(raw.isEmpty() && ready && !ended && now<leaseUntil)neutralRequired=false;
            return false;
        }
        raw.add(key);
        if(!ready || ended || neutralRequired || now>=leaseUntil)return false;
        if(started<0)started=now;
        held.add(key);return true;
    }
    public void suspend(){held.clear();neutralRequired=true;leaseUntil=0;}
    /** A spatial boundary releases input without ending or renewing the trial. */
    public void suppressAtBoundary(){suspend();}
    public void end(){ended=true;suspend();}
    public void close(){end();raw.clear();}
    public void expire(long now){
        if(started>=0 && (now<started || now-started>=ACTIVE_NS))end();
        if(!held.isEmpty() && (now>=leaseUntil || now<leaseUntil-HOLD_LEASE_NS))suspend();
    }
    public boolean down(int key,long now){expire(now);return held.contains(key);}
    public boolean neutral(long now){expire(now);return held.isEmpty();}
    public boolean started(){return started>=0;}
    public long startedAt(){return started;}
    public boolean ended(){return ended;}
    public int rawCount(){return raw.size();}
}
