package dev.minecome.hud.mixin;

import dev.minecome.hud.HudStreamLab;
import net.minecraft.client.MinecraftClient;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Exact mapped1.21.1 render(Z)V calls inspected with javap; observational, trial-only. */
@Mixin(MinecraftClient.class)
public abstract class HudClientTimingMixin {
    @Inject(method="onWindowFocusChanged(Z)V",at=@At("HEAD")) private void minecome$focusChanged(boolean focused,CallbackInfo ci){HudStreamLab.timingFocusChanged(focused);}
    @Inject(method="render(Z)V",at=@At("HEAD")) private void minecome$frameStart(CallbackInfo ci){HudStreamLab.timingStage("frame_setup");}
    @Inject(method="render(Z)V",at=@At("RETURN")) private void minecome$frameEnd(CallbackInfo ci){HudStreamLab.timingStage("between_frames");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/MinecraftClient;tick()V")) private void minecome$tickStart(CallbackInfo ci){HudStreamLab.timingStage("client_tick");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/MinecraftClient;tick()V",shift=At.Shift.AFTER)) private void minecome$tickEnd(CallbackInfo ci){HudStreamLab.timingStage("render_setup");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/render/GameRenderer;render(Lnet/minecraft/client/render/RenderTickCounter;Z)V")) private void minecome$renderStart(CallbackInfo ci){HudStreamLab.timingStage("game_render");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/render/GameRenderer;render(Lnet/minecraft/client/render/RenderTickCounter;Z)V",shift=At.Shift.AFTER)) private void minecome$renderEnd(CallbackInfo ci){HudStreamLab.timingStage("post_render");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/gl/Framebuffer;draw(II)V")) private void minecome$blitStart(CallbackInfo ci){HudStreamLab.timingStage("framebuffer_blit");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/gl/Framebuffer;draw(II)V",shift=At.Shift.AFTER)) private void minecome$blitEnd(CallbackInfo ci){HudStreamLab.timingStage("post_blit");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/util/Window;swapBuffers()V")) private void minecome$swapStart(CallbackInfo ci){HudStreamLab.timingStage("swap_buffers");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/util/Window;swapBuffers()V",shift=At.Shift.AFTER)) private void minecome$swapEnd(CallbackInfo ci){HudStreamLab.timingStage("post_swap");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lcom/mojang/blaze3d/systems/RenderSystem;limitDisplayFPS(I)V")) private void minecome$limitStart(CallbackInfo ci){HudStreamLab.timingStage("fps_limit");}
    @Inject(method="render(Z)V",at=@At(value="INVOKE",target="Lcom/mojang/blaze3d/systems/RenderSystem;limitDisplayFPS(I)V",shift=At.Shift.AFTER)) private void minecome$limitEnd(CallbackInfo ci){HudStreamLab.timingStage("post_limit");}
}
