#!/bin/bash
# Beta round 2 (2026-09-27): scenarios the first round did not try. Same two phones
# (iPhone 15 simulator, Pixel 7a emulator-5556), same builds as the last device runs
# (all beta fixes), production relay. Logs: live Android logcat for the whole run,
# iPhone unified log exported per phase, crash reports copied at the end.
# Phases: A messaging edge cases + offline, B media, C calls, D groups, E archive/block, F system.
# Usage: run_round2.sh [phase ...]   (default: A B C D E F)
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
. "$H/gates.sh"
N=${NONCE_OVERRIDE:-q$(date +%H%M)}
TL="$RUN/timeline.txt"
PHASES="${*:-A B C D E F}"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
utc_now() { date -u '+%H:%M:%S'; }
F=r2
echo "$N" > "$RUN/nonce.txt"
mkdir -p "$RUN/crash" "$RUN/extra"
ls ~/Library/Logs/DiagnosticReports/ > "$RUN/crash/baseline_list.txt" 2>/dev/null
# live Android logcat for the whole run (own session, survives the bridge)
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
pkill -f "adb -s $SERIAL logcat -T 1 -v threadtime" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
sleep 1; pgrep -f "logcat -T 1 -v threadtime" | tail -1 > "$RUN/logcat.pid"
IOS_T0=$(date '+%Y-%m-%d %H:%M:%S')
ios_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null; }
log "ROUND2 start nonce=$N phases=[$PHASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version)"
log "mknoun.xyz -> mac: $(dscacheutil -q host -a name mknoun.xyz | awk '/ip_address/ {print $2}' | tr '\n' ' ') mac_load=$(host_load)"

ios_chunk() {  # export the iPhone app log since the last chunk
  local now; now=$(date '+%Y-%m-%d %H:%M:%S')
  xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
    --predicate 'process == "Runner"' > "$RUN/ios_log_$1.txt" 2>&1
  log "ios log chunk $1: $(wc -l < "$RUN/ios_log_$1.txt") lines ($IOS_T0 .. $now)"
  IOS_T0=$now
}
diag() { bash "$H/call_diag_windows.sh" "$2-$3" > "$RUN/diag_$1.txt" 2>&1; }
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
ensure_apps() {  # both apps running (no restart when already up)
  [ -z "$(pid_and)" ] && { $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 20; }
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
}
ready_calls() {  # full readiness before a call scenario
  $ADB shell svc wifi enable; $ADB shell svc data enable
  ensure_apps
  bash "$H/pair.sh" ready_$1 cal_ensure.yaml cal_ensure.yaml
  gate "$1"
}
stop_and() { $ADB shell am force-stop $PKG; log "pixel app force-stopped (pid now: '$(pid_and)')"; }
start_and() { $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; log "pixel app launched"; sleep 20; }
wait_and_log() {  # wait_and_log <regex> <seconds>: 0 when the regex appears in the live logcat after now
  local start i
  start=$($ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r')
  for i in $(seq 1 "$2"); do
    tail -c 3000000 "$RUN/android_logcat_live.txt" | grep -E "$1" | awk -v s="$start" '($1 " " $2) >= s' | grep -q . && return 0
    sleep 1
  done
  return 1
}
wait_media_connected() { wait_and_log '"trigger":"mediaConnected"' 150; }

phase() { case " $PHASES " in *" $1 "*) return 0 ;; esac; return 1; }

