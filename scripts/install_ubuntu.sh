#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-.env}"

if [ -f "$DEPLOY_ENV_FILE" ]; then
  sed -i 's/\r$//' "$DEPLOY_ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$DEPLOY_ENV_FILE"
  set +a
fi

APP_DIR="${APP_DIR:-/opt/piper-openai-api}"
APP_USER="${APP_USER:-piperapi}"
LANGUAGES="${LANGUAGES:-all}"
CONFIGURE_NGINX="${CONFIGURE_NGINX:-snippet}"
PIPER_API_KEY="${PIPER_API_KEY:-local-dev-key}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PIPER_DEFAULT_LANGUAGE="${PIPER_DEFAULT_LANGUAGE:-en}"
PIPER_PORT="${PIPER_PORT:-8099}"
PIPER_HOST="${PIPER_HOST:-127.0.0.1}"
PIPER_TIMEOUT_SECONDS="${PIPER_TIMEOUT_SECONDS:-60}"
PIPER_TTS_MAX_CONCURRENT="${PIPER_TTS_MAX_CONCURRENT:-1}"
ENABLE_PIPER_MONITOR="${ENABLE_PIPER_MONITOR:-1}"
PIPER_MONITOR_INTERVAL="${PIPER_MONITOR_INTERVAL:-1min}"
PIPER_MONITOR_RANDOMIZED_DELAY="${PIPER_MONITOR_RANDOMIZED_DELAY:-10s}"
PIPER_MONITOR_TIMEOUT_SECONDS="${PIPER_MONITOR_TIMEOUT_SECONDS:-10}"
PIPER_MONITOR_MIN_AVAILABLE_MB="${PIPER_MONITOR_MIN_AVAILABLE_MB:-512}"
PIPER_SENTENCE_SILENCE="${PIPER_SENTENCE_SILENCE:-0.4}"
LAN_HOST="${LAN_HOST:-192.168.11.11}"
NGINX_API_PORT="${NGINX_API_PORT:-8100}"
NGINX_ALLOW_CIDR="${NGINX_ALLOW_CIDR:-100.65.0.0/16}"
NGINX_ALLOW_IPV6_CIDR="${NGINX_ALLOW_IPV6_CIDR:-}"
ENABLE_TLS="${ENABLE_TLS:-0}"
TLS_CERT_PATH="${TLS_CERT_PATH:-/etc/nginx/tls/piper-openai-api/fullchain.pem}"
TLS_KEY_PATH="${TLS_KEY_PATH:-/etc/nginx/tls/piper-openai-api/privkey.pem}"
ENABLE_CERT_SYNC="${ENABLE_CERT_SYNC:-0}"
CERT_SYNC_INTERVAL="${CERT_SYNC_INTERVAL:-1h}"
CERT_SYNC_RANDOMIZED_DELAY="${CERT_SYNC_RANDOMIZED_DELAY:-10m}"
CERT_SYNC_RELOAD_NGINX="${CERT_SYNC_RELOAD_NGINX:-1}"
NETBIRD_CERT_SOURCE_HOST="${NETBIRD_CERT_SOURCE_HOST:-}"
NETBIRD_CERT_SOURCE_USER="${NETBIRD_CERT_SOURCE_USER:-root}"
NETBIRD_CERT_SOURCE_DIR="${NETBIRD_CERT_SOURCE_DIR:-}"
NETBIRD_CERT_FULLCHAIN_PATH="${NETBIRD_CERT_FULLCHAIN_PATH:-}"
NETBIRD_CERT_PRIVKEY_PATH="${NETBIRD_CERT_PRIVKEY_PATH:-}"
NETBIRD_CERT_SOURCE_URL="${NETBIRD_CERT_SOURCE_URL:-}"
NETBIRD_CERT_FULLCHAIN_URL="${NETBIRD_CERT_FULLCHAIN_URL:-}"
NETBIRD_CERT_PRIVKEY_URL="${NETBIRD_CERT_PRIVKEY_URL:-}"
NETBIRD_CERT_BASIC_AUTH_USER="${NETBIRD_CERT_BASIC_AUTH_USER:-}"
NETBIRD_CERT_BASIC_AUTH_PASSWORD="${NETBIRD_CERT_BASIC_AUTH_PASSWORD:-}"

