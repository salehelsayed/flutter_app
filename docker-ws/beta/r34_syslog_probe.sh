#!/bin/bash
# Read-only: 8 s of unfiltered iPhone 11 syslog, to see whether the syslog relay delivers anything.
timeout 8 /opt/homebrew/bin/idevicesyslog -u 00008030-001A6D2801BB802E 2>&1 | head -5; echo "rc=$?"
idevice_id -l
