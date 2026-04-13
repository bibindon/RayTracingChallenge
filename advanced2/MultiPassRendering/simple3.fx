//
// SSAOを描画していたがうまくいかなかったので消した。
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

float g_exposure = 1.0f;
bool g_bEnableToneMapping = true;
bool g_bEnableGaussianFilter = true;
float g_gaussianBlendFactor = 0.85f;
float g_gaussianDepthThreshold = 0.0035f;
float g_gaussianNormalDotThreshold = 0.95f;
float g_gaussianKernelRadius = 20.0f;

float3 ToneMapACES(float3 color)
{
    color *= g_exposure;
    color = max(color, 0.0);
    return saturate((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14));
}

float3 SafeNormalize(float3 value, float3 fallbackValue)
{
    float lenSq = dot(value, value);
    if (lenSq <= 0.0001)
    {
        return fallbackValue;
    }

    return value * rsqrt(lenSq);
}

float ComputeGaussianKernelWeight(int offsetX, int offsetY, float radius)
{
    float sigma = max(radius * 0.5, 1.0);
    float distanceSq = float(offsetX * offsetX + offsetY * offsetY);
    return exp(-distanceSq / (2.0 * sigma * sigma));
}

float4 ApplyEdgeAwareGaussian(float2 centerUV, float4 centerColor, float centerDepth, float3 centerNormal)
{
    float2 pixelSize = float2(1.0 / 1600.0, 1.0 / 900.0);
    float4 accumulatedColor = centerColor;
    float accumulatedWeight = 1.0;
    int kernelRadius = (int)clamp(g_gaussianKernelRadius, 1.0, 15.0);

    centerNormal = SafeNormalize(centerNormal, float3(0.0, 0.0, -1.0));

    for (int offsetY = -15; offsetY <= 15; ++offsetY)
    {
        if (abs(offsetY) > kernelRadius)
        {
            continue;
        }

        for (int offsetX = -15; offsetX <= 15; ++offsetX)
        {
            if (abs(offsetX) > kernelRadius || (offsetX == 0 && offsetY == 0))
            {
                continue;
            }

            float2 sampleUV = centerUV + float2(offsetX, offsetY) * pixelSize;
            if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0)
            {
                continue;
            }

            float sampleDepth = tex2Dlod(depthSampler, float4(sampleUV, 0, 0)).r;
            if (sampleDepth >= 0.99 || abs(sampleDepth - centerDepth) > g_gaussianDepthThreshold)
            {
                continue;
            }

            float3 sampleNormal = tex2Dlod(normalSampler, float4(sampleUV, 0, 0)).rgb * 2.0 - 1.0;
            sampleNormal = SafeNormalize(sampleNormal, centerNormal);
            if (dot(centerNormal, sampleNormal) < g_gaussianNormalDotThreshold)
            {
                continue;
            }

            float sampleWeight = ComputeGaussianKernelWeight(offsetX, offsetY, kernelRadius);
            float4 sampleColor = tex2Dlod(textureSampler, float4(sampleUV, 0, 0));
            accumulatedColor += sampleColor * sampleWeight;
            accumulatedWeight += sampleWeight;
        }
    }

    return accumulatedColor / max(accumulatedWeight, 0.0001);
}

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
    float4 hdrColor = tex2D(textureSampler, inTexCood);
    float depth = tex2D(depthSampler, inTexCood).r;
    float3 normal = tex2D(normalSampler, inTexCood).rgb * 2.0 - 1.0;
    if (g_bEnableGaussianFilter && depth < 0.99)
    {
        float4 filteredHdrColor = ApplyEdgeAwareGaussian(inTexCood, hdrColor, depth, normal);
        hdrColor = lerp(hdrColor, filteredHdrColor, saturate(g_gaussianBlendFactor));
    }

    float3 mappedColor = saturate(hdrColor.rgb);
    if (g_bEnableToneMapping)
    {
        mappedColor = ToneMapACES(hdrColor.rgb);
        mappedColor = pow(mappedColor, 1.0 / 2.2);
    }
    outColor = float4(mappedColor, saturate(hdrColor.a));
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
