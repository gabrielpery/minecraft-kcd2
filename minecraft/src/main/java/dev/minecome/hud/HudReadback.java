package dev.minecome.hud;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.client.gl.Framebuffer;
import org.lwjgl.opengl.*;
import java.nio.ByteBuffer;
import java.util.function.Consumer;

/** Exact1.21.1 OpenGL backend: three bounded PBOs, zero-timeout fence polls, skip when busy. */
final class HudReadback implements AutoCloseable {
    record Completed(int id,int width,int height,byte[] bottomUp,String metadata) {}
    private static final class Slot { int buffer,width,height,id; long fence,preReadFence,preReadObservedAt,enqueuedAt; String metadata; }
    private final Slot[] slots={new Slot(),new Slot(),new Slot()};
    private final boolean pairedFenceDiagnostics;
    private long captureCalls,enqueued,busySkips,fenceTimeouts,completed;
    private long maxPendingAge,maxCompletionAge,maxEnqueueDuration,maxPollDuration,maxMapCopyDuration;
    private long lastEnqueueUtc,lastCompletionUtc;
    private long preReadCompleted,preReadTimeouts,maxPreReadObservedAge,maxPostReadAfterPreObserved;
    HudReadback(){this(false);}
    HudReadback(boolean pairedFenceDiagnostics){this.pairedFenceDiagnostics=pairedFenceDiagnostics;}
    boolean capture(Framebuffer framebuffer,int id,String metadata) {
        RenderSystem.assertOnRenderThread();long begun=System.nanoTime();captureCalls++;
        try {return enqueue(framebuffer,id,metadata,begun);}
        finally {maxEnqueueDuration=Math.max(maxEnqueueDuration,System.nanoTime()-begun);}
    }
    private boolean enqueue(Framebuffer framebuffer,int id,String metadata,long begun) {
        int size=HudPixels.byteSize(framebuffer.textureWidth,framebuffer.textureHeight);
        Slot free=null; for(Slot slot:slots)if(slot.fence==0){free=slot;break;} if(free==null){busySkips++;return false;}
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
            if(pairedFenceDiagnostics){
                free.preReadFence=GL32.glFenceSync(GL32.GL_SYNC_GPU_COMMANDS_COMPLETE,0);
                if(free.preReadFence==0)throw new IllegalStateException("HUD pre-read GL fence creation failed");
            }
            GL11.glReadPixels(0,0,free.width,free.height,GL11.GL_RGBA,GL11.GL_UNSIGNED_BYTE,0L);
            free.fence=GL32.glFenceSync(GL32.GL_SYNC_GPU_COMMANDS_COMPLETE,0);
            if(free.fence==0)throw new IllegalStateException("HUD GL fence creation failed");
            free.id=id;free.metadata=metadata;free.enqueuedAt=begun;enqueued++;lastEnqueueUtc=System.currentTimeMillis();return true;
        } catch(RuntimeException|Error failure){
            deleteFences(free);free.enqueuedAt=0;free.metadata=null;throw failure;
        } finally {
            for(int i=0;i<stores.length;i++)GlStateManager._pixelStore(stores[i],previous[i]);
            GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER,pack);GlStateManager._glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER,read);GL11.glReadBuffer(readBuffer);
        }
    }
    void poll(Consumer<Completed> consumer) {
        RenderSystem.assertOnRenderThread();long begun=System.nanoTime();
        try {pollCompleted(consumer);}
        finally {maxPollDuration=Math.max(maxPollDuration,System.nanoTime()-begun);}
    }
    private void pollCompleted(Consumer<Completed> consumer) {
        int pack=GL11.glGetInteger(GL21.GL_PIXEL_PACK_BUFFER_BINDING);
        try {
            for(Slot slot:slots) {
                if(slot.fence==0)continue;
                try {
                maxPendingAge=Math.max(maxPendingAge,System.nanoTime()-slot.enqueuedAt);
                if(slot.preReadFence!=0){
                    int before=GL32.glClientWaitSync(slot.preReadFence,0,0L);
                    if(before==GL32.GL_TIMEOUT_EXPIRED)preReadTimeouts++;
                    else if(before==GL32.GL_ALREADY_SIGNALED || before==GL32.GL_CONDITION_SATISFIED){
                        slot.preReadObservedAt=System.nanoTime();preReadCompleted++;
                        maxPreReadObservedAge=Math.max(maxPreReadObservedAge,slot.preReadObservedAt-slot.enqueuedAt);
                        GL32.glDeleteSync(slot.preReadFence);slot.preReadFence=0;
                    }else throw new IllegalStateException("HUD pre-read GL fence poll failed: "+before);
                }
                int state=GL32.glClientWaitSync(slot.fence,0,0L);
                if(state==GL32.GL_TIMEOUT_EXPIRED){fenceTimeouts++;continue;}
                if(state!=GL32.GL_ALREADY_SIGNALED && state!=GL32.GL_CONDITION_SATISFIED)throw new IllegalStateException("HUD GL fence poll failed: "+state);
                // Only this original post-read fence authorizes pixel mapping. A
                // pre-read fence is diagnostic and never advances capture freshness.
                if(slot.preReadObservedAt!=0)maxPostReadAfterPreObserved=Math.max(maxPostReadAfterPreObserved,System.nanoTime()-slot.preReadObservedAt);
                GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER,slot.buffer);
                long mapAt=System.nanoTime();byte[] pixels;
                try {
                    ByteBuffer mapped=GL30.glMapBufferRange(GL21.GL_PIXEL_PACK_BUFFER,0,HudPixels.byteSize(slot.width,slot.height),GL30.GL_MAP_READ_BIT);
                    if(mapped==null)throw new IllegalStateException("HUD completed PBO map failed");
                    pixels=new byte[mapped.remaining()];
                    try {mapped.get(pixels);} finally {if(!GL15.glUnmapBuffer(GL21.GL_PIXEL_PACK_BUFFER))throw new IllegalStateException("HUD PBO contents invalidated");}
                } finally {maxMapCopyDuration=Math.max(maxMapCopyDuration,System.nanoTime()-mapAt);}
                deleteFences(slot);
                completed++;lastCompletionUtc=System.currentTimeMillis();maxCompletionAge=Math.max(maxCompletionAge,System.nanoTime()-slot.enqueuedAt);slot.enqueuedAt=0;
                consumer.accept(new Completed(slot.id,slot.width,slot.height,pixels,slot.metadata));slot.metadata=null;
                }catch(RuntimeException|Error failure){deleteFences(slot);slot.enqueuedAt=0;slot.metadata=null;throw failure;}
            }
        } finally {GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER,pack);}
    }
    /** Bounded CPU-only evidence; never waits for, maps, or polls GPU work. */
    JsonObject diagnostics(){
        RenderSystem.assertOnRenderThread();long now=System.nanoTime(),pendingAge=0;int pending=0;
        for(Slot slot:slots)if(slot.fence!=0){pending++;pendingAge=Math.max(pendingAge,now-slot.enqueuedAt);}
        maxPendingAge=Math.max(maxPendingAge,pendingAge);
        var result=new JsonObject();result.addProperty("capture_calls",captureCalls);result.addProperty("enqueued",enqueued);result.addProperty("busy_skips",busySkips);
        result.addProperty("fence_timeout_polls",fenceTimeouts);result.addProperty("completed",completed);result.addProperty("pending_slots",pending);
        result.addProperty("current_pending_age_ms",pendingAge/1_000_000);result.addProperty("max_pending_age_ms",maxPendingAge/1_000_000);result.addProperty("max_completion_age_ms",maxCompletionAge/1_000_000);
        result.addProperty("max_enqueue_duration_ms",maxEnqueueDuration/1_000_000.0);result.addProperty("max_poll_duration_ms",maxPollDuration/1_000_000.0);result.addProperty("max_map_copy_duration_ms",maxMapCopyDuration/1_000_000.0);
        result.addProperty("last_enqueue_utc_ms",lastEnqueueUtc);result.addProperty("last_completion_utc_ms",lastCompletionUtc);
        result.addProperty("paired_fence_diagnostics",pairedFenceDiagnostics);
        if(pairedFenceDiagnostics){
            int before=0,after=0;long beforeAge=0,afterAge=0;var states=new JsonArray();
            for(Slot slot:slots)if(slot.fence!=0){
                var state=new JsonObject();state.addProperty("capture_id",slot.id);state.addProperty("enqueued_age_ms",(now-slot.enqueuedAt)/1_000_000);
                state.addProperty("pre_read_signaled_observed",slot.preReadObservedAt!=0);state.addProperty("post_read_pending",true);
                if(slot.preReadObservedAt==0){before++;beforeAge=Math.max(beforeAge,now-slot.enqueuedAt);}
                else{after++;afterAge=Math.max(afterAge,now-slot.preReadObservedAt);state.addProperty("pre_read_observed_age_ms",(slot.preReadObservedAt-slot.enqueuedAt)/1_000_000);state.addProperty("post_read_after_pre_observed_ms",(now-slot.preReadObservedAt)/1_000_000);}
                states.add(state);
            }
            result.addProperty("pre_read_fences_completed",preReadCompleted);result.addProperty("pre_read_fence_timeout_polls",preReadTimeouts);
            result.addProperty("pre_read_pending_slots",before);result.addProperty("post_read_pending_after_pre_slots",after);
            result.addProperty("current_pre_read_pending_age_ms",beforeAge/1_000_000);result.addProperty("current_post_read_after_pre_observed_ms",afterAge/1_000_000);
            result.addProperty("max_pre_read_observed_age_ms",maxPreReadObservedAge/1_000_000);result.addProperty("max_post_read_after_pre_observed_ms",maxPostReadAfterPreObserved/1_000_000);
            result.addProperty("fence_age_semantics","CPU zero-timeout poll observations; coarse bounds, not GPU timer durations");result.add("pending_fences",states);
        }
        return result;
    }
    private static void deleteFences(Slot slot){
        if(slot.fence!=0){GL32.glDeleteSync(slot.fence);slot.fence=0;}
        if(slot.preReadFence!=0){GL32.glDeleteSync(slot.preReadFence);slot.preReadFence=0;}
        slot.preReadObservedAt=0;
    }
    @Override public void close(){
        RenderSystem.assertOnRenderThread();for(Slot slot:slots){deleteFences(slot);if(slot.buffer!=0)GL15.glDeleteBuffers(slot.buffer);slot.buffer=0;slot.enqueuedAt=0;slot.metadata=null;}
    }
}
