#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/piper-openai-api}"
APP_USER="${APP_USER:-piperapi}"
LANGUAGES="${LANGUAGES:-all}"
CONFIGURE_NGINX="${CONFIGURE_NGINX:-snippet}"
PIPER_PORT="${PIPER_PORT:-8099}"
PIPER_HOST="${PIPER_HOST:-127.0.0.1}"

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

if [ "$LANGUAGES" = "all" ]; then
  sudo env MODEL_DIR=/opt/piper/models ./scripts/download_voice.sh
else
  DOWNLOAD_ARGS=()
  for LANGUAGE in $LANGUAGES; do
    DOWNLOAD_ARGS+=(--language "$LANGUAGE")
  done
  sudo env MODEL_DIR=/opt/piper/models ./scripts/download_voice.sh "${DOWNLOAD_ARGS[@]}"
fi

if [ ! -f "$APP_DIR/.env" ]; then
  sudo cp "$APP_DIR/.env.example" "$APP_DIR/.env"
fi
sudo sed -i "s/^PIPER_HOST=.*/PIPER_HOST=$PIPER_HOST/" "$APP_DIR/.env"
sudo sed -i "s/^PIPER_PORT=.*/PIPER_PORT=$PIPER_PORT/" "$APP_DIR/.env"

sudo cp deploy/piper-openai-api.service /etc/systemd/system/piper-openai-api.service
sudo systemctl daemon-reload
sudo systemctl enable piper-openai-api
sudo systemctl restart piper-openai-api

sudo mkdir -p /etc/nginx/snippets
sudo sed "s/__PIPER_PORT__/$PIPER_PORT/g" \
  deploy/nginx-piper-openai-api.locations.conf \
  | sudo tee /etc/nginx/snippets/piper-openai-api.locations.conf >/dev/null

if [ "$CONFIGURE_NGINX" = "site" ]; then
  sudo cp deploy/nginx-piper-openai-api.site.conf /etc/nginx/sites-available/piper-openai-api
  sudo ln -sf /etc/nginx/sites-available/piper-openai-api /etc/nginx/sites-enabled/piper-openai-api
  sudo nginx -t
  sudo systemctl reload nginx
  echo "Ready through nginx: http://192.168.11.11:8080/v1/audio/speech"
else
  echo "Nginx snippet installed: /etc/nginx/snippets/piper-openai-api.locations.conf"
  echo "Include it in an existing server block, then run: sudo nginx -t && sudo systemctl reload nginx"
fi

echo "Local service ready: http://$PIPER_HOST:$PIPER_PORT/v1/audio/speech"
