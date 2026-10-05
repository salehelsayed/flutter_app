#!/bin/bash
# Read-only: the iPhone 11 caller's mailbox_store wake results in all r2o capture dirs.
for d in /Volumes/CrucialX9/flutter_app/docker-ws/deploy-captures/r2o-*; do
  cat "$d"/iphone11_syslog*.txt 2>/dev/null | grep -E '"operation":"mailbox_store"' | grep -oE '^Oct  1 [0-9:]+|"wake":"[a-z_]+"|"result":(true|false)' | paste - - - 
done | sort -u
