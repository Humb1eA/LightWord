#!/usr/bin/env python3
"""Import the public 高考 3500 word list into Resources/Wordbooks/gaokao.json.

Source: https://github.com/pluto0x0/word3500 — plain text where every entry is

    word line
    [phonetic line]      (may be empty: "[]")
    one or more meaning lines

The parser anchors on the phonetic line (the only reliable marker) and walks
backwards for the word, forwards for the meanings. Guessing "does this line look
like a word" breaks on entries such as `arise (arose, arisen)` or `afterward(s)`,
which is what an earlier version did and why this one is written around anchors.

    python tools/import_gaokao.py
"""
from __future__ import annotations

import json
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tools" / "vendor" / "gaokao3500.raw.txt"
TARGET = ROOT / "Resources" / "Wordbooks" / "gaokao.json"

BOOK = {
    "id": "gaokao",
    "name": "高考 3500",
    "description": "高中课标词汇 · 含音标与中文释义",
}

# Longest alternatives first so "abbr." is not read as "a".
POS = "vt|vi|adj|adv|abbr|aux|art|conj|pron|prep|num|int|n|v|a|ad"
POS_SPLIT = re.compile(r"(?<=\s)(?=(?:" + POS + r")\.)")
POS_HEAD = re.compile(r"^(?:" + POS + r")\.")
CJK = re.compile(r"[\u4e00-\u9fff]")
CORRUPT = re.compile(r"[\uE000-\uF8FF\u0000-\u001F\u007F]")
PAREN = re.compile(r"\s*\([^)]*\)\s*")


def clean(text: str) -> str:
    """Whitespace + corrupt-codepoint cleanup; keeps full-width punctuation."""
    text = CORRUPT.sub("", text)
    return re.sub(r"\s+", " ", text).strip()


def base_id(text: str) -> str:
    """'arise (arose, arisen)' -> 'arise', 'afterward(s)' -> 'afterward'.

    Case is preserved so real homographs stay apart: 'March' (三月) is not
    'march' (行进), 'AD' (公元) is not 'ad' (广告).
    """
    stripped = PAREN.sub("", unicodedata.normalize("NFKC", text)).strip()
    return (stripped or text).strip()


def split_meanings(text: str) -> list[str]:
    text = clean(text)
    if not text:
        return []
    parts = [clean(p) for p in POS_SPLIT.split(text)]
    parts = [p for p in parts if p]
    return parts or [text]


POS_ONLY = re.compile(
    r"^(?:vt|vi|adj|adv|abbr|aux|art|conj|pron|prep|num|int|n|v|a|ad)\.?$|^(?:modal|aux)$",
    re.IGNORECASE,
)
INFLECTION = re.compile(r"\(([^)]*)\)")


def is_pos_noise(meaning: str) -> bool:
    """Entry fragments like 'n' or 'modal' carry no meaning on their own."""
    return bool(POS_ONLY.match(meaning.strip()))


def inflections(text: str) -> str:
    """'arise (arose, arisen)' -> 'arose, arisen'; '(s)' / '(an)' are ignored."""
    for match in INFLECTION.finditer(text):
        content = match.group(1).strip(" ,")
        if len(re.sub(r"[^A-Za-z]", "", content)) >= 3:
            return content
    return ""


def phonetic_indexes(lines: list[str]) -> list[int]:
    return [i for i, line in enumerate(lines) if line.strip().startswith("[")]


def previous_content(lines: list[str], index: int) -> int:
    cursor = index - 1
    while cursor >= 0 and not lines[cursor].strip():
        cursor -= 1
    return cursor


