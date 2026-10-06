#!/bin/bash
# Validate selection/inventory metadata in the main checkout (host git is fast; container git is not).
cd /Volumes/CrucialX9/flutter_app || exit 1
python3 scripts/mknoon_checks.py validate --output /tmp/wave5-validate-$$ 2>&1 | tail -6
