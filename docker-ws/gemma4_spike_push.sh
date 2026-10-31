#!/bin/bash
# Gemma 4 spike: install APK, staged adb push of the model, private cp, size+sha on both copies, delete staging (HANDOFF.md steps).
set -u
P=21071FDF600CSC; PKG=com.mknoon.translatespike
D=/Volumes/CrucialX9/flutter_app/.codex-test-logs/gemma4-spike-20261028
F=/Volumes/CrucialX9/flutter_app/gemma-ai/gemma-4-E2B-it.litertlm
SD=/data/local/tmp/gemma4-spike-m318c81a5; T=$SD/model.litertlm; PRIV=files/gemma-4-E2B-it.litertlm
SZ=2588147712; SHA=181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
fail(){ echo "FAIL: $*"; exit 1; }
echo "install start $(date -u +%T)"; adb -s $P install -r "$D/gemma4-spike-debug.apk" 2>&1 | tail -1
adb -s $P shell run-as $PKG mkdir -p files || fail mkdir
echo "--- private files before push:"; adb -s $P shell run-as $PKG ls -la files cache 2>&1
adb -s $P shell mkdir -p $SD
echo "push start $(date -u +%T)"; adb -s $P push "$F" $T 2>&1 | tail -1
s=$(adb -s $P shell stat -c %s $T | tr -d '\r'); echo "staging size=$s"; [ "$s" = $SZ ] || fail staging size
h=$(adb -s $P shell sha256sum $T | cut -d ' ' -f 1 | tr -d '\r'); echo "staging sha=$h"; [ "$h" = $SHA ] || fail staging sha
echo "cp start $(date -u +%T)"; adb -s $P shell run-as $PKG cp $T $PRIV; echo "cp exit=$?"
s=$(adb -s $P shell run-as $PKG stat -c %s $PRIV | tr -d '\r'); echo "private size=$s"; [ "$s" = $SZ ] || fail private size
h=$(adb -s $P shell run-as $PKG sha256sum $PRIV | cut -d ' ' -f 1 | tr -d '\r'); echo "private sha=$h"; [ "$h" = $SHA ] || fail private sha
adb -s $P shell rm -f $T; adb -s $P shell rmdir $SD; echo "staging after delete:"; adb -s $P shell ls -la $SD 2>&1
adb -s $P shell run-as $PKG ls -l $PRIV
echo "done $(date -u +%T)"