def parse(lines: list[str]) -> tuple[list[dict], list[str], Counter]:
    anchors = phonetic_indexes(lines)
    if not anchors:
        return [], ["no phonetic lines found"], Counter()

    artifacts: list[str] = []
    stats: Counter = Counter()

    # Group anchors per entry. A phonetic line whose predecessor is itself a
    # phonetic line (e.g. "short wave" -> "[ʃɔːt]" / "[weɪv]") continues the
    # previous entry instead of starting a new one.
    groups: list[dict] = []
    for anchor in anchors:
        previous = previous_content(lines, anchor)
        starts_entry = (
            previous >= 0
            and not lines[previous].strip().startswith("[")
            and (not groups or previous > groups[-1]["phonetics"][-1])
        )
        if starts_entry:
            groups.append({"word_index": previous, "phonetics": [anchor]})
        elif groups:
            groups[-1]["phonetics"].append(anchor)
        else:
            stats["missing_word"] += 1
            artifacts.append(f"line {anchor + 1}: no word line before phonetic")

    words: list[dict] = []
    for position, group in enumerate(groups):
        parts: list[str] = []
        for anchor in group["phonetics"]:
            raw = lines[anchor].strip()
            if not raw.endswith("]"):
                stats["unterminated_phonetic"] += 1
            parts.append(raw.strip("[]").strip())
        phonetic = re.sub(r"\s+", " ", " ".join(p for p in parts if p)).strip()

        word = clean(lines[group["word_index"]])

        next_word_index = (
            groups[position + 1]["word_index"] if position + 1 < len(groups) else len(lines)
        )

        meanings: list[str] = []
        for line in lines[group["phonetics"][-1] + 1 : next_word_index]:
            if not line.strip():
                continue
            meanings.extend(split_meanings(line))

        if not meanings:
            stats["missing_meaning"] += 1
            artifacts.append(f"line {group['word_index'] + 1}: no meaning for {word!r}")
            continue

        if not phonetic:
            stats["empty_phonetic"] += 1
        if not CJK.search(" ".join(meanings)):
            stats["meaning_without_cjk"] += 1
        if not CJK.search(word) and not word:
            stats["empty_word"] += 1

        words.append({"word": word, "phonetic": phonetic, "meanings": meanings[:4]})

    # Anything before the first entry is a preamble; anything else is a bug.
    first_word_index = groups[0]["word_index"] if groups else 0
    preamble = [line.strip() for line in lines[:first_word_index] if line.strip()]
    stats["preamble_lines"] = len(preamble)
    for line in preamble[:3]:
        artifacts.append(f"preamble: {line!r}")

    return words, artifacts, stats


def to_entries(words: list[dict]) -> tuple[list[dict], Counter]:
    """Merge entries that share an id (noun sense + verb sense of one word)."""
    stats: Counter = Counter()
    grouped: dict[str, list[dict]] = {}

    for word in words:
        key = base_id(word["word"])
        if not key:
            stats["empty_id"] += 1
            continue
        grouped.setdefault(key, []).append(word)

    entries: list[dict] = []
    for key, members in grouped.items():
        if len(members) > 1:
            stats["merged_groups"] += 1

        display = key
        phonetic = ""
        meanings: list[str] = []

        for member in members:
            forms = inflections(member["word"])
            if forms:
                note = f"变形：{forms}"
                if note not in meanings:
                    meanings.append(note)
            if not phonetic and member["phonetic"]:
                phonetic = member["phonetic"]
            for meaning in member["meanings"]:
                if is_pos_noise(meaning):
                    stats["dropped_pos_noise"] += 1
                    continue
                if meaning in meanings:
                    continue
                meanings.append(meaning)

        if not meanings:
            stats["empty_meaning_after_merge"] += 1
            continue

        entries.append(
            {
                "i": key,
                "w": display,
                "p": phonetic,
                "m": meanings[:6],
            }
        )

    entries.sort(key=lambda entry: entry["i"].lower())
    return entries, stats


def main() -> int:
    if not SOURCE.exists():
        print(f"error: missing {SOURCE}", file=sys.stderr)
        return 1

    lines = SOURCE.read_text(encoding="utf-8-sig").splitlines()
    words, anomalies, stats = parse(lines)
    entries, id_stats = to_entries(words)
    stats.update(id_stats)

    print(f"lines:            {len(lines)}")
    print(f"entries:          {len(entries)}")
    print(f"empty phonetic:   {stats['empty_phonetic']}")
    print(f"missing meaning:  {stats['missing_meaning']}")
    print(f"missing word:     {stats['missing_word']}")
    print(f"merged same-word: {stats['merged_groups']}")
    print(f"pos noise dropped:{stats['dropped_pos_noise']}")
    print(f"preamble lines:   {stats['preamble_lines']}")
    for anomaly in anomalies[:8]:
        print(f"  - {anomaly}")

    if len(entries) < 3000:
        print(f"error: only {len(entries)} entries parsed", file=sys.stderr)
        return 1
    if stats["missing_meaning"] or stats["missing_word"]:
        print("error: structural problems in source", file=sys.stderr)
        return 1
    if stats["empty_phonetic"] > len(entries) * 0.03:
        print("error: too many entries without a phonetic", file=sys.stderr)
        return 1

    document = dict(BOOK, words=entries)
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(
        json.dumps(document, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    print()
    print("sample:")
    for entry in entries[:3] + entries[150:152] + entries[-2:]:
        print(f"  {entry['w']} [{entry['p']}] {' / '.join(entry['m'])}")
    print()
    print(f"wrote {TARGET.relative_to(ROOT)}: {len(entries)} words, "
          f"{TARGET.stat().st_size / 1024:.1f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
