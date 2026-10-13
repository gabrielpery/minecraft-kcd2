package dev.minecome.hud.mixin;

import net.minecraft.client.util.Window;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

/** Inspected mapped1.21.1 Window.vsync, set only by its GLFW swap-interval callback. */
@Mixin(Window.class)
public interface HudWindowVsyncAccessor {
    @Accessor("vsync") boolean minecome$vsync();
}
