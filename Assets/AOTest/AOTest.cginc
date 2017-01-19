#define SOURCE_GBUFFER
#define VALIDATE_NORMALS

#include "Common.cginc"

// Parameters given from the script consisting of (value, 1/value).
half2 _Radius;
half2 _Slices;
half2 _Samples;

half4 frag(v2f_img input) : SV_Target
{
    // Center sample.
    float3 n0;
    float d0 = SampleDepthNormal(input.uv, n0);

    // Early Z rejection.
    if (d0 >= _ProjectionParams.z * 0.999) return 1;

    // Parameters used for inverse projection.
    float2 p11_22 = float2(unity_CameraProjection._11, unity_CameraProjection._22);
    float2 p13_31 = float2(unity_CameraProjection._13, unity_CameraProjection._23);

    // p0: View space position of the center sample.
    // v0: Normalized view vector.
    float3 p0 = ReconstructViewPos(input.uv, d0, p11_22, p13_31);
    float3 v0 = normalize(-p0);

    // Screen space search radius. Up to 1/4 screen width.
    float radius = _Radius.x * unity_CameraProjection._11 * 0.5 / p0.z;
    radius = min(radius, 0.25) * _MainTex_TexelSize.z;

    // Step width (interval between samples).
    float stepw = max(1.5, radius * _Samples.y);

    // Interleaved gradient noise (used for dithering).
    half dither = GradientNoise(input.uv);

    // AO value wll be accumulated into here.
    float ao = 0;

    // Slice loop
    UNITY_LOOP for (half sl01 = _Slices.y * 0.5; sl01 < 1; sl01 += _Slices.y)
    {
        // Slice plane angle and sampling direction.
        half phi = (sl01 + dither) * UNITY_PI;
        half2 cossin_phi = CosSin(phi);
        float2 duv = _MainTex_TexelSize.xy * cossin_phi * stepw;

        // Start from one step further.
        float2 uv1 = input.uv + duv * (0.5 + sl01);
        float2 uv2 = input.uv - duv * (0.5 + sl01);

        // Determine the horizons.
        float h1 = -1;
        float h2 = -1;

        UNITY_LOOP for (half hr = stepw * 0.5; hr < radius; hr += stepw)
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
            half atten1 = saturate(l_d1 * 2 * _Radius.y - 1);
            half atten2 = saturate(l_d2 * 2 * _Radius.y - 1);

            // Calculate the cosine and compare with the horizons.
            h1 = max(h1, lerp(dot(d1, v0) / l_d1, -1, atten1));
            h2 = max(h2, lerp(dot(d2, v0) / l_d2, -1, atten2));

            uv1 += duv;
            uv2 -= duv;
        }

        // Convert the horizons into angles between the view vector.
        h1 = -ao_acos(h1);
        h2 = +ao_acos(h2);

        // Project the normal vector onto the slice plane.
        float3 dv = float3(cossin_phi, 0);
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
        ao += (a1 + a2) / 4 * length(np);
    }

    return ao * _Slices.y;
}
