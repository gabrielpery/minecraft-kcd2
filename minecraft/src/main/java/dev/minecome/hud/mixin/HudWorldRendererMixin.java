package dev.minecome.hud.mixin;

import dev.minecome.hud.HudRenderHooks;
import net.minecraft.client.render.WorldRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(WorldRenderer.class)
public abstract class HudWorldRendererMixin {
    @Inject(method="render(Lnet/minecraft/client/render/RenderTickCounter;ZLnet/minecraft/client/render/Camera;Lnet/minecraft/client/render/GameRenderer;Lnet/minecraft/client/render/LightmapTextureManager;Lorg/joml/Matrix4f;Lorg/joml/Matrix4f;)V",at=@At("HEAD"),cancellable=true)
    private void minecome$noWorldPixels(CallbackInfo info){if(HudRenderHooks.suppressWorld())info.cancel();}
    @Inject(method="drawEntityOutlinesFramebuffer",at=@At("HEAD"),cancellable=true)
    private void minecome$noWorldOutlinePixels(CallbackInfo info){if(HudRenderHooks.suppressWorld())info.cancel();}
}
