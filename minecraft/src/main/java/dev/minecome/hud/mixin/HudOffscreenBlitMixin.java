package dev.minecome.hud.mixin;

import com.mojang.blaze3d.systems.RenderSystem;
import dev.minecome.hud.HudStreamLab;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gl.Framebuffer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;

/** Exact1.21.1 render(Z)V: real HUD/PBO first, endWrite503, desktop draw524. */
@Mixin(MinecraftClient.class)
public abstract class HudOffscreenBlitMixin {
    /** render(Z)V's sole outer clear precedes the owned framebuffer.beginWrite. */
    @Redirect(method="render(Z)V",at=@At(value="INVOKE",target="Lcom/mojang/blaze3d/systems/RenderSystem;clear(IZ)V"))
    private void minecome$ownedOffscreenClear(int mask,boolean checkError){
        if(!HudStreamLab.skipDesktopClear(mask))RenderSystem.clear(mask,checkError);
    }
    @Redirect(method="render(Z)V",at=@At(value="INVOKE",target="Lnet/minecraft/client/gl/Framebuffer;draw(II)V"))
    private void minecome$ownedOffscreenBlit(Framebuffer framebuffer,int width,int height){
        if(!HudStreamLab.skipDesktopBlit(framebuffer,width,height))framebuffer.draw(width,height);
    }
}
