package dev.minecome.hud;

import java.util.*;

/** Client-thread order/edge gate. Controls are never inferred from repeated snapshots. */
public final class HudInputGate {
    private long sequence;
    private final boolean movement;
    private final Set<Integer> keys=new HashSet<>(),buttons=new HashSet<>();
    public HudInputGate(){this(false);}
    public HudInputGate(boolean movement){this.movement=movement;}
    public void apply(HudInputProtocol.Event event,long now) {
        HudInputProtocol.validateEvent(event,now,true,movement);
        if(sequence==Long.MAX_VALUE || event.sequence()!=sequence+1)throw new IllegalArgumentException("Client input sequence gap/replay");
        Set<Integer> down=event.kind()<=2?keys:buttons;
        if(event.kind()==1 || event.kind()==4){if(!down.add(event.code()))throw new IllegalArgumentException("Duplicate input down");}
        if(event.kind()==2 || event.kind()==5){if(!down.remove(event.code()))throw new IllegalArgumentException("Unmatched input up");}
        sequence=event.sequence();
    }
    public void releaseAll(){keys.clear();buttons.clear();}
    public long sequence(){return sequence;}
    public int heldKeyCount(){return keys.size();}
    public int heldButtonCount(){return buttons.size();}
}
