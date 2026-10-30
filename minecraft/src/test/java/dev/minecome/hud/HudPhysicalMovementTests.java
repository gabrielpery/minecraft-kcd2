package dev.minecome.hud;

import com.google.gson.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;

/** Pure protocol, held-input and original-capture freshness tests; no games or synthetic native input. */
public final class HudPhysicalMovementTests {
    private static int checks;
    private static final String RUN="a".repeat(32),PATCH="b".repeat(32),HASH="c".repeat(64);
    private static final long NOW=1_800_000_000_000L;
    private static final HudInputProtocol.Identity ID=new HudInputProtocol.Identity(RUN,1,11,2,22,NOW+100000);
    private interface Work{void run()throws Exception;}
    private static void check(boolean b,String why){checks++;if(!b)throw new AssertionError(why);}
    private static void reject(Work work,String why)throws Exception{
        try{work.run();throw new AssertionError("Accepted "+why);}catch(java.io.IOException|IllegalArgumentException expected){checks++;}
    }
    private static Properties mode(){
        var p=new Properties();
        for(String key:List.of("hudPhysicalMovement","hudStreamLab","hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation"))p.setProperty("minecome."+key,"true");
        for(String key:List.of("groundPatchFile","movementTraceFile","hudHostViewFile"))p.setProperty("minecome."+key,"absolute-file");
        return p;
    }
    private static JsonObject vector(double x,double y,double z){var v=new JsonObject();v.addProperty("x",x);v.addProperty("y",y);v.addProperty("z",z);return v;}
    private static JsonObject view(long seq,long utc){
        var v=new JsonObject();v.addProperty("schema",1);v.addProperty("source_kind","live_kcd_hud_view_v1");v.addProperty("run",RUN);
        v.addProperty("patch_run",PATCH);v.addProperty("patch_sha256",HASH);v.addProperty("target_pid",2);v.addProperty("target_start_filetime","22");
        v.addProperty("seq",seq);v.addProperty("utc_ms",utc);v.add("forward",vector(0,-1,0));v.add("up",vector(0,0,1));return v;
    }
    private static byte[] bytes(JsonObject v){return v.toString().getBytes(StandardCharsets.UTF_8);}
    private static HudMovementView parse(JsonObject v)throws Exception{return HudMovementView.parse(bytes(v),ID,PATCH,HASH,NOW);}
    private static void modes()throws Exception{
        check(!HudPhysicalMovementMode.require(new Properties()),"Legacy defaults unchanged");
        check(HudPhysicalMovementMode.require(mode()),"Explicit complete movement profile accepted");
        check(HudMovementSession.selected(mode())==HudMovementSession.SHORT,"Physical default retains short session");
        var extended=mode();extended.setProperty("minecome.hudPhysicalMovementExtended","true");
        check(HudPhysicalMovementMode.require(extended) && HudMovementSession.selected(extended)==HudMovementSession.EXTENDED,"Complete live mode permits explicitly extended policy");
        var wide=new Properties();wide.putAll(extended);wide.setProperty("minecome.hudWideWalking","true");
        check(HudPhysicalMovementMode.require(wide)&&HudPhysicalMovementMode.wide(wide),"Explicit wide live walking retains physical mode");
        var wideOrphan=new Properties();wideOrphan.setProperty("minecome.hudWideWalking","true");
        reject(()->HudPhysicalMovementMode.require(wideOrphan),"wide area cannot enable unrelated modes");
        for(String invalid:List.of("TRUE","9","1","")){
            var p=mode();p.setProperty("minecome.hudWideWalking",invalid);reject(()->HudPhysicalMovementMode.require(p),"malformed wide option");
        }
        var orphan=new Properties();orphan.setProperty("minecome.hudPhysicalMovementExtended","true");
        reject(()->HudPhysicalMovementMode.require(orphan),"extended option cannot enable another mode implicitly");
        for(String invalid:List.of("TRUE","15","1","","extended")){
            var p=mode();p.setProperty("minecome.hudPhysicalMovementExtended",invalid);reject(()->HudPhysicalMovementMode.require(p),"malformed extended option "+invalid);
        }
        for(String key:List.of("hudStreamLab","hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation","groundPatchFile","movementTraceFile","hudHostViewFile")){
            var p=mode();p.remove("minecome."+key);reject(()->HudPhysicalMovementMode.require(p),"missing "+key);
        }
        for(String key:List.of("hudStreamStandalone","hudGroundMovementFixture","hudGroundMovementCoupled","hudStreamInputFixture",
                "hudStreamInputPointerFixture","hudStreamInputDelayFixture","hudStreamBackgroundTrial","hudStreamOffscreenTrial","hudStoneBridge",
                "hudStoneFixture","hudStoneLive","hudAimedStoneBridge","groundMovementLab","externalInputLab","externalInputFixture",
                "aimedStoneLab","aimedBridgeLab","hudAimedBridgeLab","hudExportLab","interactiveStoneLab","smokeWorld","dynamicBridgeSmoke")){
            var p=mode();p.setProperty("minecome."+key,"true");reject(()->HudPhysicalMovementMode.require(p),"conflict "+key);
        }
        var fixture=new Properties();
        for(String key:List.of("hudPhysicalMovementFixture","hudStreamLab","hudStreamStandalone"))fixture.setProperty("minecome."+key,"true");
        for(String key:List.of("groundPatchFile","movementTraceFile","hudHostViewFile"))fixture.setProperty("minecome."+key,"fixture-file");
        check(HudPhysicalMovementMode.require(fixture) && HudPhysicalMovementMode.fixture(fixture),"Separate labelled scripted physical controller mode");
        var extendedFixture=new Properties();extendedFixture.putAll(fixture);extendedFixture.setProperty("minecome.hudPhysicalMovementExtended","true");
        check(HudPhysicalMovementMode.require(extendedFixture) && HudMovementSession.selected(extendedFixture)==HudMovementSession.EXTENDED,"Fixture opts into the same extended controller policy explicitly");
        for(var base:List.of(extended,extendedFixture)){
            var corridor=(Properties)base.clone();corridor.setProperty("minecome.hudCorridorWalking","true");
            check(HudPhysicalMovementMode.require(corridor)&&HudPhysicalMovementMode.corridor(corridor),"Explicit corridor retains extended physical live/fixture identity");
            for(String key:List.of("hudWideWalking","hudWalkingAimed","hudFacingSeedFixture","hudGroundMovementFixture",
                    "hudGroundMovementCoupled","hudGroundCorridorFixture","hudGroundCorridorCoupled","hudGroundCorridorWalkOnly")){
                var mixed=(Properties)corridor.clone();mixed.setProperty("minecome."+key,"true");
                reject(()->HudPhysicalMovementMode.require(mixed),"Physical corridor rejects "+key);
            }
            var corridorAimed=(Properties)corridor.clone();corridorAimed.setProperty("minecome.hudWalkingAimedFixture","true");
            if(HudPhysicalMovementMode.fixture(corridor)){
                check(HudPhysicalMovementMode.require(corridorAimed)&&HudPhysicalMovementMode.fixtureYaw(corridorAimed)==-90,"Corridor aimed fixture retains standalone extended authority and eastward heading");
                var late=(Properties)corridorAimed.clone();late.setProperty("minecome.hudWalkingLateCutoffFixture","true");
                check(HudPhysicalMovementMode.require(late)&&HudPhysicalMovementMode.lateCutoffFixture(late),"Explicit late cutoff uses standalone corridor authority");
                for(String required:List.of("hudPhysicalMovementFixture","hudPhysicalMovementExtended","hudCorridorWalking","hudWalkingAimedFixture")){
                    var missing=(Properties)late.clone();missing.setProperty("minecome."+required,"false");
                    reject(()->HudPhysicalMovementMode.require(missing),"Late cleanup requires "+required);
                }
                for(String malformed:List.of("TRUE","1","")){
                    var invalid=(Properties)late.clone();invalid.setProperty("minecome.hudWalkingLateCutoffFixture",malformed);
                    reject(()->HudPhysicalMovementMode.require(invalid),"Late cleanup flag is strict boolean");
                }
                for(String yaw:List.of("0","90","180","NaN","Infinity","-181")){
                    var invalid=(Properties)corridorAimed.clone();invalid.setProperty("minecome.hudPhysicalFixtureYaw",yaw);
                    reject(()->HudPhysicalMovementMode.require(invalid),"Corridor aimed fixture rejects incompatible yaw before world construction");
                }
                corridorAimed.setProperty("minecome.hudPhysicalFixtureYaw","-90");
                check(HudPhysicalMovementMode.require(corridorAimed)&&HudPhysicalMovementMode.fixtureYaw(corridorAimed)==-90,"Explicit corridor fixture yaw follows the same validated constructor path");
            }
            else reject(()->HudPhysicalMovementMode.require(corridorAimed),"Corridor live input cannot acquire scripted aiming");
            corridor.remove("minecome.hudPhysicalMovementExtended");reject(()->HudPhysicalMovementMode.require(corridor),"Corridor cannot use short timing");
        }
        var corridorOrphan=new Properties();corridorOrphan.setProperty("minecome.hudCorridorWalking","true");
        reject(()->HudPhysicalMovementMode.require(corridorOrphan),"Corridor cannot enable implicit physical ownership");
        for(String invalid:List.of("TRUE","1","","corridor")){
            var p=(Properties)extended.clone();p.setProperty("minecome.hudCorridorWalking",invalid);reject(()->HudPhysicalMovementMode.require(p),"Malformed corridor selector");
        }
        var wideFixture=new Properties();wideFixture.putAll(extendedFixture);wideFixture.setProperty("minecome.hudWideWalking","true");
        check(HudPhysicalMovementMode.require(wideFixture),"Wide crossing fixture retains extended movement");
        wideFixture.setProperty("minecome.hudWalkingAimedFixture","true");
        check(HudPhysicalMovementMode.require(wideFixture),"Wide extended fixture supports aimed blocks after its boundary crossing");
        var facingFixture=new Properties();facingFixture.putAll(wideFixture);facingFixture.setProperty("minecome.hudFacingSeedFixture","true");
        check(HudPhysicalMovementMode.require(facingFixture)&&HudPhysicalMovementMode.facingFixture(facingFixture),"Facing bootstrap uses only the explicit wide aimed fixture");
        for(String key:List.of("hudWideWalking","hudWalkingAimedFixture","hudPhysicalMovementFixture","hudPhysicalMovementExtended")){
            var p=new Properties();p.putAll(facingFixture);p.remove("minecome."+key);
            reject(()->HudPhysicalMovementMode.require(p),"Facing fixture requires "+key);
        }
        for(String invalid:List.of("TRUE","1","","facing")){
            var p=new Properties();p.putAll(facingFixture);p.setProperty("minecome.hudFacingSeedFixture",invalid);
            reject(()->HudPhysicalMovementMode.require(p),"Malformed facing fixture option");
        }
        var facingLive=mode();facingLive.setProperty("minecome.hudFacingSeedFixture","true");
        reject(()->HudPhysicalMovementMode.require(facingLive),"Facing fixture cannot attach to live input");
        var wideAimedShort=new Properties();wideAimedShort.putAll(wideFixture);wideAimedShort.remove("minecome.hudPhysicalMovementExtended");
        reject(()->HudPhysicalMovementMode.require(wideAimedShort),"wide aimed fixture still requires extended timing");
        wideFixture.remove("minecome.hudWalkingAimedFixture");wideFixture.remove("minecome.hudPhysicalMovementExtended");
        reject(()->HudPhysicalMovementMode.require(wideFixture),"short fixture cannot claim wide crossing scenario");
        var combined=new Properties();combined.putAll(extendedFixture);combined.setProperty("minecome.hudWalkingAimedFixture","true");
        check(HudPhysicalMovementMode.require(combined),"Combined aimed walking requires explicit standalone extended fixture");
        check(HudPhysicalMovementMode.fixtureYaw(combined)==0,"Legacy aimed fixture retains yaw zero");
        var legacyWrongYaw=(Properties)combined.clone();legacyWrongYaw.setProperty("minecome.hudPhysicalFixtureYaw","-90");
        reject(()->HudPhysicalMovementMode.require(legacyWrongYaw),"Legacy aimed fixture cannot borrow the corridor heading");
        var genericYaw=(Properties)fixture.clone();genericYaw.setProperty("minecome.hudPhysicalFixtureYaw","90");
        check(HudPhysicalMovementMode.require(genericYaw)&&HudPhysicalMovementMode.fixtureYaw(genericYaw)==90,"Ordinary non-aimed fixture retains configurable finite yaw");
        for(Properties source:List.of(new Properties(),mode(),extended,fixture)){
            var p=new Properties();p.putAll(source);p.setProperty("minecome.hudWalkingAimedFixture","true");
            reject(()->HudPhysicalMovementMode.require(p),"Combined fixture cannot acquire incomplete or live profile");
        }
        for(String invalid:List.of("TRUE","1","","aimed")){
            var p=new Properties();p.putAll(extendedFixture);p.setProperty("minecome.hudWalkingAimedFixture",invalid);
            reject(()->HudPhysicalMovementMode.require(p),"Malformed combined fixture flag");
        }
        for(String key:List.of("hudPhysicalMovement","hudStreamInput","hudStreamLiveMouse","hudStreamOffscreenPresentation","hudGroundMovementFixture","hudGroundMovementCoupled","hudStreamInputFixture")){
            var p=new Properties();p.putAll(fixture);p.setProperty("minecome."+key,"true");reject(()->HudPhysicalMovementMode.require(p),"fixture cannot acquire "+key);
        }
        for(String key:List.of("hudStreamLab","hudStreamStandalone","groundPatchFile","movementTraceFile","hudHostViewFile")){
            var p=new Properties();p.putAll(fixture);p.remove("minecome."+key);reject(()->HudPhysicalMovementMode.require(p),"fixture missing "+key);
        }
        var fixtureView=view(1,NOW);fixtureView.addProperty("source_kind","standalone_hud_physical_view_fixture");
        reject(()->parse(fixtureView),"live reader rejects scripted camera provenance");
        check(HudMovementView.parse(bytes(fixtureView),ID,PATCH,HASH,NOW,true).sequence()==1,"Explicit fixture parser accepts only labelled fixture view");
        reject(()->HudMovementView.parse(bytes(view(1,NOW)),ID,PATCH,HASH,NOW,true),"fixture reader rejects live view provenance");
        check(!HudMovementView.parse(bytes(fixtureView),ID,PATCH,HASH,NOW+301,true).fresh(NOW+301),"Fixture retains original300ms freshness");
        // Construct the actual producer without starting its worker/native mapping.
        // The first autonomous run caught a separate constructor guard which
        // pure mode tests alone had not exercised.
        var original=System.getProperties();
        try{
            var selected=new Properties();selected.putAll(original);selected.putAll(fixture);System.setProperties(selected);
            Path root=Path.of(".").toAbsolutePath();String save="MineCome-HudStream-"+UUID.randomUUID();
            var identity=new HudStreamProducer.Identity(RUN,2,22,NOW+100000);
            new HudStreamProducer(root,root.resolve("fixture-output"),identity,save,true,0);checks++;
            reject(()->new HudStreamProducer(root,root.resolve("fixture-output"),identity,save,false,0),"fixture producer cannot claim synthetic transport pixels");
            reject(()->new HudStreamProducer(root,root.resolve("fixture-output"),identity,save,true,1),"fixture producer cannot acquire live input mode");
            reject(()->new HudStreamProducer(root,root.resolve("fixture-output"),identity,save,true,2),"fixture producer cannot acquire native input fixture mode");
            selected=new Properties();selected.putAll(original);selected.putAll(mode());System.setProperties(selected);
            new HudStreamProducer(root,root.resolve("live-output"),identity,save,true,1);checks++;
            reject(()->new HudStreamProducer(root,root.resolve("live-output"),identity,save,true,0),"live producer retains its required input mode");
            reject(()->new HudStreamProducer(root,root.resolve("live-output"),identity,save,false,1),"live producer retains genuine pixels guard");
        }finally{System.setProperties(original);}
    }
    private static void wire()throws Exception{
        for(int key:List.of(0x57,0x41,0x53,0x44,0x20)){
            var event=new HudInputProtocol.Event(1,NOW,1,key,0,0,0);
            reject(()->HudInputProtocol.validateEvent(event,NOW,true),"legacy movement key");
            HudInputProtocol.validateEvent(event,NOW,true,true);checks++;
            var gate=new HudInputGate(true);gate.apply(event,NOW);check(gate.heldKeyCount()==1,"v2 strict hold");
            reject(()->gate.apply(new HudInputProtocol.Event(2,NOW,1,key,0,0,0),NOW),"duplicate movement down");
            gate.apply(new HudInputProtocol.Event(2,NOW,2,key,0,0,0),NOW);check(gate.heldKeyCount()==0,"v2 balanced release");
        }
        reject(()->HudInputProtocol.validateEvent(new HudInputProtocol.Event(1,NOW,1,0x10,0,0,0),NOW,true,true),"v2 unsupported shift");
        byte[] bytes=new byte[2816];var b=ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
        b.put("MCHUDI02".getBytes(StandardCharsets.US_ASCII));b.putInt(8,2).putInt(12,2816);
        b.position(16);b.put(RUN.getBytes(StandardCharsets.US_ASCII));b.putInt(48,1).putInt(52,2).putLong(56,11).putLong(64,22).putLong(72,ID.expires());
        b.putLong(80,1).putLong(88,NOW).putInt(96,1).putInt(100,1);
        b.putLong(256,1).putLong(264,NOW).putInt(272,1).putInt(276,0x57);
        check(HudInputProtocol.decode(bytes,ID,0,NOW,0,true).events().size()==1,"v2 exact same-sized mapping decoded");
        reject(()->HudInputProtocol.decode(bytes,ID,0,NOW,0),"v1 cannot accept v2 header");
        b.putInt(8,1);reject(()->HudInputProtocol.decode(bytes,ID,0,NOW,0,true),"mixed magic version");
        b.putInt(8,2);b.putLong(264,NOW-251);reject(()->HudInputProtocol.decode(bytes,ID,0,NOW,0,true),"v2 retains250ms edge freshness");
    }
    private static void holds(){
        long now=1_000_000_000L;var gate=new HudMovementKeys();
        check(!gate.event(1,0x57,now,false) && !gate.started(),"unready down cannot start");
        gate.authority(now,true);check(!gate.down(0x57,now),"held raw input cannot resume after authority returns");
        gate.event(2,0x57,now,true);gate.authority(now,true);
        check(gate.event(1,0x57,now,true) && gate.down(0x57,now),"fresh down after neutral starts");
        gate.suspend();check(!gate.down(0x57,now),"inventory suspend immediately neutralizes");
        gate.authority(now+1,true);check(!gate.down(0x57,now+1),"inventory close does not restore held movement");
        gate.event(2,0x57,now+2,true);gate.authority(now+2,true);
        check(gate.event(1,0x57,now+3,true),"fresh release and down resume within original window");
        check(!gate.down(0x57,now+2+HudMovementKeys.HOLD_LEASE_NS),"stale input lease releases before tick");
        gate.authority(now+200_000_000,true);check(!gate.down(0x57,now+200_000_000),"heartbeat cannot resume stale held key");
        gate.event(2,0x57,now+200_000_000,true);gate.authority(now+200_000_000,true);gate.event(1,0x20,now+200_000_000,true);
        check(gate.down(0x20,now+200_000_000),"space uses same held lease");
        gate.authority(now+HudMovementKeys.ACTIVE_NS,true);
        check(gate.ended() && gate.neutral(now+HudMovementKeys.ACTIVE_NS),"fixed5s lifetime releases without renewal");
        gate.event(2,0x20,now+HudMovementKeys.ACTIVE_NS,true);gate.authority(now+HudMovementKeys.ACTIVE_NS,true);
        check(!gate.event(1,0x57,now+HudMovementKeys.ACTIVE_NS,true),"terminal cannot reactivate");
        gate.close();check(gate.rawCount()==0,"disconnect close releases raw bookkeeping");
        gate=new HudMovementKeys();gate.authority(now,true);gate.event(1,0x57,now,true);
        check(!gate.down(0x57,now-1) && gate.ended(),"monotonic regression ends movement");
        gate=new HudMovementKeys();gate.authority(now,true);gate.event(1,0x57,now,true);
        long originalStart=gate.startedAt();gate.suppressAtBoundary();
        check(!gate.ended() && gate.neutral(now),"spatial boundary suppresses input without finishing movement window");
        gate.authority(now+50_000_000L,true);
        check(!gate.down(0x57,now+50_000_000L),"renewed authority cannot restart held input at a boundary");
        gate.event(2,0x57,now+100_000_000L,true);gate.authority(now+100_000_000L,true);
        check(gate.event(1,0x53,now+110_000_000L,true) && gate.down(0x53,now+110_000_000L),"fresh reverse press can resume in same trial");
        gate.suppressAtBoundary();gate.event(2,0x53,now+200_000_000L,true);gate.authority(now+200_000_000L,true);
        check(gate.event(1,0x41,now+210_000_000L,true),"second fresh direction can resume after another boundary");
        check(gate.startedAt()==originalStart,"boundary release and re-press never renew activation timestamp");
        gate.event(2,0x41,now+300_000_000L,true);gate.authority(now+HudMovementKeys.ACTIVE_NS-1,true);
        check(gate.event(1,0x44,now+HudMovementKeys.ACTIVE_NS-1,true),"fresh input remains available until original deadline");
        gate.expire(now+HudMovementKeys.ACTIVE_NS);
        check(gate.ended() && gate.neutral(now+HudMovementKeys.ACTIVE_NS),"original five-second deadline ends all resumed movement");
        gate=new HudMovementKeys();gate.authority(now,true);gate.event(1,0x57,now,true);gate.suppressAtBoundary();
        gate.authority(now+50_000_000L,true);gate.event(2,0x57,now+50_000_001L,true);
        check(gate.event(1,0x53,now+50_000_002L,true),"balanced release and fresh press in the same input batch can resume");
        gate.suppressAtBoundary();gate.event(2,0x53,now+50_000_003L,true);
        check(!gate.event(1,0x41,now+50_000_004L,true),"release without a renewed authority lease cannot rearm");
    }
    private static void extendedHolds(){
        var session=HudMovementSession.EXTENDED;long at=1_000_000_000L;
        check(session.activeNs()==15_000_000_000L && session.maximumMotionNs()==16_000_000_000L,"Extended session has fixed15s input plus1s settling");
        check(session.traceBytes()==256*1024 && HudMovementSession.SHORT.traceBytes()==64*1024,"Trace byte budgets are explicitly isolated by session");
        check(!session.traceSource(false).equals(HudMovementSession.SHORT.traceSource(false)) &&
                !session.traceSource(true).equals(session.traceSource(false)),"Extended live and fixture trace identities are distinct");
        check(session.mayStart(-10_000_000_000L,1_999_999_999L),"Admission handles valid signed monotonic clocks");
        check(!session.mayStart(at,at-1) && !session.mayStart(Long.MIN_VALUE,Long.MAX_VALUE),"Regressed or overflowing admission interval is rejected");
        var gate=new HudMovementKeys(session);gate.authority(at,true);
        check(!gate.event(1,0x57,at,true) && !gate.started() && gate.lateStartsDenied()==1,"Extended controls cannot start before activation is supplied");
        gate.close();
        gate=new HudMovementKeys(session);gate.activate(at);gate.authority(at,true);gate.event(1,0x57,at,true);
        gate.event(2,0x57,at+1,true);gate.suspend();
        long later=at+6_000_000_000L;gate.authority(later,true);
        check(gate.event(1,0x53,later,true) && gate.down(0x53,later),"Fresh movement beyond five seconds remains possible only in extended mode");
        gate.suppressAtBoundary();gate.authority(later+1,true);
        check(!gate.down(0x53,later+1),"Extended boundary pause never resumes an old held key");
        gate.event(2,0x53,later+2,true);
        check(gate.event(1,0x44,later+3,true),"Extended boundary permits fresh reverse direction after balancing");
        check(!gate.down(0x44,later+HudMovementKeys.HOLD_LEASE_NS+1),"Longer session retains150ms hold lease");
        gate.event(2,0x44,later+HudMovementKeys.HOLD_LEASE_NS+2,false);
        long end=at+session.activeNs();gate.authority(end-1,true);
        check(gate.event(1,0x41,end-1,true),"Extended fresh input can run immediately before original15s limit");
        gate.activate(end-1);gate.authority(end,true);
        check(gate.ended() && gate.neutral(end) && gate.startedAt()==at,"Inventory, boundary and repeated activation cannot renew original15s limit");
        gate.event(2,0x41,end,true);
        check(!gate.event(1,0x57,end+1,true),"Expired extended session cannot restart");
        gate.close();check(gate.rawCount()==0,"Extended close balances all raw input");
        gate=new HudMovementKeys(session);gate.activate(at);long last=at+HudMovementSession.START_WINDOW_NS-1;gate.authority(last,true);
        check(gate.event(1,0x57,last,true),"Initial down immediately before12s cutoff is admitted");
        gate=new HudMovementKeys(session);gate.activate(at);gate.activate(at+10_000_000_000L);long cutoff=at+HudMovementSession.START_WINDOW_NS;gate.authority(cutoff,true);
        check(!gate.event(1,0x57,cutoff,true) && !gate.started() && gate.lateStartsDenied()==1,"Exact12s cutoff denies first down and activation cannot renew it");
        gate.event(2,0x57,cutoff+1,true);check(gate.rawCount()==0,"Denied late down still permits its balancing release");
        gate.authority(cutoff+2,true);check(!gate.event(1,0x53,cutoff+2,true),"Neutral release does not reopen expired admission window");
        var shortGate=new HudMovementKeys();shortGate.authority(cutoff,true);
        check(shortGate.event(1,0x57,cutoff,true),"Short baseline retains original admission behavior");
    }
    private static void views()throws Exception{
        var parsed=parse(view(1,NOW));
        check(parsed.sequence()==1 && parsed.yaw()==0 && parsed.pitch()==0,"KCD negativeY converts Minecraft yaw0");
        check(parsed.fresh(NOW+300) && !parsed.fresh(NOW+301),"camera lease anchored to source timestamp");
        check(!parsed.fresh(NOW-51),"camera cannot run before allowed clock skew");
        var v=view(2,NOW);v.add("forward",vector(1,0,0));check(parse(v).yaw()==-90,"fresh camera updates yaw basis");
        for(String field:List.of("schema","source_kind","run","patch_run","patch_sha256","target_pid","target_start_filetime","seq","utc_ms","forward","up")){
            var bad=view(1,NOW);bad.remove(field);reject(()->parse(bad),"missing view "+field);
        }
        for(String field:List.of("run","patch_run","patch_sha256","target_start_filetime","source_kind")){
            var bad=view(1,NOW);bad.addProperty(field,"wrong");reject(()->parse(bad),"wrong view "+field);
        }
        var bad=view(1,NOW);bad.addProperty("extra",1);var extra=bad;reject(()->parse(extra),"unknown view field");
        reject(()->parse(view(0,NOW)),"zero sequence");reject(()->parse(view(1,NOW+51)),"future source time");
        bad=view(1,NOW);bad.add("forward",vector(0,0,0));var zero=bad;reject(()->parse(zero),"zero camera direction");
        bad=view(1,NOW);bad.add("up",vector(0,-1,0));var parallel=bad;reject(()->parse(parallel),"parallel forward up");
        String duplicate=view(1,NOW).toString().replace("\"schema\":1","\"schema\":1,\"schema\":1");
        reject(()->HudMovementView.parse(duplicate.getBytes(StandardCharsets.UTF_8),ID,PATCH,HASH,NOW),"duplicate JSON field");
        reject(()->HudMovementView.parse(new byte[4097],ID,PATCH,HASH,NOW),"oversize camera");
    }
    private static void waitFor(BooleanSupplier condition)throws Exception{
        long end=System.nanoTime()+3_000_000_000L;while(!condition.getAsBoolean()&&System.nanoTime()<end)Thread.sleep(10);
        check(condition.getAsBoolean(),"worker reached bounded expected state");
    }
    private static void reader()throws Exception{
        Path root=Files.createTempDirectory("minecome-view-test-").toRealPath(),file=root.resolve("view.json");
        try{
            var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH);
            try(reader){
                long utc=System.currentTimeMillis();Files.write(file,bytes(view(1,utc)));reader.start();
                waitFor(()->reader.current(System.currentTimeMillis(),System.nanoTime())!=null);
                var sample=reader.current(System.currentTimeMillis(),System.nanoTime());check(sample!=null,"initial live source accepted");
                waitFor(()->reader.current(System.currentTimeMillis(),System.nanoTime())==null);
                check(reader.failure()==null,"unchanged bytes simply expire without renewal");
                var replacement=view(1,System.currentTimeMillis());Path temp=root.resolve("next.json");Files.write(temp,bytes(replacement));
                Files.move(temp,file,StandardCopyOption.REPLACE_EXISTING);
                waitFor(()->reader.failure()!=null);
                check(reader.current(System.currentTimeMillis(),System.nanoTime())==null,"same sequence cannot renew source lease");
            }
            reject(()->new HudMovementViewReader(root.getParent().resolve("outside.json"),root,ID,PATCH,HASH),"camera parent outside evidence");
        }finally{try(var paths=Files.walk(root)){for(Path path:paths.sorted(Comparator.reverseOrder()).toList())Files.delete(path);}}
    }
    private static void readerRaces()throws Exception{
        Path root=Files.createTempDirectory("minecome-view-race-").toRealPath(),file=root.resolve("view.json");
        try{
            var mode=new AtomicInteger();var reads=new AtomicInteger();long utc=System.currentTimeMillis();
            byte[] original=bytes(view(1,utc));
            HudMovementViewReader.FileReader source=path->{
                reads.incrementAndGet();
                if(mode.get()==1)throw new FileSystemException(path.toString(),null,"The process cannot access the file because it is being used by another process");
                if(mode.get()==2)throw new NoSuchFileException(path.toString());
                return original;
            };
            try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,source)){
                mode.set(1);reader.start();
                waitFor(()->reads.get()>=2);
                check(reader.failure()==null && reader.current(utc,System.nanoTime())==null,"transient initial sharing denial grants no camera authority");
                mode.set(0);waitFor(()->reader.current(System.currentTimeMillis(),System.nanoTime())!=null);
                var first=reader.current(System.currentTimeMillis(),System.nanoTime());
                var firstDiagnostic=reader.inspect(utc,System.nanoTime());
                check(firstDiagnostic.current()==first && firstDiagnostic.diagnostics().get("sample_sequence").getAsLong()==1 &&
                        firstDiagnostic.diagnostics().get("source_utc_ms").getAsLong()==utc,"diagnostics bind exact immutable accepted source");
                final int beforeMissing=reads.get();mode.set(2);waitFor(()->reads.get()>=beforeMissing+2);
                var retained=reader.current(System.currentTimeMillis(),System.nanoTime());
                check(retained==first && reader.failure()==null,"atomic replacement absence retains exact original sample/deadline during bounded retry");
                check(reader.current(utc+301,System.nanoTime())==null,"read retry cannot renew an old capture timestamp");
                mode.set(0);final int recoveredAfter=reads.get();
                waitFor(()->reads.get()>recoveredAfter);
                check(reader.current(utc,first.deadlineNs()-1)==first,"same-byte recovery keeps exact original monotonic deadline");
                check(reader.current(utc,first.deadlineNs())==null,"same-byte recovery cannot extend original monotonic deadline");
                var expired=reader.inspect(utc+301,first.deadlineNs());
                check(expired.current()==null && !expired.diagnostics().get("active_sample_available").getAsBoolean() &&
                        expired.diagnostics().get("sample_deadline_ns").getAsLong()==first.deadlineNs() &&
                        expired.diagnostics().get("source_age_ms").getAsLong()==301,
                        "rejection diagnostic preserves original sequence UTC age and monotonic expiry");
                mode.set(1);waitFor(()->reader.failure()!=null);
                check(reader.failure().contains("retry deadline") && reader.current(utc,System.nanoTime())==null,"persistent sharing violation is terminal after bounded retry");
                var terminal=reader.diagnostics(System.currentTimeMillis(),System.nanoTime());
                check(terminal.get("sample_sequence").getAsLong()==1 && terminal.get("io_faults").getAsLong()>=3 &&
                        terminal.get("failure").getAsString().contains("retry deadline"),"terminal diagnostics survive sample cleanup");
            }
            var counter=new AtomicInteger();
            byte[] fresh=bytes(view(2,System.currentTimeMillis()));
            try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,path->{
                if(counter.incrementAndGet()==1)throw new FileSystemException(path.toString(),null,"sharing violation");
                return fresh;
            })){
                reader.start();waitFor(()->reader.current(System.currentTimeMillis(),System.nanoTime())!=null);
                check(reader.current(System.currentTimeMillis(),System.nanoTime()).view().sequence()==2,"fresh replacement is parsed normally after transient fault");
            }
            for(String content:List.of("{broken",view(1,utc).toString().replace(RUN,"d".repeat(32)))){
                var count=new AtomicInteger();
                try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,path->{count.incrementAndGet();return content.getBytes(StandardCharsets.UTF_8);})){
                    reader.start();waitFor(()->reader.failure()!=null);
                    check(count.get()==1 && !reader.failure().contains("retry deadline"),"malformed/schema identity data is fatal without I/O retry");
                }
            }
            var invalidReads=new AtomicInteger();
            try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,path->{invalidReads.incrementAndGet();throw new java.io.IOException("Invalid camera file");})){
                reader.start();waitFor(()->reader.failure()!=null);
                check(invalidReads.get()==1,"invalid file/reparse contract is not retried as sharing failure");
            }
            var release=new CountDownLatch(1);var blockingReads=new AtomicInteger();long startUtc=System.currentTimeMillis();
            byte[] firstBytes=bytes(view(1,startUtc));var latest=new AtomicReference<byte[]>(firstBytes);
            try(var reader=new HudMovementViewReader(file,root,ID,PATCH,HASH,path->{
                int count=blockingReads.incrementAndGet();
                if(count==2){
                    try{if(!release.await(1,TimeUnit.SECONDS))throw new java.io.IOException("test reader release deadline");}
                    catch(InterruptedException e){throw new java.io.IOException(e);}
                    latest.set(bytes(view(2,System.currentTimeMillis())));
                }
                return latest.get();
            })){
                reader.start();waitFor(()->blockingReads.get()>=2);
                var before=reader.diagnostics(startUtc,System.nanoTime());
                long deadline=before.get("sample_deadline_ns").getAsLong();
                var stalled=reader.inspect(startUtc+301,deadline);
                check(stalled.current()==null && stalled.diagnostics().get("stage").getAsString().equals("reading") &&
                        stalled.diagnostics().get("sample_sequence").getAsLong()==1,
                        "blocked worker cannot keep old camera authority; diagnostics distinguish read delay");
                release.countDown();
                waitFor(()->{var value=reader.current(System.currentTimeMillis(),System.nanoTime());return value!=null&&value.view().sequence()==2;});
                var recovered=reader.diagnostics(System.currentTimeMillis(),System.nanoTime());
                check(recovered.get("sample_sequence").getAsLong()==2 && recovered.get("read_attempts").getAsLong()>=2 &&
                        recovered.get("parse_publish_duration_ms").getAsDouble()>=0 &&
                        recovered.get("last_read_duration_ms").getAsDouble()>=0,"fresh recovery records observed read and publish timing");
            }finally{release.countDown();}
        }finally{Files.delete(root);}
    }
    private static void fixturePublication()throws Exception{
        Path root=Files.createTempDirectory("minecome-fixture-camera-"),target=root.resolve("view.json"),temp=root.resolve("view.tmp");
        try{
            String first=view(1,NOW).toString(),second=view(2,NOW+50).toString();
            Files.writeString(temp,first);check(HudFixtureCameraFiles.replace(temp,target),"Fixture initial publication succeeds");
            check(Files.readString(target).equals(first) && !Files.exists(temp),"Fixture initial atomic publication preserves bytes");
            Files.writeString(temp,second);
            if(System.getProperty("os.name","").startsWith("Windows")){
                try(var held=Files.newByteChannel(target,Set.of(StandardOpenOption.READ,com.sun.nio.file.ExtendedOpenOption.NOSHARE_DELETE))){
                    long began=System.nanoTime();check(!HudFixtureCameraFiles.replace(temp,target),"Shared camera target drops this fixture publication after bounded retry");
                    long elapsed=System.nanoTime()-began;
                    check(elapsed>=HudFixtureCameraFiles.RETRY_NS&&elapsed<1_000_000_000L,"Camera sharing retry retains its existing 100ms bound");
                    check(Files.readString(target).equals(first) && Files.readString(temp).equals(second),"Denied replacement does not renew old source or mutate queued timestamp");
                }
            }
            check(HudFixtureCameraFiles.replace(temp,target),"Publication resumes after the sharing lock is released");
            check(Files.readString(target).equals(second),"Replacement after sharing release preserves original queued sequence/time");
            reject(()->HudFixtureCameraFiles.replace(root.resolve("missing.tmp"),target),"Non-sharing I/O failures still abort fixture publication");
            if(System.getProperty("os.name","").startsWith("Windows")){
                long utc=System.currentTimeMillis();Files.writeString(temp,view(1,utc).toString());
                check(HudFixtureCameraFiles.replace(temp,target),"Freshness test starts with its original source sample");
                try(var reader=new HudMovementViewReader(target,root,ID,PATCH,HASH)){
                    reader.start();waitFor(()->reader.current(System.currentTimeMillis(),System.nanoTime())!=null);
                    var original=reader.current(System.currentTimeMillis(),System.nanoTime());
                    Files.writeString(temp,view(2,System.currentTimeMillis()).toString());
                    try(var held=Files.newByteChannel(target,Set.of(StandardOpenOption.READ,com.sun.nio.file.ExtendedOpenOption.NOSHARE_DELETE))){
                        check(!HudFixtureCameraFiles.replace(temp,target),"Blocked fixture update can be dropped without aborting the publisher");
                    }
                    Files.delete(temp);
                    check(reader.current(original.view().utcMs()+HudMovementView.MAX_AGE_MS+1,original.deadlineNs()+1)==null,
                            "Dropping a fixture sample cannot extend the previous sample's production freshness lease");
                    long recoveredUtc=System.currentTimeMillis();Files.writeString(temp,view(3,recoveredUtc).toString());
                    check(HudFixtureCameraFiles.replace(temp,target),"Next publication uses a newly generated source sequence after a drop");
                    waitFor(()->{var sample=reader.current(System.currentTimeMillis(),System.nanoTime());return sample!=null&&sample.view().sequence()==3;});
                    check(reader.current(System.currentTimeMillis(),System.nanoTime()).view().utcMs()==recoveredUtc,"Recovered sample keeps its own source timestamp");
                }
            }
        }finally{Files.deleteIfExists(temp);Files.deleteIfExists(target);Files.deleteIfExists(root);}
    }
    private static void fixtureAimingGeometry(){
        for(boolean wide:new boolean[]{false,true}){
            var seed=new dev.minecome.protocol.AimGeometry.Cell(wide?4:2,64,0);
            var point=HudWalkingAimedFixture.topAimPoint(wide,seed);
            check(point.x()==seed.x()+(wide?.25:.5)&&point.y()==65&&point.z()==.5,"Fixture top aim retains selected patch geometry");
            for(double z:new double[]{-.25,.5,1.0}){
                var eye=new dev.minecome.protocol.Protocol.Vec3(0,65.62,z);
                double x=point.x()-eye.x(),y=point.y()-eye.y(),dz=point.z()-eye.z(),length=Math.sqrt(x*x+y*y+dz*dz);
                var ray=new dev.minecome.protocol.AimGeometry.Ray(eye,new dev.minecome.protocol.Protocol.Vec3(x/length,y/length,dz/length),4.5);
                var hit=dev.minecome.protocol.AimGeometry.intersect(ray,seed.bounds());
                check(hit.isPresent()&&hit.get().face()==dev.minecome.protocol.AimGeometry.Face.UP&&hit.get().distance()<4.5,
                        "Reference top-face aim remains within unchanged reach after walking; real fixture still uses vanilla OUTLINE");
            }
        }
        var facingSeeds=List.of(new dev.minecome.protocol.AimGeometry.Cell(4,64,-1),new dev.minecome.protocol.AimGeometry.Cell(-5,64,-1),
                new dev.minecome.protocol.AimGeometry.Cell(-1,64,4),new dev.minecome.protocol.AimGeometry.Cell(-1,64,-5));
        var faces=List.of("WEST","EAST","NORTH","SOUTH");
        for(int i=0;i<facingSeeds.size();i++){
            var seed=facingSeeds.get(i);var point=HudWalkingAimedFixture.facingTopAimPoint(seed);
            check(HudWalkingAimedFixture.nearFace(seed).name().equals(faces.get(i)),"Facing fixture selects the origin-facing vertical surface");
            var eye=new dev.minecome.protocol.Protocol.Vec3(0,65.62,0);
            double x=point.x()-eye.x(),y=point.y()-eye.y(),z=point.z()-eye.z(),length=Math.sqrt(x*x+y*y+z*z);
            var ray=new dev.minecome.protocol.AimGeometry.Ray(eye,new dev.minecome.protocol.Protocol.Vec3(x/length,y/length,z/length),4.5);
            var hit=dev.minecome.protocol.AimGeometry.intersect(ray,seed.bounds());
            check(hit.isPresent()&&hit.get().face()==dev.minecome.protocol.AimGeometry.Face.UP&&hit.get().distance()<4.5,
                    "Facing fixture top stays inside unchanged reach for every perimeter direction");
        }
        var forwardPoint=HudWalkingAimedFixture.facingTopAimPoint(new dev.minecome.protocol.AimGeometry.Cell(-1,64,4));
        check(forwardPoint.x()==-.5&&forwardPoint.y()==65&&forwardPoint.z()==4.25,"Yaw-zero fixture aims at the nearer north edge of the forward seed top");
        var corridorSeed=new dev.minecome.protocol.AimGeometry.Cell(-1,64,-5);
        var corridorPoints=List.of(HudWalkingAimedFixture.corridorTopAimPoint(corridorSeed),HudWalkingAimedFixture.corridorSideAimPoint(corridorSeed));
        var corridorFaces=List.of(dev.minecome.protocol.AimGeometry.Face.UP,dev.minecome.protocol.AimGeometry.Face.EAST);
        for(double x:new double[]{.55,.72,.9})for(double feetY:new double[]{63.9,64.04,64.15})for(int action=0;action<2;action++){
            var eye=new dev.minecome.protocol.Protocol.Vec3(x,feetY+1.62,0);var point=corridorPoints.get(action);
            double dx=point.x()-eye.x(),dy=point.y()-eye.y(),dz=point.z()-eye.z(),distance=Math.sqrt(dx*dx+dy*dy+dz*dz);
            var ray=new dev.minecome.protocol.AimGeometry.Ray(eye,new dev.minecome.protocol.Protocol.Vec3(dx/distance,dy/distance,dz/distance),4.5);
            var hit=dev.minecome.protocol.AimGeometry.intersect(ray,corridorSeed.bounds());
            check(hit.isPresent()&&hit.get().face()==corridorFaces.get(action)&&hit.get().distance()<4.5,
                    "Corridor reference ray reaches its actual top/east face after crossing and returning; vanilla OUTLINE still decides in game");
        }
    }
    public static void main(String[] args)throws Exception{modes();wire();holds();extendedHolds();views();reader();readerRaces();fixturePublication();fixtureAimingGeometry();checks+=HudMovementTimingTests.run();checks+=dev.minecome.terrain.HudMovementBoundaryTests.run();System.out.println("HudPhysicalMovementTests: "+checks+" checks passed");}
}
