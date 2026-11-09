package dev.minecome.terrain.mixin;

import net.minecraft.entity.TntEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Invoker;

/** Resumes the unchanged private vanilla detonation after its async native grant. */
@Mixin(TntEntity.class)
public interface TntBlastInvoker {
    @Invoker("explode") void minecome$explode();
}
