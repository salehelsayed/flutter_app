#!/bin/bash
# Read-only: tail of a Gradle daemon log.
tail -n "${2:-25}" "$HOME/.gradle/daemon/9.5.0/daemon-$1.out.log" 2>/dev/null | cut -c1-220
