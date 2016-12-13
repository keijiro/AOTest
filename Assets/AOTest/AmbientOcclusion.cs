using UnityEngine;
using UnityEngine.Rendering;

namespace AOTest
{
    [ExecuteInEditMode]
    [RequireComponent(typeof(Camera))]
    public class AmbientOcclusion : MonoBehaviour
    {
        [SerializeField] Shader _shader;

        Material _material;

        void OnEnable()
        {
            GetComponent<Camera>().depthTextureMode |= DepthTextureMode.DepthNormals;

            _material = new Material(Shader.Find("Hidden/AOTest/Main"));
            _material.hideFlags = HideFlags.HideAndDontSave;
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
            Graphics.Blit(source, destination, _material, 0);
        }
    }
}
