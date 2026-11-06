package dev.minecome.hud;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.systems.VertexSorter;
import net.minecraft.block.BlockRenderType;
import net.minecraft.block.BlockState;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.Camera;
import net.minecraft.client.render.RenderLayers;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Vec3d;
import net.minecraft.util.math.random.Random;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import java.util.Map;

/** Draws only server-owned blocks with Minecraft's actual baked state models.
 * Inspected Yarn1.21.1+build.3: BlockRenderManager.renderBlock delegates to the
 * world BlockModelRenderer with the state's position-dependent rendering seed;
 * WorldRenderer.render prepares client light updates before rendering layers.
 * Source inspection: runtime/evidence/world-blocks-source-20261106.
 * Host camera basis/FOV replace Minecraft camera bob and player-eye offsets.
 * This colour layer has block/block depth, but no KCD terrain/object depth.
 */
public final class GameplayWorldRenderer {
    private GameplayWorldRenderer(){}
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

    static int render(Camera camera,float tickDelta,View view,Map<BlockPos,BlockState> blocks){
        RenderSystem.assertOnRenderThread();
        if(view==null||blocks.isEmpty())return 0;
        var client=MinecraftClient.getInstance();
        if(client.world==null||client.player==null||client.getOverlay()!=null)return 0;
        var framebuffer=client.getFramebuffer();
        if(framebuffer.textureWidth<=0||framebuffer.textureHeight<=0)return 0;
        var projection=new Matrix4f(RenderSystem.getProjectionMatrix());
        var modelView=RenderSystem.getModelViewStack();
        var vertices=client.getBufferBuilders().getEntityVertexConsumers();
        // All model/layer calls remain on Minecraft's render thread. The ordinary
        // world pass is suppressed, so no chunk/entity vertices share this pass.
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
            vertices.draw();
            return rendered;
        } finally {
            modelView.popMatrix();RenderSystem.applyModelViewMatrix();
            RenderSystem.setProjectionMatrix(projection,VertexSorter.BY_DISTANCE);
            GameplayHandRenderState.end();
        }
    }
}
