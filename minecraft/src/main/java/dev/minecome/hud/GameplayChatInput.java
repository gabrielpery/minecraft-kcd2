package dev.minecome.hud;

/** Input6 character/edit-key contract; no game or platform calls. */
public final class GameplayChatInput {
    private GameplayChatInput(){}
    public static boolean opens(int code){return code==0x54||code==0xbf;}
    public static boolean scalar(int code){return code>=0x20&&code<=0x10ffff&&(code<0x7f||code>0x9f)&&(code<0xd800||code>0xdfff);}
    public static boolean editKey(int code){return switch(code){case 8,9,13,27,35,36,37,38,39,40,46->true;default->false;};}
    public static boolean repeatableEditKey(int code){return editKey(code)&&code!=13&&code!=27;}
    public static int glfw(int code){return switch(code){
        case 8->259;case 9->258;case 13->257;case 27->256;case 35->269;case 36->268;
        case 37->263;case 38->265;case 39->262;case 40->264;case 46->261;
        default->throw new IllegalArgumentException("Unsupported chat edit key");
    };}
    public static char[] characters(int code){if(!scalar(code))throw new IllegalArgumentException("Invalid chat scalar");return Character.toChars(code);}
}
