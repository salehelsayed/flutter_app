#!/bin/bash
# C4 VC204 on ONE disposable emulator only (Codex runbook C4-readiness-and-commands.txt, reviewed).
# The runner clears and uninstalls its own proof packages, so the target must be an emulator.
#   host-run bash docker-ws/c4_vc204.sh start <emulator-NNNN> [out under build/kayan-safe/]
#   host-run bash docker-ws/c4_vc204.sh status
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 2
OUT="${VC204_OUT:-build/kayan-safe/c4-vc204-emulator}"
case "${1:-status}" in
  start)
    EMU="${2:?emulator serial}"; [ -n "${3:-}" ] && OUT="$3"
    [[ "$EMU" =~ ^emulator-[0-9]+$ ]] || { echo "refused: not an emulator serial"; exit 2; }
    [ -e "$OUT" ] && { echo "refused: $OUT exists"; exit 2; }
    mkdir -p "$OUT"
    VC204_OUT="$OUT" nohup bash "$0" _run "$EMU" > "$OUT/detached.log" 2>&1 < /dev/null &
    echo $! > "$OUT/detached.pid"; echo "started pid $!" ;;
  _run)
    EMU="$2"
    export ANDROID_HOME="$HOME/Library/Android/sdk" ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
    export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home GOTOOLCHAIN=go1.27.1
    export PATH="$HOME/development/flutter-3.47.2/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    echo "start $(date -u +%FT%TZ) head=$(git rev-parse --short HEAD) target=$EMU"
    python3 - "$EMU" "$OUT" <<'PY'
import json, os, re, subprocess, sys
from pathlib import Path
sys.path.insert(0, 'scripts')
from device_campaign_preflight import device_leases, run as preflight_run
from mknoon_checks import launch
sys.path.insert(0, 'docker-ws')
import run_sims_safe as safe_launcher
emu, out = sys.argv[1], Path(sys.argv[2])
assert re.fullmatch(r'emulator-[0-9]+', emu), 'Phones prohibited for this recipe'
gate = safe_launcher.host_gate()
print('host_gate', gate['passed'], json.dumps(gate['second']))
assert gate['passed'], 'host resource gate did not pass'
env = dict(os.environ)
env['ANDROID_SERIAL'] = emu
env['SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON'] = json.dumps({'android-emulator': emu})
with device_leases([emu, 'mknoon.shared-native-build']):
    receipt = preflight_run({'kind': 'full_adapter', 'device_roles': ['android_emulator']}, Path.cwd(),
                            {'devices': {'android_emulator': emu}}, launch, env)
    (out / 'preflight.json').write_text(json.dumps(receipt, indent=2) + '\n')
    assert receipt['status'] == 'PASS', 'fresh automation/target preflight did not pass'
    assert subprocess.check_output(['adb', '-s', emu, 'get-state'], text=True).strip() == 'device'
    assert subprocess.check_output(['adb', '-s', emu, 'shell', 'getprop', 'ro.kernel.qemu'], text=True).strip() == '1'
    print('target verified: emulator, qemu=1')
    subprocess.run(['bash', 'scripts/run_vc204_android_call_lifecycle_e2e.sh', '--build-only',
                    '--artifact-dir', str(out / 'build')], check=True, env=env)
    subprocess.run(['bash', 'scripts/run_vc204_android_call_lifecycle_e2e.sh', '--device-id', emu,
                    '--artifact-dir', str(out / 'build'), '--result-dir', str(out / 'results'),
                    '--scenario', 'vc204_android_call_lifecycle'], check=True, env=env)
print('VC204_DONE')
PY
    rc=$?; echo "VC204_EXIT=$rc $(date -u +%FT%TZ)"; echo "$rc" > "$OUT/DONE" ;;
  status)
    P=$(cat "$OUT/detached.pid" 2>/dev/null)
    echo "pid ${P:-none} $(ps -p "${P:-0}" >/dev/null 2>&1 && echo running || echo stopped) done=$(cat "$OUT/DONE" 2>/dev/null || echo no)"
    tail -n 4 "$OUT/detached.log" 2>/dev/null ;;
esac
