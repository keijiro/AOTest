Shader "Hidden/AOTest/Main"
{
    Properties
    {
        _MainTex("", 2D) = ""{}
    }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag
            #include "AOTest.cginc"
            ENDCG
        }
    }
}
