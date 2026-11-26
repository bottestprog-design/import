#!/usr/bin/env python3
"""Offline smoke tests for the bundled Open WebUI filters. No network calls."""
from __future__ import annotations

import argparse
import asyncio
import importlib.util
import json
from pathlib import Path
import sys


def load_filter(path: Path, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load filter: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)
    print(f"[PASS] {message}")


async def run_tests(filters_dir: Path) -> None:
    guard_module = load_filter(filters_dir / "01-Trusted-Content-Guard.py", "local_filter_guard")
    quality_module = load_filter(filters_dir / "02-Accuracy-Thinking.py", "local_filter_quality")
    review_module = load_filter(filters_dir / "03-Selective-Self-Review.py", "local_filter_review")

    guard = guard_module.Filter()
    body = {"messages": [{"role": "user", "content": "حلل الملف"}]}
    body = await guard.inlet(body)
    check(any("LOCAL TRUSTED-CONTENT BOUNDARY:" in str(m.get("content", "")) for m in body["messages"]),
          "Guard filter inserts the untrusted-content boundary")
    count_before = len(body["messages"])
    body = await guard.request(body)
    check(len(body["messages"]) == count_before, "Guard filter is idempotent across request hops")

    quality = quality_module.Filter()
    request = {"model": "local-qwen35", "messages": [{"role": "user", "content": "مرحبا"}]}
    request = await quality.request(request)
    check(request.get("think") is True, "Qwen 3.5 thinking flag is JSON Boolean true")
    check(any("LOCAL ANSWER QUALITY RULES:" in str(m.get("content", "")) for m in request["messages"]),
          "Accuracy guidance is injected into the model context")
    other_request = {"model": "unrelated-model", "messages": []}
    other_request = await quality.request(other_request)
    check("think" not in other_request, "Thinking flag is not injected into unrelated models")
    wrapped_request = {"model": "my-workspace-assistant", "messages": []}
    wrapped_request = await quality.request(wrapped_request, __model__={"info": {"base_model_id": "local-qwen35:latest"}})
    check(wrapped_request.get("think") is True, "Thinking remains enabled when a workspace model wraps the local alias")
    base_request = {"model": "workspace-qwen", "messages": []}
    base_request = await quality.request(base_request, __model__={"info": {"base_model_id": "qwen3.5:9b-q4_K_M"}})
    check(base_request.get("think") is True, "Thinking is also enabled when a workspace reports the original Qwen 3.5 base ID")

    reviewer = review_module.Filter()
    reviewer._review_sync = lambda question, answer: "The result is 30. Verified: 6 × 5 = 30."  # offline test stub
    original = "The result is 30 based on the calculation."
    assistant_message = {
        "role": "assistant",
        "content": original,
        "finish_reason": "stop",
        "output": [{"type": "message", "content": [{"type": "output_text", "text": original}]}],
    }
    chat = {"messages": [{"role": "user", "content": "احسب 6 × 5 وراجع الناتج"}, assistant_message]}
    reviewed = await reviewer.outlet(chat)
    final_message = reviewed["messages"][1]
    check(final_message["content"].startswith("The result is 30. Verified"), "Reviewer replaces the visible assistant content")
    check(final_message["output"][0]["content"][0]["text"] == final_message["content"],
          "Reviewer updates Open WebUI output_text so the UI displays the revised answer")

    # A second-pass answer cut off by Ollama's token limit must be rejected.
    class _FakeResponse:
        def __init__(self, payload: bytes):
            self.payload = payload
        def __enter__(self):
            return self
        def __exit__(self, *args):
            return False
        def read(self):
            return self.payload

    original_urlopen = review_module.urllib.request.urlopen
    try:
        review_module.urllib.request.urlopen = lambda *args, **kwargs: _FakeResponse(
            b'{"done":true,"done_reason":"length","message":{"content":"partial review"}}'
        )
        rejected_review = review_module.Filter._review_sync(reviewer, "راجع الناتج", "A sufficiently long proposed answer for this reviewer test.")
        check(rejected_review == "", "Reviewer rejects its own output when Ollama reports a length cutoff")
    finally:
        review_module.urllib.request.urlopen = original_urlopen


    # The self-review pass must not request a hidden thinking-only response and
    # must stay within the 4K context budget of this 16GB CPU-only machine.
    captured_payload = {}
    class _CaptureResponse:
        def __enter__(self): return self
        def __exit__(self, *args): return False
        def read(self): return b'{"done":true,"done_reason":"stop","message":{"content":"A sufficiently long reviewed response."}}'
    def _capture_urlopen(request, timeout=None):
        captured_payload.update(json.loads(request.data.decode("utf-8")))
        return _CaptureResponse()
    original_urlopen = review_module.urllib.request.urlopen
    try:
        review_module.urllib.request.urlopen = _capture_urlopen
        review_module.Filter._review_sync(reviewer, "Review this", "A proposed answer long enough for the review smoke test.")
        check(captured_payload.get("think") is False, "Reviewer second pass requests visible content, not hidden thinking-only output")
        check(captured_payload.get("options", {}).get("num_ctx") == 4096, "Reviewer second pass stays within 4096 context")
    finally:
        review_module.urllib.request.urlopen = original_urlopen

    # A truncated reply must not be reviewed or replaced.
    reviewer._review_sync = lambda question, answer: "This should never run."
    truncated = {
        "messages": [
            {"role": "user", "content": "احسب 6 × 5"},
            {"role": "assistant", "content": "partial", "finish_reason": "length"},
        ]
    }
    before = truncated["messages"][1]["content"]
    after = await reviewer.outlet(truncated)
    check(after["messages"][1]["content"] == before, "Reviewer leaves truncated responses untouched")

    # An exception during the second pass must preserve the first answer.
    reviewer._review_sync = lambda question, answer: (_ for _ in ()).throw(RuntimeError("offline reviewer"))
    safe_body = {
        "messages": [
            {"role": "user", "content": "احسب 7 × 8 وراجع الناتج"},
            {"role": "assistant", "content": "The result is 56.", "finish_reason": "stop"},
        ]
    }
    safe_body_after = await reviewer.outlet(safe_body)
    check(safe_body_after["messages"][1]["content"] == "The result is 56.", "Reviewer fails open and preserves the original answer on errors")

    # A short ordinary greeting should not incur a second inference pass in smart mode.
    reviewer._review_sync = lambda question, answer: (_ for _ in ()).throw(AssertionError("review should not be called"))
    ordinary = {"messages": [{"role": "user", "content": "أهلا"}, {"role": "assistant", "content": "أهلًا بك!", "finish_reason": "stop"}]}
    ordinary_after = await reviewer.outlet(ordinary)
    check(ordinary_after["messages"][1]["content"] == "أهلًا بك!", "Smart reviewer skips ordinary short chat turns")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--filters-dir", type=Path, default=Path(__file__).resolve().parent / "Filters")
    args = parser.parse_args()
    if not args.filters_dir.is_dir():
        print(f"Filter directory not found: {args.filters_dir}", file=sys.stderr)
        return 2
    for filename in (
        "01-Trusted-Content-Guard.py",
        "02-Accuracy-Thinking.py",
        "03-Selective-Self-Review.py",
    ):
        path = args.filters_dir / filename
        if not path.is_file():
            print(f"Missing filter: {path}", file=sys.stderr)
            return 2
        source = path.read_text(encoding="utf-8")
        compile(source, str(path), "exec")
        first_docstring = source.split('"""', 2)
        if len(first_docstring) < 3:
            raise AssertionError(f"Missing Open WebUI frontmatter: {filename}")
        frontmatter = first_docstring[1]
        for required in ("title:", "author:", "version:", "required_open_webui_version:", "description:"):
            if not any(line.strip().startswith(required) for line in frontmatter.splitlines()):
                raise AssertionError(f"Missing frontmatter field {required} in {filename}")
    print("[PASS] All filter sources compile")
    print("[PASS] All filters contain valid Open WebUI YAML frontmatter fields")
    asyncio.run(run_tests(args.filters_dir))
    print("\nFILTER_TESTS: SUCCESS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
