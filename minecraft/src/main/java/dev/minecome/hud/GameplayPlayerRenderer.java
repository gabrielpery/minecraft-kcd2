package dev.minecome.hud;

import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.AbstractClientPlayerEntity;
import net.minecraft.client.render.VertexConsumerProvider;
import net.minecraft.client.util.SkinTextures;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.util.Identifier;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;

/** The real local player's model and equipped-item features in the world layer.
 * Inspected the cached Yarn1.21.1+build.3 bytecode: WorldRenderer.renderEntity
 * interpolates lastRenderX/Y/Z and prevYaw; EntityRenderDispatcher.render applies
 * EntityRenderer.getPositionOffset before calling the renderer. The registered
 * PlayerEntityRenderer supplies vanilla pose/limb animation, armor, held items,
 * Elytra and other player features. No entity or animation state is substituted.
 */
public final class GameplayPlayerRenderer {
    private static final SkinTextures STEVE=new SkinTextures(
        Identifier.ofVanilla("textures/entity/player/wide/steve.png"),null,null,null,SkinTextures.Model.WIDE,true);
    private GameplayPlayerRenderer(){}

    /** DefaultSkinHelper's inspected index 15 is wide Steve; getTexture() instead
     * returns slim Steve. This identifier resolves the installed Minecraft asset,
     * verified in the pinned game JAR, and never bundles a copied game texture.
     */
    public static SkinTextures classicSkin(AbstractClientPlayerEntity player){
        return GameplaySession.worldBlocksEnabled()&&player==MinecraftClient.getInstance().player?STEVE:null;
    }

    /** Returns whether player geometry was submitted, not whether it was visible.
     * The caller owns the world projection, terrain depth and final buffer draw.
     */
    static boolean render(float tickDelta,Vec3d origin,MatrixStack matrices,VertexConsumerProvider vertices){
        RenderSystem.assertOnRenderThread();
        var client=MinecraftClient.getInstance();var player=client.player;
        if(player==null||client.world==null||client.options.getPerspective().isFirstPerson()||
            client.getCameraEntity()!=player)return false;
        var dispatcher=client.getEntityRenderDispatcher();
        var renderer=dispatcher.getRenderer(player);
        var offset=renderer.getPositionOffset(player,tickDelta);
        double x=MathHelper.lerp(tickDelta,player.lastRenderX,player.getX())-origin.x+offset.x;
        double y=MathHelper.lerp(tickDelta,player.lastRenderY,player.getY())-origin.y+offset.y;
        double z=MathHelper.lerp(tickDelta,player.lastRenderZ,player.getZ())-origin.z+offset.z;
        float yaw=MathHelper.lerp(tickDelta,player.prevYaw,player.getYaw());
        matrices.push();
        try {
            matrices.translate(x,y,z);
            // Call the registered renderer directly: dispatcher.render also adds
            // a Minecraft-ground shadow and debug hitboxes that do not belong in
            // the host scene. This does not change global dispatcher shadow flags.
            // LivingEntityRenderer.hasLabel suppresses the camera entity's label.
            // GameplayHandRenderState prepared world diffuse lighting/dispatchers;
            // RenderPhase.Lightmap and Overlay bind and release their textures
            // during each vanilla layer draw. Keep this pass's terrain depth.
            renderer.render(player,yaw,tickDelta,matrices,vertices,dispatcher.getLight(player,tickDelta));
            return true;
        } finally {
            matrices.pop();
        }
    }
}
