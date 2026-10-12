package dev.minecome;

import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.model.BakedModel;
import net.minecraft.client.render.model.BakedQuad;
import net.minecraft.client.texture.NativeImage;
import net.minecraft.client.texture.SpriteAtlasTexture;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.random.Random;
import org.lwjgl.opengl.GL11;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Exports locally installed vanilla model quads and stitched atlas on the render thread.
 * User-local runtime output; no Minecraft assets are distributed in the repository. */
public final class BlockModelExport {
    private BlockModelExport() {}
    public static Path exportStone(MinecraftClient client) throws IOException {
        RenderSystem.assertOnRenderThread();
        Path directory=client.runDirectory.toPath().resolve("minecome-export/stone");
        Files.createDirectories(directory);
        var state=Blocks.STONE.getDefaultState();
        BakedModel model=client.getBlockRenderManager().getModel(state);
        List<BakedQuad> quads=new ArrayList<>(model.getQuads(state,null,Random.create(42)));
        for(Direction face:Direction.values()) quads.addAll(model.getQuads(state,face,Random.create(42)));
        try(BufferedWriter out=Files.newBufferedWriter(directory.resolve("stone.obj"),StandardCharsets.UTF_8)) {
            out.write("# Actual Minecraft 1.21.1 BakedModel quads; MC +Y up; unit block.\nmtllib stone.mtl\nusemtl minecraft_atlas\n");
            int vertexIndex=1;
            for(BakedQuad quad:quads) {
                int[] data=quad.getVertexData();int stride=data.length/4;
                if(stride<6) throw new IOException("Unexpected vanilla vertex stride: "+stride);
                for(int i=0;i<4;i++) {
                    int base=i*stride;
                    out.write(String.format(Locale.ROOT,"v %.9f %.9f %.9f%n",Float.intBitsToFloat(data[base]),
                            Float.intBitsToFloat(data[base+1]),Float.intBitsToFloat(data[base+2])));
                    // NativeImage row origin is top-left; OBJ V origin is bottom-left.
                    out.write(String.format(Locale.ROOT,"vt %.9f %.9f%n",Float.intBitsToFloat(data[base+4]),
                            1.0f-Float.intBitsToFloat(data[base+5])));
                }
                out.write(String.format(Locale.ROOT,"f %d/%d %d/%d %d/%d %d/%d%n",vertexIndex,vertexIndex,
                        vertexIndex+1,vertexIndex+1,vertexIndex+2,vertexIndex+2,vertexIndex+3,vertexIndex+3));vertexIndex+=4;
            }
        }
        Files.writeString(directory.resolve("stone.mtl"),"newmtl minecraft_atlas\nKd 1 1 1\nmap_Kd block-atlas.png\n",StandardCharsets.UTF_8);
        var texture=client.getTextureManager().getTexture(SpriteAtlasTexture.BLOCK_ATLAS_TEXTURE);
        int previous=GL11.glGetInteger(GL11.GL_TEXTURE_BINDING_2D);
        try {
            GL11.glBindTexture(GL11.GL_TEXTURE_2D,texture.getGlId());
            int width=GL11.glGetTexLevelParameteri(GL11.GL_TEXTURE_2D,0,GL11.GL_TEXTURE_WIDTH);
            int height=GL11.glGetTexLevelParameteri(GL11.GL_TEXTURE_2D,0,GL11.GL_TEXTURE_HEIGHT);
            if(width<=0 || height<=0 || width>16384 || height>16384) throw new IOException("Invalid atlas dimensions");
            try(NativeImage image=new NativeImage(width,height,false)) {
                image.loadFromTextureImage(0,false);image.writeTo(directory.resolve("block-atlas.png"));
            }
        }finally { GL11.glBindTexture(GL11.GL_TEXTURE_2D,previous); }
        Files.writeString(directory.resolve("README.txt"),"Exported from the active vanilla Minecraft BakedModel and GPU block atlas.\n"+
                "MC coordinate space; one block is one unit. Origin is block corner.\n"+
                "Runtime extraction does not prove KCD rendering or occlusion. Keep these game assets local.\n",StandardCharsets.UTF_8);
        return directory;
    }
}
