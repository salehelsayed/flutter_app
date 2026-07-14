#!/usr/bin/env python3
"""Select the unique fullscreen Flutter task and distinct native PiP task."""

from __future__ import annotations

import argparse
import os
import re
import stat
import tempfile
from pathlib import Path


TASK_HEADER = re.compile(r"^  \* Task\{[^#]*#(?P<task_id>[0-9]+)\b.*$")
PACKAGE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$")


def regular_unlinked_file(path: Path) -> bool:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return False
    return stat.S_ISREG(mode) and not path.is_symlink()


def task_blocks(text: str) -> list[tuple[int, str, str]]:
    blocks: list[tuple[int, str, list[str]]] = []
    current: tuple[int, str, list[str]] | None = None
    for line in text.splitlines():
        match = TASK_HEADER.match(line)
        if match is not None:
            if current is not None:
                blocks.append(current)
            current = (int(match.group("task_id")), line, [line])
        elif current is not None:
            current[2].append(line)
    if current is not None:
        blocks.append(current)
    return [(task_id, header, "\n".join(lines)) for task_id, header, lines in blocks]


def select_topology(text: str, package: str) -> tuple[int, int]:
    flutter_component = f"{package}/com.mknoon.app.MainActivity"
    native_component = (
        f"{package}/com.mknoon.app.ReceivedVideoPictureInPictureActivity"
    )
    main_ids: list[int] = []
    pinned_ids: list[int] = []
    pinned_package = re.compile(rf"(?:^|\s)A=[0-9]+:{re.escape(package)}(?:\s|$)")

    for task_id, header, block in task_blocks(text):
        if (
            f"I={flutter_component}" in header
            and "mode=fullscreen" in header
            and f"mActivityComponent={flutter_component}" in block
        ):
            main_ids.append(task_id)
        if (
            "mode=pinned" in header
            and pinned_package.search(header) is not None
            and f"mActivityComponent={native_component}" in block
            and f"mActivityComponent={flutter_component}" not in block
        ):
            pinned_ids.append(task_id)

    if len(main_ids) != 1 or len(pinned_ids) != 1:
        raise ValueError(
            "expected exactly one fullscreen MainActivity task and one native PiP task"
        )
    if main_ids[0] == pinned_ids[0]:
        raise ValueError("fullscreen and native PiP task IDs must be distinct")
    return main_ids[0], pinned_ids[0]


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() or path.is_symlink():
        raise ValueError("output must not already exist")
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--package", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()

    source = Path(arguments.input)
    output = Path(arguments.output)
    if not PACKAGE.fullmatch(arguments.package):
        parser.error("package is malformed")
    if not regular_unlinked_file(source):
        parser.error("input must be one regular non-symlink file")
    try:
        main_task_id, pinned_task_id = select_topology(
            source.read_text(encoding="utf-8"),
            arguments.package,
        )
        atomic_write(
            output,
            f"fullscreenMainTaskId={main_task_id}\n"
            f"pinnedNativeTaskId={pinned_task_id}\n",
        )
    except (OSError, UnicodeError, ValueError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
