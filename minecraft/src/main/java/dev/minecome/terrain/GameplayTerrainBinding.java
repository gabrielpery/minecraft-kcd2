package dev.minecome.terrain;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import dev.minecome.gameplay.GameplayWorld;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.UUID;

/** Persistent coordinate/terrain identity; imported collision never becomes saved blocks. */
public final class GameplayTerrainBinding {
    public record Position(double x,double y,double z,float yaw,float pitch,boolean flying,boolean falling,float fallDistance) {
        public Position(double x,double y,double z,float yaw,float pitch){this(x,y,z,yaw,pitch,false,false,0);}
        public Position(double x,double y,double z,float yaw,float pitch,boolean flying){this(x,y,z,yaw,pitch,flying,false,0);}
        public Position {if(!Double.isFinite(x)||!Double.isFinite(y)||!Double.isFinite(z)||!Float.isFinite(yaw)||!Float.isFinite(pitch)||!Float.isFinite(fallDistance)||fallDistance<0||fallDistance>128||flying&&falling||!falling&&fallDistance!=0)throw new IllegalArgumentException("Invalid resume position or airborne state");}
    }
    private final GameplayWorld save;
    private final Path directory,marker;
    private final GroundPatch surface;
    private GameplayTerrainStore coverage;
    private String previous;
    private Position resume;
    private boolean blockSupport,flightSupport;
    private GameplayTerrainBinding(GameplayWorld save,Path directory,GroundPatch surface,String previous,Position resume){
        this.save=save;this.directory=directory;this.marker=directory.resolve("binding.json");this.surface=surface;this.previous=previous;this.resume=resume;
    }
    public static GameplayTerrainBinding open(GameplayWorld save,Path source,boolean fixture)throws IOException{
        return open(save,source,fixture,false);
    }
    public static GameplayTerrainBinding open(GameplayWorld save,Path source,boolean fixture,boolean blocks)throws IOException{
        return open(save,source,fixture,blocks,false);
    }
    public static GameplayTerrainBinding open(GameplayWorld save,Path source,boolean fixture,boolean blocks,boolean explore)throws IOException{
        return open(save,source,fixture,blocks,explore,false);
    }
    public static GameplayTerrainBinding open(GameplayWorld save,Path source,boolean fixture,boolean blocks,boolean explore,boolean flight)throws IOException{
        save.verifyOwnership();GroundPatch requested=GroundPatch.read(source,true);
        String kind=requested.sourceKind();
        if(!(fixture?kind.equals("standalone_ground_fixture")||kind.equals("standalone_fixture"):kind.equals("live_kcd_ground_patch")))throw new IOException("Gameplay terrain provenance differs");
        if(!requested.run().matches("[0-9a-f]{32}"))throw new IOException("Gameplay terrain run must identify a capture");
        Path dir=save.directory().resolve("minecome-terrain");
        if(!Files.exists(dir,LinkOption.NOFOLLOW_LINKS)){
            Path staging=save.directory().resolve(".minecome-terrain-"+UUID.randomUUID()+".tmp");Files.createDirectory(staging);
            Files.copy(source,staging.resolve("ground-patch.json"));
            GroundPatch copied=GroundPatch.read(staging.resolve("ground-patch.json"),true);
            if(!copied.sha256().equals(requested.sha256()))throw new IOException("Terrain changed while binding");
            String binding=json(save,requested,null).toString();
            Files.writeString(staging.resolve("binding.json"),binding,StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
            publishInitial(save,requested,staging,dir,binding);
        }
        if(Files.isSymbolicLink(dir)||!dir.toRealPath().equals(save.directory().resolve("minecome-terrain")))throw new IOException("Redirected terrain binding");
        Path patchFile=dir.resolve("ground-patch.json"),marker=dir.resolve("binding.json");
        if(Files.isSymbolicLink(patchFile)||Files.isSymbolicLink(marker)||Files.size(marker)>4096)throw new IOException("Invalid terrain binding files");
        GroundPatch cached=GroundPatch.read(patchFile,true);String text=Files.readString(marker,StandardCharsets.UTF_8);
        try{
            JsonObject value=JsonParser.parseString(text).getAsJsonObject();
            if(value.get("schema").getAsInt()!=1||!value.get("kind").getAsString().equals("minecome_gameplay_terrain_v1")||
                !value.get("world_id").getAsString().equals(save.id().toString())||!value.get("patch_sha256").getAsString().equals(cached.sha256())||
                !value.get("patch_run").getAsString().equals(cached.run())||!cached.sha256().equals(requested.sha256())||
                value.get("host_x").getAsDouble()!=cached.centerX()||value.get("host_y").getAsDouble()!=cached.centerY()||value.get("host_z").getAsDouble()!=cached.centerZ())throw new IOException("Persistent terrain origin/identity changed");
            GameplayTerrainStore coverage=explore?GameplayTerrainStore.open(save,cached):null;
            Position position=null;
            if(value.has("resume")){JsonObject p=value.getAsJsonObject("resume");
                for(String flag:new String[]{"flying","falling"})if(p.has(flag)&&(!p.get(flag).isJsonPrimitive()||!p.getAsJsonPrimitive(flag).isBoolean()))throw new IOException("Invalid airborne checkpoint tag");
                boolean falling=p.has("falling")&&p.get("falling").getAsBoolean();if(falling!=p.has("fall_distance"))throw new IOException("Falling checkpoint lacks matching distance");
                position=new Position(p.get("x").getAsDouble(),p.get("y").getAsDouble(),p.get("z").getAsDouble(),p.get("yaw").getAsFloat(),p.get("pitch").getAsFloat(),p.has("flying")&&p.get("flying").getAsBoolean(),falling,falling?p.get("fall_distance").getAsFloat():0);validate(coverage==null?cached:coverage.surface(),position,blocks,flight);}
            var binding=new GameplayTerrainBinding(save,dir,cached,text,position);binding.blockSupport=blocks;binding.flightSupport=flight;binding.coverage=coverage;return binding;
        }catch(RuntimeException e){throw new IOException("Invalid gameplay terrain binding",e);}
    }
    private static void publishInitial(GameplayWorld save,GroundPatch requested,Path staging,Path target,String binding)throws IOException{
        long started=System.nanoTime();AccessDeniedException lastDenied=null;
        while(true){
            if(Thread.currentThread().isInterrupted())throw new java.io.InterruptedIOException("Terrain binding publication interrupted");
            save.verifyOwnership();
            if(Files.exists(target,LinkOption.NOFOLLOW_LINKS))throw new FileAlreadyExistsException(target.toString());
            Path patch=staging.resolve("ground-patch.json"),marker=staging.resolve("binding.json");
            if(Files.isSymbolicLink(staging)||!Files.isDirectory(staging,LinkOption.NOFOLLOW_LINKS)||!staging.toRealPath().equals(staging)||
                Files.isSymbolicLink(patch)||Files.isSymbolicLink(marker)||Files.size(marker)>4096||
                !Files.readString(marker,StandardCharsets.UTF_8).equals(binding)||!GroundPatch.read(patch,true).sha256().equals(requested.sha256()))
                throw new IOException("Terrain staging changed before publication");
            if(lastDenied!=null&&System.nanoTime()-started>=250_000_000L)throw lastDenied;
            try{
                // Same-parent rename, explicitly without replacement. ATOMIC_MOVE
                // permits provider-specific replacement of an existing target.
                Files.move(staging,target);return;
            }catch(AccessDeniedException denied){
                lastDenied=denied;long remaining=250_000_000L-(System.nanoTime()-started);
                if(remaining<=0)throw denied;
                try{java.util.concurrent.TimeUnit.NANOSECONDS.sleep(Math.min(5_000_000L,remaining));}
                catch(InterruptedException interrupted){Thread.currentThread().interrupt();var error=new java.io.InterruptedIOException("Terrain binding publication interrupted");error.initCause(interrupted);throw error;}
            }
        }
    }
    public GroundPatch surface(){return surface;}
    public GameplayTerrainStore coverage(){return coverage;}
    public GroundSurface currentSurface(){return coverage==null?surface:coverage.surface();}
    public synchronized Position resume(){return resume;}
    public Path patchFile(){return directory.resolve("ground-patch.json");}
    /** Runs on the bounded file worker, never the ongoing game tick. */
    public synchronized void checkpoint(Position position)throws IOException{
        validate(currentSurface(),position,blockSupport,flightSupport);save.verifyOwnership();
        if(!Files.readString(marker,StandardCharsets.UTF_8).equals(previous))throw new IOException("Terrain binding changed before checkpoint");
        String next=json(save,surface,position).toString();Path temp=directory.resolve("binding-"+UUID.randomUUID()+".tmp");
        Files.writeString(temp,next,StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
        Files.move(temp,marker,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);previous=next;resume=position;
    }
    static void validate(GroundSurface s,Position p)throws IOException{
        validate(s,p,false,false);
    }
    private static void validate(GroundSurface s,Position p,boolean blocks,boolean flight)throws IOException{
        if((p.flying()||p.falling())&&!flight)throw new IOException("Aerial checkpoint requires the Flight profile");
        double ground=s.groundForFeet(p.x(),p.z(),.3);
        if(!s.containsFeet(p.x(),p.z(),.31)||p.y()<ground-.2||((p.flying()||p.falling())?p.y()>GameplayBoundary.FLIGHT_MAX_Y:blocks?p.y()>81.2:Math.abs(p.y()-ground)>.2))throw new IOException("Resume position is outside sampled ground/block/flight coverage");
    }
    private static JsonObject json(GameplayWorld save,GroundPatch patch,Position position){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_terrain_v1");j.addProperty("world_id",save.id().toString());
        j.addProperty("patch_run",patch.run());j.addProperty("patch_sha256",patch.sha256());j.addProperty("host_x",patch.centerX());j.addProperty("host_y",patch.centerY());j.addProperty("host_z",patch.centerZ());
        if(position!=null){var p=new JsonObject();p.addProperty("x",position.x());p.addProperty("y",position.y());p.addProperty("z",position.z());p.addProperty("yaw",position.yaw());p.addProperty("pitch",position.pitch());if(position.flying())p.addProperty("flying",true);if(position.falling()){p.addProperty("falling",true);p.addProperty("fall_distance",position.fallDistance());}j.add("resume",p);}return j;
    }
}
