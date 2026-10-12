package dev.minecome.hud.mixin;

import dev.minecome.hud.HudStreamLab;
import net.minecraft.client.Mouse;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Named1.21.1 GameRenderer reads Mouse.getX/getY for genuine Screen hover rendering. */
@Mixin(Mouse.class)
public abstract class HudMouseMixin {
    @Inject(method="getX",at=@At("HEAD"),cancellable=true)
    private void minecome$uiMouseX(CallbackInfoReturnable<Double> value){Double x=HudStreamLab.virtualMouseX();if(x!=null)value.setReturnValue(x);}
    @Inject(method="getY",at=@At("HEAD"),cancellable=true)
    private void minecome$uiMouseY(CallbackInfoReturnable<Double> value){Double y=HudStreamLab.virtualMouseY();if(y!=null)value.setReturnValue(y);}
}
