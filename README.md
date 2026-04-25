# Muesli

Muesli is a macOS SwiftUI voice-to-text prototype that records microphone audio
and transcribes it locally with NVIDIA Parakeet through FluidAudio.

## Run

```bash
./script/build_and_run.sh
```

## Parakeet backend

The default model is Parakeet TDT 0.6B v3. You can switch to v2 in the toolbar
or Settings. FluidAudio downloads and caches the Core ML model artifacts on
first use; later transcriptions reuse the warmed model.
