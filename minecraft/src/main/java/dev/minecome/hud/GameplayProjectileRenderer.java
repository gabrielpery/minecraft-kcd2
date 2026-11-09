package dev.minecome.hud;

import com.mojang.blaze3d.systems.RenderSystem;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.VertexConsumerProvider;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.entity.projectile.PersistentProjectileEntity;
import net.minecraft.registry.Registries;
import net.minecraft.util.TypeFilter;
import net.minecraft.util.math.Box;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

/** Real tracked, locally owned projectiles in the existing world colour/depth pass.
 * Inspected Yarn1.21.1+build.3: ProjectileEntity.onSpawnPacket resolves the owner
 * from the packet's entity data; ProjectileEntityRenderer uses the actual yaw,
 * pitch and shake with its registered vanilla texture/model. As for dropped
 * items, interpolate the WorldRenderer base and invoke the registered renderer
 * directly to avoid adding dispatcher ground shadows/debug geometry.
 * Evidence: runtime/evidence/projectile-render-source-20261109/.
 * This renderer neither spawns projectiles nor establishes native collision.
 */
public final class GameplayProjectileRenderer {
    public static final int MAX_PROJECTILES=64;
    public static final double MAX_DISTANCE=64;
    /** Submitted geometry, not proof that depth-tested pixels were visible. */
    public record Projectile(UUID id,String type,UUID owner,double x,double y,double z){}
    private GameplayProjectileRenderer(){}

    static List<Projectile> render(float tickDelta,Vec3d origin,GroundSurface surface,
                                   MatrixStack matrices,VertexConsumerProvider vertices){
        RenderSystem.assertOnRenderThread();
        var client=MinecraftClient.getInstance();var world=client.world;var player=client.player;
        if(world==null||player==null||player.getWorld()!=world||surface==null||!GameplaySession.worldBlocksEnabled()||
                !finite(origin)||!Float.isFinite(tickDelta))return List.of();
        var bounds=new Box(origin.x-MAX_DISTANCE,origin.y-MAX_DISTANCE,origin.z-MAX_DISTANCE,
                           origin.x+MAX_DISTANCE,origin.y+MAX_DISTANCE,origin.z+MAX_DISTANCE);
        var candidates=new ArrayList<PersistentProjectileEntity>();
        // The bounded spatial query includes only actual client-tracked entities.
        // A reused player UUID or entity ID does not grant ownership: the packet's
        // resolved owner must be this exact, current client player object.
        world.collectEntitiesByType(TypeFilter.instanceOf(PersistentProjectileEntity.class),bounds,
            projectile->projectile.getWorld()==world&&!projectile.isRemoved()&&!projectile.isInvisible()&&
                projectile.getOwner()==player&&finite(projectile.getPos())&&
                projectile.squaredDistanceTo(origin)<=MAX_DISTANCE*MAX_DISTANCE&&
                world.isChunkLoaded(projectile.getBlockPos())&&surface.containsFeet(projectile.getX(),projectile.getZ(),0),
            candidates,MAX_PROJECTILES);
        candidates.sort(Comparator.comparingDouble((PersistentProjectileEntity projectile)->projectile.squaredDistanceTo(origin))
            .thenComparingInt(PersistentProjectileEntity::getId));
        var submitted=new ArrayList<Projectile>(candidates.size());var dispatcher=client.getEntityRenderDispatcher();
        for(var projectile:candidates){
            double x=MathHelper.lerp(tickDelta,projectile.lastRenderX,projectile.getX());
            double y=MathHelper.lerp(tickDelta,projectile.lastRenderY,projectile.getY());
            double z=MathHelper.lerp(tickDelta,projectile.lastRenderZ,projectile.getZ());
            if(!Double.isFinite(x)||!Double.isFinite(y)||!Double.isFinite(z)||!surface.containsFeet(x,z,0)||
                    (x-origin.x)*(x-origin.x)+(y-origin.y)*(y-origin.y)+(z-origin.z)*(z-origin.z)>MAX_DISTANCE*MAX_DISTANCE||
                    !Float.isFinite(projectile.prevPitch)||!Float.isFinite(projectile.getPitch()))continue;
            float yaw=MathHelper.lerp(tickDelta,projectile.prevYaw,projectile.getYaw());if(!Float.isFinite(yaw))continue;
            var renderer=dispatcher.getRenderer(projectile);var offset=renderer.getPositionOffset(projectile,tickDelta);
            if(!finite(offset))continue;
            matrices.push();
            try{
                matrices.translate(x-origin.x+offset.x,y-origin.y+offset.y,z-origin.z+offset.z);
                renderer.render(projectile,yaw,tickDelta,matrices,vertices,dispatcher.getLight(projectile,tickDelta));
            }finally{matrices.pop();}
            submitted.add(new Projectile(projectile.getUuid(),Registries.ENTITY_TYPE.getId(projectile.getType()).toString(),
                player.getUuid(),x,y,z));
        }
        // No world/entity references survive the frame, including disconnect or
        // respawn. Ordinary vanilla entity lifetime and cleanup remain intact.
        return List.copyOf(submitted);
    }
    private static boolean finite(Vec3d v){return v!=null&&Double.isFinite(v.x)&&Double.isFinite(v.y)&&Double.isFinite(v.z);}
}
