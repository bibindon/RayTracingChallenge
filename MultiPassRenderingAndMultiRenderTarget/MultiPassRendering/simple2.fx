float4x4 g_matWorldViewProj;
float4 g_lightNormal = { 0.3f, 1.0f, 0.5f, 0.0f };
float3 g_ambient = { 0.3f, 0.3f, 0.3f };

bool g_bUseTexture = true;

texture texture1;
sampler textureSampler = sampler_state {
    Texture = (texture1);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture texture2;
sampler depthSampler = sampler_state {
    Texture = (texture2);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture texture3;
sampler normalSampler = sampler_state {
    Texture = (texture3);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

void VertexShader1(in  float4 inPosition  : POSITION,
                   in  float2 inTexCood   : TEXCOORD0,

                   out float4 outPosition : POSITION,
                   out float2 outTexCood  : TEXCOORD0)
{
    outPosition = inPosition;
    outTexCood = inTexCood;
}

void PixelShader1(in float4 inPosition    : POSITION,
                  in float2 inTexCood     : TEXCOORD0,

                  out float4 outColor     : COLOR)
{
    float4 workColor = tex2D(textureSampler, inTexCood);

    // 深度テクスチャからサンプリング（0=近, 1=遠）
    float depth = tex2D(depthSampler, inTexCood).r;

    // 法線テクスチャからサンプリングし [0,1] → [-1,1] にデコード
    float3 normal = tex2D(normalSampler, inTexCood).rgb * 2.0 - 1.0;

    // --- スクリーンスペース レイマーチング（1次反射） ---

    // 1ピクセル分の UV ステップ
    float2 pixelSize = float2(1.0 / 1600.0, 1.0 / 900.0);

    // 法線の XY をスクリーンスペースのマーチ方向に使用
    // UV 空間は V が下向きなので Y を反転
    float2 marchDir = float2(normal.x, -normal.y);
    float dirLen = length(marchDir);

    if (dirLen > 0.001)
    {
        marchDir = marchDir / dirLen; // 正規化

        // 法線方向に 100 ピクセル先の UV を求める
        float2 sampleUV = inTexCood + marchDir * pixelSize * 100.0;

        // 範囲内なら深度チェック
        if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 &&
            sampleUV.y >= 0.0 && sampleUV.y <= 1.0)
        {
            float sampleDepth = tex2D(depthSampler, sampleUV).r;

            // マーチ先の深度が現在のピクセルより小さい（手前にある）ならヒット
            if (sampleDepth < depth - 0.001)
            {
                // ヒット地点のカラーを半分だけ混ぜて表示
                float4 hitColor = tex2D(textureSampler, sampleUV);
                workColor = lerp(workColor, hitColor, 0.5);
            }
        }
    }

    outColor = workColor;

}

technique Technique1
{
    pass Pass1
    {
        CullMode = NONE;

        VertexShader = compile vs_3_0 VertexShader1();
        PixelShader = compile ps_3_0 PixelShader1();
   }
}
