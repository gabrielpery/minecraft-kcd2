package dev.minecome.gameplay;

import com.google.gson.*;
import dev.minecome.terrain.GroundSurface;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Saved ownership only; vanilla owns the block states themselves. */
final class GameplayBlocksLedger {
    static final int MAX_BLOCKS=64,MAX_BYTES=16384;
    record Cell(int x,int y,int z) implements Comparable<Cell> {
        public int compareTo(Cell c){int n=Integer.compare(x,c.x);if(n==0)n=Integer.compare(y,c.y);return n==0?Integer.compare(z,c.z):n;}
    }
    final GameplayWorld save;final GroundSurface surface;final Path path;
    final Set<Cell> initial;final long initialRevision;
    private String previous;private long persistedRevision;
    GameplayBlocksLedger(GameplayWorld save,GroundSurface surface)throws IOException {
        this.save=save;this.surface=surface;save.verifyOwnership();path=save.directory().resolve("minecome-blocks.json");
        if(!Files.exists(path,LinkOption.NOFOLLOW_LINKS))Files.writeString(path,json(0,Set.of()).toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
        if(Files.isSymbolicLink(path)||!Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS)||Files.size(path)>MAX_BYTES)throw new IOException("Invalid persistent block ledger");
        previous=Files.readString(path,StandardCharsets.UTF_8);
        try{
            var j=JsonParser.parseString(previous).getAsJsonObject();
            if(!j.keySet().equals(Set.of("schema","kind","world_id","patch_run","patch_sha256","revision","blocks"))||integer(j,"schema")!=1||!string(j,"kind").equals("minecome_gameplay_block_ledger_v1")||!string(j,"world_id").equals(save.id().toString())||
                !string(j,"patch_run").equals(surface.run())||!string(j,"patch_sha256").equals(surface.sha256()))throw new IOException("Persistent block ledger identity differs");
            initialRevision=number(j,"revision").longValueExact();if(initialRevision<0)throw new IOException("Negative block revision");
            var cells=new TreeSet<Cell>();var blocks=j.getAsJsonArray("blocks");if(blocks.size()>MAX_BLOCKS)throw new IOException("Block ledger exceeds64 stones");
            for(var element:blocks){var b=element.getAsJsonObject();var c=new Cell(integer(b,"x"),integer(b,"y"),integer(b,"z"));
                if(!b.keySet().equals(Set.of("x","y","z","state"))||!string(b,"state").equals("minecraft:stone")||!allowed(surface,c)||!cells.add(c))throw new IOException("Invalid or duplicate owned stone");}
            initial=Set.copyOf(cells);persistedRevision=initialRevision;
        }catch(RuntimeException error){throw new IOException("Invalid persistent block ledger",error);}
    }
    static java.math.BigDecimal number(JsonObject j,String key){var v=j.get(key);if(v==null||!v.isJsonPrimitive()||!v.getAsJsonPrimitive().isNumber())throw new IllegalArgumentException("Numeric "+key+" required");return v.getAsBigDecimal();}
    static int integer(JsonObject j,String key){return number(j,key).intValueExact();}
    static String string(JsonObject j,String key){var v=j.get(key);if(v==null||!v.isJsonPrimitive()||!v.getAsJsonPrimitive().isString())throw new IllegalArgumentException("String "+key+" required");return v.getAsString();}
    static boolean allowed(GroundSurface surface,Cell c){return c.x>=-4&&c.x<=3&&c.z>=-4&&c.z<=3&&c.y>=56&&c.y<=80&&surface.containsFeet(c.x+.5,c.z+.5,.5);}
    static JsonArray blocks(Set<Cell> cells){var a=new JsonArray();for(var c:new TreeSet<>(cells)){var j=new JsonObject();j.addProperty("x",c.x);j.addProperty("y",c.y);j.addProperty("z",c.z);j.addProperty("state","minecraft:stone");a.add(j);}return a;}
    JsonObject json(long revision,Set<Cell> cells){var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_block_ledger_v1");j.addProperty("world_id",save.id().toString());
        j.addProperty("patch_run",surface.run());j.addProperty("patch_sha256",surface.sha256());j.addProperty("revision",revision);j.add("blocks",blocks(cells));return j;}
    void persist(long revision,Set<Cell> cells)throws IOException,InterruptedException {
        if(revision<=persistedRevision||cells.size()>MAX_BLOCKS||cells.stream().anyMatch(c->!allowed(surface,c)))throw new IOException("Unbounded or regressed block checkpoint");
        save.verifyOwnership();if(Files.isSymbolicLink(path)||!Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS)||Files.size(path)>MAX_BYTES||!Files.readString(path,StandardCharsets.UTF_8).equals(previous))throw new IOException("Block ledger changed outside session");
        String next=json(revision,cells).toString();GameplayBlocksFiles.atomic(path,next);previous=next;persistedRevision=revision;
    }
}
