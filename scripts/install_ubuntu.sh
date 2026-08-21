#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/piper-openai-api}"
APP_USER="${APP_USER:-piperapi}"
VOICE="${VOICE:-el_GR-joy-medium}"

if ! id "$APP_USER" >/dev/null 2>&1; then
  sudo useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi

sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip curl nginx ffmpeg

sudo mkdir -p "$APP_DIR"
sudo cp -R app requirements.txt .env.example "$APP_DIR"/
sudo chown -R "$APP_USER:$APP_USER" "$APP_DIR"

sudo -u "$APP_USER" python3 -m venv "$APP_DIR/.venv"
sudo -u "$APP_USER" "$APP_DIR/.venv/bin/pip" install --upgrade pip
sudo -u "$APP_USER" "$APP_DIR/.venv/bin/pip" install -r "$APP_DIR/requirements.txt"

MODEL_DIR=/opt/piper/models ./scripts/download_voice.sh "$VOICE"

if [ ! -f "$APP_DIR/.env" ]; then
  sudo cp "$APP_DIR/.env.example" "$APP_DIR/.env"
  sudo sed -i "s/el_GR-joy-medium/$VOICE/g" "$APP_DIR/.env"
  sudo sed -i "s/piper-el_GR-joy-medium/piper-$VOICE/g" "$APP_DIR/.env"
fi

sudo cp deploy/piper-openai-api.service /etc/systemd/system/piper-openai-api.service
sudo systemctl daemon-reload
sudo systemctl enable --now piper-openai-api

sudo cp deploy/nginx-piper-openai-api.conf /etc/nginx/sites-available/piper-openai-api
sudo ln -sf /etc/nginx/sites-available/piper-openai-api /etc/nginx/sites-enabled/piper-openai-api
sudo nginx -t
sudo systemctl reload nginx

echo "Ready: http://192.168.11.11/v1/audio/speech"
