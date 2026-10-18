#!/usr/bin/env bash

set -euo pipefail

scope="major"
scope_kind="sims"
repo_dir=""
list_only=0
print_env=0
continue_on_failure=0
include_direct_targets=0
simultaneous=0
fix_as_you_go=0
resume=0
prepare_builds=0
host_concurrency="${SIMS_HOST_CONCURRENCY:-4}"
only_target=""
start_at=""
family=""
lane=""
output_format=""

usage() {
  cat <<'EOF'
Usage:
  run_with_devices.sh [major|full|smoke] [options]  # default: major
  run_with_devices.sh [all|1to1|group|groups|intro|move-feature] [options]
  run_with_devices.sh [host-all|feature-host-all|core-host-all|performance-host] [options]

Options:
  --repo <path>              Flutter repo root. Defaults to current dir or parent.
  --list, --dry-run          Compile and print the command plan; no tests execute.
  --print-env                Print resolved export lines and exit.
  --continue-on-failure      Continue diagnostically after a failed selected row.
  --include-direct-targets   Legacy reliability option.
  --simultaneous             Automatically parallelize only compatible work.
                             Host Flutter tests use a bounded batch; performance
                             and shared device/build work remain exclusive.
  --only <ID|N|path>         Select one stable sims ID, or one legacy gate item.
  --start-at <N>             Legacy reliability/host numeric resume option.
  --family <NAME>            Filter a sims mode to one diagnostic family.
  --lane <NAME>              Filter a sims mode to one execution lane.
  --format <text|json|tsv>   Select sims plan/report output format.
  --prepare-builds           Prepare/cache selected build profiles before execution.
  --resume                   Resume a sims run from its stable-ID checkpoint.
  --fix-as-you-go            Checkpoint at failures for an explicitly authorized repair loop.
  -h, --help                 Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    major|full|smoke)
      scope="$1"
      scope_kind="sims"
      shift
      ;;
    all|1to1|intro|move-feature)
      scope="$1"
      scope_kind="reliability"
      shift
      ;;
    group|groups)
      scope="group"
      scope_kind="reliability"
      shift
      ;;
    move|moves|account-migration|account_migration)
      scope="move-feature"
      scope_kind="reliability"
      shift
      ;;
    host-all|feature-host-all|core-host-all|performance-host)
      scope="$1"
      scope_kind="host"
      shift
      ;;
    --repo)
      repo_dir="${2:?missing --repo value}"
      shift 2
      ;;
    --list|--dry-run)
      list_only=1
      shift
      ;;
    --print-env)
      print_env=1
      shift
      ;;
    --continue-on-failure)
      continue_on_failure=1
      shift
      ;;
    --include-direct-targets)
      include_direct_targets=1
      shift
      ;;
    --simultaneous|--parallel)
      simultaneous=1
      shift
      ;;
    --fix-as-you-go)
      fix_as_you_go=1
      shift
      ;;
    --resume)
      resume=1
      shift
      ;;
    --prepare-builds)
      prepare_builds=1
      shift
      ;;
    --family)
      family="${2:?missing --family value}"
      shift 2
      ;;
    --lane)
      lane="${2:?missing --lane value}"
      shift 2
      ;;
    --format)
      output_format="${2:?missing --format value}"
      shift 2
      ;;
    --only)
      only_target="${2:?missing --only value}"
      shift 2
      ;;
    --start-at)
      start_at="${2:?missing --start-at value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$scope_kind" = "host" ] && [ "$simultaneous" -eq 1 ] &&
   [ "$scope" != "performance-host" ] &&
   ! [[ "$host_concurrency" =~ ^([1-9]|[1-5][0-9]|6[0-4])$ ]]; then
  printf 'Invalid SIMS_HOST_CONCURRENCY: %s (expected 1 through 64).\n' \
    "$host_concurrency" >&2
  exit 2
fi

