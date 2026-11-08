package dev.minecome.hud;

import dev.minecome.gameplay.GameplayAimReader.RenderSample;
import java.util.function.Consumer;

/** Client-thread admission and one immutable native observation per rendered frame. */
final class GameplayNativeViewAdmission {
    private RenderSample current,frame;
    private boolean frameOpen;

    RenderSample admit(RenderSample candidate,long utc,long nanos,Consumer<RenderSample> apply) {
        if(frameOpen)throw new IllegalStateException("Native view changed inside a rendered frame");
        var next=fresh(candidate,utc,nanos);
        // Apply perspective and targeting together before publishing the sample.
        // A failed client-side application must not publish a partially applied view.
        apply.accept(next);current=next;return next;
    }
    void beginFrame(RenderSample candidate,long utc,long nanos,Consumer<RenderSample> apply) {
        frame=admit(candidate,utc,nanos,apply);frameOpen=true;
    }
    RenderSample current(){return current;}
    RenderSample frame(long utc,long nanos){return frameOpen?fresh(frame,utc,nanos):null;}
    void endFrame(){frame=null;frameOpen=false;}
    private static RenderSample fresh(RenderSample sample,long utc,long nanos){
        return sample!=null&&sample.aim().fresh(utc,nanos)?sample:null;
    }
}
