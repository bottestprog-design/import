#!/usr/bin/env python3
"""Reliable Whisper Base provisioning for LocalAI Studio.

This helper avoids PowerShell multi-line native argument quoting. It validates
the CTranslate2 layout used by faster-whisper, reuses local caches first, and
installs a model only after its files and configuration pass validation.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile
import time
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
    """Validate model data without loading the model weights into RAM."""
    folder = Path(folder)
    if not folder.is_dir():
        return False, "directory does not exist"
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
        value = config.get(key)
        if not isinstance(value, list) or not value:
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
    return True, "valid multilingual CTranslate2 Whisper model"


def _get_downloader() -> Callable:
    try:
        from faster_whisper.utils import download_model
    except Exception as exc:
        raise RuntimeError(
            "faster-whisper is not importable in the project Python environment: "
            f"{type(exc).__name__}: {exc}"
        ) from exc
    return download_model


def _copy_model_contents(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for filename in REQUIRED_FILES + ("preprocessor_config.json",):
        source_file = source / filename
        if source_file.is_file():
            shutil.copy2(source_file, destination / filename)


def _install_stage(stage: Path, target: Path) -> Path:
    valid, reason = validate_model_directory(stage)
    if not valid:
        raise RuntimeError(f"staged model failed validation: {reason}")
    backup: Path | None = None
    if target.exists():
        stamp = time.strftime("%Y%m%d-%H%M%S")
        backup = target.with_name(f"{target.name}.incomplete-backup-{stamp}")
        suffix = 1
        while backup.exists():
            backup = target.with_name(f"{target.name}.incomplete-backup-{stamp}-{suffix}")
            suffix += 1
        target.rename(backup)
    try:
        stage.rename(target)
    except Exception:
        if backup is not None and backup.exists() and not target.exists():
            backup.rename(target)
        raise
    if backup is not None:
        print(f"[MODEL] Preserved the previous incomplete folder at: {backup}", flush=True)
    return target


def ensure_model(
    model_id: str,
    output_dir: Path,
    cache_roots: list[Path] | None = None,
    auto_download: bool = True,
    downloader: Callable | None = None,
) -> tuple[Path, str]:
    """Reuse a verified target/cache, otherwise download into a staging folder."""
    target = Path(output_dir).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    valid, _ = validate_model_directory(target)
    if valid:
        return target, "already present in the configured model directory"

    downloader = downloader or _get_downloader()
    errors: list[str] = []
    seen: set[str] = set()
    for raw_root in cache_roots or []:
        if not str(raw_root).strip():
            continue
        root = Path(raw_root).expanduser()
        key = str(root.resolve()).casefold()
        if key in seen or key == str(target).casefold():
            continue
        seen.add(key)
        if not root.exists():
            continue

        cached_valid, _ = validate_model_directory(root)
        if cached_valid:
            stage = Path(tempfile.mkdtemp(prefix=f".{target.name}.stage-", dir=target.parent))
            try:
                _copy_model_contents(root, stage)
                installed = _install_stage(stage, target)
                stage = None
                return installed, f"reused the validated local model folder: {root}"
            finally:
                if stage is not None and stage.exists():
                    shutil.rmtree(stage, ignore_errors=True)

        try:
            cached_path = Path(downloader(model_id, cache_dir=str(root), local_files_only=True))
            cached_valid, cached_reason = validate_model_directory(cached_path)
            if not cached_valid:
                errors.append(f"{root}: cached snapshot invalid ({cached_reason})")
                continue
            stage = Path(tempfile.mkdtemp(prefix=f".{target.name}.stage-", dir=target.parent))
            try:
                _copy_model_contents(cached_path, stage)
                installed = _install_stage(stage, target)
                stage = None
                return installed, f"reused a Hugging Face cache snapshot: {cached_path}"
            finally:
                if stage is not None and stage.exists():
                    shutil.rmtree(stage, ignore_errors=True)
        except Exception as exc:
            errors.append(f"{root}: {type(exc).__name__}: {exc}")

    if not auto_download:
        detail = "; ".join(errors[-4:]) if errors else "no configured local cache contained this model"
        raise RuntimeError(f"Whisper model is missing and auto-download is disabled. {detail}")

    stage = Path(tempfile.mkdtemp(prefix=f".{target.name}.download-", dir=target.parent))
    try:
        print(f"[MODEL] No valid local Whisper model found. Downloading {model_id}...", flush=True)
        downloaded_path = Path(downloader(model_id, output_dir=str(stage), local_files_only=False))
        downloaded_valid, downloaded_reason = validate_model_directory(downloaded_path)
        if not downloaded_valid:
            raise RuntimeError(f"download result failed validation: {downloaded_reason}")
        if downloaded_path.resolve() != stage.resolve():
            _copy_model_contents(downloaded_path, stage)
        installed = _install_stage(stage, target)
        stage = None
        return installed, f"downloaded and validated from Hugging Face: {model_id}"
    except Exception as exc:
        cache_detail = "; ".join(errors[-3:]) if errors else "no usable local cache"
        raise RuntimeError(
            f"could not provision Whisper model {model_id}: {type(exc).__name__}: {exc}. "
            f"Local cache search: {cache_detail}"
        ) from exc
    finally:
        if stage is not None and stage.exists():
            shutil.rmtree(stage, ignore_errors=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Find, validate and provision a faster-whisper model.")
    parser.add_argument("--model-id", required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--cache-root", action="append", default=[])
    parser.add_argument("--no-download", action="store_true")
    args = parser.parse_args(argv)
    try:
        path, source = ensure_model(
            model_id=args.model_id,
            output_dir=args.output_dir,
            cache_roots=[Path(item) for item in args.cache_root],
            auto_download=not args.no_download,
        )
        print(f"WHISPER_READY={path}")
        print(f"WHISPER_SOURCE={source}")
        return 0
    except Exception as exc:
        print(f"WHISPER_FAILED={type(exc).__name__}: {exc}", file=sys.stderr)
        return 10


if __name__ == "__main__":
    raise SystemExit(main())
