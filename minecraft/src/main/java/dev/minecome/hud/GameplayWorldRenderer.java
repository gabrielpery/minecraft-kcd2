package dev.minecome.hud;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.systems.VertexSorter;
import dev.minecome.gameplay.GameplayBlocks;
import dev.minecome.gameplay.GameplayBlocksPalette;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.block.BlockRenderType;
import net.minecraft.block.BlockState;
import net.minecraft.block.ShapeContext;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.Camera;
import net.minecraft.client.render.RenderLayer;
import net.minecraft.client.render.RenderLayers;
import net.minecraft.client.render.VertexConsumer;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.util.hit.BlockHitResult;
import net.minecraft.util.hit.HitResult;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;
import net.minecraft.util.math.random.Random;
import net.minecraft.util.shape.VoxelShape;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL14;
import java.util.Map;
import java.util.List;

/** Draws owned blocks, tracked items/projectiles and the local player with Minecraft's actual models.
 * Inspected Yarn1.21.1+build.3: BlockRenderManager.renderBlock delegates to the
 * world BlockModelRenderer with the state's position-dependent rendering seed;
 * WorldRenderer.render prepares client light updates before rendering layers.
 * Source inspection: runtime/evidence/world-blocks-source-20261106.
 * Host camera basis/FOV replace Minecraft camera bob and player-eye offsets.
 * The captured heightfield occludes blocks here; the native compositor also
 * compares this world layer against matching KCD2 scene depth.
 */
public final class GameplayWorldRenderer {
    private GameplayWorldRenderer(){}
    /** Results name submitted geometry; depth can hide its pixels. */
    public record Result(int blocks,BlockPos outlined,int terrainOccluders,boolean playerRendered,
                         int droppedItems,List<GameplayDroppedItemRenderer.Item> droppedItemDetails,
                         int projectiles,List<GameplayProjectileRenderer.Projectile> projectileDetails){
        public Result{droppedItemDetails=List.copyOf(droppedItemDetails);projectileDetails=List.copyOf(projectileDetails);}
    }
    public record View(Vec3d origin,Vec3d forward,Vec3d up,double verticalFovRadians) {
        public View {
            if(!finite(origin)||!finite(forward)||!finite(up)||
                Math.abs(forward.lengthSquared()-1)>.01||Math.abs(up.lengthSquared()-1)>.05||
                Math.abs(forward.dotProduct(up))>.05||!Double.isFinite(verticalFovRadians)||
                verticalFovRadians<=.05||verticalFovRadians>=Math.PI-.05)
                throw new IllegalArgumentException("Invalid world rendering camera");
        }
        private static boolean finite(Vec3d v){return v!=null&&Double.isFinite(v.x)&&Double.isFinite(v.y)&&Double.isFinite(v.z);}
    }

