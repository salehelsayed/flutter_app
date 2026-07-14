#!/usr/bin/env python3
"""Fail-closed validator for the Android PiP audio-focus interruption proof."""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


_COMPONENT_PATTERN = re.compile(
    r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+"
    r"/[A-Za-z][A-Za-z0-9_.$]*(?:\.[A-Za-z][A-Za-z0-9_.$]*)*$"
)
_TASK_ID_PATTERN = re.compile(r"\bTask\{[^#]*#(?P<task>\d+)\b")
_TASK_HEADER_IDENTITY_PATTERN = re.compile(
    r"^\s*\* Task\{(?P<object>[^\s#{}]+)\s+#(?P<task>\d+)\b"
)
_ACTIVITY_RECORD_PATTERN = re.compile(
    r"ActivityRecord\{(?P<record>\S+)\s+\S+\s+"
    r"(?P<component>\S+)\s+t(?P<task>\d+)(?=[\s}])"
)
_WINDOW_PATTERN = re.compile(
    r"Window\{(?P<window>\S+)\s+\S+\s+(?P<component>[^\s}]+)\}"
)
_NONCE_PATTERN = re.compile(r"^[0-9a-f]{32}$")
_TASK_HEADER_PATTERN = re.compile(r"^\s*\* Task\{")
_HISTORY_HEADER_PATTERN = re.compile(
    r"^\s*\* Hist\s+#?(?P<history>\d+):"
)
_FOCUS_HEADER = "Audio Focus stack entries (last is top of stack):"
_FOCUS_TERMINATOR = "No external focus policy"


@dataclass(frozen=True)
class _Task:
    section: int
    task_id: str
    object_token: str
    indent: int
    header: str


@dataclass
class _History:
    parent: _Task
    history_index: str
    identity: tuple[str, str, str]
    indent: int
    lines: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class _ActivityGraph:
    tasks: tuple[_Task, ...]
    histories: tuple[_History, ...]


@dataclass(frozen=True)
class _FocusEntry:
    package: str
    client: str
    uid: str
    gain: str
    loss: str
    usage: str
    content: str


