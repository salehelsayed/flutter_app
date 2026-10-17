#!/bin/bash
# SE-41 two-build acceptance with a TEST key only. Everything lives outside the
# repo: a test key dir, an rsync copy of the tree patched to trust the test key
# and a local https test server reachable from emulators at 10.0.2.2:8443.
# Never uses k1, never touches updates.mknoon.xyz, never commits the copy.
#   host-run bash docker-ws/se41_test_variant.sh keys|copy|patch|build <buildNo> <outApk>|sign <payload> <out>|serve-start|serve-stop|publish <envelope>
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT=/Volumes/CrucialX9/se41_test
KEYS="$ROOT/keys"; COPY="$ROOT/app"; SRV="$ROOT/server"; LOG="$ROOT/variant.log"
mkdir -p "$ROOT"
. "$REPO/docker-ws/_flutter_sdk_env.sh"
cmd="${1:?command}"; shift
case "$cmd" in
  keys)
    if [ -f "$KEYS/public_key.b64" ]; then echo "test key already present"; else
      (cd "$REPO" && dart run tool/sign_version_file.dart keygen --out "$KEYS") | grep -v '^private key' ; fi
    ls "$KEYS" ;;
  copy)
    rsync -a --delete \
      --exclude '/.git' --exclude '/build/' --exclude '/.dart_tool/' --exclude '/.codex-test-logs/' --exclude '/artifacts/' \
      --exclude '*.noindex' --exclude 'ModuleCache.noindex' --exclude 'SourcePackages' --exclude 'ios/Pods/' \
      --exclude '.claude/worktrees/' --exclude 'graphify-out/' --exclude 'graphify-arch/' \
      "$REPO/" "$COPY/" > "$LOG" 2>&1
    echo "copy exit=$? files=$(find "$COPY" -type f | wc -l | tr -d ' ') head=$(git -C "$REPO" rev-parse --short HEAD) dirty=$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')" | tee "$COPY/.se41-test-provenance.txt" ;;
  patch)
    PUB=$(tr -d '\n ' < "$KEYS/public_key.b64")
    python3 - "$COPY" "$PUB" <<'PY'
import sys, re
copy, pub = sys.argv[1], sys.argv[2]
k = f'{copy}/lib/features/update_check/domain/update_check_keys.dart'
s = open(k).read()
s = re.sub(r"(const String updateCheckK1PublicKeyBase64 =\s*)'[^']*';", lambda m: m.group(1) + "'" + pub + "';", s)
s = re.sub(r"(const String updateCheckK2PublicKeyBase64 =\s*)'[^']*';", lambda m: m.group(1) + "'';", s)
s = re.sub(r"(const String updateCheckVersionFileUrl =\s*)'[^']*';", lambda m: m.group(1) + "'https://10.0.2.2:8443/mknoon/version.json';", s)
open(k, 'w').write(s)
f = f'{copy}/lib/features/update_check/infrastructure/version_file_fetcher.dart'
s = open(f).read()
old = "_clientFactory = clientFactory ?? HttpClient.new;"
assert old in s
s = s.replace(old, "_clientFactory = clientFactory ?? _se41TestClient;")
s += "\n// SE-41 TEST VARIANT ONLY (never committed): trust the local test server.\nHttpClient _se41TestClient() => HttpClient()\n  ..badCertificateCallback = (cert, host, port) => host == '10.0.2.2' && port == 8443;\n"
open(f, 'w').write(s)
print('patched keys/url/fetcher; k1 is the TEST key, k2 empty')
PY
    grep -c "10.0.2.2" "$COPY/lib/features/update_check/domain/update_check_keys.dart" ;;
  fast-gate)
    # TEST VARIANT ONLY: 1 minute check gate and a 15 minute WorkManager period,
    # so the background reminder can be observed without waiting 6 hours.
    python3 - "$COPY" <<'PY'
import re, sys
c = sys.argv[1]
p = f'{c}/lib/features/update_check/domain/update_check_policy.dart'
s = open(p).read(); s2 = s.replace('const Duration updateCheckInterval = Duration(hours: 6);', 'const Duration updateCheckInterval = Duration(minutes: 1);')
assert s2 != s; open(p, 'w').write(s2)
k = f'{c}/android/app/src/main/kotlin/com/mknoon/app/UpdateCheckBackgroundWork.kt'
s = open(k).read()
s2 = s.replace('UpdateCheckBackgroundWork.REPEAT_HOURS,\n            TimeUnit.HOURS,', '15L,\n            TimeUnit.MINUTES,')
assert s2 != s
s3 = s2.replace('ExistingPeriodicWorkPolicy.KEEP,', 'ExistingPeriodicWorkPolicy.UPDATE,', 1)
assert s3 != s2; open(k, 'w').write(s3)
print('fast gate: check every 1 min, WorkManager period 15 min, enqueue policy UPDATE (copy only)')
PY
    ;;
  patch-ios)
    # TEST VARIANT ONLY: the iOS simulator reaches the Mac test server on 127.0.0.1.
    python3 - "$COPY" <<'PY'
