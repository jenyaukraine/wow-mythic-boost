"""Verify the final MythicBoost ZIP using only Python's standard library."""

from __future__ import annotations

import re
import sys
from pathlib import Path, PurePosixPath
from zipfile import BadZipFile, ZipFile


FORBIDDEN_SUFFIXES = (".ps1", ".py", ".pyc", ".bak", ".old", ".zip")


def fail(message: str) -> None:
    raise SystemExit(f"Release verification failed: {message}")


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: python Tools/VerifyRelease.py <archive.zip>")
    archive = Path(sys.argv[1]).resolve()
    if not archive.is_file():
        fail(f"archive does not exist: {archive}")

    try:
        with ZipFile(archive) as package:
            names = package.namelist()
            if len(names) != len(set(names)):
                fail("archive contains duplicate paths")
            files = {name for name in names if not name.endswith("/")}
            for name in files:
                path = PurePosixPath(name)
                if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "MythicBoost":
                    fail(f"unsafe or unexpected archive path: {name}")
                lowered = name.lower()
                if lowered.endswith(FORBIDDEN_SUFFIXES) or "__pycache__" in lowered:
                    fail(f"development file entered the archive: {name}")
                if "mythicboostdesktop" in lowered or lowered.endswith("keystonetimer.lua"):
                    fail(f"abandoned component entered the archive: {name}")

            toc_name = "MythicBoost/MythicBoost.toc"
            if toc_name not in files:
                fail("MythicBoost.toc is absent")
            toc = package.read(toc_name).decode("utf-8-sig")
            version_match = re.search(r"^## Version:\s*(\d+\.\d+\.\d+)\s*$", toc, re.MULTILINE)
            if not version_match:
                fail("TOC version is absent or invalid")
            version = version_match.group(1)
            if archive.name != f"MythicBoost-{version}.zip":
                fail(f"archive name does not match TOC version {version}")

            required_extras = {
                "MythicBoost/CHANGELOG.md",
                "MythicBoost/README.txt",
                "MythicBoost/LICENSE-XPERL.txt",
                "MythicBoost/NOTICE-XPERL.txt",
            }
            absent_extras = sorted(required_extras - files)
            if absent_extras:
                fail(f"release documentation is absent: {', '.join(absent_extras)}")
            changelog = package.read("MythicBoost/CHANGELOG.md").decode("utf-8-sig")
            first_release = re.search(r"^##\s+(\d+\.\d+\.\d+)\b", changelog, re.MULTILINE)
            if not first_release or first_release.group(1) != version:
                fail("packaged changelog version does not match TOC")
            readme = package.read("MythicBoost/README.txt").decode("utf-8-sig")
            if not readme.splitlines() or readme.splitlines()[0] != f"MythicBoost {version}":
                fail("packaged README version does not match TOC")

            entries = [line.strip().replace("\\", "/") for line in toc.splitlines()
                       if line.strip() and not line.startswith("##")]
            if len(entries) != len(set(entries)):
                fail("TOC contains duplicate files")
            missing = [entry for entry in entries if f"MythicBoost/{entry}" not in files]
            if missing:
                fail(f"TOC files are absent from ZIP: {', '.join(missing)}")
            if "Contracts.lua" not in entries:
                fail("Contracts.lua is absent from release load order")
            extra_lua = sorted(name for name in files if name.endswith(".lua")
                               and name.removeprefix("MythicBoost/") not in entries)
            if extra_lua:
                fail(f"Lua files outside TOC entered ZIP: {', '.join(extra_lua)}")
    except BadZipFile as error:
        fail(f"invalid ZIP: {error}")

    print(f"Release verification OK: MythicBoost {version}, {len(entries)} TOC entries")


if __name__ == "__main__":
    main()
