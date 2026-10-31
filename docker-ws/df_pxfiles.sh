#!/bin/bash
# Read-only: size, sha256 prefix and path of every file of the test package on the Pixel (internal + external), no contents.
P=com.mknoon.sims.t011
S=21071FDF600CSC
adb -s $S shell "run-as $P sh -c 'cd /data/data/$P && for f in \$(find . -type f ! -path \"./code_cache/*\"); do echo \$(stat -c %s \$f) \$(sha256sum \$f | cut -c1-12) \$f; done'"
echo "=== external"
adb -s $S shell "for d in /sdcard/Android/data/$P /sdcard/Android/media/$P; do [ -d \$d ] && find \$d -type f -exec stat -c '%s %n' {} +; done" 2>/dev/null
echo "=== end"
