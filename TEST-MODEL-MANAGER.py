#!/usr/bin/env python3
"""Offline tests for the Whisper model manager. No network or model download."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HELPER_PATH = Path(__file__).with_name("WHISPER-MODEL-MANAGER.py")
SPEC = importlib.util.spec_from_file_location("localai_whisper_manager", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load helper: {HELPER_PATH}")
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


def create_valid_model(folder: Path) -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    config = {
        "lang_ids": [50259, 50260],
        "suppress_ids": [1, 2],
        "suppress_ids_begin": [220, 50257],
        "alignment_heads": [[3, 1]],
    }
    (folder / "config.json").write_text(json.dumps(config), encoding="utf-8")
    tokenizer = {"model": {"type": "BPE", "vocab": {}, "merges": []}}
    (folder / "tokenizer.json").write_text(
        json.dumps(tokenizer) + (" " * 1_000_000), encoding="utf-8"
    )
    (folder / "vocabulary.txt").write_text("token\n" * 20_000, encoding="utf-8")
    with (folder / "model.bin").open("wb") as stream:
        stream.seek(HELPER.MINIMUM_FILE_SIZES["model.bin"] - 1)
        stream.write(b"\0")
    return folder


class WhisperManagerTests(unittest.TestCase):
    def test_accepts_faster_whisper_ctranslate2_config(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = create_valid_model(Path(temp) / "model")
            valid, detail = HELPER.validate_model_directory(folder)
            self.assertTrue(valid, detail)

    def test_rejects_transformers_style_config(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = create_valid_model(Path(temp) / "model")
            (folder / "config.json").write_text(
                json.dumps({"model_type": "whisper", "num_mel_bins": 80}),
                encoding="utf-8",
            )
            valid, detail = HELPER.validate_model_directory(folder)
            self.assertFalse(valid)
            self.assertIn("lang_ids", detail)

    def test_reuses_local_model_folder_without_downloader(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            cache = create_valid_model(root / "cache")
            target = root / "data" / "whisper" / "models"

            def unexpected_downloader(*args, **kwargs):
                raise AssertionError("valid local model must not trigger download")

            installed, source = HELPER.ensure_model(
                "Systran/faster-whisper-base",
                target,
                cache_roots=[cache],
                downloader=unexpected_downloader,
            )
            self.assertTrue(HELPER.validate_model_directory(installed)[0])
            self.assertIn("validated local model folder", source)

    def test_downloads_to_staging_and_preserves_incomplete_target(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "data" / "whisper" / "models"
            target.mkdir(parents=True)
            (target / "partial-download.bin").write_bytes(b"partial")
            empty_cache = root / "empty-cache"
            empty_cache.mkdir()
            calls = []

            def fake_downloader(model_id, output_dir=None, local_files_only=False, cache_dir=None):
                calls.append((model_id, output_dir, local_files_only, cache_dir))
                if local_files_only:
                    raise FileNotFoundError("not cached")
                return str(create_valid_model(Path(output_dir)))

            installed, source = HELPER.ensure_model(
                "Systran/faster-whisper-base",
                target,
                cache_roots=[empty_cache],
                downloader=fake_downloader,
            )
            self.assertTrue(HELPER.validate_model_directory(installed)[0])
            self.assertIn("downloaded and validated", source)
            self.assertTrue(list(target.parent.glob("models.incomplete-backup-*")))
            self.assertEqual(len(calls), 2)
            self.assertTrue(calls[0][2])
            self.assertFalse(calls[1][2])

    def test_rejects_missing_model_files(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "partial"
            folder.mkdir()
            (folder / "config.json").write_text('{"lang_ids":[]}', encoding="utf-8")
            valid, detail = HELPER.validate_model_directory(folder)
            self.assertFalse(valid)
            self.assertIn("required file is missing", detail)


if __name__ == "__main__":
    unittest.main(verbosity=2)
