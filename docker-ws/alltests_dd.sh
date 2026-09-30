#!/bin/bash
# Read-only: owner of a DerivedData folder + processes referencing it or building.
dd="$HOME/Library/Developer/Xcode/DerivedData/$1"
/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$dd/info.plist" 2>&1
ls -la "$dd/Build/Intermediates.noindex/Runner.build/Debug-iphonesimulator/NotificationService.build/Objects-normal/arm64/NotificationService_dependency_info.dat" 2>&1
echo "== builds =="; ps ax -o pid=,etime=,command= | grep -E "xcodebuild|XCBBuildService|SWBBuildService|flutter_tools.snapshot build" | grep -v grep | cut -c1-200
