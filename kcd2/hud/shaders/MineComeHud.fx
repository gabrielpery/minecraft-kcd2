// Original bounded MineCome static snapshot proof. ReShade 6.8.0 FX syntax.
// TOPLEFT Minecraft straight RGBA8 is premultiplied once by the original addon.
// No world reconstruction, input hooks, depth reads, desktop window or icons.
texture McHud1 : MINECOME_HUD_1;
texture McHud2 : MINECOME_HUD_2;
texture McHud3 : MINECOME_HUD_3;
sampler McHudSampler1 { Texture=McHud1; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler McHudSampler2 { Texture=McHud2; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler McHudSampler3 { Texture=McHud3; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
uniform bool McHudActive = false;
uniform int McHudFrame = 0;
uniform float4 McHudRect = float4(0,0,1,1);
void McHudVS(uint id : SV_VertexID, out float4 position : SV_Position, out float2 uv : TEXCOORD) {
    uv = float2((id << 1) & 2, id & 2);
    position = float4(uv * float2(2,-2) + float2(-1,1),0,1);
}
float4 McHudPS(float4 position : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    if (!McHudActive || any(McHudRect.zw <= 0)) return 0;
    float2 source = (uv - McHudRect.xy) / McHudRect.zw;
    if (any(source < 0) || any(source >= 1)) return 0;
    if (McHudFrame == 0) return tex2D(McHudSampler1, source);
    if (McHudFrame == 1) return tex2D(McHudSampler2, source);
    return tex2D(McHudSampler3, source);
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
        // ReShade v6.8.0 runtime.cpp:2644-2645 unconditionally disables
        // depth test/write for FX graphics passes; there is no FX depth flag.
    }
}
