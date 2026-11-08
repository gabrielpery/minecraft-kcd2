package dev.minecome.gameplay;

import java.util.*;

/** Bounded world-rendered palette: solid cubes, crafting tables and dry slabs/stairs/fences/walls.
 * State names are canonical and validated without initializing Minecraft registries,
 * so saved ownership validation also runs in the offline protocol tests.
 */
public final class GameplayBlocksPalette {
    private static final Set<String> PLAIN;
    private static final Set<String> AXIS;
    private static final Set<String> SLABS;
    private static final Set<String> STAIRS;
    private static final Set<String> FENCES;
    private static final Set<String> WALLS;
    private static final Set<String> SLAB_SUFFIXES=Set.of("[type=bottom,waterlogged=false]","[type=top,waterlogged=false]","[type=double,waterlogged=false]");
    private static final Set<String> STAIR_SUFFIXES;
    private static final Set<String> FENCE_SUFFIXES;
    private static final Set<String> WALL_SUFFIXES;
    static {
        var plain=new HashSet<String>();
        for(var name:List.of("stone","cobblestone","dirt","coarse_dirt","granite","polished_granite",
                "diorite","polished_diorite","andesite","polished_andesite","bricks","stone_bricks",
                "mossy_stone_bricks","cracked_stone_bricks","chiseled_stone_bricks","sandstone",
                "cut_sandstone","chiseled_sandstone","smooth_sandstone","red_sandstone","cut_red_sandstone",
                "chiseled_red_sandstone","smooth_red_sandstone","iron_block","gold_block","diamond_block",
                "emerald_block","lapis_block","coal_block","netherite_block","quartz_block",
                "chiseled_quartz_block","smooth_quartz","obsidian","crafting_table"))plain.add("minecraft:"+name);
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
        var slab=new HashSet<String>();var stair=new HashSet<String>();
        for(var material:List.of("oak","spruce","birch","jungle","acacia","dark_oak","mangrove","cherry",
                "bamboo","crimson","warped","stone","cobblestone","granite","polished_granite","diorite",
                "polished_diorite","andesite","polished_andesite","brick","stone_brick","mossy_stone_brick",
                "sandstone","smooth_sandstone","red_sandstone","smooth_red_sandstone","quartz","smooth_quartz")){
            slab.add("minecraft:"+material+"_slab");stair.add("minecraft:"+material+"_stairs");
        }
        slab.add("minecraft:cut_sandstone_slab");slab.add("minecraft:cut_red_sandstone_slab");
        SLABS=Set.copyOf(slab);STAIRS=Set.copyOf(stair);
        // Inspected pinned Yarn1.21.1+build.3 SlabBlock/StairsBlock appendProperties
        // and their enums; stateName serializes these properties alphabetically.
        // Evidence: runtime/evidence/block-shapes-source-20261106.
        var stairSuffixes=new HashSet<String>();
        for(var facing:List.of("north","south","east","west"))for(var half:List.of("bottom","top"))
            for(var shape:List.of("straight","inner_left","inner_right","outer_left","outer_right"))
                stairSuffixes.add("[facing="+facing+",half="+half+",shape="+shape+",waterlogged=false]");
        STAIR_SUFFIXES=Set.copyOf(stairSuffixes);
        var fences=new HashSet<String>();
        for(var wood:List.of("oak","spruce","birch","jungle","acacia","dark_oak","mangrove","cherry",
                "bamboo","crimson","warped"))fences.add("minecraft:"+wood+"_fence");
        fences.add("minecraft:nether_brick_fence");FENCES=Set.copyOf(fences);
        var walls=new HashSet<String>();
        for(var material:List.of("cobblestone","mossy_cobblestone","brick","granite","diorite","andesite",
                "stone_brick","mossy_stone_brick","sandstone","red_sandstone"))walls.add("minecraft:"+material+"_wall");
        WALLS=Set.copyOf(walls);
        // Pinned FenceBlock/WallBlock appendProperties, WallShape names and
        // neighbor updates inspected in runtime/evidence/connected-shapes-source-20261106.
        // stateName uses alphabetical ordering; all vanilla dry connections,
        // including wall post changes, must survive neighbor updates and saves.
        var fenceSuffixes=new HashSet<String>();var wallSuffixes=new HashSet<String>();
        for(var east:List.of(false,true))for(var north:List.of(false,true))
            for(var south:List.of(false,true))for(var west:List.of(false,true))
                fenceSuffixes.add("[east="+east+",north="+north+",south="+south+",waterlogged=false,west="+west+"]");
        for(var east:List.of("none","low","tall"))for(var north:List.of("none","low","tall"))
            for(var south:List.of("none","low","tall"))for(var up:List.of(false,true))
                for(var west:List.of("none","low","tall"))
                    wallSuffixes.add("[east="+east+",north="+north+",south="+south+",up="+up+",waterlogged=false,west="+west+"]");
        FENCE_SUFFIXES=Set.copyOf(fenceSuffixes);WALL_SUFFIXES=Set.copyOf(wallSuffixes);
    }
    private GameplayBlocksPalette(){}
    public static boolean supportsBlock(String id){return id!=null&&(PLAIN.contains(id)||AXIS.contains(id)||SLABS.contains(id)||STAIRS.contains(id)||FENCES.contains(id)||WALLS.contains(id));}
    public static boolean supportsState(String state){
        if(state==null)return false;if(PLAIN.contains(state))return true;
        for(var value:List.of("x","y","z")){
            var suffix="[axis="+value+"]";
            if(state.endsWith(suffix)&&AXIS.contains(state.substring(0,state.length()-suffix.length())))return true;
        }
        int properties=state.indexOf('[');
        if(properties>0){var block=state.substring(0,properties);var suffix=state.substring(properties);
            return SLABS.contains(block)&&SLAB_SUFFIXES.contains(suffix)||STAIRS.contains(block)&&STAIR_SUFFIXES.contains(suffix)||
                FENCES.contains(block)&&FENCE_SUFFIXES.contains(suffix)||WALLS.contains(block)&&WALL_SUFFIXES.contains(suffix);}
        return false;
    }
    public static Set<String> blockIds(){var all=new TreeSet<>(PLAIN);all.addAll(AXIS);all.addAll(SLABS);all.addAll(STAIRS);all.addAll(FENCES);all.addAll(WALLS);return Collections.unmodifiableSet(all);}
}
