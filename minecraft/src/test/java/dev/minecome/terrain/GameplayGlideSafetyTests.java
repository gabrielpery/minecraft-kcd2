package dev.minecome.terrain;

import java.nio.charset.StandardCharsets;
import net.minecraft.util.math.Vec3d;

/** Real captured geometry admission, including fast swept motion across a coverage hole. */
public final class GameplayGlideSafetyTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static GroundPatch patch(int x,int z)throws Exception{
        return GroundPatch.parse(GameplayTerrainTests.patch(x,z).toString().getBytes(StandardCharsets.UTF_8),true);
    }
    private static String refusal(GroundSurface surface,double x,double y,double z,double dx,double dy,double dz){
        return GameplayGlideSafety.refusal(surface,new Vec3d(x,y,z),new Vec3d(dx,dy,dz));
    }
    public static void main(String[] args)throws Exception{
        var base=patch(0,0);var terrain=GameplayTerrain.initial(base);
        check(refusal(terrain,0,68,0,1.5,-.2,0)==null,"ordinary vanilla glide admitted");
        check(refusal(terrain,-1,68,0,4,0,0)==null,"bounded80m/s step admitted inside known terrain");
        check("speed_cap".equals(refusal(terrain,0,68,0,4.00001,0,0)),"step cannot exceed native glide profile");
        check("speed_cap".equals(refusal(terrain,0,68,0,3,3,0)),"speed cap includes all axes");
        check("unknown_terrain".equals(refusal(terrain,3.5,68,0,.3,0,0)),"body footprint cannot cross unknown frontier");
        check(refusal(terrain,3.5,68,0,-.3,0,0)==null,"turning inward after frontier hold can recover");
        check("ceiling".equals(refusal(terrain,0,81.9,0,0,.2,0)),"upward next step cannot cross flight ceiling");
        check(refusal(terrain,0,82,0,0,-.2,0)==null,"exact ceiling allows descent");
        check(refusal(terrain,0,64.1,0,0,-3,0)==null,"downward ground contact remains vanilla swept collision");
        check("below_terrain".equals(refusal(terrain,0,63,0,0,0,0)),"invalid below-floor start refused");
        check("invalid_motion".equals(refusal(terrain,0,68,0,Double.NaN,0,0)),"nonfinite velocity refused");
        check("invalid_motion".equals(refusal(terrain,Double.POSITIVE_INFINITY,68,0,0,0,0)),"nonfinite position refused");
        var east=terrain.admit(1,0,patch(1,0));
        check(refusal(east,3.5,68,0,2.5,-.1,0)==null,"admitted expansion opens former frontier");
        var corner=east.admit(0,1,patch(0,1));
        check(corner.containsFeet(5,3,.31)&&corner.containsFeet(3,5,.31),"hole test endpoints are both individually covered");
        check("unknown_terrain".equals(refusal(corner,5,68,3,-2,0,2)),"sweep cannot cut missing corner despite covered endpoints");
        var filled=corner.admit(1,1,patch(1,1));
        check(refusal(filled,5,68,3,-2,0,2)==null,"same sweep works after missing tile is captured");
        check(refusal(base,0,68,0,1,-.1,0)==null,"single-patch gameplay remains supported");
        System.out.println("GameplayGlideSafetyTests: "+checks+" checks passed; no games");
    }
}
