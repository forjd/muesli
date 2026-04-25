#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3.11}"
VENV_DIR="$ROOT_DIR/.venv"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python runtime '$PYTHON_BIN' was not found. Install Python 3.11 or set PYTHON_BIN." >&2
  exit 2
fi

"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
"$VENV_DIR/bin/python" -m pip install -r "$ROOT_DIR/requirements-parakeet.txt"
"$VENV_DIR/bin/python" "$ROOT_DIR/Sources/Muesli/Resources/parakeet_transcribe.py" --check-dependencies