    static Result render(Camera camera,float tickDelta,View view,Map<BlockPos,BlockState> blocks,BlockHitResult hover,GroundSurface surface){
        RenderSystem.assertOnRenderThread();
        if(view==null)return new Result(0,null,0,false,0,List.of(),0,List.of());
        var client=MinecraftClient.getInstance();
        if(client.world==null||client.player==null||client.getOverlay()!=null)return new Result(0,null,0,false,0,List.of(),0,List.of());
        var framebuffer=client.getFramebuffer();
        if(framebuffer.textureWidth<=0||framebuffer.textureHeight<=0)return new Result(0,null,0,false,0,List.of(),0,List.of());
        var projection=new Matrix4f(RenderSystem.getProjectionMatrix());
        var sorting=RenderSystem.getVertexSorting();
        float lineWidth=RenderSystem.getShaderLineWidth();
        int blendSourceRgb=GL11.glGetInteger(GL14.GL_BLEND_SRC_RGB),blendDestinationRgb=GL11.glGetInteger(GL14.GL_BLEND_DST_RGB);
        int blendSourceAlpha=GL11.glGetInteger(GL14.GL_BLEND_SRC_ALPHA),blendDestinationAlpha=GL11.glGetInteger(GL14.GL_BLEND_DST_ALPHA);
        var modelView=RenderSystem.getModelViewStack();
        var vertices=client.getBufferBuilders().getEntityVertexConsumers();
        // All model/layer calls remain on Minecraft's render thread. The ordinary
        // world pass is suppressed; only owned models share these buffers.
        GameplayHandRenderState.begin(camera,tickDelta);
        modelView.pushMatrix();
        try {
            modelView.identity();RenderSystem.applyModelViewMatrix();
            RenderSystem.setProjectionMatrix(new Matrix4f().setPerspective((float)view.verticalFovRadians(),
                (float)framebuffer.textureWidth/framebuffer.textureHeight,.05f,512f),VertexSorter.BY_DISTANCE);
            client.world.runQueuedChunkUpdates();
            client.world.getChunkManager().getLightingProvider().doLightUpdates();
            var f=view.forward();var u=view.up();
            var rotation=new Matrix4f().setLookAt(0,0,0,(float)f.x,(float)f.y,(float)f.z,(float)u.x,(float)u.y,(float)u.z);
            var matrices=new MatrixStack();matrices.multiply(new Quaternionf().setFromNormalized(rotation));
            int terrainOccluders=GameplayTerrainDepth.render(matrices,view.origin(),surface);
            var random=Random.create();int rendered=0;
            for(var entry:blocks.entrySet()){
                var pos=entry.getKey();var state=entry.getValue();
                if(state==null||state.getRenderType()!=BlockRenderType.MODEL||!client.world.isChunkLoaded(pos)||
                    client.world.getBlockState(pos)!=state)continue;
                matrices.push();
                matrices.translate(pos.getX()-view.origin().x,pos.getY()-view.origin().y,pos.getZ()-view.origin().z);
                client.getBlockRenderManager().renderBlock(state,pos,client.world,matrices,
                    vertices.getBuffer(RenderLayers.getBlockLayer(state)),true,random);
                matrices.pop();rendered++;
            }
            var droppedItems=GameplayDroppedItemRenderer.render(tickDelta,view.origin(),surface,matrices,vertices);
            var projectiles=GameplayProjectileRenderer.render(tickDelta,view.origin(),surface,matrices,vertices);
            boolean playerRendered=GameplayPlayerRenderer.render(tickDelta,view.origin(),matrices,vertices);
            vertices.draw();
            BlockPos outlined=null;
            if(hover!=null&&hover.getType()==HitResult.Type.BLOCK&&client.currentScreen==null&&!client.options.hudHidden&&
                !MinecraftClient.isFabulousGraphicsOrBetter()){
                var pos=hover.getBlockPos();var state=blocks.get(pos);
                if(state!=null&&state.getRenderType()==BlockRenderType.MODEL&&client.world.isChunkLoaded(pos)&&
                    client.world.getBlockState(pos)==state&&GameplayBlocksPalette.supportsState(GameplayBlocks.stateName(state))){
                    var shape=state.getOutlineShape(client.world,pos,ShapeContext.of(client.player));
                    if(!shape.isEmpty()){
                        // Same camera and depth buffer as the owned models above. This
                        // receives the controller's admitted eye hit in all perspectives,
                        // never an independent ray from the displaced rendering camera.
                        // The vanilla line layer supplies scaled width, view-offset and LEQUAL.
                        drawOutline(matrices,vertices.getBuffer(RenderLayer.getLines()),shape,
                            pos.getX()-view.origin().x,pos.getY()-view.origin().y,pos.getZ()-view.origin().z);
                        vertices.draw(RenderLayer.getLines());outlined=pos.toImmutable();
                    }
                }
            }
            return new Result(rendered,outlined,terrainOccluders,playerRendered,droppedItems.size(),droppedItems,projectiles.size(),projectiles);
        } finally {
            modelView.popMatrix();RenderSystem.applyModelViewMatrix();
            RenderSystem.setProjectionMatrix(projection,sorting);
            RenderSystem.lineWidth(lineWidth);
            GameplayHandRenderState.end();
            RenderSystem.blendFuncSeparate(blendSourceRgb,blendDestinationRgb,blendSourceAlpha,blendDestinationAlpha);
        }
    }

    /** Pinned Yarn1.21.1+build.3 WorldRenderer.drawBlockOutline uses the private
     * drawCuboidShapeOutline and method_3278 edge consumer. Match that edge loop:
     * the public drawShapeOutline debug helper splits boxes and adds internal seams.
     * Inspected bytecode: runtime/evidence/block-outline-source-20261106/WorldRenderer.txt.
     */
    private static void drawOutline(MatrixStack matrices,VertexConsumer vertices,VoxelShape shape,double x,double y,double z){
        var entry=matrices.peek();
        shape.forEachEdge((x1,y1,z1,x2,y2,z2)->{
            float dx=(float)(x2-x1),dy=(float)(y2-y1),dz=(float)(z2-z1);
            float length=MathHelper.sqrt(dx*dx+dy*dy+dz*dz);dx/=length;dy/=length;dz/=length;
            vertices.vertex(entry,(float)(x1+x),(float)(y1+y),(float)(z1+z)).color(0f,0f,0f,.4f).normal(entry,dx,dy,dz);
            vertices.vertex(entry,(float)(x2+x),(float)(y2+y),(float)(z2+z)).color(0f,0f,0f,.4f).normal(entry,dx,dy,dz);
        });
    }
}
