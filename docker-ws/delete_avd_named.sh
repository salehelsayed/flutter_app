#!/bin/bash
# Delete one disposable AVD that this session created. Only names starting with Oval_ or Fx_ are accepted.
#   host-run bash docker-ws/delete_avd_named.sh <name>
N="${1:?name}"; [[ "$N" =~ ^(Oval_|Fx_)[A-Za-z0-9_]+$ ]] || { echo "refused name"; exit 2; }
SDK="$HOME/Library/Android/sdk"; AVDM=$(ls "$SDK"/cmdline-tools/*/bin/avdmanager 2>/dev/null | head -1)
"$AVDM" delete avd -n "$N" 2>&1 | tail -2
