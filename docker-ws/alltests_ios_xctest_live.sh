#!/bin/bash
# Read-only: is an xcodebuild test (not build-for-testing) running against the iPhone 11 right now?
ps ax -o etime=,command= | grep -E "xcodebuild (test|test-without-building)" | grep -v grep | grep -E "00008030-001A6D2801BB802E" | cut -c1-160
