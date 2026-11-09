package dev.minecome.gameplay;

import java.util.Properties;
import java.util.Set;

/** Explicit production session identity, separate from diagnostic profiles. */
public final class GameplayMode {
    public static final int SCHEMA=3;
    public static final long MAX_LEASE_MS=86_400_000L;
    private GameplayMode(){}
    public static boolean enabled(){return Boolean.getBoolean("minecome.gameplay");}
    public static boolean bowFixtureEnabled(Properties properties){return Boolean.parseBoolean(properties.getProperty("minecome.gameplayBowFixture","false"))&&
        Boolean.parseBoolean(properties.getProperty("minecome.gameplay","false"))&&Boolean.parseBoolean(properties.getProperty("minecome.gameplayStandalone","false"))&&
        Boolean.parseBoolean(properties.getProperty("minecome.gameplayCombat","false"))&&Boolean.parseBoolean(properties.getProperty("minecome.gameplayWorldBlocks","false"))&&
        "combat".equals(properties.getProperty("minecome.gameplayFixture"));}
    public static boolean projectileFixtureEnabled(Properties properties){return bowFixtureEnabled(properties)&&Boolean.parseBoolean(properties.getProperty("minecome.gameplayProjectileFixture","false"));}
    public static boolean rangedUseEnabled(Properties properties){return bowFixtureEnabled(properties)||Boolean.parseBoolean(properties.getProperty("minecome.gameplay","false"))&&
        Boolean.parseBoolean(properties.getProperty("minecome.gameplayCombat","false"))&&Boolean.parseBoolean(properties.getProperty("minecome.gameplayWorldBlocks","false"))&&!Boolean.parseBoolean(properties.getProperty("minecome.gameplayStandalone","false"));}
    public static void requireExclusive(Properties properties){
        if(!Boolean.parseBoolean(properties.getProperty("minecome.gameplay","false")))return;
        if(Boolean.parseBoolean(properties.getProperty("minecome.gameplayBowFixture","false"))&&!bowFixtureEnabled(properties))
            throw new IllegalArgumentException("Experimental bow input requires the standalone WorldBlocks combat fixture");
        if(Boolean.parseBoolean(properties.getProperty("minecome.gameplayProjectileFixture","false"))&&!projectileFixtureEnabled(properties))throw new IllegalArgumentException("Projectile fixture requires the standalone bow fixture");
        for(String key:properties.stringPropertyNames()){
            if(!key.startsWith("minecome.")||!"true".equalsIgnoreCase(properties.getProperty(key)))continue;
            if(key.endsWith("Lab")||key.endsWith("Fixture")&&!Set.of("minecome.gameplayFixture","minecome.gameplayBowFixture","minecome.gameplayProjectileFixture").contains(key)||
                    key.equals("minecome.smokeWorld")||key.equals("minecome.dynamicBridgeSmoke")||
                    key.equals("minecome.hudPhysicalMovement")||key.equals("minecome.hudWalkingAimed"))
                throw new IllegalArgumentException("Gameplay cannot share a diagnostic owner: "+key);
        }
    }
}
