package dev.minecome.hud;

import com.google.gson.*;
import com.google.gson.stream.*;
import dev.minecome.input.ExternalInputSessionGate;
import dev.minecome.input.HostViewSeed;
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
            // Reuse the inspected basis, roll and axis conversion contract. The
            // moving snapshot has no position authority: its synthetic zero here
            // only satisfies that parser's independent initial-position field.
            var seed=new JsonObject();seed.addProperty("schema",1);seed.addProperty("run",id.run());
            seed.addProperty("source_kind",fixture?"standalone_fixture":"live_kcd_view_seed");seed.addProperty("patch_sha256",patchHash);
            seed.addProperty("target_pid",id.targetPid());seed.addProperty("target_start_filetime",Long.toUnsignedString(id.targetStart()));
            seed.addProperty("captured_utc_ms",utc);var zero=new JsonObject();zero.addProperty("x",0);zero.addProperty("y",0);zero.addProperty("z",0);
            seed.add("player",zero);seed.add("forward",value.get("forward"));seed.add("up",value.get("up"));
            var expected=new ExternalInputSessionGate.Identity(id.run(),id.targetPid(),Long.toUnsignedString(id.targetStart()));
            // Structural parsing may retain a stale snapshot, but only fresh()
            // below authorizes use. It never renews an old capture timestamp.
            var decoded=HostViewSeed.parse(seed.toString().getBytes(StandardCharsets.UTF_8),expected,patchHash,fixture,0,0,0,utc);
            return new HudMovementView(seq,utc,(float)decoded.yawDegrees(),(float)decoded.pitchDegrees());
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
}
