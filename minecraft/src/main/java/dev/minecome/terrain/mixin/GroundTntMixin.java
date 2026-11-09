package dev.minecome.terrain.mixin;

import dev.minecome.gameplay.GameplayTnt;
import net.minecraft.entity.TntEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(TntEntity.class)
public abstract class GroundTntMixin {
    @Inject(method="tick",at=@At("HEAD"),cancellable=true)
    private void minecome$ownFuse(CallbackInfo callback){if(GameplayTnt.beforeTick((TntEntity)(Object)this))callback.cancel();}
}
