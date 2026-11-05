package dev.minecome.terrain;

import com.google.gson.*;
import com.google.gson.stream.*;
import dev.minecome.hud.HudInputProtocol;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.nio.file.*;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;

/** Bounded off-thread tile ingestion and durable acknowledgement. No game calls. */
final class GameplayTerrainAdmission implements AutoCloseable {
    record Pending(GameplayTerrain expected,GameplayTerrain next,int tx,int tz,String tileHash,String tileJson){}
    private static final Set<String> KEYS=Set.of("schema","kind","run","world_id","patch_run","patch_sha256","target_pid","target_start_filetime","generation","tx","tz","tile_sha256","tile_json","utc_ms");
    private final Path file,ack;private final GameplayTerrainStore store;private final HudInputProtocol.Identity identity;private final String world;
    private final AtomicReference<Pending> accepted=new AtomicReference<>();
    private volatile Pending pending;private volatile long persistedGeneration;private volatile boolean closing,finished;private volatile String failure;
    GameplayTerrainAdmission(Path directory,GameplayTerrainStore store,HudInputProtocol.Identity identity,String world){
        this.store=store;this.identity=identity;this.world=world;file=directory.resolve("terrain-admission.json");ack=directory.resolve("terrain-ack.json");persistedGeneration=store.surface().generation();
        var worker=new Thread(this::run,"MineComeTerrainAdmission");worker.setDaemon(true);worker.start();
    }
    Pending pending(){return pending;}String failure(){return failure;}long persistedGeneration(){return persistedGeneration;}boolean finished(){return finished;}
    synchronized void applied(Pending value){if(closing||value!=pending||!accepted.compareAndSet(null,value))throw new IllegalStateException("Terrain admission ownership changed");}
    private void run(){String previous=null;long failedAt=0;try{
        while(true){
            Pending done;
            // Enqueue, close, and the final empty-queue observation share one lock:
            // a close cannot overtake an already applied candidate between drain and exit.
            synchronized(this){done=accepted.getAndSet(null);if(done==null&&closing)break;}
            if(done!=null){store.persist(done.expected(),done.next(),done.tileJson());writeAck(done);pending=null;persistedGeneration=done.next().generation();}
            if(closing)continue;
            if(pending==null){
                byte[] bytes=null;
                try{var a=Files.readAttributes(file,java.nio.file.attribute.BasicFileAttributes.class,LinkOption.NOFOLLOW_LINKS);
                    if(!a.isRegularFile()||a.isSymbolicLink()||a.size()>100_000)throw new IOException("Invalid terrain admission file");
                    try(var in=Files.newInputStream(file)){bytes=in.readNBytes(100_001);}failedAt=0;
                }catch(FileSystemException e){
                    if(!(e instanceof NoSuchFileException&&previous==null)){long now=System.nanoTime();if(failedAt==0)failedAt=now;if(now-failedAt>=100_000_000L)throw e;}
                }
                if(bytes!=null){if(bytes.length>100_000)throw new IOException("Terrain admission oversized");
                    String text=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
                    if(!text.equals(previous)){pending=parse(text,store.surface(),identity,world,System.currentTimeMillis());previous=text;}
                }
            }
            Thread.sleep(10);
        }
    }catch(Exception e){failure=e.toString();}finally{finished=true;}}
    static Pending parse(String text,GameplayTerrain current,HudInputProtocol.Identity id,String world,long now)throws IOException{
        if(text.length()>100_000)throw new IOException("Terrain admission oversized");
        try(var reader=new JsonReader(new StringReader(text))){
            reader.setLenient(false);reader.beginObject();var j=new JsonObject();
            while(reader.hasNext()){String key=reader.nextName();if(j.has(key)||!KEYS.contains(key))throw new IOException("Duplicate/unknown terrain admission field");
                JsonElement value=switch(reader.peek()){
                    case STRING -> new JsonPrimitive(reader.nextString());case NUMBER -> new JsonPrimitive(new java.math.BigDecimal(reader.nextString()));
                    default -> throw new IOException("Invalid terrain admission value");};j.add(key,value);}
            reader.endObject();if(reader.peek()!=JsonToken.END_DOCUMENT||!j.keySet().equals(KEYS))throw new IOException("Incomplete terrain admission");
            if(integer(j,"schema")!=1||!string(j,"kind").equals("minecome_gameplay_terrain_admission_v1")||!string(j,"run").equals(id.run())||!string(j,"world_id").equals(world)||
                !string(j,"patch_run").equals(current.run())||!string(j,"patch_sha256").equals(current.sha256())||integer(j,"target_pid")!=id.targetPid()||
                !string(j,"target_start_filetime").equals(Long.toUnsignedString(id.targetStart())))throw new IOException("Terrain admission identity differs");
            long utc=integer(j,"utc_ms");if(utc<=0||utc>now+50||now-utc>5000||integer(j,"generation")!=current.generation()+1)throw new IOException("Terrain admission stale or generation differs");
            int tx=Math.toIntExact(integer(j,"tx")),tz=Math.toIntExact(integer(j,"tz"));String raw=string(j,"tile_json"),hash=string(j,"tile_sha256");
            var encoded=StandardCharsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).encode(java.nio.CharBuffer.wrap(raw));
            byte[] tileBytes=new byte[encoded.remaining()];encoded.get(tileBytes);
            var tile=GroundPatch.parse(tileBytes,true);if(!tile.sha256().equals(hash))throw new IOException("Terrain tile bytes differ");
            return new Pending(current,current.admit(tx,tz,tile),tx,tz,hash,raw);
        }catch(RuntimeException e){throw new IOException("Invalid terrain admission",e);}
    }
    private void writeAck(Pending p)throws IOException,InterruptedException{
        var j=new JsonObject();j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_terrain_ack_v1");j.addProperty("run",identity.run());j.addProperty("world_id",world);
        j.addProperty("patch_run",p.next().run());j.addProperty("patch_sha256",p.next().sha256());j.addProperty("target_pid",identity.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(identity.targetStart()));
        j.addProperty("generation",p.next().generation());j.addProperty("tx",p.tx());j.addProperty("tz",p.tz());j.addProperty("tile_sha256",p.tileHash());j.addProperty("status","admitted");j.addProperty("coverage_digest",p.next().digest());
        Path temp=ack.resolveSibling("terrain-ack.tmp");Files.writeString(temp,j.toString(),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);
        long began=System.nanoTime();while(true){try{Files.move(temp,ack,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);return;}catch(AccessDeniedException e){if(System.nanoTime()-began>100_000_000L)throw e;Thread.sleep(5);}}
    }
    private static String string(JsonObject j,String k)throws IOException{var p=j.getAsJsonPrimitive(k);if(p==null||!p.isString())throw new IOException("Terrain string required");return p.getAsString();}
    private static long integer(JsonObject j,String k)throws IOException{var p=j.getAsJsonPrimitive(k);if(p==null||!p.isNumber())throw new IOException("Terrain number required");return p.getAsBigDecimal().longValueExact();}
    @Override public synchronized void close(){closing=true;}
}
