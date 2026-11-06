package dev.minecome.gameplay;

import java.util.*;

/** Initial world-rendered palette: opaque full cubes without scheduled behaviour.
 * State names are canonical and validated without initializing Minecraft registries,
 * so saved ownership validation also runs in the offline protocol tests.
 */
public final class GameplayBlocksPalette {
    private static final Set<String> PLAIN;
    private static final Set<String> AXIS;
    static {
        var plain=new HashSet<String>();
        for(var name:List.of("stone","cobblestone","dirt","coarse_dirt","granite","polished_granite",
                "diorite","polished_diorite","andesite","polished_andesite","bricks","stone_bricks",
                "mossy_stone_bricks","cracked_stone_bricks","chiseled_stone_bricks","sandstone",
                "cut_sandstone","chiseled_sandstone","smooth_sandstone","red_sandstone","cut_red_sandstone",
                "chiseled_red_sandstone","smooth_red_sandstone","iron_block","gold_block","diamond_block",
                "emerald_block","lapis_block","coal_block","netherite_block","quartz_block",
                "chiseled_quartz_block","smooth_quartz","obsidian"))plain.add("minecraft:"+name);
        for(var wood:List.of("oak","spruce","birch","jungle","acacia","dark_oak","mangrove","cherry",
                "bamboo","crimson","warped"))plain.add("minecraft:"+wood+"_planks");
        for(var color:List.of("white","orange","magenta","light_blue","yellow","lime","pink","gray",
                "light_gray","cyan","purple","blue","brown","green","red","black")){
            plain.add("minecraft:"+color+"_wool");plain.add("minecraft:"+color+"_concrete");
        }
        PLAIN=Set.copyOf(plain);var axis=new HashSet<String>();
        for(var wood:List.of("oak","spruce","birch","jungle","acacia","dark_oak","mangrove","cherry")){
            axis.add("minecraft:"+wood+"_log");axis.add("minecraft:stripped_"+wood+"_log");
        }
        AXIS=Set.copyOf(axis);
    }
    private GameplayBlocksPalette(){}
    public static boolean supportsBlock(String id){return PLAIN.contains(id)||AXIS.contains(id);}
    public static boolean supportsState(String state){
        if(state==null)return false;if(PLAIN.contains(state))return true;
        for(var value:List.of("x","y","z")){
            var suffix="[axis="+value+"]";
            if(state.endsWith(suffix)&&AXIS.contains(state.substring(0,state.length()-suffix.length())))return true;
        }
        return false;
    }
    public static Set<String> blockIds(){var all=new TreeSet<>(PLAIN);all.addAll(AXIS);return Collections.unmodifiableSet(all);}
}
