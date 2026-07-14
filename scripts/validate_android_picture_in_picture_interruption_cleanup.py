#!/usr/bin/env python3
"""Fail-closed post-uninstall audio-focus ownership validator."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

from validate_android_picture_in_picture_interruption import _parse_focus_section


_PACKAGE_PATTERN = re.compile(
    r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$"
)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", required=True)
    parser.add_argument("--app-package", required=True)
    parser.add_argument("--helper-package", required=True)
    parser.add_argument("--app-uid", required=True)
    parser.add_argument("--helper-uid", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def _fail(message: str, output: Path) -> int:
    if output.exists() and not output.is_symlink():
        output.unlink()
    print(message, file=sys.stderr)
    return 1


def main() -> int:
    args = _arguments()
    output = Path(args.output)
    audio_path = Path(args.audio)
    if output.is_symlink():
        print("Cleanup result path must not be a symlink.", file=sys.stderr)
        return 1
    if (
        audio_path.is_symlink()
        or not audio_path.is_file()
        or _PACKAGE_PATTERN.fullmatch(args.app_package) is None
        or _PACKAGE_PATTERN.fullmatch(args.helper_package) is None
        or not args.app_uid.isdigit()
        or not args.helper_uid.isdigit()
        or args.app_package == args.helper_package
        or args.app_uid == args.helper_uid
    ):
        return _fail("Cleanup focus identity was malformed or ambiguous.", output)

    audio = audio_path.read_text(encoding="utf-8", errors="replace")
    entries = _parse_focus_section(audio)
    if entries is None:
        return _fail("Cleanup audio focus section was malformed or ambiguous.", output)
    forbidden_packages = {args.app_package, args.helper_package}
    forbidden_uids = {args.app_uid, args.helper_uid}
    if any(
        entry.package in forbidden_packages or entry.uid in forbidden_uids
        for entry in entries
    ):
        return _fail("A proof package or UID retained audio focus after cleanup.", output)

    normalized = (
        "cleanupFocusReleased=true appFocusOwners=0 helperFocusOwners=0\n"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
    temporary.write_text(normalized, encoding="utf-8")
    os.replace(temporary, output)
    print(normalized, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
