package dev.minecome.hud;

import com.google.gson.*;
import com.google.gson.stream.*;
import java.io.*;
import java.math.BigDecimal;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.util.Set;

/** Bounded original-capture camera snapshots; no Minecraft/host calls. */
public record HudMovementView(long sequence,long utcMs,float yaw,float pitch) {
    public static final int MAX_BYTES=4096;
    public static final long MAX_AGE_MS=300;
    private static final Set<String> KEYS=Set.of("schema","source_kind","run","patch_run","patch_sha256",
            "target_pid","target_start_filetime","seq","utc_ms","forward","up");
    public static HudMovementView parse(byte[] bytes,HudInputProtocol.Identity id,String patchRun,String patchHash,long now) throws IOException {
        return parse(bytes,id,patchRun,patchHash,now,false);
    }
    public static HudMovementView parse(byte[] bytes,HudInputProtocol.Identity id,String patchRun,String patchHash,long now,boolean fixture) throws IOException {
        if(bytes.length<1 || bytes.length>MAX_BYTES)throw new IOException("Camera snapshot size");
        String text=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
        try(var reader=new JsonReader(new StringReader(text))){
            reader.setLenient(false);JsonObject value=read(reader,0,new int[]{0}).getAsJsonObject();
            if(reader.peek()!=JsonToken.END_DOCUMENT || !value.keySet().equals(KEYS))throw new IOException("Camera snapshot fields/trailing data");
            if(integer(value,"schema")!=1 || !string(value,"source_kind").equals(fixture?"standalone_hud_physical_view_fixture":"live_kcd_hud_view_v1") ||
                    !string(value,"run").equals(id.run()) || !string(value,"patch_run").equals(patchRun) ||
                    !string(value,"patch_sha256").equals(patchHash) || integer(value,"target_pid")!=id.targetPid() ||
                    !string(value,"target_start_filetime").equals(Long.toUnsignedString(id.targetStart())))
                throw new IOException("Camera snapshot session identity differs");
            long seq=integer(value,"seq"),utc=integer(value,"utc_ms");
            if(seq<1 || seq>1_000_000 || utc<=0 || utc>now+50)throw new IOException("Camera sequence/time invalid");
            var forward=vector(value,"forward");var up=vector(value,"up");double fn=forward.length(),un=up.length();
            if(fn<.99||fn>1.01||un<.99||un>1.01)throw new IOException("Moving camera forward/up must be unit vectors within0.01");
            if(Math.abs(forward.dot(up)/(fn*un))>.01)throw new IOException("Moving camera forward/up are not orthogonal");
            double horizontal=Math.hypot(forward.x(),forward.y());
            if(horizontal/fn<.01)throw new IOException("Near-vertical moving camera unsupported");
            // Movement consumes yaw/pitch, so roll around forward cannot change
            // these angles. Native melee recoil legitimately rolls the camera.
            // The independent GameplayAimReader -> GameplayWorldRenderer path
            // keeps the full native up vector in setLookAt and frame metadata;
            // the compositor checks that same rolled basis against native depth.
            // Initial teleport seeds retain their separate <=1degree contract.
            double yaw=Math.toDegrees(Math.atan2(-forward.x(),-forward.y()));
            double pitch=-Math.toDegrees(Math.atan2(forward.z(),horizontal));
            // Structural parsing may retain a stale snapshot, but only fresh()
            // below authorizes use. It never renews an old capture timestamp.
            return new HudMovementView(seq,utc,(float)yaw,(float)pitch);
        }catch(IllegalArgumentException|IllegalStateException|ArithmeticException e){throw new IOException("Invalid camera snapshot",e);}
    }
    public boolean fresh(long now){return now>=utcMs-50 && now-utcMs<=MAX_AGE_MS;}
    private static JsonElement read(JsonReader r,int depth,int[] count) throws IOException{
        if(depth>3 || ++count[0]>64)throw new IOException("Camera JSON bound");
        return switch(r.peek()){
            case BEGIN_OBJECT -> {r.beginObject();var o=new JsonObject();while(r.hasNext()){String key=r.nextName();if(o.has(key))throw new IOException("Duplicate camera field");o.add(key,read(r,depth+1,count));}r.endObject();yield o;}
            case STRING -> new JsonPrimitive(r.nextString());
            case NUMBER -> {BigDecimal n=new BigDecimal(r.nextString());if(!Double.isFinite(n.doubleValue()))throw new IOException("Nonfinite camera number");yield new JsonPrimitive(n);}
            default -> throw new IOException("Unsupported camera JSON value");
        };
    }
    private static String string(JsonObject o,String key)throws IOException{var p=o.get(key);if(p==null || !p.isJsonPrimitive() || !p.getAsJsonPrimitive().isString())throw new IOException("Camera string "+key);return p.getAsString();}
    private static long integer(JsonObject o,String key)throws IOException{var p=o.get(key);if(p==null || !p.isJsonPrimitive() || !p.getAsJsonPrimitive().isNumber())throw new IOException("Camera integer "+key);return p.getAsBigDecimal().longValueExact();}
    private record Vec(double x,double y,double z){double length(){return Math.hypot(Math.hypot(x,y),z);}double dot(Vec other){return x*other.x+y*other.y+z*other.z;}}
    private static Vec vector(JsonObject value,String name)throws IOException{
        var element=value.get(name);if(element==null||!element.isJsonObject()||!element.getAsJsonObject().keySet().equals(Set.of("x","y","z")))throw new IOException("Moving camera vector fields differ");
        var v=element.getAsJsonObject();double[] axes=new double[3];int i=0;
        for(String axis:new String[]{"x","y","z"}){var p=v.get(axis);if(!p.isJsonPrimitive()||!p.getAsJsonPrimitive().isNumber()||!Double.isFinite(p.getAsDouble())||Math.abs(p.getAsDouble())>10_000_000)throw new IOException("Moving camera vector number invalid");axes[i++]=p.getAsDouble();}
        return new Vec(axes[0],axes[1],axes[2]);
    }
}
