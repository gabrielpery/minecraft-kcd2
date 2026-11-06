package dev.minecome.hud;

import com.mojang.blaze3d.systems.RenderSystem;
import dev.minecome.terrain.GroundSurface;
import net.minecraft.client.render.BufferRenderer;
import net.minecraft.client.render.GameRenderer;
import net.minecraft.client.render.Tessellator;
import net.minecraft.client.render.VertexConsumer;
import net.minecraft.client.render.VertexFormat;
import net.minecraft.client.render.VertexFormats;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.util.math.Vec3d;
import org.joml.Matrix4f;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;

/** Captured heightfield geometry writes depth only, before owned block models.
 * Uses the same immutable surface as collision; no terrain colour or native
 * object geometry is invented. Pinned 1.21.1 RenderSystem/BufferRenderer API:
 * runtime/evidence/terrain-depth-source-20261106. Hands clear depth afterwards.
 */
final class GameplayTerrainDepth {
    private GameplayTerrainDepth(){}

    static int render(MatrixStack matrices,Vec3d origin,GroundSurface surface){
        RenderSystem.assertOnRenderThread();
        if(surface==null||surface.slabs().isEmpty())return 0;
        var shader=RenderSystem.getShader();
        var mask=BufferUtils.createByteBuffer(4);GL11.glGetBooleanv(GL11.GL_COLOR_WRITEMASK,mask);
        boolean cull=GL11.glIsEnabled(GL11.GL_CULL_FACE),depth=GL11.glIsEnabled(GL11.GL_DEPTH_TEST);
        boolean write=GL11.glGetBoolean(GL11.GL_DEPTH_WRITEMASK);int function=GL11.glGetInteger(GL11.GL_DEPTH_FUNC);
        try{
            RenderSystem.colorMask(false,false,false,false);
            RenderSystem.enableDepthTest();RenderSystem.depthMask(true);RenderSystem.depthFunc(GL11.GL_LEQUAL);
            RenderSystem.disableCull();RenderSystem.setShader(GameRenderer::getPositionProgram);
            var vertices=Tessellator.getInstance().begin(VertexFormat.DrawMode.QUADS,VertexFormats.POSITION);
            var matrix=matrices.peek().getPositionMatrix();int count=0;
            for(var slab:surface.slabs()){
                float x0=(float)(slab.minX()-origin.x),y0=(float)(slab.minY()-origin.y),z0=(float)(slab.minZ()-origin.z);
                float x1=(float)(slab.maxX()-origin.x),y1=(float)(slab.maxY()-origin.y),z1=(float)(slab.maxZ()-origin.z);
                // Both faces matter when a captured step is viewed from its side.
                quad(vertices,matrix,x0,y0,z0,x1,y0,z0,x1,y0,z1,x0,y0,z1);
                quad(vertices,matrix,x0,y1,z0,x0,y1,z1,x1,y1,z1,x1,y1,z0);
                quad(vertices,matrix,x0,y0,z0,x0,y1,z0,x1,y1,z0,x1,y0,z0);
                quad(vertices,matrix,x0,y0,z1,x1,y0,z1,x1,y1,z1,x0,y1,z1);
                quad(vertices,matrix,x0,y0,z0,x0,y0,z1,x0,y1,z1,x0,y1,z0);
                quad(vertices,matrix,x1,y0,z0,x1,y1,z0,x1,y1,z1,x1,y0,z1);count++;
            }
            BufferRenderer.drawWithGlobalProgram(vertices.end());return count;
        }finally{
            RenderSystem.colorMask(mask.get(0)!=0,mask.get(1)!=0,mask.get(2)!=0,mask.get(3)!=0);
            if(cull)RenderSystem.enableCull();else RenderSystem.disableCull();
            if(depth)RenderSystem.enableDepthTest();else RenderSystem.disableDepthTest();
            RenderSystem.depthMask(write);RenderSystem.depthFunc(function);RenderSystem.setShader(()->shader);
        }
    }

    private static void quad(VertexConsumer v,Matrix4f m,float ax,float ay,float az,float bx,float by,float bz,
                             float cx,float cy,float cz,float dx,float dy,float dz){
        v.vertex(m,ax,ay,az);v.vertex(m,bx,by,bz);v.vertex(m,cx,cy,cz);v.vertex(m,dx,dy,dz);
    }
}
