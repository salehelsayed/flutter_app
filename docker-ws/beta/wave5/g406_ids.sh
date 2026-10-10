#!/bin/bash
# Plan 406: print each emulator's libp2p peer id (from the E2E identity export).
ADBB=$HOME/Library/Android/sdk/platform-tools/adb
for S in emulator-5554 emulator-5556; do
  echo "$S $($ADBB -s $S shell "run-as com.mknoon.app cat app_flutter/intro_e2e_identity.json" | python3 -c "import json,sys;print(json.loads(json.load(sys.stdin)['qrPayload'])['ns'])")"
done
