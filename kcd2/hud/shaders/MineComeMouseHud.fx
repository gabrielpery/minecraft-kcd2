// Genuine Minecraft pixels with an original cursor for the captured inventory.
// Minecraft's OS cursor is not part of its framebuffer. No inventory is redrawn.
texture McHud1 : MINECOME_HUD_1;
texture McHud2 : MINECOME_HUD_2;
texture McHud3 : MINECOME_HUD_3;
sampler McHudSampler1 { Texture=McHud1; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler McHudSampler2 { Texture=McHud2; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler McHudSampler3 { Texture=McHud3; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
uniform bool McHudActive = false;
uniform int McHudFrame = 0;
uniform float4 McHudRect = float4(0,0,1,1);
uniform bool McHudCursorVisible = false;
uniform float4 McHudCursor = float4(0,0,1,0);
void McHudVS(uint id : SV_VertexID, out float4 position : SV_Position, out float2 uv : TEXCOORD) {
    uv = float2((id << 1) & 2, id & 2);
    position = float4(uv * float2(2,-2) + float2(-1,1),0,1);
}
bool McHudArrow(float2 p) {
    // Pixel-aligned arrow: triangle and short diagonal stem.
    bool head = p.x >= 0 && p.y >= 0 && p.y <= 12 && p.x <= p.y * 0.75 && p.x <= 9;
    bool stem = p.y >= 9 && p.y <= 17 && p.x >= 3 && p.x <= 7 && abs(p.x - (p.y * 0.4 - 0.6)) <= 1.5;
    return head || stem;
}
float4 McHudPS(float4 position : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    if (!McHudActive || any(McHudRect.zw <= 0)) return 0;
    float2 source = (uv - McHudRect.xy) / McHudRect.zw;
    if (any(source < 0) || any(source >= 1)) return 0;
    float4 color;
    if (McHudFrame == 0) color = tex2D(McHudSampler1, source);
    else if (McHudFrame == 1) color = tex2D(McHudSampler2, source);
    else color = tex2D(McHudSampler3, source);
    if (McHudCursorVisible) {
        float2 p = floor((position.xy - McHudCursor.xy) / max(1.0,McHudCursor.z));
        if (McHudArrow(p)) {
            bool inside = McHudArrow(p+float2(1,0)) && McHudArrow(p-float2(1,0)) &&
                          McHudArrow(p+float2(0,1)) && McHudArrow(p-float2(0,1));
            color = inside ? float4(1,1,1,1) : float4(0,0,0,1);
        }
    }
    return color;
}
technique MineComeHud {
    pass {
        VertexShader=McHudVS; PixelShader=McHudPS;
        BlendEnable=true;
        SrcBlend=ONE; DestBlend=INVSRCALPHA;
        SrcBlendAlpha=ONE; DestBlendAlpha=INVSRCALPHA;
        SRGBWriteEnable=false;
        ClearRenderTargets=false; StencilEnable=false; StencilWriteMask=0;
        GenerateMipmaps=false;
    }
}
