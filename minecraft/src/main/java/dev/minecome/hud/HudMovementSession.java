package dev.minecome.hud;

import java.util.Properties;

/** Fixed, opt-in session policies; neither input nor inventory can renew them. */
public enum HudMovementSession {
    SHORT("short",5_000_000_000L,64*1024),
    EXTENDED("extended",15_000_000_000L,256*1024);

    public static final long SETTLE_NS=1_000_000_000L,START_WINDOW_NS=12_000_000_000L;
    private final String id;
    private final long activeNs;
    private final int traceBytes;
    HudMovementSession(String id,long activeNs,int traceBytes){this.id=id;this.activeNs=activeNs;this.traceBytes=traceBytes;}
    public String id(){return id;}
    public boolean extended(){return this==EXTENDED;}
    public long activeNs(){return activeNs;}
    public long maximumMotionNs(){return activeNs+SETTLE_NS;}
    public int traceBytes(){return traceBytes;}
    public String traceSource(boolean fixture){
        return fixture?(extended()?"standalone_hud_physical_movement_extended_fixture":"standalone_hud_physical_movement_fixture"):
                (extended()?"live_kcd_hud_physical_movement_extended":"live_kcd_hud_physical_movement");
    }
    public boolean mayStart(long activatedAt,long now){
        if(!extended())return true;
        try{long elapsed=Math.subtractExact(now,activatedAt);return elapsed>=0 && elapsed<START_WINDOW_NS;}
        catch(ArithmeticException overflow){return false;}
    }
    public static HudMovementSession selected(Properties properties){
        String value=properties.getProperty("minecome.hudPhysicalMovementExtended","false");
        if(!value.equals("true") && !value.equals("false"))throw new IllegalArgumentException("Extended physical movement must be explicit true or false");
        return value.equals("true")?EXTENDED:SHORT;
    }
}
