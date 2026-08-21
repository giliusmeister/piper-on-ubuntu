from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, Response
from pydantic import BaseModel, Field


DEFAULT_MODEL_ID = "piper-el_GR-joy-medium"
DEFAULT_MODEL_PATH = "/opt/piper/models/el_GR-joy-medium.onnx"
DEFAULT_CONFIG_PATH = "/opt/piper/models/el_GR-joy-medium.onnx.json"


class SpeechRequest(BaseModel):
    model: str = Field(default=DEFAULT_MODEL_ID)
    voice: str | None = Field(default=None)
    input: str = Field(min_length=1, max_length=5000)
    instructions: str | None = None
    response_format: str = Field(default="wav")
    speed: float | None = Field(default=None, gt=0.25, le=4.0)


app = FastAPI(
    title="Local Piper OpenAI-compatible TTS API",
    version="0.1.0",
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


def _model_path() -> Path:
    return Path(os.getenv("PIPER_MODEL_PATH", DEFAULT_MODEL_PATH))


def _config_path() -> Path:
    return Path(os.getenv("PIPER_CONFIG_PATH", DEFAULT_CONFIG_PATH))


def _model_id() -> str:
    return os.getenv("PIPER_MODEL_ID", DEFAULT_MODEL_ID)


def _piper_bin() -> str:
    return os.getenv("PIPER_BIN", "piper")


def _ffmpeg_bin() -> str:
    return os.getenv("FFMPEG_BIN", "ffmpeg")


@app.get("/health")
def health() -> dict[str, object]:
    model_path = _model_path()
    config_path = _config_path()
    return {
        "ok": model_path.exists() and config_path.exists(),
        "model": _model_id(),
        "model_path": str(model_path),
        "config_path": str(config_path),
        "piper": shutil.which(_piper_bin()) is not None,
        "ffmpeg": shutil.which(_ffmpeg_bin()) is not None,
    }


@app.get("/v1/models", dependencies=[Depends(require_auth)])
def models() -> dict[str, object]:
    model_id = _model_id()
    return {
        "object": "list",
        "data": [
            {
                "id": model_id,
                "object": "model",
                "owned_by": "local-piper",
            }
        ],
    }


@app.post("/v1/audio/speech", dependencies=[Depends(require_auth)])
def speech(payload: SpeechRequest) -> Response:
    model_id = _model_id()
    if payload.model not in {model_id, DEFAULT_MODEL_ID, "tts-1", "gpt-4o-mini-tts"}:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported model '{payload.model}'. Use '{model_id}'.",
        )

    response_format = payload.response_format.lower()
    if response_format not in {"wav", "mp3"}:
        raise HTTPException(status_code=400, detail="response_format must be 'wav' or 'mp3'")

    model_path = _model_path()
    config_path = _config_path()
    if not model_path.exists() or not config_path.exists():
        raise HTTPException(status_code=503, detail="Piper model files are missing")

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
