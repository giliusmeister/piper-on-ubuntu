# Piper OpenAI-compatible TTS API on Ubuntu

Small local service for running Piper TTS behind nginx with an OpenAI-like speech endpoint.

Default local service URL:

```text
http://127.0.0.1:8099/v1/audio/speech
```

## OpenLingo Languages

The installer downloads Piper voices for these OpenLingo language codes:

| OpenLingo | Default Piper voice |
| --- | --- |
| `en` | `en_US-joe-medium` |
| `es` | `es_ES-davefx-medium` |
| `de` | `de_DE-thorsten-medium` |
| `fr` | `fr_FR-siwis-medium` |
| `it` | `it_IT-paola-medium` |
| `pt` | `pt_BR-faber-medium` |
| `ru` | `ru_RU-irina-medium` |
| `ar` | `ar_JO-kareem-medium` |
| `hi` | `hi_IN-pratham-medium` |
| `ko` | `ko_KR-kss-medium` |
| `zh` | `zh_CN-huayan-medium` |
| `ja` | best available Japanese Piper voice from `voices.json` |
| `el` | `el_GR-joy-medium` |

For languages without a pinned preferred key, the downloader chooses the best available voice from the official Piper registry, preferring `medium`, then `high`, `low`, and `x_low`.

## API

### Health

Use `http://127.0.0.1:8099` before nginx is connected, or the LAN URL after adding the nginx snippet.

```bash
curl http://127.0.0.1:8099/health
```

### Models

```bash
curl http://127.0.0.1:8099/v1/models \
  -H "Authorization: Bearer local-dev-key"
```

### Speech

Choose the voice by OpenLingo language code:

```bash
curl -X POST http://127.0.0.1:8099/v1/audio/speech \
  -H "Authorization: Bearer local-dev-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "piper-auto",
    "voice": "el",
    "language": "el",
    "input": "Γεια σου",
    "response_format": "wav"
  }' \
  --output speech.wav
```

Or choose the exact Piper model id:

```json
{
  "model": "piper-el_GR-joy-medium",
  "input": "Γεια σου",
  "response_format": "mp3"
}
```

`instructions` is accepted for OpenAI compatibility but ignored by Piper. MP3 output requires `ffmpeg`.

### Pauses

The wrapper passes `PIPER_SENTENCE_SILENCE` to Piper as `--sentence-silence`.
The default is `0.4`, which adds a short pause after sentence boundaries such as `.`, `?`, and `!`.

```env
PIPER_SENTENCE_SILENCE=0.4
```

Piper also has upstream support for per-phoneme pauses in some builds/configurations, but the
Python CLI installed by this project exposes `--sentence-silence` reliably.

## Ubuntu Install

Copy this project to the Ubuntu server, then install the full LAN profile for the second server:

```bash
chmod +x scripts/*.sh
LAN_HOST=192.168.11.21 NGINX_API_PORT=8100 PIPER_PORT=8099 LANGUAGES="all" CONFIGURE_NGINX=site bash scripts/install_ubuntu.sh
```

This installs the service on `127.0.0.1:8099`, exposes nginx on `192.168.11.21:8100`, and downloads all OpenLingo voices. Use `LANGUAGES="en el"` first if you want a smaller smoke-test install.

If `8099` is busy too, choose another local-only port:

```bash
LAN_HOST=192.168.11.21 NGINX_API_PORT=8100 PIPER_PORT=8199 LANGUAGES="en el" CONFIGURE_NGINX=site bash scripts/install_ubuntu.sh
```

### Install With NetBird Wildcard Certificate

If the main NetBird server already exposes the wildcard certificate for the subnet, keep the real URL and Basic Auth credentials in local `.env`. The installer loads `.env` automatically and can fetch the certificate over HTTPS or SSH before writing the nginx TLS site.

Local `.env` on the target server:

```env
ENABLE_TLS=1
ENABLE_CERT_SYNC=1
CERT_SYNC_INTERVAL=15min
CERT_SYNC_RANDOMIZED_DELAY=2min
NETBIRD_CERT_SOURCE_URL=https://netbird.example.internal/example.internal
NETBIRD_CERT_BASIC_AUTH_USER=cert-reader
NETBIRD_CERT_BASIC_AUTH_PASSWORD=
```

Quote `.env` values that contain shell-special characters, for example `NETBIRD_CERT_BASIC_AUTH_PASSWORD='secret&value'`.

Install command:

```bash
chmod +x scripts/*.sh
LAN_HOST=192.168.11.21 \
NGINX_API_PORT=9443 \
PIPER_PORT=8099 \
NGINX_ALLOW_CIDR=100.65.0.0/16 \
LANGUAGES="all" \
CONFIGURE_NGINX=site \
bash scripts/install_ubuntu.sh
```

For HTTPS download mode, the installer expects `fullchain.pem` and `privkey.pem` under `NETBIRD_CERT_SOURCE_URL`. It copies them to:

```text
/etc/nginx/tls/piper-openai-api/fullchain.pem
/etc/nginx/tls/piper-openai-api/privkey.pem
```

With `ENABLE_CERT_SYNC=1`, the installer also enables `piper-openai-api-cert-sync.timer`. The timer checks the NetBird certificate source every `CERT_SYNC_INTERVAL`, installs the new certificate only when the files change, then validates and reloads nginx.

If the certificate file URLs are different, set explicit URLs instead:

