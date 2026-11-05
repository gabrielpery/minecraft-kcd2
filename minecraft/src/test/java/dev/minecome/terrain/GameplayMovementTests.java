package dev.minecome.terrain;

import com.google.gson.*;
import dev.minecome.gameplay.GameplayWorld;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;

/** Ongoing hold leases, frontier braking and persistent coordinate identity. */
public final class GameplayMovementTests {
    private static int checks;
    private static void check(boolean ok,String why){checks++;if(!ok)throw new AssertionError(why);}
    private static void reject(Action a,String why)throws Exception{try{a.run();throw new AssertionError(why);}catch(java.io.IOException expected){checks++;}}
    private interface Action{void run()throws Exception;}
    public static void main(String[] args)throws Exception{
        var keys=new GameplayMovementKeys();long now=1_000_000_000L;keys.authority(now,true);check(keys.event(1,'W',now,true),"initial press");
        for(int i=1;i<=1000;i++){now+=50_000_000L;keys.authority(now,true);}
        check(keys.down('W',now),"ongoing50second hold must not reach demo expiry");
        keys.authority(now,false);keys.authority(now+1,true);check(!keys.down('W',now+1),"inventory suspends held input");check(!keys.event(1,'A',now+1,true),"held raw input cannot silently resume");
        keys.event(2,'W',now+2,true);keys.event(2,'A',now+2,true);check(keys.event(1,'D',now+3,true),"balanced release permits new press");
        check(!keys.down('D',now+GameplayMovementKeys.LEASE_NS+2),"authority expires promptly");
        var flyingKeys=new GameplayMovementKeys(true);flyingKeys.authority(now,true);
        flyingKeys.event(1,0x20,now,true);flyingKeys.event(2,0x20,now,true);flyingKeys.event(1,0x20,now,true);flyingKeys.event(2,0x20,now,true);
        for(boolean expected:new boolean[]{true,false,true,false}){flyingKeys.authority(now,true);flyingKeys.tick(now);check(flyingKeys.down(0x20,now)==expected,"batched double tap reaches four distinct vanilla ticks");now+=50_000_000;}
        flyingKeys.event(1,0x20,now,true);flyingKeys.event(2,0x20,now,true);flyingKeys.suspend();flyingKeys.authority(now+1,true);flyingKeys.tick(now+1);check(!flyingKeys.down(0x20,now+1),"UI handoff discards queued jump taps");
        flyingKeys.event(1,0x20,now+1,true);flyingKeys.event(2,0x20,now+1,true);flyingKeys.tick(now+GameplayMovementKeys.LEASE_NS+2);check(!flyingKeys.down(0x20,now+GameplayMovementKeys.LEASE_NS+2),"queued released taps cannot survive lease expiry");
        flyingKeys.authority(now+GameplayMovementKeys.LEASE_NS+3,true);check(flyingKeys.event(1,0x10,now+GameplayMovementKeys.LEASE_NS+3,true),"flight descent lease");check(flyingKeys.event(1,0x11,now+GameplayMovementKeys.LEASE_NS+3,true),"flight sprint lease");flyingKeys.close();check(!flyingKeys.down(0x10,now+GameplayMovementKeys.LEASE_NS+4)&&!flyingKeys.down(0x11,now+GameplayMovementKeys.LEASE_NS+4),"flight controls released on close");
        Path root=Files.createTempDirectory("minecome-gameplay-movement-");Path saves=root.resolve("runtime/instance/saves");
        var world=GameplayWorld.prepare(saves,root);Files.write(world.directory().resolve("level.dat"),new byte[]{1});
        Path patchFile=root.resolve("ground.json");Files.writeString(patchFile,patch().toString(),StandardCharsets.UTF_8);
        var binding=GameplayTerrainBinding.open(world,patchFile,true);check(binding.resume()==null,"first attach has no old location");
        var surface=binding.surface();var gate=new GameplayBoundary(surface);
        check(gate.allows(new GameplayBoundary.Motion(0,64,0,0,0,0,true),1,0,false,-90,.13),"center permits vanilla walking");
        check(!gate.allows(new GameplayBoundary.Motion(3.5,64,0,.1,0,0,true),1,0,false,-90,.13),"unknown terrain frontier stops acceleration");
        check(gate.allowsFlight(new GameplayBoundary.Motion(0,67,0,0,0,0,false),1,0,1,-90,.05,true),"default sprint flight and climb admitted at centre");
        check(!gate.allowsFlight(new GameplayBoundary.Motion(3.2,67,0,.3,0,0,false),1,0,0,-90,.05,true),"sprint flight braking envelope cannot leave terrain");
        check(!gate.allowsFlight(new GameplayBoundary.Motion(0,81.8,0,0,.12,0,false),0,0,1,0,.05,false),"flight ceiling includes future vertical coast");
        check(gate.allowsFlight(new GameplayBoundary.Motion(0,81.8,0,0,0,0,false),0,0,-1,0,.05,false),"flight ceiling allows descent");
        check(gate.allowsFlight(new GameplayBoundary.Motion(0,82,0,0,0,0,false),0,0,-1,0,.05,false),"exact ceiling checkpoint can descend");
        check(!gate.allowsFlight(new GameplayBoundary.Motion(0,81.8,0,0,.12,0,false),0,0,0,0,.05,false),"neutral upward coast still requires a safe stopping envelope");
        check(gate.allowsFlight(new GameplayBoundary.Motion(0,64.1,0,0,-.2,0,false),0,0,-1,0,.05,false),"landing uses actual ground collision");
        check(!gate.allowsFlight(new GameplayBoundary.Motion(0,67,0,0,0,0,false),0,0,0,0,.1,false),"boosted nondefault flight speed stays outside native speed contract");
        binding.checkpoint(new GameplayTerrainBinding.Position(.5,64,-.25,40,2));
        var reopened=GameplayTerrainBinding.open(GameplayWorld.prepare(saves,root),binding.patchFile(),true);
        check(reopened.resume().x()==.5&&reopened.resume().z()==-.25,"resume retains last position rather than origin");
        check(reopened.surface().centerX()==100&&reopened.surface().centerY()==200&&reopened.surface().centerZ()==50,"host origin stable");
        reject(()->binding.checkpoint(new GameplayTerrainBinding.Position(4,64,0,0,0)),"checkpoint outside terrain refused");
        var aerial=GameplayTerrainBinding.open(world,patchFile,true,true,false,true);aerial.checkpoint(new GameplayTerrainBinding.Position(.5,68,-.25,40,2,true));
        var resumedFlight=GameplayTerrainBinding.open(world,patchFile,true,true,false,true);check(resumedFlight.resume().flying()&&resumedFlight.resume().y()==68,"aerial checkpoint retains position and explicit flight tag");
        reject(()->GameplayTerrainBinding.open(world,patchFile,true,true,false),"walking profile cannot load aerial checkpoint");
        reject(()->aerial.checkpoint(new GameplayTerrainBinding.Position(.5,82.1,-.25,40,2,true)),"aerial checkpoint cannot exceed native envelope");
        aerial.checkpoint(new GameplayTerrainBinding.Position(.5,67,-.25,40,2,false,true,1.25f));
        var resumedFall=GameplayTerrainBinding.open(world,patchFile,true,true,false,true);check(resumedFall.resume().falling()&&!resumedFall.resume().flying()&&resumedFall.resume().fallDistance()==1.25f,"midfall save replaces stale flying tag and retains existing fall distance");
        reject(()->GameplayTerrainBinding.open(world,patchFile,true,true,false),"walking profile cannot load a falling checkpoint");
        aerial.checkpoint(new GameplayTerrainBinding.Position(.5,64,-.25,40,2));check(!GameplayTerrainBinding.open(world,patchFile,true).resume().flying(),"landed checkpoint remains compatible with previous walking profile");
        var changed=patch();changed.getAsJsonObject("center").addProperty("z",51);for(var point:changed.getAsJsonArray("points"))point.getAsJsonObject().addProperty("z",51);
        Path other=root.resolve("changed.json");Files.writeString(other,changed.toString());reject(()->GameplayTerrainBinding.open(world,other,true),"new capture cannot silently move established origin");
        var marker=JsonParser.parseString(Files.readString(world.directory().resolve("minecome-terrain/binding.json"))).getAsJsonObject();marker.addProperty("world_id","foreign");Files.writeString(world.directory().resolve("minecome-terrain/binding.json"),marker.toString());
        reject(()->GameplayTerrainBinding.open(world,patchFile,true),"foreign saved binding refused");
        System.out.println("GameplayMovementTests: "+checks+" checks passed; no games");
    }
    private static JsonObject patch(){
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("run","0123456789abcdef0123456789abcdef");p.addProperty("grid_size",9);p.addProperty("spacing",1);p.addProperty("walking_area","wide");
        var c=new JsonObject();c.addProperty("x",100);c.addProperty("y",200);c.addProperty("z",50);p.add("center",c);var provenance=new JsonObject();provenance.addProperty("kind","standalone_fixture");p.add("provenance",provenance);var points=new JsonArray();
        for(int row=0;row<9;row++)for(int col=0;col<9;col++){var q=new JsonObject();q.addProperty("index",row*9+col+1);q.addProperty("x",100+col-4);q.addProperty("y",200+row-4);q.addProperty("z",50);q.addProperty("nx",0);q.addProperty("ny",0);q.addProperty("nz",1);points.add(q);}p.add("points",points);return p;
    }
}
