package dev.minecome.hud.mixin;

import dev.minecome.hud.GameplayPlayerRenderer;
import net.minecraft.client.network.AbstractClientPlayerEntity;
import net.minecraft.client.util.SkinTextures;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(AbstractClientPlayerEntity.class)
public abstract class GameplayPlayerSkinMixin {
    // Inspected Yarn1.21.1+build.3: dispatcher renderer selection and the player's
    // body/arms both use AbstractClientPlayerEntity.getSkinTextures(). Override
    // only MineCome's owned local session; ordinary worlds retain their skin.
    @Inject(method="getSkinTextures",at=@At("HEAD"),cancellable=true)
    private void minecome$localSteve(CallbackInfoReturnable<SkinTextures> callback){
        var skin=GameplayPlayerRenderer.classicSkin((AbstractClientPlayerEntity)(Object)this);
        if(skin!=null)callback.setReturnValue(skin);
    }
}
