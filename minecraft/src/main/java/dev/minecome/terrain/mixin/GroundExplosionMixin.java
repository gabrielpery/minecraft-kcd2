package dev.minecome.terrain.mixin;

import dev.minecome.gameplay.GameplayTnt;
import dev.minecome.gameplay.GameplayBlasts;
import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import net.minecraft.entity.Entity;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.World;
import net.minecraft.world.explosion.Explosion;
import net.minecraft.world.explosion.ExplosionBehavior;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(Explosion.class)
public abstract class GroundExplosionMixin {
    @Shadow @Final private World world;
    @Inject(method="affectWorld",at=@At("HEAD"))
    private void minecome$ownedBlocks(boolean particles,CallbackInfo callback){GameplayTnt.beforeAffectWorld(world,(Explosion)(Object)this);}
    @Inject(method="getExposure",at=@At("HEAD"),cancellable=true)
    private static void minecome$nativeExposure(Vec3d center,Entity target,CallbackInfoReturnable<Float> callback){var exposure=GameplayBlasts.exposure(center,target);if(exposure!=null)callback.setReturnValue(exposure);}
    @WrapOperation(method="collectBlocksAndDamageEntities",at=@At(value="INVOKE",target="Lnet/minecraft/world/explosion/ExplosionBehavior;shouldDamage(Lnet/minecraft/world/explosion/Explosion;Lnet/minecraft/entity/Entity;)Z"))
    private boolean minecome$nativeShield(ExplosionBehavior behavior,Explosion explosion,Entity target,Operation<Boolean> original){return GameplayBlasts.shouldDamage(explosion,target,original.call(behavior,explosion,target));}
}
