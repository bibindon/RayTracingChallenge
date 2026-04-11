bool g_bEnableSSAO = true;
float g_occlusionDarkenStrength = 1.35f;
float g_occlusionDepthBias = 0.000015f;
float g_occlusionDepthFalloff = 250.0f;

texture texture1;
sampler textureSampler = sampler_state
{
    Texture = (texture1);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture texture2;
sampler depthSampler = sampler_state
{
    Texture = (texture2);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture texture3;
sampler normalSampler = sampler_state
{
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

void PixelShader1(in float2 inTexCood : TEXCOORD0,
                  out float4 outColor : COLOR)
{
    float2 pixelSize = float2(1.0 / 1600.0, 1.0 / 900.0);
    float2 halfPixel = pixelSize * 0.5;
    float2 baseUV = clamp(inTexCood, halfPixel, 1.0 - halfPixel);

    float4 workColor = tex2D(textureSampler, baseUV);
    float depth = tex2D(depthSampler, baseUV).r;
    float3 normal = tex2D(normalSampler, baseUV).rgb * 2.0 - 1.0;

    if (!g_bEnableSSAO || depth >= 0.98)
    {
        outColor = workColor;
        return;
    }
    float2 marchDir = float2(normal.x, -normal.y);
    float dirLen = length(marchDir);
    if (dirLen <= 0.0001)
    {
        outColor = workColor;
        return;
    }

    marchDir = marchDir / dirLen;

    float occlusion = 0.0;

    for (int i = 0; i < 64; ++i)
    {
        float noise = frac(sin(dot(inTexCood + float2(i * 0.123, i * 0.371),
                                   float2(12.9898, 78.233))) * 43758.5453);
        float angleNoise = frac(sin(dot(inTexCood + float2(i * 0.719, i * 0.183),
                                        float2(39.3468, 11.1351))) * 24634.6345);

        float rayLength = noise * noise * 200.0;

        float angleOffset = angleNoise * 2.0 - 1.0;
        angleOffset = angleOffset * abs(angleOffset);
        angleOffset *= 1.5707963;

        float sinTheta = sin(angleOffset);
        float cosTheta = cos(angleOffset);
        float2 sampleDir = float2(
            marchDir.x * cosTheta - marchDir.y * sinTheta,
            marchDir.x * sinTheta + marchDir.y * cosTheta);

        float2 sampleUV = baseUV + sampleDir * pixelSize * rayLength;
        sampleUV = clamp(sampleUV, halfPixel, 1.0 - halfPixel);

        if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 &&
            sampleUV.y >= 0.0 && sampleUV.y <= 1.0)
        {
            float sampleDepth = tex2Dlod(depthSampler, float4(sampleUV, 0, 0)).r;
            float depthDiff = abs(depth - sampleDepth);
            float sampleWeight = 1.0 / (1.0 + depthDiff * g_occlusionDepthFalloff);

            if (sampleDepth + g_occlusionDepthBias < depth)
            {
                occlusion += sampleWeight;
            }
        }
    }

    float ao = 1.0 - saturate((occlusion / 64.0) * (1.0 / max(g_occlusionDarkenStrength, 0.0001)));
    outColor = float4(workColor.rgb * ao, workColor.a);
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
