bool g_bEnableRayTracing = true;

// 間接光として元の色にどれだけ混ぜるか。
float g_indirectLightIntensity = 0.40f;

// スクリーンスペース上で探索する最大距離。
float g_sampleRadius = 45.0f;

// 遠いサンプルほど寄与を減らすための係数。
float g_distanceFalloffStrength = 0.25f;

// 理想サンプル位置と実際のヒット位置のずれに対する減衰係数。
float g_targetMatchStrength = 0.35f;

// 深度比較時に少しだけ手前側を優遇するためのバイアス。
float g_depthCompareBias = 0.05f;

// 深度差に対する重みの変化量。
float g_depthCompareFalloff = 4.0f;

// 射影行列と逆射影行列。
// 深度からビュー空間位置を復元したり、
// ビュー空間上のサンプル点をスクリーンへ戻したりするために使う。
float4x4 g_matProj;
float4x4 g_matProjInv;

texture texture1;
sampler textureSampler = sampler_state {
    // ベースとなる色バッファ。
    Texture = (texture1);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture texture2;
sampler depthSampler = sampler_state {
    // 1パス目で書き出した深度バッファ。
    Texture = (texture2);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture texture3;
sampler normalSampler = sampler_state {
    // 1パス目で書き出した法線バッファ。
    Texture = (texture3);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

texture texture4;
sampler tangentSampler = sampler_state {
    // 1パス目で書き出した接線バッファ。
    Texture = (texture4);
    MipFilter = NONE;
    MinFilter = POINT;
    MagFilter = POINT;
};

float3 SafeNormalize(float3 value, float3 fallbackValue)
{
    // 長さがほぼゼロのベクトルを正規化すると不安定になるので、
    // その場合は安全な既定値を返す。
    float lenSq = dot(value, value);
    if (lenSq <= 0.0001)
    {
        return fallbackValue;
    }

    return value * rsqrt(lenSq);
}

float3 ReconstructViewPosition(float2 uv, float depth)
{
    // スクリーンUVを NDC に戻す。
    float2 ndc = uv * 2.0 - 1.0;
    ndc.y = -ndc.y;

    // 深度と合わせてクリップ空間位置を組み立て、
    // 逆射影行列でビュー空間位置へ戻す。
    float4 clipPos = float4(ndc, depth, 1.0);
    float4 viewPos = mul(clipPos, g_matProjInv);

    // 同次座標から 3D 座標へ戻して返す。
    return viewPos.xyz / max(viewPos.w, 0.0001);
}

float2 ProjectViewPositionToUV(float3 viewPos)
{
    // ビュー空間の点をクリップ空間へ投影する。
    float4 clipPos = mul(float4(viewPos, 1.0), g_matProj);

    // NDC に変換する。
    float2 ndc = clipPos.xy / max(clipPos.w, 0.0001);

    // 0..1 の UV に戻す。
    float2 uv = ndc * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;
    return uv;
}

void BuildBasis(float3 normal, float3 tangentInput, out float3 tangent, out float3 binormal)
{
    // 入力接線から法線方向の成分を落として、
    // 法線に直交する接線を作る。
    tangent = tangentInput - normal * dot(tangentInput, normal);
    tangent = SafeNormalize(tangent, float3(1.0, 0.0, 0.0));

    // 接線が法線とほぼ平行だと基底が壊れるので、
    // 別の up ベクトルから作り直す。
    if (abs(dot(tangent, normal)) > 0.999)
    {
        float3 up = float3(1.0, 0.0, 0.0);
        if (abs(normal.y) < 0.999)
        {
            up = float3(0.0, 1.0, 0.0);
        }
        tangent = SafeNormalize(cross(up, normal), float3(1.0, 0.0, 0.0));
    }

    // 従法線と接線を整えて、直交基底を完成させる。
    binormal = SafeNormalize(cross(normal, tangent), float3(0.0, 1.0, 0.0));
    tangent = SafeNormalize(cross(binormal, normal), tangent);
}


void VertexShader1(in  float4 inPosition  : POSITION,
                   in  float2 inTexCood   : TEXCOORD0,
                   out float4 outPosition : POSITION,
                   out float2 outTexCood  : TEXCOORD0)
{
    // フルスクリーンクアッドなので、頂点位置と UV をそのまま流すだけ。
    outPosition = inPosition;
    outTexCood = inTexCood;
}

void PixelShader1(in float4 inPosition    : POSITION,
                  in float2 inTexCood     : TEXCOORD0,
                  out float4 outColor     : COLOR)
{
    // DX9 のフルスクリーンクアッドに合わせて半ピクセル補正を入れる。
    float2 pixelSize = float2(1.0 / 1600.0, 1.0 / 900.0);
    inTexCood += pixelSize * 0.5f;

    // 現在ピクセルの G-buffer 情報を取得する。
    float4 workColor = tex2D(textureSampler, inTexCood);
    float depth = tex2D(depthSampler, inTexCood).r;
    float3 normal = tex2D(normalSampler, inTexCood).rgb * 2.0 - 1.0;
    float3 tangentInput = tex2D(tangentSampler, inTexCood).rgb * 2.0 - 1.0;

    // 法線が壊れていても最低限動くように安全に正規化する。
    normal = SafeNormalize(normal, float3(0.0, 0.0, -1.0));

    // 無効ピクセルや背景はそのまま返す。
    if (!g_bEnableRayTracing || depth >= 0.99)
    {
        outColor = workColor;
        return;
    }

    // 現在ピクセルの接線空間基底を構築する。
    float3 tangent;
    float3 binormal;
    BuildBasis(normal, tangentInput, tangent, binormal);

    // 現在ピクセルのビュー空間位置。
    float3 baseViewPos = ReconstructViewPosition(inTexCood, depth);

    // 元の色を基準として、見つかったヒット色を加算していく。
    float4 accumulatedColor = workColor;
    float accumulatedWeight = 1.0;

    for (int i = 0; i < 32; ++i)
    {
        // 疑似乱数から半球サンプルの角度と半径を決める。
        float noise = frac(sin(dot(inTexCood + float2(i * 0.123, i * 0.371),
                                   float2(12.9898, 78.233))) * 43758.5453);
        float angleNoise = frac(sin(dot(inTexCood + float2(i * 0.719, i * 0.183),
                                        float2(39.3468, 11.1351))) * 24634.6345);

        // 接線空間上の半球サンプル方向を作る。
        float radiusNoise = sqrt(noise);
        float phi = angleNoise * 6.2831853;
        float localZ = sqrt(saturate(1.0 - noise));
        float2 localXY = float2(cos(phi), sin(phi)) * radiusNoise;
        float3 localSampleDir = float3(localXY, localZ);

        // 接線空間からビュー空間へ回転する。
        float3 sampleDir = tangent * localSampleDir.x +
                           binormal * localSampleDir.y +
                           normal * localSampleDir.z;
        sampleDir = SafeNormalize(sampleDir, normal);

        // サンプル距離を決めて、理想的なサンプル先をビュー空間上に置く。
        float sampleDistance = lerp(0.15, g_sampleRadius, noise * noise);
        float3 targetViewPos = baseViewPos + sampleDir * sampleDistance;

        // その理想点が画面のどこに見えるかを求める。
        float2 sampleUV = ProjectViewPositionToUV(targetViewPos);

        // 画面内にあるサンプルだけ処理する。
        if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 &&
            sampleUV.y >= 0.0 && sampleUV.y <= 1.0)
        {
            // その画面位置に実際に見えている深度を読む。
            float sampleDepth = tex2Dlod(depthSampler, float4(sampleUV, 0, 0)).r;
            if (sampleDepth >= 0.99)
            {
                // 背景ならヒットなし扱い。
                continue;
            }

            // 実際のヒット点の位置と法線を復元する。
            float3 sampleViewPos = ReconstructViewPosition(sampleUV, sampleDepth);
            float3 sampleNormal = tex2Dlod(normalSampler, float4(sampleUV, 0, 0)).rgb * 2.0 - 1.0;
            sampleNormal = SafeNormalize(sampleNormal, normal);

            // 基準点からヒット点までの情報を作る。
            float3 deltaToHit = sampleViewPos - baseViewPos;
            float positionError = length(sampleViewPos - targetViewPos);
            float depthToTarget = targetViewPos.z - sampleViewPos.z;
            float normalizedDistance = sampleDistance / max(g_sampleRadius, 0.0001);

            // 遠いサンプルほど寄与を下げる。
            float distanceWeight = saturate(1.0 - normalizedDistance * g_distanceFalloffStrength);

            // 理想位置からずれているヒットほど寄与を下げる。
            float targetMatchWeight = 1.0 / (1.0 + positionError * g_targetMatchStrength);

            // 実ヒットが理想サンプル位置より手前にあるほど寄与を上げる。
            float depthWeight = saturate((depthToTarget + g_depthCompareBias) * g_depthCompareFalloff);

            // 同一面の自己ヒットを減らすため、法線が似すぎているものは寄与を抑える。
            float normalAlignment = dot(normal, sampleNormal);
            float normalWeight = saturate(0.2 + 0.8 * ((1.0 - normalAlignment) * 0.5));
            if (normalAlignment > 0.95)
            {
                normalWeight = 0.0;
            }

            // 半球外からの不自然なヒットは寄与を落とす。
            float hemisphereWeight = saturate(0.35 + 0.65 * dot(sampleDir, SafeNormalize(deltaToHit, sampleDir)));

            // ヒット位置の色を読み、重み付きで蓄積する。
            float4 hitColor = tex2Dlod(textureSampler, float4(sampleUV, 0, 0));
            float sampleWeight = distanceWeight * targetMatchWeight * depthWeight * normalWeight * hemisphereWeight;

            // 条件の良いヒットほど強く混ぜて、簡易的な間接光として使う。
            accumulatedColor += hitColor * sampleWeight;
            accumulatedWeight += sampleWeight;
        }
    }

    // 集めた色を正規化する。
    float4 indirectColor = accumulatedColor / max(accumulatedWeight, 0.0001);

    // 元の色と間接光をブレンドする。
    workColor = lerp(workColor, indirectColor, saturate(g_indirectLightIntensity));

    outColor = workColor;
}

technique Technique1
{
    pass Pass1
    {
        // フルスクリーンクアッド描画なのでカリング不要。
        CullMode = NONE;

        VertexShader = compile vs_3_0 VertexShader1();
        PixelShader = compile ps_3_0 PixelShader1();
   }
}
