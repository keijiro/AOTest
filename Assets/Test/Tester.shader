Shader "Hidden/AOTest/Tester"
{
    Properties
    {
        _MainTex("", 2D) = ""{}
        _RefTex("", 2D) = ""{}
    }
    CGINCLUDE

    #include "UnityCG.cginc"

    sampler2D _MainTex;
    sampler2D _RefTex;

    float _Mix;

    half3 HueToRGB(half h)
    {
        h = frac(h);
        half r = abs(h * 6 - 3) - 1;
        half g = 2 - abs(h * 6 - 2);
        half b = 2 - abs(h * 6 - 4);
        half3 rgb = saturate(half3(r, g, b));
        return GammaToLinearSpace(rgb);
    }

    half4 frag(v2f_img input) : SV_Target
    {
        float c_i = saturate(tex2D(_MainTex, input.uv).r);
        float c_r = saturate(tex2D(_RefTex, input.uv).r);
        #if defined(_DIFF_MODE)
        float diff = abs(1 - c_i / c_r);
        return half4(HueToRGB(diff) * saturate(diff * 10), 1);
        #else
        return lerp(c_i, c_r, _Mix);
        #endif
    }

    ENDCG
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass
        {
            CGPROGRAM
            #pragma multi_compile _ _DIFF_MODE
            #pragma vertex vert_img
            #pragma fragment frag
            #pragma target 3.0
            ENDCG
        }
    }
}
