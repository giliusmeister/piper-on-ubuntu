from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, FastAPI, Header, HTTPException, Response
from pydantic import BaseModel, Field


MODEL_DIR = Path(os.getenv("PIPER_MODEL_DIR", "/opt/piper/models"))
VOICE_MAP_PATH = Path(
    os.getenv("PIPER_VOICE_MAP_PATH", str(MODEL_DIR / "openlingo_voices.json"))
)
DEFAULT_LANGUAGE = os.getenv("PIPER_DEFAULT_LANGUAGE", "el")
DEFAULT_MODEL_ID = "piper-el_GR-joy-medium"
DEFAULT_MODEL_PATH = "/opt/piper/models/el_GR-joy-medium.onnx"
DEFAULT_CONFIG_PATH = "/opt/piper/models/el_GR-joy-medium.onnx.json"
OPENAI_COMPAT_MODELS = {"piper-auto", "tts-1", "gpt-4o-mini-tts"}
OPENAI_VOICE_ALIASES = {
    "alloy",
    "ash",
    "ballad",
    "coral",
    "echo",
    "fable",
    "nova",
    "onyx",
    "sage",
    "shimmer",
}
LANGUAGE_ALIASES = {
    "en": ("en", "english"),
    "es": ("es", "spanish", "espanol", "español"),
    "de": ("de", "german", "deutsch"),
    "fr": ("fr", "french", "francais", "français"),
    "it": ("it", "italian", "italiano"),
    "pt": ("pt", "portuguese", "portugues", "português"),
    "ru": ("ru", "russian", "русский"),
    "ar": ("ar", "arabic", "العربية"),
    "hi": ("hi", "hindi", "हिन्दी", "हिंदी"),
    "ko": ("ko", "korean", "한국어"),
    "zh": ("zh", "chinese", "mandarin", "中文", "普通话"),
    "ja": ("ja", "japanese", "日本語"),
    "el": ("el", "greek", "ελληνικά", "ελληνικα"),
}

FALLBACK_VOICES: dict[str, dict[str, str]] = {
    "el": {
        "openlingo_code": "el",
        "key": "el_GR-joy-medium",
        "name": "joy",
        "quality": "medium",
        "language_code": "el_GR",
        "language_name": "Greek",
        "model_path": DEFAULT_MODEL_PATH,
        "config_path": DEFAULT_CONFIG_PATH,
    }
}


class SpeechRequest(BaseModel):
    model: str = Field(default="piper-auto")
    voice: str | None = Field(default=None)
    input: str = Field(min_length=1, max_length=5000)
    instructions: str | None = None
    response_format: str = Field(default="wav")
    language: str | None = Field(default=None)
    speed: float | None = Field(default=None, gt=0.25, le=4.0)


app = FastAPI(
    title="Local Piper OpenAI-compatible TTS API",
    version="0.2.0",
)


def _api_key() -> str | None:
    key = os.getenv("PIPER_API_KEY", "local-dev-key").strip()
    return key or None


def require_auth(authorization: Annotated[str | None, Header()] = None) -> None:
    expected = _api_key()
    if expected is None:
        return

    if authorization != f"Bearer {expected}":
        raise HTTPException(status_code=401, detail="Invalid API key")


def _piper_bin() -> str:
    return os.getenv("PIPER_BIN", "piper")


def _ffmpeg_bin() -> str:
    return os.getenv("FFMPEG_BIN", "ffmpeg")


def _load_voice_map() -> dict[str, dict[str, str]]:
    if VOICE_MAP_PATH.exists():
        data = json.loads(VOICE_MAP_PATH.read_text(encoding="utf-8"))
        return data.get("voices", data)

    return FALLBACK_VOICES


def _voice_to_model(voice: dict[str, str]) -> dict[str, str]:
    key = voice["key"]
    return {
        "id": f"piper-{key}",
        "object": "model",
        "owned_by": "local-piper",
        "language": voice.get("openlingo_code"),
        "voice": voice.get("name"),
        "piper_key": key,
    }


def _matches_voice(candidate: str, openlingo_code: str, voice: dict[str, str]) -> bool:
    normalized = candidate.strip()
    if not normalized:
        return False

    aliases = {
        openlingo_code,
        voice.get("name", ""),
        voice["key"],
        f"piper-{voice['key']}",
        voice.get("language_code", ""),
    }
    return normalized in aliases


def _language_from_instructions(instructions: str | None, voices: dict[str, dict[str, str]]) -> str | None:
    if not instructions:
        return None

    normalized = instructions.lower()
    for openlingo_code, aliases in LANGUAGE_ALIASES.items():
        if openlingo_code not in voices:
            continue
        if any(_contains_language_alias(normalized, alias.lower()) for alias in aliases):
            return openlingo_code

    return None


def _contains_language_alias(text: str, alias: str) -> bool:
    if alias.isascii() and len(alias) <= 3:
        return re.search(rf"(?<![a-z]){re.escape(alias)}(?![a-z])", text) is not None

    return alias in text


