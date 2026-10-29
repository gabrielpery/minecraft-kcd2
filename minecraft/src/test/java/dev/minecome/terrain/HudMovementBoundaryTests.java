package dev.minecome.terrain;

import com.google.gson.*;
import java.nio.charset.StandardCharsets;

/** Pure geometry/decision regressions; these are not live movement proof. */
public final class HudMovementBoundaryTests {
    private static int checks;
    private static void check(boolean value,String why){checks++;if(!value)throw new AssertionError(why);}
    private static GroundPatch patch(double[] heights)throws Exception{
        var root=new JsonObject();root.addProperty("schema",1);root.addProperty("run","boundary-regression");
        root.addProperty("grid_size",5);root.addProperty("spacing",1);
        var center=new JsonObject();center.addProperty("x",0);center.addProperty("y",0);center.addProperty("z",10);root.add("center",center);
        var provenance=new JsonObject();provenance.addProperty("kind","standalone_fixture");root.add("provenance",provenance);
        var points=new JsonArray();
        for(int row=0;row<5;row++)for(int col=0;col<5;col++){
            var p=new JsonObject();p.addProperty("index",row*5+col+1);p.addProperty("x",col-2);p.addProperty("y",row-2);
            p.addProperty("z",10+heights[row*5+col]);p.addProperty("nx",0);p.addProperty("ny",0);p.addProperty("nz",1);points.add(p);
        }
        root.add("points",points);return GroundPatch.parse(root.toString().getBytes(StandardCharsets.UTF_8));
    }
    private static MovementTraceSink.Motion motion(double x,double y,double z,double vx,double vy,double vz,boolean ground){
        return new MovementTraceSink.Motion(x,y,z,vx,vy,vz,ground,ground);
    }
    private static HudMovementBoundary.Decision forward(HudMovementBoundary gate,MovementTraceSink.Motion m,double yaw){
        return gate.check(m,1,0,false,yaw,.13001,.42001,true);
    }
    public static int run()throws Exception{
        checks=0;
        var flat=patch(new double[25]);var origin=motion(0,64,0,0,-.0784,0,true);var gate=new HudMovementBoundary(flat,origin);
        var initial=forward(gate,origin,0);
        check(initial.allow() && initial.flat(),"flat initial input has real braking clearance");
        check(initial.reach()<.4,"flat support uses shorter ground coast");
        check(!forward(gate,motion(0,64,1.4,0,-.0784,.117,true),0).allow(),"full next-tick acceleration plus coast rejects before patch edge");
        check(!forward(gate,motion(1.1,64,1.1,.08,-.0784,.08,true),-45).allow(),"diagonal corner respects sphere, not just each axis");
        check(gate.check(origin,0,0,true,0,.13001,.42001,false).allow(),"neutral vanilla jump at centre fits unchanged vertical and sphere bounds");
        check(!gate.check(motion(.65,64,0,.06,-.0784,0,true),0,0,true,0,.13001,.42001,false).allow(),"jump reserves air drag from the first tick as well as its vertical apex");
        check(!gate.check(origin,-1,0,true,0,.13001,.42001,true).allow(),"opposing input cannot cancel the reserved sprint-jump impulse");
        check(!gate.check(motion(0,64.3,0,0,-.0784,0,true),0,0,true,0,.13001,.42001,false).allow(),"jump apex above host ceiling rejected before jump");
        check(!gate.check(origin,1,0,false,Double.NaN,.13001,.42001,false).allow(),"nonfinite heading fails closed");
        check(!gate.check(origin,1,0,false,0,.3,.42001,false).allow(),"unexpected speed fails closed");
        check(!gate.check(origin,2,0,false,0,.13001,.42001,false).allow(),"invalid direction fails closed");
        check(!forward(gate,motion(0,64,0,0,-.1,.25,false),0).allow(),"airborne motion reserves complete air coast");

        // Numeric height offsets from the failed27Oct live capture. Coordinates
        // and provenance are replaced by a standalone fixture; no assets/save.
        var slope=patch(new double[]{
            .5,.401115417480469,.301113128662109,.239219665527344,.139217376708984,
            .301113128662109,.239219665527344,.149997711181641,.0892181396484375,-.0107803344726562,
            .149997711181641,.0511131286621094,0,-.0988845825195312,-.160781860351562,
            .0654258728027344,-.0618934631347656,-.160781860351562,-.25,-.310779571533203,
            .118961334228516,-.172676086425781,-.272674560546875,-.361896514892578,-.460781097412109});
        double y=slope.groundForFeet(0,0,.3),yaw=Math.toDegrees(Math.atan2(-.290459,-.956887));
        var start=motion(0,y,0,0,-.0784,0,true);var downhill=new HudMovementBoundary(slope,start);
        check(Math.abs(y-64.11008262634277)<1e-8,"captured settled support height reproduced");
        check(forward(downhill,start,yaw).allow(),"captured patch permits initial physical walking");
        var unsafe=forward(downhill,motion(.12496852213797746,y,-.4116818383674196,.028661939772670793,-.0784,-.09442057771765487,true),yaw);
        check(!unsafe.allow(),"recorded approach is stopped before second drop, not after crossing host bound");
        check(!forward(downhill,motion(.2189813114400206,63.957109451293945,-.7213866925800805,.03356532296671531,-.0784,-.11057371590804964,true),yaw).allow(),"recorded lower safe step cannot coast into unsafe next step");
        check(!forward(downhill,motion(.48190169507837277,63.738661766052246,-1.587521180119247,.019784267489013765,-.0784,-.06517500144266153,true),yaw).allow(),"recorded outside-limit landing fails closed");

        check(downhill.check(motion(.2189813114400206,63.957109451293945,-.7213866925800805,0,-.0784,0,true),-1,0,false,yaw,.13001,.42001,false).allow(),"a released player can safely walk back from the sampled lower step");
        double[] inclined=new double[25];for(int row=0;row<5;row++)for(int col=0;col<5;col++)inclined[row*5+col]=-.4*(row-2);
        var steeper=patch(inclined);double top=steeper.groundForFeet(0,0,.3);
        var slopeGate=new HudMovementBoundary(steeper,motion(0,top,0,0,-.0784,0,true));
        double lower=steeper.groundForFeet(0,-.6,.3);
        check(top-lower>.2 && slopeGate.check(motion(0,lower,-.6,0,-.0784,0,true),0,0,false,0,.13001,.42001,false).allow(),"physical profile allows supported descent beyond the old0.2m limit inside the sphere");
        // Independently integrate ordinary flat-supported vanilla ticks until
        // the decision releases input, then coast. Sloped vanilla movement is
        // checked by the separate actual-Minecraft fixture, not this model.
        double x=0,z=0,vx=0,vz=0;boolean ended=false;int held=0;
        for(int tick=0;tick<30;tick++){
            var m=motion(x,64,z,vx,-.0784,vz,true);
            if(!ended && !forward(gate,m,yaw).allow())ended=true;
            double ax=ended?0:-Math.sin(Math.toRadians(yaw))*.098;
            double az=ended?0:Math.cos(Math.toRadians(yaw))*.098;
            if(!ended)held++;
            x+=vx+ax;z+=vz+az;vx=(vx+ax)*(.6f*.91f);vz=(vz+az)*(.6f*.91f);
            check(Math.abs(flat.groundForFeet(x,z,.3)-64)<1e-8,"flat regression keeps supported feet throughout neutral coast");
            check(Math.sqrt(x*x+z*z)<1.8,"regression coast remains inside existing Java guard");
        }
        check(ended && held>0,"boundary release is reachable after actual input");
        check(Math.hypot(x,z)>.8,"flat stopping envelope permits useful travel before releasing input");
        check(Math.hypot(vx,vz)<.003,"neutral coast reaches rest without modifying velocity");
        for(int angle=0;angle<360;angle+=45){
            check(forward(gate,origin,angle).allow(),"all eight headings supported on flat centre");
            check(gate.check(origin,1,1,false,angle,.13001,.42001,true).allow(),"diagonal normalization preserves flat clearance");
        }
        completion();
        var corridor=GroundCorridorTests.flatCorridor();
        var corridorAnchor=new MovementTraceSink.Motion(0,64,0,0,0,0,true,true,false,true);
        var corridorGate=new HudMovementBoundary(corridor,corridorAnchor);
        var crossed=new MovementTraceSink.Motion(5.5,64,0,.1,-.0784,0,true,true,false,true);
        check(forward(corridorGate,crossed,-90).allow(),"Physical corridor admits grounded travel beyond the old four-metre edge");
        check(corridorGate.check(crossed,-1,0,false,-90,.13001,.42001,false).allow(),"Physical corridor permits ordinary return input beyond old edge");
        var rightEdge=new MovementTraceSink.Motion(7.3,64,0,.1,-.0784,0,true,true,false,true);
        check(!forward(corridorGate,rightEdge,-90).allow(),"Physical corridor reserves raw rectangle stopping clearance");
        var leftEdge=new MovementTraceSink.Motion(-3.3,64,0,-.1,-.0784,0,true,true,false,true);
        check(!forward(corridorGate,leftEdge,90).allow(),"Physical corridor rejects braking past negative rectangle edge");
        var sideEdge=new MovementTraceSink.Motion(5.5,64,3.3,0,-.0784,.1,true,true,false,true);
        check(!forward(corridorGate,sideEdge,0).allow(),"Expanded X authority does not widen Z clearance");
        var offsetAnchor=new MovementTraceSink.Motion(.001,64,0,0,0,0,true,true,false,true);
        var offsetGate=new HudMovementBoundary(corridor,offsetAnchor);
        check(!forward(offsetGate,leftEdge,90).allow(),"Frozen nonzero physical anchor cannot expand native rectangle authority");
        // Actual29Oct captured run reached bothX>4.5, then W was released on
        // a slab descent. Retain its horizontal motion in this pure footprint
        // check: a conservative airborne coast passes7.5 before the old5.5 goal.
        var descending=new MovementTraceSink.Motion(4.73267331404574,63.68766368865967,0,.11855739150455975,-.1552320045166016,0,false,true,false,true);
        var descentStop=forward(corridorGate,descending,-90);
        check(!descentStop.allow()&&descentStop.reason().equals("sampled_footprint_braking_clearance"),
                "Recorded descent still releases W rather than weakening the sampled braking bound");
        check(descending.x()-.3>4,"Whole player footprint has already crossed the original edge before this stop");
        return checks;
    }
    private static void completion(){
        var finish=new HudMovementCompletion();long began=1_000_000_000L;
        // Actual failure: first slow client tick had crossed .15m, while the
        // fresh integrated-server sample was still at the previous .098m tick.
        check(finish.update(began,true,.15148964,.098)==HudMovementCompletion.Result.WAITING,"lagged server cannot prematurely fail final walking proof");
        check(finish.update(began+50_000_000L,true,.180695,.15148964)==HudMovementCompletion.Result.WAITING,"coasting client/server remain observable while proof catches up");
        check(finish.update(began+100_000_000L,true,.19664,.180695)==HudMovementCompletion.Result.WAITING,"no completion before minimum stable interval");
        check(finish.update(began+499_999_999L,true,.21,.21)==HudMovementCompletion.Result.WAITING,"full500ms grounded interval required");
        check(finish.update(began+500_000_000L,true,.21,.21)==HudMovementCompletion.Result.PASSED,"final independent client/server displacement passes after settling");
        var shortWalk=new HudMovementCompletion();
        check(shortWalk.update(began,true,.16,.098)==HudMovementCompletion.Result.WAITING,"insufficient server proof is initially pending");
        check(shortWalk.update(began+500_000_000L,true,.16,.098)==HudMovementCompletion.Result.INSUFFICIENT_WALK,"stable client-only movement still cannot pass");
        var interrupted=new HudMovementCompletion();
        interrupted.update(began,true,.2,.2);
        check(interrupted.update(began+400_000_000L,false,.2,.2)==HudMovementCompletion.Result.WAITING,"instability resets grounded interval");
        check(interrupted.update(began+500_000_000L,true,.2,.2)==HudMovementCompletion.Result.WAITING,"old stable time cannot be reused after instability");
        check(interrupted.update(began+999_999_999L,true,.2,.2)==HudMovementCompletion.Result.WAITING,"replacement stable interval must also last500ms");
        check(interrupted.update(began+1_000_000_000L,true,.2,.2)==HudMovementCompletion.Result.PASSED,"replacement complete interval can pass");
        var rewind=new HudMovementCompletion();rewind.update(began,true,.2,.2);
        check(rewind.update(began-1,true,.2,.2)==HudMovementCompletion.Result.WAITING,"regressed clock cannot grant completed stability");
    }
}
