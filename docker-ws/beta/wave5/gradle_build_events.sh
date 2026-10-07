#!/bin/bash
# Read-only: recent build lifecycle lines from a Gradle daemon log (not health checks).
f="$HOME/.gradle/daemon/9.5.0/daemon-$1.out.log"
grep -nE "Starting build|testDebugUnitTest|BUILD (SUCCESSFUL|FAILED)|Waiting for another flutter|startup lock|Received command|Daemon is busy|Canceling|Build cancelled|Command execution" "$f" | tail -12 | cut -c1-200
