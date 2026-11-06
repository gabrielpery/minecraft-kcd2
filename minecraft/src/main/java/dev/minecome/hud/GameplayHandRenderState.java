package dev.minecome.hud;

import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.BackgroundRenderer;
import net.minecraft.client.render.Camera;
import net.minecraft.client.render.DiffuseLighting;
import org.lwjgl.opengl.GL11;

/** Supplies the state vanilla WorldRenderer would normally prepare before hands.
 * Inspected Yarn1.21.1+build.3 WorldRenderer.render: shader time/dispatchers at30/49/68,
 * dimension diffuse lighting at587/593 and final depth mask/clearFog at2635/2641.
 * No models, transforms or animation are substituted for vanilla HeldItemRenderer.
 */
final class GameplayHandRenderState {
    private static boolean active,depth,cull,blend,depthWrite;
    private static int depthFunction;
    private static float[] color;
    private GameplayHandRenderState(){}

    static void begin(Camera camera,float tickDelta){
        RenderSystem.assertOnRenderThread();
        if(active)throw new IllegalStateException("Nested gameplay hand render state");
        var client=MinecraftClient.getInstance();
        depth=GL11.glIsEnabled(GL11.GL_DEPTH_TEST);cull=GL11.glIsEnabled(GL11.GL_CULL_FACE);
        blend=GL11.glIsEnabled(GL11.GL_BLEND);depthWrite=GL11.glGetBoolean(GL11.GL_DEPTH_WRITEMASK);
        depthFunction=GL11.glGetInteger(GL11.GL_DEPTH_FUNC);color=RenderSystem.getShaderColor().clone();active=true;
        RenderSystem.enableDepthTest();RenderSystem.depthMask(true);RenderSystem.depthFunc(GL11.GL_LEQUAL);
        RenderSystem.enableCull();RenderSystem.disableBlend();RenderSystem.defaultBlendFunc();RenderSystem.setShaderColor(1,1,1,1);
        // WorldRenderer is skipped, so its normal depth-write state was skipped
        // too. Clear after enabling writes rather than relying on last frame's UI.
        RenderSystem.clear(GL11.GL_DEPTH_BUFFER_BIT,MinecraftClient.IS_SYSTEM_MAC);
        RenderSystem.setShaderGameTime(client.world.getTime(),tickDelta);
        client.getBlockEntityRenderDispatcher().configure(client.world,camera,client.crosshairTarget);
        client.getEntityRenderDispatcher().configure(client.world,camera,client.targetedEntity);
        if(client.world.getDimensionEffects().isDarkened())DiffuseLighting.enableForLevel();else DiffuseLighting.disableForLevel();
        BackgroundRenderer.clearFog();
    }

    static void end(){
        if(!active)return;RenderSystem.assertOnRenderThread();active=false;
        if(depth)RenderSystem.enableDepthTest();else RenderSystem.disableDepthTest();
        if(cull)RenderSystem.enableCull();else RenderSystem.disableCull();
        if(blend)RenderSystem.enableBlend();else RenderSystem.disableBlend();
        RenderSystem.depthMask(depthWrite);RenderSystem.depthFunc(depthFunction);
        RenderSystem.setShaderColor(color[0],color[1],color[2],color[3]);color=null;
        // GameRenderer sets GUI diffuse lighting immediately after its GUI clear.
        // GameplaySession restores the original blend factors after frame capture.
    }
}
