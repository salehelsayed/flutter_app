#!/bin/bash
# Owner-approved (10-29): delete ONLY the old hand-copied Gemma model Documents/gemma-4-E2B-it.litertlm in the Mknoon
# container on the iPhone 11. The new downloaded copy lives in Library/Application Support/gemma_translation/ and stays.
#   host-run bash docker-ws/iphone11_old_model_delete.sh check|delete
set -uo pipefail
U=00008030-001A6D2801BB802E; A=/opt/homebrew/bin/afcclient; F=Documents/gemma-4-E2B-it.litertlm
free() { timeout 60 /opt/homebrew/bin/ideviceinfo -u $U -q com.apple.disk_usage 2>&1 | grep -E '^AmountDataAvailable'; }
echo "== Documents listing"; timeout 60 $A -u $U --container com.mknoon.app ls Documents 2>&1 | head -20
echo "== info $F"; timeout 60 $A -u $U --container com.mknoon.app info "$F" 2>&1 | head -10
echo "== new copy info"; timeout 60 $A -u $U --container com.mknoon.app info "Library/Application Support/gemma_translation/gemma-4-E2B-it.litertlm" 2>&1 | grep -iE 'size|type' | head -3
echo "== free before"; free
[ "${1:-check}" = delete ] || exit 0
echo "== rm $F"; timeout 120 $A -u $U --container com.mknoon.app rm "$F" 2>&1; echo "rm exit=$?"
sleep 5
echo "== Documents after"; timeout 60 $A -u $U --container com.mknoon.app ls Documents 2>&1 | head -20
echo "== new copy still there"; timeout 60 $A -u $U --container com.mknoon.app info "Library/Application Support/gemma_translation/gemma-4-E2B-it.litertlm" 2>&1 | grep -iE 'size' | head -2
echo "== free after"; free
