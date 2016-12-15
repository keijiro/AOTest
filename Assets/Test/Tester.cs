using UnityEngine;
using UnityEngine.Rendering;

namespace AOTest
{
    [ExecuteInEditMode]
    [RequireComponent(typeof(Camera))]
    public class Tester : MonoBehaviour
    {
        [SerializeField] Texture2D _referenceImage;
        [SerializeField, Range(0, 1)] float _mix;
        [SerializeField] bool _showDifference;

        [SerializeField, HideInInspector] Shader _shader;

        Material _material;

        void OnEnable()
        {
            _material = new Material(Shader.Find("Hidden/AOTest/Tester"));
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
            _material.SetTexture("_RefTex", _referenceImage);
            _material.SetFloat("_Mix", _mix);

            if (_showDifference)
                _material.EnableKeyword("_DIFF_MODE");
            else
                _material.DisableKeyword("_DIFF_MODE");

            Graphics.Blit(source, destination, _material, 0);
        }
    }
}
