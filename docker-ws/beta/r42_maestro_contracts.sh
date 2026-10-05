#!/bin/bash
# Run the maestro-flow-contracts unit tests directly inside the store snapshot.
cd /Volumes/CrucialX9/flutter_app-store-20261001 || exit 1
export PATH="$HOME/.maestro/bin:/opt/homebrew/bin:$PATH"
/opt/homebrew/opt/python@3.14/bin/python3.14 -m unittest scripts/test/maestro_flow_runner_test.py scripts/test/maestro_migration_metadata_test.py 2>&1 | tail -6
echo "R42 EXIT ${PIPESTATUS[0]}"
