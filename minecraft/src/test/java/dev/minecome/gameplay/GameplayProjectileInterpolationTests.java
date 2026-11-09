package dev.minecome.gameplay;

import java.util.List;
import static dev.minecome.gameplay.GameplayProjectileInterpolation.*;

/** Real timeline logic with a deterministic clock; no entities or renderer required. */
final class GameplayProjectileInterpolationTests {
    private static int checks;
    private static long ms(double value){return (long)(value*1_000_000);}
    private static Sample sample(int segment,double time,double x,double y){return new Sample(segment,ms(time),new Point(x,y,0));}
    private static void check(boolean valid,String reason){checks++;if(!valid)throw new AssertionError(reason);}
    private static void at(Frame frame,double x,double y,String reason){check(Math.abs(frame.point().x()-x)<1e-9&&Math.abs(frame.point().y()-y)<1e-9&&frame.point().z()==0,reason);}
    static int run(){
        checks=0;var p=new GameplayProjectileInterpolation();var a=sample(0,0,0,0);var b=sample(1,50,2,0);
        at(p.frame(List.of(a),0),0,0,"Launch pose does not predict its first unchecked segment");
        at(p.frame(List.of(a,b),ms(50)),0,0,"A confirmation starts at the previous confirmed endpoint");
        at(p.frame(List.of(a,b),ms(60)),.4,0,"Repeated publication does not restart interpolation");
        var middle=p.frame(List.of(a,b),ms(75));at(middle,1,0,"Intermediate render frames lie inside the confirmed segment");check(middle.intermediate(),"Intermediate frame is measurable");
        at(p.frame(List.of(a,b),ms(100)),2,0,"Playback reaches the authoritative endpoint");
        var hold=p.frame(List.of(a,b),ms(250));at(hold,2,0,"Transport stalls hold the latest endpoint without extrapolation");check(!hold.intermediate(),"A held endpoint is not counted as interpolation");

        p.clear();p.frame(List.of(a),0);p.frame(List.of(a,b),ms(50));var c=sample(2,75,2,2);
        at(p.frame(List.of(a,b,c),ms(75)),1,0,"Next confirmation preserves unfinished previous segment");
        at(p.frame(List.of(a,b,c),ms(90)),1.6,0,"A corner cannot become an unchecked diagonal shortcut");
        at(p.frame(List.of(a,b,c),ms(100)),2,0,"Playback passes through the exact confirmed corner");
        at(p.frame(List.of(a,b,c),ms(112.5)),2,1,"Second segment begins only after reaching the corner");
        at(p.frame(List.of(a,b,c),ms(125)),2,2,"Queued playback finishes at the newest endpoint");

        p.clear();p.frame(List.of(a),0);var slow=sample(1,200,2,0);
        at(p.frame(List.of(a,slow),ms(200)),0,0,"A slow confirmation does not jump on arrival");
        at(p.frame(List.of(a,slow),ms(250)),1,0,"Slow confirmation still uses bounded interpolation");
        at(p.frame(List.of(a,slow),ms(300)),2,0,"Added presentation delay is bounded at 100ms");
        p.clear();p.frame(List.of(a),0);var tiny=sample(1,1,.1,0);p.frame(List.of(a,tiny),ms(1));
        at(p.frame(List.of(a,tiny),ms(9)),.05,0,"Catch-up ticks retain at least one 16ms presentation interval");

        for(var invalid:List.of(sample(1,301,2,0),sample(1,50,4.01,0),sample(2,50,2,0),sample(1,0,2,0))){
            p.clear();p.frame(List.of(a),0);var reset=p.frame(List.of(a,invalid),ms(350));
            check(reset.point().equals(invalid.point())&&!reset.intermediate(),"Stale/oversized/missing/nonmonotonic segments snap without inventing a path");
        }
        p.clear();p.frame(List.of(a),0);var four=sample(1,50,4,0);p.frame(List.of(a,four),ms(50));
        at(p.frame(List.of(a,four),ms(75)),2,0,"Maximum supported 4m segment remains interpolated");
        p.clear();p.frame(List.of(a),0);var d=sample(2,100,2,2);var e=sample(3,150,3,2);
        var overflow=p.frame(List.of(a,b,d,e),ms(150));check(overflow.point().equals(e.point())&&!overflow.intermediate(),"Buffered playback never exceeds the 100ms cap");
        p.clear();at(p.frame(List.of(d),ms(150)),2,2,"Embed/removal/respawn reset starts at the supplied authoritative point");
        at(p.frame(List.of(a),ms(160)),0,0,"Regressed source generation cannot inherit the old path");
        p.frame(List.of(a,b),ms(170));at(p.frame(List.of(a,b),ms(100)),2,0,"Backwards presentation clock resets without replay");
        var changed=sample(1,51,3,0);at(p.frame(List.of(a,changed),ms(120)),3,0,"Mutated source sample cannot retain an old interpolation");
        try{new Point(Double.NaN,0,0);throw new AssertionError("Nonfinite point accepted");}catch(IllegalArgumentException expected){checks++;}
        System.out.println("Projectile interpolation: "+checks+" checks; confirmed polyline only, <=100ms playback");return checks;
    }
}
