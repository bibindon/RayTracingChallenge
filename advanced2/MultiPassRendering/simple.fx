float4x4 g_matWorldViewProj;
float4x4 g_matWorld;
float4x4 g_matView;
float4 g_lightPosition = { -8.0f, 8.0f, -8.0f, 1.0f };
float4 g_baseColor = { 0.5f, 0.5f, 0.5f, 1.0f };
float3 g_ambient = { 0.4f, 0.4f, 0.4f };
float g_hdrIntensity = 1.0f;

bool g_bUseTexture = true;
bool g_bUnlit = false;

texture texture1;
sampler textureSampler = sampler_state
{
    Texture = (texture1);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

void VertexShader1(
    in float4 inPosition : POSITION,
    in float3 inNormal : NORMAL,
    in float3 inTangent : TANGENT,
    in float2 inTexCoord0 : TEXCOORD0,
    out float4 outPosition : POSITION0,
    out float2 outTexCoord0 : TEXCOORD0,
    out float2 outClipZW : TEXCOORD1,
    out float3 outNormal : TEXCOORD2,
    out float3 outTangent : TEXCOORD3,
    out float3 outWorldNormal : TEXCOORD4,
    out float3 outWorldPosition : TEXCOORD5)
{
    float4 clipPosition = mul(inPosition, g_matWorldViewProj);
    float4 worldPosition = mul(inPosition, g_matWorld);
    outPosition = clipPosition;
    outTexCoord0 = inTexCoord0;

    // Reconstruct depth per-pixel from clip-space z and w.
    outClipZW = clipPosition.zw;

    outNormal = mul(inNormal, (float3x3)g_matView);
    outTangent = mul(inTangent, (float3x3)g_matView);
    outWorldNormal = mul(inNormal, (float3x3)g_matWorld);
    outWorldPosition = worldPosition.xyz;
}

void PixelShaderMRT(
    in float2 inTexCoord0 : TEXCOORD0,
    in float2 inClipZW : TEXCOORD1,
    in float3 inNormal : TEXCOORD2,
    in float3 inTangent : TEXCOORD3,
    in float3 inWorldNormal : TEXCOORD4,
    in float3 inWorldPosition : TEXCOORD5,
    out float4 outColor0 : COLOR0,
    out float4 outColor1 : COLOR1,
    out float4 outColor2 : COLOR2,
    out float4 outColor3 : COLOR3)
{
    float4 baseColor = g_baseColor;

    if (g_bUseTexture)
    {
        baseColor = tex2D(textureSampler, inTexCoord0);
    }
    baseColor.rgb *= g_hdrIntensity;

    float3 litColor = baseColor.rgb;
    if (!g_bUnlit)
    {
        float3 N = normalize(inWorldNormal);
        float3 L = normalize(g_lightPosition.xyz - inWorldPosition);
        float NdotL = saturate(dot(N, L));
        float3 lighting = g_ambient + (1.0 - g_ambient) * NdotL;
        litColor *= lighting;
    }
    outColor0 = float4(litColor, baseColor.a);

    float d = saturate(inClipZW.x / inClipZW.y);
    outColor1 = float4(d, d, d, 1.0);

    float3 N = normalize(inNormal);
    outColor2 = float4(N * 0.5 + 0.5, 1.0);

    float3 T = normalize(inTangent - N * dot(inTangent, N));
    outColor3 = float4(T * 0.5 + 0.5, 1.0);
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
