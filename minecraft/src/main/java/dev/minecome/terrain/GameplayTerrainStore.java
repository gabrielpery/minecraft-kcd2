package dev.minecome.terrain;

import com.google.gson.*;
import com.google.gson.stream.*;
import dev.minecome.gameplay.GameplayWorld;
import java.io.*;
import java.math.BigDecimal;
import java.nio.*;
import java.nio.charset.*;
import java.nio.file.*;
import java.util.*;

/** Atomic persistent coverage metadata. Call only on the file worker or initial load, never an active game tick. */
public final class GameplayTerrainStore {
    public static final int MAX_BYTES=8*1024*1024;
    private final GameplayWorld save;
    private final Path path;
    private final List<String> rawTiles=new ArrayList<>();
    private GameplayTerrain surface;
    private String previous;
    private GameplayTerrainStore(GameplayWorld save,GroundPatch base)throws IOException{
        this.save=save;save.verifyOwnership();Path dir=save.directory().resolve("minecome-terrain");
        if(Files.isSymbolicLink(dir)||!Files.isDirectory(dir,LinkOption.NOFOLLOW_LINKS)||!dir.toRealPath().equals(dir))throw new IOException("Owned terrain directory required");
        path=dir.resolve("coverage.json");surface=GameplayTerrain.initial(base);
        if(!Files.exists(path,LinkOption.NOFOLLOW_LINKS)){
            previous=json(surface,rawTiles).toString();Files.writeString(path,previous,StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);return;
        }
        previous=readOwned();
        try{
            var root=parse(previous);keys(root,"schema","kind","world_id","patch_run","patch_sha256","generation","digest","tiles");
            if(integer(root,"schema")!=1||!text(root,"kind").equals("minecome_gameplay_coverage_v1")||!text(root,"world_id").equals(save.id().toString())||
                    !text(root,"patch_run").equals(base.run())||!text(root,"patch_sha256").equals(base.sha256()))throw new IOException("Coverage identity differs");
            int generation=integer(root,"generation");if(generation<0||generation>=GameplayTerrain.MAX_TILES)throw new IOException("Coverage generation outside capacity");
            var entries=root.getAsJsonArray("tiles");if(entries==null||entries.size()!=generation)throw new IOException("Incomplete coverage generation");
            for(var entry:entries){var j=entry.getAsJsonObject();keys(j,"tx","tz","sha256","json");String raw=text(j,"json");GroundPatch tile=GroundPatch.parse(utf8(raw),true);
                if(!text(j,"sha256").equals(tile.sha256()))throw new IOException("Saved tile bytes changed");surface=surface.admit(integer(j,"tx"),integer(j,"tz"),tile);rawTiles.add(raw);}
            if(!text(root,"digest").equals(surface.digest()))throw new IOException("Coverage digest differs");
        }catch(RuntimeException e){throw new IOException("Invalid saved terrain coverage",e);}
    }
    public static GameplayTerrainStore open(GameplayWorld save,GroundPatch base)throws IOException{return new GameplayTerrainStore(save,base);}
    public synchronized GameplayTerrain surface(){return surface;}
    public Path path(){return path;}
    /** Persist the exact candidate before allowing gameplay to move into it. */
    public synchronized void persist(GameplayTerrain expected,GameplayTerrain next,String rawTileJson)throws IOException{
        if(surface!=expected||!next.isSuccessorOf(expected))throw new IOException("Coverage predecessor changed");
        var added=next.tiles().get(next.tileCount()-1);var parsed=GroundPatch.parse(utf8(rawTileJson),true);
        if(!parsed.sha256().equals(added.patch().sha256()))throw new IOException("Candidate raw tile changed");
        save.verifyOwnership();if(!readOwned().equals(previous))throw new IOException("Coverage changed outside this session; preserving it");
        var nextRaw=new ArrayList<>(rawTiles);nextRaw.add(rawTileJson);String text=json(next,nextRaw).toString();byte[] bytes=utf8(text);if(bytes.length>MAX_BYTES)throw new IOException("Coverage file exceeds bound");
        Path temp=path.resolveSibling("coverage-"+UUID.randomUUID()+".tmp");
        try{
            Files.write(temp,bytes,StandardOpenOption.CREATE_NEW);long until=System.nanoTime()+100_000_000L;
            while(true){try{Files.move(temp,path,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);break;}
                catch(FileSystemException e){if(System.nanoTime()>=until)throw e;try{Thread.sleep(5);}catch(InterruptedException interrupted){Thread.currentThread().interrupt();throw new IOException("Coverage persist interrupted",interrupted);}}}
        }finally{Files.deleteIfExists(temp);}
        previous=text;surface=next;rawTiles.add(rawTileJson);
    }
    private String readOwned()throws IOException{
        if(Files.isSymbolicLink(path)||!Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS))throw new IOException("Invalid coverage file");
        try(var input=Files.newInputStream(path)){byte[] bytes=input.readNBytes(MAX_BYTES+1);if(bytes.length<2||bytes.length>MAX_BYTES)throw new IOException("Coverage file size invalid");
            return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();}
    }
    private JsonObject json(GameplayTerrain value,List<String> raws){
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_coverage_v1");j.addProperty("world_id",save.id().toString());
        j.addProperty("patch_run",value.run());j.addProperty("patch_sha256",value.sha256());j.addProperty("generation",value.generation());j.addProperty("digest",value.digest());
        var list=new JsonArray();for(int i=1;i<value.tileCount();i++){var tile=value.tiles().get(i);var entry=new JsonObject();entry.addProperty("tx",tile.tx());entry.addProperty("tz",tile.tz());entry.addProperty("sha256",tile.patch().sha256());entry.addProperty("json",raws.get(i-1));list.add(entry);}j.add("tiles",list);return j;
    }
    private static byte[] utf8(String text)throws IOException{var encoded=StandardCharsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).encode(CharBuffer.wrap(text));byte[] bytes=new byte[encoded.remaining()];encoded.get(bytes);return bytes;}
    private static String text(JsonObject j,String key){var p=j.getAsJsonPrimitive(key);if(p==null||!p.isString())throw new IllegalArgumentException("Coverage string required: "+key);return p.getAsString();}
    private static int integer(JsonObject j,String key){var p=j.getAsJsonPrimitive(key);if(p==null||!p.isNumber())throw new IllegalArgumentException("Coverage integer required: "+key);return p.getAsBigDecimal().intValueExact();}
    private static void keys(JsonObject j,String... keys){if(!j.keySet().equals(Set.of(keys)))throw new IllegalArgumentException("Unknown or missing coverage fields");}
    private static JsonObject parse(String text)throws IOException{try(var r=new JsonReader(new StringReader(text))){r.setLenient(false);var j=readJson(r,0,new int[]{0}).getAsJsonObject();if(r.peek()!=JsonToken.END_DOCUMENT)throw new IOException("Trailing coverage JSON");return j;}}
    private static JsonElement readJson(JsonReader r,int depth,int[] count)throws IOException{
        if(depth>4||++count[0]>1024)throw new IOException("Coverage JSON exceeds bounds");return switch(r.peek()){
            case BEGIN_OBJECT -> {r.beginObject();var j=new JsonObject();while(r.hasNext()){String key=r.nextName();if(j.has(key))throw new IOException("Duplicate coverage field "+key);j.add(key,readJson(r,depth+1,count));}r.endObject();yield j;}
            case BEGIN_ARRAY -> {r.beginArray();var a=new JsonArray();while(r.hasNext())a.add(readJson(r,depth+1,count));r.endArray();yield a;}
            case STRING -> new JsonPrimitive(r.nextString());
            case NUMBER -> new JsonPrimitive(new BigDecimal(r.nextString()));
            default -> throw new IOException("Invalid coverage JSON value");};
    }
}
