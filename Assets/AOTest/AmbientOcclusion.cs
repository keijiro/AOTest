using UnityEngine;
using UnityEngine.Rendering;

namespace AOTest
{
    [ExecuteInEditMode]
    [RequireComponent(typeof(Camera))]
    public class AmbientOcclusion : MonoBehaviour
    {
        [SerializeField] float _searchRadius = 1;
        [SerializeField] int _slicePerPixel = 4;
        [SerializeField] int _samplePerSlice = 18;

        [SerializeField, HideInInspector] Shader _shader;

        Material _material;

        void OnEnable()
        {
            _material = new Material(Shader.Find("Hidden/AOTest/Main"));
            _material.hideFlags = HideFlags.HideAndDontSave;
        }

        void OnValidate()
        {
            _searchRadius = Mathf.Max(_searchRadius, 1e-3f);
            _slicePerPixel = Mathf.Clamp(_slicePerPixel, 1, 64);
            _samplePerSlice = Mathf.Clamp(_samplePerSlice, 1, 128);
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
            _material.SetVector("_SearchRadius", new Vector2(_searchRadius, 1.0f / _searchRadius));
            _material.SetVector("_SlicePerPixel", new Vector2(_slicePerPixel, 1.0f / _slicePerPixel));
            _material.SetVector("_SamplePerSlice", new Vector2(_samplePerSlice, 1.0f / _samplePerSlice));
            Graphics.Blit(source, destination, _material, 0);
        }
    }
}
