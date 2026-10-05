#!/bin/bash
# Read-only: any flutter/xcode build processes and who holds the tail pipes.
ps -axo pid=,ppid=,etime=,command= | grep -E "build ios|xcodebuild|flutter_tools|XCBBuildService|Runner.xcworkspace|pod " | grep -v grep | cut -c1-170
echo "--- tail 15093 fds:"; lsof -p 15093 2>/dev/null | grep -E "PIPE|FIFO" | head -3
