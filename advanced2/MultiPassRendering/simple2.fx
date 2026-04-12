bool g_bEnableRayTracing = true;
float g_indirectLightIntensity = 0.43f;
float g_sampleRadius = 30.0f;
float g_depthCompareBias = 0.02f;
float g_depthCompareFalloff = 6.0f;
float4x4 g_matProj;
float4x4 g_matProjInv;

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

texture texture4;
sampler tangentSampler = sampler_state {
    Texture = (texture4);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

float3 SafeNormalize(float3 value, float3 fallbackValue)
{
    float lenSq = dot(value, value);
    if (lenSq <= 0.0001)
    {
        return fallbackValue;
    }

    return value * rsqrt(lenSq);
}

float3 ReconstructViewPosition(float2 uv, float depth)
{
    float2 ndc = uv * 2.0 - 1.0;
    ndc.y = -ndc.y;

    float4 clipPos = float4(ndc, depth, 1.0);
    float4 viewPos = mul(clipPos, g_matProjInv);
    return viewPos.xyz / max(viewPos.w, 0.0001);
}

float2 ProjectViewPositionToUV(float3 viewPos)
{
    float4 clipPos = mul(float4(viewPos, 1.0), g_matProj);
    float2 ndc = clipPos.xy / max(clipPos.w, 0.0001);
    float2 uv = ndc * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;
    return uv;
}

void BuildBasis(float3 normal, float3 tangentInput, out float3 tangent, out float3 binormal)
{
    tangent = tangentInput - normal * dot(tangentInput, normal);
    tangent = SafeNormalize(tangent, float3(1.0, 0.0, 0.0));

    if (abs(dot(tangent, normal)) > 0.999)
    {
        float3 up = abs(normal.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
        tangent = SafeNormalize(cross(up, normal), float3(1.0, 0.0, 0.0));
    }

    binormal = SafeNormalize(cross(normal, tangent), float3(0.0, 1.0, 0.0));
    tangent = SafeNormalize(cross(binormal, normal), tangent);
}

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
    float2 pixelSize = float2(1.0 / 1600.0, 1.0 / 900.0);
    inTexCood += pixelSize * 0.5f;

    float4 workColor = tex2D(textureSampler, inTexCood);
    float depth = tex2D(depthSampler, inTexCood).r;
    float3 normal = tex2D(normalSampler, inTexCood).rgb * 2.0 - 1.0;
    float3 tangentInput = tex2D(tangentSampler, inTexCood).rgb * 2.0 - 1.0;

    normal = SafeNormalize(normal, float3(0.0, 0.0, -1.0));

    if (!g_bEnableRayTracing || depth >= 0.99)
    {
        outColor = workColor;
        return;
    }

    float3 tangent;
    float3 binormal;
    BuildBasis(normal, tangentInput, tangent, binormal);

    float3 baseViewPos = ReconstructViewPosition(inTexCood, depth);
    float4 accumulatedColor = workColor;
    float accumulatedWeight = 1.0;

    for (int i = 0; i < 64; ++i)
    {
        float noise = frac(sin(dot(inTexCood + float2(i * 0.123, i * 0.371),
                                   float2(12.9898, 78.233))) * 43758.5453);
        float angleNoise = frac(sin(dot(inTexCood + float2(i * 0.719, i * 0.183),
                                        float2(39.3468, 11.1351))) * 24634.6345);

        float radiusNoise = sqrt(noise);
        float phi = angleNoise * 6.2831853;
        float localZ = sqrt(saturate(1.0 - noise));
        float2 localXY = float2(cos(phi), sin(phi)) * radiusNoise;
        float3 localSampleDir = float3(localXY, localZ);

        float3 sampleDir = tangent * localSampleDir.x +
                           binormal * localSampleDir.y +
                           normal * localSampleDir.z;
        sampleDir = SafeNormalize(sampleDir, normal);

        float sampleDistance = lerp(0.15, g_sampleRadius, noise * noise);
        float3 targetViewPos = baseViewPos + sampleDir * sampleDistance;
        float2 sampleUV = ProjectViewPositionToUV(targetViewPos);

        if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 &&
            sampleUV.y >= 0.0 && sampleUV.y <= 1.0)
        {
            float sampleDepth = tex2Dlod(depthSampler, float4(sampleUV, 0, 0)).r;
            if (sampleDepth >= 0.99)
            {
                continue;
            }

            float3 sampleViewPos = ReconstructViewPosition(sampleUV, sampleDepth);
            float3 sampleNormal = tex2Dlod(normalSampler, float4(sampleUV, 0, 0)).rgb * 2.0 - 1.0;
            sampleNormal = SafeNormalize(sampleNormal, normal);

            float3 deltaToHit = sampleViewPos - baseViewPos;
            float positionError = length(sampleViewPos - targetViewPos);
            float depthToTarget = targetViewPos.z - sampleViewPos.z;
            float distanceWeight = saturate(1.0 - sampleDistance / g_sampleRadius);
            float targetMatchWeight = 1.0 / (1.0 + positionError * 4.0);
            float depthWeight = saturate((depthToTarget + g_depthCompareBias) * g_depthCompareFalloff);
            float normalWeight = saturate((1.0 - dot(normal, sampleNormal)) * 0.5);
            float hemisphereWeight = saturate(dot(sampleDir, SafeNormalize(deltaToHit, sampleDir)));

            float4 hitColor = tex2Dlod(textureSampler, float4(sampleUV, 0, 0));
            float sampleWeight = distanceWeight * targetMatchWeight * depthWeight * normalWeight * hemisphereWeight;

            accumulatedColor += hitColor * sampleWeight;
            accumulatedWeight += sampleWeight;
        }
    }

    float4 indirectColor = accumulatedColor / max(accumulatedWeight, 0.0001);
    workColor = lerp(workColor, indirectColor, saturate(g_indirectLightIntensity));

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
