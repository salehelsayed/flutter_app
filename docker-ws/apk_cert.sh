#!/bin/bash
# Print the signer cert SHA-256 of an APK (read-only).
#   host-run bash docker-ws/apk_cert.sh <apk>
BT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"* | sort -V | tail -1)
"$BT/apksigner" verify --print-certs "$1" 2>&1 | grep -E "SHA-256|SHA-1" | head -2
