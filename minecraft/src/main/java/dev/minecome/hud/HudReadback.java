package dev.minecome.hud;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.client.gl.Framebuffer;
import org.lwjgl.opengl.*;
import java.nio.ByteBuffer;
import java.util.function.Consumer;

/** Exact1.21.1 OpenGL backend: three bounded PBOs, zero-timeout fence polls, skip when busy. */
final class HudReadback implements AutoCloseable {
    record Completed(int id,int width,int height,byte[] bottomUp,String metadata) {}
    private static final class Slot { int buffer,width,height,id; long fence; String metadata; }
    private final Slot[] slots={new Slot(),new Slot(),new Slot()};
    boolean capture(Framebuffer framebuffer,int id,String metadata) {
        RenderSystem.assertOnRenderThread(); int size=HudPixels.byteSize(framebuffer.textureWidth,framebuffer.textureHeight);
        Slot free=null; for(Slot slot:slots)if(slot.fence==0){free=slot;break;} if(free==null)return false;
        int pack=GL11.glGetInteger(GL21.GL_PIXEL_PACK_BUFFER_BINDING), read=GL11.glGetInteger(GL30.GL_READ_FRAMEBUFFER_BINDING);
        int readBuffer=GL11.glGetInteger(GL11.GL_READ_BUFFER);
        int[] stores={GL11.GL_PACK_ALIGNMENT,GL11.GL_PACK_ROW_LENGTH,GL11.GL_PACK_SKIP_ROWS,GL11.GL_PACK_SKIP_PIXELS};
        int[] previous=new int[stores.length];for(int i=0;i<stores.length;i++)previous[i]=GL11.glGetInteger(stores[i]);
        try {
            if(free.buffer==0)free.buffer=GL15.glGenBuffers();
            GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER,free.buffer);
            if(free.width!=framebuffer.textureWidth || free.height!=framebuffer.textureHeight){
                GL15.glBufferData(GL21.GL_PIXEL_PACK_BUFFER,size,GL15.GL_STREAM_READ);free.width=framebuffer.textureWidth;free.height=framebuffer.textureHeight;
            }
            GlStateManager._glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER,framebuffer.fbo);GL11.glReadBuffer(GL30.GL_COLOR_ATTACHMENT0);
            GlStateManager._pixelStore(GL11.GL_PACK_ALIGNMENT,1);
            for(int i=1;i<stores.length;i++)GlStateManager._pixelStore(stores[i],0);
            GL11.glReadPixels(0,0,free.width,free.height,GL11.GL_RGBA,GL11.GL_UNSIGNED_BYTE,0L);
            free.fence=GL32.glFenceSync(GL32.GL_SYNC_GPU_COMMANDS_COMPLETE,0);
            if(free.fence==0)throw new IllegalStateException("HUD GL fence creation failed");
            free.id=id;free.metadata=metadata; return true;
        } finally {
            for(int i=0;i<stores.length;i++)GlStateManager._pixelStore(stores[i],previous[i]);
            GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER,pack);GlStateManager._glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER,read);GL11.glReadBuffer(readBuffer);
        }
    }
    void poll(Consumer<Completed> consumer) {
        RenderSystem.assertOnRenderThread();int pack=GL11.glGetInteger(GL21.GL_PIXEL_PACK_BUFFER_BINDING);
        try {
            for(Slot slot:slots) {
                if(slot.fence==0)continue;
                int state=GL32.glClientWaitSync(slot.fence,0,0L);
                if(state==GL32.GL_TIMEOUT_EXPIRED)continue;
                if(state==GL32.GL_WAIT_FAILED)throw new IllegalStateException("HUD GL fence poll failed");
                GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER,slot.buffer);
                ByteBuffer mapped=GL30.glMapBufferRange(GL21.GL_PIXEL_PACK_BUFFER,0,HudPixels.byteSize(slot.width,slot.height),GL30.GL_MAP_READ_BIT);
                if(mapped==null)throw new IllegalStateException("HUD completed PBO map failed");
                byte[] pixels=new byte[mapped.remaining()];
                try {mapped.get(pixels);} finally {if(!GL15.glUnmapBuffer(GL21.GL_PIXEL_PACK_BUFFER))throw new IllegalStateException("HUD PBO contents invalidated");}
                GL32.glDeleteSync(slot.fence);slot.fence=0;
                consumer.accept(new Completed(slot.id,slot.width,slot.height,pixels,slot.metadata));slot.metadata=null;
            }
        } finally {GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER,pack);}
    }
    @Override public void close(){
        RenderSystem.assertOnRenderThread();for(Slot slot:slots){if(slot.fence!=0)GL32.glDeleteSync(slot.fence);if(slot.buffer!=0)GL15.glDeleteBuffers(slot.buffer);slot.fence=0;slot.buffer=0;}
    }
}
