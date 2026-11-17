package dev.minecome.terrain.mixin;

import dev.minecome.terrain.GameplayGlideSafety;
import net.minecraft.entity.LivingEntity;
import net.minecraft.util.math.Vec3d;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Inspected pinned1.21.1 Yarn LivingEntity.travel(Vec3d): the fall-flying branch
 * computes gravity/lift/turning, applies(.99,.98,.99)drag, calls setVelocity,
 * then move(SELF,getVelocity()) before collision damage/landing. The second
 * hook checks that computed displacement without reproducing vanilla physics.
 * Only the exact installed client player is gated; server/NPC travel is untouched.
 */
@Mixin(LivingEntity.class)
public abstract class GameplayGlideTravelMixin {
    @Inject(method="travel",at=@At("HEAD"),cancellable=true)
    private void minecome$holdGlide(Vec3d input,CallbackInfo ci){
        if(GameplayGlideSafety.holdTravel((LivingEntity)(Object)this))ci.cancel();
    }
    @Inject(method="travel",at=@At(value="INVOKE",target="Lnet/minecraft/entity/LivingEntity;move(Lnet/minecraft/entity/MovementType;Lnet/minecraft/util/math/Vec3d;)V"),cancellable=true)
    private void minecome$boundGlideMove(Vec3d input,CallbackInfo ci){
        if(GameplayGlideSafety.holdMove((LivingEntity)(Object)this))ci.cancel();
    }
}
