#!/bin/bash
# Read-only: size and path of the T011 test package's data files on the Pixel (no contents).
adb -s 21071FDF600CSC shell "run-as com.mknoon.sims.t011 sh -c 'cd /data/data/com.mknoon.sims.t011 && ls -lR databases shared_prefs app_flutter 2>/dev/null'" | awk 'NF>=8 && $1 ~ /^-/ {print $5, $NF} /:$/ {print}'
