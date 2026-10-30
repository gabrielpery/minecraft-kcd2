package dev.minecome.terrain;

/** Decision coverage using a real parsed corridor; actual physics remains the game fixture's job. */
final class GroundCorridorSequenceTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static GroundMovementSequence.Motion ground(double x){return new GroundMovementSequence.Motion(x,64,.5,0,0,0,true,true);}
    private static GroundMovementSequence prepared()throws Exception{
        return prepared(false);
    }
    private static GroundMovementSequence prepared(boolean walkOnly)throws Exception{
        var sequence=new GroundMovementSequence(GroundCorridorTests.flatCorridor(),0,walkOnly);
        sequence.update(0,ground(.5),ground(.5),0);
        check(sequence.update(2_000_000_000L,ground(.5),ground(.5),0).forward(),"Corridor begins with ordinary forward input after stable support");
        return sequence;
    }
    private static GroundMovementSequence returning()throws Exception{
        var sequence=prepared();
        check(sequence.update(2_050_000_000L,ground(5.7),ground(5.4),0).forward(),"Client crossing alone cannot finish the outward walk");
        check(!sequence.update(2_100_000_000L,ground(5.7),ground(5.7),0).forward(),"Both crossings release outward input");
        sequence.update(2_200_000_000L,ground(5.7),ground(5.7),0);
        check(sequence.update(3_200_000_000L,ground(5.7),ground(5.7),0).jump(),"Jump begins only after settling beyond the old edge");
        var air=new GroundMovementSequence.Motion(5.7,64.5,.5,0,.2,0,false,false);
        sequence.update(3_250_000_000L,air,air,0);sequence.update(3_300_000_000L,air,air,0);
        sequence.update(3_900_000_000L,ground(5.7),ground(5.7),0);
        var held=sequence.update(4_500_000_000L,ground(5.7),ground(5.7),0);
        check(held.backward()&&!held.forward()&&!held.jump()&&sequence.phase()==GroundMovementSequence.Phase.RETURNING,
                "Grounded jump completion begins backward input without changing yaw or teleporting");
        return sequence;
    }
    private static void extension()throws Exception{
        var plan=GroundExpansion.parse(GroundExpansionTests.fixture("standalone_fixture",0).toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
        var sequence=new GroundMovementSequence(plan.initial(),0,true,plan);
        sequence.update(0,ground(.5),ground(.5),0);
        check(sequence.update(2_000_000_000L,ground(.5),ground(.5),0).forward(),"Extension begins inside initial corridor");
        check(sequence.update(2_050_000_000L,ground(4.5),ground(4.5),0).forward(),"Extension reaches admission point through vanilla input");
        sequence.acceptExpansion(plan.expanded());
        check(sequence.update(2_100_000_000L,ground(8.5),ground(8.5),0).forward(),"Admitted surface allows crossing former8m edge");
        check(sequence.update(2_150_000_000L,ground(9.6),ground(9.4),0).forward(),"Extension waits for both observed targets");
        check(!sequence.update(2_200_000_000L,ground(9.6),ground(9.6),0).forward(),"Both-thread crossing releases held input");
        sequence.update(2_250_000_000L,ground(9.6),ground(9.6),0);
        check(sequence.update(3_250_000_000L,ground(9.6),ground(9.6),0).backward(),"Extension returns without teleport/jump");
        sequence.update(3_300_000_000L,ground(.8),ground(.8),0);
        sequence.update(3_350_000_000L,ground(.8),ground(.8),0);
        sequence.update(3_900_000_000L,ground(.8),ground(.8),0);
        check(sequence.phase()==GroundMovementSequence.Phase.PASSED&&sequence.clientWalk()>9&&sequence.serverWalk()>9,"Additive crossing and original-origin return pass");
        check(!sequence.clientAir()&&!sequence.serverAir(),"Extension walk does not claim jumps");
        var denied=new GroundMovementSequence(plan.initial(),0,true,plan);
        denied.update(0,ground(.5),ground(.5),0);denied.update(2_000_000_000L,ground(.5),ground(.5),0);
        denied.update(2_050_000_000L,ground(8.5),ground(8.5),0);
        check(denied.phase()==GroundMovementSequence.Phase.FAILED,"Unadmitted surface keeps original movement bounds");
        try{denied.acceptExpansion(plan.expanded());throw new AssertionError("Failed sequence revived");}
        catch(IllegalStateException expected){checks++;}
    }
    static int run()throws Exception{
        extension();
        var walk=prepared(true);
        walk.update(2_050_000_000L,ground(5.7),ground(5.7),0);
        walk.update(2_100_000_000L,ground(5.7),ground(5.7),0);
        var walkHeld=walk.update(3_100_000_000L,ground(5.7),ground(5.7),0);
        check(walkHeld.backward()&&!walkHeld.jump()&&walk.phase()==GroundMovementSequence.Phase.RETURNING,
                "Explicit walk-only variant returns after outward settling without jumping");
        walk.update(3_200_000_000L,ground(.8),ground(.8),0);
        walk.update(3_250_000_000L,ground(.8),ground(.8),0);
        walk.update(3_800_000_000L,ground(.8),ground(.8),0);
        check(walk.phase()==GroundMovementSequence.Phase.PASSED&&walk.clientMaxX()==5.7&&walk.serverMaxX()==5.7&&
                walk.clientReturnDistance()<.31&&walk.serverReturnDistance()<.31,
                "Walk-only preserves both-thread crossing and grounded return proof");
        check(!walk.clientAir()&&!walk.serverAir()&&!walk.clientLand()&&!walk.serverLand(),"Walk-only does not claim diagnostic jump or landing proof");
        var sequence=returning();
        check(sequence.update(4_550_000_000L,ground(.8),ground(1.1),0).backward(),"Return waits for both authoritative observations");
        check(!sequence.update(4_600_000_000L,ground(.8),ground(.8),0).backward(),"Return releases input before settling");
        sequence.update(4_650_000_000L,ground(.8),ground(.8),0);sequence.update(5_200_000_000L,ground(.8),ground(.8),0);
        check(sequence.phase()==GroundMovementSequence.Phase.PASSED&&sequence.clientAir()&&sequence.serverLand(),"Full crossing/jump/return completes inside original20s budget");
        check(sequence.clientMaxX()==5.7&&sequence.serverMaxX()==5.7&&sequence.clientReturnDistance()<.31&&sequence.serverReturnDistance()<.31,
                "Both maximum crossing and final return distance are retained");
        var blocked=prepared();for(int i=1;i<=60;i++)blocked.update(2_000_000_000L+i*50_000_000L,ground(.5),ground(.5),0);
        check(blocked.phase()==GroundMovementSequence.Phase.FAILED,"An obstructed outward walk cannot hold keys indefinitely");
        var blockedReturn=returning();for(int i=1;i<=60;i++)blockedReturn.update(4_500_000_000L+i*50_000_000L,ground(5.7),ground(5.7),0);
        check(blockedReturn.phase()==GroundMovementSequence.Phase.FAILED,"An obstructed return cannot hold keys indefinitely");
        var divergence=prepared();divergence.update(2_050_000_000L,ground(2),ground(.5),0);
        check(divergence.phase()==GroundMovementSequence.Phase.FAILED,"Diverging client/server observations fail the corridor");
        var boundary=prepared();boundary.update(2_050_000_000L,ground(7.6),ground(7.6),0);
        check(boundary.phase()==GroundMovementSequence.Phase.FAILED,"Corridor coverage still stops before its outer edge");
        var correction=prepared();correction.update(2_050_000_000L,ground(.5),ground(.5),1);
        check(correction.phase()==GroundMovementSequence.Phase.FAILED,"Vanilla position correction cannot masquerade as seam crossing");
        return checks;
    }
}
