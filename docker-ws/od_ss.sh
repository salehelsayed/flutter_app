#!/bin/bash
# Read-only: count of FlutterSecureStorage entries of the test package and a sha256 prefix per (encrypted) entry name. Never values.
P=com.mknoon.sims.t011; S=21071FDF600CSC
adb -s $S shell "run-as $P sh -c 'ls shared_prefs; cat shared_prefs/FlutterSecureStorage.xml 2>/dev/null'" | grep -o '<string name="[^"]*"' | sed 's/<string name="//; s/"$//' | while read n; do printf '%s' "$n" | shasum -a 256 | cut -c1-10; done | sort > /tmp/df_ss_$$.txt
echo "entries=$(wc -l < /tmp/df_ss_$$.txt | tr -d ' ')"; cat /tmp/df_ss_$$.txt; rm -f /tmp/df_ss_$$.txt
