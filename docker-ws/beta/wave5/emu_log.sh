#!/bin/bash
tail -n 12 /tmp/emulator_$1.log 2>/dev/null | cut -c1-200; pgrep -fl "qemu-system.*-avd $1" | cut -c1-120
