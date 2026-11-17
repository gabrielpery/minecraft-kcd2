package dev.minecome.terrain;

import com.google.gson.JsonObject;
import java.util.Objects;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.entity.LivingEntity;
import net.minecraft.util.math.Vec3d;

/** A gameplay-owned frontier/authority hold around otherwise vanilla Elytra travel. */
public final class GameplayGlideSafety {
    /** Four blocks per vanilla tick: the matching native glide profile allows80m/s. */
    public static final double MAX_STEP=4;
    private static final double RADIUS=.31;
    private static Ownership owner;
    private static final class Ownership {
        final ClientPlayerEntity player;
        final ClientWorld world;
        GroundSurface surface;
        boolean held=true;
        long travelTicks,heldTicks,stepChecks,acceptedSteps,boundaryHolds;
        String lastReason="held";
        Ownership(ClientPlayerEntity player,GroundSurface surface){this.player=player;world=(ClientWorld)player.getWorld();this.surface=surface;}
    }
    private GameplayGlideSafety(){}
    public static void install(ClientPlayerEntity player,GroundSurface surface){
        requireLocal(player);Objects.requireNonNull(surface);
        if(owner!=null)throw new IllegalStateException("Existing glide safety owner preserved");
        owner=new Ownership(player,surface);
    }
    public static boolean setHeld(ClientPlayerEntity player,boolean held){
        var own=owned(player);if(own==null)return false;
        requireLocal(player);own.held=held;return true;
    }
    public static boolean updateSurface(ClientPlayerEntity player,GroundSurface surface){
        var own=owned(player);if(own==null)return false;
        requireLocal(player);Objects.requireNonNull(surface);
        if(own.surface!=surface&&!(own.surface instanceof GameplayTerrain before&&surface instanceof GameplayTerrain next&&next.isSuccessorOf(before)))
            throw new IllegalArgumentException("Glide terrain requires the exact additive successor");
        own.surface=surface;return true;
    }
    public static boolean clear(ClientPlayerEntity player){
        var own=owner;if(own==null||own.player!=player)return false;
        if(!MinecraftClient.getInstance().isOnThread())throw new IllegalStateException("Glide release requires the client thread");
        owner=null;return true;
    }
    private static void requireLocal(ClientPlayerEntity player){
        var client=MinecraftClient.getInstance();
        if(!client.isOnThread()||player==null||client.player!=player||client.world!=player.getWorld())
            throw new IllegalStateException("Glide safety requires the exact local player and client thread");
    }
    private static Ownership owned(LivingEntity entity){
        var own=owner;
        return own!=null&&own.player==entity&&entity.getWorld()==own.world?own:null;
    }
    /** HEAD cancellation keeps vanilla from regenerating drift during a UI/lease hold. */
    public static boolean holdTravel(LivingEntity entity){
        var own=owned(entity);if(own==null||!entity.isFallFlying())return false;
        own.travelTicks++;
        if(own.held){own.heldTicks++;own.lastReason="held";return true;}
        var velocity=entity.getVelocity();
        if(!finite(velocity)||velocity.lengthSquared()>MAX_STEP*MAX_STEP)return refuse(own,"speed_cap");
        return false;
    }
    /** Called after vanilla computes glide lift/turning/drag, immediately before its swept move. */
    public static boolean holdMove(LivingEntity entity){
        var own=owned(entity);if(own==null||!entity.isFallFlying())return false;
        own.stepChecks++;
        String refusal=refusal(own.surface,entity.getPos(),entity.getVelocity());
        if(refusal!=null)return refuse(own,refusal);
        own.acceptedSteps++;own.lastReason="none";return false;
    }
    private static boolean refuse(Ownership own,String reason){
        own.boundaryHolds++;own.lastReason=reason;own.player.setVelocity(Vec3d.ZERO);return true;
    }
    /** Full one-tick sweep, including interior holes; descending contact is resolved by vanilla collision. */
    static String refusal(GroundSurface surface,Vec3d position,Vec3d step){
        if(surface==null||!finite(position)||!finite(step))return "invalid_motion";
        if(step.lengthSquared()>MAX_STEP*MAX_STEP)return "speed_cap";
        double minX=Math.min(position.x,position.x+step.x)-RADIUS,maxX=Math.max(position.x,position.x+step.x)+RADIUS;
        double minZ=Math.min(position.z,position.z+step.z)-RADIUS,maxZ=Math.max(position.z,position.z+step.z)+RADIUS;
        boolean covered=surface instanceof GameplayTerrain terrain?terrain.containsRectangle(minX,minZ,maxX,maxZ):
                surface.containsFeet(minX,minZ,0)&&surface.containsFeet(maxX,maxZ,0);
        if(!covered)return "unknown_terrain";
        if(position.y>GameplayBoundary.FLIGHT_MAX_Y||position.y+step.y>GameplayBoundary.FLIGHT_MAX_Y)return "ceiling";
        double floor=surface.groundForFeet(position.x,position.z,.3);
        if(!Double.isFinite(floor)||position.y<floor-.2)return "below_terrain";
        return null;
    }
    private static boolean finite(Vec3d vector){return vector!=null&&Double.isFinite(vector.x)&&Double.isFinite(vector.y)&&Double.isFinite(vector.z);}
    public static JsonObject evidence(){
        var j=new JsonObject();var own=owner;j.addProperty("installed",own!=null);
        if(own!=null){j.addProperty("held",own.held);j.addProperty("travel_ticks",own.travelTicks);j.addProperty("held_ticks",own.heldTicks);
            j.addProperty("step_checks",own.stepChecks);j.addProperty("accepted_steps",own.acceptedSteps);j.addProperty("boundary_holds",own.boundaryHolds);j.addProperty("last_reason",own.lastReason);}
        return j;
    }
}
