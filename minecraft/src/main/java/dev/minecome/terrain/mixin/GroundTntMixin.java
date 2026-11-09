package dev.minecome.terrain.mixin;

import dev.minecome.gameplay.GameplayTnt;
import dev.minecome.gameplay.GameplayBlasts;
import net.minecraft.entity.TntEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(TntEntity.class)
public abstract class GroundTntMixin {
    @Inject(method="tick",at=@At("HEAD"),cancellable=true)
    private void minecome$ownFuse(CallbackInfo callback){var tnt=(TntEntity)(Object)this;if(GameplayTnt.beforeTick(tnt)||GameplayBlasts.holdTick(tnt))callback.cancel();}
    @Inject(method="tick",at=@At(value="INVOKE",target="Lnet/minecraft/entity/TntEntity;discard()V"),cancellable=true)
    private void minecome$prepareBlast(CallbackInfo callback){if(GameplayBlasts.prepare((TntEntity)(Object)this))callback.cancel();}
}
