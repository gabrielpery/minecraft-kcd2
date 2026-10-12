package dev.minecome.hud.mixin;

import com.mojang.blaze3d.platform.GlStateManager;
import dev.minecome.hud.HudExportLab;
import org.lwjgl.opengl.GL11;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Preserve vanilla RGB; ordinary UI source-over gets accumulated alpha for transparent extraction. */
@Mixin(value=GlStateManager.class,remap=false)
public abstract class HudBlendMixin {
    @ModifyVariable(method="_blendFuncSeparate(IIII)V",at=@At("HEAD"),argsOnly=true,ordinal=3,remap=false)
    private static int minecome$sourceOverAlpha(int destinationAlpha,int sourceRgb,int destinationRgb,int sourceAlpha,int originalDestinationAlpha){
        return HudExportLab.transparentFrame() && sourceRgb==GL11.GL_SRC_ALPHA && destinationRgb==GL11.GL_ONE_MINUS_SRC_ALPHA && sourceAlpha==GL11.GL_ONE && originalDestinationAlpha==GL11.GL_ZERO ? GL11.GL_ONE_MINUS_SRC_ALPHA:destinationAlpha;
    }
    @Inject(method="_blendFunc(II)V",at=@At("HEAD"),cancellable=true,remap=false)
    private static void minecome$sourceOverPair(int source,int destination,CallbackInfo info){
        if(HudExportLab.transparentFrame() && source==GL11.GL_SRC_ALPHA && destination==GL11.GL_ONE_MINUS_SRC_ALPHA){
            GlStateManager._blendFuncSeparate(source,destination,GL11.GL_ONE,GL11.GL_ONE_MINUS_SRC_ALPHA);info.cancel();
        }
    }
}
