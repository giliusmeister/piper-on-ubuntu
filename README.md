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

## Ubuntu Install

Copy this project to the Ubuntu server, then install only English and Greek first:

```bash
chmod +x scripts/*.sh
PIPER_PORT=8099 LANGUAGES="en el" bash scripts/install_ubuntu.sh
```

This installs the service on `127.0.0.1:8099` and writes an nginx snippet, but it does not claim port 80.

If `8099` is busy too, choose another local-only port:

```bash
PIPER_PORT=8199 LANGUAGES="en el" bash scripts/install_ubuntu.sh
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

1. Installs Python, nginx, ffmpeg, and curl.
2. Creates a `piperapi` system user.
3. Copies the app to `/opt/piper-openai-api`.
4. Creates a Python virtualenv and installs `piper-tts`.
5. Downloads Piper voice files to `/opt/piper/models`.
6. Writes `/opt/piper/models/openlingo_voices.json`.
7. Installs and starts `piper-openai-api.service`.
8. Writes `/etc/nginx/snippets/piper-openai-api.locations.conf`.

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
CONFIGURE_NGINX=site PIPER_PORT=8099 LANGUAGES="en el" bash scripts/install_ubuntu.sh
```

That creates a site on port `8080`:

```text
http://192.168.11.11:8080/v1/audio/speech
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
TTS_BASE_URL=http://192.168.11.11/v1
TTS_API_KEY=local-dev-key
TTS_MODEL=piper-auto
TTS_RESPONSE_FORMAT=wav
```

Send the current OpenLingo language code as `language` or `voice` in the speech request.

## Notes

- `POST /v1/audio/speech` returns `audio/wav` or `audio/mpeg`.
- `GET /v1/models` returns a minimal OpenAI-style model list.
- Auth defaults to `Authorization: Bearer local-dev-key`; replace it in `/opt/piper-openai-api/.env` for real use.
- Set `PIPER_API_KEY=` empty in `/opt/piper-openai-api/.env` to disable auth inside a trusted LAN.
- Do not commit a real `.env`; `.gitignore` excludes it.

Sources checked:

- Piper voices are published in [`rhasspy/piper-voices`](https://huggingface.co/rhasspy/piper-voices/blob/main/voices.json).
- The upstream Piper voice list is in [`rhasspy/piper/VOICES.md`](https://github.com/rhasspy/piper/blob/master/VOICES.md).
- The Python package used here is [`piper-tts`](https://pypi.org/project/piper-tts/), currently pinned to `1.6.0`.
