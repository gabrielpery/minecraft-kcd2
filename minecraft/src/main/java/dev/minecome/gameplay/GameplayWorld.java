package dev.minecome.gameplay;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import net.minecraft.client.MinecraftClient;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.resource.DataConfiguration;
import net.minecraft.world.Difficulty;
import net.minecraft.world.GameMode;
import net.minecraft.world.GameRules;
import net.minecraft.world.gen.GeneratorOptions;
import net.minecraft.world.gen.WorldPresets;
import net.minecraft.world.level.LevelInfo;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Set;
import java.util.UUID;

/** Owned persistent guest save. Bootstrap superflat is not imported KCD collision. */
public final class GameplayWorld {
    public static final String SAVE_NAME="MineCome-Gameplay";
    public static final String MARKER_NAME="minecome-world.json";
    private static final String KIND="minecome_gameplay_world_v1";
    private final Path savesDirectory,directory;
    private final UUID id;
    private final boolean newlyCreated;
    private boolean opened;

    private GameplayWorld(Path savesDirectory,Path directory,UUID id,boolean newlyCreated){
        this.savesDirectory=savesDirectory;this.directory=directory;this.id=id;this.newlyCreated=newlyCreated;
    }
    public String saveName(){return SAVE_NAME;}
    public UUID id(){return id;}
    public Path directory(){return directory;}
    /** True only for this reservation; never a request to reset an existing world. */
    public boolean newlyCreated(){return newlyCreated;}

    /** Refuses unrelated or incomplete saves. The caller provides its isolated instance's saves directory. */
    public static GameplayWorld prepare(Path savesDirectory,Path projectRoot)throws IOException{
        if(savesDirectory==null||projectRoot==null||!savesDirectory.isAbsolute()||!projectRoot.isAbsolute())
            throw new IllegalArgumentException("Absolute owned gameplay paths required");
        Path root=projectRoot.toRealPath();
        Path saves=savesDirectory.normalize();
        if(!saves.startsWith(root)||saves.equals(root))throw new IOException("Gameplay instance must be inside the project");
        // Check an existing ancestor before createDirectories so a redirected
        // instance cannot create its missing child directories outside the project.
        Path ancestor=saves;
        while(!Files.exists(ancestor,LinkOption.NOFOLLOW_LINKS))ancestor=ancestor.getParent();
        if(!ancestor.toRealPath().startsWith(root))throw new IOException("Gameplay instance ancestor left the project");
        Files.createDirectories(saves);
        saves=saves.toRealPath();
        if(!saves.startsWith(root)||saves.equals(root))throw new IOException("Resolved gameplay instance left the project");
        Path directory=saves.resolve(SAVE_NAME);
        if(Files.exists(directory,LinkOption.NOFOLLOW_LINKS)){
            verifyDirectory(directory,saves);
            UUID id=readIdentity(directory);
            requireLevel(directory);
            return new GameplayWorld(saves,directory,id,false);
        }
        // CREATE_NEW and createDirectory never adopt or replace another world.
        Files.createDirectory(directory);
        UUID id=UUID.randomUUID();
        var marker=new JsonObject();marker.addProperty("schema",1);marker.addProperty("kind",KIND);
        marker.addProperty("save",SAVE_NAME);marker.addProperty("world_id",id.toString());
        Files.writeString(directory.resolve(MARKER_NAME),marker.toString(),StandardCharsets.UTF_8,
                StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE);
        return new GameplayWorld(saves,directory,id,true);
    }

    /** Read-only ownership check, useful before recording state or restoring a session. */
    public void verifyOwnership()throws IOException{
        verifyDirectory(directory,savesDirectory);
        if(!id.equals(readIdentity(directory)))throw new IOException("Gameplay save ownership changed");
    }

