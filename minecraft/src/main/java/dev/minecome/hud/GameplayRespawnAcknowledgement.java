package dev.minecome.hud;

import com.google.gson.stream.*;
import java.io.*;
import java.util.*;

/** Pure, duplicate-safe admission of native death/respawn receipts. */
final class GameplayRespawnAcknowledgement {
    enum Action { IGNORE, DEAD, RESPAWN }
    record Point(double x,double y,double z){
        Point {if(!Double.isFinite(x)||!Double.isFinite(y)||!Double.isFinite(z))throw new IllegalArgumentException("Nonfinite respawn point");}
    }
    private static final Set<String> KEYS=Set.of("schema","kind","run","world_id","target_pid","target_start_filetime","patch_run","patch_sha256","lifecycle","respawn_epoch","from","target","utc_ms");
    private static final Set<String> NUMBERS=Set.of("schema","target_pid","respawn_epoch","utc_ms");
    private GameplayRespawnAcknowledgement(){}

    static Action parse(String text,HudInputProtocol.Identity identity,String world,String patchRun,String patchHash,
                        long epoch,long deathAckEpoch,long respawnAckEpoch,Point from,Point target,long now){
        if(text==null||text.length()>4096)throw new IllegalArgumentException("Respawn acknowledgment oversized/missing");
        if(epoch<=0||now<=0||deathAckEpoch<0||deathAckEpoch>epoch||respawnAckEpoch<0||respawnAckEpoch>deathAckEpoch)throw new IllegalArgumentException("Invalid respawn acknowledgment context");
        try(var reader=new JsonReader(new StringReader(text))){
            reader.setLenient(false);reader.beginObject();var values=new HashMap<String,Object>();
            while(reader.hasNext()){
                String key=reader.nextName();if(values.containsKey(key)||!KEYS.contains(key))throw new IOException("Duplicate/unknown respawn acknowledgment field");
                Object value;
                if(key.equals("from")||key.equals("target"))value=point(reader);
                else if(NUMBERS.contains(key)){
                    if(reader.peek()!=JsonToken.NUMBER)throw new IOException("Respawn integer required");
                    String raw=reader.nextString();if(!raw.matches("[0-9]+"))throw new IOException("Exact nonnegative respawn integer required");value=Long.parseLong(raw);
                }else{
                    if(reader.peek()!=JsonToken.STRING)throw new IOException("Respawn string required");value=reader.nextString();
                }
                values.put(key,value);
            }
            reader.endObject();if(reader.peek()!=JsonToken.END_DOCUMENT||!values.keySet().equals(KEYS))throw new IOException("Incomplete respawn acknowledgment");
            if((long)values.get("schema")!=1||!values.get("kind").equals("minecome_gameplay_respawn_ack_v1")||!values.get("run").equals(identity.run())||
                !values.get("world_id").equals(world)||(long)values.get("target_pid")!=identity.targetPid()||!values.get("target_start_filetime").equals(Long.toUnsignedString(identity.targetStart()))||
                !values.get("patch_run").equals(patchRun)||!values.get("patch_sha256").equals(patchHash))throw new IOException("Respawn acknowledgment identity differs");
            String phase=(String)values.get("lifecycle");if(!phase.equals("dead")&&!phase.equals("respawn"))throw new IOException("Unknown respawn lifecycle");
            long received=(long)values.get("respawn_epoch"),utc=(long)values.get("utc_ms");
            if(received<=0||utc<=0)throw new IOException("Respawn epoch/time must be positive");
            // Native atomic publication leaves the previous valid receipt in place
            // until it has observed the next transition. It cannot authorize input.
            if(received<epoch)return Action.IGNORE;
            if(received!=epoch)throw new IOException("Unexpected future respawn epoch");
            if(!matches((Point)values.get("from"),from))throw new IOException("Respawn acknowledgment origin differs");
            if(!matches((Point)values.get("target"),phase.equals("dead")?from:target))throw new IOException("Respawn acknowledgment target differs");
            if(phase.equals("respawn")&&deathAckEpoch!=epoch)throw new IOException("Respawn acknowledgment preceded death acknowledgment");
            // Re-reading an already consumed receipt is harmless; its timestamp
            // expires without invalidating a completed handshake.
            if(phase.equals("dead")&&deathAckEpoch==epoch||phase.equals("respawn")&&respawnAckEpoch==epoch)return Action.IGNORE;
            if(utc-now>50||now-utc>2000)throw new IOException("Respawn acknowledgment expired");
            return phase.equals("dead")?Action.DEAD:Action.RESPAWN;
        }catch(IOException|RuntimeException e){throw new IllegalArgumentException("Invalid respawn acknowledgment",e);}
    }
    private static Point point(JsonReader reader)throws IOException{
        reader.beginObject();var values=new HashMap<String,Double>();
        while(reader.hasNext()){
            String key=reader.nextName();if(!Set.of("x","y","z").contains(key)||values.containsKey(key)||reader.peek()!=JsonToken.NUMBER)throw new IOException("Invalid/duplicate respawn coordinate");
            double value=Double.parseDouble(reader.nextString());if(!Double.isFinite(value))throw new IOException("Nonfinite respawn coordinate");values.put(key,value);
        }
        reader.endObject();if(values.size()!=3)throw new IOException("Incomplete respawn point");return new Point(values.get("x"),values.get("y"),values.get("z"));
    }
    private static boolean matches(Point actual,Point expected){
        if(expected==null)return false;double x=actual.x()-expected.x(),y=actual.y()-expected.y(),z=actual.z()-expected.z();return x*x+y*y+z*z<1e-8;
    }
}
