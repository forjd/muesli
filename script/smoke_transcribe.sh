#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT_DIR/.venv/bin/python"
AUDIO="$ROOT_DIR/.cache/smoke-silence.wav"
MODEL="${1:-nvidia/parakeet-tdt-0.6b-v3}"

if [[ ! -x "$PYTHON" ]]; then
  echo "Missing .venv. Run ./script/setup_python.sh first." >&2
  exit 2
fi

"$PYTHON" - <<PY
import wave
from pathlib import Path

path = Path("$AUDIO")
path.parent.mkdir(exist_ok=True)
with wave.open(str(path), "wb") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(16000)
    wav.writeframes(b"\\x00\\x00" * 16000)
print(path)
PY

HF_HOME="$ROOT_DIR/.cache/huggingface" \
NEMO_HOME="$ROOT_DIR/.cache/nemo" \
"$PYTHON" "$ROOT_DIR/Sources/Muesli/Resources/parakeet_transcribe.py" \
  --model "$MODEL" \
  "$AUDIO"
