package dev.minecome.gameplay;

import com.google.gson.*;
import com.sun.nio.file.ExtendedOpenOption;
import dev.minecome.hud.HudInputProtocol;
import dev.minecome.terrain.*;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.*;

/** Combat transport identity, shape, coordinate and malformed input checks; no game. */
public final class GameplayCombatProtocolTests {
    private static int checks;
    private static final long NOW=1_800_000_000_000L;
    private static final HudInputProtocol.Identity ID=new HudInputProtocol.Identity("a".repeat(32),11,22,33,44,NOW+60000);
    private static final String WORLD="00000000-0000-0000-0000-000000000001";
    private static final GroundSurface SURFACE=new GroundSurface(){
        public String run(){return "b".repeat(32);}public String sourceKind(){return "fixture";}public String sha256(){return "c".repeat(64);}
        public double centerX(){return 120.5;}public double centerY(){return 2045.25;}public double centerZ(){return 56.75;}
        public List<GroundPatch.Point> points(){return List.of();}public List<GroundPatch.Slab> slabs(){return List.of();}public List<GroundPatch.Cell> cells(){return List.of();}
        public double heightAt(double x,double z){return 64;}public double groundForFeet(double x,double z,double r){return 64;}public boolean containsFeet(double x,double z,double r){return true;}public boolean wide(){return false;}
    };
    private static void check(boolean v,String reason){checks++;if(!v)throw new AssertionError(reason);}
    private static GameplayCombatProtocol.Snapshot parse(String text){return GameplayCombatProtocol.parse(text,ID,WORLD,SURFACE);}
    private static void reject(String text,String reason){try{parse(text);throw new AssertionError(reason);}catch(IllegalArgumentException expected){checks++;}}
    private static void reject(JsonObject value,String reason){reject(value.toString(),reason);}
    public static void main(String[] args)throws Exception{
        var valid=snapshot();var good=parse(valid.toString());
        check(good.seq()==1&&good.hitAck()==0&&good.actors().size()==1&&good.hurts().size()==1,"Current host snapshot accepted");
        check(good.actors().getFirst().maxHealth()==100&&good.hurts().getFirst().damage()==4,"Native health and Minecraft damage preserved");
        check(good.fresh(NOW-50)&&good.fresh(NOW+500)&&!good.fresh(NOW-51)&&!good.fresh(NOW+501),"Bounded timestamp freshness");
        try{good.actors().clear();throw new AssertionError("Mutable snapshot actors");}catch(UnsupportedOperationException expected){checks++;}
        for(var point:List.of(new GameplayCombatProtocol.Point(120.5,2045.25,56.75),new GameplayCombatProtocol.Point(-500.25,2000.5,-4.25),new GameplayCombatProtocol.Point(1,2,3))){
            var mc=GameplayCombatProtocol.toMinecraft(point,SURFACE);var back=GameplayCombatProtocol.toHost(mc,SURFACE);
            check(Math.abs(back.x()-point.x())<1e-12&&Math.abs(back.y()-point.y())<1e-12&&Math.abs(back.z()-point.z())<1e-12,"Host/Minecraft axes round trip");
        }
        var origin=GameplayCombatProtocol.toMinecraft(new GameplayCombatProtocol.Point(SURFACE.centerX(),SURFACE.centerY(),SURFACE.centerZ()),SURFACE);
        check(origin.equals(new GameplayCombatProtocol.Point(0,64,0)),"Captured ground maps to Minecraft anchor");
        var axis=GameplayCombatProtocol.toMinecraft(new GameplayCombatProtocol.Point(SURFACE.centerX()+1,SURFACE.centerY()+2,SURFACE.centerZ()+3),SURFACE);
        check(axis.equals(new GameplayCombatProtocol.Point(1,67,-2)),"Native up and north map to correct Minecraft axes");
        for(String key:valid.keySet()){
            var altered=valid.deepCopy();altered.remove(key);reject(altered,"Missing root field "+key);
            altered=valid.deepCopy();altered.add(key,JsonNull.INSTANCE);reject(altered,"Null root field "+key);
            reject(valid.toString().replaceFirst("\\{","{\""+key+"\":"+valid.get(key)+","),"Duplicate root field "+key);
        }
        for(String key:List.of("kind","run","world_id","target_start_filetime","patch_run","patch_sha256")){
            var altered=valid.deepCopy();altered.addProperty(key,"foreign");reject(altered,"Foreign combat identity "+key);
            altered=valid.deepCopy();altered.addProperty(key,1);reject(altered,"Numeric combat identity "+key);
        }
        for(String key:List.of("schema","target_pid","seq","utc_ms","hit_ack"))for(String raw:List.of("\"1\"","1.0","1e0","-1","true","[]","9223372036854775808"))
            reject(valid.toString().replace("\""+key+"\":"+valid.get(key),"\""+key+"\":"+raw),"Exact integer syntax "+key+"="+raw);
        var actor=valid.getAsJsonArray("actors").get(0).getAsJsonObject();
        for(String key:actor.keySet()){
            var altered=valid.deepCopy();altered.getAsJsonArray("actors").get(0).getAsJsonObject().remove(key);reject(altered,"Missing actor field "+key);
            reject(valid.toString().replace("\"actors\":[{","\"actors\":[{\""+key+"\":"+actor.get(key)+","),"Duplicate actor field "+key);
        }
        for(String key:List.of("x","y","z","width","height","health","max_health"))for(String raw:List.of("1e999","true","\"1\"","null","[]"))
            reject(valid.toString().replace("\""+key+"\":"+actor.get(key),"\""+key+"\":"+raw),"Malformed actor number "+key);
        for(String key:List.of("token","width","height","max_health")){
            var altered=valid.deepCopy();altered.getAsJsonArray("actors").get(0).getAsJsonObject().addProperty(key,0);reject(altered,"Zero actor identity/shape "+key);
        }
        var altered=valid.deepCopy();altered.getAsJsonArray("actors").add(actor.deepCopy());reject(altered,"Duplicate generation token");
        altered=valid.deepCopy();altered.getAsJsonArray("actors").get(0).getAsJsonObject().addProperty("token",257);reject(altered,"Token capacity bound");
        altered=valid.deepCopy();altered.getAsJsonArray("actors").get(0).getAsJsonObject().addProperty("health",0);reject(altered,"Live actor requires positive health");
        altered=valid.deepCopy();altered.getAsJsonArray("actors").get(0).getAsJsonObject().addProperty("alive",false);check(!parse(altered.toString()).actors().getFirst().alive(),"Native dead flag remains authoritative even with residual HP");
        altered=valid.deepCopy();altered.getAsJsonArray("actors").get(0).getAsJsonObject().addProperty("health",101);reject(altered,"Health above maximum");
        altered=valid.deepCopy();altered.getAsJsonArray("actors").get(0).getAsJsonObject().addProperty("extra",true);reject(altered,"Unknown actor property");
        altered=valid.deepCopy();for(int i=1;i<33;i++)altered.getAsJsonArray("actors").add(actor.deepCopy());reject(altered,"Actor capacity bound");
        altered=valid.deepCopy();altered.getAsJsonArray("hurts").add(altered.getAsJsonArray("hurts").get(0).deepCopy());reject(altered,"Repeated hurt sequence");
        altered=valid.deepCopy();altered.getAsJsonArray("hurts").get(0).getAsJsonObject().addProperty("kind","projectile");reject(altered,"Unimplemented damage kind rejected");
        altered=valid.deepCopy();altered.getAsJsonArray("hurts").get(0).getAsJsonObject().addProperty("damage",1001);reject(altered,"Damage bound");
        for(String text:List.of("","null","[]","{}",valid+"{}","/*comment*/"+valid," ".repeat(131073)))reject(text,"Malformed/bounded document");
        snapshotFiles();
        System.out.println("GameplayCombatProtocolTests: "+checks+" checks passed; no games");
    }
    private static void snapshotFiles()throws Exception{
        Path directory=Files.createTempDirectory("minecome-combat-snapshot-");
        try{
            Path file=directory.resolve("host-combat.json");
            check(GameplayCombatSnapshot.read(file)==null,"Missing atomic publication is unavailable, not malformed");
            rejectFile(directory,"Directory is not a combat snapshot");
            Files.write(file,new byte[131073]);rejectFile(file,"Oversized file rejected before allocation");
            Files.write(file,new byte[]{(byte)0xc3,(byte)0x28});rejectFile(file,"Malformed UTF8 rejected without replacement characters");
            Files.writeString(file,snapshot().toString(),StandardCharsets.UTF_8);
            check(parse(GameplayCombatSnapshot.read(file)).seq()==1,"Complete valid file parsed");
            windowsSharing(file);
            Path link=directory.resolve("linked.json");boolean linked=false;
            try{Files.createSymbolicLink(link,file);linked=true;}catch(UnsupportedOperationException|FileSystemException unavailable){System.out.println("Combat snapshot symlink creation unavailable: "+unavailable.getClass().getSimpleName());}
            if(linked){rejectFile(link,"Symbolic link rejected instead of followed");Files.delete(link);}

            // Race the production reader against actual atomic file replacement,
            // including different byte lengths. A reader must see one intact
            // generation or unavailable; never a false malformed-file failure.
            Path temporary=directory.resolve("publication.tmp");var done=new AtomicBoolean();var failure=new AtomicReference<Throwable>();var writes=new AtomicInteger();
            var writer=new Thread(()->{try{
                for(int sequence=2;sequence<=501;sequence++){
                    var value=snapshot();value.addProperty("seq",sequence);value.getAsJsonArray("actors").get(0).getAsJsonObject().addProperty("x",sequence);
                    Files.writeString(temporary,value+" ".repeat(sequence%97),StandardCharsets.UTF_8);
                    long deadline=System.nanoTime()+2_000_000_000L;
                    for(;;){try{Files.move(temporary,file,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);break;}
                        catch(AccessDeniedException busy){if(System.nanoTime()>=deadline)throw busy;Thread.sleep(1);}}
                    writes.incrementAndGet();
                }
            }catch(Throwable error){failure.set(error);}finally{done.set(true);}},"CombatSnapshotAtomicWriter");
            long deadline=System.nanoTime()+10_000_000_000L;int reads=0,overlap=0;long previous=1;writer.start();
            try{
                do{
                    if(System.nanoTime()>=deadline)throw new AssertionError("Atomic snapshot race deadline");
                    String text=GameplayCombatSnapshot.read(file);if(text==null)continue;var value=parse(text);
                    if(value.seq()<previous||value.seq()>1&&value.actors().getFirst().x()!=value.seq())throw new AssertionError("Torn/reversed atomic snapshot");
                    previous=value.seq();reads++;if(writes.get()>0&&!done.get())overlap++;
                }while(!done.get());
            }finally{writer.join(3000);}
            if(failure.get()!=null)throw new AssertionError("Atomic publisher failed",failure.get());
            check(!writer.isAlive()&&writes.get()==500,"All500 actual atomic replacements completed");
            check(reads>0&&overlap>0,"Production reads overlapped active atomic replacement");
            check(parse(GameplayCombatSnapshot.read(file)).seq()==501,"Final complete publication retained");
            System.out.println("Combat snapshot atomic race: "+writes.get()+" replacements, "+reads+" reads, "+overlap+" during replacement");
        }finally{
            try(var children=Files.list(directory)){for(var child:children.toList())Files.deleteIfExists(child);}
            Files.delete(directory);
        }
    }
    private static void rejectFile(Path path,String reason)throws IOException{
        try{if(GameplayCombatSnapshot.read(path)==null)throw new AssertionError(reason+" was incorrectly ignored");throw new AssertionError(reason);}
        catch(IOException expected){checks++;}
    }
    private static void windowsSharing(Path file)throws Exception{
        if(!System.getProperty("os.name").startsWith("Windows"))return;
        long sourceUtc=parse(GameplayCombatSnapshot.read(file)).utc();
        // A real Windows handle denying read sharing reproduces the generic
        // FileSystemException seen during native atomic publication. No mocked
        // exception/message matching and no games or external helper process.
        try(var held=FileChannel.open(file,StandardOpenOption.READ,ExtendedOpenOption.NOSHARE_READ,
                ExtendedOpenOption.NOSHARE_WRITE,ExtendedOpenOption.NOSHARE_DELETE)){
            try(var attempted=FileChannel.open(file,StandardOpenOption.READ)){throw new AssertionError("Windows sharing fixture did not exclude readers");}
            catch(FileSystemException conflict){check(conflict.getClass()==FileSystemException.class,"Actual sharing violation is generic FileSystemException");}
            long begun=System.nanoTime();
            for(int i=0;i<32;i++)check(GameplayCombatSnapshot.read(file)==null,"Sharing conflict is unavailable without failing validation");
            check(System.nanoTime()-begun<2_000_000_000L,"Unavailable reads return promptly for ongoing guest publication");
        }
        var resumed=parse(GameplayCombatSnapshot.read(file));
        check(resumed.seq()==1&&resumed.utc()==sourceUtc,"Read resumes after handle closes without retimestamping source");
        check(!resumed.fresh(sourceUtc+501),"Recovery cannot renew an expired source snapshot");
        System.out.println("Combat snapshot Windows sharing: generic FileSystemException reproduced,32 unavailable reads, unchanged source deadline");
    }
    private static JsonObject snapshot(){
        var j=GameplayCombatProtocol.identity(ID,WORLD,SURFACE,"minecome_gameplay_combat_host_v1");j.addProperty("seq",1);j.addProperty("utc_ms",NOW);j.addProperty("hit_ack",0);
        var actors=new JsonArray();var a=new JsonObject();a.addProperty("token",1);a.addProperty("x",122.5);a.addProperty("y",2045.25);a.addProperty("z",56.75);a.addProperty("width",.6);a.addProperty("height",1.8);a.addProperty("health",100);a.addProperty("max_health",100);a.addProperty("alive",true);actors.add(a);j.add("actors",actors);
        var hurts=new JsonArray();var h=new JsonObject();h.addProperty("seq",1);h.addProperty("attacker_token",1);h.addProperty("damage",4);h.addProperty("kind","melee");hurts.add(h);j.add("hurts",hurts);return j;
    }
}
