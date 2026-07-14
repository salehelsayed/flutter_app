#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

evidence_dir="${1:-build/android-renderer-manifest-contract}"
mkdir -p "$evidence_dir"

ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false \
ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=false \
  ./android/gradlew -p android \
    :app:processProfileMainManifest \
    :app:processReleaseMainManifest \
    --console=plain \
    >"$evidence_dir/gradle.log" 2>&1

profile_manifest="build/app/intermediates/merged_manifest/profile/processProfileMainManifest/AndroidManifest.xml"
release_manifest="build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml"

for manifest in "$profile_manifest" "$release_manifest"; do
  if [[ ! -s "$manifest" ]]; then
    printf 'Merged manifest missing: %s\n' "$manifest" >&2
    exit 1
  fi
done

cp "$profile_manifest" "$evidence_dir/profile-merged-manifest.xml"
cp "$release_manifest" "$evidence_dir/release-merged-manifest.xml"

python3 - \
  "$evidence_dir/profile-merged-manifest.xml" \
  "$evidence_dir/release-merged-manifest.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = "{http://schemas.android.com/apk/res/android}"
ENABLE_IMPELLER = "io.flutter.embedding.android.EnableImpeller"
IMPELLER_BACKEND = "io.flutter.embedding.android.ImpellerBackend"


def android_attr(element: ET.Element, name: str) -> str | None:
    return element.get(f"{ANDROID}{name}")


def exactly_one(elements: list[ET.Element], label: str) -> ET.Element:
    if len(elements) != 1:
        raise AssertionError(f"expected exactly one {label}, found {len(elements)}")
    return elements[0]


def inspect(path: Path) -> None:
    root = ET.parse(path).getroot()
    application = root.find("application")
    if application is None:
        raise AssertionError(f"{path}: missing application")

    all_metadata = list(root.iter("meta-data"))
    impeller = [
        node
        for node in all_metadata
        if android_attr(node, "name") == ENABLE_IMPELLER
    ]
    renderer_policy = exactly_one(impeller, f"{ENABLE_IMPELLER} metadata")
    if renderer_policy not in list(application):
        raise AssertionError(f"{path}: renderer policy is not application scoped")
    if android_attr(renderer_policy, "value") != "false":
        raise AssertionError(f"{path}: Impeller must be disabled")
    if any(
        android_attr(node, "name") == IMPELLER_BACKEND
        for node in all_metadata
    ):
        raise AssertionError(f"{path}: release-ignored ImpellerBackend is present")

    activities = list(application.findall("activity"))

    def activity(suffix: str) -> ET.Element:
        return exactly_one(
            [
                node
                for node in activities
                if (android_attr(node, "name") or "").endswith(suffix)
            ],
            suffix,
        )

    main = activity("MainActivity")
    pip = activity("ReceivedVideoPictureInPictureActivity")
    if android_attr(main, "hardwareAccelerated") != "true":
        raise AssertionError(f"{path}: MainActivity lost hardware acceleration")
    expected_pip = {
        "hardwareAccelerated": "true",
        "supportsPictureInPicture": "true",
        "resizeableActivity": "true",
    }
    for key, expected in expected_pip.items():
        if android_attr(pip, key) != expected:
            raise AssertionError(f"{path}: PiP {key} is not {expected}")

    providers = list(application.findall("provider"))
    egress = exactly_one(
        [
            node
            for node in providers
            if (android_attr(node, "name") or "").endswith(
                "ReceivedMediaEgressProvider"
            )
        ],
        "ReceivedMediaEgressProvider",
    )
    if android_attr(egress, "grantUriPermissions") != "true":
        raise AssertionError(f"{path}: media egress URI grants were disabled")

    mime_types = {
        android_attr(node, "mimeType")
        for node in main.iter("data")
        if android_attr(node, "mimeType")
    }
    for required in ("image/*", "video/*"):
        if required not in mime_types:
            raise AssertionError(f"{path}: missing share MIME type {required}")


for argument in sys.argv[1:]:
    inspect(Path(argument))

print(
    "PASS variants=profile,release renderer=Skia/OpenGLES "
    "impeller=false pip=true mediaShare=true mediaEgress=true"
)
PY
