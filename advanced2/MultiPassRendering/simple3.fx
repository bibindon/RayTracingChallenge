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

float g_exposure = 1.0f;

float3 ToneMapACES(float3 color)
{
    color *= g_exposure;
    color = max(color, 0.0);
    return saturate((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14));
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
    float3 mappedColor = ToneMapACES(hdrColor.rgb);
    mappedColor = pow(mappedColor, 1.0 / 2.2);
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
