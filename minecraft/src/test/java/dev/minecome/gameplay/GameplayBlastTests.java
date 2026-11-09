package dev.minecome.gameplay;

import com.google.gson.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Pure native blast receipt and pinned vanilla exposure checks. */
final class GameplayBlastTests {
    private static int checks;
    private static final long NOW=1_800_000_000_000L;
    private static final HudInputProtocol.Identity ID=new HudInputProtocol.Identity("a".repeat(32),11,22,33,44,NOW+60000);
    private static final String WORLD="00000000-0000-0000-0000-000000000001";
    private static final GroundSurface SURFACE=new GroundSurface(){
        public String run(){return "b".repeat(32);}public String sourceKind(){return "fixture";}public String sha256(){return "c".repeat(64);}
        public double centerX(){return 120.5;}public double centerY(){return 2045.25;}public double centerZ(){return 56.75;}
        public List<GroundPatch.Point> points(){return List.of();}public List<GroundPatch.Slab> slabs(){return List.of();}public List<GroundPatch.Cell> cells(){return List.of();}
        public double heightAt(double x,double z){return 64;}public double groundForFeet(double x,double z,double r){return 64;}public boolean containsFeet(double x,double z,double r){return true;}public boolean wide(){return false;}
    };
    private static void check(boolean ok,String reason){checks++;if(!ok)throw new AssertionError(reason);}
    private static void reject(Runnable action,String reason){try{action.run();throw new AssertionError(reason);}catch(IllegalArgumentException expected){checks++;}}
    private static GameplayBlastProtocol.Reply parse(JsonObject value){return GameplayBlastProtocol.parse(value.toString(),ID,WORLD,SURFACE);}
    static int run(){
        double half=(double)(.6f/2f),height=(double)1.8f;
        var samples=GameplayBlastExposure.samples(-half,64,-half,half,64+height,half);
        check(samples.size()==45,"Pinned .6x1.8 float32 actor has45 exposure rays");
        check(samples.get(1).x()==samples.getFirst().x()&&samples.get(1).y()==64&&samples.get(1).z()>samples.getFirst().z(),"Vanilla innermost lattice axis is Z");
        check(samples.get(3).y()>64&&samples.get(3).z()==samples.getFirst().z(),"Vanilla middle lattice axis is Y");
        check(samples.get(15).x()>samples.getFirst().x()&&samples.get(15).y()==64,"Vanilla outer lattice axis is X");
        check(GameplayBlastExposure.combine(samples,"1".repeat(45),p->true)==1,"Unobstructed native and Minecraft rays preserve full exposure");
        var calls=new AtomicInteger();check(GameplayBlastExposure.combine(samples,"0".repeat(45),p->{calls.incrementAndGet();return true;})==0&&calls.get()==0,"Native scenery blocks every exposure ray without Minecraft override");
        check(GameplayBlastExposure.combine(samples,"1".repeat(45),p->false)==0,"Minecraft blocks still occlude native actor damage");
        check(GameplayBlastExposure.combine(samples,"1".repeat(15)+"0".repeat(30),p->true)==1f/3f,"Partial native cover retains exact sample weighting");
        for(String mask:List.of("1".repeat(44),"1".repeat(46),"1".repeat(44)+"x",""))reject(()->GameplayBlastExposure.combine(samples,mask,p->true),"Mask must match pinned lattice exactly");
        reject(()->GameplayBlastExposure.samples(0,0,0,4,8,4),"Excess lattice cannot silently truncate");
        reject(()->GameplayBlastExposure.samples(0,0,0,0,1,1),"Empty actor bounds rejected");
        reject(()->GameplayBlastExposure.samples(Double.NaN,0,0,1,1,1),"Nonfinite actor bounds rejected");

        var valid=reply();var parsed=parse(valid);check(parsed.prepareSeq()==3&&parsed.actors().size()==1&&parsed.actors().getFirst().exposure().length()==45,"Native preparation binds exact sequence, actor and exposure");
        try{parsed.actors().clear();throw new AssertionError("Mutable blast actors");}catch(UnsupportedOperationException expected){checks++;}
        for(String key:valid.keySet()){
            var changed=valid.deepCopy();changed.remove(key);reject(()->parse(changed),"Missing blast envelope field "+key);
            String duplicate=valid.toString().replaceFirst("\\{","{\""+key+"\":"+valid.get(key)+",");reject(()->GameplayBlastProtocol.parse(duplicate,ID,WORLD,SURFACE),"Duplicate blast field "+key);
        }
        for(String key:valid.getAsJsonObject("reply").keySet()){var changed=valid.deepCopy();changed.getAsJsonObject("reply").remove(key);reject(()->parse(changed),"Missing blast reply "+key);}
        for(String key:List.of("run","world_id","patch_run","patch_sha256","target_start_filetime")){var changed=valid.deepCopy();changed.addProperty(key,"foreign");reject(()->parse(changed),"Foreign blast identity "+key);}
        var wrongSeq=valid.deepCopy();wrongSeq.getAsJsonObject("reply").addProperty("prepare_seq",2);reject(()->parse(wrongSeq),"Prepare grant cannot name another request");
        var duplicateActor=valid.deepCopy();duplicateActor.getAsJsonObject("reply").getAsJsonArray("actors").add(duplicateActor.getAsJsonObject("reply").getAsJsonArray("actors").get(0).deepCopy());reject(()->parse(duplicateActor),"Duplicate generation cannot produce repeated blast damage");
        var dead=valid.deepCopy();dead.getAsJsonObject("reply").getAsJsonArray("actors").get(0).getAsJsonObject().addProperty("alive",false);reject(()->parse(dead),"Dead native actor cannot grant damage");
        var applied=valid.deepCopy();var body=applied.getAsJsonObject("reply");body.addProperty("operation","commit");body.addProperty("result","applied");body.add("actors",new JsonArray());
        var outcome=new JsonObject();outcome.addProperty("actor_token",1);outcome.addProperty("result","damaged");outcome.addProperty("reason","");outcome.addProperty("before",100);outcome.addProperty("after",0);body.getAsJsonArray("outcomes").add(outcome);
        check(parse(applied).outcomes().getFirst().after()==0,"Lethal native health clamp is a valid real receipt");
        var healing=applied.deepCopy();healing.getAsJsonObject("reply").getAsJsonArray("outcomes").get(0).getAsJsonObject().addProperty("after",101);reject(()->parse(healing),"Blast cannot report healing");
        var repeated=applied.deepCopy();repeated.getAsJsonObject("reply").getAsJsonArray("outcomes").add(outcome.deepCopy());reject(()->parse(repeated),"Repeated native damage receipt rejected");
        var missingHealth=applied.deepCopy();missingHealth.getAsJsonObject("reply").getAsJsonArray("outcomes").get(0).getAsJsonObject().add("before",JsonNull.INSTANCE);reject(()->parse(missingHealth),"Applied damage requires native before/after");
        var noTargets=applied.deepCopy();noTargets.getAsJsonObject("reply").add("outcomes",new JsonArray());check(parse(noTargets).outcomes().isEmpty(),"Chain blast may commit no targets after earlier native death");
        var request=new GameplayBlastProtocol.Request(4,NOW-500,"commit","d".repeat(32),"e".repeat(32),3,new GameplayCombatProtocol.Point(1,2,3),List.of(new GameplayBlastProtocol.Target(1,28)));
        var encoded=GameplayBlastProtocol.request(request,ID,WORLD,SURFACE);check(encoded.get("utc_ms").getAsLong()==NOW-500&&GameplayBlastProtocol.request(request,ID,WORLD,SURFACE).equals(encoded),"Publication retries preserve original source timestamp and payload");
        check(encoded.getAsJsonObject("request").getAsJsonArray("targets").get(0).getAsJsonObject().get("damage_fraction").getAsDouble()==1.4,"Actual vanilla TNT damage above20 is not capped before native health clamp");
        for(String bad:List.of("null","[]","{}",valid+"{}"," ".repeat(32769)))reject(()->GameplayBlastProtocol.parse(bad,ID,WORLD,SURFACE),"Malformed or oversized blast rejected");
        return checks;
    }
    private static JsonObject reply(){
        var j=GameplayCombatProtocol.identity(ID,WORLD,SURFACE,"minecome_gameplay_blasts_host_v1");j.addProperty("seq",3);j.addProperty("utc_ms",NOW);j.addProperty("request_utc_ms",NOW-50);
        var r=new JsonObject();r.addProperty("operation","prepare");r.addProperty("explosion","d".repeat(32));r.addProperty("owner","e".repeat(32));r.addProperty("prepare_seq",3);var center=new JsonObject();center.addProperty("x",1);center.addProperty("y",2);center.addProperty("z",3);r.add("center",center);r.addProperty("power",4);r.addProperty("result","prepared");r.addProperty("reason","");r.add("outcomes",new JsonArray());
        var actors=new JsonArray();var a=new JsonObject();a.addProperty("token",1);a.addProperty("x",5);a.addProperty("y",2);a.addProperty("z",3);a.addProperty("width",.6);a.addProperty("height",1.8);a.addProperty("health",100);a.addProperty("max_health",100);a.addProperty("alive",true);a.addProperty("exposure","1".repeat(45));actors.add(a);r.add("actors",actors);j.add("reply",r);return j;
    }
}
