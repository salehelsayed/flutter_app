#!/bin/bash
# Plan 406: is the build script alive, and what are its children?
date
ps -axo pid,ppid,etime,%cpu,command | grep -E "g406_build_all|flutter build|flutter_tools.snapshot build|xcodebuild -|ensure_go_ios|make ios|gomobile" | grep -v grep | cut -c1-200 | head -12
echo "--- Runner.app mtime: $(stat -f %Sm /Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406/build/ios/iphoneos/Runner.app/Runner 2>&1)"
echo "--- bridge symbols: $(grep -c BridgeGenerateIdentity /Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406/build/ios/iphoneos/Runner.app/Runner 2>&1)"
defaults read /Volumes/CrucialX9/flutter_app/.claude/worktrees/go-upgrade-406/build/ios/iphoneos/Runner.app/Info.plist CFBundleVersion 2>&1
