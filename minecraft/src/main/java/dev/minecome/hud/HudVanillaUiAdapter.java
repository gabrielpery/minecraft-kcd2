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
    private final Set<Integer> keys=new HashSet<>();
    private final HudPointerState pointer=new HudPointerState();
    private Screen pointerScreen;
    private long screenGeneration,cleanupReleases,lateReleasesConsumed,mouseDragCalls,wheelCalls;
    private double x=0.5,y=0.5;
    private boolean pointerKnown;
    HudVanillaUiAdapter(MinecraftClient client,boolean mouseAllowed){world=client.world;player=client.player;server=client.getServer();this.mouseAllowed=mouseAllowed;}
    static boolean inventory(Screen screen){return screen instanceof InventoryScreen || screen instanceof CreativeInventoryScreen;}
    private void requireOwned(MinecraftClient client){if(!client.isOnThread() || client.world!=world || client.player!=player || client.getServer()!=server || !client.isIntegratedServerRunning())throw new IllegalStateException("Vanilla UI owner/thread changed");}
    void apply(MinecraftClient client,HudInputProtocol.Event event){
        synchronizeScreen(client);Screen screen=client.currentScreen;
        if(screen!=null && !inventory(screen))throw new IllegalStateException("Unowned screen during HUD input");
        if(event.kind()<=2){
            int glfw=event.code()==0x1b?256:event.code();
            if(event.kind()==2){keys.remove(glfw);if(screen!=null)screen.keyReleased(glfw,0,0);return;}
            keys.add(glfw);
            if(event.code()==0x45){if(screen==null)client.setScreen(new InventoryScreen(client.player));else closeInventory(screen);}
            else if(event.code()==0x1b){if(screen!=null)closeInventory(screen);}
            else if(screen!=null)screen.keyPressed(glfw,0,0);
            else client.player.getInventory().selectedSlot=event.code()-0x31;
            return;
        }
        if(!mouseAllowed)throw new IllegalStateException("Live mouse forwarding is disabled");
        if(event.kind()==5 && pointer.awaitingRelease(event.code())){pointer.release(event.code());lateReleasesConsumed++;return;}
        if(screen==null)throw new IllegalStateException("Pointer event without actual vanilla inventory");
        double oldX=logicalX(screen),oldY=logicalY(screen);x=event.x();y=event.y();pointerKnown=true;
        double nextX=logicalX(screen),nextY=logicalY(screen);screen.mouseMoved(nextX,nextY);
        switch(event.kind()){
            case 3 -> {int button=pointer.activeButton();if(button!=-1){screen.mouseDragged(nextX,nextY,button,nextX-oldX,nextY-oldY);mouseDragCalls++;}}
            case 4 -> {pointer.press(event.code());screen.mouseClicked(nextX,nextY,event.code());}
            case 5 -> {pointer.release(event.code());screen.mouseReleased(nextX,nextY,event.code());}
            case 6 -> {screen.mouseScrolled(nextX,nextY,0,HudPointerState.wheel(event.value(),client.options.getDiscreteMouseScroll().getValue(),client.options.getMouseWheelSensitivity().getValue()));wheelCalls++;}
            default -> throw new IllegalArgumentException("Unexpected UI input kind");
        }
    }
    void synchronizeScreen(MinecraftClient client){
        requireOwned(client);Screen current=client.currentScreen;
        if(current==pointerScreen)return;
        releasePointerScreen();pointerKnown=false;
        pointerScreen=inventory(current)?current:null;
        if(pointerScreen!=null)screenGeneration++;
    }
    private void releasePointerScreen(){
        var released=pointer.releaseScreen();Screen screen=pointerScreen;pointerScreen=null;
        if(screen!=null)for(int button:released){screen.mouseReleased(logicalX(screen),logicalY(screen),button);cleanupReleases++;}
    }
    private void closeInventory(Screen screen){releasePointerScreen();pointerKnown=false;screen.close();}
    void releaseAndClose(MinecraftClient client){
        if(!client.isOnThread() || client.world!=world || client.player!=player || client.getServer()!=server){pointer.clear();pointerScreen=null;pointerKnown=false;keys.clear();return;}
        Screen screen=client.currentScreen;
        try{
            releasePointerScreen();
            if(inventory(screen)){
                for(int key:keys)screen.keyReleased(key,0,0);
                screen.close();
            }
        }finally{pointer.clear();pointerScreen=null;pointerKnown=false;keys.clear();}
    }
    private double logicalX(Screen screen){return Math.min(screen.width-0.001,x*screen.width);}
    private double logicalY(Screen screen){return Math.min(screen.height-0.001,y*screen.height);}
    JsonObject pointerDiagnostics(){
        var proof=new JsonObject();proof.addProperty("held_buttons",pointer.heldCount());proof.addProperty("pending_releases",pointer.pendingReleaseCount());proof.addProperty("active_button",pointer.activeButton());
        proof.addProperty("cleanup_releases",cleanupReleases);proof.addProperty("late_releases_consumed",lateReleasesConsumed);proof.addProperty("screen_generation",screenGeneration);proof.addProperty("mouse_drag_calls",mouseDragCalls);proof.addProperty("wheel_calls",wheelCalls);return proof;
    }
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
