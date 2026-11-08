package dev.minecome.hud;

import com.mojang.blaze3d.systems.RenderSystem;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.VertexConsumerProvider;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.entity.ItemEntity;
import net.minecraft.registry.Registries;
import net.minecraft.util.TypeFilter;
import net.minecraft.util.math.Box;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

/** Actual tracked item entities in the same colour/depth pass as owned blocks.
 * Inspected cached Yarn1.21.1+build.3 WorldRenderer.renderEntity interpolates
 * lastRenderX/Y/Z and prevYaw. ItemEntityRenderer supplies the vanilla stack
 * model, count-dependent copies, bob, spin and ground transform. The dispatcher
 * supplies world light; its render wrapper would also add a fake ground shadow
 * and optional debug geometry, so call the registered item renderer directly.
 * World.collectEntitiesByType(..., limit) aborts its spatial lookup at the limit.
 * Bytecode evidence: runtime/evidence/dropped-item-source-20261108/.
 */
public final class GameplayDroppedItemRenderer {
    public static final int MAX_ITEMS=256;
    public static final double MAX_DISTANCE=64;
    /** Submitted entity identity and interpolated base, not a visible-pixel claim. */
    public record Item(UUID id,String item,int count,double x,double y,double z){}
    private GameplayDroppedItemRenderer(){}

    static List<Item> render(float tickDelta,Vec3d origin,GroundSurface surface,
                             MatrixStack matrices,VertexConsumerProvider vertices){
        RenderSystem.assertOnRenderThread();
        var client=MinecraftClient.getInstance();var world=client.world;
        if(world==null||client.player==null||surface==null||!GameplaySession.worldBlocksEnabled()||
                !finite(origin)||!Float.isFinite(tickDelta))return List.of();
        var candidates=new ArrayList<ItemEntity>();
        var bounds=new Box(origin.x-MAX_DISTANCE,origin.y-MAX_DISTANCE,origin.z-MAX_DISTANCE,
                           origin.x+MAX_DISTANCE,origin.y+MAX_DISTANCE,origin.z+MAX_DISTANCE);
        // Bounded spatial collection avoids scanning all loaded entities or
        // first materializing an unbounded drop list. Captured XZ coverage is
        // required; vertical motion remains vanilla and terrain depth occludes it.
        world.collectEntitiesByType(TypeFilter.instanceOf(ItemEntity.class),bounds,
            item->item.getWorld()==world&&!item.isRemoved()&&!item.isInvisible()&&!item.getStack().isEmpty()&&
                finite(item.getPos())&&item.squaredDistanceTo(origin)<=MAX_DISTANCE*MAX_DISTANCE&&
                world.isChunkLoaded(item.getBlockPos())&&surface.containsFeet(item.getX(),item.getZ(),0),
            candidates,MAX_ITEMS);
        candidates.sort(Comparator.comparingDouble((ItemEntity item)->item.squaredDistanceTo(origin)).thenComparingInt(ItemEntity::getId));
        var submitted=new ArrayList<Item>(candidates.size());
        var dispatcher=client.getEntityRenderDispatcher();
        for(var item:candidates){
            double x=MathHelper.lerp(tickDelta,item.lastRenderX,item.getX());
            double y=MathHelper.lerp(tickDelta,item.lastRenderY,item.getY());
            double z=MathHelper.lerp(tickDelta,item.lastRenderZ,item.getZ());
            if(!Double.isFinite(x)||!Double.isFinite(y)||!Double.isFinite(z)||!surface.containsFeet(x,z,0)||
                    (x-origin.x)*(x-origin.x)+(y-origin.y)*(y-origin.y)+(z-origin.z)*(z-origin.z)>MAX_DISTANCE*MAX_DISTANCE)continue;
            var renderer=dispatcher.getRenderer(item);var offset=renderer.getPositionOffset(item,tickDelta);
            if(!finite(offset))continue;
            float yaw=MathHelper.lerp(tickDelta,item.prevYaw,item.getYaw());if(!Float.isFinite(yaw))continue;
            matrices.push();
            try{
                matrices.translate(x-origin.x+offset.x,y-origin.y+offset.y,z-origin.z+offset.z);
                renderer.render(item,yaw,tickDelta,matrices,vertices,dispatcher.getLight(item,tickDelta));
            }finally{matrices.pop();}
            var stack=item.getStack();
            submitted.add(new Item(item.getUuid(),Registries.ITEM.getId(stack.getItem()).toString(),stack.getCount(),x,y,z));
        }
        return List.copyOf(submitted);
    }
    private static boolean finite(Vec3d v){return v!=null&&Double.isFinite(v.x)&&Double.isFinite(v.y)&&Double.isFinite(v.z);}
}
