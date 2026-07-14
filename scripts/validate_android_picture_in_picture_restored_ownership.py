#!/usr/bin/env python3
"""Fail-closed semantic validator for restored Android PiP ownership."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path


_TASK_ID_PATTERN = re.compile(r"\bTask\{[^#]*#(?P<task>\d+)\b")
_TASK_INTENT_COMPONENT_PATTERN = re.compile(r"(?:^|\s)I=(?P<component>[^\s}]+)")
_ACTIVITY_RECORD_PATTERN = re.compile(
    r"ActivityRecord\{(?P<record>\S+)\s+\S+\s+"
    r"(?P<component>\S+)\s+t(?P<task>\d+)(?=[\s}])"
)
_WINDOW_PATTERN = re.compile(
    r"Window\{(?P<window>\S+)\s+\S+\s+(?P<component>[^\s}]+)\}"
)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--activities", required=True)
    parser.add_argument("--audio", required=True)
    parser.add_argument("--flutter-component", required=True)
    parser.add_argument("--native-component", required=True)
    parser.add_argument("--uid", required=True)
    parser.add_argument("--expected-audio-tracks", required=True, type=int)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def _fail(message: str, output: Path) -> int:
    if output.exists() and not output.is_symlink():
        output.unlink()
    print(message, file=sys.stderr)
    return 1


def _task_id(line: str) -> str | None:
    match = _TASK_ID_PATTERN.search(line)
    return None if match is None else match.group("task")


def _task_intent_component(line: str) -> str | None:
    match = _TASK_INTENT_COMPONENT_PATTERN.search(line)
    return None if match is None else match.group("component")


def _activity_identity(line: str) -> tuple[str, str, str] | None:
    match = _ACTIVITY_RECORD_PATTERN.search(line)
    if match is None:
        return None
    return match.group("record"), match.group("component"), match.group("task")


def _window_identities(line: str) -> set[tuple[str, str]]:
    return {
        (match.group("window"), match.group("component"))
        for match in _WINDOW_PATTERN.finditer(line)
    }


def _unique_anchor(lines: list[str], prefix: str) -> str | None:
    matches = [line.strip() for line in lines if line.strip().startswith(prefix)]
    return matches[0] if len(matches) == 1 else None


def _history_blocks(lines: list[str]) -> list[list[str]]:
    blocks: list[list[str]] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not re.match(r"^\s*\* Hist\s+#?\d+:", line):
            index += 1
            continue
        header_indent = len(line) - len(line.lstrip())
        end = index + 1
        while end < len(lines):
            candidate = lines[end]
            if candidate.strip():
                candidate_indent = len(candidate) - len(candidate.lstrip())
                if candidate_indent <= header_indent:
                    break
            end += 1
        blocks.append(lines[index:end])
        index = end
    return blocks


def _native_history_blocks(
    lines: list[str],
    native_component: str,
) -> list[list[str]]:
    return [
        block
        for block in _history_blocks(lines)
        if (
            (identity := _activity_identity(block[0])) is not None
            and identity[1] == native_component
        )
    ]


def main() -> int:
    args = _arguments()
    output = Path(args.output)
    if args.expected_audio_tracks not in (0, 1):
        return _fail("Expected AudioTrack count must be zero or one.", output)
    if output.is_symlink():
        print("Restored-ownership result path must not be a symlink.", file=sys.stderr)
        return 1

    activities_path = Path(args.activities)
    audio_path = Path(args.audio)
    if not activities_path.is_file() or not audio_path.is_file():
        return _fail("Restored-ownership input was missing.", output)
    activities = activities_path.read_text(encoding="utf-8", errors="replace")
    audio = audio_path.read_text(encoding="utf-8", errors="replace")
    lines = activities.splitlines()

    fullscreen_task_ids: set[str] = set()
    pinned_task_ids: set[str] = set()
    for line in lines:
        if not re.match(r"^\s*\* Task\{", line):
            continue
        task_id = _task_id(line)
        if task_id is None:
            return _fail("A task header lacked one numeric task ID.", output)
        if "mode=pinned" in line:
            pinned_task_ids.add(task_id)
        if (
            _task_intent_component(line) == args.flutter_component
            and "mode=fullscreen" in line
            and "visible=true" in line
            and "visibleRequested=true" in line
        ):
            fullscreen_task_ids.add(task_id)

    if pinned_task_ids:
        return _fail("A pinned task remained after Flutter restoration.", output)
    if len(fullscreen_task_ids) != 1:
        return _fail(
            "Expected one unique visible fullscreen Flutter MainActivity task.",
            output,
        )
    fullscreen_task_id = next(iter(fullscreen_task_ids))

    flutter_history_blocks = [
        block
        for block in _history_blocks(lines)
        if (
            (identity := _activity_identity(block[0])) is not None
            and identity[1] == args.flutter_component
            and identity[2] == fullscreen_task_id
        )
    ]
    if len(flutter_history_blocks) != 1:
        return _fail(
            "Expected one Flutter MainActivity history owner in the fullscreen task.",
            output,
        )
    flutter_history = flutter_history_blocks[0]
    flutter_activity_identity = _activity_identity(flutter_history[0])
    if flutter_activity_identity is None:
        return _fail("The Flutter history owner lacked an exact identity.", output)
    flutter_windows = {
        identity
        for line in flutter_history
        for identity in _window_identities(line)
        if identity[1] == args.flutter_component
    }
    if not flutter_windows:
        return _fail("The Flutter history owner lacked an exact window identity.", output)

    activity_anchors = (
        ("topResumedActivity=", "topResumedActivity"),
        ("ResumedActivity:", "ResumedActivity"),
        ("mFocusedApp=", "mFocusedApp"),
    )
    for prefix, label in activity_anchors:
        anchor = _unique_anchor(lines, prefix)
        if anchor is None or _activity_identity(anchor) != flutter_activity_identity:
            return _fail(
                f"{label} was not bound to the exact fullscreen Flutter Activity.",
                output,
            )

    current_focus = _unique_anchor(lines, "mCurrentFocus=")
    current_focus_windows = (
        set() if current_focus is None else _window_identities(current_focus)
    )
    if len(current_focus_windows) != 1 or not current_focus_windows <= flutter_windows:
        return _fail(
            "mCurrentFocus was not bound to an exact fullscreen Flutter window.",
            output,
        )

    focused_root = _unique_anchor(lines, "topDisplayFocusedRootTask=")
    if (
        focused_root is None
        or _task_id(focused_root) != fullscreen_task_id
        or _task_intent_component(focused_root) != args.flutter_component
    ):
        return _fail(
            "The focused root was not the unique fullscreen Flutter task.",
            output,
        )

    native_blocks = _native_history_blocks(lines, args.native_component)
    finished_native_residue = False
    active_state_pattern = re.compile(
        r"\bstate=(?:RESUMED|STARTED|PAUSING|PAUSED|STOPPING)\b"
    )
    for block in native_blocks:
        header = block[0]
        finished = " f}}" in header or any("finishing=true" in line for line in block)
        active = any(
            active_state_pattern.search(line)
            or "mVisibleRequested=true" in line
            or "nowVisible=true" in line
            for line in block
        )
        if active and not finished:
            return _fail("The native PiP Activity remained active or visible.", output)
        finished_native_residue = finished_native_residue or finished

    for line in lines:
        stripped = line.strip()
        identity = _activity_identity(stripped)
        if (
            stripped.startswith("* ActivityRecord{")
            and identity is not None
            and identity[1] == args.native_component
            and " f}}" not in stripped
        ):
            return _fail("An unfinished native PiP Activity remained visible.", output)

    started_players = [
        line
        for line in audio.splitlines()
        if "AudioPlaybackConfiguration " in line
        and f"u/pid:{args.uid}/" in line
        and "state:started" in line
    ]
    audio_tracks = [
        line
        for line in started_players
        if "type:android.media.AudioTrack" in line
    ]
    media_players = [
        line
        for line in started_players
        if "type:android.media.MediaPlayer" in line
    ]
    if len(media_players) != 0:
        return _fail("A native MediaPlayer remained started after restoration.", output)
    if (
        len(audio_tracks) != args.expected_audio_tracks
        or len(started_players) != args.expected_audio_tracks
    ):
        return _fail(
            "Started playback was not owned by the exact expected Flutter AudioTrack.",
            output,
        )

    normalized = (
        "restoredOwnership=true "
        f"fullscreenFlutterTaskId={fullscreen_task_id} "
        "topResumed=true resumed=true currentFocus=true focusedApp=true "
        "pinnedTasks=0 nativeActive=false "
        f"finishedNativeResidue={str(finished_native_residue).lower()} "
        f"flutterAudioTracks={len(audio_tracks)} nativeMediaPlayers=0 "
        f"startedPlayers={len(started_players)}\n"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
    temporary.write_text(normalized, encoding="utf-8")
    os.replace(temporary, output)
    print(normalized, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
