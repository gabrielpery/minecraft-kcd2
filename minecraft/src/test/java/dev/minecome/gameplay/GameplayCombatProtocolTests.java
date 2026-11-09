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
        projectileReplies();snapshotFiles();
        checks+=GameplayProjectileInterpolationTests.run();
        checks+=GameplayBlastTests.run();
        System.out.println("GameplayCombatProtocolTests: "+checks+" checks passed; no games");
    }
    private static void projectileReplies(){
        var envelope=GameplayCombatProtocol.identity(ID,WORLD,SURFACE,"minecome_gameplay_projectiles_host_v1");envelope.addProperty("seq",1);envelope.addProperty("utc_ms",NOW);envelope.addProperty("request_utc_ms",NOW-30);
        var reply=new JsonObject();reply.addProperty("operation","trace");reply.addProperty("projectile","d".repeat(32));reply.addProperty("segment",1);reply.addProperty("result","clear");reply.addProperty("reason","");reply.addProperty("actor_token",0);
        var zero=new JsonObject();zero.addProperty("x",0);zero.addProperty("y",0);zero.addProperty("z",0);reply.add("contact",zero.deepCopy());reply.add("normal",zero.deepCopy());reply.add("actor",JsonNull.INSTANCE);reply.add("before",JsonNull.INSTANCE);reply.add("after",JsonNull.INSTANCE);envelope.add("reply",reply);
        check(projectile(envelope.toString()).result().equals("clear"),"Native clear trajectory accepted with explicit null outcomes");
        for(String key:envelope.keySet()){var changed=envelope.deepCopy();changed.remove(key);rejectProjectile(changed.toString(),"Missing projectile root "+key);rejectProjectile(envelope.toString().replaceFirst("\\{","{\""+key+"\":"+envelope.get(key)+","),"Duplicate projectile root "+key);}
        for(String key:reply.keySet()){var changed=envelope.deepCopy();changed.getAsJsonObject("reply").remove(key);rejectProjectile(changed.toString(),"Missing projectile reply "+key);}
        for(String key:List.of("run","world_id","patch_run","patch_sha256","target_start_filetime")){var changed=envelope.deepCopy();changed.addProperty(key,"foreign");rejectProjectile(changed.toString(),"Foreign projectile owner "+key);}
        for(String raw:List.of("\"1\"","1.0","1e0","-1","true","null"))rejectProjectile(envelope.toString().replace("\"seq\":1","\"seq\":"+raw),"Exact projectile sequence "+raw);
        var scene=envelope.deepCopy();scene.getAsJsonObject("reply").addProperty("result","scenery");rejectProjectile(scene.toString(),"Scenery needs a real normal");scene.getAsJsonObject("reply").getAsJsonObject("normal").addProperty("z",1);check(projectile(scene.toString()).result().equals("scenery"),"Scenery contact admitted");
        var actor=envelope.deepCopy();var a=snapshot().getAsJsonArray("actors").get(0).deepCopy();actor.getAsJsonObject("reply").addProperty("result","actor");actor.getAsJsonObject("reply").addProperty("actor_token",1);actor.getAsJsonObject("reply").add("actor",a);check(projectile(actor.toString()).actor().token()==1,"Native actor generation and geometry admitted");
        var wrong=actor.deepCopy();wrong.getAsJsonObject("reply").addProperty("actor_token",2);rejectProjectile(wrong.toString(),"Actor token mismatch");wrong=actor.deepCopy();wrong.getAsJsonObject("reply").getAsJsonObject("actor").addProperty("alive",false);rejectProjectile(wrong.toString(),"Dead actor cannot admit arrow trace");
        var impact=actor.deepCopy();var h=impact.getAsJsonObject("reply");h.addProperty("operation","impact");h.addProperty("result","damaged");h.addProperty("before",100);h.addProperty("after",0);h.getAsJsonObject("actor").addProperty("health",0);h.getAsJsonObject("actor").addProperty("alive",false);check(projectile(impact.toString()).after()==0,"Lethal native impact accepted with dead actor snapshot");
        wrong=impact.deepCopy();wrong.getAsJsonObject("reply").addProperty("after",101);rejectProjectile(wrong.toString(),"Native damage cannot heal");wrong=impact.deepCopy();wrong.getAsJsonObject("reply").add("before",JsonNull.INSTANCE);rejectProjectile(wrong.toString(),"Damage needs real outcome");
        var refused=envelope.deepCopy();refused.getAsJsonObject("reply").addProperty("operation","impact");refused.getAsJsonObject("reply").addProperty("result","rejected");refused.getAsJsonObject("reply").addProperty("reason","stale_contact");check(projectile(refused.toString()).result().equals("rejected"),"Rejected impact may have no actor/outcome");
        for(String raw:List.of("true","\"1\"","1e999","null"))rejectProjectile(scene.toString().replace("\"z\":1","\"z\":"+raw),"Invalid native normal "+raw);
        var request=new GameplayProjectileProtocol.Request(3,NOW,"impact","d".repeat(32),2,new GameplayCombatProtocol.Point(1,2,3),new GameplayCombatProtocol.Point(2,3,4),1,7);
        var encoded=GameplayProjectileProtocol.request(request,ID,WORLD,SURFACE);check(encoded.getAsJsonObject("request").get("damage_fraction").getAsDouble()==.35,"Actual vanilla projectile damage normalization preserved");
        for(String bad:List.of("null","[]","{}",envelope+"{}"," ".repeat(8193)))rejectProjectile(bad,"Bounded projectile document");
    }
    private static GameplayProjectileProtocol.Reply projectile(String text){return GameplayProjectileProtocol.parse(text,ID,WORLD,SURFACE);}
    private static void rejectProjectile(String text,String reason){try{projectile(text);throw new AssertionError(reason);}catch(IllegalArgumentException expected){checks++;}}
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
