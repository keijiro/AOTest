#include "UnityCG.cginc"

// Source image
sampler2D _MainTex;
float4 _MainTex_TexelSize;

// G Buffer reference
sampler2D _CameraGBufferTexture2;
sampler2D_float _CameraDepthTexture;
sampler2D _CameraDepthNormalsTexture;

#if !defined(SHADER_API_PSSL) && !defined(SHADER_API_XBOXONE)

// Use the standard sqrt as default.
float ao_sqrt(float x)
{
    return sqrt(x);
}

// Fast approximation of acos from Lagarde 2014 http://goo.gl/H9Qdom
float ao_acos(float x)
{
#if 0
    // Polynomial degree 2
    float ax = abs(x);
    float y = (1.56467 - 0.155972 * ax) * ao_sqrt(1 - ax);
    return x < 0 ? UNITY_PI - y : y;
#else
    // Polynomial degree 3
    float ax = abs(x);
    float y = ((0.0464619 * ax - 0.201877) * ax + 1.57018) * ao_sqrt(1 - ax);
    return x < 0 ? UNITY_PI - y : y;
#endif
}

#else

// On PS4 and Xbox One, use the optimized sqrt/acos functions
// from the original GTAO paper.

float ao_sqrt(float x)
{
    return asfloat(0x1FBD1DF5 + (asint(x) >> 1));
}

float ao_acos(float x)
{
    float y = -0.156583 * abs(x) + UNITY_PI / 2;
    y *= ao_sqrt(1 - abs(x));
    return x < 0 ? UNITY_PI - y : y;
}

#endif

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
    float d = LinearizeDepth(tex2Dlod(_CameraDepthTexture, float4(uv, 0, 0)).r);
#else
    float4 cdn = tex2Dlod(_CameraDepthNormalsTexture, float4(uv, 0, 0));
    float d = DecodeFloatRG(cdn.zw);
#endif
    return d * _ProjectionParams.z + CheckBounds(uv, d);
}

float3 SampleNormal(float2 uv)
{
#if defined(SOURCE_GBUFFER)
    float3 norm = tex2Dlod(_CameraGBufferTexture2, float4(uv, 0, 0)).xyz;
    norm = norm * 2 - any(norm); // gets (0,0,0) when norm == 0
    norm = mul((float3x3)unity_WorldToCamera, norm);
#if defined(VALIDATE_NORMALS)
    norm = normalize(norm);
#endif
    return norm;
#else
    float4 cdn = tex2Dlod(_CameraDepthNormalsTexture, float4(uv, 0, 0));
    return DecodeViewNormalStereo(cdn) * float3(1, 1, -1);
#endif
}

float SampleDepthNormal(float2 uv, out float3 normal)
{
#if defined(SOURCE_GBUFFER) || defined(SOURCE_DEPTH)
    normal = SampleNormal(uv);
    return SampleDepth(uv);
#else
    float4 cdn = tex2Dlod(_CameraDepthNormalsTexture, float4(uv, 0, 0));
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
