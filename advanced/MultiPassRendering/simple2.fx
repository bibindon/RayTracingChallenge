float4x4 g_matWorldViewProj;
float4 g_lightNormal = { 0.3f, 1.0f, 0.5f, 0.0f };
float3 g_ambient = { 0.3f, 0.3f, 0.3f };

bool g_bUseTexture = true;
float g_indirectLightIntensity = 0.5f;

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
    float3 normal = tex2D(normalSampler, inTexCood).rgb * 2.0 - 1.0;

    float2 pixelSize = float2(1.0 / 1600.0, 1.0 / 900.0);

    // Convert the view-space normal to screen-space motion.
    float2 marchDir = float2(normal.x, -normal.y);
    float dirLen = length(marchDir);
    if (dirLen > 0.0001)
    {
        marchDir = marchDir / dirLen;

        float4 accumulatedColor = workColor;
        float accumulatedWeight = 1.0;

        for (int i = 0; i < 32; ++i)
        {
            float noise = frac(sin(dot(inTexCood + float2(i * 0.123, i * 0.371),
                                       float2(12.9898, 78.233))) * 43758.5453);

            // Smaller values occur more often by squaring the random number.
            float rayLength = noise * noise * 200.0;
            float2 sampleUV = inTexCood + marchDir * pixelSize * rayLength;

            if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 &&
                sampleUV.y >= 0.0 && sampleUV.y <= 1.0)
            {
                float4 hitColor = tex2Dlod(textureSampler, float4(sampleUV, 0, 0));
                accumulatedColor += hitColor;
                accumulatedWeight += 1.0;
            }
        }

        float4 indirectColor = accumulatedColor / accumulatedWeight;
        workColor = lerp(workColor, indirectColor, saturate(g_indirectLightIntensity));
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
