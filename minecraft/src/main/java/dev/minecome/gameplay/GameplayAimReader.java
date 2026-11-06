package dev.minecome.gameplay;

import com.google.gson.*;
import com.google.gson.stream.*;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.hud.GameplayWorldRenderer;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.util.math.Vec3d;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Set;

/** Latest exact native camera/ray sample. File work never runs on a game tick. */
public final class GameplayAimReader implements AutoCloseable {
    private static final Set<String> KEYS=Set.of("schema","kind","run","world_id","patch_run","patch_sha256","target_pid","target_start_filetime","seq","utc_ms","origin","direction","range","known","distance","terrain_hit");
    private static final Set<String> VIEW_KEYS;
    static{var keys=new java.util.HashSet<>(KEYS);keys.add("up");keys.add("vertical_fov");VIEW_KEYS=Set.copyOf(keys);}
    private final Path file;private final HudInputProtocol.Identity identity;private final GroundSurface surface;private final String worldId;
    private volatile GameplayBlocks.Aim latest;private volatile String failure;private volatile boolean closing;
    public record RenderSample(GameplayBlocks.Aim aim,GameplayWorldRenderer.View view){}
    private volatile RenderSample renderSample;private final boolean worldBlocks;
    public GameplayAimReader(Path directory,HudInputProtocol.Identity identity,GroundSurface surface,String worldId){
        this(directory,identity,surface,worldId,false);
    }
    public GameplayAimReader(Path directory,HudInputProtocol.Identity identity,GroundSurface surface,String worldId,boolean worldBlocks){
        this.worldBlocks=worldBlocks;
        this.file=directory.resolve("gameplay-aim.json");this.identity=identity;this.surface=surface;this.worldId=worldId;
        Thread worker=new Thread(this::readLoop,"MineComeGameplayAim");worker.setDaemon(true);worker.start();
    }
    public GameplayBlocks.Aim current(){if(closing||failure!=null)return null;var a=latest;return a!=null&&a.fresh(System.currentTimeMillis(),System.nanoTime())?a:null;}
    public String failure(){return failure;}
    /** One publication supplies both projection and target; never mix adjacent native samples. */
    public RenderSample worldSample(){var sample=renderSample;return !closing&&failure==null&&sample!=null&&sample.aim().fresh(System.currentTimeMillis(),System.nanoTime())?sample:null;}
    private void readLoop(){long sequence=0,utc=0,failedAt=0;String previous=null;try{
        while(!closing){
            String text=null;
            try{
                var attrs=Files.readAttributes(file,java.nio.file.attribute.BasicFileAttributes.class,LinkOption.NOFOLLOW_LINKS);
                if(!attrs.isRegularFile()||attrs.isSymbolicLink()||attrs.size()>4096)throw new IOException("Aim snapshot invalid/oversized");
                try(var stream=Files.newInputStream(file)){var bytes=stream.readNBytes(4097);if(bytes.length>4096)throw new IOException("Aim snapshot oversized");text=new String(bytes,StandardCharsets.UTF_8);}
                failedAt=0;
            }catch(FileSystemException e){
                // Atomic replacement can briefly deny read sharing on Windows.
                // Keep the original sample deadline; only filesystem errors retry.
                if(!(e instanceof NoSuchFileException&&previous==null)){
                    long now=System.nanoTime();if(failedAt==0)failedAt=now;
                    if(now-failedAt>=100_000_000L)throw new IOException("Aim filesystem retry deadline",e);
                }
            }
            if(text!=null){
                if(!text.equals(previous)){
                    var value=parse(text,identity,worldId,surface,System.currentTimeMillis());
                    if(worldBlocks&&value.get("schema").getAsInt()!=2)throw new IOException("World block camera requires aim v2");
                    long seq=value.get("seq").getAsLong(),time=value.get("utc_ms").getAsLong();
                    if(seq<=sequence||time<utc)throw new IOException("Aim snapshot sequence regressed");sequence=seq;utc=time;previous=text;
                    var p=vector(value.getAsJsonObject("origin"));var d=vector(value.getAsJsonObject("direction"));
                    latest=new GameplayBlocks.Aim(time,System.nanoTime(),new Vec3d(p.x-surface.centerX(),64+p.z-surface.centerZ(),surface.centerY()-p.y),
                        new Vec3d(d.x,d.z,-d.y),value.get("range").getAsDouble(),value.get("known").getAsBoolean(),value.get("distance").getAsDouble(),value.get("terrain_hit").getAsBoolean());
                    if(worldBlocks){var u=vector(value.getAsJsonObject("up"));renderSample=new RenderSample(latest,new GameplayWorldRenderer.View(latest.origin(),latest.direction(),new Vec3d(u.x,u.z,-u.y),number(value,"vertical_fov")));}
                }
            }
            Thread.sleep(10);
        }
    }catch(Exception e){if(!closing)failure=e.toString();}}
    public static JsonObject parse(String text,HudInputProtocol.Identity id,String world,GroundSurface surface,long now)throws IOException{
        if(text.length()>4096)throw new IOException("Aim snapshot oversized");
        try(var r=new JsonReader(new StringReader(text))){
            r.setLenient(false);var j=object(r,0);
            long schema=integer(j,"schema");boolean view=schema==2;
            if(r.peek()!=JsonToken.END_DOCUMENT||!j.keySet().equals(view?VIEW_KEYS:KEYS)||(schema!=1&&schema!=2)||!string(j,"kind").equals(view?"minecome_gameplay_aim_v2":"minecome_gameplay_aim_v1")||
                !string(j,"run").equals(id.run())||!string(j,"world_id").equals(world)||!string(j,"patch_run").equals(surface.run())||!string(j,"patch_sha256").equals(surface.sha256())||
                integer(j,"target_pid")!=id.targetPid()||!string(j,"target_start_filetime").equals(Long.toUnsignedString(id.targetStart())))throw new IOException("Aim identity differs");
            long seq=integer(j,"seq"),utc=integer(j,"utc_ms");double range=number(j,"range"),hit=number(j,"distance");
            if(seq<1||seq>1_000_000||utc<1||utc>now+50||range<=0||range>4.5||hit< -1||hit>range||(hit<0&&hit!= -1))throw new IOException("Aim sequence/time/range invalid");
            var origin=vector(j.getAsJsonObject("origin"));var direction=vector(j.getAsJsonObject("direction"));
            if(origin.lengthSquared()>3e14||Math.abs(direction.lengthSquared()-1)>.001)throw new IOException("Aim vectors invalid");
            if(view){var up=vector(j.getAsJsonObject("up"));double fov=number(j,"vertical_fov");if(Math.abs(up.lengthSquared()-1)>.05||Math.abs(up.dotProduct(direction))>.05||fov<=.05||fov>=Math.PI-.05)throw new IOException("Render camera basis/FOV invalid");}
            boolean known=bool(j,"known"),terrain=bool(j,"terrain_hit");if(!known&&hit!=-1||terrain&&(!known||hit<0))throw new IOException("Aim terrain classification invalid");return j;
        }catch(RuntimeException e){throw new IOException("Invalid aim JSON",e);}
    }
    private static JsonObject object(JsonReader r,int depth)throws IOException{
        if(depth>1)throw new IOException("Aim nesting");var j=new JsonObject();r.beginObject();int fields=0;
        while(r.hasNext()){String key=r.nextName();if(j.has(key)||++fields>20)throw new IOException("Duplicate/excess aim fields");
            JsonElement v=switch(r.peek()){
                case BEGIN_OBJECT -> object(r,depth+1);
                case STRING -> new JsonPrimitive(r.nextString());
                case NUMBER -> new JsonPrimitive(new java.math.BigDecimal(r.nextString()));
                case BOOLEAN -> new JsonPrimitive(r.nextBoolean());
                default -> throw new IOException("Unsupported aim value");};j.add(key,v);
        }r.endObject();return j;
    }
    private static String string(JsonObject j,String k)throws IOException{var p=j.getAsJsonPrimitive(k);if(p==null||!p.isString())throw new IOException("Aim string "+k);return p.getAsString();}
    private static double number(JsonObject j,String k)throws IOException{var p=j.getAsJsonPrimitive(k);if(p==null||!p.isNumber()||!Double.isFinite(p.getAsDouble()))throw new IOException("Aim number "+k);return p.getAsDouble();}
    private static long integer(JsonObject j,String k)throws IOException{number(j,k);return j.get(k).getAsBigDecimal().longValueExact();}
    private static boolean bool(JsonObject j,String k)throws IOException{var p=j.getAsJsonPrimitive(k);if(p==null||!p.isBoolean())throw new IOException("Aim boolean "+k);return p.getAsBoolean();}
    private static Vec3d vector(JsonObject j)throws IOException{if(!j.keySet().equals(Set.of("x","y","z")))throw new IOException("Aim vector fields");return new Vec3d(number(j,"x"),number(j,"y"),number(j,"z"));}
    @Override public void close(){closing=true;latest=null;renderSample=null;}
}
