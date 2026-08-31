"""Verify that every Russian Lua UI string ships in both locale tables."""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

from luaparser import ast, astnodes


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "MythicBoost"
CYRILLIC = re.compile(r"[А-яЁё]")
ENTRY = re.compile(r'^\s*\[("(?:\\.|[^"\\])*")\]\s*=')
EXCLUDED = {"Localization.lua", "Modules/RealmData.lua"}
NO_WRAP = {"искусственного интеллекта"}


def source_strings() -> tuple[set[str], list[str]]:
    values: set[str] = set()
    unwrapped: list[str] = []
    for path in sorted(ADDON.rglob("*.lua")):
        relative = path.relative_to(ADDON).as_posix()
        if relative in EXCLUDED:
            continue
        text = path.read_text(encoding="utf-8-sig")
        tree = ast.parse(text)
        for node in ast.walk(tree):
            if isinstance(node, astnodes.String) and CYRILLIC.search(node.raw):
                values.add(node.raw)
                prefix = text[max(0, node._first_token.start - 32):node._first_token.start]
                if node.raw not in NO_WRAP and not re.search(r"\bL\s*\(\s*$", prefix):
                    unwrapped.append(f"{relative}: {node.raw[:80]}")
    return values, unwrapped


def locale_counts() -> Counter[str]:
    counts: Counter[str] = Counter()
    for line in (ADDON / "Localization.lua").read_text(encoding="utf-8-sig").splitlines():
        match = ENTRY.match(line)
        if match:
            counts[json.loads(match.group(1))] += 1
    return counts


def main() -> None:
    source, unwrapped = source_strings()
    counts = locale_counts()
    missing = sorted(source - counts.keys())
    stale = sorted(counts.keys() - source)
    wrong_count = sorted(key for key in source if counts[key] != 2)
    problems = []
    if missing:
        problems.append(f"missing keys: {missing[:8]}")
    if stale:
        problems.append(f"stale keys: {stale[:8]}")
    if wrong_count:
        problems.append(f"keys not present exactly twice: {wrong_count[:8]}")
    if unwrapped:
        problems.append(f"Russian UI strings not wrapped in L(): {unwrapped[:8]}")
    if problems:
        raise SystemExit("Localization check failed: " + "; ".join(problems))
    print(f"Localization check OK: {len(source)} keys in ru/en/de")


if __name__ == "__main__":
    main()
