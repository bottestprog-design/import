#!/usr/bin/env python3
"""Provision a faster-whisper model in the Hugging Face cache used by Open WebUI.

Open WebUI 0.13.5 calls faster_whisper.WhisperModel(model_size_or_path,
download_root=WHISPER_MODEL_DIR, local_files_only=...). Therefore this manager
keeps WHISPER_MODEL as the configured model alias (for example, "base") and
places a valid Hugging Face snapshot in a cache root passed as download_root.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Callable

REQUIRED_FILES = ("config.json", "model.bin", "tokenizer.json", "vocabulary.txt")
MINIMUM_FILE_SIZES = {
    "config.json": 500,
    "model.bin": 100_000_000,
    "tokenizer.json": 1_000_000,
    "vocabulary.txt": 100_000,
}
CT2_CONFIG_KEYS = ("lang_ids", "suppress_ids", "suppress_ids_begin")


def validate_model_directory(folder: Path) -> tuple[bool, str]:
    """Validate a CTranslate2 snapshot without loading weights into memory."""
    folder = Path(folder)
    if not folder.is_dir():
        return False, "snapshot directory does not exist"
    for filename in REQUIRED_FILES:
        path = folder / filename
        if not path.is_file():
            return False, f"required file is missing: {filename}"
        minimum = MINIMUM_FILE_SIZES[filename]
        size = path.stat().st_size
        if size < minimum:
            return False, f"{filename} is incomplete ({size} bytes; expected at least {minimum})"

    try:
        config = json.loads((folder / "config.json").read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return False, f"config.json is not valid JSON: {exc}"
    if not isinstance(config, dict):
        return False, "config.json root must be a JSON object"
    for key in CT2_CONFIG_KEYS:
        if not isinstance(config.get(key), list) or not config[key]:
            return False, f"config.json is missing a non-empty CTranslate2 field: {key}"

    try:
        tokenizer = json.loads((folder / "tokenizer.json").read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return False, f"tokenizer.json is not valid JSON: {exc}"
    if not isinstance(tokenizer, dict) or not isinstance(tokenizer.get("model"), dict):
        return False, "tokenizer.json does not contain a tokenizer model object"

    try:
        with (folder / "vocabulary.txt").open("r", encoding="utf-8") as stream:
            if not stream.readline():
                return False, "vocabulary.txt is empty"
    except (OSError, UnicodeError) as exc:
        return False, f"vocabulary.txt cannot be read: {exc}"
    return True, "valid multilingual CTranslate2 Whisper snapshot"


def _get_downloader() -> Callable:
    try:
        from faster_whisper.utils import download_model
    except Exception as exc:
        raise RuntimeError(
            "faster-whisper is not importable in the project Python environment: "
            f"{type(exc).__name__}: {exc}"
        ) from exc
    return download_model


def _try_cached_snapshot(
    model_id: str,
    cache_root: Path,
    downloader: Callable,
) -> tuple[Path | None, str]:
    try:
        snapshot = Path(
            downloader(
                model_id,
                cache_dir=str(cache_root),
                local_files_only=True,
            )
        ).resolve()
    except Exception as exc:
        return None, f"{type(exc).__name__}: {exc}"

    valid, detail = validate_model_directory(snapshot)
    if not valid:
        return None, detail
    return snapshot, "valid cached Hugging Face snapshot"


def ensure_model(
    model_id: str,
    cache_dir: Path,
    cache_roots: list[Path] | None = None,
    auto_download: bool = True,
    downloader: Callable | None = None,
) -> tuple[Path, Path, str]:
    """Return (snapshot_path, cache_root, source) compatible with download_root."""
    target_cache = Path(cache_dir).expanduser().resolve()
    target_cache.mkdir(parents=True, exist_ok=True)
    downloader = downloader or _get_downloader()

    roots: list[Path] = [target_cache]
    seen = {str(target_cache).casefold()}
    for raw_root in cache_roots or []:
        if not str(raw_root).strip():
            continue
        root = Path(raw_root).expanduser()
        key = str(root.resolve()).casefold()
        if key in seen:
            continue
        seen.add(key)
        roots.append(root)

    errors: list[str] = []
    for root in roots:
        if not root.is_dir():
            continue
        snapshot, detail = _try_cached_snapshot(model_id, root, downloader)
        if snapshot is not None:
            source = "already present in the configured Whisper cache" if root == target_cache else f"reused local Hugging Face cache: {root}"
            return snapshot, root.resolve(), source
        errors.append(f"{root}: {detail}")

    if not auto_download:
        detail = "; ".join(errors[-4:]) if errors else "no configured local cache contains this model"
        raise RuntimeError(f"Whisper model is missing and automatic download is disabled. {detail}")

    print(f"[MODEL] No valid local Whisper snapshot found. Downloading {model_id} into {target_cache}...", flush=True)
    try:
        snapshot = Path(
            downloader(
                model_id,
                cache_dir=str(target_cache),
                local_files_only=False,
            )
        ).resolve()
        valid, detail = validate_model_directory(snapshot)
        if not valid:
            raise RuntimeError(f"downloaded snapshot failed validation: {detail}")
        return snapshot, target_cache, f"downloaded and validated Hugging Face cache snapshot: {model_id}"
    except Exception as exc:
        cache_detail = "; ".join(errors[-3:]) if errors else "no usable local cache"
        raise RuntimeError(
            f"could not provision Whisper model {model_id}: {type(exc).__name__}: {exc}. "
            f"Local cache search: {cache_detail}"
        ) from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Find, validate and provision a faster-whisper cache snapshot.")
    parser.add_argument("--model-id", required=True, help="faster-whisper model alias, e.g. base")
    parser.add_argument("--cache-dir", required=True, type=Path, help="Open WebUI WHISPER_MODEL_DIR")
    parser.add_argument("--cache-root", action="append", default=[])
    parser.add_argument("--no-download", action="store_true")
    args = parser.parse_args(argv)

    try:
        snapshot, cache_root, source = ensure_model(
            model_id=args.model_id,
            cache_dir=args.cache_dir,
            cache_roots=[Path(item) for item in args.cache_root],
            auto_download=not args.no_download,
        )
        print(f"WHISPER_READY={snapshot}")
        print(f"WHISPER_CACHE_DIR={cache_root}")
        print(f"WHISPER_SOURCE={source}")
        return 0
    except Exception as exc:
        print(f"WHISPER_FAILED={type(exc).__name__}: {exc}", file=sys.stderr)
        return 10


if __name__ == "__main__":
    raise SystemExit(main())
