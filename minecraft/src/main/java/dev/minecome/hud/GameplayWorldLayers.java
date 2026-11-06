package dev.minecome.hud;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gl.Framebuffer;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.*;

/** Saves the world before vanilla hands/UI replace its colour and depth. Render thread only. */
final class GameplayWorldLayers implements AutoCloseable {
    // Inspected pinned Yarn1.21.1+build.3 Framebuffer.initFbo/copyDepthFrom:
    // use its exact colour/depth formats so depth blits match the main framebuffer.
    private static final class OwnedFramebuffer extends Framebuffer {
        OwnedFramebuffer(){super(true);}
    }
    private OwnedFramebuffer world;
    private boolean captured;
    void beginFrame(){RenderSystem.assertOnRenderThread();captured=false;}
    Framebuffer framebuffer(){return captured?world:null;}
    void capture(Framebuffer source,boolean hasWorld){
        RenderSystem.assertOnRenderThread();HudPixels.byteSize(source.textureWidth,source.textureHeight);
        captured=false;
        try(var saved=new State()){
            RenderSystem.disableScissor();RenderSystem.colorMask(true,true,true,true);RenderSystem.depthMask(true);
            if(world==null||world.textureWidth!=source.textureWidth||world.textureHeight!=source.textureHeight){
                if(world!=null)world.delete();world=new OwnedFramebuffer();
                try{world.resize(source.textureWidth,source.textureHeight,MinecraftClient.IS_SYSTEM_MAC);}
                catch(RuntimeException|Error failure){world.delete();world=null;throw failure;}
            }
            GlStateManager._glBindFramebuffer(GL30.GL_DRAW_FRAMEBUFFER,world.fbo);
            if(hasWorld){
                GlStateManager._glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER,source.fbo);
                int previousSourceRead=GL11.glGetInteger(GL11.GL_READ_BUFFER);
                try{
                    GL11.glReadBuffer(GL30.GL_COLOR_ATTACHMENT0);
                    GlStateManager._glBlitFrameBuffer(0,0,source.textureWidth,source.textureHeight,0,0,world.textureWidth,world.textureHeight,
                            GL11.GL_COLOR_BUFFER_BIT|GL11.GL_DEPTH_BUFFER_BIT,GL11.GL_NEAREST);
                }finally{GL11.glReadBuffer(previousSourceRead);}
            }else{
                // A missing/stale native view must not replay the previous world.
                RenderSystem.clearColor(0,0,0,0);GlStateManager._clearDepth(1);
                RenderSystem.clear(GL11.GL_COLOR_BUFFER_BIT|GL11.GL_DEPTH_BUFFER_BIT,MinecraftClient.IS_SYSTEM_MAC);
            }
            GlStateManager._glBindFramebuffer(GL30.GL_DRAW_FRAMEBUFFER,source.fbo);
            RenderSystem.clearColor(0,0,0,0);
            RenderSystem.clear(GL11.GL_COLOR_BUFFER_BIT,MinecraftClient.IS_SYSTEM_MAC);
            captured=true;
        }
    }
    @Override public void close(){
        RenderSystem.assertOnRenderThread();captured=false;
        if(world!=null)try(var saved=new State()){world.delete();world=null;}
    }
    /** Framebuffer allocation also changes texture binding, clear values and viewport. */
    private static final class State implements AutoCloseable {
        final int read=GL11.glGetInteger(GL30.GL_READ_FRAMEBUFFER_BINDING),draw=GL11.glGetInteger(GL30.GL_DRAW_FRAMEBUFFER_BINDING);
        final int texture=GL11.glGetInteger(GL11.GL_TEXTURE_BINDING_2D),readBuffer=GL11.glGetInteger(GL11.GL_READ_BUFFER);
        final boolean depth=GL11.glIsEnabled(GL11.GL_DEPTH_TEST),depthMask=GL11.glGetBoolean(GL11.GL_DEPTH_WRITEMASK),scissor=GL11.glIsEnabled(GL11.GL_SCISSOR_TEST);
        final double clearDepth=GL11.glGetDouble(GL11.GL_DEPTH_CLEAR_VALUE);
        final int[] viewport=new int[4],box=new int[4];final float[] clear=new float[4];
        final java.nio.ByteBuffer mask=BufferUtils.createByteBuffer(4);
        State(){GL11.glGetIntegerv(GL11.GL_VIEWPORT,viewport);GL11.glGetIntegerv(GL11.GL_SCISSOR_BOX,box);GL11.glGetFloatv(GL11.GL_COLOR_CLEAR_VALUE,clear);GL11.glGetBooleanv(GL11.GL_COLOR_WRITEMASK,mask);}
        @Override public void close(){
            GlStateManager._glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER,read);GL11.glReadBuffer(readBuffer);
            GlStateManager._glBindFramebuffer(GL30.GL_DRAW_FRAMEBUFFER,draw);GlStateManager._bindTexture(texture);
            RenderSystem.viewport(viewport[0],viewport[1],viewport[2],viewport[3]);RenderSystem.clearColor(clear[0],clear[1],clear[2],clear[3]);GlStateManager._clearDepth(clearDepth);
            RenderSystem.colorMask(mask.get(0)!=0,mask.get(1)!=0,mask.get(2)!=0,mask.get(3)!=0);RenderSystem.depthMask(depthMask);
            if(depth)RenderSystem.enableDepthTest();else RenderSystem.disableDepthTest();
            if(scissor)RenderSystem.enableScissor(box[0],box[1],box[2],box[3]);else RenderSystem.disableScissor();
        }
    }
}
