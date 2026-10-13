package dev.minecome.hud.mixin;

import com.mojang.blaze3d.systems.RenderSystem;
import dev.minecome.hud.HudStreamLab;
import org.lwjgl.glfw.GLFW;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;

/** Inspected1.21.1 flipFrame keeps both event polls, replayQueue and Tessellator.clear. */
@Mixin(value=RenderSystem.class,remap=false)
public abstract class HudOffscreenPresentationMixin {
    @Redirect(method="flipFrame(J)V",at=@At(value="INVOKE",target="Lorg/lwjgl/glfw/GLFW;glfwSwapBuffers(J)V",remap=false),remap=false)
    private static void minecome$ownedOffscreenSwap(long window){
        if(!HudStreamLab.skipDesktopSwap(window))GLFW.glfwSwapBuffers(window);
    }
}
