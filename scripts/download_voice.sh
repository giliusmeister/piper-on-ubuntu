#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${MODEL_DIR:-/opt/piper/models}"

python3 "$SCRIPT_DIR/download_voices.py" --model-dir "$MODEL_DIR" "$@"
