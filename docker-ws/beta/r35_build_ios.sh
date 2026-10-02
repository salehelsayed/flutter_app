#!/bin/bash
# R2 open-issues follow-up iPhone build, 2026-10-01 (from r34_build_ios.sh): the main checkout now holds the
# fix worktree's changes plus the follow-up fixes. Copies the live tree (only read) into an isolated folder, checks the fix markers, and builds an iOS device
# release with FDC_FLOW_LOG=1 so Dart [FLOW] events reach the iPhone syslog. Same flags as build_ios_flowlog.sh
# (PRODUCTION_APNS, release voice-call defines incl. native iOS calls). Output: artifacts/beta-20260928/build-r2-o/
set -u
SRC=/Volumes/CrucialX9/flutter_app
DST=/Volumes/CrucialX9/flutter_app-r2val
LIVE=/Volumes/CrucialX9/flutter_app
OUT="$LIVE/artifacts/beta-20260928/build-r2-o2"
mkdir -p "$OUT"; RESULT="$OUT/result.txt"; : > "$RESULT"
note() { echo "[$(date '+%H:%M:%S')] $*" >> "$RESULT"; }

note "source: branch $(git -C "$SRC" rev-parse --abbrev-ref HEAD) head $(git -C "$SRC" rev-parse --short HEAD) dirty $(git -C "$SRC" status --porcelain | wc -l | tr -d ' ')"
note "sync start"
PROOF_DST="$DST" PROOF_MAX_GB=12 bash "$LIVE/docker-ws/prepare_proof_checkout_5556.sh" > "$OUT/prepare.log" 2>&1 || { note "PREPARE FAILED (see prepare.log)"; exit 1; }
note "synced: $(tr '\n' ' ' < "$DST/.proof-checkout-provenance.txt")"
cd "$DST" || exit 2
for m in "lib/core/media/m4a_duration.dart:m4a" \
         "ios/Runner/AppDelegate.swift:if !Self.firebaseConfigured {" \
         "lib/features/groups/application/drain_group_offline_inbox_use_case.dart:_settleV3PastEpochMessage" \
         "lib/features/groups/presentation/widgets/group_member_row.dart:inviteStatus != GroupInviteDeliveryStatus.unknown" \
         "lib/features/groups/presentation/screens/group_info_screen.dart:tooltip: l10n.action_back"; do
  grep -qiF "${m#*:}" "${m%%:*}" || { note "FIX MARKER MISSING ${m#*:} in ${m%%:*}"; exit 1; }
done
note "fix markers present (fixer changes + follow-up fixes)"

. "$LIVE/docker-ws/_flutter_sdk_env.sh"
STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-$(git -C "$SRC" rev-parse --short HEAD).r2o2.flowlog.t${STAMP}"
echo "$BUILD_NAME" > "$OUT/build_name.txt"; echo "$STAMP" > "$OUT/stamp.txt"
cp "$LIVE/tool/build/voice_call_release_defines.json" "$OUT/defines.json"
note "call defines: $(tr -d '\n ' < "$OUT/defines.json")"
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
note "R35 BUILD DONE"
