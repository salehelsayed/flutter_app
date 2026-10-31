#!/bin/bash
# Read-only: list Xcode build-related processes (xcodebuild, XCBBuildService, SWBBuildService, swift-build, clang, ld, simctl, CoreSimulator boot) with pid, ppid, etime, pcpu, cwd and args cut.
#   host-run bash docker-ws/host_xcode_build_procs.sh
ps -axo pid=,ppid=,etime=,pcpu=,args= | grep -E 'xcodebuild|XCBBuildService|SWBBuildService|swift-build|swift-frontend|/clang |/ld |simctl|launchd_sim|SecurityAgent' | grep -v grep | while read -r pid ppid et cpu rest; do
  cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
  printf '%6s %6s %12s %5s cwd=%s | %s\n' "$pid" "$ppid" "$et" "$cpu" "$cwd" "$(echo "$rest" | cut -c1-140)"
done
exit 0
