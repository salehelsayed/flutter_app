#!/bin/bash
# Hourly cleanup part 2 (owner 11-01), flutter_app's OWN finished test output only. Explicit paths, no globs outside them.
# Keeps: summary/result files (*.tsv, summary.txt, verdict.md, results.json, final-verification.json, timeline/notes),
# protected restore DerivedData (129-prod, 194-prod, 195-prod-you), store DerivedData, in-use IN-008 DerivedData,
# the prod 192 restore APK, the in-use 196 APK, the 129 store AAB/IPA (inside the worktree, untouched).
#   host-run bash docker-ws/cleanup_own_20261101.sh
R=/Volumes/CrucialX9/flutter_app; L=$R/.codex-test-logs
before=$(df -k / | awk 'NR==2{print $4}'); beforeX=$(df -k /Volumes/CrucialX9 | awk 'NR==2{print $4}')
rmdir_safe() { [ -e "$1" ] && rm -rf "$1" && echo "deleted ${1#$HOME/}"; }
# DerivedData of finished test builds (home disk)
for d in tmp-dd-161 tmp-dd-179-keep tmp-dd-181-keep tmp-dd-182-keep tmp-dd-codexui-notif; do rmdir_safe "$HOME/$d"; done
# Test APKs of pushed or released work (not store builds, not the prod 192 restore, not the in-use 196)
for f in p0-phone-20261031/build191/apk/pixel-191.apk push3-20261101/build193/apk/pixel-193.apk a1-proof-20261101/apk/pixel-195.apk \
         owner129-install-20261031/apk/pixel-190.apk candidate129-188-20261030/apk/pixel-188.apk candidate129-189-20261030/apk/pixel-189.apk \
         orbit3d129-20261030/apk/pixel-183.apk; do [ -f "$L/$f" ] && rm -f "$L/$f" && echo "deleted $f"; done
# Bulky raw lane logs of pushed runs (keep summary.txt)
for d in p0-merge-20261031/lanes p0-merge-20261031/lanes2 p0-merge-20261031/lanes3 push3-20261101/lanes push3-20261101/lanes2 push4-20261101/lanes; do
  [ -d "$L/$d/report" ] && find "$L/$d/report" -type f \( -name '*.raw.log' -o -name 'partial.json' -o -name 'plan.json' \) -delete && echo "raw lane logs removed in $d"
  [ -f "$L/$d/run.log" ] && rm -f "$L/$d/run.log"
done
# Bulky raw device logs of the finished P0 campaign and proofs (keep verdicts, timelines, tsv, notes)
for d in p0-phone-20261031 a1-proof-20261101 codexui-notif-red-20261101 codexui-notif-green-20261101; do
  [ -d "$L/$d" ] && find "$L/$d" -type f \( -name '*syslog*.txt' -o -name '*logcat*.txt' -o -name '*logcat*.log' -o -name 'xcodebuild_test.log' -o -name '*.mp4' -o -name '*.png' \) -size +1M -not -path '*/testmedia/*' -delete && echo "raw device logs removed in $d"
done
after=$(df -k / | awk 'NR==2{print $4}'); afterX=$(df -k /Volumes/CrucialX9 | awk 'NR==2{print $4}')
echo "freed internal $(( (after-before)/1024/1024 )) GB, external $(( (afterX-beforeX)/1024/1024 )) GB"
