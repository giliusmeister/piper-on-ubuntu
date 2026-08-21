#!/usr/bin/env bash
set -euo pipefail

VOICE="${1:-el_GR-joy-medium}"
MODEL_DIR="${MODEL_DIR:-/opt/piper/models}"
BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main"

case "$VOICE" in
  el_GR-joy-medium)
    VOICE_PATH="el/el_GR/joy/medium"
    ;;
  el_GR-rapunzelina-medium)
    VOICE_PATH="el/el_GR/rapunzelina/medium"
    ;;
  el_GR-rapunzelina-low)
    VOICE_PATH="el/el_GR/rapunzelina/low"
    ;;
  *)
    echo "Unsupported voice: $VOICE" >&2
    echo "Supported: el_GR-joy-medium, el_GR-rapunzelina-medium, el_GR-rapunzelina-low" >&2
    exit 2
    ;;
esac

sudo mkdir -p "$MODEL_DIR"
sudo curl -L --fail -o "$MODEL_DIR/$VOICE.onnx" "$BASE_URL/$VOICE_PATH/$VOICE.onnx"
sudo curl -L --fail -o "$MODEL_DIR/$VOICE.onnx.json" "$BASE_URL/$VOICE_PATH/$VOICE.onnx.json"

echo "Downloaded $VOICE to $MODEL_DIR"
