#!/bin/bash
f="$HOME/.gradle/daemon/9.5.0/daemon-$1.out.log"; echo "log modified $(( $(date +%s) - $(stat -f %m "$f") )) s ago; size $(stat -f %z "$f")"
pgrep -fl "flutter_tools.snapshot" | cut -c1-160 | head -5
