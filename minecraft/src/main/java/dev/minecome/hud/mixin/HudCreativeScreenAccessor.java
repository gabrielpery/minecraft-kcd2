package dev.minecome.hud.mixin;

import net.minecraft.client.gui.screen.ingame.CreativeInventoryScreen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.*;

/** Read-only exact Yarn1.21.1 fields/method, inspected in the cached named jar. */
@Mixin(CreativeInventoryScreen.class)
public interface HudCreativeScreenAccessor {
    @Accessor("scrollPosition") float minecome$scrollPosition();
    @Invoker("hasScrollbar") boolean minecome$hasScrollbar();
}
