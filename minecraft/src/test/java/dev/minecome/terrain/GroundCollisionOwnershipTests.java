package dev.minecome.terrain;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import net.minecraft.util.math.BlockPos;
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
    private static GroundPatch patch() throws Exception {
        var p=new JsonObject();p.addProperty("schema",1);p.addProperty("run","owned-fixture");p.addProperty("grid_size",5);p.addProperty("spacing",1);
        var center=new JsonObject();center.addProperty("x",0);center.addProperty("y",0);center.addProperty("z",0);p.add("center",center);
        var provenance=new JsonObject();provenance.addProperty("kind","standalone_fixture");p.add("provenance",provenance);
        var points=new JsonArray();
        for(int row=0;row<5;row++)for(int col=0;col<5;col++){
            var point=new JsonObject();point.addProperty("index",row*5+col+1);point.addProperty("x",col-2);point.addProperty("y",row-2);
            point.addProperty("z",0);point.addProperty("nx",0);point.addProperty("ny",0);point.addProperty("nz",1);points.add(point);
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
        System.out.println("GROUND_COLLISION_OWNERSHIP_TESTS_PASS checks="+checks);
    }
}
