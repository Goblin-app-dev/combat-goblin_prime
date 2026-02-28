# ASR Model Assets — Phase 12C

Offline speech-to-text model files for `OfflineSpeechToTextEngine`.

## Model

Offline transducer ASR model compatible with `sherpa_onnx` `OfflineRecognizer`.
Recommended: `sherpa-onnx-zipformer-en-2023-06-26` or equivalent English transducer model.

## Required files

Place the following files in this directory before building:

| File | Source |
|------|--------|
| `encoder.onnx` | From model release archive |
| `decoder.onnx` | From model release archive |
| `joiner.onnx` | From model release archive |
| `tokens.txt` | From model release archive |

## Notes

- All files are bundled as Flutter assets and extracted to the app documents directory on first launch.
- The model runs entirely on-device via `sherpa_onnx` (no network required).
- Extraction happens lazily on the first `transcribe()` call.
- `OfflineSpeechToTextEngine` uses 2 CPU threads by default; configurable in Phase 12D.
- On iOS, the FFI bridge requires a physical device; simulator is unsupported.
- Context hints (faction names, unit keys, weapon keys) are passed to the engine but the offline transducer model does not currently use them for rescoring. Phase 12D may add an n-gram rescorer for domain vocabulary bias.
