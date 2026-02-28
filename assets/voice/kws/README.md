# KWS Model Assets — Phase 12C

Keyword spotting model files for `PlatformWakeWordDetector`.

## Model

`sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`
(zipformer transducer, ~3.3M parameters, 16 kHz input)

## Required files

Place the following files in this directory before building:

| File | Source |
|------|--------|
| `encoder.onnx` | From model release archive |
| `decoder.onnx` | From model release archive |
| `joiner.onnx` | From model release archive |
| `tokens.txt` | From model release archive |
| `keywords.txt` | Generated via sentencepiece (see below) |

## Generating keywords.txt

Keywords must use the model's BPE token vocabulary, not CMU phonemes.

```bash
# Install sentencepiece
pip install sentencepiece

# Encode "hey goblin" using the model's bpe.model
echo "hey goblin" | spm_encode --model=bpe.model --output_format=piece
# Example output: ▁HEY ▁GOB LIN

# Write to keywords.txt (one keyword phrase per line)
echo "▁HEY ▁GOB LIN" > keywords.txt
```

Each line in `keywords.txt` is one keyword phrase expressed as space-separated BPE tokens.

## Notes

- All files are bundled as Flutter assets and extracted to the app documents directory on first launch.
- The model runs entirely on-device via `sherpa_onnx` (no network required).
- On iOS, the FFI bridge requires a physical device; simulator is unsupported.
