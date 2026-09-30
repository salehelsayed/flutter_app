#!/bin/bash
# Read-only: full Telecom event history lines for the app's recent calls.
. "$(dirname "$0")/beta_env.sh"
$ADB shell dumpsys telecom 2>/dev/null | grep -E "^\s+[0-9:.]+ - (CREATED|SET_|DESTROYED|REQUEST_DISCONNECT|SET_DISCONNECTED|CALL_ANSWERED|REJECT|START_CONNECTION|CommSess)|Call TC@|CommSess" | tail -30
