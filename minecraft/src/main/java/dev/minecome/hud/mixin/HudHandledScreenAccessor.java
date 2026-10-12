package dev.minecome.hud.mixin;

import net.minecraft.client.gui.screen.ingame.HandledScreen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

/** Exact Yarn1.21.1 protected GUI origin fields, inspected in the cached named jar. */
@Mixin(HandledScreen.class)
public interface HudHandledScreenAccessor {
    @Accessor("x") int minecome$originX();
    @Accessor("y") int minecome$originY();
}
