package dev.minecome.hud;

import com.google.gson.JsonObject;
import dev.minecome.hud.HudMovementInventoryEvidence.Frame;
import dev.minecome.hud.HudMovementInventoryEvidence.Position;

/** Actual observed screens, bindings and later poses must agree before claiming inventory isolation. */
public final class HudMovementInventoryEvidenceTests {
    private static final long BASE=10_000_000_000L,MS=1_000_000L;
    private static int checks;
    private static void check(boolean value,String why){checks++;if(!value)throw new AssertionError(why);}
    private static Position p(double x){return new Position(x,64,0);}
    private static Frame frame(long ms,boolean inventory,double client,double server,int mask,boolean before){
        return detailed(ms,inventory,p(client),p(server),ms/50+1,ms,true,true,mask,before);
    }
    private static Frame detailed(long ms,boolean inventory,Position client,Position server,long sequence,long serverMs,
                                  boolean clientGrounded,boolean serverGrounded,int mask,boolean before){
        return new Frame(1000+ms,BASE+ms*MS,inventory,client,server,sequence,BASE+serverMs*MS,
                clientGrounded,serverGrounded,mask,before);
    }
    private static HudMovementInventoryEvidence closed(){
        var evidence=new HudMovementInventoryEvidence();
        for(long ms:new long[]{0,100,200})evidence.observe(frame(ms,true,0,0,0,false));
        evidence.observe(frame(300,false,0,0,0,false));return evidence;
    }
    private static void event(HudMovementInventoryEvidence evidence,long sequence,long ms,int kind,int key,boolean accepted){
        evidence.event(new HudInputProtocol.Event(sequence,1000+ms,kind,key,0,0,0),1000+ms,BASE+ms*MS,accepted);
    }
    private static void resume(HudMovementInventoryEvidence evidence,int mask,boolean before,double client,double server){
        event(evidence,1,320,1,0x57,true);
        evidence.observe(frame(350,false,0,0,mask,before));
        evidence.observe(frame(400,false,client,server,mask,before));
    }
    private static JsonObject window(HudMovementInventoryEvidence evidence){return evidence.evidence().getAsJsonArray("windows").get(0).getAsJsonObject();}
    private static boolean still(HudMovementInventoryEvidence evidence){return window(evidence).get("immobility_verified").getAsBoolean();}
    private static boolean resumed(HudMovementInventoryEvidence evidence){return window(evidence).getAsJsonObject("resumed_movement").get("verified").getAsBoolean();}
    private static boolean complete(HudMovementInventoryEvidence evidence){return evidence.evidence().get("capture_complete").getAsBoolean();}
    public static void main(String[] args){
        var good=closed();
        check(!still(good),"Live collection cannot claim final immobility before cleanup seals observations");
        resume(good,1,true,.06,.06);good.finish();
        check(complete(good)&&still(good)&&resumed(good),"Observed stationary inventory followed by accepted bound walking on both sides verifies");
        check(window(good).get("server_sequence_advances").getAsLong()>=2,"Inventory contains distinct advancing authoritative samples");
        check(!good.evidence().get("physical_attempt_observed").getAsBoolean(),"No missing native-suppressed attempt is invented");
        var exported=good.evidence();exported.getAsJsonArray("windows").get(0).getAsJsonObject().addProperty("immobility_verified",false);
        check(still(good),"Export mutation cannot change retained observations");

        var rejected=closed();event(rejected,1,320,1,0x57,false);
        rejected.observe(frame(400,false,.06,.06,1,true));rejected.finish();
        check(still(rejected)&&!resumed(rejected),"Movement after a rejected edge is not certified as accepted resumption");
        var jump=closed();event(jump,1,320,1,0x20,true);jump.observe(frame(400,false,.06,.06,16,true));jump.finish();
        check(!resumed(jump),"Jump acceptance cannot substitute for a walking key");
        var noBinding=closed();resume(noBinding,0,true,.06,.06);noBinding.finish();
        check(!resumed(noBinding),"Accepted event without actual nonzero bindings is insufficient");
        var releaseOnly=closed();resume(releaseOnly,1,false,.06,.06);releaseOnly.finish();
        check(!resumed(releaseOnly),"A binding observed outside the vanilla input phase cannot prove actual walking input");
        var wrongBinding=closed();resume(wrongBinding,2,true,.06,.06);wrongBinding.finish();
        check(!resumed(wrongBinding),"W acceptance cannot borrow an observed S binding");
        var clientOnly=closed();resume(clientOnly,1,true,.06,0);clientOnly.finish();
        check(!resumed(clientOnly),"Client displacement alone cannot prove authoritative resumed walking");
        var previousWalk=closed();previousWalk.observe(frame(310,false,.08,.08,0,true));
        event(previousWalk,1,320,1,0x57,true);previousWalk.observe(frame(400,false,.08,.08,1,true));previousWalk.finish();
        check(!resumed(previousWalk),"Displacement already present before the accepted edge cannot be reused");

        var drift=new HudMovementInventoryEvidence();
        drift.observe(frame(0,true,0,0,0,false));drift.observe(frame(100,true,.02,.02,0,false));
        drift.observe(frame(200,true,0,0,0,false));drift.observe(frame(300,false,0,0,0,false));drift.finish();
        check(!still(drift)&&window(drift).get("max_client_displacement").getAsDouble()==.02,
                "Moving away and returning while inventory is open still fails immobility");
        var divergence=new HudMovementInventoryEvidence();divergence.observe(frame(0,true,0,0,0,false));
        divergence.observe(frame(100,true,.009,-.009,0,false));divergence.observe(frame(200,true,0,0,0,false));
        divergence.observe(frame(300,false,0,0,0,false));divergence.finish();
        check(!still(divergence),"Individually small drift cannot conceal client/server disagreement");
        var airborne=new HudMovementInventoryEvidence();airborne.observe(frame(0,true,0,0,0,false));
        airborne.observe(detailed(100,true,p(0),p(0),3,100,true,false,0,false));
        airborne.observe(frame(200,true,0,0,0,false));airborne.observe(frame(300,false,0,0,0,false));airborne.finish();
        check(!still(airborne),"A non-grounded authoritative observation prevents a stationary-ground claim");
        var leaking=new HudMovementInventoryEvidence();leaking.observe(frame(0,true,0,0,0,false));
        leaking.observe(frame(100,true,0,0,1,true));leaking.observe(frame(200,true,0,0,0,false));
        leaking.observe(frame(300,false,0,0,0,false));leaking.finish();
        check(!still(leaking)&&window(leaking).get("bindings_or").getAsInt()==1,"Zero displacement does not excuse a leaked walking binding");

        var stale=new HudMovementInventoryEvidence();stale.observe(frame(0,true,0,0,0,false));
        stale.observe(detailed(100,true,p(0),p(0),2,-151,true,true,0,false));
        stale.observe(frame(200,true,0,0,0,false));stale.observe(frame(300,false,0,0,0,false));stale.finish();
        check(!still(stale)&&window(stale).get("stale_samples").getAsLong()>0,"Old server data fails instead of filling an inventory gap");
        var unavailable=new HudMovementInventoryEvidence();unavailable.observe(frame(0,true,0,0,0,false));
        unavailable.observe(detailed(100,true,p(0),null,3,100,true,true,0,false));
        unavailable.observe(frame(200,true,0,0,0,false));unavailable.observe(frame(300,false,0,0,0,false));unavailable.finish();
        check(!still(unavailable),"Missing server position cannot be treated as zero displacement proof");
        var repeated=new HudMovementInventoryEvidence();
        for(long ms:new long[]{0,100,200,250})repeated.observe(detailed(ms,ms!=250,p(0),p(0),1,0,true,true,0,false));
        repeated.finish();check(!still(repeated)&&window(repeated).get("server_sequence_advances").getAsLong()==0,
                "Repeated reads of one fresh server observation do not establish an interval");
        var preOpen=new HudMovementInventoryEvidence();
        for(long ms:new long[]{0,100,200})preOpen.observe(detailed(ms,true,p(0),p(0),1,-1,true,true,0,false));
        preOpen.observe(detailed(250,false,p(0),p(0),2,100,true,true,0,false));preOpen.finish();
        check(!still(preOpen)&&window(preOpen).get("samples").getAsLong()==1,"Fresh pre-open server data is excluded from inventory proof");
        var gap=new HudMovementInventoryEvidence();
        for(long ms:new long[]{0,300,400,500})gap.observe(frame(ms,ms!=500,0,0,0,false));gap.finish();
        check(!still(gap),"Fresh endpoint observations cannot conceal a missing interval longer than 250ms");
        var shortWindow=new HudMovementInventoryEvidence();
        for(long ms:new long[]{0,50,100,200})shortWindow.observe(frame(ms,ms!=200,0,0,0,false));shortWindow.finish();
        check(!still(shortWindow),"An inventory shorter than 250ms is insufficient even with many observations");
        var unclosed=new HudMovementInventoryEvidence();
        for(long ms:new long[]{0,100,200,300})unclosed.observe(frame(ms,true,0,0,0,false));unclosed.finish();
        check(!complete(unclosed)&&!still(unclosed)&&!window(unclosed).get("complete").getAsBoolean(),"Cleanup never invents an inventory close");

        var oldResume=closed();event(oldResume,1,320,1,0x57,true);
        oldResume.observe(detailed(350,false,p(.06),p(.06),8,310,true,true,1,true));oldResume.finish();
        check(!resumed(oldResume),"A fresh but pre-edge server pose cannot prove later resumed displacement");
        var shortTap=closed();event(shortTap,1,320,1,0x57,true);
        shortTap.observe(detailed(330,false,p(0),p(0),8,310,true,true,1,true));
        event(shortTap,2,340,2,0x57,false);
        shortTap.observe(detailed(400,false,p(.06),p(.06),9,390,true,true,0,true));shortTap.finish();
        check(resumed(shortTap),"An actual short-tap binding can precede its authoritative displacement without requiring the key to stay held");
        var regressedResume=closed();resume(regressedResume,1,true,.06,.06);
        regressedResume.observe(detailed(410,false,p(.06),p(.06),8,390,true,true,1,true));regressedResume.finish();
        check(!resumed(regressedResume),"Regressed authoritative sequence/time invalidates resumed walking proof");
        var staleResume=closed();event(staleResume,1,320,1,0x57,true);
        staleResume.observe(detailed(600,false,p(.06),p(.06),8,349,true,true,1,true));staleResume.finish();
        check(!resumed(staleResume),"A stale post-event server pose cannot prove resumed displacement");

        var deniedInside=new HudMovementInventoryEvidence();deniedInside.observe(frame(0,true,0,0,0,false));
        event(deniedInside,1,50,1,0x57,false);event(deniedInside,2,60,2,0x57,false);
        deniedInside.observe(frame(100,true,0,0,0,false));deniedInside.observe(frame(200,true,0,0,0,false));
        deniedInside.observe(frame(300,false,0,0,0,false));deniedInside.finish();
        check(still(deniedInside)&&window(deniedInside).get("delivered_w_down_observed").getAsBoolean(),"A delivered denied W is recorded separately from physical input provenance");
        check(!deniedInside.evidence().get("physical_attempt_observed").getAsBoolean(),"Even a delivered edge does not certify physical input provenance");
        var acceptedInside=new HudMovementInventoryEvidence();acceptedInside.observe(frame(0,true,0,0,0,false));
        event(acceptedInside,1,50,1,0x57,true);acceptedInside.observe(frame(100,true,0,0,0,false));
        acceptedInside.observe(frame(200,true,0,0,0,false));acceptedInside.observe(frame(300,false,0,0,0,false));acceptedInside.finish();
        check(!complete(acceptedInside)&&!still(acceptedInside),"An accepted inventory movement edge invalidates collection");
        var clock=closed();clock.observe(frame(299,false,0,0,0,false));clock.finish();
        check(!complete(clock),"Regressed observation clocks cannot silently preserve proof");

        var windows=new HudMovementInventoryEvidence();
        for(int i=0;i<5;i++)for(long offset:new long[]{0,100,200,300})windows.observe(frame(i*500L+offset,offset!=300,0,0,0,false));
        windows.finish();check(windows.evidence().getAsJsonArray("windows").size()==4&&windows.evidence().get("window_count").getAsLong()==5,
                "Window storage is bounded while aggregate count records overflow");
        check(windows.evidence().get("truncated").getAsBoolean()&&!complete(windows),"Truncation cannot claim complete inventory evidence");
        var events=closed();for(int i=1;i<=33;i++)event(events,i,320+i,2,0x57,false);events.finish();
        check(events.evidence().getAsJsonArray("events").size()==32&&events.evidence().get("event_count").getAsLong()==33,
                "Delivered edge storage is bounded and overflow stays visible");
        check(events.evidence().get("truncated").getAsBoolean()&&!still(events),"Truncated edge evidence cannot certify immobility");
        System.out.println("HudMovementInventoryEvidenceTests: "+checks+" checks passed; no games");
    }
}
