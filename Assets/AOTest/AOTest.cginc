#include "UnityCG.cginc"

#define SOURCE_GBUFFER
#define VALIDATE_NORMALS

sampler2D _MainTex;
float4 _MainTex_TexelSize;

sampler2D _CameraGBufferTexture2;
sampler2D_float _CameraDepthTexture;
sampler2D _CameraDepthNormalsTexture;

// Trigonometric function utility
float2 CosSin(float theta)
{
    float sn, cs;
    sincos(theta, sn, cs);
    return float2(cs, sn);
}

// Pseudo random number generator with 2D coordinates
float UVRandom(float u, float v)
{
    float f = dot(float2(12.9898, 78.233), float2(u, v));
    return frac(43758.5453 * sin(f));
}

// Interleaved gradient function from Jimenez 2014 http://goo.gl/eomGso
float GradientNoise(float2 uv)
{
    uv = floor(uv * _ScreenParams.xy);
    float f = dot(float2(0.06711056f, 0.00583715f), uv);
    return frac(52.9829189f * frac(f));
}

// Boundary check for depth sampler
// (returns a very large value if it lies out of bounds)
float CheckBounds(float2 uv, float d)
{
    float ob = any(uv < 0) + any(uv > 1);
#if defined(UNITY_REVERSED_Z)
    ob += (d <= 0.00001);
#else
    ob += (d >= 0.99999);
#endif
    return ob * 1e8;
}

// Z buffer depth to linear 0-1 depth
float LinearizeDepth(float z)
{
    float isOrtho = unity_OrthoParams.w;
    float isPers = 1 - unity_OrthoParams.w;
    z *= _ZBufferParams.x;
    return (1 - isOrtho * z) / (isPers * z + _ZBufferParams.y);
}

// Depth/normal sampling functions
float SampleDepth(float2 uv)
{
#if defined(SOURCE_GBUFFER) || defined(SOURCE_DEPTH)
    float d = LinearizeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
#else
    float4 cdn = tex2D(_CameraDepthNormalsTexture, uv);
    float d = DecodeFloatRG(cdn.zw);
#endif
    return d * _ProjectionParams.z + CheckBounds(uv, d);
}

float3 SampleNormal(float2 uv)
{
#if defined(SOURCE_GBUFFER)
    float3 norm = tex2D(_CameraGBufferTexture2, uv).xyz;
    norm = norm * 2 - any(norm); // gets (0,0,0) when norm == 0
    norm = mul((float3x3)unity_WorldToCamera, norm);
#if defined(VALIDATE_NORMALS)
    norm = normalize(norm);
#endif
    return norm;
#else
    float4 cdn = tex2D(_CameraDepthNormalsTexture, uv);
    return DecodeViewNormalStereo(cdn) * float3(1, 1, -1);
#endif
}

float SampleDepthNormal(float2 uv, out float3 normal)
{
#if defined(SOURCE_GBUFFER) || defined(SOURCE_DEPTH)
    normal = SampleNormal(uv);
    return SampleDepth(uv);
#else
    float4 cdn = tex2D(_CameraDepthNormalsTexture, uv);
    normal = DecodeViewNormalStereo(cdn) * float3(1, 1, -1);
    float d = DecodeFloatRG(cdn.zw);
    return d * _ProjectionParams.z + CheckBounds(uv, d);
#endif
}

// Check if the camera is perspective.
// (returns 1.0 when orthographic)
float CheckPerspective(float x)
{
    return lerp(x, 1, unity_OrthoParams.w);
}

// Reconstruct view-space position from UV and depth.
// p11_22 = (unity_CameraProjection._11, unity_CameraProjection._22)
// p13_31 = (unity_CameraProjection._13, unity_CameraProjection._23)
float3 ReconstructViewPos(float2 uv, float depth, float2 p11_22, float2 p13_31)
{
    return float3((uv * 2 - 1 - p13_31) / p11_22 * CheckPerspective(depth), depth);
}

half4 frag(v2f_img input) : SV_Target
{
    const int kDiv1 = 20;
    const int kDiv2 = 5;

    // Parameters used in coordinate conversion
    float2 p11_22 = float2(unity_CameraProjection._11, unity_CameraProjection._22);
    float2 p13_31 = float2(unity_CameraProjection._13, unity_CameraProjection._23);

    float3 n0;
    float d0 = SampleDepthNormal(input.uv, n0);

    float3 p0 = ReconstructViewPos(input.uv, d0, p11_22, p13_31);

    float acc = 0;

    for (int i = 0; i < kDiv1; i++)
    {
        float phi = UVRandom(input.uv.x, input.uv.y + i) * UNITY_PI;
        float2 duv = _MainTex_TexelSize.xy * CosSin(phi) * 20;

        float2 uv1 = input.uv + duv;
        float2 uv2 = input.uv - duv;

        float h1 = 0;
        float h2 = 0;

        for (int j = 0; j < kDiv2; j++)
        {
            float z1 = SampleDepth(uv1);
            float z2 = SampleDepth(uv2);

            float3 d1 = ReconstructViewPos(uv1, z1, p11_22, p13_31) - p0;
            float3 d2 = ReconstructViewPos(uv2, z2, p11_22, p13_31) - p0;

            h1 = max(h1, -normalize(d1).z);
            h2 = max(h2, -normalize(d2).z);

            uv1 += duv;
            uv2 -= duv;
        }

        h1 = acos(h1);
        h2 = acos(h2);

        float3 sn = float3(CosSin(phi).yx * float2(1, 1), 0);
        float3 np = n0 - sn * dot(sn, n0);
        float cont = length(np);

        float n = acos(-normalize(np).z);

        acc +=
            0.25 * cont * (-cos(2 * h1 - n) + cos(n) + 2 * h1 * sin(n)) +
            0.25 * cont * (-cos(2 * h2 - n) + cos(n) + 2 * h2 * sin(n));
    }

    return 2 * acc / kDiv1 / UNITY_PI;
}
