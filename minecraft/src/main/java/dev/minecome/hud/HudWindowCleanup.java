package dev.minecome.hud;

import com.google.gson.JsonObject;

/** Terminal operations on the one GLFW window hidden by the owned lab. */
final class HudWindowCleanup {
    interface Window {
        long handle();
        boolean windowed();
        boolean visible();
        boolean focusOnShow();
        void focusOnShow(boolean value);
        void show();
        void hide();
    }
    private HudWindowCleanup(){}
    static boolean retainHidden(boolean input,boolean fixture,boolean liveMouse,boolean offscreen,boolean hideVerified){
        return input && !fixture && liveMouse && offscreen && hideVerified;
    }
    static JsonObject finish(Window window,long expectedHandle,boolean originalVisible,boolean originalFocusOnShow,boolean keepHidden){
        var proof=new JsonObject();proof.addProperty("attempted",true);proof.addProperty("original_visible",originalVisible);
        proof.addProperty("original_focus_on_show",originalFocusOnShow);proof.addProperty("focus_requested",false);
        proof.addProperty("policy",keepHidden?"hidden_until_process_exit":"restore_original_visibility");
        proof.addProperty("expected_window_handle",Long.toUnsignedString(expectedHandle));
        boolean identity=false,restored=false,hidden=false,succeeded=false,showWithFocusDisabled=false;String error=null;
        try{
            long actualHandle=window.handle();proof.addProperty("actual_window_handle",Long.toUnsignedString(actualHandle));
            if(expectedHandle==0 || actualHandle!=expectedHandle)throw new IllegalStateException("Owned GLFW window changed before cleanup");
            identity=true;
            if(!window.windowed())throw new IllegalStateException("Owned window left windowed mode before cleanup");
            try{
                boolean wantedVisible=keepHidden?false:originalVisible;
                if(window.visible()!=wantedVisible){
                    if(wantedVisible){
                        window.focusOnShow(false);
                        if(window.focusOnShow())throw new IllegalStateException("GLFW focus-on-show disable failed");
                        showWithFocusDisabled=true;window.show();
                    }else window.hide();
                }
            }finally{window.focusOnShow(originalFocusOnShow);}
            boolean actualVisible=window.visible(),actualFocusOnShow=window.focusOnShow();
            proof.addProperty("actual_visible",actualVisible);proof.addProperty("actual_focus_on_show",actualFocusOnShow);
            restored=actualVisible==originalVisible && actualFocusOnShow==originalFocusOnShow;
            hidden=keepHidden && !actualVisible && actualFocusOnShow==originalFocusOnShow;
            succeeded=keepHidden?hidden:restored;
        }catch(RuntimeException e){error=e.getMessage();}
        proof.addProperty("window_identity_verified",identity);proof.addProperty("show_with_focus_disabled",showWithFocusDisabled);
        proof.addProperty("restored",restored);proof.addProperty("hidden_for_exit",hidden);proof.addProperty("cleanup_succeeded",succeeded);
        if(error!=null)proof.addProperty("failure",error);
        return proof;
    }
}
