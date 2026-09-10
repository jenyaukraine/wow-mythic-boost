"""Regression tests for the release ZIP verifier."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "Tools" / "VerifyRelease.py"
VERSION = "2.4.121"


def write_archive(path: Path, files: dict[str, str | bytes]) -> None:
    with ZipFile(path, "w", ZIP_DEFLATED) as package:
        for name, content in files.items():
            # ZipInfo normalizes Windows separators at construction; preserve
            # deliberately malformed member names to exercise the verifier.
            entry = ZipInfo(name)
            entry.filename = name
            package.writestr(entry, content)


def base_files(version: str = VERSION) -> dict[str, str]:
    toc = "\n".join(
        [
            "## Interface: 120000",
            "## Title: MythicBoost",
            f"## Version: {version}",
            "Contracts.lua",
            "",
        ]
    )
    return {
        "MythicBoost/MythicBoost.toc": toc,
        "MythicBoost/Contracts.lua": "local _, JP = ...\n",
        "MythicBoost/CHANGELOG.md": f"## {version}\n\n- Test release.\n",
        "MythicBoost/README.txt": f"MythicBoost {version}\n",
        "MythicBoost/LICENSE-XPERL.txt": "license\n",
        "MythicBoost/NOTICE-XPERL.txt": "notice\n",
    }


def verify(archive: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VERIFY), str(archive)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def assert_fails(files: dict[str, str], archive_name: str, expected: str) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary) / archive_name
        write_archive(archive, files)
        result = verify(archive)
    assert result.returncode != 0, result.stdout
    assert expected in result.stdout, result.stdout


def test_valid_release_archive_passes() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary) / f"MythicBoost-{VERSION}.zip"
        write_archive(archive, base_files())
        result = verify(archive)
    assert result.returncode == 0, result.stdout
    assert f"Release verification OK: MythicBoost {VERSION}, 1 TOC entries" in result.stdout


def test_development_files_are_rejected() -> None:
    files = base_files()
    files["MythicBoost/Tools/ImportAutoBiS.py"] = "print('dev')\n"
    assert_fails(files, f"MythicBoost-{VERSION}.zip", "development file entered")


def test_temporary_patch_artifacts_are_rejected() -> None:
    for suffix in (".pyo", ".tmp", ".orig", ".rej", ".patch", ".diff"):
        files = base_files()
        files[f"MythicBoost/Modules/Leftover{suffix}"] = "stale artifact\n"
        assert_fails(files, f"MythicBoost-{VERSION}.zip", "development file entered")


def test_removed_autobis_notice_is_rejected() -> None:
    files = base_files()
    files["MythicBoost/NOTICE-AUTOBIS.txt"] = "stale notice\n"
    assert_fails(files, f"MythicBoost-{VERSION}.zip", "removed AutoBiS notice entered")


def test_lua_files_outside_toc_are_rejected() -> None:
    files = base_files()
    files["MythicBoost/Modules/Unlisted.lua"] = "return true\n"
    assert_fails(files, f"MythicBoost-{VERSION}.zip", "Lua files outside TOC")


def test_unsafe_archive_paths_are_rejected() -> None:
    files = base_files()
    files["Tools/TestMythicBoost.py"] = "print('outside addon')\n"
    assert_fails(files, f"MythicBoost-{VERSION}.zip", "unsafe or unexpected archive path")


def test_filename_must_match_toc_version() -> None:
    assert_fails(base_files(), "MythicBoost-9.9.9.zip", "archive name does not match TOC version")


def test_windows_case_collisions_are_rejected() -> None:
    files = base_files()
    files["MythicBoost/contracts.lua"] = "return true\n"
    assert_fails(files, f"MythicBoost-{VERSION}.zip", "duplicate paths")


def test_noncanonical_file_and_directory_paths_are_rejected() -> None:
    for name in ("MythicBoost/../", "MythicBoost\\escape.lua", "MythicBoost//extra.txt",
                 "MythicBoost/./extra.txt", "MythicBoost/extra.txt:stream", "MythicBoost/extra. /",
                 "MythicBoost/extra.txt./"):
        files = base_files()
        files[name] = ""
        assert_fails(files, f"MythicBoost-{VERSION}.zip", "unsafe or unexpected archive path")


def test_unlisted_uppercase_lua_is_rejected() -> None:
    files = base_files()
    files["MythicBoost/Modules/Unlisted.LUA"] = "return true\n"
    assert_fails(files, f"MythicBoost-{VERSION}.zip", "Lua files outside TOC")


def test_invalid_utf8_is_reported_without_traceback() -> None:
    files = base_files()
    files["MythicBoost/README.txt"] = b"\xff\xfe"
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary) / f"MythicBoost-{VERSION}.zip"
        write_archive(archive, files)
        result = verify(archive)
    assert result.returncode != 0
    assert "Release verification failed: invalid ZIP" in result.stdout, result.stdout
    assert "Traceback" not in result.stdout, result.stdout


if __name__ == "__main__":
    test_valid_release_archive_passes()
    test_development_files_are_rejected()
    test_temporary_patch_artifacts_are_rejected()
    test_removed_autobis_notice_is_rejected()
    test_lua_files_outside_toc_are_rejected()
    test_unsafe_archive_paths_are_rejected()
    test_filename_must_match_toc_version()
    test_windows_case_collisions_are_rejected()
    test_noncanonical_file_and_directory_paths_are_rejected()
    test_unlisted_uppercase_lua_is_rejected()
    test_invalid_utf8_is_reported_without_traceback()
    print("Release verifier regression tests passed")
