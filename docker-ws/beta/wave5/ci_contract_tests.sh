#!/bin/bash
# Run the same validation the CI metadata job runs, on the Mac.
cd /Volumes/CrucialX9/flutter_app || exit 1
python3 scripts/mknoon_checks.py validate --output /tmp/w5-ci-validate 2>&1 | tail -1
python3 -m unittest discover -s scripts/test -p '*checks_test.py' 2>&1 | tail -3
python3 -m unittest discover -s scripts/test -p 'testing_inventory_test.py' 2>&1 | tail -3