def _resolve_voice(payload: SpeechRequest) -> dict[str, str]:
    voices = _load_voice_map()
    generic_model = payload.model in OPENAI_COMPAT_MODELS
    openai_compat_voice = generic_model and payload.voice in OPENAI_VOICE_ALIASES

    selectors = [
        payload.language,
        None if openai_compat_voice else payload.voice,
        _language_from_instructions(payload.instructions, voices),
        None if generic_model else payload.model,
    ]

    for selector in selectors:
        if selector is None:
            continue

        for openlingo_code, voice in voices.items():
            if _matches_voice(selector, openlingo_code, voice):
                return voice

    if payload.language or (payload.voice and not openai_compat_voice) or not generic_model:
        supported = ", ".join(sorted(voices.keys()))
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported language/voice/model. Supported OpenLingo codes: {supported}",
        )

    if DEFAULT_LANGUAGE in voices:
        return voices[DEFAULT_LANGUAGE]

    supported = ", ".join(sorted(voices.keys()))
    raise HTTPException(
        status_code=400,
        detail=f"Unsupported language/voice/model. Supported OpenLingo codes: {supported}",
    )


def _voice_status(voice: dict[str, str]) -> dict[str, Any]:
    model_path = Path(voice["model_path"])
    config_path = Path(voice["config_path"])
    return {
        "key": voice["key"],
        "name": voice.get("name"),
        "language_code": voice.get("language_code"),
        "model_id": f"piper-{voice['key']}",
        "model_path": str(model_path),
        "config_path": str(config_path),
        "installed": model_path.exists() and config_path.exists(),
    }


@app.get("/health")
def health() -> dict[str, object]:
    voices = _load_voice_map()
    voice_status = {code: _voice_status(voice) for code, voice in voices.items()}
    return {
        "ok": all(item["installed"] for item in voice_status.values()),
        "default_language": DEFAULT_LANGUAGE,
        "voice_map_path": str(VOICE_MAP_PATH),
        "voices": voice_status,
        "piper": shutil.which(_piper_bin()) is not None,
        "ffmpeg": shutil.which(_ffmpeg_bin()) is not None,
    }


@app.get("/v1/models", dependencies=[Depends(require_auth)])
def models() -> dict[str, object]:
    return {
        "object": "list",
        "data": [_voice_to_model(voice) for voice in _load_voice_map().values()],
    }


@app.post("/v1/audio/speech", dependencies=[Depends(require_auth)])
def speech(payload: SpeechRequest) -> Response:
    voice = _resolve_voice(payload)
    response_format = payload.response_format.lower()
    if response_format not in {"wav", "mp3"}:
        raise HTTPException(status_code=400, detail="response_format must be 'wav' or 'mp3'")

    model_path = Path(voice["model_path"])
    config_path = Path(voice["config_path"])
    if not model_path.exists() or not config_path.exists():
        raise HTTPException(
            status_code=503,
            detail=f"Piper model files are missing for {voice['key']}",
        )

    with tempfile.TemporaryDirectory(prefix="piper-tts-") as tmpdir:
        wav_path = Path(tmpdir) / "speech.wav"

        command = [
            _piper_bin(),
            "--model",
            str(model_path),
            "--config",
            str(config_path),
            "--output_file",
            str(wav_path),
        ]

        try:
            subprocess.run(
                command,
                input=payload.input,
                text=True,
                check=True,
                capture_output=True,
                timeout=int(os.getenv("PIPER_TIMEOUT_SECONDS", "60")),
            )
        except FileNotFoundError as exc:
            raise HTTPException(status_code=503, detail="Piper binary was not found") from exc
        except subprocess.TimeoutExpired as exc:
            raise HTTPException(status_code=504, detail="Piper synthesis timed out") from exc
        except subprocess.CalledProcessError as exc:
            detail = exc.stderr.strip() or exc.stdout.strip() or "Piper synthesis failed"
            raise HTTPException(status_code=500, detail=detail) from exc

        if response_format == "wav":
            return Response(content=wav_path.read_bytes(), media_type="audio/wav")

        mp3_path = Path(tmpdir) / "speech.mp3"
        try:
            subprocess.run(
                [
                    _ffmpeg_bin(),
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-y",
                    "-i",
                    str(wav_path),
                    "-codec:a",
                    "libmp3lame",
                    "-q:a",
                    "4",
                    str(mp3_path),
                ],
                check=True,
                capture_output=True,
                timeout=30,
            )
        except FileNotFoundError as exc:
            raise HTTPException(status_code=503, detail="ffmpeg is required for mp3 output") from exc
        except subprocess.CalledProcessError as exc:
            detail = exc.stderr.decode("utf-8", errors="replace").strip() or "ffmpeg failed"
            raise HTTPException(status_code=500, detail=detail) from exc

        return Response(content=mp3_path.read_bytes(), media_type="audio/mpeg")
