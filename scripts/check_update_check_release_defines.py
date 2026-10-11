#!/usr/bin/env python3
"""Release guard for the SE-41 update check kill switch.

Store builds must not ship with the update check turned off. Pass the exact
`flutter build` arguments; the guard reads every `--dart-define` and
`--dart-define-from-file` among them (and the MKNOON_UPDATE_CHECK environment
variable, in case someone expects flutter to read it) and exits 1 when any of
them sets MKNOON_UPDATE_CHECK=off.

Used by scripts/build_ios_appstore_ipa.sh, docker-ws/build_store_release.sh and
docker-ws/build_play_aab.sh.
"""

import json
import os
import pathlib
import sys

KEY = "MKNOON_UPDATE_CHECK"


def _defines_from_file(path):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        # flutter also accepts KEY=VALUE (.env style) files.
        data = {}
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                data[key.strip()] = value.strip()
    if not isinstance(data, dict):
        return []
    return [str(data[KEY])] if KEY in data else []


def update_check_values(args, environ):
    """Every MKNOON_UPDATE_CHECK value the build would see, with its source."""
    found = []
    if KEY in environ:
        found.append(("environment", environ[KEY]))
    index = 0
    while index < len(args):
        arg = args[index]
        value = None
        for flag in ("--dart-define", "--dart-define-from-file"):
            if arg == flag and index + 1 < len(args):
                value = (flag, args[index + 1])
                index += 1
            elif arg.startswith(flag + "="):
                value = (flag, arg[len(flag) + 1 :])
            if value:
                break
        if value:
            flag, payload = value
            if flag == "--dart-define":
                key, _, define = payload.partition("=")
                if key == KEY:
                    found.append(("--dart-define", define))
            else:
                for define in _defines_from_file(payload):
                    found.append((f"--dart-define-from-file={payload}", define))
        index += 1
    return found


def main(argv, environ=os.environ):
    try:
        values = update_check_values(argv, environ)
    except OSError as error:
        # Fail closed: an unreadable define file could hide MKNOON_UPDATE_CHECK=off.
        print(f"RELEASE GUARD FAILED: cannot read a define file: {error}", file=sys.stderr)
        return 1
    offending = [(source, value) for source, value in values if value.strip().lower() == "off"]
    if offending:
        for source, value in offending:
            print(
                f"RELEASE GUARD FAILED: {KEY}={value} (from {source}). "
                "Store builds must keep the SE-41 update check on. Remove the "
                f"{KEY}=off define; it is only for local and test builds.",
                file=sys.stderr,
            )
        return 1
    print(f"release guard OK: {KEY} is not off")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
