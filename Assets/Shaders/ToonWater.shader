Shader "Mistwork/Toon Water"
{
    Properties
    {
        [Header(Water Colors)]
        _WaterSurfaceColor("Water Surface Color", Color) = (1, 1, 1, 1)
        _WaterDeepColor("Water Deep Color", Color) = (1, 1, 1, 1)
        _WaterShoreColor("Water Shore Color", Color) = (1, 1, 1, 1)
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0

        [Header(Water Normal Map)]
        [Normal]_NormalTex("Normal Texture", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(0, 1)) = 0
        _NormalSpeed("Normal Speed", Vector) = (0, 0, 0, 0)
        
        [Header(World Reflection)]
        _WorldReflectionStrength("Reflection Strength", Range(0, 1)) = 0

        [Header(Thresholds)]
        _NearShoreThreshold("Near Shore Threshold", Float) = 0
        _DeepThreshold("Deep Threshold", Float) = 0
        
        [Header(Refraction)]
        _DistortionTex("Distortion Texture", 2D) = "bump" {}
        _DistortionAmount("Distortion Amount", Float) = 0
        _DistortionSpeed("Distortion Speed", Vector) = (0.1, 0.1, 0, 0)

        [Header(Displacement)]
        _DisplacementTex("Displacement Texture", 2D) = "white" {}
        _DisplacementAmount("Displacement Amount", Float) = 0
        _DisplacementSpeed("Displacement Speed", Vector) = (0.1, 0.1, 0, 0)

        [Header(Foam)]
        _FoamTex("Foam Texture", 2D) = "white" {}
        _FoamCutoff("Foam Cutoff", Range(0, 1)) = 0.777
        _FoamSpeed("Foam Speed", Vector) = (0, 0, 0, 0)
        _FoamDistance("Foam Distance", Float) = 0.4
        _FoamDistortionTex("Foam Distortion", 2D) = "white" {}
        _FoamDistortionAmount("Foam Distortion Amount", Range(0, 1)) = 0.27
        
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent"}
        Cull Off
        ZWrite Off
        LOD 200

        //Get grab pass information and store into _GrabTexture
        GrabPass
        {
            "_GrabTexture"
        }

        CGPROGRAM
        #pragma surface surf Standard vertex:vert fullforwardshadows
        #pragma target 4.0
        

        sampler2D _DisplacementTex;
        float4 _DisplacementTex_ST;

        struct Input
        {
            float2 uv_NormalTex;
            float2 uv_DistortionTex;
            float2 uv_FoamTex;
            float2 uv_FoamDistortionTex;
            float4 grabPassUV;
            float4 screenPos;
            float3 worldPos;
        };

        sampler2D _FoamTex;
        sampler2D _FoamDistortionTex;
        float _FoamDistortionAmount;
        sampler2D _NormalTex;
        sampler2D _DistortionTex;
        
        float4 _WaterSurfaceColor;
        float4 _WaterShoreColor;
        float4 _WaterDeepColor;
        float _WorldReflectionStrength;

        float _NearShoreThreshold;
        float _DeepThreshold;

        float _NormalStrength;
        float2 _NormalSpeed;
        float _DistortionAmount;
        float2 _DistortionSpeed;
        float _DisplacementAmount;
        float2 _DisplacementSpeed;

        float _FoamCutoff;
        float2 _FoamSpeed;
        float _FoamDistance;

        float _MainAlpha;
        half _Glossiness;
        half _Metallic;

        //Global camera depth texture
        sampler2D _CameraDepthTexture;
        sampler2D _GrabTexture;
        //Global reflection texture coming from "SurfaceReflection" script
        uniform sampler2D _WorldReflectionTex;
        

        UNITY_INSTANCING_BUFFER_START(Props)
        UNITY_INSTANCING_BUFFER_END(Props)

        void vert(inout appdata_full v, out Input o)
        {
            UNITY_INITIALIZE_OUTPUT(Input,o);
            float4 clipSpacePos = UnityObjectToClipPos(v.vertex);
            o.grabPassUV = ComputeScreenPos(clipSpacePos);

            //Sample displacement texture
            float4 displacementTex = tex2Dlod(_DisplacementTex, float4(v.texcoord.xy * _DisplacementTex_ST + _Time.y * _DisplacementSpeed, 0, 0));
            //Generate waves movies vertices y values along the displacement texture y value. Use _DisplacementAmount to adjust the height of the waves.
            v.vertex.y += displacementTex.y * _DisplacementAmount;
        }

        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            //#### DEPTH BASED WATER COLORS ####
            //Sample camera depth texture depth values
            float depthNonLinear = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(IN.screenPos));
            //Convert camera depth texture depth values to be linear
            float depthLinear = LinearEyeDepth(depthNonLinear);
            //Get depth values relative to the water surface (water surface depth is stored in w component of IN.screenPos)
            float depthFromSurface = depthLinear - IN.screenPos.w;
            //Compare depth values to _DeepThreshold, percentage-wise
            float deepDistBasedDepth = saturate(depthFromSurface / _DeepThreshold);
            //Compare depth values to _NearShoreThreshold, percentage-wise
            float shoreDistBasedDepth = saturate(depthFromSurface / _NearShoreThreshold);
            //Use two lerp functions to interpolate between the three colors of the water based on their depth values
            float4 waterColor = lerp(lerp(_WaterShoreColor, _WaterSurfaceColor, shoreDistBasedDepth), _WaterDeepColor, deepDistBasedDepth);

            //Normal Map to make water surface curlier
            float3 normalTex = UnpackNormalWithScale(tex2D(_NormalTex, IN.uv_NormalTex + _Time.y * _NormalSpeed), _NormalStrength); 
            
            //#### FAKE REFRACTION ####
            //Sample the values of a normal map and animate its UVs 
            float3 distortionTex = UnpackNormal(tex2D(_DistortionTex, IN.uv_DistortionTex + _Time.y * _DistortionSpeed));
            //Adjust the amount of refraction distortion
            distortionTex.xy *= _DistortionAmount;
            //Use the the sampled normal map values to distort grabTex UVs to simulate water refraction distortion
            IN.grabPassUV.xy += distortionTex.xy * IN.grabPassUV.z;
            //Sample the grab-pass texture so we can look through the water surface
            float4 grabTex = tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(IN.grabPassUV));

            //#### PLANAR REFLECTION ####
            //Sample the global texture coming from SurfaceReflection. It containes skybox and environment reflections
            float4 worldReflTex = tex2Dproj(_WorldReflectionTex, UNITY_PROJ_COORD(IN.grabPassUV));
            
            //#### FOAM ####
            //Compute the foam presence near the shoreline (distance based)
            float foamDistBasedDepth = saturate(depthFromSurface / _FoamDistance);
            //Adjust the foam presence near the shoreline using _FoamCutoff property
            float foamCutOff = foamDistBasedDepth * _FoamCutoff;
            //Sample foam distortion texture. Makes the foam to look more cartoony
            float2 foamDistortTex = (tex2D(_FoamDistortionTex, IN.uv_FoamDistortionTex).xy * 2 - 1) * _FoamDistortionAmount;
            //Adds animation to the foam
            float2 foamUV = float2((IN.uv_FoamTex.x + _Time.y * _FoamSpeed.x) + foamDistortTex.x, (IN.uv_FoamTex.y + _Time.y * _FoamSpeed.y) + foamDistortTex.y);
            //Sample the foam texture
            float foamTex = tex2D(_FoamTex, foamUV).r;
            //Adjust foam presence on water surface based on _FoamCutoff property 
            float foam = foamTex > foamCutOff ? 1 : 0;
            //Compute the final pixel color by applying the water colors and the grabTex and then adding foam
            float4 c = waterColor * grabTex + foam;
            
            //Render
            o.Albedo = c.rgb;

            o.Metallic = _Metallic;
            o.Smoothness = _Glossiness;
            o.Alpha = _MainAlpha;
            //Apply planar reflection
            o.Emission = worldReflTex * _WorldReflectionStrength;
            o.Normal = normalTex;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