    /** Must run on the Minecraft client thread; ordinary saved rules and player state are preserved. */
    public void open(MinecraftClient client,Runnable onCancelled)throws IOException{
        if(client==null||onCancelled==null)throw new IllegalArgumentException("Client and cancellation callback required");
        if(!client.isOnThread())throw new IllegalStateException("Gameplay world must open on the client thread");
        if(opened||client.world!=null||client.isIntegratedServerRunning())throw new IllegalStateException("A world is already opening or active");
        if(!client.getLevelStorage().getSavesDirectory().toRealPath().equals(savesDirectory))
            throw new IOException("Gameplay world belongs to another Minecraft instance");
        verifyOwnership();
        if(newlyCreated){
            if(Files.exists(directory.resolve("level.dat"),LinkOption.NOFOLLOW_LINKS)
                    ||Files.exists(directory.resolve("level.dat_old"),LinkOption.NOFOLLOW_LINKS))
                throw new IOException("Reserved new world acquired unexpected saved data");
            GameRules rules=new GameRules();
            LevelInfo info=new LevelInfo(SAVE_NAME,GameMode.CREATIVE,false,Difficulty.NORMAL,true,rules,DataConfiguration.SAFE_MODE);
            opened=true;
            // Inspected Yarn 1.21.1+build.3 IntegratedServerLoader.createAndStart: creates
            // a LevelStorage session, loads vanilla datapacks and starts the integrated server.
            client.createIntegratedServerLoader().createAndStart(SAVE_NAME,info,new GeneratorOptions(42,false,false),
                    registries->registries.get(RegistryKeys.WORLD_PRESET).get(WorldPresets.FLAT).createDimensionsRegistryHolder(),client.currentScreen);
        }else{
            requireLevel(directory);opened=true;
            // Inspected same mapped class: start(String,Runnable) opens the existing
            // LevelStorage session and invokes vanilla loading, preserving saved state.
            client.createIntegratedServerLoader().start(SAVE_NAME,onCancelled);
        }
    }

    private static void verifyDirectory(Path directory,Path saves)throws IOException{
        if(Files.isSymbolicLink(directory)||!Files.isDirectory(directory,LinkOption.NOFOLLOW_LINKS)
                ||!directory.toRealPath().equals(saves.resolve(SAVE_NAME)))
            throw new IOException("Gameplay save directory is not the owned direct child");
    }
    private static UUID readIdentity(Path directory)throws IOException{
        Path marker=directory.resolve(MARKER_NAME);
        if(Files.isSymbolicLink(marker)||!Files.isRegularFile(marker,LinkOption.NOFOLLOW_LINKS)
                ||Files.size(marker)<2||Files.size(marker)>2048)throw new IOException("Missing or invalid MineCome ownership marker");
        try{
            var data=JsonParser.parseString(Files.readString(marker,StandardCharsets.UTF_8)).getAsJsonObject();
            if(!data.keySet().equals(Set.of("schema","kind","save","world_id"))
                    ||!data.get("schema").isJsonPrimitive()||!data.getAsJsonPrimitive("schema").isNumber()
                    ||!data.get("schema").getAsString().equals("1")
                    ||!string(data,"kind").equals(KIND)||!string(data,"save").equals(SAVE_NAME))
                throw new IllegalArgumentException("Unexpected world marker schema");
            String value=string(data,"world_id");UUID id=UUID.fromString(value);
            if(!id.toString().equals(value))throw new IllegalArgumentException("Noncanonical world UUID");
            return id;
        }catch(RuntimeException invalid){throw new IOException("Invalid MineCome ownership marker",invalid);}
    }
    private static String string(JsonObject object,String key){
        if(!object.get(key).isJsonPrimitive()||!object.getAsJsonPrimitive(key).isString())
            throw new IllegalArgumentException("World marker string required");
        return object.get(key).getAsString();
    }
    private static void requireLevel(Path directory)throws IOException{
        Path level=directory.resolve("level.dat");
        if(Files.isSymbolicLink(level)||!Files.isRegularFile(level,LinkOption.NOFOLLOW_LINKS)||Files.size(level)==0)
            throw new IOException("Owned gameplay save is incomplete; preserving it without recreation");
    }
}