# ============ A: messaging edge cases and offline
if phase A; then
  log "=== PHASE A messaging"
  ensure_apps
  bash "$H/pair.sh" t09_text $F/t09_ios.yaml $F/t09_android.yaml NONCE=$N
  bash "$H/pair.sh" t10_burst $F/t10_ios.yaml $F/t10_android.yaml NONCE=$N
  bash "$H/dump_ui.sh" t10_after > /dev/null 2>&1
  bash "$H/pair.sh" t13_delete_for_me $F/t13_ios.yaml $F/t13_android.yaml NONCE=$N
  # T11 sender offline
  bash "$H/pair.sh" t11_prep - cal_ensure.yaml
  $ADB shell svc wifi disable; $ADB shell svc data disable
  log "t11 pixel network OFF (ping: $($ADB shell 'ping -c 1 -W 2 mknoun.xyz >/dev/null 2>&1 && echo up || echo down' | tr -d '\r'))"
  bash "$H/run_flow.sh" android $F/t11_android.yaml t11_offline_send NONCE=$N
  sleep 40
  $ADB shell svc wifi enable; $ADB shell svc data enable
  log "t11 pixel network ON"
  bash "$H/run_flow.sh" ios $F/t11_ios.yaml t11_receive NONCE=$N
  bash "$H/run_flow.sh" android $F/t11_android_after.yaml t11_after NONCE=$N
  # T12 mutations while the Pixel app is stopped
  bash "$H/pair.sh" t12_seed $F/t12_seed_ios.yaml $F/t12_seed_android.yaml NONCE=$N
  stop_and
  bash "$H/run_flow.sh" ios $F/t12_mutate_ios.yaml t12_mutate NONCE=$N
  sleep 10
  start_and
  bash "$H/run_flow.sh" android $F/t12_check_android.yaml t12_check NONCE=$N
  ios_chunk A
fi

# ============ B: media
if phase B; then
  log "=== PHASE B media"
  ensure_apps
  bash "$H/pair.sh" t01_photo $F/t01_ios.yaml $F/t01_android.yaml NONCE=$N
  bash "$H/pair.sh" t02_album $F/t02_ios.yaml $F/t02_android.yaml NONCE=$N
  bash "$H/pair.sh" t03_view_once $F/t03_ios.yaml $F/t03_android.yaml NONCE=$N
  # T04: protected photo on the Pixel; sample the window flags and screenshots while it is open
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
  ios_chunk B
fi

# ============ C: calls
if phase C; then
  log "=== PHASE C calls"
  ready_calls t24; t0=$(utc_now)
  bash "$H/pair_callee_first.sh" t24_controls $F/t24_ios.yaml $F/t24_android.yaml
  diag t24 "$t0" "$(utc_now)"
  ready_calls t25; t0=$(utc_now)
  bash "$H/pair_callee_first.sh" t25_home_in_call $F/t25_ios.yaml $F/t25_android.yaml
  diag t25 "$t0" "$(utc_now)"
  ready_calls t26; t0=$(utc_now)
  START=$(( $(date +%s) * 1000 + 110000 )); log "t26 glare start_ms=$START"
  bash "$H/pair.sh" t26_glare $F/t26.yaml $F/t26.yaml START_MS=$START
  diag t26 "$t0" "$(utc_now)"
  ready_calls t27; t0=$(utc_now)
  bash "$H/pair_callee_first.sh" t27_redial $F/t27_ios.yaml $F/t27_android.yaml NONCE=$N
  diag t27 "$t0" "$(utc_now)"
  ready_calls t28; t0=$(utc_now)
  bash "$H/pair_callee_first.sh" t28_recording $F/t28_ios.yaml $F/t28_android.yaml
  diag t28 "$t0" "$(utc_now)"
  ready_calls t29; t0=$(utc_now)
  bash "$H/pair_callee_first.sh" t29_wifi_switch $F/t29_ios.yaml connect_android_callee.yaml TAG=t29 HOLD=110000 &
  P=$!
  if wait_media_connected; then
    sleep 10
    $ADB shell svc wifi disable
    sleep 3
    log "t29 pixel Wi-Fi OFF, mobile data ON (ping: $($ADB shell 'ping -c 1 -W 3 mknoun.xyz >/dev/null 2>&1 && echo up || echo down' | tr -d '\r'))"
    sleep 40
    $ADB shell svc wifi enable
    log "t29 pixel Wi-Fi ON"
  else
    log "t29 no mediaConnected within 150 s; Wi-Fi left on"
  fi
  wait $P
  diag t29 "$t0" "$(utc_now)"
  ready_calls t30; t0=$(utc_now)
  $ADB shell input keyevent KEYCODE_HOME; sleep 3
  log "t30 pixel app in background (pid $(pid_and))"
  bash "$H/pair_callee_first.sh" t30_bg_callee $F/t30_ios.yaml $F/t30_android.yaml
  diag t30 "$t0" "$(utc_now)"
  ready_calls t31; t0=$(utc_now)
  bash "$H/run_flow.sh" ios $F/t31_home_ios.yaml t31_home
  bash "$H/run_flow.sh" android $F/t31_android.yaml t31_bg_ios_callee &
  P=$!
  if wait_and_log '"event":"CALL_STATE_TRANSITION".*"(inviting|ringing|outgoing)' 150; then
    log "t31 pixel is calling; iPhone app comes to the front in 20 s"; sleep 20
  else log "t31 no outgoing call seen in 150 s"; fi
  bash "$H/run_flow.sh" ios $F/t31_front_ios.yaml t31_front
  wait $P
  diag t31 "$t0" "$(utc_now)"
  ready_calls t32; t0=$(utc_now)
  bash "$H/pair_callee_first.sh" t32_long_call $F/t32_ios.yaml $F/t32_android.yaml
  diag t32 "$t0" "$(utc_now)"
  ios_chunk C