import sys
c = sys.argv[1]
k = f'{c}/lib/features/update_check/domain/update_check_keys.dart'
s = open(k).read(); s2 = s.replace("https://10.0.2.2:8443/mknoon/version.json", "https://127.0.0.1:8443/mknoon/version.json")
assert s2 != s; open(k, 'w').write(s2)
f = f'{c}/lib/features/update_check/infrastructure/version_file_fetcher.dart'
s = open(f).read(); s2 = s.replace("host == '10.0.2.2' && port == 8443", "host == '127.0.0.1' && port == 8443")
assert s2 != s; open(f, 'w').write(s2)
print('patched for the iOS simulator: https://127.0.0.1:8443')
PY
    ;;
  build-ios-sim)
    BN="${1:?build number}"
    (cd "$COPY" && bash scripts/ensure_go_ios_bindings.sh > "$ROOT/ios-bindings.log" 2>&1; \
      flutter build ios --simulator --debug --no-pub --build-number="$BN" --dart-define-from-file=tool/build/voice_call_release_defines.json \
        --dart-define=MKNOON_UPDATE_CHECK=on > "$ROOT/build-ios-$BN.log" 2>&1)
    rc=$?; echo "ios sim build $BN exit=$rc"; ls -d "$COPY/build/ios/iphonesimulator/Runner.app" 2>/dev/null; exit $rc ;;
  sim)
    # TEST VARIANT ONLY: drive the booted iPhone simulator. Subcommands:
    #   sim install | sim launch [lang] | sim shot <name> | sim terminate
    SUB="${1:?sim subcommand}"; shift
    UDID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; b=[v["udid"] for vs in d.values() for v in vs if v.get("state")=="Booted" and v["name"].startswith("iPhone")]; print(b[0] if b else "")')
    [ -n "$UDID" ] || { echo "no booted iPhone simulator"; exit 2; }
    case "$SUB" in
      install) xcrun simctl install "$UDID" "$COPY/build/ios/iphonesimulator/Runner.app"; echo "install exit=$?" ;;
      launch) L="${1:-}"; if [ -n "$L" ]; then xcrun simctl launch --terminate-running-process "$UDID" com.mknoon.app -AppleLanguages "($L)" -AppleLocale "$L"; else xcrun simctl launch --terminate-running-process "$UDID" com.mknoon.app; fi; echo "launch exit=$?" ;;
      terminate) xcrun simctl terminate "$UDID" com.mknoon.app; echo "terminate exit=$?" ;;
      shot) N="${1:?name}"; mkdir -p "$REPO/build/se41_sim"; xcrun simctl io "$UDID" screenshot "/tmp/se41_$N.png" >/dev/null 2>&1; rc=$?; cp "/tmp/se41_$N.png" "$REPO/build/se41_sim/$N.png" 2>/dev/null; rm -f "/tmp/se41_$N.png"; echo "shot exit=$rc build/se41_sim/$N.png" ;;
      *) echo "unknown sim subcommand"; exit 2 ;;
    esac ;;
  build)
    BN="${1:?build number}"; OUT="${2:?out apk}"
    (cd "$COPY" && flutter pub get --offline > "$ROOT/pubget.log" 2>&1; \
      flutter build apk --debug --build-number="$BN" --dart-define-from-file=tool/build/voice_call_release_defines.json \
        --dart-define=CONTACT_REPAIR_ROLLOUT=true --dart-define=MKNOON_UPDATE_CHECK=on \
        --android-project-arg=enableAndroidNativeCalls=true > "$ROOT/build-$BN.log" 2>&1)
    rc=$?; echo "build $BN exit=$rc"; [ $rc -eq 0 ] && cp "$COPY/build/app/outputs/flutter-apk/app-debug.apk" "$OUT" && shasum -a 256 "$OUT"
    exit $rc ;;
  sign)
    IN="${1:?payload}"; OUT="${2:?out}"
    PRIV="$KEYS/signing_key.b64"
    (cd "$REPO" && dart run tool/sign_version_file.dart sign --key "$PRIV" --key-id k1 --in "$IN" --out "$OUT") ; echo "sign exit=$?" ;;
  serve-start)
    mkdir -p "$SRV/mknoon"
    if [ ! -f "$ROOT/cert.pem" ]; then
      openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=10.0.2.2" \
        -addext "subjectAltName=IP:10.0.2.2" -keyout "$ROOT/key.pem" -out "$ROOT/cert.pem" > "$ROOT/openssl.log" 2>&1 || { echo "openssl failed"; cat "$ROOT/openssl.log"; exit 1; }
    fi
    cat > "$ROOT/serve.py" <<'PY'
import http.server, ssl, os, sys
root = sys.argv[1]; os.chdir(root)
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *a):
        with open('../access.log', 'a') as f: f.write(self.log_date_time_string() + ' ' + (fmt % a) + '\n')
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store'); super().end_headers()
srv = http.server.ThreadingHTTPServer(('0.0.0.0', 8443), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(sys.argv[2], sys.argv[3])
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
PY
    nohup python3 "$ROOT/serve.py" "$SRV" "$ROOT/cert.pem" "$ROOT/key.pem" > "$ROOT/serve.log" 2>&1 < /dev/null &
    echo $! > "$ROOT/serve.pid"; sleep 1; echo "server pid $(cat "$ROOT/serve.pid")" ;;
  serve-stop)
    P=$(cat "$ROOT/serve.pid" 2>/dev/null); if [ -n "$P" ] && ps -p "$P" -o command= | grep -q serve.py; then kill "$P"; echo "stopped $P"; else echo "no server"; fi ;;
  serve-status)
    echo "pid file: $(cat "$ROOT/serve.pid" 2>/dev/null || echo none)"
    /usr/sbin/lsof -nP -iTCP:8443 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print "listener pid " $2 " " $1}' ;;
  serve-kill)
    P="${1:?pid}"; C=$(ps -p "$P" -o command= 2>/dev/null)
    case "$C" in *serve.py*) kill "$P" && echo "stopped $P" ;; *) echo "pid $P is not serve.py: $C"; exit 1 ;; esac ;;
  publish)
    SRC="${1:?envelope}"; cp "$SRC" "$SRV/mknoon/version.json.tmp" && mv "$SRV/mknoon/version.json.tmp" "$SRV/mknoon/version.json"; echo "published $(shasum -a 256 "$SRV/mknoon/version.json" | cut -c1-16)" ;;
  *) echo "unknown command"; exit 2 ;;
esac
