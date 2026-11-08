// Genuine Minecraft pixels with an original cursor for the captured inventory.
// Minecraft's OS cursor is not part of its framebuffer. No inventory is redrawn.
#ifndef MINECOME_WORLD_SOURCE_WIDTH
#define MINECOME_WORLD_SOURCE_WIDTH 1280
#endif
#ifndef MINECOME_WORLD_SOURCE_HEIGHT
#define MINECOME_WORLD_SOURCE_HEIGHT 720
#endif
texture McHud1 : MINECOME_HUD_1;
texture McHud2 : MINECOME_HUD_2;
texture McHud3 : MINECOME_HUD_3;
texture McHostDepth : DEPTH;
sampler McHostDepthSampler { Texture=McHostDepth; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler McHudSampler1 { Texture=McHud1; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler McHudSampler2 { Texture=McHud2; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler McHudSampler3 { Texture=McHud3; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
uniform bool McHudActive = false;
uniform int McHudFrame = 0;
uniform float4 McHudRect = float4(0,0,1,1);
uniform bool McHudCursorVisible = false;
uniform float4 McHudCursor = float4(0,0,1,0);
// Format2 is a vertical atlas: overlay, world color, then float depth bytes.
// Only the world layer participates in scene occlusion; hands/UI stay in front.
uniform bool McHudLayers = false;
uniform bool McHostDepthAvailable < source="bufready_depth"; >;
uniform bool McHostDepthReady = false;
uniform float4 McHostProjection = float4(0,0,0,0);
uniform float4 McHostNearest = float4(0,0,0,0);
uniform float2 McGuestProjection = float2(0.05,512);
// Native validates source identity/age, exact1280x720 atlas dimensions, current
// camera/depth ownership and these finite bases/projection rows before enabling.
// Source UTC is never renewed by this current-view rasterization.
uniform bool McWorldWarpReady = false;
uniform float3 McWarpSourceOrigin = 0;
uniform float3 McWarpSourceForward = float3(0,1,0);
uniform float3 McWarpSourceUp = float3(0,0,1);
uniform float2 McWarpSourceTanHalf = float2(1,1);
uniform float3 McWarpTargetOrigin = 0;
uniform float3 McWarpTargetRight = float3(1,0,0);
uniform float3 McWarpTargetForward = float3(0,1,0);
uniform float3 McWarpTargetUp = float3(0,0,1);
// Canonical rows act on (right,up,positive-forward,1), including native jitter.
uniform float4 McWarpClipX = float4(1,0,0,0);
uniform float4 McWarpClipY = float4(0,1,0,0);
uniform float4 McWarpClipZ = float4(0,0,1,0);
uniform float4 McWarpClipW = float4(0,0,1,0);
texture McWarpNearest { Width=BUFFER_WIDTH; Height=BUFFER_HEIGHT; Format=R32F; MipLevels=1; };
texture McWarpWorld { Width=BUFFER_WIDTH; Height=BUFFER_HEIGHT; Format=RGBA8; MipLevels=1; };
sampler McWarpNearestSampler { Texture=McWarpNearest; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };
sampler McWarpWorldSampler { Texture=McWarpWorld; AddressU=CLAMP; AddressV=CLAMP; MinFilter=POINT; MagFilter=POINT; MipFilter=POINT; };

// One independent constant-depth quad per actual source pixel. Neighboring
// pixels never share a triangle: depth jumps and disocclusions cannot acquire
// invented connecting surfaces. Uncovered target pixels remain transparent.
struct McWarpVertex {
    float4 position : SV_Position;
    float2 source : TEXCOORD0;
    float targetDepth : TEXCOORD1;
};
McWarpVertex McWarpVS(uint id : SV_VertexID) {
    McWarpVertex output;
    output.position=float4(2,2,2,1); output.source=0; output.targetDepth=0;
    if (!McWorldWarpReady || !McHudActive || !McHudLayers || id >= MINECOME_WORLD_SOURCE_WIDTH*MINECOME_WORLD_SOURCE_HEIGHT*6) return output;
    uint pixel=id/6, vertex=id%6;
    float2 cell=float2(pixel%MINECOME_WORLD_SOURCE_WIDTH,pixel/MINECOME_WORLD_SOURCE_WIDTH);
    float2 source=(cell+0.5)/float2(MINECOME_WORLD_SOURCE_WIDTH,MINECOME_WORLD_SOURCE_HEIGHT);
    float4 colour=tex2Dlod(McHudSampler1,float4(source.x,(source.y+1.0)/3.0,0,0));
    if (!(colour.a>0)) return output;
    uint4 bytes=(uint4)round(tex2Dlod(McHudSampler1,float4(source.x,(source.y+2.0)/3.0,0,0))*255.0);
    float raw=asfloat(bytes.x | (bytes.y<<8) | (bytes.z<<16) | (bytes.w<<24));
    if (!(raw>=0 && raw<1)) return output;
    float depth=McGuestProjection.x*McGuestProjection.y /
        (McGuestProjection.y-raw*(McGuestProjection.y-McGuestProjection.x));
    if (!(depth>0) || isinf(depth) || isnan(depth)) return output;
    float3 sourceRight=cross(McWarpSourceForward,McWarpSourceUp);
    float2 centrePlane=(source*float2(2,-2)+float2(-1,1))*McWarpSourceTanHalf;
    float3 relative=McWarpSourceOrigin-McWarpTargetOrigin+
        depth*(McWarpSourceForward+sourceRight*centrePlane.x+McWarpSourceUp*centrePlane.y);
    // Reject the whole pixel if its plane crosses the target eye. Replacing
    // only individual behind-eye vertices would create artificial triangles.
    float2 halfExtent=depth*McWarpSourceTanHalf/float2(MINECOME_WORLD_SOURCE_WIDTH,MINECOME_WORLD_SOURCE_HEIGHT);
    float minimumDepth=dot(relative,McWarpTargetForward)-
        abs(dot(sourceRight,McWarpTargetForward))*halfExtent.x-
        abs(dot(McWarpSourceUp,McWarpTargetForward))*halfExtent.y;
    if (!(minimumDepth>0.0001)) return output;
    float2 corner=vertex==0?float2(0,0):vertex==1?float2(1,0):
        vertex==2?float2(0,1):vertex==3?float2(0,1):vertex==4?float2(1,0):float2(1,1);
    relative+=sourceRight*((corner.x-0.5)*2.0*halfExtent.x)+
        McWarpSourceUp*((0.5-corner.y)*2.0*halfExtent.y);
    float4 local=float4(dot(relative,McWarpTargetRight),dot(relative,McWarpTargetUp),dot(relative,McWarpTargetForward),1);
    float4 clip=float4(dot(McWarpClipX,local),dot(McWarpClipY,local),dot(McWarpClipZ,local),dot(McWarpClipW,local));
    if (any(isnan(clip)) || any(isinf(clip))) return output;
    output.position=clip; output.source=source; output.targetDepth=local.z;
    return output;
}
float McWarpNearestPS(McWarpVertex input) : SV_Target {
    if (!(input.targetDepth>0)) discard;
    return 1.0/input.targetDepth;
}
float4 McWarpWorldPS(McWarpVertex input) : SV_Target {
    if (!(input.targetDepth>0)) discard;
    float inverseDepth=1.0/input.targetDepth;
    float nearest=tex2D(McWarpNearestSampler,input.position.xy/float2(BUFFER_WIDTH,BUFFER_HEIGHT)).r;
    // Both passes execute identical geometry/interpolation. R32F roundoff is
    // allowed only at float precision, not a physical-depth surface dilation.
    if (!(nearest>0) || inverseDepth<nearest-max(nearest*0.0000005,0.00000001)) discard;
    return tex2D(McHudSampler1,float2(input.source.x,(input.source.y+1.0)/3.0));
}
float McGuestDepth(float2 source) {
    uint4 bytes = (uint4)round(tex2D(McHudSampler1,float2(source.x,(source.y+2.0)/3.0))*255.0);
    float raw = asfloat(bytes.x | (bytes.y<<8) | (bytes.z<<16) | (bytes.w<<24));
    return McGuestProjection.x*McGuestProjection.y /
        (McGuestProjection.y-raw*(McGuestProjection.y-McGuestProjection.x));
}
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
    if (McHudLayers) {
        float4 overlay = tex2D(McHudSampler1,float2(source.x,source.y/3.0));
        float4 world = McWorldWarpReady ? tex2D(McWarpWorldSampler,uv) : tex2D(McHudSampler1,float2(source.x,(source.y+1.0)/3.0));
        // Camera/projection proof is supplied by the guarded native tracker.
        if (McHostDepthReady && McHostDepthAvailable && world.a > 0) {
            float raw = tex2D(McHostDepthSampler,uv).r;
            // KCD2 tools LinearizeDepthPS, including its separate nearest-camera
            // projection. Coefficients come from reflected CBPerViewGlobal:b6.
            float sky = McHostProjection.w > 0.5 ? 0.0 : 1.0;
            if (raw != sky) {
                float normalized = McHostProjection.y/(raw-McHostProjection.x);
                float nearestMax = McHostProjection.y/(McHostNearest.z-McHostProjection.x);
                if (normalized < nearestMax) normalized = McHostNearest.y/(raw-McHostNearest.x);
                float metres = normalized*McHostProjection.z;
                float guestMetres=McWorldWarpReady ? 1.0/max(tex2D(McWarpNearestSampler,uv).r,0.00000001) : McGuestDepth(source);
                if (metres > 0 && metres < McHostProjection.z && guestMetres > metres + 0.03)
                    world = 0;
            }
        }
        color = overlay + world*(1.0-overlay.a);
    }
    else if (McHudFrame == 0) color = tex2D(McHudSampler1, source);
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
// ReShade6.8.0 FX forcibly disables hardware depth writes/tests. Positive
// reciprocal depth with MAX blending supplies nearest-surface arbitration in
// an independently zero-cleared R32F target; the colour pass resolves against it.
// Native must keep this technique ordered before MineComeHud.
technique MineComeWorldWarp {
    pass Nearest {
        VertexShader=McWarpVS; PixelShader=McWarpNearestPS;
        VertexCount=MINECOME_WORLD_SOURCE_WIDTH*MINECOME_WORLD_SOURCE_HEIGHT*6; PrimitiveTopology=TRIANGLELIST;
        RenderTarget=McWarpNearest;
        BlendEnable=true; SrcBlend=ONE; DestBlend=ONE; BlendOp=MAX;
        SrcBlendAlpha=ONE; DestBlendAlpha=ONE; BlendOpAlpha=MAX;
        SRGBWriteEnable=false; ClearRenderTargets=true;
        StencilEnable=false; StencilWriteMask=0; GenerateMipmaps=false;
    }
    pass Resolve {
        VertexShader=McWarpVS; PixelShader=McWarpWorldPS;
        VertexCount=MINECOME_WORLD_SOURCE_WIDTH*MINECOME_WORLD_SOURCE_HEIGHT*6; PrimitiveTopology=TRIANGLELIST;
        RenderTarget=McWarpWorld;
        BlendEnable=false; SRGBWriteEnable=false; ClearRenderTargets=true;
        StencilEnable=false; StencilWriteMask=0; GenerateMipmaps=false;
    }
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
