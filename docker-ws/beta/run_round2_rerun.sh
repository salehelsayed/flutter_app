#!/bin/bash
# Round 2 re-run of the scenarios whose first run failed for test-flow reasons
# (wrong chat, non-last message edit, leftover menu, short media waits, long typing).
# Same log capture as run_round2.sh, new run folder and nonce.
# Usage: run_round2_rerun.sh [block ...]   (default: A2 B2 C2)
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
. "$H/gates.sh"
N=r$(date +%H%M)
TL="$RUN/timeline.txt"
BLOCKS="${*:-A2 B2 C2 D2 E2}"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
F=r2
echo "$N" > "$RUN/nonce.txt"
mkdir -p "$RUN/crash" "$RUN/extra"
ls ~/Library/Logs/DiagnosticReports/ > "$RUN/crash/baseline_list.txt" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
pkill -f "adb -s $SERIAL logcat -T 1 -v threadtime" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
sleep 1; pgrep -f "logcat -T 1 -v threadtime" | tail -1 > "$RUN/logcat.pid"
IOS_T0=$(date '+%Y-%m-%d %H:%M:%S')
log "RERUN start nonce=$N blocks=[$BLOCKS] mac_load=$(host_load)"
ios_chunk() {
  local now; now=$(date '+%Y-%m-%d %H:%M:%S')
  xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
    --predicate 'process == "Runner"' > "$RUN/ios_log_$1.txt" 2>&1
  log "ios log chunk $1: $(wc -l < "$RUN/ios_log_$1.txt") lines"
  IOS_T0=$now
}
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
ensure_apps() {
  [ -z "$(pid_and)" ] && { $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 20; }
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
}
stop_and() { $ADB shell am force-stop $PKG; log "pixel app force-stopped (pid now: '$(pid_and)')"; }
start_and() { $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; log "pixel app launched"; sleep 20; }
block() { case " $BLOCKS " in *" $1 "*) return 0 ;; esac; return 1; }

if block A2; then
  log "=== BLOCK A2 messaging re-run"
  ensure_apps
  bash "$H/pair.sh" t09r_text $F/t09r_ios.yaml $F/t09r_android.yaml NONCE=$N
  bash "$H/pair.sh" t10_burst $F/t10_ios.yaml $F/t10_android.yaml NONCE=$N
  bash "$H/dump_ui.sh" t10_after > /dev/null 2>&1
  bash "$H/pair.sh" t13_delete_for_me $F/t13_ios.yaml $F/t13_android.yaml NONCE=$N
  bash "$H/pair.sh" t12_seed $F/t12_seed_ios.yaml $F/t12_seed_android.yaml NONCE=$N
  stop_and
  bash "$H/run_flow.sh" ios $F/t12_mutate_ios.yaml t12_mutate NONCE=$N
  sleep 10; start_and
  bash "$H/run_flow.sh" android $F/t12_check_android.yaml t12_check NONCE=$N
  ios_chunk A2
fi
if block B2; then
  log "=== BLOCK B2 media re-run"
  # The Pixel composer was stuck at "Processing 45%" (video transcode stall, main run T02).
  # Record whether it survives an app restart, then continue.
  bash "$H/dump_ui.sh" b2_before_restart android > /dev/null 2>&1
  $ADB shell am force-stop $PKG; start_and
  bash "$H/run_flow.sh" android cal_ensure.yaml b2_after_restart
  bash "$H/dump_ui.sh" b2_after_restart android > /dev/null 2>&1
  log "b2 composer after restart: $(grep -c 'Processing' "$RUN/ui/b2_after_restart_android.json") 'Processing' nodes"
  ensure_apps
  bash "$H/pair.sh" t01_photo $F/t01_ios.yaml $F/t01_android.yaml NONCE=$N
  bash "$H/pair.sh" t03_view_once $F/t03_ios.yaml $F/t03_android.yaml NONCE=$N
  ( for i in $(seq 1 40); do
      f=$($ADB shell dumpsys window windows 2>/dev/null | grep -E "mCurrentFocus|SECURE" | tr -d '\r' | tr '\n' ' ' | cut -c1-300)
      $ADB exec-out screencap -p > "$RUN/extra/t04_screencap_$i.png" 2>/dev/null
      echo "[$(date '+%H:%M:%S')] $i size=$(stat -f %z "$RUN/extra/t04_screencap_$i.png") $f" >> "$RUN/extra/t04_secure_samples.txt"
      sleep 6
    done ) &
  SAMPLER=$!
  bash "$H/pair.sh" t04_protected $F/t04_ios.yaml $F/t04_android.yaml NONCE=$N
  kill $SAMPLER 2>/dev/null
  bash "$H/pair.sh" t05_photo_ios $F/t05_ios.yaml $F/t05_android.yaml NONCE=$N
  bash "$H/pair.sh" t02_album $F/t02_ios.yaml $F/t02_android.yaml NONCE=$N
  ios_chunk B2
