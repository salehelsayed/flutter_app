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
(
  cd "$ROOT_DIR"
  flutter build ipa --release --export-options-plist="$EXPORT_PLIST" "$@"
)

ipa_dir="$ROOT_DIR/build/ios/ipa"
if [[ -d "$ipa_dir" ]]; then
  printf '\nIPA output:\n'
  find "$ipa_dir" -maxdepth 1 -type f -name '*.ipa' -print | sort
fi