fi

# ============ D: groups
if phase D; then
  log "=== PHASE D groups"
  ensure_apps
  bash "$H/pair.sh" t16_create $F/t16_create_ios.yaml $F/t16_accept_android.yaml NONCE=$N
  bash "$H/run_flow.sh" ios $F/t16_rename_ios.yaml t16_rename NONCE=$N
  bash "$H/run_flow.sh" android $F/t16_check_android.yaml t16_check NONCE=$N
  bash "$H/pair.sh" t17_group_edits $F/t17_ios.yaml $F/t17_android.yaml NONCE=$N
  bash "$H/pair.sh" t18_group_media $F/t18_ios.yaml $F/t18_android.yaml NONCE=$N
  bash "$H/run_flow.sh" android $F/t18_fwd_android.yaml t18_forwarded NONCE=$N
  bash "$H/run_flow.sh" ios $F/t19_make_admin_ios.yaml t19_make_admin NONCE=$N
  bash "$H/run_flow.sh" android $F/t19_android.yaml t19_pixel_admin NONCE=$N
  bash "$H/run_flow.sh" ios $F/t19_check_ios.yaml t19_remove_admin NONCE=$N
  stop_and
  bash "$H/run_flow.sh" ios $F/t20_ios.yaml t20_group_offline_send NONCE=$N
  sleep 10; start_and
  bash "$H/run_flow.sh" android $F/t20_android.yaml t20_group_offline_recv NONCE=$N
  # T21: the member remove icon has no accessibility label; tap the point right of "Manage role"
  bash "$H/run_flow.sh" ios $F/t21_ginfo_ios.yaml t21_ginfo NONCE=$N
  bash "$H/dump_ui.sh" t21_ginfo ios > /dev/null 2>&1
  POINT=$(/usr/bin/python3 - "$RUN/ui/t21_ginfo_ios.json" <<'PY'
import json, re, sys
raw = open(sys.argv[1]).read(); root = json.loads(raw[raw.find("{"):])
hits = []
def walk(n):
    a = n.get("attributes", {})
    if (a.get("accessibilityText") or "").strip() == "Manage role":
        m = re.findall(r"\d+", a.get("bounds", "")); hits.append([int(x) for x in m])
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
  bash "$H/run_flow.sh" ios $F/t23_dissolve_ios.yaml t23_dissolve NONCE=$N
  bash "$H/run_flow.sh" android $F/t23_check_android.yaml t23_check NONCE=$N
  ios_chunk D
fi

# ============ E: archive and block
if phase E; then
  log "=== PHASE E archive / block"
  ensure_apps
  bash "$H/run_flow.sh" android $F/t14_archive_android.yaml t14_archive NONCE=$N
  bash "$H/run_flow.sh" ios $F/t14_ios.yaml t14_send NONCE=$N
  bash "$H/run_flow.sh" android $F/t14_check_android.yaml t14_check NONCE=$N
  bash "$H/run_flow.sh" android $F/t15_block_android.yaml t15_block NONCE=$N
  t0=$(utc_now)
  bash "$H/run_flow.sh" ios $F/t15_blocked_ios.yaml t15_blocked_send_call NONCE=$N
  diag t15 "$t0" "$(utc_now)"
  bash "$H/run_flow.sh" android $F/t15_unblock_android.yaml t15_unblock NONCE=$N
  bash "$H/run_flow.sh" ios $F/t15_after_ios.yaml t15_after NONCE=$N
  bash "$H/run_flow.sh" android $F/t15_check_android.yaml t15_check NONCE=$N
  ios_chunk E
fi

# ============ F: system
if phase F; then
  log "=== PHASE F system"
  ensure_apps
  # T33: message to a killed (not force-stopped) Pixel app, opened from the notification
  bash "$H/pair.sh" t33_prep - cal_ensure.yaml
  $ADB shell input keyevent KEYCODE_HOME; sleep 3
  $ADB shell am kill $PKG; sleep 2
  [ -n "$(pid_and)" ] && { $ADB shell "run-as $PKG kill -9 $(pid_and)" 2>/dev/null; sleep 2; }
  log "t33 pixel app killed in the background (pid now: '$(pid_and)')"
  bash "$H/run_flow.sh" ios $F/t33_ios.yaml t33_send NONCE=$N
  sleep 60
  log "t33 pixel pid after the messages: '$(pid_and)'"
  $ADB shell dumpsys notification --noredact 2>/dev/null | grep -E "pkg=$PKG|android.title|android.text" | head -40 > "$RUN/extra/t33_notifications.txt"
  log "t33 notification lines: $(wc -l < "$RUN/extra/t33_notifications.txt")"
  $ADB shell cmd statusbar expand-notifications; sleep 2
  bash "$H/run_flow.sh" android $F/t33_android.yaml t33_open NONCE=$N
  $ADB shell cmd statusbar collapse
  ensure_apps
  # T34: landscape
  bash "$H/pair.sh" t34_landscape $F/t34.yaml $F/t34.yaml NONCE=$N
  $ADB shell settings put system user_rotation 0
  # T35a: Pixel in Arabic with 1.6x text, the iPhone declines its call
  $ADB shell settings put system font_scale 1.6
  $ADB shell cmd locale set-app-locales $PKG --user 0 --locales ar
  $ADB shell am force-stop $PKG; start_and
  log "t35a pixel: font_scale=$($ADB shell settings get system font_scale | tr -d '\r') locales=$($ADB shell cmd locale get-app-locales $PKG --user 0 | tr -d '\r')"
  bash "$H/pair.sh" t35a_pixel_ar $F/t35_decline.yaml $F/t35_tour.yaml NONCE=$N
  $ADB shell settings put system font_scale 1.0
  $ADB shell "cmd locale set-app-locales $PKG --user 0 --locales ''"
  $ADB shell am force-stop $PKG; start_and
  log "t35a pixel restored: font_scale=$($ADB shell settings get system font_scale | tr -d '\r') locales=$($ADB shell cmd locale get-app-locales $PKG --user 0 | tr -d '\r')"
  # T35b: iPhone in Arabic with accessibility text size, the Pixel declines its call
  xcrun simctl ui "$UDID" content_size accessibility-extra-large
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; sleep 2
  xcrun simctl launch "$UDID" "$BUNDLE" -AppleLanguages "(ar)" -AppleLocale ar_SA >/dev/null 2>&1
  log "t35b iphone: content_size=$(xcrun simctl ui "$UDID" content_size 2>&1) launched with -AppleLanguages (ar)"
  bash "$H/pair.sh" t35b_iphone_ar $F/t35_tour.yaml $F/t35_decline.yaml NONCE=$N
  xcrun simctl ui "$UDID" content_size large
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null; sleep 2
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
  log "t35b iphone restored: content_size=$(xcrun simctl ui "$UDID" content_size 2>&1)"
  ios_chunk F
fi

# ============ end: dumps, crash reports, Android crash/ANR records
bash "$H/dump_ui.sh" final > /dev/null 2>&1
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
$ADB shell dumpsys dropbox --print data_app_crash > "$RUN/extra/android_dropbox_crash.txt" 2>&1
$ADB shell dumpsys dropbox --print data_app_anr > "$RUN/extra/android_dropbox_anr.txt" 2>&1
$ADB shell dumpsys dropbox --print data_app_native_crash > "$RUN/extra/android_dropbox_native_crash.txt" 2>&1
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "ROUND2 RUN DONE"
