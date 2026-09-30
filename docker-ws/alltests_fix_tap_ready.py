"""Tap smoke: start the 120 s native readiness bound when the XCTest case starts, not when `xcodebuild test`
(which first rebuilds) is launched. Compilation keeps its own bounded allowance. Updates the legacy source hash.
Both checkouts."""
import hashlib, pathlib
rel = 'scripts/run_ios_notification_tap_ui_smoke.sh'
old = r"""wait_for_ready_signal() {
  local ready_file="$1"
  local log_file="$2"
  local watched_pid="$3"
  local timeout_seconds="$4"
  local deadline=$((SECONDS + timeout_seconds))

  while ((SECONDS < deadline)); do
    # Match the event emitted by NotificationTapUITests, not a log predicate,
    # exported build setting, empty file, or partially written marker.
    local ready_pattern="(^|[[:space:]])${READY_MARKER} mode=(warm|cold) title_configured=(true|false)([[:space:]]|$)"
"""
new = r"""# `xcodebuild test` rebuilds before it runs the selected case. Under host load
# that build alone can exceed the native readiness bound, so compilation gets
# its own allowance and the readiness bound starts when the XCTest case starts.
readonly XCTEST_CASE_START_BUDGET_SECONDS=1800

wait_for_ready_signal() {
  local ready_file="$1"
  local log_file="$2"
  local watched_pid="$3"
  local timeout_seconds="$4"
  # Match the event emitted by NotificationTapUITests, not a log predicate,
  # exported build setting, empty file, or partially written marker.
  local ready_pattern="(^|[[:space:]])${READY_MARKER} mode=(warm|cold) title_configured=(true|false)([[:space:]]|$)"
  local case_start_pattern="^Test Case '-\[RunnerUITests\.[A-Za-z0-9_]+ [A-Za-z0-9_]+\]' started"
  local start_line=0
  if [[ -f "$log_file" ]]; then
    start_line=$(wc -l <"$log_file" | tr -d ' ')
  fi
  local build_deadline=$((SECONDS + XCTEST_CASE_START_BUDGET_SECONDS))
  while ((SECONDS < build_deadline)); do
    if [[ -f "$ready_file" ]] && grep -Eq "$ready_pattern" "$ready_file"; then
      return 0
    fi
    if [[ -f "$log_file" ]] &&
      tail -n "+$((start_line + 1))" "$log_file" | grep -Eq "$case_start_pattern"; then
      break
    fi
    if ! kill -0 "$watched_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  local deadline=$((SECONDS + timeout_seconds))

  while ((SECONDS < deadline)); do
"""
old_hash = '"scripts/run_ios_notification_tap_ui_smoke.sh": "55207b91665ee412e567e4c1cc06d513df338db9d29fe65886fcb79a3452d056"'
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, rel); s = p.read_text()
    if new not in s:
        assert s.count(old) == 1, root
        p.write_text(s.replace(old, new))
    digest = hashlib.sha256(p.read_bytes()).hexdigest()
    c = pathlib.Path(root, 'tool/testing/legacy_target_contracts.json'); ct = c.read_text()
    if old_hash in ct:
        c.write_text(ct.replace(old_hash, f'"scripts/run_ios_notification_tap_ui_smoke.sh": "{digest}"'))
    print(root, digest, 'hash_ok' if digest in c.read_text() else 'HASH NOT FOUND')
