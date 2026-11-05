package dev.minecome.hud;

import java.util.*;

/** Client-thread order/edge gate. Controls are never inferred from repeated snapshots. */
public final class HudInputGate {
    private long sequence;
    private final boolean movement,blocks;
    private final Set<Integer> keys=new HashSet<>(),buttons=new HashSet<>(),worldButtons=new HashSet<>();
    public HudInputGate(){this(false);}
    public HudInputGate(boolean movement){this(movement,false);}
    public HudInputGate(boolean movement,boolean blocks){this.movement=movement;this.blocks=blocks;}
    public void apply(HudInputProtocol.Event event,long now) {
        HudInputProtocol.validateEvent(event,now,true,movement,blocks);
        if(sequence==Long.MAX_VALUE || event.sequence()!=sequence+1)throw new IllegalArgumentException("Client input sequence gap/replay");
        Set<Integer> down=event.kind()<=2?keys:event.kind()>=7?worldButtons:buttons;
        if(event.kind()==1 || event.kind()==4 || event.kind()==7){if(!down.add(event.code()))throw new IllegalArgumentException("Duplicate input down");}
        if(event.kind()==2 || event.kind()==5 || event.kind()==8){if(!down.remove(event.code()))throw new IllegalArgumentException("Unmatched input up");}
        sequence=event.sequence();
    }
    public void releaseAll(){keys.clear();buttons.clear();worldButtons.clear();}
    public long sequence(){return sequence;}
    public int heldKeyCount(){return keys.size();}
    public int heldButtonCount(){return buttons.size()+worldButtons.size();}
}
