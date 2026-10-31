#!/bin/bash
# Read-only: names, sizes and sha256 prefixes in the test package's account_migration dir. Never contents.
P=com.mknoon.sims.t011; S=21071FDF600CSC
adb -s $S shell "run-as $P sh -c 'cd /data/data/$P/app_flutter 2>/dev/null && if [ -d account_migration ]; then find account_migration | while read f; do if [ -f \"\$f\" ]; then echo \$(stat -c %s \"\$f\") \$(sha256sum \"\$f\" | cut -c1-12) \"\$f\"; else echo dir \"\$f\"; fi; done; else echo no-account_migration-dir; fi'"
