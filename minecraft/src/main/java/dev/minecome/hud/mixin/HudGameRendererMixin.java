package dev.minecome.hud.mixin;

import dev.minecome.hud.HudRenderHooks;
import net.minecraft.client.render.GameRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Named1.21.1 bytecode: GUI depth clear at317, final DrawContext.draw at974, return986. */
@Mixin(GameRenderer.class)
public abstract class HudGameRendererMixin {
    @Inject(method="render(Lnet/minecraft/client/render/RenderTickCounter;Z)V",at=@At(value="INVOKE",target="Lcom/mojang/blaze3d/systems/RenderSystem;clear(IZ)V",ordinal=0))
    private void minecome$transparentUi(CallbackInfo info){HudRenderHooks.beforeGuiClear();}
    @Inject(method="render(Lnet/minecraft/client/render/RenderTickCounter;Z)V",at=@At("RETURN"))
    private void minecome$completedUi(CallbackInfo info){HudRenderHooks.afterRender();}
    @Inject(method="renderHand",at=@At("HEAD"),cancellable=true)
    private void minecome$uiOnly(CallbackInfo info){if(HudRenderHooks.suppressWorld())info.cancel();}
}
