#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path


BASE_URL = "https://huggingface.co/rhasspy/piper-voices/resolve/main"
VOICES_JSON_URL = "https://huggingface.co/rhasspy/piper-voices/raw/main/voices.json"
OPENLINGO_LANGUAGES = ("en", "es", "de", "fr", "it", "pt", "ru", "ar", "hi", "ko", "zh", "ja", "el")

PREFERRED_KEYS = {
    "en": "en_US-joe-medium",
    "es": "es_ES-davefx-medium",
    "de": "de_DE-thorsten-medium",
    "fr": "fr_FR-siwis-medium",
    "it": "it_IT-paola-medium",
    "pt": "pt_BR-faber-medium",
    "ru": "ru_RU-irina-medium",
    "ar": "ar_JO-kareem-medium",
    "hi": "hi_IN-pratham-medium",
    "ko": "ko_KR-kss-medium",
    "zh": "zh_CN-huayan-medium",
    "el": "el_GR-joy-medium",
}

QUALITY_ORDER = {"medium": 0, "high": 1, "low": 2, "x_low": 3}


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def find_voice(registry: dict, language: str, requested_key: str | None = None) -> dict:
    if requested_key:
        if requested_key not in registry:
            raise KeyError(f"Voice key not found in registry: {requested_key}")
        return registry[requested_key]

    preferred_key = PREFERRED_KEYS.get(language)
    if preferred_key and preferred_key in registry:
        return registry[preferred_key]

    candidates = [
        voice
        for voice in registry.values()
        if voice.get("language", {}).get("family") == language
    ]
    if not candidates:
        raise KeyError(f"No Piper voice found for OpenLingo language: {language}")

    return sorted(
        candidates,
        key=lambda voice: (
            QUALITY_ORDER.get(voice.get("quality", ""), 99),
            voice.get("key", ""),
        ),
    )[0]


def voice_files(voice: dict) -> tuple[str, str]:
    paths = sorted(voice["files"].keys())
    model = next(path for path in paths if path.endswith(".onnx"))
    config = next(path for path in paths if path.endswith(".onnx.json"))
    return model, config


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {destination.name}")
    urllib.request.urlretrieve(url, destination)


def parse_voice_override(value: str) -> tuple[str, str]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("Voice override must look like lang=voice_key")
    language, key = value.split("=", 1)
    return language.strip(), key.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", default="/opt/piper/models")
    parser.add_argument("--voice-map", default=None)
    parser.add_argument("--language", action="append", choices=OPENLINGO_LANGUAGES)
    parser.add_argument("--voice", action="append", type=parse_voice_override, default=[])
    parser.add_argument("--registry-url", default=VOICES_JSON_URL)
    parser.add_argument("--base-url", default=BASE_URL)
    args = parser.parse_args()

    model_dir = Path(args.model_dir)
    voice_map_path = Path(args.voice_map) if args.voice_map else model_dir / "openlingo_voices.json"
    selected_languages = tuple(args.language or OPENLINGO_LANGUAGES)
    overrides = dict(args.voice)

    registry = fetch_json(args.registry_url)
    voice_map = {"voices": {}}

    for language in selected_languages:
        voice = find_voice(registry, language, overrides.get(language))
        model_file, config_file = voice_files(voice)
        model_destination = model_dir / Path(model_file).name
        config_destination = model_dir / Path(config_file).name

        if not model_destination.exists():
            download(f"{args.base_url}/{model_file}", model_destination)
        if not config_destination.exists():
            download(f"{args.base_url}/{config_file}", config_destination)

        voice_map["voices"][language] = {
            "openlingo_code": language,
            "key": voice["key"],
            "name": voice["name"],
            "quality": voice["quality"],
            "language_code": voice["language"]["code"],
            "language_name": voice["language"]["name_english"],
            "model_path": str(model_destination),
            "config_path": str(config_destination),
        }

    voice_map_path.write_text(
        json.dumps(voice_map, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {voice_map_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
