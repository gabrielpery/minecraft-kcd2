package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.hud.mixin.HudHandledScreenAccessor;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ingame.*;
import java.util.*;

/** Real vanilla Screen entry points on the exact owned client thread/world. */
final class HudVanillaUiAdapter {
    private final Object world,player,server;
    private final boolean mouseAllowed;
    private final Set<Integer> buttons=new HashSet<>(),keys=new HashSet<>();
    private double x=0.5,y=0.5;
    private boolean pointerKnown;
    HudVanillaUiAdapter(MinecraftClient client,boolean mouseAllowed){world=client.world;player=client.player;server=client.getServer();this.mouseAllowed=mouseAllowed;}
    static boolean inventory(Screen screen){return screen instanceof InventoryScreen || screen instanceof CreativeInventoryScreen;}
    private void requireOwned(MinecraftClient client){if(!client.isOnThread() || client.world!=world || client.player!=player || client.getServer()!=server || !client.isIntegratedServerRunning())throw new IllegalStateException("Vanilla UI owner/thread changed");}
    void apply(MinecraftClient client,HudInputProtocol.Event event){
        requireOwned(client);Screen screen=client.currentScreen;
        if(screen!=null && !inventory(screen))throw new IllegalStateException("Unowned screen during HUD input");
        if(event.kind()<=2){
            int glfw=event.code()==0x1b?256:event.code();
            if(event.kind()==2){keys.remove(glfw);if(screen!=null)screen.keyReleased(glfw,0,0);return;}
            keys.add(glfw);
            if(event.code()==0x45){if(screen==null)client.setScreen(new InventoryScreen(client.player));else screen.close();}
            else if(event.code()==0x1b){if(screen!=null)screen.close();}
            else if(screen!=null)screen.keyPressed(glfw,0,0);
            else client.player.getInventory().selectedSlot=event.code()-0x31;
            return;
        }
        if(!mouseAllowed)throw new IllegalStateException("Live mouse forwarding is disabled");
        if(screen==null)throw new IllegalStateException("Pointer event without actual vanilla inventory");
        double oldX=logicalX(screen),oldY=logicalY(screen);x=event.x();y=event.y();pointerKnown=true;
        double nextX=logicalX(screen),nextY=logicalY(screen);screen.mouseMoved(nextX,nextY);
        switch(event.kind()){
            case 3 -> {for(int button:buttons)screen.mouseDragged(nextX,nextY,button,nextX-oldX,nextY-oldY);}
            case 4 -> {buttons.add(event.code());screen.mouseClicked(nextX,nextY,event.code());}
            case 5 -> {buttons.remove(event.code());screen.mouseReleased(nextX,nextY,event.code());}
            case 6 -> screen.mouseScrolled(nextX,nextY,0,event.value());
            default -> throw new IllegalArgumentException("Unexpected UI input kind");
        }
    }
    void releaseAndClose(MinecraftClient client){
        if(!client.isOnThread() || client.world!=world || client.player!=player || client.getServer()!=server){buttons.clear();keys.clear();return;}
        Screen screen=client.currentScreen;
        if(inventory(screen)){
            for(int button:buttons)screen.mouseReleased(logicalX(screen),logicalY(screen),button);
            for(int key:keys)screen.keyReleased(key,0,0);
            screen.close();
        }
        buttons.clear();keys.clear();
    }
    private double logicalX(Screen screen){return Math.min(screen.width-0.001,x*screen.width);}
    private double logicalY(Screen screen){return Math.min(screen.height-0.001,y*screen.height);}
    Double windowX(MinecraftClient client){return pointerKnown && inventory(client.currentScreen)?Math.min(client.getWindow().getWidth()-0.001,x*client.getWindow().getWidth()):null;}
    Double windowY(MinecraftClient client){return pointerKnown && inventory(client.currentScreen)?Math.min(client.getWindow().getHeight()-0.001,y*client.getWindow().getHeight()):null;}
    JsonArray fixtureTargets(MinecraftClient client){
        requireOwned(client);if(!(client.currentScreen instanceof HandledScreen<?> screen) || !inventory(screen))throw new IllegalStateException("No actual inventory handler for fixture targets");
        var origin=(HudHandledScreenAccessor)screen;var result=new JsonArray();
        for(int index=0;index<2;index++){
            final int wanted=index;var slot=screen.getScreenHandler().slots.stream().filter(value->value.inventory==client.player.getInventory() && value.getIndex()==wanted).findFirst().orElseThrow(()->new IllegalStateException("Actual player hotbar slot unavailable"));
            var value=new JsonObject();value.addProperty("slot",index);value.addProperty("x",(origin.minecome$originX()+slot.x+8.0)/screen.width);value.addProperty("y",(origin.minecome$originY()+slot.y+8.0)/screen.height);
            result.add(value);
        }
        return result;
    }
}
