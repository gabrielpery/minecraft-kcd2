package dev.minecome.gameplay;

import java.util.*;

/** Native source lifetime and delayed-batch behavior, independent of either game. */
public final class GameplayIncomingDamageTests {
    private static final long UTC=1_800_000_000_000L,NANO=10_000_000_000L;
    private static final GameplayCombatProtocol.Actor ACTOR=new GameplayCombatProtocol.Actor(1,1,2,3,.6f,1.8f,100,100,true);
    private static int checks;
    private static GameplayCombatProtocol.Hurt hurt(long seq,long utc){return new GameplayCombatProtocol.Hurt(seq,1,8,utc,"melee");}
    private static void check(boolean ok,String reason){checks++;if(!ok)throw new AssertionError(reason);}
    private static void reject(Runnable action,String reason){try{action.run();throw new AssertionError(reason);}catch(IllegalStateException expected){checks++;}}
    public static int run(){
        checks=0;var q=new GameplayIncomingDamage();var first=hurt(1,UTC-1500);var second=hurt(2,UTC-900);
        q.admit(List.of(first,second),List.of(ACTOR),UTC,NANO);
        var entry=q.due(NANO);check(entry!=null&&entry.actor()==ACTOR&&entry.hurt().equals(first),"First real source and captured attacker preserved");
        q.retire(entry,NANO);check(q.ack()==1&&q.due(NANO+599_000_000L)==null,"Batched hits retain original 600ms interval");
        entry=q.due(NANO+600_000_000L);check(entry!=null&&entry.hurt().equals(second),"Second source becomes due without retimestamping");
        q.retire(entry,NANO+600_000_000L);q.admit(List.of(first,second),List.of(),UTC+10000,NANO+10_000_000_000L);
        check(q.pending()==0&&q.ack()==2,"Acknowledged unchanged republishing cannot replay or refresh damage");
        reject(()->q.admit(List.of(new GameplayCombatProtocol.Hurt(2,1,9,UTC-900,"melee")),List.of(ACTOR),UTC,NANO),"Same sequence changed damage rejected");
        reject(()->q.admit(List.of(new GameplayCombatProtocol.Hurt(2,1,8,UTC-900,"projectile")),List.of(ACTOR),UTC,NANO),"Same sequence changed native damage classification rejected");
        reject(()->new GameplayIncomingDamage().admit(List.of(new GameplayCombatProtocol.Hurt(1,1,8,UTC,"unknown")),List.of(ACTOR),UTC,NANO),"Unknown native damage classification rejected");
        var projectile=new GameplayIncomingDamage();var arrow=new GameplayCombatProtocol.Hurt(1,1,8,UTC,"projectile");projectile.admit(List.of(arrow),List.of(ACTOR),UTC,NANO);
        check(projectile.due(NANO).hurt().kind().equals("projectile"),"Native projectile classification remains immutable through admission");
        reject(()->q.admit(List.of(hurt(2,UTC)),List.of(ACTOR),UTC,NANO),"Same sequence changed source time rejected");
        reject(()->q.admit(List.of(hurt(4,UTC)),List.of(ACTOR),UTC,NANO),"Gap rejected");
        for(long source:List.of(UTC-2001,UTC+51))reject(()->new GameplayIncomingDamage().admit(List.of(hurt(1,source)),List.of(ACTOR),UTC,NANO),"First admission rejects expired/future original source");
        reject(()->new GameplayIncomingDamage().admit(List.of(hurt(1,UTC)),List.of(),UTC,NANO),"Missing captured attacker rejected");
        reject(()->new GameplayIncomingDamage().admit(List.of(hurt(1,UTC)),List.of(ACTOR,ACTOR),UTC,NANO),"Ambiguous captured attacker rejected");
        var regressed=new GameplayIncomingDamage();regressed.admit(List.of(hurt(1,UTC)),List.of(ACTOR),UTC,NANO);
        reject(()->regressed.admit(List.of(hurt(2,UTC-1)),List.of(ACTOR),UTC,NANO),"Original source clock regression rejected");
        var stalled=new GameplayIncomingDamage();stalled.admit(List.of(first,second),List.of(ACTOR),UTC,NANO);
        var delayed=stalled.due(NANO+3_000_000_000L);stalled.retire(delayed,NANO+3_000_000_000L);
        check(stalled.due(NANO+3_599_000_000L)==null&&stalled.due(NANO+3_600_000_000L)!=null,"A stalled Minecraft tick cannot collapse original spacing into vanilla cooldown");
        stalled.admit(List.of(first,second),List.of(),UTC+10000,NANO+10_000_000_000L);
        check(stalled.entries().getFirst().hurt().sourceUtc()==UTC-900,"Accepted queued source survives republishing without renewed freshness");
        var sameTime=new GameplayIncomingDamage();sameTime.admit(List.of(hurt(1,UTC),hurt(2,UTC)),List.of(ACTOR),UTC,NANO);
        sameTime.retire(sameTime.due(NANO),NANO);check(sameTime.due(NANO)!=null,"Simultaneous native hits leave vanilla cooldown semantics intact");
        var life=new GameplayIncomingDamage();life.admit(List.of(first,second),List.of(ACTOR),UTC,NANO);
        var discarded=life.newLife(UTC+1);check(discarded.size()==2&&life.ack()==2&&life.pending()==0,"Respawn retires prior-life backlog without damage");
        life.admit(List.of(hurt(3,UTC)),List.of(ACTOR),UTC+2,NANO);entry=life.due(NANO);
        check(life.oldLife(entry),"Late pre-respawn source is explicitly old-life");life.retire(entry,NANO);
        life.admit(List.of(hurt(4,UTC+2)),List.of(ACTOR),UTC+3,NANO);entry=life.due(NANO);
        check(entry!=null&&!life.oldLife(entry),"New-life source does not inherit dead player's pacing");
        life.close();check(life.pending()==0&&life.due(NANO)==null,"Lease end removes all pending damage");
        var capacity=new GameplayIncomingDamage();var batch=new ArrayList<GameplayCombatProtocol.Hurt>();for(int i=1;i<=32;i++)batch.add(hurt(i,UTC));
        capacity.admit(batch,List.of(ACTOR),UTC,NANO);reject(()->capacity.admit(List.of(hurt(33,UTC)),List.of(ACTOR),UTC,NANO),"Pending queue capped at32");
        return checks;
    }
}
