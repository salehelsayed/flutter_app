# Round-3 Android validation helpers (2026-10-08). Sourced by the case scripts; runs in the Claude container.
# Pixel 6 (physical, 21071FDF600CSC) = Android side; iPhone 13 (physical, USB) = the other side, driven via ap.py.
export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
V3="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$V3/../../.." && pwd)"
OUT="${OUT:-$ROOT/artifacts/beta-20261008}"
mkdir -p "$OUT/shots" "$OUT/logs" "$OUT/ui"
PX=21071FDF600CSC
PKG=com.mknoon.app
padb() { timeout 60 /claude-host-bin/adb -s "$PX" "$@"; }
ios() { timeout 300 python3 "$V3/../ap.py" 13 "$@"; }
ts() { date -u '+%H:%M:%S'; }
note() { echo "[$(ts)] $*" | tee -a "$OUT/timeline.txt"; }
p_now_ms() { padb shell date +%s%3N | tr -d '\r'; }
p_wake() { padb shell dumpsys power | grep -m1 -oE 'mWakefulness=[A-Za-z]+' | cut -d= -f2; }
p_keyguard() { padb shell dumpsys window | grep -m1 -oE 'isKeyguardShowing=[a-z]+|mKeyguardShowing=[a-z]+' | cut -d= -f2; }
p_top() { padb shell dumpsys activity activities | grep -m1 topResumedActivity | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.$]+' | head -1; }
p_pid() { padb shell pidof "$PKG" | tr -d '\r'; }
p_shot() { padb shell screencap -p /sdcard/v3.png; padb pull /sdcard/v3.png "$OUT/shots/$1.png" >/dev/null 2>&1; echo "$OUT/shots/$1.png"; }
p_dump() {  # p_dump <name>: UI tree to ui/<name>.xml; prints text/content-desc of every node
  padb shell rm -f /sdcard/v3.xml
  padb shell uiautomator dump /sdcard/v3.xml >/dev/null 2>&1
  padb shell cat /sdcard/v3.xml > "$OUT/ui/$1.xml"
  grep -oE '(text|content-desc)="[^"]+"' "$OUT/ui/$1.xml" | sed -E 's/^(text|content-desc)=//' | tr '\n' ' '
}
p_tap_node() {  # p_tap_node <name> <regex on text or content-desc>: tap the centre of the first matching node
  local b
  b=$(grep -oE '<node [^>]*>' "$OUT/ui/$1.xml" | grep -E "(text|content-desc)=\"$2\"" | head -1 | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | grep -oE '[0-9]+')
  [ -z "$b" ] && { echo "no node $2"; return 1; }
  set -- $b
  padb shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
}
p_notifs() {  # Mknoon notifications: id, title, text, category
  padb shell dumpsys notification --noredact | awk '
    /NotificationRecord\(/ {if (mk && rec != "") print rec; mk = ($0 ~ /pkg=com\.mknoon\.app/); rec = ""; if (mk) {match($0, /id=[0-9-]+/); rec = substr($0, RSTART, RLENGTH)}; next}
    mk && /android\.title=|android\.text=|category=|fullscreenIntent=/ {sub(/^ +/, ""); rec = rec " | " $0}
    END {if (mk && rec != "") print rec}' | cut -c1-400
}
p_log_since() {  # p_log_since <device time 'MM-DD HH:MM:SS.mmm'> <file>
  padb logcat -d -v threadtime -T "$1" > "$2" 2>/dev/null
}
p_devtime() { padb shell date "'+%m-%d %H:%M:%S.000'" | tr -d '\r'; }
p_kill_app() {  # Home, then kill only the process (stopped=false, so FCM can still start it)
  padb shell input keyevent KEYCODE_HOME; sleep 2
  padb shell am kill "$PKG"; sleep 2
  for _ in 1 2 3 4; do [ -z "$(p_pid)" ] && break; padb shell input keyevent KEYCODE_HOME; sleep 2; padb shell am kill "$PKG"; sleep 2; done
  echo "pid after kill: '$(p_pid)' $(padb shell dumpsys package $PKG | grep -m1 -oE 'stopped=(true|false)')"
}
p_open_app() { padb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; }
ios_busy() {  # another client's Appium session on the iPhone 13 in the last 10 minutes?
  python3 - "$ROOT/docker-ws/beta/r34_appium_server.log" <<'PY'
import sys, re, json, datetime
mine = set(json.load(open(sys.argv[1].replace('r34_appium_server.log', 'ap_sessions.json'))).values()) if True else set()
mine = {s if isinstance(s, str) else s.get('id') for s in mine}
cut = datetime.datetime.utcnow() - datetime.timedelta(minutes=10)
busy = []
for line in open(sys.argv[1], errors='replace'):
    m = re.match(r'(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)', line)
    if not m: continue
    t = datetime.datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S')
    sm = re.search(r'\[([0-9a-f]{8})\]', line)
    if t > cut and sm and not any(str(x).startswith(sm.group(1)) for x in mine):
        busy.append(sm.group(1))
print(' '.join(sorted(set(busy))) or 'idle')
PY
}
