package dev.minecome.terrain;

import java.util.HashSet;
import java.util.Set;

/** Renewable authority, without a diagnostic play-duration limit. */
public final class GameplayMovementKeys {
    public static final long LEASE_NS=150_000_000L;
    private final Set<Integer> raw=new HashSet<>(),held=new HashSet<>();
    private long until;private boolean neutral=true,closed;
    public static boolean movement(int key){return key=='W'||key=='A'||key=='S'||key=='D'||key==0x20;}
    public void authority(long now,boolean allowed){expire(now);if(!allowed){suspend();return;}if(raw.isEmpty())neutral=false;if(!closed)until=now+LEASE_NS;}
    public boolean event(int kind,int key,long now,boolean allowed){
        if(!movement(key)||(kind!=1&&kind!=2))throw new IllegalArgumentException("Not a movement edge");expire(now);
        if(kind==2){raw.remove(key);held.remove(key);if(raw.isEmpty()&&allowed&&!closed&&now<until)neutral=false;return false;}
        raw.add(key);if(!allowed||closed||neutral||now>=until)return false;held.add(key);return true;
    }
    public void suspend(){held.clear();neutral=true;until=0;}
    public void expire(long now){if(!held.isEmpty()&&(now>=until||now<until-LEASE_NS))suspend();}
    public boolean down(int key,long now){expire(now);return held.contains(key);}
    public boolean neutral(long now){expire(now);return held.isEmpty();}
    public void close(){closed=true;suspend();raw.clear();}
}