upsert_env() {
  local key="$1"
  local value="$2"
  local quoted_value
  local tmp_file
  printf -v quoted_value '%q' "$value"
  tmp_file="$(mktemp)"

  if [ -f "$APP_DIR/.env" ]; then
    sudo awk -v key="$key" -v value="$quoted_value" '
      BEGIN { found = 0 }
      $0 ~ "^" key "=" { print key "=" value; found = 1; next }
      { print }
      END { if (!found) print key "=" value }
    ' "$APP_DIR/.env" >"$tmp_file"
  else
    printf '%s=%s\n' "$key" "$quoted_value" >"$tmp_file"
  fi

  sudo install -m 600 "$tmp_file" "$APP_DIR/.env"
  rm -f "$tmp_file"
}

if ! id "$APP_USER" >/dev/null 2>&1; then
  sudo useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi

sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip curl nginx ffmpeg openssh-client

sudo mkdir -p "$APP_DIR"
sudo cp -R app requirements.txt .env.example scripts "$APP_DIR"/
sudo sed -i 's/\r$//' "$APP_DIR"/scripts/*.sh
sudo chown -R "$APP_USER:$APP_USER" "$APP_DIR"
sudo chmod 755 "$APP_DIR"/scripts/*.sh

if [ -x "$APP_DIR/.venv/bin/python" ]; then
  desired_python_version="$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
  current_python_version="$("$APP_DIR/.venv/bin/python" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
  if [ "$current_python_version" != "$desired_python_version" ]; then
    backup_venv="$APP_DIR/.venv.backup.$(date +%Y%m%d%H%M%S)"
    echo "Existing venv uses Python $current_python_version; moving it to $backup_venv before creating Python $desired_python_version venv."
    sudo mv "$APP_DIR/.venv" "$backup_venv"
  fi
fi

sudo -u "$APP_USER" "$PYTHON_BIN" -m venv "$APP_DIR/.venv"
sudo -u "$APP_USER" "$APP_DIR/.venv/bin/pip" install --upgrade pip
sudo -u "$APP_USER" "$APP_DIR/.venv/bin/pip" install -r "$APP_DIR/requirements.txt"

if [ "$LANGUAGES" = "all" ]; then
  sudo env MODEL_DIR=/opt/piper/models "$APP_DIR/scripts/download_voice.sh"
else
  DOWNLOAD_ARGS=()
  for LANGUAGE in $LANGUAGES; do
    DOWNLOAD_ARGS+=(--language "$LANGUAGE")
  done
  sudo env MODEL_DIR=/opt/piper/models "$APP_DIR/scripts/download_voice.sh" "${DOWNLOAD_ARGS[@]}"
fi

if [ ! -f "$APP_DIR/.env" ]; then
  sudo cp "$APP_DIR/.env.example" "$APP_DIR/.env"
fi

upsert_env PIPER_API_KEY "$PIPER_API_KEY"
upsert_env PYTHON_BIN "$PYTHON_BIN"
upsert_env PIPER_DEFAULT_LANGUAGE "$PIPER_DEFAULT_LANGUAGE"
upsert_env PIPER_HOST "$PIPER_HOST"
upsert_env PIPER_PORT "$PIPER_PORT"
upsert_env PIPER_TIMEOUT_SECONDS "$PIPER_TIMEOUT_SECONDS"
upsert_env PIPER_TTS_MAX_CONCURRENT "$PIPER_TTS_MAX_CONCURRENT"
upsert_env ENABLE_PIPER_MONITOR "$ENABLE_PIPER_MONITOR"
upsert_env PIPER_MONITOR_INTERVAL "$PIPER_MONITOR_INTERVAL"
upsert_env PIPER_MONITOR_RANDOMIZED_DELAY "$PIPER_MONITOR_RANDOMIZED_DELAY"
upsert_env PIPER_MONITOR_TIMEOUT_SECONDS "$PIPER_MONITOR_TIMEOUT_SECONDS"
upsert_env PIPER_MONITOR_MIN_AVAILABLE_MB "$PIPER_MONITOR_MIN_AVAILABLE_MB"
upsert_env PIPER_SENTENCE_SILENCE "$PIPER_SENTENCE_SILENCE"
upsert_env LAN_HOST "$LAN_HOST"
upsert_env NGINX_API_PORT "$NGINX_API_PORT"
upsert_env NGINX_ALLOW_CIDR "$NGINX_ALLOW_CIDR"
upsert_env NGINX_ALLOW_IPV6_CIDR "$NGINX_ALLOW_IPV6_CIDR"
upsert_env ENABLE_TLS "$ENABLE_TLS"
upsert_env TLS_CERT_PATH "$TLS_CERT_PATH"
upsert_env TLS_KEY_PATH "$TLS_KEY_PATH"
upsert_env ENABLE_CERT_SYNC "$ENABLE_CERT_SYNC"
upsert_env CERT_SYNC_INTERVAL "$CERT_SYNC_INTERVAL"
upsert_env CERT_SYNC_RANDOMIZED_DELAY "$CERT_SYNC_RANDOMIZED_DELAY"
upsert_env CERT_SYNC_RELOAD_NGINX "$CERT_SYNC_RELOAD_NGINX"
upsert_env NETBIRD_CERT_SOURCE_URL "$NETBIRD_CERT_SOURCE_URL"
upsert_env NETBIRD_CERT_FULLCHAIN_URL "$NETBIRD_CERT_FULLCHAIN_URL"
upsert_env NETBIRD_CERT_PRIVKEY_URL "$NETBIRD_CERT_PRIVKEY_URL"
upsert_env NETBIRD_CERT_BASIC_AUTH_USER "$NETBIRD_CERT_BASIC_AUTH_USER"
upsert_env NETBIRD_CERT_BASIC_AUTH_PASSWORD "$NETBIRD_CERT_BASIC_AUTH_PASSWORD"
upsert_env NETBIRD_CERT_SOURCE_HOST "$NETBIRD_CERT_SOURCE_HOST"
upsert_env NETBIRD_CERT_SOURCE_USER "$NETBIRD_CERT_SOURCE_USER"
upsert_env NETBIRD_CERT_SOURCE_DIR "$NETBIRD_CERT_SOURCE_DIR"
upsert_env NETBIRD_CERT_FULLCHAIN_PATH "$NETBIRD_CERT_FULLCHAIN_PATH"
upsert_env NETBIRD_CERT_PRIVKEY_PATH "$NETBIRD_CERT_PRIVKEY_PATH"

sudo chown root:root "$APP_DIR/.env"
sudo chmod 600 "$APP_DIR/.env"

sudo cp deploy/piper-openai-api.service /etc/systemd/system/piper-openai-api.service
sudo systemctl daemon-reload
sudo systemctl enable piper-openai-api
sudo systemctl restart piper-openai-api

sudo mkdir -p /etc/nginx/snippets
NGINX_ALLOW_RULES="allow $NGINX_ALLOW_CIDR;"
if [ -n "$NGINX_ALLOW_IPV6_CIDR" ]; then
  NGINX_ALLOW_RULES="$NGINX_ALLOW_RULES\nallow $NGINX_ALLOW_IPV6_CIDR;"
fi
sudo sed \
  -e "s/__PIPER_PORT__/$PIPER_PORT/g" \
  -e "s|__NGINX_ALLOW_RULES__|$NGINX_ALLOW_RULES|g" \
  deploy/nginx-piper-openai-api.locations.conf \
  | sudo tee /etc/nginx/snippets/piper-openai-api.locations.conf >/dev/null

if [ "$CONFIGURE_NGINX" = "site" ]; then
  if [ "$ENABLE_TLS" = "1" ]; then
    if [ -n "$NETBIRD_CERT_SOURCE_HOST" ] || [ -n "$NETBIRD_CERT_SOURCE_URL" ] || [ -n "$NETBIRD_CERT_FULLCHAIN_URL" ]; then
      sudo env \
        SOURCE_HOST="$NETBIRD_CERT_SOURCE_HOST" \
        SOURCE_USER="$NETBIRD_CERT_SOURCE_USER" \
        SOURCE_CERT_DIR="$NETBIRD_CERT_SOURCE_DIR" \
        SOURCE_FULLCHAIN_PATH="$NETBIRD_CERT_FULLCHAIN_PATH" \
        SOURCE_PRIVKEY_PATH="$NETBIRD_CERT_PRIVKEY_PATH" \
        SOURCE_URL="$NETBIRD_CERT_SOURCE_URL" \
        SOURCE_FULLCHAIN_URL="$NETBIRD_CERT_FULLCHAIN_URL" \
        SOURCE_PRIVKEY_URL="$NETBIRD_CERT_PRIVKEY_URL" \
        SOURCE_BASIC_AUTH_USER="$NETBIRD_CERT_BASIC_AUTH_USER" \
        SOURCE_BASIC_AUTH_PASSWORD="$NETBIRD_CERT_BASIC_AUTH_PASSWORD" \
        TARGET_FULLCHAIN_PATH="$TLS_CERT_PATH" \
        TARGET_PRIVKEY_PATH="$TLS_KEY_PATH" \
        CERT_SYNC_RELOAD_NGINX=0 \
        "$APP_DIR/scripts/fetch_netbird_certificate.sh"
    fi

    if [ ! -f "$TLS_CERT_PATH" ] || [ ! -f "$TLS_KEY_PATH" ]; then
      echo "TLS is enabled but certificate files are missing: $TLS_CERT_PATH / $TLS_KEY_PATH" >&2
      exit 1
    fi

    sed \
      -e "s/__NGINX_API_PORT__/$NGINX_API_PORT/g" \
      -e "s/__LAN_HOST__/$LAN_HOST/g" \
      -e "s|__TLS_CERT_PATH__|$TLS_CERT_PATH|g" \
      -e "s|__TLS_KEY_PATH__|$TLS_KEY_PATH|g" \
      deploy/nginx-piper-openai-api.site-ssl.conf \
      | sudo tee /etc/nginx/sites-available/piper-openai-api >/dev/null
  else
    sed -e "s/__NGINX_API_PORT__/$NGINX_API_PORT/g" -e "s/__LAN_HOST__/$LAN_HOST/g" deploy/nginx-piper-openai-api.site.conf | sudo tee /etc/nginx/sites-available/piper-openai-api >/dev/null
  fi
  sudo ln -sf /etc/nginx/sites-available/piper-openai-api /etc/nginx/sites-enabled/piper-openai-api
  sudo nginx -t
  sudo systemctl reload nginx
  if [ "$ENABLE_TLS" = "1" ]; then
    echo "Ready through nginx: https://$LAN_HOST:$NGINX_API_PORT/v1/audio/speech"
  else
    echo "Ready through nginx: http://$LAN_HOST:$NGINX_API_PORT/v1/audio/speech"
  fi
else
  echo "Nginx snippet installed: /etc/nginx/snippets/piper-openai-api.locations.conf"
  echo "Include it in an existing server block, then run: sudo nginx -t && sudo systemctl reload nginx"
fi

if [ "$ENABLE_TLS" = "1" ] && [ "$ENABLE_CERT_SYNC" = "1" ]; then
  sudo cp deploy/piper-openai-api-cert-sync.service /etc/systemd/system/piper-openai-api-cert-sync.service
  sudo sed \
    -e "s/__CERT_SYNC_INTERVAL__/$CERT_SYNC_INTERVAL/g" \
    -e "s/__CERT_SYNC_RANDOMIZED_DELAY__/$CERT_SYNC_RANDOMIZED_DELAY/g" \
    deploy/piper-openai-api-cert-sync.timer \
    | sudo tee /etc/systemd/system/piper-openai-api-cert-sync.timer >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable --now piper-openai-api-cert-sync.timer
  echo "Certificate sync timer enabled: piper-openai-api-cert-sync.timer"
fi


if [ "$ENABLE_PIPER_MONITOR" = "1" ]; then
  sudo cp deploy/piper-openai-api-monitor.service /etc/systemd/system/piper-openai-api-monitor.service
  sudo sed \
    -e "s/__PIPER_MONITOR_INTERVAL__/$PIPER_MONITOR_INTERVAL/g" \
    -e "s/__PIPER_MONITOR_RANDOMIZED_DELAY__/$PIPER_MONITOR_RANDOMIZED_DELAY/g" \
    deploy/piper-openai-api-monitor.timer \
    | sudo tee /etc/systemd/system/piper-openai-api-monitor.timer >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable --now piper-openai-api-monitor.timer
  echo "Piper monitor timer enabled: piper-openai-api-monitor.timer"
fi

echo "Local service ready: http://$PIPER_HOST:$PIPER_PORT/v1/audio/speech"
