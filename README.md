# Piper OpenAI-compatible TTS API on Ubuntu

Small local service for running Piper TTS behind nginx with an OpenAI-like speech endpoint.

Target LAN URL:

```text
http://192.168.11.11/v1/audio/speech
```

Default voice:

```text
el_GR-joy-medium
```

## API

### Health

```bash
curl http://192.168.11.11/health
```

### Speech

```bash
curl -X POST http://192.168.11.11/v1/audio/speech \
  -H "Authorization: Bearer local-dev-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "piper-el_GR-joy-medium",
    "voice": "joy",
    "input": "Γεια σου",
    "response_format": "wav"
  }' \
  --output speech.wav
```

MP3 output is supported when `ffmpeg` is installed:

```json
{
  "model": "piper-el_GR-joy-medium",
  "voice": "joy",
  "input": "Γεια σου",
  "response_format": "mp3"
}
```

`instructions` is accepted for OpenAI compatibility but ignored by Piper.

## Ubuntu Install

Copy this project to the Ubuntu server, then run:

```bash
chmod +x scripts/*.sh
VOICE=el_GR-joy-medium ./scripts/install_ubuntu.sh
```

Alternative Greek voices:

```bash
VOICE=el_GR-rapunzelina-medium ./scripts/install_ubuntu.sh
VOICE=el_GR-rapunzelina-low ./scripts/install_ubuntu.sh
```

The installer:

1. Installs Python, nginx, ffmpeg, and curl.
2. Creates a `piperapi` system user.
3. Copies the app to `/opt/piper-openai-api`.
4. Creates a Python virtualenv and installs `piper-tts`.
5. Downloads Piper voice files to `/opt/piper/models`.
6. Installs and starts `piper-openai-api.service`.
7. Configures nginx as a reverse proxy on port 80.

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
TTS_MODEL=piper-el_GR-joy-medium
TTS_VOICE=joy
TTS_RESPONSE_FORMAT=wav
```

## Notes

- `POST /v1/audio/speech` returns `audio/wav` or `audio/mpeg`.
- `GET /v1/models` returns a minimal OpenAI-style model list.
- Auth defaults to `Authorization: Bearer local-dev-key`.
- Set `PIPER_API_KEY=` empty in `/opt/piper-openai-api/.env` to disable auth inside a trusted LAN.

Sources checked:

- Piper voices are published in [`rhasspy/piper-voices`](https://huggingface.co/rhasspy/piper-voices/blob/main/voices.json).
- The upstream Piper voice list is in [`rhasspy/piper/VOICES.md`](https://github.com/rhasspy/piper/blob/master/VOICES.md).
- The Python package used here is [`piper-tts`](https://pypi.org/project/piper-tts/), currently pinned to `1.6.0`.
