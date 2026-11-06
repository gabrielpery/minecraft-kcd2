package dev.minecome.hud.mixin;

import dev.minecome.hud.HudRenderHooks;
import net.minecraft.client.render.Camera;
import net.minecraft.client.render.GameRenderer;
import org.joml.Matrix4f;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Inspected Yarn1.21.1+build.3 GameRenderer: render GUI clear at323;
 * renderWorld hand invocation at620; renderHand invokes HeldItemRenderer.renderItem at239.
 * Local inspection: runtime/evidence/hands-source-20261106/GameRenderer.txt. */
@Mixin(GameRenderer.class)
public abstract class HudGameRendererMixin {
    @Inject(method="render(Lnet/minecraft/client/render/RenderTickCounter;Z)V",at=@At(value="INVOKE",target="Lcom/mojang/blaze3d/systems/RenderSystem;clear(IZ)V",ordinal=0))
    private void minecome$transparentUi(CallbackInfo info){HudRenderHooks.beforeGuiClear();}
    @Inject(method="render(Lnet/minecraft/client/render/RenderTickCounter;Z)V",at=@At("RETURN"))
    private void minecome$completedUi(CallbackInfo info){HudRenderHooks.afterRender();}
    @Inject(method="renderHand(Lnet/minecraft/client/render/Camera;FLorg/joml/Matrix4f;)V",at=@At("HEAD"),cancellable=true)
    private void minecome$handLayer(Camera camera,float tickDelta,Matrix4f view,CallbackInfo info){
        if(HudRenderHooks.suppressHand()){info.cancel();return;}
        HudRenderHooks.beforeHand(camera,tickDelta);
    }
    @Inject(method="renderHand(Lnet/minecraft/client/render/Camera;FLorg/joml/Matrix4f;)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/render/item/HeldItemRenderer;renderItem(FLnet/minecraft/client/util/math/MatrixStack;Lnet/minecraft/client/render/VertexConsumerProvider$Immediate;Lnet/minecraft/client/network/ClientPlayerEntity;I)V"))
    private void minecome$startedHandPass(CallbackInfo info){HudRenderHooks.handRenderStarted();}
    @Inject(method="renderHand(Lnet/minecraft/client/render/Camera;FLorg/joml/Matrix4f;)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/render/item/HeldItemRenderer;renderItem(FLnet/minecraft/client/util/math/MatrixStack;Lnet/minecraft/client/render/VertexConsumerProvider$Immediate;Lnet/minecraft/client/network/ClientPlayerEntity;I)V",shift=At.Shift.AFTER))
    private void minecome$completedHandPass(CallbackInfo info){HudRenderHooks.handRenderCompleted();}
    @Inject(method="renderHand(Lnet/minecraft/client/render/Camera;FLorg/joml/Matrix4f;)V",at=@At("RETURN"))
    private void minecome$restoreHandState(CallbackInfo info){HudRenderHooks.afterHand();}
}
