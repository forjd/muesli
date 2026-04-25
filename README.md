# Muesli

Muesli is a macOS SwiftUI voice-to-text prototype that records microphone audio
as 16 kHz mono WAV and sends it to a local NVIDIA Parakeet sidecar.

## Run

```bash
./script/setup_python.sh
./script/build_and_run.sh
```

## Parakeet backend

The app bundles `parakeet_transcribe.py` and executes the project-local
`.venv/bin/python`. Run `./script/setup_python.sh` once to create the
environment and install PyTorch, torchaudio, and NVIDIA NeMo.

You can override the runtime with `MUESLI_PYTHON=/path/to/python`.

The default model is `nvidia/parakeet-tdt-0.6b-v3`. You can switch to
`nvidia/parakeet-tdt-0.6b-v2` in the toolbar or Settings.

Muesli keeps a persistent Python worker alive while the app is open. The first
request for a model still pays the NeMo/model load cost, but later requests
reuse the warmed model.

## Smoke test

```bash
./script/smoke_transcribe.sh
./script/smoke_transcribe.sh nvidia/parakeet-tdt-0.6b-v2
```

Model files are cached under `.cache/`. The first run can take longer while
Hugging Face artifacts are downloaded.
