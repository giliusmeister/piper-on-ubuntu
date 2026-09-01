#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/.env"
CERT_ENV_FILE="${CERT_ENV_FILE:-$DEFAULT_ENV_FILE}"

if [[ -f "$CERT_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$CERT_ENV_FILE"
  set +a
fi

SOURCE_HOST="${SOURCE_HOST:-${NETBIRD_CERT_SOURCE_HOST:-}}"
SOURCE_USER="${SOURCE_USER:-${NETBIRD_CERT_SOURCE_USER:-root}}"
SOURCE_CERT_DIR="${SOURCE_CERT_DIR:-${NETBIRD_CERT_SOURCE_DIR:-}}"
SOURCE_FULLCHAIN_PATH="${SOURCE_FULLCHAIN_PATH:-${NETBIRD_CERT_FULLCHAIN_PATH:-}}"
SOURCE_PRIVKEY_PATH="${SOURCE_PRIVKEY_PATH:-${NETBIRD_CERT_PRIVKEY_PATH:-}}"
SOURCE_URL="${SOURCE_URL:-${NETBIRD_CERT_SOURCE_URL:-}}"
SOURCE_FULLCHAIN_URL="${SOURCE_FULLCHAIN_URL:-${NETBIRD_CERT_FULLCHAIN_URL:-}}"
SOURCE_PRIVKEY_URL="${SOURCE_PRIVKEY_URL:-${NETBIRD_CERT_PRIVKEY_URL:-}}"
SOURCE_BASIC_AUTH_USER="${SOURCE_BASIC_AUTH_USER:-${NETBIRD_CERT_BASIC_AUTH_USER:-}}"
SOURCE_BASIC_AUTH_PASSWORD="${SOURCE_BASIC_AUTH_PASSWORD:-${NETBIRD_CERT_BASIC_AUTH_PASSWORD:-}}"
TARGET_CERT_DIR="${TARGET_CERT_DIR:-/etc/nginx/tls/piper-openai-api}"
TARGET_FULLCHAIN_PATH="${TARGET_FULLCHAIN_PATH:-${TLS_CERT_PATH:-$TARGET_CERT_DIR/fullchain.pem}}"
TARGET_PRIVKEY_PATH="${TARGET_PRIVKEY_PATH:-${TLS_KEY_PATH:-$TARGET_CERT_DIR/privkey.pem}}"
RELOAD_NGINX="${RELOAD_NGINX:-${CERT_SYNC_RELOAD_NGINX:-0}}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

escape_curl_config_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

if [[ -n "$SOURCE_CERT_DIR" ]]; then
  SOURCE_FULLCHAIN_PATH="${SOURCE_FULLCHAIN_PATH:-$SOURCE_CERT_DIR/fullchain.pem}"
  SOURCE_PRIVKEY_PATH="${SOURCE_PRIVKEY_PATH:-$SOURCE_CERT_DIR/privkey.pem}"
fi

if [[ -n "$SOURCE_URL" ]]; then
  SOURCE_URL="${SOURCE_URL%/}"
  SOURCE_FULLCHAIN_URL="${SOURCE_FULLCHAIN_URL:-$SOURCE_URL/fullchain.pem}"
  SOURCE_PRIVKEY_URL="${SOURCE_PRIVKEY_URL:-$SOURCE_URL/privkey.pem}"
fi

LOCAL_FULLCHAIN="$TMP_DIR/fullchain.pem"
LOCAL_PRIVKEY="$TMP_DIR/privkey.pem"

if [[ -n "$SOURCE_FULLCHAIN_URL" || -n "$SOURCE_PRIVKEY_URL" ]]; then
  if [[ -z "$SOURCE_FULLCHAIN_URL" || -z "$SOURCE_PRIVKEY_URL" ]]; then
    echo "Set SOURCE_URL or both SOURCE_FULLCHAIN_URL and SOURCE_PRIVKEY_URL" >&2
    exit 1
  fi

  CURL_CONFIG="$TMP_DIR/curl.conf"
  {
    printf '%s\n' 'fail'
    printf '%s\n' 'silent'
    printf '%s\n' 'show-error'
    printf '%s\n' 'location'
    if [[ -n "$SOURCE_BASIC_AUTH_USER" || -n "$SOURCE_BASIC_AUTH_PASSWORD" ]]; then
      auth_user="$(escape_curl_config_value "$SOURCE_BASIC_AUTH_USER")"
      auth_password="$(escape_curl_config_value "$SOURCE_BASIC_AUTH_PASSWORD")"
      printf 'user = "%s:%s"\n' "$auth_user" "$auth_password"
    fi
  } >"$CURL_CONFIG"
  chmod 600 "$CURL_CONFIG"

  curl --config "$CURL_CONFIG" --output "$LOCAL_FULLCHAIN" "$SOURCE_FULLCHAIN_URL"
  curl --config "$CURL_CONFIG" --output "$LOCAL_PRIVKEY" "$SOURCE_PRIVKEY_URL"
else
  if [[ -z "$SOURCE_HOST" ]]; then
    echo "SOURCE_HOST is required for scp mode" >&2
    exit 1
  fi

  if [[ -z "$SOURCE_FULLCHAIN_PATH" || -z "$SOURCE_PRIVKEY_PATH" ]]; then
    echo "Set SOURCE_CERT_DIR or both SOURCE_FULLCHAIN_PATH and SOURCE_PRIVKEY_PATH" >&2
    exit 1
  fi

  REMOTE_FULLCHAIN="${SOURCE_USER}@${SOURCE_HOST}:${SOURCE_FULLCHAIN_PATH}"
  REMOTE_PRIVKEY="${SOURCE_USER}@${SOURCE_HOST}:${SOURCE_PRIVKEY_PATH}"

  scp -q "$REMOTE_FULLCHAIN" "$LOCAL_FULLCHAIN"
  scp -q "$REMOTE_PRIVKEY" "$LOCAL_PRIVKEY"
fi

changed=0
if [[ ! -f "$TARGET_FULLCHAIN_PATH" ]] || ! cmp -s "$LOCAL_FULLCHAIN" "$TARGET_FULLCHAIN_PATH"; then
  changed=1
fi
if [[ ! -f "$TARGET_PRIVKEY_PATH" ]] || ! cmp -s "$LOCAL_PRIVKEY" "$TARGET_PRIVKEY_PATH"; then
  changed=1
fi

if [[ "$changed" = "0" ]]; then
  echo "Certificate is already up to date."
  exit 0
fi

sudo install -d -m 700 "$TARGET_CERT_DIR"
sudo install -m 600 "$LOCAL_FULLCHAIN" "$TARGET_FULLCHAIN_PATH"
sudo install -m 600 "$LOCAL_PRIVKEY" "$TARGET_PRIVKEY_PATH"

echo "Certificate updated:"
echo "  fullchain: $TARGET_FULLCHAIN_PATH"
echo "  privkey:   $TARGET_PRIVKEY_PATH"

if [[ "$RELOAD_NGINX" = "1" ]]; then
  sudo nginx -t
  sudo systemctl reload nginx
  echo "nginx reloaded."
fi
