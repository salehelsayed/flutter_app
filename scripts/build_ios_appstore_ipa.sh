#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_PLIST="$ROOT_DIR/ios/ExportOptions-AppStore.plist"
LOCAL_EXPORT_PLIST="$ROOT_DIR/ios/ExportOptions.plist"

if [[ ! -f "$EXPORT_PLIST" ]]; then
  printf 'Missing export options plist: %s\n' "$EXPORT_PLIST" >&2
  exit 1
fi

if [[ -f "$LOCAL_EXPORT_PLIST" ]]; then
  local_method="$(
    /usr/libexec/PlistBuddy -c 'Print :method' "$LOCAL_EXPORT_PLIST" 2>/dev/null || true
  )"
  if [[ "$local_method" == "development" || "$local_method" == "debugging" ]]; then
    printf 'Note: ignoring local %s with method=%s\n' \
      "$LOCAL_EXPORT_PLIST" \
      "$local_method"
  fi
fi

printf 'Building App Store Connect IPA with %s\n' "$EXPORT_PLIST"
# Reserve a unique evidence directory before Flutter can overwrite shared output.
# Argument values are hashed by the helper, so defines cannot leak into metadata.
set -- --release --export-options-plist="$EXPORT_PLIST" --dart-define-from-file="$ROOT_DIR/tool/build/voice_call_release_defines.json" "$@"
capture_dir="$(python3 "$ROOT_DIR/scripts/ios_build_provenance.py" begin --root "$ROOT_DIR" -- "$@")"
(
  cd "$ROOT_DIR"
  # 1:1 voice calling is compile-time gated. The release carries the gates
  # from tool/build/voice_call_release_defines.json (see tool/build/README.md);
  # without them the app has no call button and presents no incoming call.
  flutter build ipa "$@"
)

retained_dir="$(python3 "$ROOT_DIR/scripts/ios_build_provenance.py" retain --root "$ROOT_DIR" --capture "$ROOT_DIR/$capture_dir" -- "$@")"
printf '\nRetained archive, symbols, IPA and provenance: %s\n' "$retained_dir"

ipa_dir="$ROOT_DIR/build/ios/ipa"
if [[ -d "$ipa_dir" ]]; then
  printf '\nIPA output:\n'
  find "$ipa_dir" -maxdepth 1 -type f -name '*.ipa' -print | sort
fi
