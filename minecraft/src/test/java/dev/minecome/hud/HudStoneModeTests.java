package dev.minecome.hud;

public final class HudStoneModeTests {
    public static void main(String[] args) {
        int checks=0;
        // All opt-in combinations: no stone mode, exact standalone profile, exact live profile.
        for(int mask=0;mask<(1<<11);mask++){
            boolean[] f=new boolean[11];for(int bit=0;bit<f.length;bit++)f[bit]=(mask&(1<<bit))!=0;
            boolean none=!f[0]&&!f[1]&&!f[2];
            boolean fixture=f[0]&&f[1]&&!f[2]&&f[3]&&f[4]&&f[5]&&f[6]&&!f[7]&&!f[8]&&!f[9]&&!f[10];
            boolean live=f[0]&&!f[1]&&f[2]&&f[3]&&!f[4]&&f[5]&&!f[6]&&!f[7]&&!f[8]&&!f[9]&&f[10];
            boolean accepted;
            try{HudStoneMode.require(f[0],f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8],f[9],f[10]);accepted=true;}
            catch(IllegalArgumentException expected){accepted=false;}
            if(accepted!=(none||fixture||live))throw new AssertionError("Stone mode flags incorrectly handled: "+mask);
            checks++;
        }
        System.out.println("HudStoneModeTests: "+checks+" checks passed.");
    }
}