```bash
ENABLE_TLS=1 \
NETBIRD_CERT_FULLCHAIN_URL=https://netbird.example.internal/example.internal/fullchain.pem \
NETBIRD_CERT_PRIVKEY_URL=https://netbird.example.internal/example.internal/privkey.pem \
CONFIGURE_NGINX=site \
bash scripts/install_ubuntu.sh
```

After English and Greek are verified, download all OpenLingo voices:

```bash
sudo MODEL_DIR=/opt/piper/models bash scripts/download_voice.sh
sudo systemctl restart piper-openai-api
```

To override a voice during manual download:

```bash
sudo MODEL_DIR=/opt/piper/models bash scripts/download_voice.sh \
  --language el \
  --voice el=el_GR-rapunzelina-medium
```

The installer:

1. Installs Python, nginx, ffmpeg, curl, and the OpenSSH client.
2. Creates a `piperapi` system user.
3. Copies the app to `/opt/piper-openai-api`.
4. Creates a Python virtualenv and installs `piper-tts`.
5. Downloads Piper voice files to `/opt/piper/models`.
6. Writes `/opt/piper/models/openlingo_voices.json`.
7. Installs and starts `piper-openai-api.service`.
8. Writes `/etc/nginx/snippets/piper-openai-api.locations.conf`.
9. Optionally fetches TLS certificate files from the main NetBird server and writes an HTTPS nginx site.
10. Optionally enables a systemd timer that keeps polling the certificate source and reloads nginx only after a changed certificate is installed.

## Certificate Sync Script

The installer can keep this automatic through `piper-openai-api-cert-sync.timer`. Use these commands to inspect or force the sync on the second server:

```bash
sudo systemctl list-timers piper-openai-api-cert-sync.timer
sudo systemctl status piper-openai-api-cert-sync.timer
sudo systemctl start piper-openai-api-cert-sync.service
```

The sync service reads `/opt/piper-openai-api/.env`. The fetch script can still be run manually with another env file if needed:

```bash
sudo CERT_ENV_FILE=/path/to/local.env CERT_SYNC_RELOAD_NGINX=1 bash /opt/piper-openai-api/scripts/fetch_netbird_certificate.sh
```

For SSH/SCP mode, keep using host/path variables instead of URL variables:

```bash
sudo SOURCE_HOST=100.64.0.10 \
SOURCE_USER=root \
SOURCE_CERT_DIR=/etc/letsencrypt/live/subnet.example.com \
bash /opt/piper-openai-api/scripts/fetch_netbird_certificate.sh
```

## Nginx

Port 80 is often already used by other apps. The installer does not enable a new port 80 server block by default.

Add this line inside an existing nginx `server { ... }` block:

```nginx
include /etc/nginx/snippets/piper-openai-api.locations.conf;
```

Then reload nginx:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

After that, the LAN URL is:

```text
http://192.168.11.11/v1/audio/speech
```

If you want a standalone nginx test port instead:

```bash
LAN_HOST=192.168.11.21 NGINX_API_PORT=8100 PIPER_PORT=8099 LANGUAGES="all" CONFIGURE_NGINX=site bash scripts/install_ubuntu.sh
```

That creates a standalone nginx site on `NGINX_API_PORT`, for example `8100`:

```text
http://192.168.11.21:8100/v1/audio/speech
```

The nginx snippet allows only `NGINX_ALLOW_CIDR`, which defaults to the NetBird subnet `100.65.0.0/16`. With `ENABLE_TLS=1`, the standalone site listens with TLS on the same configured port, for example:

```text
https://192.168.11.21:9443/v1/audio/speech
```

## Manual CLI Check

After installation:

```bash
echo "Γεια σου" | /opt/piper-openai-api/.venv/bin/piper \
  --model /opt/piper/models/el_GR-joy-medium.onnx \
  --config /opt/piper/models/el_GR-joy-medium.onnx.json \
  --output_file /tmp/hello.wav
```

## Service Commands

```bash
sudo systemctl status piper-openai-api
sudo journalctl -u piper-openai-api -f
sudo nginx -t
sudo systemctl reload nginx
```

## OpenLingo Env

```env
TTS_PROVIDER=openai-compatible
TTS_BASE_URL=http://192.168.11.21:8100/v1
TTS_API_KEY=local-dev-key
TTS_MODEL=piper-auto
TTS_RESPONSE_FORMAT=mp3
```

If the second server is exposed through TLS, use the HTTPS base URL instead:

```env
TTS_BASE_URL=https://192.168.11.21:9443/v1
```

Send the current OpenLingo language code as `language` or `voice` in the speech request.

## Notes

- `POST /v1/audio/speech` returns `audio/wav` or `audio/mpeg`.
- `GET /v1/models` returns a minimal OpenAI-style model list.
- Auth defaults to `Authorization: Bearer local-dev-key`; replace it in `/opt/piper-openai-api/.env` for real use.
- Set `PIPER_API_KEY=` empty in `/opt/piper-openai-api/.env` to disable auth inside a trusted LAN.
- Do not commit a real `.env`; `.gitignore` excludes it.
- The HTTPS install path assumes the target server can reach the main NetBird certificate endpoint or SSH host and has access to the wildcard certificate files. Keep real internal URLs, Basic Auth credentials, SSH users, and hostnames in local `.env` only.

Sources checked:

- Piper voices are published in [`rhasspy/piper-voices`](https://huggingface.co/rhasspy/piper-voices/blob/main/voices.json).
- The upstream Piper voice list is in [`rhasspy/piper/VOICES.md`](https://github.com/rhasspy/piper/blob/master/VOICES.md).
- The Python package used here is [`piper-tts`](https://pypi.org/project/piper-tts/), currently pinned to `1.7.0`.
