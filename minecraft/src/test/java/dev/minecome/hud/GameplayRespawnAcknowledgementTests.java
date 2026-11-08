package dev.minecome.hud;

import com.google.gson.*;
import java.util.List;
import dev.minecome.hud.GameplayRespawnAcknowledgement.Action;
import dev.minecome.hud.GameplayRespawnAcknowledgement.Point;

/** Malformed, stale, foreign and replayed receipts never authorize movement. */
public final class GameplayRespawnAcknowledgementTests {
    private static int checks;
    private static final long NOW=1_800_000_000_000L;
    private static final HudInputProtocol.Identity ID=new HudInputProtocol.Identity("a".repeat(32),11,22,33,Long.MAX_VALUE,NOW+60_000);
    private static final String WORLD="b".repeat(32),PATCH="c".repeat(32),HASH="d".repeat(64);
    private static final Point FROM=new Point(10.5,20.25,30.75),TARGET=new Point(0,0,64.05);
    private static void check(boolean value,String description){checks++;if(!value)throw new AssertionError(description);}
    private static Action parse(String text,long epoch,long dead,long respawn,long now){return GameplayRespawnAcknowledgement.parse(text,ID,WORLD,PATCH,HASH,epoch,dead,respawn,FROM,TARGET,now);}
    private static void reject(Runnable action,String description){try{action.run();throw new AssertionError(description);}catch(IllegalArgumentException expected){checks++;}}
    private static void reject(JsonObject value,String description){reject(()->parse(value.toString(),2,0,0,NOW),description);}
    public static void main(String[] args){
        var dead=receipt("dead",2,NOW);var respawn=receipt("respawn",2,NOW);
        check(parse(dead.toString(),2,0,0,NOW)==Action.DEAD,"Current death accepted");
        check(parse(respawn.toString(),2,2,0,NOW)==Action.RESPAWN,"Current ordered respawn accepted");
        reject(()->parse(respawn.toString(),2,0,0,NOW),"Respawn cannot precede death ack");
        check(parse(dead.toString(),2,2,0,NOW+10_000)==Action.IGNORE,"Consumed death can remain beyond freshness interval");
        check(parse(respawn.toString(),2,2,2,NOW+10_000)==Action.IGNORE,"Consumed respawn cannot run twice");
        check(parse(receipt("dead",1,NOW-60_000).toString(),2,1,1,NOW)==Action.IGNORE,"Prior epoch cannot authorize current death");
        check(parse(receipt("respawn",1,NOW-60_000).toString(),2,1,1,NOW)==Action.IGNORE,"Prior completed relocation cannot authorize current respawn");
        reject(()->parse(receipt("dead",3,NOW).toString(),2,0,0,NOW),"Future epoch rejected");
        reject(()->parse(receipt("dead",0,NOW).toString(),2,0,0,NOW),"Zero epoch rejected");
        for(long utc:new long[]{NOW-2000,NOW+50})check(parse(receipt("dead",2,utc).toString(),2,0,0,NOW)==Action.DEAD,"Inclusive source-time boundary accepted");
        for(long utc:new long[]{0,NOW-2001,NOW+51,Long.MAX_VALUE})reject(()->parse(receipt("dead",2,utc).toString(),2,0,0,NOW),"Stale/zero/future time rejected");
        for(String key:List.of("kind","run","world_id","target_start_filetime","patch_run","patch_sha256","lifecycle")){
            var altered=dead.deepCopy();altered.addProperty(key,"foreign");reject(altered,"Foreign identity/phase rejected: "+key);
        }
        for(String key:List.of("schema","target_pid")){var altered=dead.deepCopy();altered.addProperty(key,999);reject(altered,"Foreign integer identity rejected");}
        for(String key:dead.keySet()){
            var altered=dead.deepCopy();altered.remove(key);reject(altered,"Missing field rejected: "+key);
            altered=dead.deepCopy();altered.add(key,JsonNull.INSTANCE);reject(altered,"Null field rejected: "+key);
            String duplicate=dead.toString().replaceFirst("\\{","{\""+key+"\":"+dead.get(key)+",");reject(()->parse(duplicate,2,0,0,NOW),"Duplicate field rejected: "+key);
        }
        var unknown=dead.deepCopy();unknown.addProperty("extra",true);reject(unknown,"Unknown top-level field rejected");
        for(String key:List.of("schema","target_pid","respawn_epoch","utc_ms"))for(String raw:List.of("\"2\"","2.0","2e0","-1","true","[]","9223372036854775808")){
            String altered=dead.toString().replace("\""+key+"\":"+dead.get(key),"\""+key+"\":"+raw);reject(()->parse(altered,2,0,0,NOW),"Invalid integer syntax/type/overflow: "+key);
        }
        for(String key:List.of("kind","run","world_id","target_start_filetime","patch_run","patch_sha256","lifecycle"))for(JsonElement value:List.of(new JsonPrimitive(1),new JsonPrimitive(true),new JsonArray(),new JsonObject())){
            var altered=dead.deepCopy();altered.add(key,value);reject(altered,"Non-string receipt identity rejected");
        }
        for(String point:List.of("from","target")){
            for(String axis:List.of("x","y","z")){
                var altered=dead.deepCopy();altered.getAsJsonObject(point).remove(axis);reject(altered,"Incomplete coordinate rejected");
                altered=dead.deepCopy();altered.getAsJsonObject(point).addProperty(axis,"0");reject(altered,"String coordinate rejected");
                altered=dead.deepCopy();altered.getAsJsonObject(point).addProperty(axis,999.0);reject(altered,"Changed coordinate rejected");
                String duplicate=dead.toString().replace("\""+point+"\":{","\""+point+"\":{\""+axis+"\":0,");reject(()->parse(duplicate,2,0,0,NOW),"Duplicate nested coordinate rejected");
            }
            var altered=dead.deepCopy();altered.getAsJsonObject(point).addProperty("w",1);reject(altered,"Unknown coordinate rejected");
            for(String value:List.of("[]","null","0","{\"x\":1e999,\"y\":0,\"z\":0}","{\"x\":NaN,\"y\":0,\"z\":0}","{\"x\":true,\"y\":0,\"z\":0}")){
                String raw=dead.toString().replace("\""+point+"\":"+dead.get(point),"\""+point+"\":"+value);reject(()->parse(raw,2,0,0,NOW),"Malformed coordinate object rejected");
            }
        }
        var shifted=respawn.deepCopy();shifted.add("target",point(FROM));reject(()->parse(shifted.toString(),2,2,0,NOW),"Death position is not a respawn acknowledgment");
        var changedConsumed=dead.deepCopy();changedConsumed.getAsJsonObject("from").addProperty("x",999);reject(()->parse(changedConsumed.toString(),2,2,0,NOW),"Consumed current receipt cannot change origin");
        for(String malformed:List.of("","[]","null",dead+"{}",dead.toString().substring(1)," ".repeat(4097),"/*comment*/"+dead))reject(()->parse(malformed,2,0,0,NOW),"Malformed/bounded document rejected");
        reject(()->GameplayRespawnAcknowledgement.parse(dead.toString(),ID,WORLD,PATCH,HASH,2,0,0,null,TARGET,NOW),"Missing expected origin rejected");
        reject(()->GameplayRespawnAcknowledgement.parse(respawn.toString(),ID,WORLD,PATCH,HASH,2,2,0,FROM,null,NOW),"Missing expected target rejected");
        reject(()->parse(dead.toString(),0,0,0,NOW),"No outstanding epoch rejected");
        reject(()->parse(dead.toString(),2,0,2,NOW),"Invalid acknowledgment state rejected");
        System.out.println("GameplayRespawnAcknowledgementTests: "+checks+" checks passed; no games");
    }
    private static JsonObject receipt(String lifecycle,long epoch,long utc){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_respawn_ack_v1");j.addProperty("run",ID.run());j.addProperty("world_id",WORLD);j.addProperty("target_pid",ID.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(ID.targetStart()));j.addProperty("patch_run",PATCH);j.addProperty("patch_sha256",HASH);j.addProperty("lifecycle",lifecycle);j.addProperty("respawn_epoch",epoch);j.add("from",point(FROM));j.add("target",point(lifecycle.equals("dead")?FROM:TARGET));j.addProperty("utc_ms",utc);return j;
    }
    private static JsonObject point(Point p){var j=new JsonObject();j.addProperty("x",p.x());j.addProperty("y",p.y());j.addProperty("z",p.z());return j;}
}
