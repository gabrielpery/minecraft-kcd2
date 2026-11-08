package dev.minecome.hud.mixin;

import dev.minecome.hud.GameplaySession;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerInteractionManager;
import net.minecraft.entity.player.PlayerEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.Redirect;
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

    // Cached Yarn1.21.1+build.3 handleInputEvents cancels item use when useKey
    // is up. Host mouse input belongs to our controller, not that key binding.
    // Preserve only its fresh admitted food hold; do not synthesize useKey,
    // which would let vanilla doItemUse interact with an unrelated crosshair.
    @Redirect(method="handleInputEvents",at=@At(value="INVOKE",target="Lnet/minecraft/client/network/ClientPlayerInteractionManager;stopUsingItem(Lnet/minecraft/entity/player/PlayerEntity;)V"))
    private void minecome$preserveGameplayFood(ClientPlayerInteractionManager manager,PlayerEntity player){
        if(!GameplaySession.preserveFoodUse())manager.stopUsingItem(player);
    }
}
