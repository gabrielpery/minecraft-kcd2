package dev.minecome.terrain.mixin;

import dev.minecome.terrain.GroundCollision;

import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import net.minecraft.block.BlockState;
import net.minecraft.block.ShapeContext;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.shape.VoxelShape;
import net.minecraft.world.BlockCollisionSpliterator;
import net.minecraft.world.BlockView;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;

/** Exact1.21.1 Yarn target verified in cached named bytecode; see docs/research/MOVEMENT.md. */
@Mixin(BlockCollisionSpliterator.class)
public abstract class GroundCollisionMixin {
    @WrapOperation(method="computeNext",at=@At(value="INVOKE",target=
            "Lnet/minecraft/block/BlockState;getCollisionShape(Lnet/minecraft/world/BlockView;Lnet/minecraft/util/math/BlockPos;Lnet/minecraft/block/ShapeContext;)Lnet/minecraft/util/shape/VoxelShape;"))
    private VoxelShape minecome$groundShape(BlockState state,BlockView world,BlockPos pos,ShapeContext context,Operation<VoxelShape> original) {
        return GroundCollision.merge(world,pos,original.call(state,world,pos,context));
    }
}