fi
ready_calls() {
  $ADB shell svc wifi enable; $ADB shell svc data enable
  ensure_apps
  bash "$H/pair.sh" ready_$1 cal_ensure.yaml cal_ensure.yaml
  gate "$1"
}
diag() { bash "$H/call_diag_windows.sh" "$2-$3" > "$RUN/diag_$1.txt" 2>&1; }
utc_now() { date -u '+%H:%M:%S'; }
if block D2; then
  log "=== BLOCK D2 group rename re-run on a fresh group (the first rename tapped the heading, not the field)"
  ensure_apps
  bash "$H/pair.sh" t16_create $F/t16_create_ios.yaml $F/t16_accept_android.yaml NONCE=$N
  bash "$H/run_flow.sh" ios $F/t16_rename_ios.yaml t16_rename NONCE=$N
  bash "$H/run_flow.sh" android $F/t16_check_android.yaml t16_check NONCE=$N
  bash "$H/pair.sh" t17_group_react_reply $F/t17_ios.yaml $F/t17_android.yaml NONCE=$N
  # T21 remove + re-add, T22 leave, on the fresh group
  bash "$H/run_flow.sh" ios $F/t21_ginfo_ios.yaml t21_ginfo NONCE=$N
  bash "$H/dump_ui.sh" t21_ginfo ios > /dev/null 2>&1
  POINT=$(/usr/bin/python3 - "$RUN/ui/t21_ginfo_ios.json" <<'PY'
import json, re, sys
raw = open(sys.argv[1]).read(); root = json.loads(raw[raw.find("{"):])
hits = []
def walk(n):
    a = n.get("attributes", {})
    if (a.get("accessibilityText") or "").strip() == "Manage role":
        hits.append([int(x) for x in re.findall(r"\d+", a.get("bounds", ""))])
    for c in n.get("children", []): walk(c)
walk(root)
if hits:
    x1, y1, x2, y2 = hits[0]; print(f"{x2 + (x2 - x1) // 2},{(y1 + y2) // 2}")
PY
)
  log "t21 remove icon point: '${POINT}'"
  if [ -n "$POINT" ]; then
    bash "$H/run_flow.sh" ios $F/t21_tap_point_ios.yaml t21_remove "POINT=$POINT"
    bash "$H/run_flow.sh" android $F/t21_removed_android.yaml t21_removed NONCE=$N
    bash "$H/run_flow.sh" ios $F/t21_readd_ios.yaml t21_readd NONCE=$N
    bash "$H/pair.sh" t21_back $F/t21_check_ios.yaml $F/t21_accept_android.yaml NONCE=$N
  fi
  bash "$H/run_flow.sh" android $F/t22_leave_android.yaml t22_leave NONCE=$N
  bash "$H/run_flow.sh" ios $F/t22_check_ios.yaml t22_check NONCE=$N
  ios_chunk D2
fi
if block E2; then
  log "=== BLOCK E2 archive re-run (the first run matched the tab label without its count)"
  ensure_apps
  bash "$H/run_flow.sh" android $F/t14_archive_android.yaml t14_archive NONCE=$N
  bash "$H/run_flow.sh" ios $F/t14_ios.yaml t14_send NONCE=$N
  bash "$H/run_flow.sh" android $F/t14_check_android.yaml t14_check NONCE=$N
  # T15 block / unblock (the chat of a blocked contact is hidden from home: unblock from the list)
  bash "$H/run_flow.sh" android $F/t15_block_android.yaml t15_block NONCE=$N
  bash "$H/run_flow.sh" ios $F/t15_blocked_ios.yaml t15_blocked_send_call NONCE=$N
  bash "$H/run_flow.sh" android $F/t15_unblock_android.yaml t15_unblock NONCE=$N
  bash "$H/run_flow.sh" ios $F/t15_after_ios.yaml t15_after NONCE=$N
  bash "$H/run_flow.sh" android $F/t15_check_android.yaml t15_check NONCE=$N
  ios_chunk E2
fi
if block C2; then
  log "=== BLOCK C2 calls re-run"
  ready_calls t27; t0=$(utc_now)
  bash "$H/pair_callee_first.sh" t27_redial $F/t27_ios.yaml $F/t27_android.yaml NONCE=$N
  diag t27 "$t0" "$(utc_now)"
  # T32 again with the 4-minute hold timed by this script (Maestro cut a 120 s wait to 0.3 s)
  ready_calls t32b; t0=$(utc_now)
  bash "$H/pair_callee_first.sh" t32b_connect connect_ios_caller.yaml connect_android_callee.yaml TAG=t32b HOLD=1000
  log "t32b connected; holding 240 s"
  sleep 240
  bash "$H/run_flow.sh" ios $F/t32b_end_ios.yaml t32b_end
  diag t32b "$t0" "$(utc_now)"
  ios_chunk C2
fi
if block F2; then
  log "=== BLOCK F2 iPhone Arabic + accessibility text size (first try ran while the simulator was stuck in landscape)"
  ensure_apps
  xcrun simctl ui "$UDID" content_size accessibility-extra-large
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; sleep 2
  xcrun simctl launch "$UDID" "$BUNDLE" -AppleLanguages "(ar)" -AppleLocale ar_SA >/dev/null 2>&1
  log "t35b iphone: content_size=$(xcrun simctl ui "$UDID" content_size 2>&1) launched with -AppleLanguages (ar)"
  bash "$H/pair.sh" t35b_iphone_ar $F/t35_tour.yaml $F/t35_decline.yaml NONCE=$N
  xcrun simctl ui "$UDID" content_size large
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; sleep 2
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
  log "t35b iphone restored: content_size=$(xcrun simctl ui "$UDID" content_size 2>&1)"
  ios_chunk F2
fi
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "RERUN DONE"
