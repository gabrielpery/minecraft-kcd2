package dev.minecome.hud;

import java.util.*;

/** Pointer edges owned by one UI adapter; no operating-system input state. */
final class HudPointerState {
    private final Set<Integer> held=new LinkedHashSet<>(),releasedByClose=new HashSet<>();
    private int activeButton=-1;

    void press(int button){
        requireButton(button);
        if(held.contains(button) || releasedByClose.contains(button))throw new IllegalStateException("Pointer button already held");
        held.add(button);activeButton=button;
    }
    boolean release(int button){
        requireButton(button);
        // A real late up must consume its edge without releasing a newly opened Screen.
        if(releasedByClose.remove(button))return false;
        if(!held.remove(button))throw new IllegalStateException("Pointer up without down");
        // Pinned1.21.1 Mouse.onMouseButton clears activeButton on any button up.
        activeButton=-1;return true;
    }
    boolean awaitingRelease(int button){return releasedByClose.contains(button);}
    List<Integer> releaseScreen(){
        var result=List.copyOf(held);releasedByClose.addAll(held);held.clear();activeButton=-1;return result;
    }
    int activeButton(){return activeButton;}
    int heldCount(){return held.size();}
    int pendingReleaseCount(){return releasedByClose.size();}
    void clear(){held.clear();releasedByClose.clear();activeButton=-1;}
    static double wheel(int notches,boolean discrete,double sensitivity){
        if(notches==0 || notches< -16 || notches>16 || !Double.isFinite(sensitivity) || sensitivity<0)throw new IllegalArgumentException("Invalid UI wheel");
        // Pinned1.21.1 Mouse.onMouseScroll applies signum before sensitivity.
        return (discrete?Math.signum(notches):notches)*sensitivity;
    }
    private static void requireButton(int button){if(button<0 || button>1)throw new IllegalArgumentException("Unsupported pointer button");}
}
