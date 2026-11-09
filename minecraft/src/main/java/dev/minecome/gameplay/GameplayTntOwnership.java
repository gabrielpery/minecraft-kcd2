package dev.minecome.gameplay;

import java.util.UUID;
import java.util.Collection;
import java.util.List;
import java.util.function.Predicate;

/** Durable entity ownership; these tags never replace vanilla explosion attribution. */
public final class GameplayTntOwnership {
    public static final int MAX_ACTIVE=16;
    private static final String PREFIX="minecome.tnt.v1:";
    public record Owner(UUID world,UUID player){}
    private GameplayTntOwnership(){}
    public static String tag(UUID world,UUID player){return PREFIX+world+":"+player;}
    public static boolean managed(String tag){return tag!=null&&tag.startsWith("minecome.tnt.");}
    public static Owner parse(String tag){
        if(tag==null||!tag.startsWith(PREFIX))return null;
        String value=tag.substring(PREFIX.length());if(value.length()!=73||value.charAt(36)!=':')return null;
        try{var world=UUID.fromString(value.substring(0,36));var player=UUID.fromString(value.substring(37));
            return tag.equals(tag(world,player))?new Owner(world,player):null;
        }catch(IllegalArgumentException invalid){return null;}
    }
    public static boolean matches(String tag,UUID world,UUID player){var owner=parse(tag);return owner!=null&&owner.world().equals(world)&&owner.player().equals(player);}
    public static Owner owner(Collection<String> tags){
        Owner found=null;for(var tag:tags)if(managed(tag)){var owner=parse(tag);if(owner==null||found!=null&&!found.equals(owner))return null;found=owner;}return found;
    }
    /** Filter before vanilla removes blocks. Unadmitted blasts may not turn an
     * owned TNT block into an untracked entity; their other effects stay vanilla. */
    public static <T> void filterAffected(List<T> affected,boolean admitted,int chainSlots,Predicate<T> owned,Predicate<T> tnt){
        var iterator=affected.iterator();while(iterator.hasNext()){
            var cell=iterator.next();boolean ours=owned.test(cell);
            if(!admitted){if(ours&&tnt.test(cell))iterator.remove();continue;}
            if(!ours){iterator.remove();continue;}
            if(tnt.test(cell)){if(chainSlots<=0){iterator.remove();continue;}chainSlots--;}
        }
    }
}
