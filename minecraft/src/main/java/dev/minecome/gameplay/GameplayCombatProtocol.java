package dev.minecome.gameplay;

import com.google.gson.*;
import com.google.gson.internal.LazilyParsedNumber;
import com.google.gson.stream.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.GroundSurface;
import dev.minecome.terrain.GroundPatch;
import java.io.*;
import java.util.*;

/** Bounded, duplicate-safe combat snapshots. No game calls or mutable entities. */
public final class GameplayCombatProtocol {
    public record Point(double x,double y,double z){}
    public record Actor(int token,double x,double y,double z,float width,float height,double health,double maxHealth,boolean alive){}
    public record Hurt(long seq,int attackerToken,float damage){}
    public record Snapshot(long seq,long utc,List<Actor> actors,List<Hurt> hurts,long hitAck){
        public boolean fresh(long now){return now>=utc-50&&now-utc<=500;}
    }
    private static final Set<String> ROOT=Set.of("schema","kind","run","world_id","target_pid","target_start_filetime","patch_run","patch_sha256","seq","utc_ms","actors","hurts","hit_ack");
    private GameplayCombatProtocol(){}
    public static Point toMinecraft(Point p,GroundSurface s){return new Point(p.x()-s.centerX(),p.z()-s.centerZ()+GroundPatch.ANCHOR_Y,s.centerY()-p.y());}
    public static Point toHost(Point p,GroundSurface s){return new Point(s.centerX()+p.x(),s.centerY()-p.z(),s.centerZ()+p.y()-GroundPatch.ANCHOR_Y);}
    public static Snapshot parse(String text,HudInputProtocol.Identity identity,String world,GroundSurface surface){
        if(text==null||text.length()>131072)throw new IllegalArgumentException("Oversized combat snapshot");
        try(var reader=new JsonReader(new StringReader(text))){
            reader.setLenient(false);var root=element(reader,0).getAsJsonObject();if(reader.peek()!=JsonToken.END_DOCUMENT)throw new IOException("Trailing combat document");keys(root,ROOT);
            if(integer(root,"schema",1,1)!=1||!string(root,"kind").equals("minecome_gameplay_combat_host_v1")||!string(root,"run").equals(identity.run())||
                    !string(root,"world_id").equals(world)||integer(root,"target_pid",1,Integer.MAX_VALUE)!=identity.targetPid()||
                    !string(root,"target_start_filetime").equals(Long.toUnsignedString(identity.targetStart()))||!string(root,"patch_run").equals(surface.run())||!string(root,"patch_sha256").equals(surface.sha256()))throw new IOException("Combat snapshot identity differs");
            long seq=integer(root,"seq",1,10_000_000),utc=integer(root,"utc_ms",1,Long.MAX_VALUE),ack=integer(root,"hit_ack",0,10_000_000);
            var actors=new ArrayList<Actor>();var tokens=new HashSet<Integer>();var list=array(root,"actors",32);
            for(var value:list){var a=value.getAsJsonObject();keys(a,Set.of("token","x","y","z","width","height","health","max_health","alive"));
                int token=(int)integer(a,"token",1,256);if(!tokens.add(token))throw new IOException("Duplicate native actor");
                double x=number(a,"x",-100000,100000),y=number(a,"y",-100000,100000),z=number(a,"z",-10000,10000);
                float width=(float)number(a,"width",.05,4),height=(float)number(a,"height",.05,8);
                double maximum=number(a,"max_health",.001,1000000),health=number(a,"health",0,maximum);boolean alive=bool(a,"alive");
                if(alive&&health<=0)throw new IOException("Native live actor has no health");
                actors.add(new Actor(token,x,y,z,width,height,health,maximum,alive));
            }
            var hurts=new ArrayList<Hurt>();long previous=0;
            for(var value:array(root,"hurts",32)){var h=value.getAsJsonObject();keys(h,Set.of("seq","attacker_token","damage","kind"));long number=integer(h,"seq",1,10_000_000);
                if(number<=previous||!string(h,"kind").equals("melee"))throw new IOException("Invalid combat damage order/type");previous=number;
                hurts.add(new Hurt(number,(int)integer(h,"attacker_token",1,256),(float)number(h,"damage",.001,1000)));
            }
            return new Snapshot(seq,utc,List.copyOf(actors),List.copyOf(hurts),ack);
        }catch(IOException|RuntimeException e){throw new IllegalArgumentException("Invalid combat snapshot",e);}
    }
    public static JsonObject identity(HudInputProtocol.Identity id,String world,GroundSurface surface,String kind){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind",kind);j.addProperty("run",id.run());j.addProperty("world_id",world);j.addProperty("target_pid",id.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(id.targetStart()));j.addProperty("patch_run",surface.run());j.addProperty("patch_sha256",surface.sha256());return j;
    }
    static JsonElement element(JsonReader r,int depth)throws IOException{return element(r,depth,false);}
    static JsonElement element(JsonReader r,int depth,boolean allowNull)throws IOException{
        if(depth>4)throw new IOException("Combat nesting limit");
        return switch(r.peek()){
            case BEGIN_OBJECT->{r.beginObject();var j=new JsonObject();while(r.hasNext()){var key=r.nextName();if(key.length()>64||j.has(key)||j.size()>=32)throw new IOException("Duplicate/oversized combat object");j.add(key,element(r,depth+1,allowNull));}r.endObject();yield j;}
            case BEGIN_ARRAY->{r.beginArray();var a=new JsonArray();while(r.hasNext()){if(a.size()>=32)throw new IOException("Oversized combat array");a.add(element(r,depth+1,allowNull));}r.endArray();yield a;}
            case STRING->{var s=r.nextString();if(s.length()>128)throw new IOException("Oversized combat string");yield new JsonPrimitive(s);}
            case NUMBER->{var s=r.nextString();if(s.length()>64)throw new IOException("Oversized combat number");yield new JsonPrimitive(new LazilyParsedNumber(s));}
            case BOOLEAN->new JsonPrimitive(r.nextBoolean());
            case NULL->{if(!allowNull)throw new IOException("Unsupported combat null");r.nextNull();yield JsonNull.INSTANCE;}
            default->throw new IOException("Unsupported combat value");
        };
    }
    static void keys(JsonObject j,Set<String> names)throws IOException{if(!j.keySet().equals(names))throw new IOException("Combat fields differ");}
    static String string(JsonObject j,String n)throws IOException{var v=j.get(n);if(!v.isJsonPrimitive()||!v.getAsJsonPrimitive().isString())throw new IOException("Combat string required");return v.getAsString();}
    static long integer(JsonObject j,String n,long min,long max)throws IOException{var v=j.get(n);if(!v.isJsonPrimitive()||!v.getAsJsonPrimitive().isNumber()||!v.getAsString().matches("[0-9]+"))throw new IOException("Exact combat integer required");long x=Long.parseLong(v.getAsString());if(x<min||x>max)throw new IOException("Combat integer bounds");return x;}
    static double number(JsonObject j,String n,double min,double max)throws IOException{var v=j.get(n);if(!v.isJsonPrimitive()||!v.getAsJsonPrimitive().isNumber())throw new IOException("Combat number required");double x=v.getAsDouble();if(!Double.isFinite(x)||x<min||x>max)throw new IOException("Combat number bounds");return x;}
    static boolean bool(JsonObject j,String n)throws IOException{var v=j.get(n);if(!v.isJsonPrimitive()||!v.getAsJsonPrimitive().isBoolean())throw new IOException("Combat boolean required");return v.getAsBoolean();}
    static JsonArray array(JsonObject j,String n,int maximum)throws IOException{var v=j.get(n);if(!v.isJsonArray()||v.getAsJsonArray().size()>maximum)throw new IOException("Combat array required");return v.getAsJsonArray();}
}
