texture texture1;
sampler textureSampler = sampler_state
{
    Texture = (texture1);
    MipFilter = NONE;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
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

    float4 color =
        tex2D(textureSampler, inTexCood + pixelSize * float2(-1.0, -1.0)) * (1.0 / 16.0) +
        tex2D(textureSampler, inTexCood + pixelSize * float2( 0.0, -1.0)) * (2.0 / 16.0) +
        tex2D(textureSampler, inTexCood + pixelSize * float2( 1.0, -1.0)) * (1.0 / 16.0) +
        tex2D(textureSampler, inTexCood + pixelSize * float2(-1.0,  0.0)) * (2.0 / 16.0) +
        tex2D(textureSampler, inTexCood)                                  * (4.0 / 16.0) +
        tex2D(textureSampler, inTexCood + pixelSize * float2( 1.0,  0.0)) * (2.0 / 16.0) +
        tex2D(textureSampler, inTexCood + pixelSize * float2(-1.0,  1.0)) * (1.0 / 16.0) +
        tex2D(textureSampler, inTexCood + pixelSize * float2( 0.0,  1.0)) * (2.0 / 16.0) +
        tex2D(textureSampler, inTexCood + pixelSize * float2( 1.0,  1.0)) * (1.0 / 16.0);

    outColor = color;
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
