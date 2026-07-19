#!/usr/bin/env python3
"""macOS clipboard helpers for Claude Code running inside Docker.

Claude Code's Linux binary checks common Linux clipboard tools (xclip/wl-paste)
when Ctrl+V is pressed for an image.  The Docker container cannot see the macOS
pasteboard, so scripts/run_claude_docker.sh installs tiny xclip/wl-paste shims
that call this host-side helper through the localhost bridge.

All file-producing commands are restricted to the repo's shared
.claude-host-tmp directory, which is bind-mounted into the container.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

IMAGE_TARGETS = (
    "image/png",
    "image/tiff",
    "image/jpeg",
    "image/gif",
    "image/bmp",
)
APPLE_IMAGE_MARKERS = (
    "PNGf",
    "TIFF",
    "JPEG",
    "GIF",
    "BMP",
    "jp2",
    "PICT",
    "TPIC",
    "picture",
)


def _repo_root() -> Path:
    return Path(os.environ.get("CLAUDE_HOST_REPO_ROOT", Path.cwd())).resolve()


def _shared_tmp_root() -> Path:
    root = Path(os.environ.get("CLAUDE_HOST_SHARED_TMP_ROOT", _repo_root() / ".claude-host-tmp")).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def _resolve_shared_file(raw_path: str) -> Path:
    path = Path(raw_path)
    if not path.is_absolute():
        path = Path.cwd() / path
    resolved = path.resolve(strict=False)
    shared_root = _shared_tmp_root()
    try:
        resolved.relative_to(shared_root)
    except ValueError:
        raise SystemExit(f"refusing to write outside shared temp root: {resolved}")
    resolved.parent.mkdir(parents=True, exist_ok=True)
    return resolved


def _run_osascript(script: str) -> subprocess.CompletedProcess[str]:
    args: list[str] = ["osascript"]
    for line in script.splitlines():
        stripped = line.rstrip()
        if stripped:
            args.extend(["-e", stripped])
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def _applescript_path(path: Path) -> str:
    return str(path).replace("\\", "\\\\").replace('"', '\\"')


def _clipboard_info() -> str:
    completed = _run_osascript("clipboard info")
    if completed.returncode != 0:
        return ""
    return completed.stdout


def has_image() -> bool:
    info = _clipboard_info()
    if not info:
        return False
    return any(marker.lower() in info.lower() for marker in APPLE_IMAGE_MARKERS)


def print_targets() -> int:
    if not has_image():
        return 1
    print("\n".join(IMAGE_TARGETS))
    return 0


def _write_clipboard_as_apple_type(dest: Path, apple_type: str, variable: str) -> bool:
    dest_s = _applescript_path(dest)
    script = f"""
set outPath to POSIX file "{dest_s}"
set {variable} to (the clipboard as «class {apple_type}»)
set outFile to open for access outPath with write permission
set eof outFile to 0
write {variable} to outFile
close access outFile
"""
    completed = _run_osascript(script)
    return completed.returncode == 0 and dest.exists() and dest.stat().st_size > 0


def write_image(dest_raw: str) -> int:
    dest = _resolve_shared_file(dest_raw)
    if not has_image():
        print("clipboard does not contain an image", file=sys.stderr)
        return 1

    pngpaste = shutil.which("pngpaste")
    if pngpaste:
        completed = subprocess.run([pngpaste, str(dest)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if completed.returncode == 0 and dest.exists() and dest.stat().st_size > 0:
            return 0

    if _write_clipboard_as_apple_type(dest, "PNGf", "png_data"):
        return 0

    with tempfile.TemporaryDirectory(dir=str(_shared_tmp_root())) as tmp_dir:
        tiff_path = Path(tmp_dir) / "clipboard.tiff"
        if _write_clipboard_as_apple_type(tiff_path, "TIFF", "tiff_data"):
            sips = shutil.which("sips")
            if sips:
                completed = subprocess.run(
                    [sips, "-s", "format", "png", str(tiff_path), "--out", str(dest)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
                if completed.returncode == 0 and dest.exists() and dest.stat().st_size > 0:
                    return 0

    print("failed to read an image from the macOS clipboard", file=sys.stderr)
    return 1


def read_text() -> int:
    pbpaste = shutil.which("pbpaste")
    if not pbpaste:
        return 127
    completed = subprocess.run([pbpaste], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if completed.stdout:
        sys.stdout.buffer.write(completed.stdout)
    if completed.stderr:
        sys.stderr.buffer.write(completed.stderr)
    return completed.returncode


def write_text_file(raw_path: str) -> int:
    pbcopy = shutil.which("pbcopy")
    if not pbcopy:
        return 127
    path = _resolve_shared_file(raw_path)
    data = path.read_bytes()
    completed = subprocess.run([pbcopy], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if completed.stdout:
        sys.stdout.buffer.write(completed.stdout)
    if completed.stderr:
        sys.stderr.buffer.write(completed.stderr)
    return completed.returncode


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("has-image")
    subparsers.add_parser("targets")
    subparsers.add_parser("read-text")
    write_image_parser = subparsers.add_parser("write-image")
    write_image_parser.add_argument("path")
    write_text_parser = subparsers.add_parser("write-text-file")
    write_text_parser.add_argument("path")

    args = parser.parse_args(argv)
    if args.command == "has-image":
        return 0 if has_image() else 1
    if args.command == "targets":
        return print_targets()
    if args.command == "write-image":
        return write_image(args.path)
    if args.command == "read-text":
        return read_text()
    if args.command == "write-text-file":
        return write_text_file(args.path)
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
