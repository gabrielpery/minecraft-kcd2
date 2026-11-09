package dev.minecome.terrain.mixin;

import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import dev.minecome.gameplay.GameplayTnt;
import net.minecraft.block.TntBlock;
import net.minecraft.block.BlockState;
import net.minecraft.entity.Entity;
import net.minecraft.entity.LivingEntity;
import net.minecraft.entity.TntEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.entity.projectile.ProjectileEntity;
import net.minecraft.item.ItemStack;
import net.minecraft.item.Items;
import net.minecraft.util.Hand;
import net.minecraft.util.ItemActionResult;
import net.minecraft.util.hit.BlockHitResult;
import net.minecraft.util.math.BlockPos;
import net.minecraft.world.World;
import net.minecraft.world.explosion.Explosion;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(TntBlock.class)
public abstract class GroundTntBlockMixin {
    @Inject(method="onUseWithItem",at=@At("HEAD"),cancellable=true)
    private void minecome$guardIgnition(ItemStack stack,BlockState state,World world,BlockPos pos,PlayerEntity player,Hand hand,BlockHitResult hit,CallbackInfoReturnable<ItemActionResult> callback){
        if((stack.isOf(Items.FLINT_AND_STEEL)||stack.isOf(Items.FIRE_CHARGE))&&GameplayTnt.denyPrime(world,pos,player))callback.setReturnValue(ItemActionResult.FAIL);
    }
    @Inject(method="onBlockAdded",at=@At("HEAD"),cancellable=true)
    private void minecome$guardAdded(BlockState state,World world,BlockPos pos,BlockState oldState,boolean notify,CallbackInfo callback){if(GameplayTnt.denyPrime(world,pos,null))callback.cancel();}
    @Inject(method="neighborUpdate",at=@At("HEAD"),cancellable=true)
    private void minecome$guardPower(BlockState state,World world,BlockPos pos,net.minecraft.block.Block source,BlockPos sourcePos,boolean notify,CallbackInfo callback){if(GameplayTnt.denyPrime(world,pos,null))callback.cancel();}
    @Inject(method="onProjectileHit",at=@At("HEAD"),cancellable=true)
    private void minecome$guardProjectile(World world,BlockState state,BlockHitResult hit,ProjectileEntity projectile,CallbackInfo callback){if(GameplayTnt.denyPrime(world,hit.getBlockPos(),projectile.getOwner() instanceof LivingEntity owner?owner:null))callback.cancel();}
    @WrapOperation(method="primeTnt(Lnet/minecraft/world/World;Lnet/minecraft/util/math/BlockPos;Lnet/minecraft/entity/LivingEntity;)V",at=@At(value="INVOKE",target="Lnet/minecraft/world/World;spawnEntity(Lnet/minecraft/entity/Entity;)Z"))
    private static boolean minecome$prime(World world,Entity entity,Operation<Boolean> original,World source,BlockPos position,LivingEntity igniter){
        return entity instanceof TntEntity tnt?GameplayTnt.spawn(source,position,tnt,null,()->original.call(world,entity)):original.call(world,entity);
    }
    @WrapOperation(method="onDestroyedByExplosion",at=@At(value="INVOKE",target="Lnet/minecraft/world/World;spawnEntity(Lnet/minecraft/entity/Entity;)Z"))
    private boolean minecome$chain(World world,Entity entity,Operation<Boolean> original,World source,BlockPos position,Explosion explosion){
        return entity instanceof TntEntity tnt?GameplayTnt.spawn(source,position,tnt,explosion,()->original.call(world,entity)):original.call(world,entity);
    }
}
