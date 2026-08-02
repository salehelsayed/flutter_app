#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

evidence_dir="${1:-build/dropped-push-recovery-manifest-contract}"
mkdir -p "$evidence_dir"

./android/gradlew -p android \
  :app:processDebugMainManifest \
  --console=plain \
  >"$evidence_dir/gradle.log" 2>&1

merged_manifest="build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml"
if [[ ! -s "$merged_manifest" ]]; then
  printf 'Merged manifest missing: %s\n' "$merged_manifest" >&2
  exit 1
fi

cp "$merged_manifest" "$evidence_dir/debug-merged-manifest.xml"

python3 - "$evidence_dir/debug-merged-manifest.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = "{http://schemas.android.com/apk/res/android}"
MESSAGING_ACTION = "com.google.firebase.MESSAGING_EVENT"
CUSTOM_OWNER = "com.mknoon.app.MknoonFirebaseMessagingService"
FLUTTERFIRE_OWNER = (
    "io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService"
)
FIREBASE_FALLBACK = "com.google.firebase.messaging.FirebaseMessagingService"


def android_attr(element: ET.Element, name: str) -> str | None:
    return element.get(f"{ANDROID}{name}")


def exactly_one(elements: list[ET.Element], label: str) -> ET.Element:
    if len(elements) != 1:
        raise AssertionError(f"expected exactly one {label}, found {len(elements)}")
    return elements[0]


path = Path(sys.argv[1])
root = ET.parse(path).getroot()
application = root.find("application")
if application is None:
    raise AssertionError(f"{path}: missing application")

services = list(application.findall("service"))


def named(name: str) -> list[ET.Element]:
    return [service for service in services if android_attr(service, "name") == name]


if named(FLUTTERFIRE_OWNER):
    raise AssertionError(f"{path}: FlutterFire messaging owner was reintroduced")

custom = exactly_one(named(CUSTOM_OWNER), "MKnoon messaging owner")
fallback = exactly_one(named(FIREBASE_FALLBACK), "Firebase SDK fallback")


def messaging_filters(service: ET.Element) -> list[ET.Element]:
    return [
        intent_filter
        for intent_filter in service.findall("intent-filter")
        if any(
            android_attr(action, "name") == MESSAGING_ACTION
            for action in intent_filter.findall("action")
        )
    ]


custom_filter = exactly_one(messaging_filters(custom), "MKnoon messaging filter")
fallback_filter = exactly_one(
    messaging_filters(fallback), "Firebase fallback messaging filter"
)
if android_attr(custom_filter, "priority") != "500":
    raise AssertionError(f"{path}: MKnoon messaging priority is not 500")
if android_attr(fallback_filter, "priority") != "-500":
    raise AssertionError(f"{path}: Firebase fallback priority is not -500")
if android_attr(custom, "exported") != "false":
    raise AssertionError(f"{path}: MKnoon messaging owner must remain non-exported")

all_messaging_filters = [
    intent_filter
    for service in services
    for intent_filter in messaging_filters(service)
]
if len(all_messaging_filters) != 2:
    raise AssertionError(
        f"{path}: expected two messaging filters, found {len(all_messaging_filters)}"
    )

print(
    "PASS flutterfireOwner=0 mknoonOwner=1 mknoonPriority=500 "
    "firebaseFallback=1 firebasePriority=-500 messagingFilters=2"
)
PY
