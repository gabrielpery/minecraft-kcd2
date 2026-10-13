package dev.minecome.hud;

import com.google.gson.JsonObject;
import net.minecraft.client.MinecraftClient;

/** Client-thread lifecycle shared by the separate fixed-cell and aimed experiments. */
interface HudBlockBridge extends AutoCloseable {
    void tick(MinecraftClient client, boolean actionsEnabled);
    boolean failed();
    String failure();
    JsonObject evidence();
    void close();
}
