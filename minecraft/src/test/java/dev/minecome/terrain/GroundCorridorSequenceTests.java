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
    static int run()throws Exception{
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
