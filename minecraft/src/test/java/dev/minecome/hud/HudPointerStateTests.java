package dev.minecome.hud;

import java.util.List;

/** Gesture transitions that differ from a set of held mouse buttons. */
public final class HudPointerStateTests {
    private static int checks;
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    private static void rejected(Runnable action){
        boolean rejected=false;try{action.run();}catch(IllegalArgumentException|IllegalStateException expected){rejected=true;}
        check(rejected,"invalid edge must be rejected");
    }
    public static void main(String[] args){
        var pointer=new HudPointerState();
        check(pointer.activeButton()==-1 && pointer.heldCount()==0,"initial pointer neutral");
        pointer.press(0);check(pointer.activeButton()==0,"left drag active");
        pointer.press(1);check(pointer.activeButton()==1 && pointer.heldCount()==2,"latest down alone receives drag");
        rejected(()->pointer.press(1));
        check(pointer.release(0),"physical left up delivered");
        check(pointer.activeButton()==-1 && pointer.heldCount()==1,"any up clears vanilla active button, even another button");
        check(pointer.release(1),"remaining up delivered");rejected(()->pointer.release(1));

        pointer.press(0);pointer.press(1);
        List<Integer> releases=pointer.releaseScreen();
        check(releases.equals(List.of(0,1)),"close releases every held button once in press order");
        check(pointer.activeButton()==-1 && pointer.heldCount()==0,"close stops all dragging");
        check(pointer.releaseScreen().isEmpty(),"repeated screen cleanup is idempotent");
        check(pointer.awaitingRelease(0) && pointer.awaitingRelease(1),"physical ups remain tracked after screen close");
        check(pointer.pendingReleaseCount()==2,"close evidence counts both pending physical releases");
        rejected(()->pointer.press(0));
        check(!pointer.release(0),"late up is consumed without calling a new screen");
        check(pointer.pendingReleaseCount()==1,"consuming one late release preserves the other");
        pointer.press(0);
        check(!pointer.release(1) && pointer.activeButton()==0,"old-screen up cannot stop a new-screen gesture");
        check(pointer.release(0),"new-screen genuine up delivered");
        check(!pointer.awaitingRelease(0) && !pointer.awaitingRelease(1),"all physical edges balanced");
        check(pointer.pendingReleaseCount()==0,"all pending releases consumed exactly once");

        pointer.press(1);pointer.releaseScreen();pointer.clear();
        check(pointer.activeButton()==-1 && pointer.heldCount()==0 && !pointer.awaitingRelease(1),"terminal cleanup removes pending old-screen edges");
        rejected(()->pointer.release(1));pointer.press(1);check(pointer.release(1),"a fresh session can use the same button");
        rejected(()->pointer.press(-1));rejected(()->pointer.press(2));rejected(()->pointer.release(2));

        check(HudPointerState.wheel(3,false,2)==6,"continuous wheel applies sensitivity to all notches");
        check(HudPointerState.wheel(-3,false,0.5)==-1.5,"negative continuous wheel preserves direction");
        check(HudPointerState.wheel(3,true,2)==2,"discrete wheel normalizes before sensitivity");
        check(HudPointerState.wheel(-16,true,0.5)==-0.5,"discrete negative endpoint");
        check(HudPointerState.wheel(16,false,0)==0,"zero sensitivity produces no scrolling");
        rejected(()->HudPointerState.wheel(0,false,1));rejected(()->HudPointerState.wheel(17,false,1));
        rejected(()->HudPointerState.wheel(-17,false,1));rejected(()->HudPointerState.wheel(1,false,-1));
        rejected(()->HudPointerState.wheel(1,false,Double.NaN));rejected(()->HudPointerState.wheel(1,false,Double.POSITIVE_INFINITY));
        System.out.println("HUD_POINTER_STATE_TEST_PASS checks="+checks);
    }
}
