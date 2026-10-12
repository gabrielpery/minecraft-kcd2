package dev.minecome.terrain.mixin;

import dev.minecome.terrain.GroundMovementLab;

import net.minecraft.client.network.ClientPlayNetworkHandler;
import net.minecraft.network.packet.s2c.play.PlayerPositionLookS2CPacket;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** RETURN avoids counting the initial off-thread dispatch and its main-thread retry twice. */
@Mixin(ClientPlayNetworkHandler.class)
public abstract class GroundCorrectionMixin {
    @Inject(method="onPlayerPositionLook",at=@At("RETURN"))
    private void minecome$groundCorrection(PlayerPositionLookS2CPacket packet,CallbackInfo ci) {
        GroundMovementLab.positionCorrection();
        dev.minecome.input.ExternalInputLab.positionCorrection();
    }
}
