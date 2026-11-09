package dev.minecome.gameplay;

import java.util.*;

/** Server-thread event queue. Accepted source times never become publication times. */
public final class GameplayIncomingDamage {
    public record Entry(GameplayCombatProtocol.Hurt hurt,GameplayCombatProtocol.Actor actor,long dueNano){}
    private final ArrayDeque<Entry> pending=new ArrayDeque<>();
    private final LinkedHashMap<Long,GameplayCombatProtocol.Hurt> seen=new LinkedHashMap<>();
    private long highest,ack,lastSourceUtc,lastAppliedSourceUtc,lastAppliedNano,lifeCutoffUtc;
    public long ack(){return ack;}
    public int pending(){return pending.size();}
    public List<Entry> entries(){return List.copyOf(pending);}
    public boolean oldLife(Entry entry){return entry.hurt().sourceUtc()<=lifeCutoffUtc;}
    public void admit(List<GameplayCombatProtocol.Hurt> hurts,List<GameplayCombatProtocol.Actor> actors,long nowUtc,long nowNano){
        for(var hurt:hurts){
            var prior=seen.get(hurt.seq());
            if(prior!=null){if(!prior.equals(hurt))throw new IllegalStateException("Native damage source changed after admission");continue;}
            if(hurt.seq()!=highest+1||hurt.seq()>10_000_000)throw new IllegalStateException("Native damage source gap/replay");
            if(hurt.sourceUtc()<1||hurt.sourceUtc()>nowUtc+50||nowUtc-hurt.sourceUtc()>2000||hurt.sourceUtc()<lastSourceUtc)
                throw new IllegalStateException("Native damage original source expired/regressed");
            if(!Float.isFinite(hurt.damage())||hurt.damage()<.001f||hurt.damage()>1000||hurt.attackerToken()<1||hurt.attackerToken()>256)
                throw new IllegalStateException("Native damage bounds differ");
            GameplayCombatProtocol.Actor actor=null;
            for(var candidate:actors)if(candidate.token()==hurt.attackerToken()){if(actor!=null)throw new IllegalStateException("Native damage actor duplicated");actor=candidate;}
            if(actor==null)throw new IllegalStateException("Native damage has no captured attacker");
            if(pending.size()>=32||!pending.isEmpty()&&hurt.sourceUtc()-pending.getFirst().hurt().sourceUtc()>2000)
                throw new IllegalStateException("Native damage backlog exceeds two seconds/32 events");
            long due=nowNano;
            if(hurt.sourceUtc()>lifeCutoffUtc){
                var previous=pending.peekLast();
                if(previous!=null&&!oldLife(previous))due=Math.max(nowNano,previous.dueNano()+(hurt.sourceUtc()-previous.hurt().sourceUtc())*1_000_000L);
                else if(lastAppliedSourceUtc>0)due=Math.max(nowNano,lastAppliedNano+(hurt.sourceUtc()-lastAppliedSourceUtc)*1_000_000L);
            }
            pending.addLast(new Entry(hurt,actor,due));seen.put(hurt.seq(),hurt);highest=hurt.seq();lastSourceUtc=hurt.sourceUtc();
            while(seen.size()>64)seen.remove(seen.keySet().iterator().next());
        }
    }
    public Entry due(long nowNano){
        var entry=pending.peekFirst();if(entry==null)return null;if(oldLife(entry))return entry;
        long due=entry.dueNano();if(lastAppliedSourceUtc>0)due=Math.max(due,lastAppliedNano+(entry.hurt().sourceUtc()-lastAppliedSourceUtc)*1_000_000L);
        return nowNano>=due?entry:null;
    }
    public void retire(Entry entry,long nowNano){
        if(pending.peekFirst()!=entry||entry.hurt().seq()!=ack+1)throw new IllegalStateException("Native damage retirement differs");
        pending.removeFirst();ack=entry.hurt().seq();
        if(!oldLife(entry)){lastAppliedSourceUtc=entry.hurt().sourceUtc();lastAppliedNano=nowNano;}
    }
    /** Native hits admitted under the dead player never cross into the replacement player. */
    public List<Entry> newLife(long utc){
        if(utc<lifeCutoffUtc)throw new IllegalStateException("Native damage respawn clock regressed");lifeCutoffUtc=utc;
        var discarded=List.copyOf(pending);pending.clear();ack=highest;lastAppliedSourceUtc=lastAppliedNano=0;return discarded;
    }
    public void close(){pending.clear();seen.clear();}
}
