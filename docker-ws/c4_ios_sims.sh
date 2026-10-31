#!/bin/bash
# C4 iOS pass (Codex runbook C4-readiness-and-commands.txt, reviewed): boot the 4 pinned simulators under
# device leases, then run the 7 iOS SIMS scenarios + 2 builds through the safe launcher in major mode.
#   host-run bash docker-ws/c4_ios_sims.sh prepare     (boot + exclude list, foreground, ~2-4 min)
#   host-run bash docker-ws/c4_ios_sims.sh start [out] [exclude file]   (self-detached launcher run)
#   host-run bash docker-ws/c4_ios_sims.sh status
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 2
PREP=build/kayan-safe/c4-ios-preparation; OUT="${C4_OUT:-build/kayan-safe/c4-ios-sims-major}"; EXCLUDE="${C4_EXCLUDE:-$PREP/exclude.txt}"
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
case "${1:-status}" in
  prepare)
    python3 - <<'PY'
from pathlib import Path
import json, subprocess, sys
sys.path.insert(0, 'scripts')
from device_campaign_preflight import device_leases
sys.path.insert(0, 'docker-ws')
import run_sims_safe as safe_launcher
source = json.loads(Path('build/kayan-safe/c1-resume-f10/device-config.json').read_text())['devices']
role_keys = {'A': 'ios_simulator', 'B': 'ios_simulator_b', 'C': 'ios_simulator_c', 'D': 'ios_simulator_d'}
pins = {letter: source[key] for letter, key in role_keys.items()}
keep = {
    'native.ios.runner_tests', 'groups.multi_party_release', 'kx0028',
    'production.group_catalog.private_peer_disconnect_not_removal',
    'production.group_catalog.private_admin_role_transfer_delivery',
    'production.group_catalog.private_partition_readd_heal',
    'production.group_catalog.private_background_resume_group_delivery',
    'build.ios.simulator.app', 'build.ios.simulator.e2e',
}
manifest = json.loads(Path('tool/sims/critical_features.json').read_text())
major = {r['id'] for r in manifest['capabilities'] if r.get('active', True) and 'major' in r.get('modes', [])}
assert keep <= major, keep - major
gate = safe_launcher.host_gate()
print('host_gate', gate.get('passed'))
assert gate['passed'], 'host resource gate did not pass'
out = Path('build/kayan-safe/c4-ios-preparation')
out.mkdir(parents=True, exist_ok=False)
with device_leases(pins.values()):
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True))
    rows = {r['udid']: r for items in inventory['devices'].values() for r in items if r.get('isAvailable', True)}
    available = {}
    for letter, udid in pins.items():
        if udid not in rows:
            print(letter, 'unavailable')
            continue
        if rows[udid].get('state') != 'Booted':
            subprocess.run(['xcrun', 'simctl', 'boot', udid], check=True)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], check=True, stdout=subprocess.DEVNULL)
        available[letter] = udid
        print(letter, 'booted')
    (out / 'available-pins.json').write_text(json.dumps(available, indent=2) + '\n')
    requirements = {'native.ios.runner_tests': set('A'), 'groups.multi_party_release': set('ABCD'), 'kx0028': set('A')}
    for row in keep:
        if row.startswith('production.group_catalog.'):
            requirements[row] = set('ABC')
    unavailable = {row for row, needed in requirements.items() if not needed <= available.keys()}
    print('unavailable rows', sorted(unavailable))
    (out / 'exclude.txt').write_text('\n'.join(sorted((major - keep) | unavailable)) + '\n')
PY
    ;;
  start)
    [ -n "${2:-}" ] && OUT="$2"; [ -n "${3:-}" ] && EXCLUDE="$3"
    mkdir -p "$OUT"; rm -f "$OUT/DONE"
    C4_OUT="$OUT" C4_EXCLUDE="$EXCLUDE" nohup bash "$0" _run > "$OUT/detached.log" 2>&1 < /dev/null &
    echo $! > "$OUT/detached.pid"; echo "started pid $!" ;;
  _run)
    export ANDROID_HOME="$HOME/Library/Android/sdk" ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
    export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home MAESTRO_CLI_NO_ANALYTICS=1
    for role in '' _SECOND _THIRD _FOURTH; do export "SIMS_ANDROID_EMULATOR${role}_DEVICE_ID="; done
    for L in A B C D; do export "SIMS_IOS_SIMULATOR_${L}_DEVICE_ID=$(python3 -c "import json;print(json.load(open('$PREP/available-pins.json')).get('$L',''))")"; done
    export SIMS_IOS_SIMULATOR_ID="$SIMS_IOS_SIMULATOR_A_DEVICE_ID"
    export KAYAN_TEST_RELAY_FILE="$REPO/build/kayan-safe/test-relay.txt"
    echo "start $(date -u +%FT%TZ) head=$(git rev-parse --short HEAD) A=${SIMS_IOS_SIMULATOR_A_DEVICE_ID:+set}"
    python3 docker-ws/run_sims_safe.py major --output "$OUT" --exclude-file "$EXCLUDE"; rc=$?
    echo "SAFE_SIMS_EXIT=$rc $(date -u +%FT%TZ)"; echo "$rc" > "$OUT/DONE" ;;
  status)
    P=$(cat "$OUT/detached.pid" 2>/dev/null)
    echo "pid ${P:-none} $(ps -p "${P:-0}" >/dev/null 2>&1 && echo running || echo stopped) done=$(cat "$OUT/DONE" 2>/dev/null || echo no)"
    tail -n 3 "$OUT/detached.log" 2>/dev/null ;;
esac
