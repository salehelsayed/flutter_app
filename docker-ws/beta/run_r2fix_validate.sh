#!/bin/bash
# R2-1 fix validation on the two phones (fix builds installed in place):
#  V0 the old stuck dissolve ("Beta Group n4") must now show as dissolved on the Pixel
#  V1 iPhone admin dissolves a new group  -> Pixel member must show it dissolved
#  V2 iPhone admin removes the Pixel      -> Pixel must show it was removed
#  V3 Pixel admin dissolves a new group    -> iPhone member must show it dissolved
# After each case: count SIGNED_AUDIT_REJECTED lines on the member since the case started.
# Usage: run_r2fix_validate.sh [case ...]   (default: V0 V1 V2 V3)
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
bash "$H/logs_start.sh" > /dev/null
RUN=$(current_run)
TL="$RUN/timeline.txt"
CASES="${*:-V0 V1 V2 V3}"
S=$(date +%H%M)
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$TL"; }
F=r2
mkdir -p "$RUN/crash" "$RUN/extra"
ls ~/Library/Logs/DiagnosticReports/ > "$RUN/crash/baseline_list.txt" 2>/dev/null
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
pkill -f "adb -s $SERIAL logcat -T 1 -v threadtime" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 < /dev/null &
sleep 1; pgrep -f "logcat -T 1 -v threadtime" | tail -1 > "$RUN/logcat.pid"
IOS_T0=$(date '+%Y-%m-%d %H:%M:%S')
ios_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null; }
log "R2FIX VALIDATE start cases=[$CASES] builds: android=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') ios=$(ios_version) mac_load=$(sysctl -n vm.loadavg | awk '{print $2}')"
pid_and() { $ADB shell pidof $PKG 2>/dev/null | tr -d '\r'; }
ensure_apps() {
  [ -z "$(pid_and)" ] && { $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 20; }
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
}
emu_now() { $ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r'; }
and_rejections_since() {  # and_rejections_since "<MM-DD HH:MM:SS>" : SIGNED_AUDIT_REJECTED on the Pixel since then
  awk -v s="$1" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt" | grep -c 'SIGNED_AUDIT_REJECTED'
}
ios_rejections_since() {  # ios_rejections_since "<YYYY-MM-DD HH:MM:SS>"
  xcrun simctl spawn "$UDID" log show --start "$1" --style compact --predicate 'process == "Runner"' 2>/dev/null | grep -c 'SIGNED_AUDIT_REJECTED'
}
case_on() { case " $CASES " in *" $1 "*) return 0 ;; esac; return 1; }
ensure_apps

if case_on V0; then
  e0=$(emu_now)
  log "=== V0 old stuck dissolve (Beta Group n4) on the Pixel"
  bash "$H/run_flow.sh" android $F/vd_check_dissolved.yaml v0_old_dissolve "GROUP=Beta Group n4"
  log "V0 Pixel SIGNED_AUDIT_REJECTED since start: $(and_rejections_since "$e0"); lines: $(awk -v s="$e0" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt" | grep -oE 'SIGNED_AUDIT_REJECTED","details":\{[^}]*' | sort | uniq -c | head -3 | tr '\n' ' ')"
fi
if case_on V1; then
  N=v1$S; e0=$(emu_now)
  log "=== V1 iPhone admin dissolves R2 Group $N; the Pixel is the member"
  bash "$H/pair.sh" v1_create $F/t16_create_ios.yaml $F/t16_accept_android.yaml NONCE=$N
  bash "$H/run_flow.sh" ios $F/vd_dissolve.yaml v1_dissolve "GROUP=R2 Group $N"
  bash "$H/run_flow.sh" android $F/vd_check_dissolved.yaml v1_member_sees "GROUP=R2 Group $N"
  log "V1 Pixel SIGNED_AUDIT_REJECTED since the case started: $(and_rejections_since "$e0")"
fi
if case_on V2; then
  N=v2$S; e0=$(emu_now)
  log "=== V2 iPhone admin removes the Pixel from R2 Group $N"
  bash "$H/pair.sh" v2_create $F/t16_create_ios.yaml $F/t16_accept_android.yaml NONCE=$N
  bash "$H/run_flow.sh" ios $F/t21_ginfo_ios.yaml v2_ginfo NONCE=$N
  bash "$H/dump_ui.sh" v2_ginfo ios > /dev/null 2>&1
  POINT=$(/usr/bin/python3 - "$RUN/ui/v2_ginfo_ios.json" <<'PY'
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
  log "V2 remove icon point: '$POINT'"
  [ -n "$POINT" ] && bash "$H/run_flow.sh" ios $F/t21_tap_point_ios.yaml v2_remove "POINT=$POINT"
  bash "$H/run_flow.sh" android $F/vd_check_removed.yaml v2_member_sees "GROUP=R2 Group $N"
  log "V2 Pixel SIGNED_AUDIT_REJECTED since the case started: $(and_rejections_since "$e0")"
fi
if case_on V3; then
  N=v3$S; i0=$(date '+%Y-%m-%d %H:%M:%S')
  log "=== V3 Pixel admin dissolves R2 Group $N; the iPhone is the member"
  bash "$H/pair.sh" v3_create $F/vr_accept_ios.yaml $F/vr_create_android.yaml NONCE=$N
  bash "$H/run_flow.sh" android $F/vd_dissolve.yaml v3_dissolve "GROUP=R2 Group $N"
  bash "$H/run_flow.sh" ios $F/vd_check_dissolved.yaml v3_member_sees "GROUP=R2 Group $N"
  log "V3 iPhone SIGNED_AUDIT_REJECTED since the case started: $(ios_rejections_since "$i0")"
fi

now=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$IOS_T0" --end "$now" \
  --predicate 'process == "Runner"' > "$RUN/ios_log_validate.txt" 2>&1
log "ios log: $(wc -l < "$RUN/ios_log_validate.txt") lines"
log "Pixel SIGNED_AUDIT_REJECTED whole run: $(grep -c SIGNED_AUDIT_REJECTED "$RUN/android_logcat_live.txt"); iPhone whole run: $(grep -c SIGNED_AUDIT_REJECTED "$RUN/ios_log_validate.txt")"
for f in $(ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null); do
  grep -qx "$f" "$RUN/crash/baseline_list.txt" || cp ~/Library/Logs/DiagnosticReports/"$f" "$RUN/crash/" 2>/dev/null
done
log "new crash reports: $(ls "$RUN/crash" | grep -v baseline_list | tr '\n' ' ')"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
log "R2FIX VALIDATE DONE"