find_repo_root() {
  local dir="${1:-$PWD}"
  while [ "$dir" != "/" ]; do
    if [ -x "$dir/scripts/run_test_gates.sh" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

if [ -n "$repo_dir" ]; then
  repo_dir="$(cd "$repo_dir" && pwd)"
else
  if ! repo_dir="$(find_repo_root "$PWD")"; then
    printf 'Could not find repo root with scripts/run_test_gates.sh.\n' >&2
    exit 1
  fi
fi

cd "$repo_dir"

if [ "$scope_kind" = "sims" ]; then
  if [ "$print_env" -eq 1 ]; then
    printf '%s\n' '--print-env is only supported for legacy reliability scopes.' >&2
    exit 2
  fi
  if [ "$include_direct_targets" -eq 1 ] || [ -n "$start_at" ]; then
    printf '%s\n' \
      '--include-direct-targets/--start-at are legacy reliability options; use stable --only/--resume for sims modes.' >&2
    exit 2
  fi

  cmd=(./scripts/run_test_gates.sh sims "$scope")
  if [ "$list_only" -eq 1 ]; then
    cmd+=(--list)
  fi
  if [ "$simultaneous" -eq 1 ]; then
    cmd+=(--simultaneous)
  fi
  if [ "$continue_on_failure" -eq 1 ]; then
    cmd+=(--continue-on-failure)
  fi
  if [ "$fix_as_you_go" -eq 1 ]; then
    cmd+=(--fix-as-you-go)
  fi
  if [ "$resume" -eq 1 ]; then
    cmd+=(--resume)
  fi
  if [ "$prepare_builds" -eq 1 ]; then
    cmd+=(--prepare-builds)
  fi
  if [ -n "$only_target" ]; then
    cmd+=(--only "$only_target")
  fi
  if [ -n "$family" ]; then
    cmd+=(--family "$family")
  fi
  if [ -n "$lane" ]; then
    cmd+=(--lane "$lane")
  fi
  if [ -n "$output_format" ]; then
    cmd+=(--format "$output_format")
  fi

  # Adapter diagnostics stay on stderr so --format json/tsv remains valid,
  # machine-readable stdout from the repo-owned CLI.
  printf 'Running from repo: %s\n' "$repo_dir" >&2
  printf '%s\n' \
    'Target/build selection: delegated to the repo sims planner; the skill adapter selected none.' >&2
  printf 'Command:' >&2
  printf ' %q' "${cmd[@]}" >&2
  printf '\n' >&2
  "${cmd[@]}"
  exit $?
fi

if [ "$scope_kind" = "host" ]; then
  if [ "$print_env" -eq 1 ]; then
    printf '%s\n' '--print-env is only supported for reliability scopes.' >&2
    exit 2
  fi
  if [ "$include_direct_targets" -eq 1 ]; then
    printf '%s\n' \
      '--include-direct-targets is only supported for reliability scopes.' >&2
    exit 2
  fi

  cmd=(./scripts/run_test_gates.sh "$scope")
  if [ "$simultaneous" -eq 1 ]; then
    if [ "$scope" = "performance-host" ]; then
      printf '%s\n' \
        'Simultaneous policy: performance-host is exclusive; running serially.'
    else
      cmd+=(--batch-flutter --concurrency "$host_concurrency" \
        --reporter failures-only)
      printf 'Simultaneous policy: host Flutter tests use bounded concurrency=%s; Go tails remain serial.\n' \
        "$host_concurrency"
    fi
  fi
  if [ "$list_only" -eq 1 ]; then
    cmd+=(--list)
  fi
  if [ "$continue_on_failure" -eq 1 ]; then
    cmd+=(--continue-on-failure)
  fi
  if [ -n "$only_target" ]; then
    cmd+=(--only "$only_target")
  fi
  if [ -n "$start_at" ]; then
    cmd+=(--start-at "$start_at")
  fi

  printf 'Running from repo: %s\n' "$repo_dir"
  printf 'Command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  "${cmd[@]}"
  exit $?
fi

# Everything below this point is compatibility behavior for the old
# reliability-sim entrypoint. Canonical sims modes return above without
# injecting relay addresses or resolving a device.
if [ "$list_only" -eq 1 ] && [ "$print_env" -eq 0 ]; then
  cmd=(./scripts/run_test_gates.sh reliability-sim "$scope" --list)
  if [ "$continue_on_failure" -eq 1 ]; then
    cmd+=(--continue-on-failure)
  fi
  if [ "$include_direct_targets" -eq 1 ]; then
    cmd+=(--include-direct-targets)
  fi
  if [ "$simultaneous" -eq 1 ]; then
    cmd+=(--simultaneous)
  fi
  if [ -n "$only_target" ]; then
    cmd+=(--only "$only_target")
  fi
  if [ -n "$start_at" ]; then
    cmd+=(--start-at "$start_at")
  fi

  printf 'Running from repo: %s\n' "$repo_dir"
  printf 'Command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'

  "${cmd[@]}"
  exit $?
fi

if [ -z "${MKNOON_RELAY_ADDRESSES:-}" ]; then
  printf '%s\n' \
    'Set MKNOON_RELAY_ADDRESSES before legacy execution; the safe launcher can load docker-ws/local_devices.env.' >&2
  exit 2
fi

env_file="$(mktemp)"
trap 'rm -f "$env_file"' EXIT

python3 - "$scope" >"$env_file" <<'PY'
import json
import os
import shlex
import subprocess
import sys

scope = sys.argv[1]


def run_json(command):
    try:
        result = subprocess.run(
            command,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


flutter_devices = run_json(["flutter", "devices", "--machine"]) or []
simctl_booted = run_json(["xcrun", "simctl", "list", "devices", "booted", "-j"]) or {}

flutter_mobile = []
android_devices = []
for entry in flutter_devices:
    platform = entry.get("targetPlatform", "")
    if platform == "ios" or platform.startswith("android"):
        item = {
            "id": entry.get("id", ""),
            "name": entry.get("name", ""),
            "platform": platform,
            "emulator": bool(entry.get("emulator")),
        }
        flutter_mobile.append(item)
        if platform.startswith("android"):
            android_devices.append(item)

flutter_mobile = sorted(
    (device for device in flutter_mobile if device["id"]),
    key=lambda device: (device["platform"], device["name"], device["id"]),
)
android_devices = sorted(
    (device for device in android_devices if device["id"]),
    key=lambda device: (device["emulator"], device["name"], device["id"]),
)
physical_android = [device for device in android_devices if not device["emulator"]]
android_emulators = [device for device in android_devices if device["emulator"]]

booted_iphones = []
for runtime_devices in (simctl_booted.get("devices") or {}).values():
    for device in runtime_devices:
        name = str(device.get("name", ""))
        device_type = str(device.get("deviceTypeIdentifier", ""))
        if (
            device.get("state") == "Booted"
            and device.get("isAvailable", True) is not False
            and (
                name.startswith("iPhone")
                or "iPhone" in name
                or ".iPhone-" in device_type
            )
        ):
            booted_iphones.append({
                "id": device.get("udid", ""),
                "name": name,
            })

booted_iphones = sorted(
    (device for device in booted_iphones if device["id"]),
    key=lambda device: (device["name"], device["id"]),
)


def env(name):
    value = os.environ.get(name, "").strip()
    return value or None


def split_csv(value):
    return [part.strip() for part in value.split(",") if part.strip()]


single = env("RELIABILITY_SINGLE_DEVICE_ID")
if not single:
    flutter_single = env("FLUTTER_DEVICE_ID")
    if flutter_single and "," not in flutter_single:
        single = flutter_single
if not single and physical_android:
    single = physical_android[0]["id"]
if not single and android_emulators:
    single = android_emulators[0]["id"]
if not single and flutter_mobile:
    single = flutter_mobile[0]["id"]

multi = env("RELIABILITY_MULTI_DEVICE_IDS") or env("FLUTTER_MULTI_DEVICE_IDS")
if not multi:
    flutter_device = env("FLUTTER_DEVICE_ID")
    if flutter_device and "," in flutter_device:
        multi = ",".join(split_csv(flutter_device)[:2])
if not multi and physical_android and android_emulators:
    multi = f"{physical_android[0]['id']},{android_emulators[0]['id']}"
if not multi and len(android_devices) >= 2:
    multi = ",".join(device["id"] for device in android_devices[:2])
if not multi and len(flutter_mobile) >= 2:
    multi = ",".join(device["id"] for device in flutter_mobile[:2])

# These variables are consumed only by explicitly iOS-specific compatibility
# scripts. Never populate them from the ordinary cross-platform pair.
tap = env("IOS_NOTIFICATION_TAP_DEVICES")
if not tap and len(booted_iphones) >= 2:
    tap = ",".join(device["id"] for device in booted_iphones[:2])

ios_primary = env("SIMULATOR_DEVICE")
if not ios_primary and booted_iphones:
    ios_primary = booted_iphones[0]["id"]
ios_secondary = env("IOS_SECONDARY_SIMULATOR_DEVICE")
if not ios_secondary and len(booted_iphones) >= 2:
    ios_secondary = booted_iphones[1]["id"]

android_serial = env("ANDROID_SERIAL")
if not android_serial and android_emulators:
    android_serial = android_emulators[0]["id"]
if not android_serial and android_devices:
    android_serial = android_devices[0]["id"]

device_a = env("DEVICE_A")
device_b = env("DEVICE_B")
device_c = env("DEVICE_C")
device_d = env("DEVICE_D")

need_single = scope in {"all", "1to1", "group", "intro", "move-feature"}
need_two = scope in {"all", "1to1", "group"}

errors = []
if need_single and not single:
    errors.append("No one-device Flutter target found.")
if need_two and (not multi or len(split_csv(multi)) < 2):
    errors.append("Need two available Flutter targets for two-device reliability suites.")

if errors:
    print("# Device resolution failed", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    if booted_iphones:
        print("Booted iPhone simulators:", file=sys.stderr)
        for device in booted_iphones:
            print(f"  - {device['name']}: {device['id']}", file=sys.stderr)
    else:
        print("Booted iPhone simulators: none", file=sys.stderr)
    if flutter_mobile:
        print("Flutter mobile devices:", file=sys.stderr)
        for device in flutter_mobile:
            print(
                f"  - {device['name']} ({device['platform']}): {device['id']}",
                file=sys.stderr,
            )
    sys.exit(1)

values = {
    "MKNOON_RELAY_ADDRESSES": env("MKNOON_RELAY_ADDRESSES"),
    "RELIABILITY_SINGLE_DEVICE_ID": single,
    "RELIABILITY_MULTI_DEVICE_IDS": multi,
    "IOS_NOTIFICATION_TAP_DEVICES": tap,
    "SIMULATOR_DEVICE": ios_primary,
    "IOS_SECONDARY_SIMULATOR_DEVICE": ios_secondary,
    "ANDROID_SERIAL": android_serial,
    "DEVICE_A": device_a,
    "DEVICE_B": device_b,
    "DEVICE_C": device_c,
    "DEVICE_D": device_d,
}

for key, value in values.items():
    if value:
        print(f"export {key}={shlex.quote(value)}")

print("# Resolved reliability devices:", file=sys.stderr)
if single:
    print(f"#   one-device: {single}", file=sys.stderr)
if multi:
    print(f"#   two-device: {multi}", file=sys.stderr)
if all([device_a, device_b, device_c, device_d]):
    print(
        f"#   intro four-device: {device_a},{device_b},{device_c},{device_d}",
        file=sys.stderr,
    )
PY

if [ "$print_env" -eq 1 ]; then
  cat "$env_file"
  exit 0
fi

# shellcheck disable=SC1090
source "$env_file"

cmd=(./scripts/run_test_gates.sh reliability-sim "$scope")
if [ "$list_only" -eq 1 ]; then
  cmd+=(--list)
fi
if [ "$continue_on_failure" -eq 1 ]; then
  cmd+=(--continue-on-failure)
fi
if [ "$include_direct_targets" -eq 1 ]; then
  cmd+=(--include-direct-targets)
fi
if [ "$simultaneous" -eq 1 ]; then
  cmd+=(--simultaneous)
fi
if [ -n "$only_target" ]; then
  cmd+=(--only "$only_target")
fi
if [ -n "$start_at" ]; then
  cmd+=(--start-at "$start_at")
fi

printf 'Running from repo: %s\n' "$repo_dir"
printf 'Command:'
printf ' %q' "${cmd[@]}"
printf '\n'

"${cmd[@]}"
