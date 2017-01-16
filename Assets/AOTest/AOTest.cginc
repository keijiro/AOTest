#include "UnityCG.cginc"

#define SOURCE_GBUFFER
#define VALIDATE_NORMALS

sampler2D _MainTex;
float4 _MainTex_TexelSize;

sampler2D _CameraGBufferTexture2;
sampler2D_float _CameraDepthTexture;
sampler2D _CameraDepthNormalsTexture;

half _AttenRadius;

// Trigonometric function utility
float2 CosSin(float theta)
{
    float sn, cs;
    sincos(theta, sn, cs);
    return float2(cs, sn);
}

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

half4 frag(v2f_img input) : SV_Target
{
    const int kDirections = 4;
    const int kSearch = 32;

    // Parameters used in coordinate conversion.
    float2 p11_22 = float2(unity_CameraProjection._11, unity_CameraProjection._22);
    float2 p13_31 = float2(unity_CameraProjection._13, unity_CameraProjection._23);

    // Center sample.
    float3 n0;
    float d0 = SampleDepthNormal(input.uv, n0);

    // Early rejection FIXME: this is not a correct way.
    if (d0 > 100) return 1;

    // p0: View space position of the center sample.
    // v0: Normalized view vector.
    float3 p0 = ReconstructViewPos(input.uv, d0, p11_22, p13_31);
    float3 v0 = normalize(-p0);

    // Visibility accumulation.
    float vis = 0;

    UNITY_LOOP for (int i = 0; i < kDirections; i++)
    {
        // Sampling direction.
        float phi = (GradientNoise(input.uv) + i) * UNITY_PI / kDirections;
        float2 duv = _MainTex_TexelSize.xy * CosSin(phi) * 1.5;

        // Start from one step further.
        float2 uv1 = input.uv + duv;
        float2 uv2 = input.uv - duv;

        // Cosine of horizons.
        float h1 = -1;
        float h2 = -1;

        for (int j = 0; j < kSearch; j++)
        {
            // Sample the depths.
            float z1 = SampleDepth(uv1);
            float z2 = SampleDepth(uv2);

            // View space difference from the center point.
            float3 d1 = ReconstructViewPos(uv1, z1, p11_22, p13_31) - p0;
            float3 d2 = ReconstructViewPos(uv2, z2, p11_22, p13_31) - p0;
            float l_d1 = length(d1);
            float l_d2 = length(d2);

            // Distance based attenuation.
            half atten1 = saturate(l_d1 * 2 / _AttenRadius - 1);
            half atten2 = saturate(l_d2 * 2 / _AttenRadius - 1);

            // Calculate the cosine and compare with the horizons.
            h1 = max(h1, lerp(dot(d1, v0) / l_d1, -1, atten1));
            h2 = max(h2, lerp(dot(d2, v0) / l_d2, -1, atten2));

            uv1 += duv;
            uv2 -= duv;
        }

        // Convert the horizons into angles between the view vector.
        h1 = -ao_acos(h1);
        h2 = +ao_acos(h2);

        // Project the normal vector onto the sampling slice plane.
        float3 dv = float3(CosSin(phi), 0);
        float3 sn = normalize(cross(v0, dv));
        float3 np = n0 - sn * dot(sn, n0);

        // Calculate the angle between the projected normal and the view vector.
        float n = ao_acos(min(dot(np, v0) / length(np), 1));
        if (dot(np, dv) > 0) n = -n;

        // Clamp the horizon angles with the normal hemisphere.
        h1 = n + max(h1 - n, -0.5 * UNITY_PI);
        h2 = n + min(h2 - n,  0.5 * UNITY_PI);

        // Cosine weighting GTAO integrator.
        float2 cossin_n = CosSin(n);
        float a1 = -cos(2 * h1 - n) + cossin_n.x + 2 * h1 * cossin_n.y;
        float a2 = -cos(2 * h2 - n) + cossin_n.x + 2 * h2 * cossin_n.y;
        vis += (a1 + a2) / 4 * length(np);
    }

    return vis / kDirections;
}
