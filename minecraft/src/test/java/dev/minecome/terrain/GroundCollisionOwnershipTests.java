package dev.minecome.terrain;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Box;
import net.minecraft.util.shape.VoxelShapes;
import net.minecraft.world.BlockView;

import java.lang.reflect.Proxy;
import java.nio.charset.StandardCharsets;

/** No world/game startup: immutable collision installations and exact scoped release. */
public final class GroundCollisionOwnershipTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static BlockView world(){
        return (BlockView)Proxy.newProxyInstance(BlockView.class.getClassLoader(),new Class<?>[]{BlockView.class},
                (proxy,method,args)->{throw new AssertionError("Unexpected game-world API call: "+method.getName());});
    }
    private static GroundPatch patch() throws Exception {return patch(0);}
    private static GroundPatch patch(double height) throws Exception {
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("run","owned-fixture");p.addProperty("grid_size",5);p.addProperty("spacing",1);
        var center=new JsonObject();center.addProperty("x",0);center.addProperty("y",0);center.addProperty("z",0);p.add("center",center);
        var provenance=new JsonObject();provenance.addProperty("kind","standalone_fixture");p.add("provenance",provenance);
        var points=new JsonArray();
        for(int row=0;row<5;row++)for(int col=0;col<5;col++){
            var point=new JsonObject();point.addProperty("index",row*5+col+1);point.addProperty("x",col-2);point.addProperty("y",row-2);
            point.addProperty("z",height);point.addProperty("nx",0);point.addProperty("ny",0);point.addProperty("nz",1);points.add(point);
        }
        p.add("points",points);return GroundPatch.parse(p.toString().getBytes(StandardCharsets.UTF_8));
    }
    public static void main(String[] args)throws Exception {
        GroundCollision.clear();
        var client=world();var server=world();var stranger=world();var patch=patch();var cell=patch.cells().getFirst();
        var position=new BlockPos(cell.x(),cell.y(),cell.z());var empty=VoxelShapes.empty();
        check(GroundCollision.available(false)&&GroundCollision.available(true),"Both sides initially unclaimed");
        GroundCollision.install(client,patch,false);GroundCollision.install(server,patch,true);
        check(!GroundCollision.available(false)&&!GroundCollision.available(true),"Installed sides cannot be claimed");
        check(!GroundCollision.merge(client,position,empty).isEmpty(),"Client proxy exists");
        check(!GroundCollision.merge(server,position,empty).isEmpty(),"Server proxy exists");
        check(GroundCollision.merge(stranger,position,empty)==empty,"Unrelated world gets original collision");
        check(!GroundCollision.clear(stranger,patch.run(),false),"Wrong client world cannot clear");
        check(!GroundCollision.clear(client,"another-run",false),"Wrong run cannot clear");
        check(!GroundCollision.clear(client,patch.run(),true),"Wrong side cannot clear");
        check(GroundCollision.installed(client,false)&&GroundCollision.installed(server,true),"Failed cleanup preserves both installations");
        check(GroundCollision.clear(client,patch.run(),false),"Exact client installation released");
        check(GroundCollision.available(false)&&!GroundCollision.available(true),"Client release does not clear server");
        check(GroundCollision.merge(client,position,empty)==empty,"Released client has no proxy shape");
        check(!GroundCollision.clear(client,patch.run(),false),"Released installation is not claimed again");
        check(GroundCollision.clear(server,patch.run(),true),"Exact server installation released");
        check(GroundCollision.available(false)&&GroundCollision.available(true),"Both sides released");
        GroundSurface corridor=GroundCorridor.parse(GroundCorridorTests.bytes(GroundCorridorTests.fixture("standalone_fixture",0)));
        GroundCollision.install(client,corridor,false);GroundCollision.install(server,corridor,true);
        check(GroundCollision.matches(client,corridor,false)&&GroundCollision.matches(server,corridor,true),"Both worlds publish the same composite owner");
        check(!GroundCollision.merge(client,new BlockPos(6,63,0),empty).isEmpty(),"Collision exists beyond the original patch boundary");
        check(GroundCollision.merge(client,new BlockPos(8,63,0),empty)==empty,"Composite collision remains bounded");
        try{GroundCollision.install(stranger,corridor,false);throw new AssertionError("Corridor replaced existing owner");}
        catch(IllegalStateException expected){checks++;}
        check(GroundCollision.matches(client,corridor,false),"Failed composite installation preserves original map");
        check(!GroundCollision.clear(client,corridor.run(),"0".repeat(64),false),"Wrong manifest digest cannot release composite");
        check(!GroundCollision.clear(stranger,corridor.run(),corridor.sha256(),false),"Wrong world cannot release composite");
        check(GroundCollision.clear(client,corridor.run(),corridor.sha256(),false),"Exact composite client owner released");
        check(GroundCollision.installed(server,true),"Client release preserves composite server");
        check(GroundCollision.clear(server,corridor.run(),corridor.sha256(),true),"Exact composite server owner released");
        var fractional=patch(.875);GroundCollision.install(server,fractional,true);
        var buried=new Box(.375,64.5,.375,.625,64.75,.625);
        check(Math.abs(GroundCollision.itemLift(server,buried,false)-.37501)<.000001,"Fractional slab overlap has bounded upward recovery");
        var below=new Box(.375,64.125,.375,.625,64.375,.625);
        check(Math.abs(GroundCollision.itemLift(server,below,true)-.75001)<.000001,"Fresh vanilla drop beneath thin slab recovers inside its placement cell");
        check(GroundCollision.itemLift(server,below,false)==0,"Old nonoverlapping below-ground item is not lifted");
        check(GroundCollision.itemLift(stranger,buried,true)==0,"Foreign world cannot recover an item");
        check(GroundCollision.itemLift(client,buried,true)==0,"Server recovery does not run in client world");
        check(GroundCollision.itemLift(server,buried.offset(0,.375,0),true)==0,"Item on the terrain top remains untouched");
        check(GroundCollision.itemLift(server,buried.offset(0,1,0),true)==0,"Airborne item remains untouched");
        check(GroundCollision.itemLift(server,buried.offset(1.5,0,0),true)==0,"Unknown footprint edge is refused");
        check(GroundCollision.itemLift(server,buried.offset(0,-2,0),true)==0,"Unbounded recovery is refused");
        check(GroundCollision.itemLift(server,new Box(0,64,0,1,65,1),true)==0,"Player-size body is outside item recovery");
        check(GroundCollision.clear(server,fractional.run(),true),"Fractional test owner releases");
        check(GroundCollision.itemLift(server,buried,true)==0,"Cleared world cannot recover an item");
        System.out.println("GROUND_COLLISION_OWNERSHIP_TESTS_PASS checks="+checks);
    }
}
