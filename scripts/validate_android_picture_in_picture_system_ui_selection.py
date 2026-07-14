#!/usr/bin/env python3

import json
import os
import stat
import sys


SCHEMA = "mknoon.android-pip-system-ui-control.v1"
KEYS = {
    "schema",
    "selectorSource",
    "resourceId",
    "contentDescription",
    "bounds",
    "center",
    "geometryEvidence",
}


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate selection key: {key}")
        result[key] = value
    return result


def require_plain_string(value, label, *, nonempty=False):
    if not isinstance(value, str) or "\n" in value or "\r" in value:
        raise ValueError(f"invalid selection string: {label}")
    if nonempty and not value:
        raise ValueError(f"empty selection string: {label}")
    return value


def require_int_list(value, length, label):
    if (
        not isinstance(value, list)
        or len(value) != length
        or any(type(entry) is not int for entry in value)
    ):
        raise ValueError(f"invalid selection list: {label}")
    return value


def validate(input_path, output_path):
    metadata = os.lstat(input_path)
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise ValueError("selection input must be one regular single-link file")
    with open(input_path, "r", encoding="utf-8") as handle:
        value = json.load(handle, object_pairs_hook=reject_duplicate_keys)
    if not isinstance(value, dict) or set(value) != KEYS:
        raise ValueError("selection keys did not match exact schema")
    if value["schema"] != SCHEMA:
        raise ValueError("selection schema did not match")
    selector_source = require_plain_string(
        value["selectorSource"], "selectorSource", nonempty=True
    )
    resource_id = require_plain_string(value["resourceId"], "resourceId")
    description = require_plain_string(
        value["contentDescription"], "contentDescription"
    )
    evidence = require_plain_string(value["geometryEvidence"], "geometryEvidence")
    bounds = require_int_list(value["bounds"], 4, "bounds")
    center = require_int_list(value["center"], 2, "center")
    if (
        bounds[2] <= bounds[0]
        or bounds[3] <= bounds[1]
        or not bounds[0] <= center[0] <= bounds[2]
        or not bounds[1] <= center[1] <= bounds[3]
    ):
        raise ValueError("selection bounds or center were invalid")

    lines = [
        f"selectorSource={selector_source}",
        f"resourceId={resource_id}",
        f"contentDescription={description}",
        f"bounds={' '.join(map(str, bounds))}",
        f"center={' '.join(map(str, center))}",
        f"geometryEvidence={evidence}",
    ]
    if os.path.lexists(output_path):
        raise ValueError("normalized selection output already exists")
    temporary = f"{output_path}.tmp.{os.getpid()}"
    try:
        with open(temporary, "x", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.rename(temporary, output_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    if len(sys.argv) != 3:
        raise ValueError("usage: validator <selection.json> <normalized.txt>")
    validate(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(3)
