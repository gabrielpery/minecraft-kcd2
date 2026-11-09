package dev.minecome.gameplay;

import com.google.gson.JsonParser;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.UUID;

/** Ownership/resume tests. The actual create/reload cycle is checked in the gameplay fixture. */
public final class GameplayWorldTests {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void reject(Action action,String message)throws Exception{
        try{action.run();throw new AssertionError(message);}catch(IOException|IllegalArgumentException expected){checks++;}
    }
    public static void main(String[] args)throws Exception{
        var profile=new java.util.Properties();profile.setProperty("minecome.gameplay","true");
        check(!GameplayMode.bowFixtureEnabled(profile),"Ordinary gameplay cannot draw experimental bows");GameplayMode.requireExclusive(profile);
        profile.setProperty("minecome.gameplayBowFixture","true");reject(()->GameplayMode.requireExclusive(profile),"Bow gate requires standalone combat fixture");
        profile.setProperty("minecome.gameplayStandalone","true");profile.setProperty("minecome.gameplayCombat","true");profile.setProperty("minecome.gameplayWorldBlocks","true");profile.setProperty("minecome.gameplayFixture","combat");
        check(GameplayMode.bowFixtureEnabled(profile),"Exact optional standalone combat bow profile admitted");GameplayMode.requireExclusive(profile);
        for(String key:new String[]{"minecome.gameplayStandalone","minecome.gameplayCombat","minecome.gameplayWorldBlocks","minecome.gameplayFixture"}){
            String previous=profile.getProperty(key);profile.remove(key);check(!GameplayMode.bowFixtureEnabled(profile),"Missing bow gate "+key);reject(()->GameplayMode.requireExclusive(profile),"Reject missing bow gate "+key);profile.setProperty(key,previous);
        }
        profile.setProperty("minecome.someOtherFixture","true");reject(()->GameplayMode.requireExclusive(profile),"Bow gate does not permit other diagnostic ownership");
        profile.remove("minecome.someOtherFixture");profile.setProperty("minecome.gameplayProjectileFixture","true");GameplayMode.requireExclusive(profile);check(GameplayMode.projectileFixtureEnabled(profile),"Projectile simulator requires exact standalone bow fixture");
        profile.remove("minecome.gameplayBowFixture");reject(()->GameplayMode.requireExclusive(profile),"Projectile fixture cannot bypass bow owner");profile.remove("minecome.gameplayProjectileFixture");
        check(!GameplayMode.rangedUseEnabled(profile),"Ordinary standalone does not admit connected bow input");profile.remove("minecome.gameplayStandalone");profile.remove("minecome.gameplayFixture");check(GameplayMode.rangedUseEnabled(profile),"Connected Combat owns production bows");
        Path root=Files.createTempDirectory("minecome-gameplay-world-").toRealPath();
        Path saves=root.resolve("instance/saves");
        var fresh=GameplayWorld.prepare(saves,root);
        check(fresh.newlyCreated(),"First run reserves a fresh world");
        check(fresh.saveName().equals("MineCome-Gameplay"),"Fixed persistent name");
        check(fresh.directory().equals(saves.resolve(GameplayWorld.SAVE_NAME)),"Save stays in isolated instance");
        fresh.verifyOwnership();checks++;
        reject(()->GameplayWorld.prepare(saves,root),"Incomplete initial creation must not be replaced");
        byte[] level={10,0,1,2,3};
        Files.write(fresh.directory().resolve("level.dat"),level);
        Files.createDirectory(fresh.directory().resolve("playerdata"));
        Path player=fresh.directory().resolve("playerdata").resolve(UUID.randomUUID()+".dat");
        byte[] playerState={1,2,9,10,11,12};Files.write(player,playerState);
        byte[] marker=Files.readAllBytes(fresh.directory().resolve(GameplayWorld.MARKER_NAME));
        var reopened=GameplayWorld.prepare(saves,root);
        check(!reopened.newlyCreated(),"Second launch reopens");
        check(reopened.id().equals(fresh.id()),"Stable UUID across reopen");
        check(Arrays.equals(level,Files.readAllBytes(reopened.directory().resolve("level.dat"))),"World state preserved");
        check(Arrays.equals(playerState,Files.readAllBytes(player)),"Player inventory/mode data untouched");
        check(Arrays.equals(marker,Files.readAllBytes(reopened.directory().resolve(GameplayWorld.MARKER_NAME))),"Ownership marker unchanged on reopen");
        Path unrelated=root.resolve("unrelated/saves");Files.createDirectories(unrelated.resolve(GameplayWorld.SAVE_NAME));
        Files.writeString(unrelated.resolve(GameplayWorld.SAVE_NAME).resolve("level.dat"),"unrelated");
        reject(()->GameplayWorld.prepare(unrelated,root),"Never adopt a same-name unmarked save");
        check(Files.readString(unrelated.resolve(GameplayWorld.SAVE_NAME).resolve("level.dat")).equals("unrelated"),"Refusal preserves unrelated save");
        Path ownerFile=fresh.directory().resolve(GameplayWorld.MARKER_NAME);
        var changed=JsonParser.parseString(new String(marker,java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();
        changed.addProperty("world_id",UUID.randomUUID().toString());Files.writeString(ownerFile,changed.toString());
        reject(reopened::verifyOwnership,"Retained handle detects identity change");
        for(String invalid:new String[]{"{}","[]","{\"schema\":1}","null"}){
            Files.writeString(ownerFile,invalid);reject(()->GameplayWorld.prepare(saves,root),"Malformed marker rejected");
        }
        Files.write(ownerFile,marker);
        Files.write(fresh.directory().resolve("level.dat"),new byte[0]);
        reject(()->GameplayWorld.prepare(saves,root),"Empty level data is not silently recreated");
        reject(()->GameplayWorld.prepare(Path.of("relative/saves"),root),"Relative paths rejected");
        reject(()->GameplayWorld.prepare(root.resolve("../outside-saves").normalize(),root),"Outside instance rejected before writing");
        reject(()->GameplayWorld.prepare(root,root),"Project root itself is not an instance");
        System.out.println("GameplayWorldTests: "+checks+" checks passed; no game calls");
    }
}
