float4x4 g_matWorldViewProj;
float4 g_lightNormal = { 0.3f, 1.0f, 0.5f, 0.0f };
float3 g_ambient = { 0.3f, 0.3f, 0.3f };

bool g_bUseTexture = true;

texture texture1;
sampler textureSampler = sampler_state
{
    Texture = (texture1);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// ▼ 頂点シェーダー：clip空間の z/w を 0..1 にして渡す + 法線を渡す
void VertexShader1(
    in float4 inPosition : POSITION,
    in float3 inNormal : NORMAL,
    in float2 inTexCoord0 : TEXCOORD0,
    out float4 outPosition : POSITION0,
    out float2 outTexCoord0 : TEXCOORD0,
    out float outDepth01 : TEXCOORD1,
    out float3 outNormal : TEXCOORD2)
{
    float4 clipPosition = mul(inPosition, g_matWorldViewProj);
    outPosition = clipPosition;
    outTexCoord0 = inTexCoord0;

    // 0..1（近=0, 遠=1）
    float depthNdc = clipPosition.z / clipPosition.w;
    outDepth01 = saturate(depthNdc);

    // 法線をそのまま渡す
    outNormal = inNormal;
}

// ▼ ピクセルシェーダー：N·Lライティング + MRTのCOLOR1にグレースケールで深度を書き込む
void PixelShaderMRT(
    in float2 inTexCoord0 : TEXCOORD0,
    in float inDepth01 : TEXCOORD1,
    in float3 inNormal : TEXCOORD2,
    out float4 outColor0 : COLOR0,
    out float4 outColor1 : COLOR1)
{
    float4 baseColor = float4(0.5, 0.5, 0.5, 1.0);

    if (g_bUseTexture)
    {
        baseColor = tex2D(textureSampler, inTexCoord0);
    }

    // N·L ランバートライティング
    float3 N = normalize(inNormal);
    float3 L = normalize(g_lightNormal.xyz);
    float NdotL = saturate(dot(N, L));
    float3 lighting = g_ambient + (1.0 - g_ambient) * NdotL;
    outColor0 = float4(baseColor.rgb * lighting, baseColor.a);

    // 近いほど黒、遠いほど白
    float d = inDepth01;
    outColor1 = float4(d, d, d, 1.0);
}

// ==== 追加: MRT を使うテクニック ====
technique TechniqueMRT
{
    pass P0
    {
        CullMode = NONE;
        VertexShader = compile vs_3_0 VertexShader1();
        PixelShader = compile ps_3_0 PixelShaderMRT();
    }
}
