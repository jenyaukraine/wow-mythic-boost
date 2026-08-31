"""Fail fast when generated changes bypass MythicBoost's stable contracts."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "MythicBoost"
TOC = ADDON / "MythicBoost.toc"


def fail(message: str) -> None:
    raise SystemExit(f"Architecture check failed: {message}")


def toc_entries() -> list[str]:
    lines = TOC.read_text(encoding="utf-8-sig").splitlines()
    entries = [line.strip().replace("\\", "/") for line in lines if line.strip() and not line.startswith("##")]
    if len(entries) != len(set(entries)):
        fail("MythicBoost.toc contains duplicate files")
    for entry in entries:
        if not (ADDON / entry).is_file():
            fail(f"TOC file is missing: {entry}")
    return entries


def check_load_order(entries: list[str]) -> None:
    required = ["Localization.lua", "Contracts.lua", "Core.lua", "UI.lua"]
    try:
        positions = [entries.index(name) for name in required]
    except ValueError as error:
        fail(f"required foundation file is absent: {error}")
    if positions != sorted(positions):
        fail("foundation order must be Localization -> Contracts -> Core -> UI")


def check_api_ownership(entries: list[str]) -> None:
    owned_calls = {
        "GetChallengeCompletionInfo",
        "GetCompletionInfo",
        "GetActiveChallengeMapID",
        "GetActiveKeystoneInfo",
        "GetStartTime",
        "IsChallengeModeActive",
        "GetDeathCount",
        "GetMapTable",
        "GetMapUIInfo",
        "GetApplicationInfo",
        "GetApplications",
    }
    for entry in entries:
        if not entry.endswith(".lua") or entry == "Contracts.lua" or entry.startswith("Libs/"):
            continue
        source = (ADDON / entry).read_text(encoding="utf-8-sig")
        for call in owned_calls:
            if re.search(rf"\b{re.escape(call)}\b", source):
                fail(f"{entry} bypasses Contracts.lua with {call}")


def check_limits(entries: list[str]) -> None:
    source = (ADDON / "Contracts.lua").read_text(encoding="utf-8-sig")
    required = {
        "LOG_ENTRIES",
        "SCANNED_PLAYERS",
        "SCANNED_PLAYER_TTL",
        "PROFILE_CACHE_ENTRIES",
        "HISTORY_TEAMMATES",
        "HISTORY_RUNS",
        "ACTIVE_APPLICATIONS",
    }
    missing = sorted(name for name in required if not re.search(rf"\b{name}\s*=", source))
    if missing:
        fail(f"central limits are missing: {', '.join(missing)}")

    forbidden = {
        "Modules/GroupSearchUI.lua": [r"PROFILE_CACHE_LIMIT\s*=\s*\d", r"\b5\s*-\s*activeOutside"],
        "Modules/RunHistory.lua": [r"MAX_TEAMMATES\s*=\s*\d", r"MAX_RUNS\s*=\s*\d"],
        "Core.lua": [r"SCANNED_LIMIT\s*=\s*\d", r"LOG_LIMIT\s*=\s*\d"],
    }
    for entry, patterns in forbidden.items():
        module_source = (ADDON / entry).read_text(encoding="utf-8-sig")
        for pattern in patterns:
            if re.search(pattern, module_source):
                fail(f"{entry} duplicates a central limit ({pattern})")


def check_release_surface(entries: list[str]) -> None:
    if "Modules/KeystoneTimer.lua" in entries:
        fail("abandoned KeystoneTimer.lua must not be shipped")
    toc_text = TOC.read_text(encoding="utf-8-sig")
    version_match = re.search(r"^## Version:\s*(\d+\.\d+\.\d+)\s*$", toc_text, re.MULTILINE)
    if not version_match:
        fail("TOC version is absent or invalid")
    changelog = (ADDON / "CHANGELOG.md").read_text(encoding="utf-8-sig")
    first_release = re.search(r"^##\s+(\d+\.\d+\.\d+)\b", changelog, re.MULTILINE)
    if not first_release or first_release.group(1) != version_match.group(1):
        fail("TOC version must match the first changelog release")


def main() -> None:
    entries = toc_entries()
    check_load_order(entries)
    check_api_ownership(entries)
    check_limits(entries)
    check_release_surface(entries)
    print(f"Architecture check OK: {len(entries)} TOC entries")


if __name__ == "__main__":
    main()
