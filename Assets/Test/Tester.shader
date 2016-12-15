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

    half4 frag(v2f_img input) : SV_Target
    {
        float c_i = saturate(tex2D(_MainTex, input.uv).r);
        float c_r = saturate(tex2D(_RefTex, input.uv).r);
        #if defined(_DIFF_MODE)
        return saturate(c_r - c_i) + float4(saturate(c_i - c_r), 0, 0, 0);
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
