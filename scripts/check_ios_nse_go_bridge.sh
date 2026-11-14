#!/usr/bin/env bash
# Store-build gate: the NotificationService extension must carry the Go decrypt bridge (GoMknoonNSE).
# Without ios/Runner/GoMknoonNSE.xcframework at pod-install time the Podfile silently drops the pod and the
# extension compiles a throw-only stub, so every push fails to decrypt. A linked bridge carries the Go runtime.
# Only stops a bad build; never changes it. Usage: check_ios_nse_go_bridge.sh <.ipa | .app | directory holding one .ipa>
set -euo pipefail
target="${1:?usage: check_ios_nse_go_bridge.sh <ipa|app|dir>}"
if [[ -d "$target" && "$target" != *.app ]]; then
  ipas=()
  while IFS= read -r f; do ipas+=("$f"); done < <(find "$target" -type f -name '*.ipa' | sort)
  [[ ${#ipas[@]} -eq 1 ]] || { echo "NSE gate FAILED: expected exactly one .ipa under $target, found ${#ipas[@]}" >&2; exit 1; }
  target="${ipas[0]}"
fi
work=""
if [[ "$target" == *.ipa ]]; then
  work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
  unzip -q "$target" 'Payload/*/PlugIns/NotificationService.appex/NotificationService' -d "$work"
  nse="$(find "$work/Payload" -path '*/PlugIns/NotificationService.appex/NotificationService' -type f | head -1)"
else
  nse="$target/PlugIns/NotificationService.appex/NotificationService"
fi
[[ -n "${nse:-}" && -f "$nse" ]] || { echo "NSE gate FAILED: NotificationService binary missing in $1" >&2; exit 1; }
# Debug builds move the extension's code into NotificationService.debug.dylib next to a small launcher.
files=("$nse"); [[ -f "$nse.debug.dylib" ]] && files+=("$nse.debug.dylib")
if [[ "$target" == *.ipa ]]; then unzip -q -o "$target" 'Payload/*/PlugIns/NotificationService.appex/NotificationService.debug.dylib' -d "$work" 2>/dev/null || true; [[ -f "$nse.debug.dylib" ]] && files=("$nse" "$nse.debug.dylib"); fi
build_id=0; goexit=0; size=0
for f in "${files[@]}"; do
  build_id=$(( build_id + $(grep -a -c 'Go build ID' "$f" || true) ))
  goexit=$(( goexit + $(grep -a -c 'runtime.goexit' "$f" || true) ))
  size=$(( size + $(wc -c < "$f" | tr -d ' ') ))
done
if [[ "$build_id" -gt 0 && "$goexit" -gt 0 ]]; then
  echo "NSE gate PASS: Go decrypt bridge linked (size=$size go_build_id=$build_id runtime_goexit=$goexit)"
else
  echo "NSE gate FAILED: NotificationService has no Go runtime (size=$size go_build_id=$build_id runtime_goexit=$goexit): GoMknoonNSE bridge missing, push decryption would fail" >&2
  exit 1
fi
