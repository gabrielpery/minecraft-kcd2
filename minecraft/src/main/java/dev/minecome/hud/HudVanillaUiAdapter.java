package dev.minecome.hud;

import com.google.gson.*;
import dev.minecome.hud.mixin.HudHandledScreenAccessor;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ChatScreen;
import net.minecraft.client.gui.screen.ingame.*;
import java.util.*;

/** Real vanilla Screen entry points on the exact owned client thread/world. */
final class HudVanillaUiAdapter {
    private final Object world,player,server;
    private final boolean mouseAllowed,commandsAllowed;
    private final Set<Integer> keys=new HashSet<>(),editKeys=new HashSet<>();
    private OwnedChatScreen ownedChat;
    private final HudPointerState pointer=new HudPointerState();
    private Screen pointerScreen;
    private long screenGeneration,cleanupReleases,lateReleasesConsumed,mouseDragCalls,wheelCalls,mouseClickCalls,mouseReleaseCalls;
    private long chatOpenCalls,chatTextCalls,chatEditDownCalls,chatEditUpCalls,chatSubmitCalls,chatCancelCalls,chatTailEvents;
    private double x=0.5,y=0.5;
    private boolean pointerKnown;
    HudVanillaUiAdapter(MinecraftClient client,boolean mouseAllowed){this(client,mouseAllowed,false);}
    HudVanillaUiAdapter(MinecraftClient client,boolean mouseAllowed,boolean commandsAllowed){world=client.world;player=client.player;server=client.getServer();this.mouseAllowed=mouseAllowed;this.commandsAllowed=commandsAllowed;}
    static boolean inventory(Screen screen){return screen instanceof InventoryScreen || screen instanceof CreativeInventoryScreen || screen instanceof CraftingScreen || screen instanceof FurnaceScreen;}
    static boolean chat(Screen screen){return screen instanceof ChatScreen;}
    static int screenKind(Screen screen){return screen==null?0:chat(screen)?2:inventory(screen)?1:-1;}
    // Inspected Yarn 1.21.1 ChatScreen: constructor seeds chatField; vanilla
    // keyPressed submits through sendMessage/sendChatCommand and owns history.
    // This subclass only exposes field text to the actual-Minecraft fixture.
    private static final class OwnedChatScreen extends ChatScreen {
        OwnedChatScreen(String initial){super(initial);}
        String text(){return chatField.getText();}
    }
    String chatText(MinecraftClient client){requireOwned(client);if(client.currentScreen!=ownedChat||ownedChat==null)throw new IllegalStateException("No actual owned vanilla chat");return ownedChat.text();}
    private void requireOwned(MinecraftClient client){if(!client.isOnThread() || client.world!=world || client.player!=player || client.getServer()!=server || !client.isIntegratedServerRunning())throw new IllegalStateException("Vanilla UI owner/thread changed");}
    void apply(MinecraftClient client,HudInputProtocol.Event event){
        synchronizeScreen(client);Screen screen=client.currentScreen;
        if(screen!=null && !inventory(screen) && screen!=ownedChat)throw new IllegalStateException("Unowned screen during HUD input");
        if(event.kind()>=9){
            if(!commandsAllowed)throw new IllegalStateException("Live chat forwarding is disabled");
            // A submit/cancel closes ChatScreen synchronously. Remaining input
            // captured before the next screen acknowledgement must not leak.
            if(screen==null||screen!=ownedChat){chatTailEvents++;return;}
            if(event.kind()==9){for(char character:GameplayChatInput.characters(event.code()))screen.charTyped(character,0);chatTextCalls++;}
            else if(event.kind()==10){int glfw=GameplayChatInput.glfw(event.code());editKeys.add(glfw);screen.keyPressed(glfw,0,0);chatEditDownCalls++;if(event.code()==13)chatSubmitCalls++;if(event.code()==27)chatCancelCalls++;}
            else if(event.kind()==11){int glfw=GameplayChatInput.glfw(event.code());editKeys.remove(glfw);screen.keyReleased(glfw,0,0);chatEditUpCalls++;}
            else throw new IllegalArgumentException("Unexpected chat input kind");
            return;
        }
        if(event.kind()<=2){
            int glfw=event.code()==0x1b?256:event.code()==0x74?294:event.code();
            if(screen==ownedChat && ownedChat!=null){if(event.kind()==2)keys.remove(glfw);return;}
            if(event.kind()==2){keys.remove(glfw);if(screen!=null)screen.keyReleased(glfw,0,0);return;}
            keys.add(glfw);
            if(commandsAllowed&&GameplayChatInput.opens(event.code())){if(screen==null){ownedChat=new OwnedChatScreen(event.code()==0xbf?"/":"");client.setScreen(ownedChat);chatOpenCalls++;}}
            else if(event.code()==0x45){if(screen==null)client.setScreen(new InventoryScreen(client.player));else closeInventory(screen);}
            else if(event.code()==0x1b){if(screen!=null)closeInventory(screen);}
            // F5 requests host camera authority; it must not change the local
            // perspective ahead of the matching native camera acknowledgement.
            // Consume it in other profiles/screens instead of corrupting slot 67.
            else if(event.code()==0x74){if(commandsAllowed&&screen==null)GameplaySession.requestPerspective();}
            else if(screen!=null)screen.keyPressed(glfw,0,0);
            else if(event.code()>=0x31&&event.code()<=0x39)client.player.getInventory().selectedSlot=event.code()-0x31;
            else throw new IllegalArgumentException("Unexpected world UI key");
            return;
        }
        if(!mouseAllowed)throw new IllegalStateException("Live mouse forwarding is disabled");
        if(event.kind()==5 && pointer.awaitingRelease(event.code())){pointer.release(event.code());lateReleasesConsumed++;return;}
        if(screen==ownedChat && ownedChat!=null)return;
        if(screen==null)throw new IllegalStateException("Pointer event without actual vanilla inventory");
        double oldX=logicalX(screen),oldY=logicalY(screen);x=event.x();y=event.y();pointerKnown=true;
        double nextX=logicalX(screen),nextY=logicalY(screen);screen.mouseMoved(nextX,nextY);
        switch(event.kind()){
            case 3 -> {int button=pointer.activeButton();if(button!=-1){screen.mouseDragged(nextX,nextY,button,nextX-oldX,nextY-oldY);mouseDragCalls++;}}
            case 4 -> {pointer.press(event.code());screen.mouseClicked(nextX,nextY,event.code());mouseClickCalls++;}
            case 5 -> {pointer.release(event.code());screen.mouseReleased(nextX,nextY,event.code());mouseReleaseCalls++;}
            case 6 -> {screen.mouseScrolled(nextX,nextY,0,HudPointerState.wheel(event.value(),client.options.getDiscreteMouseScroll().getValue(),client.options.getMouseWheelSensitivity().getValue()));wheelCalls++;}
            default -> throw new IllegalArgumentException("Unexpected UI input kind");
        }
    }
    void synchronizeScreen(MinecraftClient client){
        requireOwned(client);Screen current=client.currentScreen;
        // Pinned Yarn1.21.1 CraftingScreen wraps the server-opened handler.
        // Keep cursor routing and native movement suppression on the existing
        // inventory state, but never admit a detached/stale crafting screen.
        if(current instanceof CraftingScreen crafting && (crafting.getScreenHandler()!=client.player.currentScreenHandler || crafting.getScreenHandler().syncId<=0))
            throw new IllegalStateException("Crafting screen handler ownership changed");
        // FurnaceScreen inherits ordinary HandledScreen slot/close behavior;
        // recipes, fuel and stored contents remain on its actual server handler.
        // Inspected runtime/evidence/furnace-source-20261108/FurnaceScreen.txt.
        if(current instanceof FurnaceScreen furnace && (furnace.getScreenHandler()!=client.player.currentScreenHandler || furnace.getScreenHandler().syncId<=0))
            throw new IllegalStateException("Furnace screen handler ownership changed");
        if(ownedChat!=null&&current!=ownedChat){releaseChatKeys();ownedChat=null;}
        if(commandsAllowed&&current!=null&&!inventory(current)&&current!=ownedChat)throw new IllegalStateException("Unowned screen during gameplay chat");
        if(current==pointerScreen)return;
        releasePointerScreen();pointerKnown=false;
        pointerScreen=inventory(current)?current:null;
        if(pointerScreen!=null)screenGeneration++;
    }
    private void releasePointerScreen(){
        var released=pointer.releaseScreen();Screen screen=pointerScreen;pointerScreen=null;
        if(screen!=null)for(int button:released){screen.mouseReleased(logicalX(screen),logicalY(screen),button);cleanupReleases++;}
    }
    // HandledScreen.close sends ClientPlayerEntity.closeHandledScreen before
    // closing the GUI, returning crafting inputs through the real server.
    // Inspected runtime/evidence/crafting-source-20261108/HandledScreen.txt.
    private void closeInventory(Screen screen){releasePointerScreen();pointerKnown=false;screen.close();}
    private void releaseChatKeys(){if(ownedChat!=null)for(int key:editKeys)ownedChat.keyReleased(key,0,0);editKeys.clear();}
    void releaseAndClose(MinecraftClient client){
        if(!client.isOnThread() || client.world!=world || client.player!=player || client.getServer()!=server){pointer.clear();pointerScreen=null;pointerKnown=false;keys.clear();editKeys.clear();ownedChat=null;return;}
        Screen screen=client.currentScreen;
        try{
            releasePointerScreen();
            releaseChatKeys();
            if(inventory(screen)){
                for(int key:keys)screen.keyReleased(key,0,0);
                screen.close();
            }
            else if(screen!=null&&screen==ownedChat)screen.close();
        }finally{pointer.clear();pointerScreen=null;pointerKnown=false;keys.clear();editKeys.clear();ownedChat=null;}
    }
    private double logicalX(Screen screen){return Math.min(screen.width-0.001,x*screen.width);}
    private double logicalY(Screen screen){return Math.min(screen.height-0.001,y*screen.height);}
    JsonObject pointerDiagnostics(){
        var proof=new JsonObject();proof.addProperty("held_buttons",pointer.heldCount());proof.addProperty("pending_releases",pointer.pendingReleaseCount());proof.addProperty("active_button",pointer.activeButton());
        proof.addProperty("cleanup_releases",cleanupReleases);proof.addProperty("late_releases_consumed",lateReleasesConsumed);proof.addProperty("screen_generation",screenGeneration);proof.addProperty("mouse_drag_calls",mouseDragCalls);proof.addProperty("wheel_calls",wheelCalls);
        proof.addProperty("mouse_click_calls",mouseClickCalls);proof.addProperty("mouse_release_calls",mouseReleaseCalls);return proof;
    }
    JsonObject chatDiagnostics(){
        var proof=new JsonObject();proof.addProperty("enabled",commandsAllowed);proof.addProperty("open_calls",chatOpenCalls);proof.addProperty("text_scalar_calls",chatTextCalls);
        proof.addProperty("edit_down_calls",chatEditDownCalls);proof.addProperty("edit_up_calls",chatEditUpCalls);proof.addProperty("submit_key_calls",chatSubmitCalls);proof.addProperty("cancel_key_calls",chatCancelCalls);
        proof.addProperty("closed_screen_tail_events",chatTailEvents);proof.addProperty("held_edit_keys",editKeys.size());return proof;
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
