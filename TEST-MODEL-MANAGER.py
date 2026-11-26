#!/usr/bin/env python3
"""Offline tests for the Whisper cache manager. No network or model download."""
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
    (folder / "config.json").write_text(json.dumps(config) + (" " * 500), encoding="utf-8")
    tokenizer = {"model": {"type": "BPE", "vocab": {}, "merges": []}}
    (folder / "tokenizer.json").write_text(
        json.dumps(tokenizer) + (" " * 1_000_000), encoding="utf-8"
    )
    (folder / "vocabulary.txt").write_text("token\n" * 20_000, encoding="utf-8")
    with (folder / "model.bin").open("wb") as stream:
        stream.seek(HELPER.MINIMUM_FILE_SIZES["model.bin"] - 1)
        stream.write(b"\0")
    return folder


def cache_snapshot(root: Path) -> Path:
    return create_valid_model(
        root / "models--Systran--faster-whisper-base" / "snapshots" / "test-commit"
    )


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
                json.dumps({"model_type": "whisper", "num_mel_bins": 80}) + (" " * 500),
                encoding="utf-8",
            )
            valid, detail = HELPER.validate_model_directory(folder)
            self.assertFalse(valid)
            self.assertIn("lang_ids", detail)

    def test_reuses_configured_huggingface_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            cache = root / "configured-cache"
            snapshot = cache_snapshot(cache)

            def fake_downloader(model_id, cache_dir=None, local_files_only=False):
                self.assertEqual(model_id, "base")
                self.assertEqual(Path(cache_dir), cache.resolve())
                self.assertTrue(local_files_only)
                return str(snapshot)

            found, selected_cache, source = HELPER.ensure_model(
                "base", cache, downloader=fake_downloader
            )
            self.assertEqual(found, snapshot.resolve())
            self.assertEqual(selected_cache, cache.resolve())
            self.assertIn("configured Whisper cache", source)

    def test_reuses_another_local_huggingface_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            configured = root / "configured"
            external = root / "old-hf-cache"
            snapshot = cache_snapshot(external)
            calls = []

            def fake_downloader(model_id, cache_dir=None, local_files_only=False):
                calls.append((Path(cache_dir), local_files_only))
                if Path(cache_dir) == external and local_files_only:
                    return str(snapshot)
                raise FileNotFoundError("not in this cache")

            found, selected_cache, source = HELPER.ensure_model(
                "base", configured, cache_roots=[external], downloader=fake_downloader
            )
            self.assertEqual(found, snapshot.resolve())
            self.assertEqual(selected_cache, external.resolve())
            self.assertIn("reused local Hugging Face cache", source)
            self.assertEqual(len(calls), 2)

    def test_downloads_into_the_open_webui_cache_root(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            cache = root / "configured-cache"
            calls = []

            def fake_downloader(model_id, cache_dir=None, local_files_only=False):
                calls.append((model_id, Path(cache_dir), local_files_only))
                if local_files_only:
                    raise FileNotFoundError("not in cache")
                return str(cache_snapshot(Path(cache_dir)))

            found, selected_cache, source = HELPER.ensure_model(
                "base", cache, downloader=fake_downloader
            )
            self.assertTrue(HELPER.validate_model_directory(found)[0])
            self.assertEqual(selected_cache, cache.resolve())
            self.assertIn("downloaded and validated", source)
            self.assertEqual(calls[-1], ("base", cache.resolve(), False))
            self.assertTrue(cache.exists())

    def test_rejects_missing_model_files(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "partial"
            folder.mkdir()
            (folder / "config.json").write_text('{"lang_ids":[]}' + (" " * 500), encoding="utf-8")
            valid, detail = HELPER.validate_model_directory(folder)
            self.assertFalse(valid)
            self.assertIn("required file is missing", detail)


if __name__ == "__main__":
    unittest.main(verbosity=2)
