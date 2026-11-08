package dev.minecome.hud;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.Perspective;
import net.minecraft.util.math.Vec3d;

/** Vanilla camera selection for the owned guest; native camera authority is separate. */
public final class GameplayPerspective {
    private GameplayPerspective() {}

    /** Native schema3 is an acknowledged view, not a local F5 prediction. */
    public static Perspective acknowledged(int mode) {
        return switch(mode){case 0->Perspective.FIRST_PERSON;case 1->Perspective.THIRD_PERSON_BACK;case 2->Perspective.THIRD_PERSON_FRONT;
            default->throw new IllegalArgumentException("Unknown native perspective "+mode);};
    }

    public static void select(MinecraftClient client, Perspective perspective) {
        if (!client.isOnThread()) throw new IllegalStateException("Perspective must change on the client thread");
        var previous = client.options.getPerspective();
        if (previous == perspective) return;
        // Inspected Yarn 1.21.1+build.3 MinecraftClient.handleInputEvents,
        // offsets 13-87: setPerspective, refresh camera postprocessor, terrain.
        client.options.setPerspective(perspective);
        if (previous.isFirstPerson() != perspective.isFirstPerson())
            client.gameRenderer.onCameraEntitySet(perspective.isFirstPerson() ? client.getCameraEntity() : null);
        client.worldRenderer.scheduleTerrainUpdate();
    }

    public static GameplayWorldRenderer.View view(MinecraftClient client, float tickDelta, double verticalFov) {
        // GameRenderer updates the real Camera before HudRenderHooks.beforeWorld.
        // Camera.update owns its eye-height interpolation, front/back rotation
        // and eight-ray clipToSpace; never translate the player to fake a view.
        var camera = client.gameRenderer.getCamera();
        if (!camera.isReady() || camera.getFocusedEntity() != client.player) return null;
        return new GameplayWorldRenderer.View(camera.getPos(),
            new Vec3d(camera.getHorizontalPlane()).normalize(),
            new Vec3d(camera.getVerticalPlane()).normalize(), verticalFov);
    }
}
