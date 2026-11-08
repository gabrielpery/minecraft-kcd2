package dev.minecome.terrain.mixin;

import dev.minecome.terrain.GroundCollision;
import net.minecraft.entity.ItemEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Pinned ItemEntity.tick noClip/pushOutOfBlocks path inspected in
 * runtime/evidence/dropped-item-source-20261108/ItemEntity.txt. */
@Mixin(ItemEntity.class)
public abstract class GroundItemCollisionMixin {
    @Inject(method="tick",at=@At("HEAD"))
    private void minecome$recoverFractionalTerrain(CallbackInfo callback){
        GroundCollision.recoverItem((ItemEntity)(Object)this);
    }
}
