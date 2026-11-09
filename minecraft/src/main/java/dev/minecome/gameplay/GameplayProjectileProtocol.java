package dev.minecome.gameplay;

import com.google.gson.*;
import com.google.gson.stream.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.GroundSurface;
import java.io.*;
import java.util.Set;
import static dev.minecome.gameplay.GameplayCombatProtocol.*;

/** Immutable one-request/one-receipt trajectory transport, separate from eye-based melee. */
public final class GameplayProjectileProtocol {
    public record Request(long seq,long utc,String operation,String projectile,int segment,Point from,Point to,int token,float damage){}
    public record Reply(long seq,long utc,long requestUtc,String operation,String projectile,int segment,String result,String reason,
                        int token,Point contact,Point normal,Actor actor,Double before,Double after){}
    private static final Set<String> ROOT=Set.of("schema","kind","run","world_id","target_pid","target_start_filetime","patch_run","patch_sha256","seq","utc_ms","request_utc_ms","reply");
    private static final Set<String> REPLY=Set.of("operation","projectile","segment","result","reason","actor_token","contact","normal","actor","before","after");
    private GameplayProjectileProtocol(){}
    public static JsonObject request(Request request,HudInputProtocol.Identity id,String world,GroundSurface surface){
        var j=identity(id,world,surface,"minecome_gameplay_projectiles_guest_v1");j.addProperty("seq",request.seq());j.addProperty("utc_ms",request.utc());
        var r=new JsonObject();r.addProperty("operation",request.operation());r.addProperty("projectile",request.projectile());r.addProperty("segment",request.segment());
        r.add("from",point(request.from()));r.add("to",point(request.to()));r.addProperty("actor_token",request.token());r.addProperty("damage_mc",request.damage());r.addProperty("damage_fraction",request.damage()/20d);j.add("request",r);return j;
    }
    public static Reply parse(String text,HudInputProtocol.Identity id,String world,GroundSurface surface){
        if(text==null||text.length()>8192)throw new IllegalArgumentException("Oversized projectile reply");
        try(var reader=new JsonReader(new StringReader(text))){
            reader.setLenient(false);var j=element(reader,0,true).getAsJsonObject();if(reader.peek()!=JsonToken.END_DOCUMENT)throw new IOException("Trailing projectile reply");keys(j,ROOT);
            if(integer(j,"schema",1,1)!=1||!string(j,"kind").equals("minecome_gameplay_projectiles_host_v1")||!string(j,"run").equals(id.run())||!string(j,"world_id").equals(world)||
                integer(j,"target_pid",1,Integer.MAX_VALUE)!=id.targetPid()||!string(j,"target_start_filetime").equals(Long.toUnsignedString(id.targetStart()))||
                !string(j,"patch_run").equals(surface.run())||!string(j,"patch_sha256").equals(surface.sha256()))throw new IOException("Projectile reply identity differs");
            long seq=integer(j,"seq",1,10_000_000),utc=integer(j,"utc_ms",1,Long.MAX_VALUE),requestUtc=integer(j,"request_utc_ms",1,Long.MAX_VALUE);
            var r=j.getAsJsonObject("reply");keys(r,REPLY);String operation=string(r,"operation"),projectile=string(r,"projectile"),result=string(r,"result"),reason=string(r,"reason");
            if(!Set.of("trace","impact").contains(operation)||!projectile.matches("[0-9a-f]{32}")||reason.length()>128)throw new IOException("Projectile reply operation/identity differs");
            int segment=(int)integer(r,"segment",1,4096),token=(int)integer(r,"actor_token",0,256);Point contact=point(r.getAsJsonObject("contact")),normal=point(r.getAsJsonObject("normal"));
            double normalSquared=normal.x()*normal.x()+normal.y()*normal.y()+normal.z()*normal.z();if(normalSquared>1.01)throw new IOException("Projectile normal bounds");
            Actor actor=null;
            if(!r.get("actor").isJsonNull()){
                var a=r.getAsJsonObject("actor");keys(a,Set.of("token","x","y","z","width","height","health","max_health","alive"));
                int actorToken=(int)integer(a,"token",1,256);double maximum=number(a,"max_health",.001,1_000_000),health=number(a,"health",0,maximum);boolean alive=bool(a,"alive");
                if(actorToken!=token||alive&&health<=0)throw new IOException("Projectile actor identity/health differs");
                actor=new Actor(actorToken,number(a,"x",-100000,100000),number(a,"y",-100000,100000),number(a,"z",-10000,10000),
                    (float)number(a,"width",.05,4),(float)number(a,"height",.05,8),health,maximum,alive);
            }
            Double before=r.get("before").isJsonNull()?null:number(r,"before",0,1_000_000),after=r.get("after").isJsonNull()?null:number(r,"after",0,1_000_000);
            if(operation.equals("trace")){
                if(!Set.of("clear","scenery","actor","rejected").contains(result)||before!=null||after!=null||result.equals("actor")&&(actor==null||!actor.alive())||
                    (result.equals("clear")||result.equals("scenery"))&&(token!=0||actor!=null)||result.equals("scenery")&&normalSquared<.9)throw new IOException("Projectile trace result differs");
            }else if(!Set.of("damaged","no_damage","rejected").contains(result)||(!result.equals("rejected")&&(token==0||before==null||after==null||after>before+.01)))throw new IOException("Projectile impact result differs");
            return new Reply(seq,utc,requestUtc,operation,projectile,segment,result,reason,token,contact,normal,actor,before,after);
        }catch(IOException|RuntimeException e){throw new IllegalArgumentException("Invalid projectile reply",e);}
    }
    private static Point point(JsonObject j)throws IOException{keys(j,Set.of("x","y","z"));return new Point(number(j,"x",-100000,100000),number(j,"y",-100000,100000),number(j,"z",-100000,100000));}
    private static JsonObject point(Point point){var j=new JsonObject();j.addProperty("x",point.x());j.addProperty("y",point.y());j.addProperty("z",point.z());return j;}
}
