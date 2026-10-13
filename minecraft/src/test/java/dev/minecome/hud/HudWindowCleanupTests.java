package dev.minecome.hud;

import java.util.ArrayList;
import java.util.List;

/** Executes terminal operations against an observable window stand-in; no GLFW. */
public final class HudWindowCleanupTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static final class Window implements HudWindowCleanup.Window {
        long handle=42;boolean visible=false,focus=true,windowed=true,hideWorks=true,showThrows,focusDisableWorks=true;
        final List<String> operations=new ArrayList<>();
        public long handle(){return handle;}
        public boolean windowed(){return windowed;}
        public boolean visible(){return visible;}
        public boolean focusOnShow(){return focus;}
        public void focusOnShow(boolean value){operations.add("focus:"+value);if(value || focusDisableWorks)focus=value;}
        public void show(){operations.add("show");if(focus)throw new AssertionError("show must never request focus");if(showThrows)throw new IllegalStateException("show failed");visible=true;}
        public void hide(){operations.add("hide");if(hideWorks)visible=false;}
    }
    public static void main(String[] args){
        for(int bits=0;bits<32;bits++){
            boolean actual=HudWindowCleanup.retainHidden((bits&1)!=0,(bits&2)!=0,(bits&4)!=0,(bits&8)!=0,(bits&16)!=0);
            check(actual==(bits==29),"only verified explicit non-fixture live mouse may retain hidden");
        }
        var window=new Window();
        var proof=HudWindowCleanup.finish(window,42,true,true,true);
        check(proof.get("cleanup_succeeded").getAsBoolean() && proof.get("hidden_for_exit").getAsBoolean(),"owned live hidden cleanup succeeds");
        check(!proof.get("restored").getAsBoolean(),"original visible state is truthfully not restored");
        check(!window.visible && window.operations.equals(List.of("focus:true")),"hidden live window never shows");
        check(proof.get("expected_window_handle").getAsString().equals(proof.get("actual_window_handle").getAsString()),"receipt identifies the same window");
        window.operations.clear();HudWindowCleanup.finish(window,42,true,true,true);
        check(window.operations.equals(List.of("focus:true")),"repeated CLIENT_STOPPING cleanup also never shows");

        window=new Window();window.visible=true;
        proof=HudWindowCleanup.finish(window,42,true,true,true);
        check(!window.visible && window.operations.equals(List.of("hide","focus:true")),"visible owned window is hidden during terminal cleanup");
        check(proof.get("hidden_for_exit").getAsBoolean(),"successful re-hide recorded");
        window=new Window();window.visible=true;window.hideWorks=false;
        proof=HudWindowCleanup.finish(window,42,true,true,true);
        check(!proof.get("cleanup_succeeded").getAsBoolean() && !proof.get("hidden_for_exit").getAsBoolean(),"silent GLFW hide failure cannot pass");

        window=new Window();
        proof=HudWindowCleanup.finish(window,42,true,true,false);
        check(window.visible && window.focus,"fixture restores both original values");
        check(window.operations.equals(List.of("focus:false","show","focus:true")),"fixture shows only while focus-on-show disabled");
        check(proof.get("restored").getAsBoolean() && !proof.get("hidden_for_exit").getAsBoolean(),"ordinary restoration contract retained");
        window=new Window();window.focus=false;
        proof=HudWindowCleanup.finish(window,42,false,false,false);
        check(!window.visible && !window.focus && window.operations.equals(List.of("focus:false")),"originally hidden fixture remains hidden");
        check(proof.get("restored").getAsBoolean(),"already-hidden original state restored");
        window=new Window();proof=HudWindowCleanup.finish(window,42,false,true,true);
        check(proof.get("restored").getAsBoolean() && proof.get("hidden_for_exit").getAsBoolean(),"original hidden state may truthfully be both restored and retained");

        for(boolean keepHidden:new boolean[]{false,true}){
            window=new Window();window.handle=99;proof=HudWindowCleanup.finish(window,42,true,true,keepHidden);
            check(window.operations.isEmpty() && !proof.get("window_identity_verified").getAsBoolean(),"foreign window receives no mutation");
            check(!proof.get("cleanup_succeeded").getAsBoolean(),"identity mismatch rejected");
            window=new Window();proof=HudWindowCleanup.finish(window,0,true,true,keepHidden);
            check(window.operations.isEmpty() && !proof.get("cleanup_succeeded").getAsBoolean(),"missing owned handle rejected");
            window=new Window();window.windowed=false;proof=HudWindowCleanup.finish(window,42,true,true,keepHidden);
            check(window.operations.isEmpty() && !proof.get("cleanup_succeeded").getAsBoolean(),"fullscreen window receives no visibility operation");
        }
        window=new Window();window.showThrows=true;proof=HudWindowCleanup.finish(window,42,true,true,false);
        check(window.focus && !proof.get("cleanup_succeeded").getAsBoolean(),"show exception restores focus attribute and records failure");
        check(proof.get("failure").getAsString().equals("show failed"),"actual failure retained");
        window=new Window();window.focusDisableWorks=false;proof=HudWindowCleanup.finish(window,42,true,true,false);
        check(!window.operations.contains("show") && !proof.get("cleanup_succeeded").getAsBoolean(),"failed focus-disable never invokes show");
        System.out.println("HUD_WINDOW_CLEANUP_TEST_PASS checks="+checks);
    }
}