@dataclass(frozen=True)
class _FocusRequest:
    package: str
    client: str
    uid: str
    usage: str
    content: str
    gain: str


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--resolved-component", required=True)
    parser.add_argument("--start-output", required=True)
    parser.add_argument("--pre-activities", required=True)
    parser.add_argument("--pre-audio", required=True)
    parser.add_argument("--post-activities", required=True)
    parser.add_argument("--post-audio", required=True)
    parser.add_argument("--logcat", required=True)
    parser.add_argument("--app-component", required=True)
    parser.add_argument("--helper-component", required=True)
    parser.add_argument("--app-package", required=True)
    parser.add_argument("--helper-package", required=True)
    parser.add_argument("--app-uid", required=True)
    parser.add_argument("--helper-uid", required=True)
    parser.add_argument("--nonce", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def _fail(message: str, output: Path) -> int:
    if output.exists() and not output.is_symlink():
        output.unlink()
    print(message, file=sys.stderr)
    return 1


def _read_regular(path_value: str, label: str, output: Path) -> str | None:
    path = Path(path_value)
    if path.is_symlink() or not path.is_file():
        _fail(f"{label} input must be one regular file.", output)
        return None
    return path.read_text(encoding="utf-8", errors="replace")


def _task_id(line: str) -> str | None:
    match = _TASK_ID_PATTERN.search(line)
    return None if match is None else match.group("task")


def _activity_identity(line: str) -> tuple[str, str, str] | None:
    match = _ACTIVITY_RECORD_PATTERN.search(line)
    if match is None:
        return None
    return match.group("record"), match.group("component"), match.group("task")


def _window_identities(line: str) -> list[tuple[str, str]]:
    return [
        (match.group("window"), match.group("component"))
        for match in _WINDOW_PATTERN.finditer(line)
    ]


def _unique_anchor(lines: list[str], prefix: str) -> str | None:
    matches = [line.strip() for line in lines if line.strip().startswith(prefix)]
    return matches[0] if len(matches) == 1 else None


def _parse_activity_graph(activities: str) -> _ActivityGraph | None:
    tasks: list[_Task] = []
    histories: list[_History] = []
    task_stack: list[_Task] = []
    task_keys: set[tuple[int, str]] = set()
    task_identities: dict[str, tuple[str, str]] = {}
    history_keys: set[tuple[int, str, str, str]] = set()
    section_labels: set[str] = set()
    section = -1
    active_history: _History | None = None

    for line in activities.splitlines():
        stripped = line.strip()
        if not stripped:
            if active_history is not None:
                active_history.lines.append(line)
            continue
        indent = len(line) - len(line.lstrip())
        is_task = _TASK_HEADER_PATTERN.match(line) is not None
        history_match = _HISTORY_HEADER_PATTERN.match(line)
        is_history = history_match is not None

        if active_history is not None and (
            indent <= active_history.indent or is_task or is_history
        ):
            active_history = None

        if indent == 0 and not is_task and not is_history:
            if stripped in section_labels:
                return None
            section_labels.add(stripped)
            section += 1
            task_stack.clear()
            continue

        while task_stack and indent <= task_stack[-1].indent:
            task_stack.pop()

        if is_task:
            task_match = _TASK_HEADER_IDENTITY_PATTERN.match(line)
            if task_match is None:
                return None
            task_id = task_match.group("task")
            object_token = task_match.group("object")
            if section < 0:
                section = 0
            key = (section, task_id)
            if key in task_keys:
                return None
            header = line.strip()
            global_identity = (object_token, header)
            prior_identity = task_identities.get(task_id)
            if prior_identity is not None and prior_identity != global_identity:
                return None
            task_identities[task_id] = global_identity
            task = _Task(section, task_id, object_token, indent, header)
            task_keys.add(key)
            tasks.append(task)
            task_stack.append(task)
            continue

        if is_history:
            identity = _activity_identity(line)
            if (
                not task_stack
                or history_match is None
                or identity is None
                or identity[2] != task_stack[-1].task_id
            ):
                return None
            history_index = history_match.group("history")
            history_key = (
                section,
                task_stack[-1].task_id,
                task_stack[-1].object_token,
                history_index,
            )
            if history_key in history_keys:
                return None
            history_keys.add(history_key)
            active_history = _History(
                parent=task_stack[-1],
                history_index=history_index,
                identity=identity,
                indent=indent,
                lines=[line],
            )
            histories.append(active_history)
            continue

        if active_history is not None:
            active_history.lines.append(line)

    if not tasks or not section_labels:
        return None
    return _ActivityGraph(tuple(tasks), tuple(histories))


def _task_field(task: _Task, name: str) -> str | None:
    matches = re.findall(
        rf"(?:^|\s){re.escape(name)}=([^\s}}]+)(?=[\s}}])", task.header
    )
    return matches[0] if len(matches) == 1 else None


def _component_histories(
    graph: _ActivityGraph, component: str
) -> list[_History]:
    return [
        history
        for history in graph.histories
        if history.identity[1] == component
    ]


def _exact_assignment(value: str, name: str) -> str | None:
    matches = re.findall(
        rf"(?:^|\s){re.escape(name)}=([^\s]+)(?=\s|$)", value
    )
    return matches[0] if len(matches) == 1 else None


def _parse_focus_entry(line: str) -> _FocusEntry | None:
    segments = line.strip().split(" -- ")
    if not segments or not segments[0].startswith("source:"):
        return None
    values: dict[str, str] = {}
    required = {"pack", "client", "gain", "loss", "uid", "attr"}
    for segment in segments[1:]:
        match = re.match(r"^(?P<key>[A-Za-z]+):\s*(?P<value>.*)$", segment)
        if match is None or match.group("key") not in required:
            continue
        key = match.group("key")
        if key in values:
            return None
        values[key] = match.group("value").strip()
    if set(values) != required or not values["uid"].isdigit():
        return None
    usage = _exact_assignment(values["attr"], "usage")
    content = _exact_assignment(values["attr"], "content")
    if usage is None or content is None:
        return None
    return _FocusEntry(
        package=values["pack"],
        client=values["client"],
        uid=values["uid"],
        gain=values["gain"],
        loss=values["loss"],
        usage=usage,
        content=content,
    )


def _parse_focus_section(audio: str) -> list[_FocusEntry] | None:
    lines = audio.splitlines()
    headers = [index for index, line in enumerate(lines) if line.strip() == _FOCUS_HEADER]
    terminators = [
        index for index, line in enumerate(lines) if line.strip() == _FOCUS_TERMINATOR
    ]
    if (
        len(headers) != 1
        or len(terminators) != 1
        or headers[0] >= terminators[0]
    ):
        return None
    entries: list[_FocusEntry] = []
    for line in lines[headers[0] + 1 : terminators[0]]:
        stripped = line.strip()
        if not stripped:
            continue
        if not stripped.startswith("source:"):
            return None
        entry = _parse_focus_entry(line)
        if entry is None:
            return None
        entries.append(entry)
    return entries


def _focus_client_manager(client: str, owner_class: str) -> str | None:
    match = re.fullmatch(
        rf"(?P<manager>android\.media\.AudioManager@[A-Za-z0-9]+?)"
        rf"{re.escape(owner_class)}"
        r"(?:(?:\$\$[A-Za-z0-9_$]+)?@[A-Za-z0-9]+)",
        client,
    )
    return None if match is None else match.group("manager")


def _parse_focus_request(line: str) -> _FocusRequest | None:
    match = re.search(
        r"requestAudioFocus\(\) from uid/pid (?P<uid>\d+)/\d+ "
        r"AA=(?P<usage>[A-Z0-9_]+)/(?P<content>[A-Z0-9_]+) "
        r"clientId=(?P<client>\S+) "
        r"callingPack=(?P<package>[A-Za-z][A-Za-z0-9_.]+) "
        r"req=(?P<gain>\d+) flags=\S+ sdk=\d+\s*$",
        line,
    )
    if match is None:
        return None
    return _FocusRequest(
        package=match.group("package"),
        client=match.group("client"),
        uid=match.group("uid"),
        usage=match.group("usage"),
        content=match.group("content"),
        gain=match.group("gain"),
    )


def _started_players(audio: str, uid: str) -> list[str]:
    return [
        line
        for line in audio.splitlines()
        if "AudioPlaybackConfiguration " in line
        and f"u/pid:{uid}/" in line
        and "state:started" in line
    ]


def _validate_component(
    resolved: str, expected: str, output: Path
) -> bool:
    lines = [line.strip() for line in resolved.splitlines() if line.strip()]
    if len(lines) != 1:
        _fail("Resolved interruption component was not exactly one line.", output)
        return False
    component = lines[0]
    if (
        _COMPONENT_PATTERN.fullmatch(component) is None
        or component != expected
        or "resolveractivity" in component.lower()
        or "chooseractivity" in component.lower()
    ):
        _fail("Resolved interruption component was malformed, ambient, or unexpected.", output)
        return False
    return True


def _validate_pre_owner(
    activities: str,
    audio: str,
    app_component: str,
    helper_component: str,
    app_package: str,
    app_uid: str,
    output: Path,
) -> bool:
    lines = activities.splitlines()
    graph = _parse_activity_graph(activities)
    if graph is None:
        _fail("Pre-interruption activity graph was malformed or ambiguous.", output)
        return False
    pinned_ids = {
        task.task_id
        for task in graph.tasks
        if _task_field(task, "mode") == "pinned"
    }
    native_histories = _component_histories(graph, app_component)
    if (
        len(pinned_ids) != 1
        or len(native_histories) != 1
        or native_histories[0].parent.task_id not in pinned_ids
    ):
        _fail("Pre-interruption owner was not one exact native pinned task.", output)
        return False
    native_identity = native_histories[0].identity
    native_occurrences = {
        identity
        for line in lines
        if (identity := _activity_identity(line)) is not None
        and identity[1] == app_component
    }
    if native_occurrences != {native_identity}:
        _fail("Pre-interruption native Activity identity was not unique.", output)
        return False
    if helper_component in activities:
        _fail("The helper was active before the interruption action.", output)
        return False
    focus_entries = _parse_focus_section(audio)
    if focus_entries is None or len(focus_entries) != 1:
        _fail("Pre-interruption audio focus stack was not unique.", output)
        return False
    focus = focus_entries[0]
    app_class = app_component.split("/", 1)[1]
    if (
        focus.package != app_package
        or focus.uid != app_uid
        or focus.gain != "GAIN"
        or focus.loss != "none"
        or focus.usage != "USAGE_MEDIA"
        or focus.content != "CONTENT_TYPE_MOVIE"
        or _focus_client_manager(focus.client, app_class) is None
    ):
        _fail("Pre-interruption focus was not the exact native movie owner.", output)
        return False
    players = _started_players(audio, app_uid)
    if len(players) != 1 or "type:android.media.MediaPlayer" not in players[0]:
        _fail("Pre-interruption playback was not one native MediaPlayer.", output)
        return False
    return True


def _validate_post_activity(
    activities: str,
    app_component: str,
    helper_component: str,
    output: Path,
) -> str | None:
    lines = activities.splitlines()
    graph = _parse_activity_graph(activities)
    if graph is None:
        _fail("Post-interruption activity graph was malformed or ambiguous.", output)
        return None
    pinned_ids = {
        task.task_id
        for task in graph.tasks
        if _task_field(task, "mode") == "pinned"
    }
    if pinned_ids:
        _fail("A pinned task remained after focus interruption.", output)
        return None

    helper_histories = _component_histories(graph, helper_component)
    if len(helper_histories) != 1:
        _fail("Expected one global exact interruption helper history owner.", output)
        return None
    helper_history = helper_histories[0]
    helper_identity = helper_history.identity
    helper_task_id = helper_identity[2]
    helper_task = helper_history.parent
    if (
        helper_task.task_id != helper_task_id
        or _task_field(helper_task, "mode") != "fullscreen"
        or _task_field(helper_task, "visible") != "true"
        or _task_field(helper_task, "visibleRequested") != "true"
    ):
        _fail("The exact helper task was not visible and fullscreen.", output)
        return None

    helper_activity_identities = {
        identity
        for line in lines
        if (identity := _activity_identity(line)) is not None
        and identity[1] == helper_component
    }
    if helper_activity_identities != {helper_identity}:
        _fail("Helper Activity occurrences did not share one exact identity.", output)
        return None
    helper_windows = [
        identity
        for line in helper_history.lines
        for identity in _window_identities(line)
        if identity[1] == helper_component
    ]
    if len(helper_windows) != 1:
        _fail("The helper task did not have one exact window identity.", output)
        return None
    for prefix, label in (
        ("topResumedActivity=", "topResumedActivity"),
        ("ResumedActivity:", "ResumedActivity"),
        ("mFocusedApp=", "mFocusedApp"),
    ):
        anchor = _unique_anchor(lines, prefix)
        if anchor is None or _activity_identity(anchor) != helper_identity:
            _fail(f"{label} was not the exact interruption helper.", output)
            return None
    current_focus = _unique_anchor(lines, "mCurrentFocus=")
    current_windows = (
        [] if current_focus is None else _window_identities(current_focus)
    )
    if len(current_windows) != 1 or current_windows[0] != helper_windows[0]:
        _fail("mCurrentFocus was not the exact helper window.", output)
        return None
    focused_root = _unique_anchor(lines, "topDisplayFocusedRootTask=")
    if focused_root is None or _task_id(focused_root) != helper_task_id:
        _fail("The focused root was not the exact helper task.", output)
        return None
    active_pattern = re.compile(
        r"\bstate=(?:RESUMED|STARTED|PAUSING|PAUSED|STOPPING)\b"
    )
    for history in _component_histories(graph, app_component):
        finished = " f}}" in history.lines[0] or any(
            "finishing=true" in line for line in history.lines
        )
        active = any(
            active_pattern.search(line)
            or "mVisibleRequested=true" in line
            or "nowVisible=true" in line
            for line in history.lines
        )
        if active and not finished:
            _fail("The native PiP Activity remained active or visible.", output)
            return None
    return helper_task_id


def _validate_post_focus(
    audio: str,
    app_package: str,
    helper_package: str,
    app_uid: str,
    helper_uid: str,
    helper_component: str,
    output: Path,
) -> bool:
    entries = _parse_focus_section(audio)
    if entries is None or len(entries) != 1:
        _fail("Post-interruption focus stack was not one unique helper owner.", output)
        return False
    entry = entries[0]
    helper_class = helper_component.split("/", 1)[1]
    manager = _focus_client_manager(entry.client, helper_class)
    if (
        entry.package != helper_package
        or entry.uid != helper_uid
        or entry.gain != "GAIN"
        or entry.loss != "none"
        or entry.usage != "USAGE_MEDIA"
        or entry.content != "CONTENT_TYPE_MOVIE"
        or manager is None
    ):
        _fail("Post-interruption focus was not transferred to the helper.", output)
        return False
    request_lines = [
        line
        for line in audio.splitlines()
        if "requestAudioFocus()" in line
        and helper_package in line
    ]
    requests: list[_FocusRequest] = []
    for line in request_lines:
        request = _parse_focus_request(line)
        if request is None or request.package != helper_package:
            _fail("A helper audio-focus request row was malformed.", output)
            return False
        requests.append(request)
    current_requests = [request for request in requests if request.uid == helper_uid]
    request = current_requests[0] if len(current_requests) == 1 else None
    if (
        request is None
        or not requests
        or requests[-1] is not request
        or request.package != helper_package
        or request.uid != helper_uid
        or request.usage != "USAGE_MEDIA"
        or request.content != "CONTENT_TYPE_MOVIE"
        or request.gain != "1"
        or request.client != entry.client
    ):
        _fail("The helper's granted GAIN request was not uniquely observable.", output)
        return False
    if _started_players(audio, app_uid) or _started_players(audio, helper_uid):
        _fail("Playback remained started after the interruption terminal.", output)
        return False
    return True


def main() -> int:
    args = _arguments()
    output = Path(args.output)
    if output.is_symlink():
        print("Interruption result path must not be a symlink.", file=sys.stderr)
        return 1
    if (
        _COMPONENT_PATTERN.fullmatch(args.app_component) is None
        or _COMPONENT_PATTERN.fullmatch(args.helper_component) is None
        or not args.app_uid.isdigit()
        or not args.helper_uid.isdigit()
        or args.app_uid == args.helper_uid
        or _NONCE_PATTERN.fullmatch(args.nonce) is None
    ):
        return _fail("Interruption identity arguments were malformed or ambiguous.", output)

    input_specs = (
        ("resolved_component", args.resolved_component, "Resolved component"),
        ("start_output", args.start_output, "Start output"),
        ("pre_activities", args.pre_activities, "Pre activities"),
        ("pre_audio", args.pre_audio, "Pre audio"),
        ("post_activities", args.post_activities, "Post activities"),
        ("post_audio", args.post_audio, "Post audio"),
        ("logcat", args.logcat, "Logcat"),
    )
    values: dict[str, str] = {}
    for key, path, label in input_specs:
        value = _read_regular(path, label, output)
        if value is None:
            return 1
        values[key] = value

    if not _validate_component(
        values["resolved_component"], args.helper_component, output
    ):
        return 1
    start_lines = [line.strip() for line in values["start_output"].splitlines()]
    if start_lines.count("Status: ok") != 1 or start_lines.count(
        f"Activity: {args.helper_component}"
    ) != 1:
        return _fail("Explicit helper start did not settle on the exact component.", output)
    if not _validate_pre_owner(
        values["pre_activities"],
        values["pre_audio"],
        args.app_component,
        args.helper_component,
        args.app_package,
        args.app_uid,
        output,
    ):
        return 1

    helper_task_id = _validate_post_activity(
        values["post_activities"],
        args.app_component,
        args.helper_component,
        output,
    )
    if helper_task_id is None:
        return 1
    if not _validate_post_focus(
        values["post_audio"],
        args.app_package,
        args.helper_package,
        args.app_uid,
        args.helper_uid,
        args.helper_component,
        output,
    ):
        return 1

    native_terminal = "[MKNOON_PIP] TERMINAL state=stopped reason=interrupted"
    logcat_lines = values["logcat"].splitlines()
    helper_attempts = [
        (index, line.strip())
        for index, line in enumerate(logcat_lines)
        if re.search(
            r"\[MKNOON_PIP_INTERRUPT\] "
            r"(?:FOCUS_REQUEST_REJECTED|FOCUS_REQUEST|REJECTED)(?=\s|$)",
            line,
        )
    ]
    native_indexes = [
        index for index, line in enumerate(logcat_lines) if native_terminal in line
    ]
    all_native_terminals = [
        line for line in logcat_lines if "[MKNOON_PIP] TERMINAL " in line
    ]
    helper_grant = (
        None
        if len(helper_attempts) != 1
        else re.search(
            r"\[MKNOON_PIP_INTERRUPT\] FOCUS_REQUEST "
            r"nonce=(?P<nonce>[0-9a-f]{32}) "
            r"gain=(?P<gain>[A-Z0-9_]+) "
            r"usage=(?P<usage>[A-Z0-9_]+) "
            r"content=(?P<content>[A-Z0-9_]+) "
            r"result=(?P<result>[a-z]+) uid=(?P<uid>\d+)\s*$",
            helper_attempts[0][1],
        )
    )
    if (
        helper_grant is None
        or helper_grant.group("nonce") != args.nonce
        or helper_grant.group("gain") != "GAIN"
        or helper_grant.group("usage") != "USAGE_MEDIA"
        or helper_grant.group("content") != "CONTENT_TYPE_MOVIE"
        or helper_grant.group("result") != "granted"
        or helper_grant.group("uid") != args.helper_uid
        or len(native_indexes) != 1
        or len(all_native_terminals) != 1
        or helper_attempts[0][0] >= native_indexes[0]
    ):
        return _fail(
            "Focus grant and exact interrupted terminal were not unique and ordered.",
            output,
        )

    normalized = (
        "interruptionProof=true "
        f"helperTaskId={helper_task_id} helperTopResumed=true "
        "helperFocused=true focusGain=GAIN distinctUid=true nativeTerminals=1 "
        "alternateTerminals=0 pinnedTasks=0 nativeActive=false "
        "proofStartedPlayers=0\n"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
    temporary.write_text(normalized, encoding="utf-8")
    os.replace(temporary, output)
    print(normalized, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
