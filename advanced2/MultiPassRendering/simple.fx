float4x4 g_matWorldViewProj;
float4x4 g_matView;
float4 g_lightNormal = { 0.3f, 1.0f, 0.5f, 0.0f };
float4 g_baseColor = { 0.5f, 0.5f, 0.5f, 1.0f };
float3 g_ambient = { 0.5f, 0.5f, 0.5f };

bool g_bUseTexture = true;

texture texture1;
sampler textureSampler = sampler_state
{
    Texture = (texture1);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

void VertexShader1(
    in float4 inPosition : POSITION,
    in float3 inNormal : NORMAL,
    in float2 inTexCoord0 : TEXCOORD0,
    out float4 outPosition : POSITION0,
    out float2 outTexCoord0 : TEXCOORD0,
    out float2 outClipZW : TEXCOORD1,
    out float3 outNormal : TEXCOORD2)
{
    float4 clipPosition = mul(inPosition, g_matWorldViewProj);
    outPosition = clipPosition;
    outTexCoord0 = inTexCoord0;

    // Reconstruct depth per-pixel from clip-space z and w.
    outClipZW = clipPosition.zw;

    outNormal = mul(inNormal, (float3x3)g_matView);
}

void PixelShaderMRT(
    in float2 inTexCoord0 : TEXCOORD0,
    in float2 inClipZW : TEXCOORD1,
    in float3 inNormal : TEXCOORD2,
    out float4 outColor0 : COLOR0,
    out float4 outColor1 : COLOR1,
    out float4 outColor2 : COLOR2)
{
    float4 baseColor = g_baseColor;

    if (g_bUseTexture)
    {
        baseColor = tex2D(textureSampler, inTexCoord0);
    }

    float3 N = normalize(inNormal);
    float3 L = normalize(g_lightNormal.xyz);
    float NdotL = saturate(dot(N, L));
    float3 lighting = g_ambient + (1.0 - g_ambient) * NdotL;
    outColor0 = float4(baseColor.rgb * lighting, baseColor.a);

    float d = saturate(inClipZW.x / inClipZW.y);
    outColor1 = float4(d, d, d, 1.0);

    outColor2 = float4(N * 0.5 + 0.5, 1.0);
}

technique TechniqueMRT
{
    pass P0
    {
        CullMode = NONE;
        VertexShader = compile vs_3_0 VertexShader1();
        PixelShader = compile ps_3_0 PixelShaderMRT();
    }
}
