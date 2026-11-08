package dev.minecome.hud;

/** Format2: overlay RGBA, world RGBA, raw GL depth float32; each plane is equally sized. */
final class HudLayerPixels {
    private HudLayerPixels() {}
    static int byteSize(int width,int height){return Math.multiplyExact(HudPixels.byteSize(width,height),3);}
    static void require(byte[] layers,int width,int height){
        if(layers==null||layers.length!=byteSize(width,height))throw new IllegalArgumentException("Incorrect layered HUD byte count");
    }
    static byte[] straightTopLeft(byte[] bottomUp,int width,int height){
        require(bottomUp,width,height);int plane=HudPixels.byteSize(width,height),row=width*4;
        byte[] result=new byte[bottomUp.length];
        for(int p=0;p<2;p++)for(int y=0;y<height;y++)for(int x=0;x<row;x+=4){
            int source=p*plane+(height-1-y)*row+x,destination=p*plane+y*row+x,alpha=bottomUp[source+3]&255;
            result[destination+3]=(byte)alpha;
            // Opaque world/HUD pixels are already straight alpha. Avoid three
            // integer divisions per pixel on the latency-sensitive publisher.
            if(alpha==255){result[destination]=bottomUp[source];result[destination+1]=bottomUp[source+1];result[destination+2]=bottomUp[source+2];}
            else if(alpha!=0)for(int c=0;c<3;c++)result[destination+c]=(byte)Math.min(255,((bottomUp[source+c]&255)*255+alpha/2)/alpha);
        }
        // Depth is not colour. Preserve all IEEE754 bits, changing row order only.
        for(int y=0;y<height;y++)System.arraycopy(bottomUp,2*plane+(height-1-y)*row,result,2*plane+y*row,row);
        return result;
    }
    /** Legacy fixture/PNG view only; the transport retains independent layers. */
    static byte[] flattenBottomUp(byte[] layers,int width,int height){
        require(layers,width,height);int plane=HudPixels.byteSize(width,height);byte[] result=new byte[plane];
        for(int p=0;p<plane;p+=4){int inverse=255-(layers[p+3]&255);
            for(int c=0;c<4;c++)result[p+c]=(byte)Math.min(255,(layers[p+c]&255)+((layers[plane+p+c]&255)*inverse+127)/255);
        }
        return result;
    }
}
