package dev.minecome.hud.mixin;

import dev.minecome.hud.GameplaySession;
import net.minecraft.client.gui.hud.InGameHud;
import net.minecraft.client.option.Perspective;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

/** Inspected Yarn1.21.1+build.3 InGameHud.renderCrosshair bytecode: the single
 * Perspective.isFirstPerson call at offset12 gates all vanilla crosshair drawing.
 * Inspection: runtime/evidence/perspective-source-20261108/InGameHud.txt.
 * Keep vanilla spectator/debug/attack-indicator and GUI visibility rules intact. */
@Mixin(InGameHud.class)
public abstract class GameplayCrosshairMixin {
    @Redirect(method="renderCrosshair(Lnet/minecraft/client/gui/DrawContext;Lnet/minecraft/client/render/RenderTickCounter;)V",
        at=@At(value="INVOKE",target="Lnet/minecraft/client/option/Perspective;isFirstPerson()Z"),require=1)
    private boolean minecome$aimInOwnedPerspective(Perspective perspective){
        return perspective.isFirstPerson()||GameplaySession.worldBlocksEnabled();
    }
}
