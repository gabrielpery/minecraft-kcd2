package dev.minecome.terrain.mixin;

import dev.minecome.gameplay.GameplayProjectiles;
import net.minecraft.entity.Entity;
import net.minecraft.entity.projectile.PersistentProjectileEntity;
import net.minecraft.util.hit.*;
import net.minecraft.util.math.Vec3d;
import net.minecraft.world.*;
import org.spongepowered.asm.mixin.*;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.*;

/** Exact 1.21.1 tick/ray hooks inspected in projectile-impact-source-20261109. */
@Mixin(PersistentProjectileEntity.class)
public abstract class GroundProjectileCollisionMixin {
    @Shadow protected boolean inGround;
    @Inject(method="tick",at=@At("HEAD"),cancellable=true)
    private void minecome$awaitNativeSegment(CallbackInfo callback){if(GameplayProjectiles.beforeTick((PersistentProjectileEntity)(Object)this,inGround))callback.cancel();}
    @Inject(method="tick",at=@At("RETURN"))
    private void minecome$publishNativeSegment(CallbackInfo callback){GameplayProjectiles.afterTick((PersistentProjectileEntity)(Object)this,inGround);}
    @Redirect(method="tick",at=@At(value="INVOKE",target="Lnet/minecraft/world/World;raycast(Lnet/minecraft/world/RaycastContext;)Lnet/minecraft/util/hit/BlockHitResult;"))
    private BlockHitResult minecome$nativeScenery(World world,RaycastContext context){return GameplayProjectiles.blockHit((PersistentProjectileEntity)(Object)this,world,context);}
    @Inject(method="onBlockHit",at=@At("HEAD"))
    private void minecome$confirmNativeScenery(BlockHitResult hit,CallbackInfo callback){GameplayProjectiles.onBlockHit((PersistentProjectileEntity)(Object)this,hit);}
    @Inject(method="canHit",at=@At("RETURN"),cancellable=true)
    private void minecome$exactNativeActor(Entity candidate,CallbackInfoReturnable<Boolean> callback){if(callback.getReturnValueZ()&&!GameplayProjectiles.allowEntity((PersistentProjectileEntity)(Object)this,candidate))callback.setReturnValue(false);}
    @Inject(method="getEntityCollision",at=@At("RETURN"),cancellable=true)
    private void minecome$nativeActorContact(Vec3d from,Vec3d to,CallbackInfoReturnable<EntityHitResult> callback){callback.setReturnValue(GameplayProjectiles.entityHit((PersistentProjectileEntity)(Object)this,from,to,callback.getReturnValue()));}
}
