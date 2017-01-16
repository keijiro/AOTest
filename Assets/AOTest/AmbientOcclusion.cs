using UnityEngine;
using UnityEngine.Rendering;

namespace AOTest
{
    [ExecuteInEditMode]
    [RequireComponent(typeof(Camera))]
    public class AmbientOcclusion : MonoBehaviour
    {
        [SerializeField] float _attenuationRadius = 2;

        [SerializeField, HideInInspector] Shader _shader;

        Material _material;

        void OnEnable()
        {
            GetComponent<Camera>().depthTextureMode |= DepthTextureMode.DepthNormals;

            _material = new Material(Shader.Find("Hidden/AOTest/Main"));
            _material.hideFlags = HideFlags.HideAndDontSave;
        }

        void OnValidate()
        {
            _attenuationRadius = Mathf.Max(_attenuationRadius, 1e-4f);
        }

        void OnDestroy()
        {
            if (Application.isPlaying)
                Destroy(_material);
            else
                DestroyImmediate(_material);
        }

        [ImageEffectOpaque]
        void OnRenderImage(RenderTexture source, RenderTexture destination)
        {
            _material.SetFloat("_AttenRadius", _attenuationRadius);
            Graphics.Blit(source, destination, _material, 0);
        }
    }
}
