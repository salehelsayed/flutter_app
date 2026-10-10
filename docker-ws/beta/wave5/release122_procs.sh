#!/bin/bash
ps -axo pid,etime,pcpu,command | grep -E "xcodebuild|swift-frontend|clang|ld64|go build|gomobile" | grep -v grep | awk "{print \$2, \$3, \$4}" | sort | uniq -c | sort -rn | head -8
ls -la /Volumes/CrucialX9/flutter_app/build/ios/archive/ 2>/dev/null | tail -3
sysctl -n vm.loadavg
