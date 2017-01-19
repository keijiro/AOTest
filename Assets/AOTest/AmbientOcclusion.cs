using UnityEngine;

namespace AOTest
{
    [ExecuteInEditMode]
    [RequireComponent(typeof(Camera))]
    public class AmbientOcclusion : MonoBehaviour
    {
        [SerializeField]
        [Tooltip("The maximum distance of the horizon search. " +
                 "This value is also used for distance attenuation.")]
        float _radius = 1;

        [SerializeField]
        [Tooltip("The number of the horizon search slices. " + 
                 "This value affects the accuracy of the AO estimation.")]
        int _sliceCount = 4;

        [SerializeField]
        [Tooltip("The maximum number of samples in each horizon search slice. " +
                 "The total sample count is determined by (Slice Count) x (Samples Per Slice).")]
        int _samplesPerSlice = 8;

        [SerializeField, HideInInspector] Shader _shader;

        Material _material;

        void OnEnable()
        {
            _material = new Material(Shader.Find("Hidden/AOTest/Main"));
            _material.hideFlags = HideFlags.HideAndDontSave;
        }

        void OnValidate()
        {
            _radius = Mathf.Max(_radius, 1e-3f);
            _sliceCount = Mathf.Clamp(_sliceCount, 1, 64);
            _samplesPerSlice = Mathf.Clamp(_samplesPerSlice, 1, 128);
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
            _material.SetVector("_Radius", new Vector2(_radius, 1.0f / _radius));
            _material.SetVector("_Slices", new Vector2(_sliceCount, 1.0f / _sliceCount));
            _material.SetVector("_Samples", new Vector2(_samplesPerSlice, 1.0f / _samplesPerSlice));
            Graphics.Blit(source, destination, _material, 0);
        }
    }
}
