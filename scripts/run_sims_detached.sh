#!/usr/bin/env bash
# Detached reliability-sim launcher.
#
# Long reliability-sim runs launched as harness-tracked background tasks get
# SIGTERM'd by the harness's background-task supervisor at a variable
# ~11-28 min on a busy workstation. This wrapper runs the gate in its OWN
# SESSION (setsid) so the supervisor's process-group SIGTERM cannot reach it:
# the wrapper returns in ~1s, the real run keeps going independently, and all
# output streams to a log file.
#
# Usage:
#   scripts/run_sims_detached.sh [--env-file FILE] [--log FILE] <scope> [runner options...]
#
# Examples:
#   scripts/run_sims_detached.sh all --start-at 34
#   scripts/run_sims_detached.sh all --only 34            # group multi-party full sweep
#   scripts/run_sims_detached.sh intro                    # 4-sim intro E2E
#   scripts/run_sims_detached.sh --env-file /tmp/4sim.env group
#
# Device environment:
#   - With --env-file, the file is sourced (set -a) inside the detached run.
#   - Otherwise the bundled resolver (.claude/skills/sims/scripts/
#     run_with_devices.sh <scope> --print-env) is snapshotted at launch time
#     and embedded into the run script.
#
# Outputs (printed on launch):
#   LOG  — streamed runner output; final line is EXIT=<code>.
#   PGID — <log>.pgid; kill deliberately (and ONLY deliberately) with:
#              kill -TERM -"$(cat <log>.pgid)"
#
# Monitor read-only: tail -f <log> ; grep '^==> #' <log> for command
# transitions; the run is resumable via --start-at after any interruption.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/.claude/skills/sims/scripts/run_with_devices.sh"

env_file=""
log_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file)
      env_file="${2:?--env-file needs a path}"
      shift 2
      ;;
    --log)
      log_file="${2:?--log needs a path}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [ $# -lt 1 ]; then
  printf 'Usage: %s [--env-file FILE] [--log FILE] <scope> [runner options...]\n' "$0" >&2
  exit 64
fi

scope="$1"
shift

stamp="$(date +%Y%m%d-%H%M%S)"
log_dir="${SIMS_DETACHED_LOG_DIR:-$REPO_ROOT/build/sims-detached}"
mkdir -p "$log_dir"
if [ -z "$log_file" ]; then
  log_file="$log_dir/sims-$scope-$stamp.log"
fi
pgid_file="$log_file.pgid"
run_script="$log_file.run.sh"

if [ -n "$env_file" ] && [ ! -f "$env_file" ]; then
  printf 'env file not found: %s\n' "$env_file" >&2
  exit 66
fi

# Snapshot device env at launch time (unless an explicit env file owns it).
env_exports=""
if [ -z "$env_file" ]; then
  if [ -x "$HELPER" ]; then
    if ! env_exports="$("$HELPER" "$scope" --print-env 2>&1)"; then
      printf 'Device resolution failed for scope %s:\n%s\n' "$scope" "$env_exports" >&2
      exit 69
    fi
  else
    printf 'WARNING: %s not found; relying on inherited environment.\n' "$HELPER" >&2
  fi
fi

{
  printf '#!/usr/bin/env bash\n'
  printf 'exec >> %q 2>&1\n' "$log_file"
  printf 'cd %q\n' "$REPO_ROOT"
  printf 'echo "=== run_sims_detached: scope=%s args=%s ==="\n' "$scope" "$*"
  printf 'echo "=== started: $(date) pid=$$ ==="\n'
  if [ -n "$env_file" ]; then
    printf 'set -a\nsource %q\nset +a\n' "$env_file"
  elif [ -n "$env_exports" ]; then
    printf '%s\n' "$env_exports"
  fi
  printf './scripts/run_test_gates.sh reliability-sim %q' "$scope"
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
  printf 'code=$?\n'
  printf 'echo "=== finished: $(date) ==="\n'
  printf 'echo "EXIT=$code"\n'
} > "$run_script"
chmod +x "$run_script"

# Detach into a new session so the supervisor's group-wide SIGTERM cannot
# reach the run. macOS has no setsid(1); fall back to a python3 fork+setsid.
if command -v setsid >/dev/null 2>&1; then
  setsid "$run_script" >/dev/null 2>&1 &
  echo $! > "$pgid_file"
  disown
else
  python3 - "$run_script" "$pgid_file" <<'PY'
import os, sys
run_script, pgid_file = sys.argv[1], sys.argv[2]
pid = os.fork()
if pid == 0:
    os.setsid()
    devnull = os.open(os.devnull, os.O_RDWR)
    os.dup2(devnull, 0)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
    os.execv(run_script, [run_script])
with open(pgid_file, "w") as f:
    f.write(f"{pid}\n")
PY
fi

pgid="$(cat "$pgid_file")"
printf 'detached reliability-sim run launched\n'
printf '  scope: %s %s\n' "$scope" "$*"
printf '  log:   %s\n' "$log_file"
printf '  pgid:  %s\n' "$pgid"
printf '  tail:  tail -f %q\n' "$log_file"
printf '  kill (deliberate only): kill -TERM -%s\n' "$pgid"
