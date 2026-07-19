#!/bin/bash
# Stop a wedged run_fresh_all_phones.sh (hung devicectl tunnel to a detached
# iPhone) BEFORE it reaches the Pixel phase and wipes the Pixel identity.
pkill -f 'run_fresh_all_phones.sh' && echo "killed run_fresh_all_phones.sh" || echo "script not running"
pkill -f 'devicectl device install' && echo "killed hung devicectl install" || true
pkill -f 'devicectl device uninstall' && echo "killed hung devicectl uninstall" || true
exit 0
