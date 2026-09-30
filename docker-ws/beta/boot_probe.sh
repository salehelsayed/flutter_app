#!/bin/bash
# Read-only: is emulator-5556 booting, boot-looping, or stuck?
. "$(dirname "$0")/beta_env.sh"
echo "now $(date '+%H:%M:%S')"
$ADB shell 'uptime; for p in sys.boot_completed dev.bootcomplete init.svc.zygote init.svc.zygote_secondary sys.system_server.start_count init.svc.bootanim; do echo "$p=$(getprop $p)"; done; pidof system_server || echo no-system_server'
echo "--- last fatal/crash lines"
$ADB logcat -d -b main,system,crash -v time 2>/dev/null | grep -E "FATAL|Fatal signal|system_server.*(crash|died)|WATCHDOG|Zygote.*(died|exit)|boot_progress|BootReceiver" | tail -12 | cut -c1-200
ps -axo pid,etime,command | grep -E "qemu-system|emulator -avd|emulator.*Pixel_7a" | grep -v grep | cut -c1-160
