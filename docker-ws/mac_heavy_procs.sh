#!/bin/bash
# Read-only: load, swap and memory pressure, plus Gradle/Kotlin daemons, emulators, simulators and xcodebuild with RSS (MB).
#   host-run bash docker-ws/mac_heavy_procs.sh
uptime | sed 's/.*load/load/'
sysctl -n vm.swapusage
memory_pressure 2>/dev/null | grep -E "free percentage|Swapouts" | head -2
ps -axo pid=,rss=,etime=,args= | grep -E "GradleDaemon|KotlinCompileDaemon|kotlin-daemon|qemu-system|CoreSimulator/.*launchd_sim|xcodebuild|flutter_tester|dartvm" | grep -v grep | awk '{printf "%s %dMB %s ", $1, $2/1024, $3; for(i=4;i<=NF&&i<9;i++) printf "%s ", substr($i,1,60); print ""}'
