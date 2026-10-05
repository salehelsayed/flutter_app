#!/bin/bash
# R2 open-issues (O1-O13) iPhone validation build, 2026-10-01.
# Copies the fix worktree (only read) into an isolated folder, checks the fix markers, and builds an iOS device
# release with FDC_FLOW_LOG=1 so Dart [FLOW] events reach the iPhone syslog. Same flags as build_ios_flowlog.sh
# (PRODUCTION_APNS, release voice-call defines incl. native iOS calls). Output: artifacts/beta-20260928/build-r2-o/
set -u
SRC=/Volumes/CrucialX9/flutter_app-r2-fixes-20261001
DST=/Volumes/CrucialX9/flutter_app-r2val
LIVE=/Volumes/CrucialX9/flutter_app
OUT="$LIVE/artifacts/beta-20260928/build-r2-o"
mkdir -p "$OUT"; RESULT="$OUT/result.txt"; : > "$RESULT"
note() { echo "[$(date '+%H:%M:%S')] $*" >> "$RESULT"; }

note "worktree: branch $(git -C "$SRC" rev-parse --abbrev-ref HEAD) head $(git -C "$SRC" rev-parse --short HEAD) dirty $(git -C "$SRC" status --porcelain | wc -l | tr -d ' ')"
git -C "$SRC" status --porcelain > "$OUT/worktree_status.txt"
git -C "$SRC" diff --stat > "$OUT/worktree_diffstat.txt"
T=$(mktemp); sed "s#^SRC=/Volumes/CrucialX9/flutter_app\$#SRC=$SRC#" "$LIVE/docker-ws/prepare_proof_checkout_5556.sh" > "$T"
grep -q "^SRC=$SRC\$" "$T" || { note "PREPARE SCRIPT PATCH FAILED"; exit 1; }
note "sync start"
PROOF_DST="$DST" PROOF_MAX_GB=12 bash "$T" > "$OUT/prepare.log" 2>&1 || { note "PREPARE FAILED (see prepare.log)"; exit 1; }
note "synced: $(tr '\n' ' ' < "$DST/.proof-checkout-provenance.txt")"
cd "$DST" || exit 2
for m in "lib/core/media/m4a_duration.dart:m4a" \
         "lib/features/conversation/application/chat_message_listener.dart:rchiv" \
         "lib/core/services/incoming_message_router.dart:readiness_proof" \
         "lib/features/call/application/incoming_call_pre_presentation_admission.dart:locked" \
         "lib/shared/widgets/media/audio_player_widget.dart:_isDisposing"; do
  grep -qiF "${m#*:}" "${m%%:*}" || { note "FIX MARKER MISSING ${m#*:} in ${m%%:*}"; exit 1; }
done
for f in $(cut -c4- "$OUT/worktree_status.txt"); do
  cmp -s "$SRC/$f" "$DST/$f" || { note "COPY DIFFERS from worktree: $f"; exit 1; }
done
note "copy matches every changed worktree file ($(wc -l < "$OUT/worktree_status.txt" | tr -d ' '))"

. "$LIVE/docker-ws/_flutter_sdk_env.sh"
STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-$(git -C "$SRC" rev-parse --short HEAD).r2o.flowlog.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/build_name.txt"; echo "$STAMP" > "$OUT/stamp.txt"
cp "$LIVE/tool/build/voice_call_release_defines.json" "$OUT/defines.json"
note "call defines (live tree, not in the worktree): $(tr -d '\n ' < "$OUT/defines.json")"
note "ios go bindings"
scripts/ensure_go_ios_bindings.sh > "$OUT/go_bindings.log" 2>&1 || { note "IOS FAILED (go bindings)"; exit 1; }
note "ios build $BUILD_NAME"
M=$(mktemp)
if flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
     --dart-define-from-file="$LIVE/tool/build/voice_call_release_defines.json" --dart-define=FDC_FLOW_LOG=1 \
     --build-name="$BUILD_NAME" --build-number="$STAMP" > "$OUT/ios_build.log" 2>&1 \
   && [ build/ios/iphoneos/Runner.app/Info.plist -nt "$M" ]; then
  g=$(LC_ALL=C grep -a -c "BridgeGenerateIdentity" build/ios/iphoneos/Runner.app/Runner 2>/dev/null)
  [ "${g:-0}" -ge 1 ] || { note "IOS FAILED (Go bridge not linked)"; exit 1; }
  note "IOS OK $BUILD_NAME bundleVersion=$STAMP go_linked=$g"
else
  note "IOS FAILED (see ios_build.log)"; exit 1
fi
note "R34 BUILD DONE"
