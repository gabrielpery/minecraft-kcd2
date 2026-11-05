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
    public record Position(double x,double y,double z,float yaw,float pitch) {
        public Position {if(!Double.isFinite(x)||!Double.isFinite(y)||!Double.isFinite(z)||!Float.isFinite(yaw)||!Float.isFinite(pitch))throw new IllegalArgumentException("Nonfinite resume position");}
    }
    private final GameplayWorld save;
    private final Path directory,marker;
    private final GroundPatch surface;
    private String previous;
    private Position resume;
    private boolean blockSupport;
    private GameplayTerrainBinding(GameplayWorld save,Path directory,GroundPatch surface,String previous,Position resume){
        this.save=save;this.directory=directory;this.marker=directory.resolve("binding.json");this.surface=surface;this.previous=previous;this.resume=resume;
    }
    public static GameplayTerrainBinding open(GameplayWorld save,Path source,boolean fixture)throws IOException{
        return open(save,source,fixture,false);
    }
    public static GameplayTerrainBinding open(GameplayWorld save,Path source,boolean fixture,boolean blocks)throws IOException{
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
            Files.writeString(staging.resolve("binding.json"),json(save,requested,null).toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
            Files.move(staging,dir,StandardCopyOption.ATOMIC_MOVE);
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
            Position position=null;
            if(value.has("resume")){JsonObject p=value.getAsJsonObject("resume");position=new Position(p.get("x").getAsDouble(),p.get("y").getAsDouble(),p.get("z").getAsDouble(),p.get("yaw").getAsFloat(),p.get("pitch").getAsFloat());validate(cached,position,blocks);}
            var binding=new GameplayTerrainBinding(save,dir,cached,text,position);binding.blockSupport=blocks;return binding;
        }catch(RuntimeException e){throw new IOException("Invalid gameplay terrain binding",e);}
    }
    public GroundPatch surface(){return surface;}
    public synchronized Position resume(){return resume;}
    public Path patchFile(){return directory.resolve("ground-patch.json");}
    /** Runs on the bounded file worker, never the ongoing game tick. */
    public synchronized void checkpoint(Position position)throws IOException{
        validate(surface,position,blockSupport);save.verifyOwnership();
        if(!Files.readString(marker,StandardCharsets.UTF_8).equals(previous))throw new IOException("Terrain binding changed before checkpoint");
        String next=json(save,surface,position).toString();Path temp=directory.resolve("binding-"+UUID.randomUUID()+".tmp");
        Files.writeString(temp,next,StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
        Files.move(temp,marker,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);previous=next;resume=position;
    }
    static void validate(GroundSurface s,Position p)throws IOException{
        validate(s,p,false);
    }
    private static void validate(GroundSurface s,Position p,boolean blocks)throws IOException{
        double ground=s.groundForFeet(p.x(),p.z(),.3);
        if(!s.containsFeet(p.x(),p.z(),.31)||p.y()<ground-.2||(blocks?p.y()>81.2:Math.abs(p.y()-ground)>.2))throw new IOException("Resume position is outside sampled ground/block coverage");
    }
    private static JsonObject json(GameplayWorld save,GroundPatch patch,Position position){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_terrain_v1");j.addProperty("world_id",save.id().toString());
        j.addProperty("patch_run",patch.run());j.addProperty("patch_sha256",patch.sha256());j.addProperty("host_x",patch.centerX());j.addProperty("host_y",patch.centerY());j.addProperty("host_z",patch.centerZ());
        if(position!=null){var p=new JsonObject();p.addProperty("x",position.x());p.addProperty("y",position.y());p.addProperty("z",position.z());p.addProperty("yaw",position.yaw());p.addProperty("pitch",position.pitch());j.add("resume",p);}return j;
    }
}
