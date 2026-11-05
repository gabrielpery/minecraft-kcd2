package dev.minecome.terrain;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayWorld;
import dev.minecome.hud.HudInputProtocol;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.List;
import java.util.function.BooleanSupplier;

/** Identity/freshness and durable admission handshake; no Minecraft thread or native engine calls. */
public final class GameplayTerrainAdmissionTests {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Action action,String message)throws Exception{try{action.run();throw new AssertionError(message);}catch(IOException|IllegalArgumentException|IllegalStateException expected){checks++;}}
    private static void await(BooleanSupplier condition,String failure)throws Exception{long until=System.nanoTime()+3_000_000_000L;while(!condition.getAsBoolean()&&System.nanoTime()<until)Thread.sleep(5);check(condition.getAsBoolean(),failure);}
    public static void main(String[] args)throws Exception{
        long now=System.currentTimeMillis();var id=new HudInputProtocol.Identity("a".repeat(32),11,22,33,44,now+60_000);
        Path root=Files.createTempDirectory("minecome-gameplay-admission-").toRealPath();var save=GameplayWorld.prepare(root.resolve("instance/saves"),root);
        Files.createDirectory(save.directory().resolve("minecome-terrain"));var base=GroundPatch.parse(GameplayTerrainTests.patch(0,0).toString().getBytes(StandardCharsets.UTF_8),true);
        var store=GameplayTerrainStore.open(save,base);var current=store.surface();String world=save.id().toString();var valid=admission(current,id,world,1,0,now);
        var parsed=GameplayTerrainAdmission.parse(valid.toString(),current,id,world,now);check(parsed.expected()==current&&parsed.next().generation()==1&&parsed.next().hasTile(1,0),"Fresh matching next tile produces immutable candidate");
        for(String field:List.of("kind","run","world_id","patch_run","patch_sha256","target_start_filetime")){
            var j=valid.deepCopy();j.addProperty(field,"foreign");reject(()->GameplayTerrainAdmission.parse(j.toString(),current,id,world,now),"Foreign identity refused: "+field);
        }
        var otherPid=valid.deepCopy();otherPid.addProperty("target_pid",34);reject(()->GameplayTerrainAdmission.parse(otherPid.toString(),current,id,world,now),"Different native process refused");
        var duplicate=valid.toString().replaceFirst("\\{","{\"generation\":1,");reject(()->GameplayTerrainAdmission.parse(duplicate,current,id,world,now),"Duplicate admission fields refused");
        var missing=valid.deepCopy();missing.remove("tile_sha256");reject(()->GameplayTerrainAdmission.parse(missing.toString(),current,id,world,now),"Incomplete admission refused");
        var unknown=valid.deepCopy();unknown.addProperty("surprise",1);reject(()->GameplayTerrainAdmission.parse(unknown.toString(),current,id,world,now),"Unknown admission fields refused");
        for(long utc:new long[]{now-5001,now+51,0}){var j=valid.deepCopy();j.addProperty("utc_ms",utc);reject(()->GameplayTerrainAdmission.parse(j.toString(),current,id,world,now),"Source time cannot be stale, zero or future");}
        for(double generation:new double[]{0,2,1.5}){var j=valid.deepCopy();j.addProperty("generation",generation);reject(()->GameplayTerrainAdmission.parse(j.toString(),current,id,world,now),"Only exact next generation admitted");}
        var rawChanged=valid.deepCopy();rawChanged.addProperty("tile_json",valid.get("tile_json").getAsString()+" ");reject(()->GameplayTerrainAdmission.parse(rawChanged.toString(),current,id,world,now),"Changed capture bytes refused");
        var far=admission(current,id,world,2,0,now);reject(()->GameplayTerrainAdmission.parse(far.toString(),current,id,world,now),"Disconnected capture refused");
        var fractional=valid.deepCopy();fractional.addProperty("tx",1.25);reject(()->GameplayTerrainAdmission.parse(fractional.toString(),current,id,world,now),"Fractional lattice coordinate refused");
        var malformed=valid.deepCopy();malformed.addProperty("tile_json",valid.get("tile_json").getAsString()+"\ud800");reject(()->GameplayTerrainAdmission.parse(malformed.toString(),current,id,world,now),"Invalid raw Unicode refused");
        reject(()->GameplayTerrainAdmission.parse(valid.toString(),parsed.next(),id,world,now),"Accepted generation cannot be replayed");

        Path directory=Files.createDirectories(root.resolve("runtime/evidence/first"));Path file=directory.resolve("terrain-admission.json");
        var worker=new GameplayTerrainAdmission(directory,store,id,world);
        try{
            writeAtomic(file,admission(store.surface(),id,world,1,0,System.currentTimeMillis()).toString());
            await(()->worker.pending()!=null||worker.failure()!=null,"Reader produces candidate");check(worker.failure()==null,"Candidate read succeeds");var pending=worker.pending();
            Thread.sleep(40);check(!Files.exists(directory.resolve("terrain-ack.json"))&&store.surface().generation()==0,"No persisted coverage or acknowledgement before both-world application");
            worker.applied(pending);await(()->worker.persistedGeneration()==1||worker.failure()!=null,"Applied coverage persists");check(worker.failure()==null&&worker.pending()==null,"Applied candidate completed without failure");
            var ack=JsonParser.parseString(Files.readString(directory.resolve("terrain-ack.json"))).getAsJsonObject();
            check(ack.get("coverage_digest").getAsString().equals(pending.next().digest())&&ack.get("generation").getAsInt()==1&&ack.get("status").getAsString().equals("admitted"),"Ack identifies the durable applied generation");
            check(GameplayTerrainStore.open(save,base).surface().digest().equals(pending.next().digest()),"Acknowledge only reconstructible saved coverage");
            Thread.sleep(40);check(worker.failure()==null&&worker.pending()==null,"Repeated identical file does not become a new generation");
            writeAtomic(file,Files.readString(file)+" ");await(()->worker.failure()!=null,"Changed old generation fails closed");check(worker.persistedGeneration()==1,"Replay does not mutate admitted coverage");
        }finally{worker.close();await(worker::finished,"First reader closes");}

        Path finalDirectory=Files.createDirectories(root.resolve("runtime/evidence/drain"));var drain=new GameplayTerrainAdmission(finalDirectory,store,id,world);
        try{
            writeAtomic(finalDirectory.resolve("terrain-admission.json"),admission(store.surface(),id,world,2,0,System.currentTimeMillis()).toString());
            await(()->drain.pending()!=null||drain.failure()!=null,"Second-generation candidate read");check(drain.failure()==null,"Second candidate valid");
            drain.applied(drain.pending());drain.close();await(drain::finished,"Accepted candidate drains on close");
            check(drain.failure()==null&&drain.persistedGeneration()==2&&Files.exists(finalDirectory.resolve("terrain-ack.json")),"Close retains acknowledged application and saves before finishing");
        }finally{drain.close();}

        Path cancelledDirectory=Files.createDirectories(root.resolve("runtime/evidence/cancelled"));var cancelled=new GameplayTerrainAdmission(cancelledDirectory,store,id,world);
        try{
            writeAtomic(cancelledDirectory.resolve("terrain-admission.json"),admission(store.surface(),id,world,3,0,System.currentTimeMillis()).toString());
            await(()->cancelled.pending()!=null||cancelled.failure()!=null,"Unapplied candidate reaches shutdown boundary");check(cancelled.failure()==null,"Shutdown candidate valid");
            var candidate=cancelled.pending();cancelled.close();reject(()->cancelled.applied(candidate),"Close must reject a late game-thread apply instead of losing accepted work");
            await(cancelled::finished,"Unapplied reader closes");
            check(cancelled.failure()==null&&store.surface().generation()==2&&!Files.exists(cancelledDirectory.resolve("terrain-ack.json")),"Close before apply does not persist or acknowledge uninstalled collision");
        }finally{cancelled.close();}
        System.out.println("GameplayTerrainAdmissionTests: "+checks+" checks passed; no games");
    }
    private static JsonObject admission(GameplayTerrain surface,HudInputProtocol.Identity id,String world,int tx,int tz,long utc)throws IOException{
        String raw=GameplayTerrainTests.patch(tx,tz).toString();var tile=GroundPatch.parse(raw.getBytes(StandardCharsets.UTF_8),true);var j=new JsonObject();
        j.addProperty("schema",1);j.addProperty("kind","minecome_gameplay_terrain_admission_v1");j.addProperty("run",id.run());j.addProperty("world_id",world);
        j.addProperty("patch_run",surface.run());j.addProperty("patch_sha256",surface.sha256());j.addProperty("target_pid",id.targetPid());j.addProperty("target_start_filetime",Long.toUnsignedString(id.targetStart()));
        j.addProperty("generation",surface.generation()+1);j.addProperty("tx",tx);j.addProperty("tz",tz);j.addProperty("tile_sha256",tile.sha256());j.addProperty("tile_json",raw);j.addProperty("utc_ms",utc);return j;
    }
    private static void writeAtomic(Path path,String value)throws IOException{Path tmp=path.resolveSibling(path.getFileName()+".test.tmp");Files.writeString(tmp,value,StandardCharsets.UTF_8);Files.move(tmp,path,StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);}
}
