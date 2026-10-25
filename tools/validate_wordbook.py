#!/usr/bin/env python3
"""Validate a built word book JSON: structure, uniqueness, non-empty fields.

Usage:
    python tools/validate_wordbook.py [path-to.json]

Defaults to Resources/Wordbooks/gaokao.json. Runs in CI before the app is built,
so a broken word list fails fast instead of shipping a blank app.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = ROOT / "Resources" / "Wordbooks" / "gaokao.json"

MIN_WORDS = 50


def fail(message: str) -> int:
    print(f"FAIL {message}", file=sys.stderr)
    return 1


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT
    if not path.exists():
        return fail(f"missing file: {path}")

    try:
        book = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return fail(f"invalid JSON: {error}")

    for key in ("id", "name", "description", "words"):
        if key not in book:
            return fail(f"missing top-level key: {key}")

    words = book["words"]
    if not isinstance(words, list):
        return fail("'words' must be a list")
    if len(words) < MIN_WORDS:
        return fail(f"only {len(words)} words, expected at least {MIN_WORDS}")

    seen: set[str] = set()
    problems: list[str] = []
    blank_phonetics = 0

    for index, word in enumerate(words):
        if not isinstance(word, dict):
            problems.append(f"[{index}] not an object")
            continue

        word_id = word.get("i")
        text = word.get("w")
        phonetic = word.get("p")
        meanings = word.get("m")

        if not isinstance(word_id, str) or not word_id:
            problems.append(f"[{index}] bad id")
            continue
        if word_id in seen:
            problems.append(f"[{index}] duplicate id {word_id}")
        seen.add(word_id)

        if not isinstance(text, str) or not text:
            problems.append(f"[{index}] {word_id}: empty word")
        if not isinstance(phonetic, str):
            problems.append(f"[{index}] {word_id}: phonetic must be a string")
        elif not phonetic:
            # The 3500 list ships a few empty "[]" phonetics; the app hides the row.
            blank_phonetics += 1
        if not isinstance(meanings, list) or not meanings:
            problems.append(f"[{index}] {word_id}: empty meanings")
        elif not all(isinstance(m, str) and m.strip() for m in meanings):
            problems.append(f"[{index}] {word_id}: blank meaning entry")

        examples = word.get("e", [])
        if examples:
            if not isinstance(examples, list):
                problems.append(f"[{index}] {word_id}: 'e' must be a list")
            else:
                for example in examples:
                    if not isinstance(example, dict) or "en" not in example or "zh" not in example:
                        problems.append(f"[{index}] {word_id}: example needs en/zh")

    if not problems and blank_phonetics > len(words) * 0.03:
        problems.append(
            f"{blank_phonetics} entries have no phonetic, above the 3% tolerance"
        )

    if problems:
        for problem in problems[:20]:
            print(f"FAIL {problem}", file=sys.stderr)
        return 1

    examples = sum(1 for word in words if word.get("e"))
    print(
        f"OK {book['id']}: {len(words)} words, {examples} with examples, "
        f"{blank_phonetics} without phonetic, {path.stat().st_size / 1024:.1f} KB"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
