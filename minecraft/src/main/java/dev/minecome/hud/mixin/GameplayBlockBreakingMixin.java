package dev.minecome.hud.mixin;

import dev.minecome.hud.GameplaySession;
import net.minecraft.client.MinecraftClient;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(MinecraftClient.class)
public abstract class GameplayBlockBreakingMixin {
    // Inspected cached Yarn1.21.1+build.3 MinecraftClient.handleBlockBreaking(Z)V:
    // with no native attackKey it calls interactionManager.cancelBlockBreaking.
    // The sustained controller uses actual vanilla breaking packets/progress at
    // END_CLIENT_TICK. Preserve only its admitted, fresh Survival hold, leaving
    // ordinary worlds and every other vanilla attack path untouched.
    @Inject(method="handleBlockBreaking",at=@At("HEAD"),cancellable=true)
    private void minecome$preserveGameplayHold(boolean breaking,CallbackInfo callback){
        if(GameplaySession.preserveBlockBreaking())callback.cancel();
    }
}
