package dev.minecome.terrain.mixin;

import dev.minecome.gameplay.GameplayTnt;
import net.minecraft.world.World;
import net.minecraft.world.explosion.Explosion;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Explosion.class)
public abstract class GroundExplosionMixin {
    @Shadow @Final private World world;
    @Inject(method="affectWorld",at=@At("HEAD"))
    private void minecome$ownedBlocks(boolean particles,CallbackInfo callback){GameplayTnt.beforeAffectWorld(world,(Explosion)(Object)this);}
}
