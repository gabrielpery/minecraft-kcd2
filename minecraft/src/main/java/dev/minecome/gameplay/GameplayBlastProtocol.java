package dev.minecome.gameplay;

import com.google.gson.*;
import com.google.gson.stream.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.GroundSurface;
import java.io.*;
import java.util.*;
import static dev.minecome.gameplay.GameplayCombatProtocol.*;

/** Dedicated immutable blast prepare/commit, independent of current player eye and melee intent. */
public final class GameplayBlastProtocol {
    public record Target(int token,float damage){}
    public record Request(long seq,long utc,String operation,String explosion,String owner,long prepareSeq,Point center,List<Target> targets){public Request{targets=List.copyOf(targets);}}
    public record VisibleActor(Actor actor,String exposure){}
    public record Outcome(int token,String result,String reason,Double before,Double after){}
    public record Reply(long seq,long utc,long requestUtc,String operation,String explosion,String owner,long prepareSeq,Point center,String result,String reason,List<VisibleActor> actors,List<Outcome> outcomes){public Reply{actors=List.copyOf(actors);outcomes=List.copyOf(outcomes);}}
    private static final Set<String> ROOT=Set.of("schema","kind","run","world_id","target_pid","target_start_filetime","patch_run","patch_sha256","seq","utc_ms","request_utc_ms","reply");
    private GameplayBlastProtocol(){}
    public static JsonObject request(Request request,HudInputProtocol.Identity id,String world,GroundSurface surface){
        var j=identity(id,world,surface,"minecome_gameplay_blasts_guest_v1");j.addProperty("seq",request.seq());j.addProperty("utc_ms",request.utc());
        var r=new JsonObject();r.addProperty("operation",request.operation());r.addProperty("explosion",request.explosion());r.addProperty("owner",request.owner());r.addProperty("prepare_seq",request.prepareSeq());r.add("center",point(request.center()));r.addProperty("power",4);
        var targets=new JsonArray();for(var target:request.targets()){var t=new JsonObject();t.addProperty("actor_token",target.token());t.addProperty("damage_mc",target.damage());t.addProperty("damage_fraction",target.damage()/20d);targets.add(t);}r.add("targets",targets);j.add("request",r);return j;
    }
    public static Reply parse(String text,HudInputProtocol.Identity id,String world,GroundSurface surface){
        if(text==null||text.length()>32768)throw new IllegalArgumentException("Oversized blast reply");
        try(var reader=new JsonReader(new StringReader(text))){
            reader.setLenient(false);var j=element(reader,0,true).getAsJsonObject();if(reader.peek()!=JsonToken.END_DOCUMENT)throw new IOException("Trailing blast reply");keys(j,ROOT);
            if(integer(j,"schema",1,1)!=1||!string(j,"kind").equals("minecome_gameplay_blasts_host_v1")||!string(j,"run").equals(id.run())||!string(j,"world_id").equals(world)||integer(j,"target_pid",1,Integer.MAX_VALUE)!=id.targetPid()||!string(j,"target_start_filetime").equals(Long.toUnsignedString(id.targetStart()))||!string(j,"patch_run").equals(surface.run())||!string(j,"patch_sha256").equals(surface.sha256()))throw new IOException("Blast reply identity differs");
            long seq=integer(j,"seq",1,10_000_000),utc=integer(j,"utc_ms",1,Long.MAX_VALUE),requestUtc=integer(j,"request_utc_ms",1,Long.MAX_VALUE);
            var r=j.getAsJsonObject("reply");keys(r,Set.of("operation","explosion","owner","prepare_seq","center","power","result","reason","actors","outcomes"));
            String operation=string(r,"operation"),explosion=string(r,"explosion"),owner=string(r,"owner"),result=string(r,"result"),reason=string(r,"reason");
            if(!Set.of("prepare","commit").contains(operation)||!explosion.matches("[0-9a-f]{32}")||!owner.matches("[0-9a-f]{32}")||reason.length()>128)throw new IOException("Blast reply operation/source differs");
            long prepareSeq=integer(r,"prepare_seq",0,10_000_000);if(number(r,"power",4,4)!=4)throw new IOException("Blast power differs");var center=point(r.getAsJsonObject("center"));
            var actors=new ArrayList<VisibleActor>();var tokens=new HashSet<Integer>();
            for(var value:array(r,"actors",8)){
                var a=value.getAsJsonObject();keys(a,Set.of("token","x","y","z","width","height","health","max_health","alive","exposure"));
                int token=(int)integer(a,"token",1,256);if(!tokens.add(token))throw new IOException("Duplicate blast actor");
                double max=number(a,"max_health",.001,1_000_000),health=number(a,"health",.001,max);if(!bool(a,"alive"))throw new IOException("Dead blast actor grant");
                var actor=new Actor(token,number(a,"x",-100000,100000),number(a,"y",-100000,100000),number(a,"z",-10000,10000),(float)number(a,"width",.05,4),(float)number(a,"height",.05,8),health,max,true);
                String mask=string(a,"exposure");if(mask.isEmpty()||mask.length()>128||!mask.matches("[01]+"))throw new IOException("Blast exposure bits invalid");actors.add(new VisibleActor(actor,mask));
            }
            var outcomes=new ArrayList<Outcome>();tokens.clear();
            for(var value:array(r,"outcomes",8)){
                var o=value.getAsJsonObject();keys(o,Set.of("actor_token","result","reason","before","after"));int token=(int)integer(o,"actor_token",1,256);if(!tokens.add(token))throw new IOException("Duplicate blast outcome");
                String status=string(o,"result"),why=string(o,"reason");if(!Set.of("damaged","no_damage","rejected").contains(status)||why.length()>128)throw new IOException("Blast outcome result differs");
                Double before=o.get("before").isJsonNull()?null:number(o,"before",0,1_000_000),after=o.get("after").isJsonNull()?null:number(o,"after",0,1_000_000);
                if(!status.equals("rejected")&&(before==null||after==null||after>before+.01))throw new IOException("Blast outcome health differs");outcomes.add(new Outcome(token,status,why,before,after));
            }
            if(result.equals("rejected")){if(!actors.isEmpty()||!outcomes.isEmpty())throw new IOException("Rejected blast has effects");}
            else if(operation.equals("prepare")){if(!result.equals("prepared")||prepareSeq!=seq||!outcomes.isEmpty())throw new IOException("Blast preparation differs");}
            else if(!result.equals("applied")||prepareSeq<1||!actors.isEmpty())throw new IOException("Blast commit differs");
            return new Reply(seq,utc,requestUtc,operation,explosion,owner,prepareSeq,center,result,reason,actors,outcomes);
        }catch(IOException|RuntimeException e){throw new IllegalArgumentException("Invalid blast reply",e);}
    }
    private static Point point(JsonObject p)throws IOException{keys(p,Set.of("x","y","z"));return new Point(number(p,"x",-100000,100000),number(p,"y",-100000,100000),number(p,"z",-100000,100000));}
    private static JsonObject point(Point p){var j=new JsonObject();j.addProperty("x",p.x());j.addProperty("y",p.y());j.addProperty("z",p.z());return j;}
}
