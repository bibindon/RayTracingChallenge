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

    float depth = tex2D(depthSampler, inTexCood).r;
    float3 normal = tex2D(normalSampler, inTexCood).rgb * 2.0 - 1.0;

    float2 pixelSize = float2(1.0 / 1600.0, 1.0 / 900.0);

    // Convert the view-space normal to screen-space motion.
    float2 marchDir = float2(normal.x, -normal.y);
    float dirLen = length(marchDir);

    marchDir = marchDir / dirLen;

    float rayLength = 100.0;
    float2 sampleUV = inTexCood + marchDir * pixelSize * rayLength;

    if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 &&
        sampleUV.y >= 0.0 && sampleUV.y <= 1.0)
    {
        float sampleDepth = tex2Dlod(depthSampler, float4(sampleUV, 0, 0)).r;
        float depthDiff = depth - sampleDepth;

        float4 hitColor = tex2Dlod(textureSampler, float4(sampleUV, 0, 0));
        workColor = lerp(workColor, hitColor, 0.25);
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
