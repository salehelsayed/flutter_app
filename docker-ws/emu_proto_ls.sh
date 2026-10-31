#!/bin/bash
# Read-only: list emulator gRPC proto files shipped with the SDK and copy them into docker-ws/.emu_protos for a test helper.
D="$HOME/Library/Android/sdk/emulator/lib"; ls "$D"/*.proto 2>/dev/null | head -20
mkdir -p "$(dirname "$0")/.emu_protos"; cp "$D"/emulator_controller.proto "$(dirname "$0")/.emu_protos/" 2>/dev/null && echo copied
