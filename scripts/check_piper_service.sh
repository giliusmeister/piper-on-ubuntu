#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/.env"
MONITOR_ENV_FILE="${MONITOR_ENV_FILE:-$DEFAULT_ENV_FILE}"

if [[ -f "$MONITOR_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$MONITOR_ENV_FILE"
  set +a
fi

PIPER_HOST="${PIPER_HOST:-127.0.0.1}"
PIPER_PORT="${PIPER_PORT:-8099}"
LAN_HOST="${LAN_HOST:-}"
NGINX_API_PORT="${NGINX_API_PORT:-8100}"
CONFIGURE_NGINX="${CONFIGURE_NGINX:-snippet}"
ENABLE_TLS="${ENABLE_TLS:-0}"
ENABLE_CERT_SYNC="${ENABLE_CERT_SYNC:-0}"
PIPER_MONITOR_TIMEOUT_SECONDS="${PIPER_MONITOR_TIMEOUT_SECONDS:-10}"
PIPER_MONITOR_MIN_AVAILABLE_MB="${PIPER_MONITOR_MIN_AVAILABLE_MB:-512}"

fail() {
  echo "Piper monitor failed: $*" >&2
  exit 1
}

check_json_ok() {
  local url="$1"
  local body
  body="$(curl --fail --silent --show-error --max-time "$PIPER_MONITOR_TIMEOUT_SECONDS" "$url")" || fail "health request failed: $url"
  python3 -c 'import json, sys; url = sys.argv[1]; data = json.load(sys.stdin); assert data.get("ok") is True, f"health is not ok for {url}: ok={data.get('"'"'ok'"'"')!r}"' "$url" <<<"$body"
}

check_available_memory() {
  local available_mb
  available_mb="$(awk '/MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)"
  if [[ -n "$available_mb" && "$available_mb" -lt "$PIPER_MONITOR_MIN_AVAILABLE_MB" ]]; then
    fail "available memory is ${available_mb}MB, below ${PIPER_MONITOR_MIN_AVAILABLE_MB}MB"
  fi
}

systemctl is-active --quiet piper-openai-api.service || fail "piper-openai-api.service is not active"
check_available_memory
check_json_ok "http://$PIPER_HOST:$PIPER_PORT/health"

if [[ "$CONFIGURE_NGINX" = "site" && -n "$LAN_HOST" ]]; then
  scheme="http"
  if [[ "$ENABLE_TLS" = "1" ]]; then
    scheme="https"
  fi
  check_json_ok "$scheme://$LAN_HOST:$NGINX_API_PORT/health"
fi

if [[ "$ENABLE_TLS" = "1" && "$ENABLE_CERT_SYNC" = "1" ]]; then
  systemctl is-active --quiet piper-openai-api-cert-sync.timer || fail "piper-openai-api-cert-sync.timer is not active"
fi

echo "Piper monitor ok."
