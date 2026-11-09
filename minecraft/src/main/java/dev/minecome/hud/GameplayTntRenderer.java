package dev.minecome.hud;

import com.mojang.blaze3d.systems.RenderSystem;
import dev.minecome.gameplay.GameplayTnt;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.VertexConsumerProvider;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.entity.TntEntity;
import net.minecraft.util.TypeFilter;
import net.minecraft.util.math.Box;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

/** Admitted, client-tracked primed TNT in the owned world colour/depth pass.
 * Inspected Yarn1.21.1+build.3: TntEntityRenderer.render uses the actual tracked
 * block state and fuse for vanilla flashing and the final fuse-based scale.
 * Interpolate the WorldRenderer entity base and call the registered renderer
 * directly, avoiding dispatcher ground shadows and debug geometry.
 * Bytecode evidence: runtime/evidence/tnt-render-source-20261109/.
 * Admission/explosion authority remains with GameplayTnt, not this renderer.
 */
public final class GameplayTntRenderer {
    public static final int MAX_TNT=16;
    public static final double MAX_DISTANCE=64;
    /** Submitted entity identity and interpolated base, not visible-pixel proof. */
    public record Tnt(UUID id,int fuse,double x,double y,double z){}
    private GameplayTntRenderer(){}

    static List<Tnt> render(float tickDelta,Vec3d origin,GroundSurface surface,
                            MatrixStack matrices,VertexConsumerProvider vertices){
        RenderSystem.assertOnRenderThread();
        var client=MinecraftClient.getInstance();var world=client.world;var player=client.player;
        if(world==null||player==null||player.getWorld()!=world||surface==null||!GameplaySession.worldBlocksEnabled()||
                !finite(origin)||!Float.isFinite(tickDelta))return List.of();
        var bounds=new Box(origin.x-MAX_DISTANCE,origin.y-MAX_DISTANCE,origin.z-MAX_DISTANCE,
                           origin.x+MAX_DISTANCE,origin.y+MAX_DISTANCE,origin.z+MAX_DISTANCE);
        var candidates=new ArrayList<TntEntity>();
        // Bounded spatial collection and exact controller admission prevent
        // unrelated TNT or another world's matching UUID from becoming visible.
        world.collectEntitiesByType(TypeFilter.instanceOf(TntEntity.class),bounds,
            tnt->tnt.getWorld()==world&&!tnt.isRemoved()&&!tnt.isInvisible()&&GameplayTnt.renderAllowed(tnt)&&
                finite(tnt.getPos())&&tnt.squaredDistanceTo(origin)<=MAX_DISTANCE*MAX_DISTANCE&&
                world.isChunkLoaded(tnt.getBlockPos())&&surface.containsFeet(tnt.getX(),tnt.getZ(),0),
            candidates,MAX_TNT);
        candidates.sort(Comparator.comparingDouble((TntEntity tnt)->tnt.squaredDistanceTo(origin)).thenComparingInt(TntEntity::getId));
        var submitted=new ArrayList<Tnt>(candidates.size());var dispatcher=client.getEntityRenderDispatcher();
        for(var tnt:candidates){
            double x=MathHelper.lerp(tickDelta,tnt.lastRenderX,tnt.getX());
            double y=MathHelper.lerp(tickDelta,tnt.lastRenderY,tnt.getY());
            double z=MathHelper.lerp(tickDelta,tnt.lastRenderZ,tnt.getZ());
            if(!Double.isFinite(x)||!Double.isFinite(y)||!Double.isFinite(z)||!surface.containsFeet(x,z,0)||
                    (x-origin.x)*(x-origin.x)+(y-origin.y)*(y-origin.y)+(z-origin.z)*(z-origin.z)>MAX_DISTANCE*MAX_DISTANCE)continue;
            float yaw=MathHelper.lerp(tickDelta,tnt.prevYaw,tnt.getYaw());if(!Float.isFinite(yaw))continue;
            var renderer=dispatcher.getRenderer(tnt);var offset=renderer.getPositionOffset(tnt,tickDelta);
            if(!finite(offset))continue;
            matrices.push();
            try{
                matrices.translate(x-origin.x+offset.x,y-origin.y+offset.y,z-origin.z+offset.z);
                renderer.render(tnt,yaw,tickDelta,matrices,vertices,dispatcher.getLight(tnt,tickDelta));
            }finally{matrices.pop();}
            submitted.add(new Tnt(tnt.getUuid(),tnt.getFuse(),x,y,z));
        }
        return List.copyOf(submitted);
    }
    private static boolean finite(Vec3d v){return v!=null&&Double.isFinite(v.x)&&Double.isFinite(v.y)&&Double.isFinite(v.z);}
}
