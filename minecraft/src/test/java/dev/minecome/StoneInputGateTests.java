package dev.minecome;

import dev.minecome.protocol.Protocol;

public final class StoneInputGateTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    public static void main(String[] args) {
        var air=new StoneInputGate.State(true,true,true,true,true,false,true,false);
        var stone=new StoneInputGate.State(true,true,true,true,true,true,false,false);
        check(StoneInputGate.evaluate(Protocol.PLACE_STONE,air)==0,"air in owned Creative lab permits vanilla placement");
        check(StoneInputGate.evaluate(Protocol.BREAK_STONE,stone)==0,"stone in owned Creative lab permits vanilla break");
        check(StoneInputGate.evaluate(Protocol.PLACE_STONE,stone)==Protocol.INPUT_OCCUPIED,"placement never replaces stone");
        check(StoneInputGate.evaluate(Protocol.BREAK_STONE,air)==Protocol.INPUT_ABSENT,"absent stone never dispatches break");
        var other=new StoneInputGate.State(true,true,true,true,true,false,false,false);
        check(StoneInputGate.evaluate(Protocol.BREAK_STONE,other)==Protocol.INPUT_OCCUPIED,"non-stone blocks cannot be remotely broken");
        for(int missing=0;missing<5;missing++) {
            boolean[] fields={true,true,true,true,true};fields[missing]=false;
            var unavailable=new StoneInputGate.State(fields[0],fields[1],fields[2],fields[3],fields[4],false,true,false);
            check(StoneInputGate.evaluate(Protocol.PLACE_STONE,unavailable)==Protocol.INPUT_UNAVAILABLE,"missing lab/creative/chunk/reach/support fails closed "+missing);
            check(StoneInputGate.evaluate(Protocol.BREAK_STONE,unavailable)==Protocol.INPUT_UNAVAILABLE,"break uses same ownership checks "+missing);
        }
        var busy=new StoneInputGate.State(true,true,true,true,true,false,true,true);
        check(StoneInputGate.evaluate(Protocol.PLACE_STONE,busy)==Protocol.INPUT_BUSY,"one vanilla action remains pending until proof/timeout");
        try{StoneInputGate.evaluate(3,air);throw new AssertionError("Unknown action accepted");}catch(IllegalArgumentException expected){checks++;}
        System.out.println("StoneInputGateTests: "+checks+" checks passed");
    }
}
