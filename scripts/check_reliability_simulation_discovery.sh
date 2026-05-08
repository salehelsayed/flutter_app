#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_mode="human"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/check_reliability_simulation_discovery.sh
  ./scripts/check_reliability_simulation_discovery.sh --records-tsv
  ./scripts/check_reliability_simulation_discovery.sh --checks-tsv

Options:
  --records-tsv   Emit classified candidates as category/kind/path/note TSV.
  --checks-tsv    Emit expanded checks/scenarios as category/path/id/note TSV.
EOF
}

while (($# > 0)); do
  case "$1" in
    --records-tsv)
      output_mode="records-tsv"
      shift
      ;;
    --checks-tsv)
      output_mode="checks-tsv"
      shift
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

records_file="$(mktemp)"
checks_file="$(mktemp)"
expansion_errors_file="$(mktemp)"
trap 'rm -f "$records_file" "$checks_file" "$expansion_errors_file"' EXIT

record() {
  local category="$1"
  local path="$2"
  local kind="$3"
  local note="$4"
  printf '%s\t%s\t%s\t%s\n' "$category" "$kind" "$path" "$note" >>"$records_file"
}

record_check() {
  local category="$1"
  local path="$2"
  local check_id="$3"
  local note="$4"
  printf '%s\t%s\t%s\t%s\n' "$category" "$path" "$check_id" "$note" >>"$checks_file"
}

record_expansion_error() {
  local path="$1"
  local note="$2"
  printf '%s\t%s\n' "$path" "$note" >>"$expansion_errors_file"
}

classify_path() {
  local path="$1"

  case "$path" in
    smoke_test_friends.sh)
      record "intro" "$path" "runner" "intro three/four-simulator scenario harness"
      return
      ;;
    reset_simulators.sh)
      record "support" "$path" "support" "intro simulator reset helper"
      return
      ;;
    lib/core/debug/intro_e2e_runner.dart)
      record "support" "$path" "support" "intro E2E app-side runner"
      return
      ;;
    lib/core/debug/e2e_test_mode.dart)
      record "support" "$path" "support" "debug E2E mode wiring"
      return
      ;;
    lib/core/debug/smoke_test_runner.dart)
      record "support" "$path" "support" "smoke-test app-side automation runner"
      return
      ;;
    scripts/push_fixture_to_simulator.sh|scripts/push_fixture_to_android_emulator.sh)
      record "support" "$path" "support" "push fixture injection helper"
      return
      ;;
    scripts/smoke_test_push_decrypt_simulator.sh)
      record "1to1" "$path" "runner" "1:1 push-decrypt simulator smoke rows"
      record "group" "$path" "runner" "group push-decrypt simulator smoke rows"
      return
      ;;
    scripts/run_ios_notification_tap_ui_smoke.sh)
      record "1to1" "$path" "runner" "iOS notification tap smoke includes 1:1 rows"
      record "group" "$path" "runner" "iOS notification tap smoke includes group rows"
      return
      ;;
  esac

  case "$path" in
    integration_test/scripts/_android_app_package.dart|\
    integration_test/scripts/routing_smoke_group_criteria.dart|\
    integration_test/setup_device.dart|\
    integration_test/benchmark_helpers.dart)
      record "support" "$path" "support" "shared integration-test helper"
      return
      ;;
    integration_test/scripts/posts_phase*_smoke.sh|\
    integration_test/posts_phase*_fake_test.dart)
      record "ignored" "$path" "ignored" "posts simulator/fake smoke outside 1:1/group/intro reliability"
      return
      ;;
    integration_test/scripts/run_benchmark_suite.dart|\
    integration_test/scripts/run_group_publish_benchmark.dart|\
    integration_test/scripts/run_timeout_accuracy_benchmark.dart|\
    integration_test/benchmark_*_harness.dart|\
    integration_test/*_performance_test.dart|\
    integration_test/*_performance_harness.dart)
      record "ignored" "$path" "ignored" "benchmark/performance coverage outside reliability simulation discovery"
      return
      ;;
  esac

  case "$path" in
    integration_test/scripts/run_routing_smoke_e2e.dart)
      record "1to1" "$path" "runner" "two-simulator 1:1 routing smoke"
      record "group" "$path" "runner" "two-simulator group routing smoke"
      return
      ;;
    integration_test/routing_smoke_alice_harness.dart|\
    integration_test/routing_smoke_bob_harness.dart)
      record "support" "$path" "support" "1:1 routing smoke harness"
      return
      ;;
    integration_test/group_smoke_alice_harness.dart|\
    integration_test/group_smoke_bob_harness.dart)
      record "support" "$path" "support" "group routing smoke harness"
      return
      ;;
  esac

  case "$path" in
    integration_test/scripts/run_transport_e2e.dart|\
    integration_test/scripts/run_wifi_relay_fallback_smoke.dart|\
    integration_test/scripts/run_soak_e2e.dart|\
    integration_test/scripts/run_media_message_journey_e2e.dart|\
    integration_test/scripts/run_notification_open_during_other_chat.dart)
      record "1to1" "$path" "runner" "1:1 simulator/E2E orchestrator"
      return
      ;;
    integration_test/scripts/run_media_stable_id_smoke.dart|\
    integration_test/scripts/run_media_delivery_ui_smoke.dart)
      record "1to1" "$path" "runner" "1:1 media simulator smoke"
      record "group" "$path" "runner" "group media simulator smoke"
      return
      ;;
    integration_test/scripts/run_notification_open_ui_smoke.dart)
      record "1to1" "$path" "runner" "notification-open smoke includes 1:1 rows"
      record "group" "$path" "runner" "notification-open smoke includes group rows"
      record "intro" "$path" "runner" "notification-open smoke includes intro routing rows"
      return
      ;;
    integration_test/scripts/run_notification_sound_smoke.dart)
      record "1to1" "$path" "runner" "notification sound smoke includes 1:1 rows"
      record "group" "$path" "runner" "notification sound smoke includes group rows"
      return
      ;;
    integration_test/notification_open_during_other_chat_alice_harness.dart|\
    integration_test/notification_open_during_other_chat_bob_harness.dart)
      record "support" "$path" "support" "1:1 notification-open two-simulator harness"
      return
      ;;
    integration_test/notification_sound_smoke_alice_harness.dart|\
    integration_test/notification_sound_smoke_bob_harness.dart)
      record "support" "$path" "support" "1:1/group notification sound harness"
      return
      ;;
  esac

  case "$path" in
    integration_test/scripts/run_group_recovery_e2e.dart|\
    integration_test/scripts/run_group_multi_device_real.dart|\
    integration_test/scripts/run_foreground_group_push_simulator_smoke.dart)
      record "group" "$path" "runner" "group simulator/E2E orchestrator"
      return
      ;;
    integration_test/foreground_group_push_simulator_alice_harness.dart|\
    integration_test/foreground_group_push_simulator_bob_harness.dart|\
    integration_test/group_multi_device_real_harness.dart)
      record "support" "$path" "support" "group simulator harness"
      return
      ;;
  esac

  case "$path" in
    integration_test/transport_e2e_test.dart|\
    integration_test/wifi_relay_fallback_smoke_test.dart|\
    integration_test/wifi_transport_test.dart|\
    integration_test/background_reconnect_test.dart|\
    integration_test/relay_chaos_soak_test.dart|\
    integration_test/soak_e2e_test.dart|\
    integration_test/conversation_bridge_test.dart|\
    integration_test/media_message_journey_e2e_test.dart|\
    integration_test/voice_message_e2e_test.dart|\
    integration_test/cold_start_sendable_no_user_action_test.dart)
      record "1to1" "$path" "test" "1:1 transport/conversation simulator test"
      return
      ;;
    integration_test/media_stable_id_smoke_test.dart|\
    integration_test/cold_start_message_render_simulator_test.dart)
      record "1to1" "$path" "test" "1:1 simulator smoke test"
      record "group" "$path" "test" "group simulator smoke test"
      return
      ;;
    integration_test/notification_open_ui_smoke_test.dart)
      record "1to1" "$path" "test" "notification-open smoke includes 1:1 rows"
      record "group" "$path" "test" "notification-open smoke includes group rows"
      record "intro" "$path" "test" "notification-open smoke includes intro routing rows"
      return
      ;;
    integration_test/foreground_group_push_drain_test.dart)
      record "1to1" "$path" "test" "foreground push drain includes 1:1 control coverage"
      record "group" "$path" "test" "foreground group push drain test"
      return
      ;;
    integration_test/group_recovery_e2e_test.dart|\
    integration_test/group_recovery_cli_e2e_test.dart|\
    integration_test/group_delete_preserves_friends_simulator_test.dart|\
    integration_test/group_invite_accept_spinner_simulator_test.dart|\
    integration_test/group_new_member_media_simulator_proof_test.dart|\
    integration_test/group_real_crypto_onboarding_test.dart|\
    integration_test/multi_relay_failover_test.dart)
      record "group" "$path" "test" "group simulator/E2E test"
      return
      ;;
  esac

  case "$path" in
    integration_test/bidi_text_smoke_test.dart|\
    integration_test/feed_performance_test.dart|\
    integration_test/feed_wired_init_performance_harness.dart|\
    integration_test/identity_progress_performance_test.dart|\
    integration_test/loading_states_smoke_test.dart|\
    integration_test/orbit_performance_harness.dart|\
    integration_test/settings_background_choice_smoke_test.dart|\
    integration_test/smoke_test.dart)
      record "ignored" "$path" "ignored" "general UI/performance smoke outside 1:1/group/intro reliability"
      return
      ;;
  esac

  record "unclassified" "$path" "unclassified" "candidate matched discovery but has no classification rule"
}

discover_candidates() {
  {
    find integration_test -maxdepth 1 -type f -name '*.dart' -print 2>/dev/null
    find integration_test/scripts -maxdepth 1 -type f -print 2>/dev/null
    find scripts -maxdepth 1 -type f \( \
      -name '*simulator*.sh' -o \
      -name '*emulator*.sh' -o \
      -name '*e2e*.sh' -o \
      -name '*smoke*.sh' \
    \) -print 2>/dev/null
    find lib/core/debug -maxdepth 1 -type f \( -name '*e2e*.dart' -o -name '*smoke*.dart' \) -print 2>/dev/null
    [ -f smoke_test_friends.sh ] && printf '%s\n' smoke_test_friends.sh
    [ -f reset_simulators.sh ] && printf '%s\n' reset_simulators.sh
  } | sed 's#^\./##' | sort -u
}

print_category() {
  local category="$1"
  local title="$2"
  local count
  count="$(awk -F '\t' -v cat="$category" '$1 == cat { count++ } END { print count + 0 }' "$records_file")"
  printf '\n%s (%s)\n' "$title" "$count"
  awk -F '\t' -v cat="$category" '$1 == cat { printf "  - [%s] %s - %s\n", $2, $3, $4 }' "$records_file" | sort
}

print_check_category() {
  local category="$1"
  local title="$2"
  local count
  count="$(awk -F '\t' -v cat="$category" '$1 == cat { count++ } END { print count + 0 }' "$checks_file")"
  printf '\n%s (%s)\n' "$title" "$count"
  awk -F '\t' -v cat="$category" '$1 == cat { printf "  - %s :: %s - %s\n", $2, $3, $4 }' "$checks_file" | sort
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

extract_dart_test_labels() {
  local path="$1"
  perl -0ne "while (/(?:^|\\n)\\s*(?:testWidgets|test)\\s*\\(\\s*((?:\\\"[^\\\"]*\\\"|'[^']*'|\\s)+)/sg) { my \$block = \$1; my \$name = ''; while (\$block =~ /\\\"([^\\\"]*)\\\"|'([^']*)'/g) { \$name .= defined \$1 ? \$1 : \$2; } \$name =~ s/\\s+/ /g; \$name =~ s/^\\s+|\\s+\$//g; print \"\$name\\n\" if \$name ne ''; }" "$path"
}

should_include_dart_label() {
  local category="$1"
  local source_path="$2"
  local label="$3"
  local lower
  lower="$(lowercase "$label")"

  case "$source_path" in
    integration_test/notification_open_ui_smoke_test.dart)
      case "$category" in
        1to1)
          case "$lower" in *group*|*intro*|*invite*|*post*) return 1 ;; *) return 0 ;; esac
          ;;
        group)
          case "$lower" in *group*) return 0 ;; *) return 1 ;; esac
          ;;
        intro)
          case "$lower" in *intro*|*invite*) return 0 ;; *) return 1 ;; esac
          ;;
      esac
      ;;
    integration_test/media_stable_id_smoke_test.dart)
      case "$category" in
        1to1)
          case "$lower" in *1:1*|*one-to-one*|*one\ to\ one*) return 0 ;; *) return 1 ;; esac
          ;;
        group)
          case "$lower" in *group*|*announcement*) return 0 ;; *) return 1 ;; esac
          ;;
      esac
      ;;
    integration_test/foreground_group_push_drain_test.dart)
      case "$category" in
        1to1)
          case "$lower" in *1:1*) return 0 ;; *) return 1 ;; esac
          ;;
        group)
          case "$lower" in *group*|*announcement*) return 0 ;; *) return 1 ;; esac
          ;;
      esac
      ;;
  esac

  return 0
}

expand_dart_test_declarations() {
  local category="$1"
  local output_path="$2"
  local source_path="$3"
  local note="$4"
  local count=0
  local label
  local detail

  detail="$note"
  if [ "$output_path" != "$source_path" ]; then
    detail="$note; target=$source_path"
  fi

  while IFS= read -r label; do
    [ -n "$label" ] || continue
    if should_include_dart_label "$category" "$source_path" "$label"; then
      record_check "$category" "$output_path" "$label" "$detail"
      count=$((count + 1))
    fi
  done < <(extract_dart_test_labels "$source_path")

  printf '%s\n' "$count"
}

extract_runner_targets() {
  local path="$1"
  awk '{
    line = $0
    while (match(line, /integration_test\/[A-Za-z0-9_\/.-]+_test\.dart/)) {
      print substr(line, RSTART, RLENGTH)
      line = substr(line, RSTART + RLENGTH)
    }
  }' "$path" | sort -u
}

expand_runner_target_tests() {
  local category="$1"
  local path="$2"
  local note="$3"
  local target
  local count
  local total=0
  local found=0

  while IFS= read -r target; do
    [ -n "$target" ] || continue
    found=1
    if [ ! -f "$target" ]; then
      record_expansion_error "$path" "references missing target test: $target"
      continue
    fi
    count="$(expand_dart_test_declarations "$category" "$path" "$target" "$note")"
    total=$((total + count))
  done < <(extract_runner_targets "$path")

  if [ "$total" -gt 0 ]; then
    return 0
  fi

  if [ "$found" -gt 0 ]; then
    record_expansion_error "$path" "target test(s) found but no $category checks matched"
  fi
  return 1
}

expand_intro_smoke() {
  local category="$1"
  local path="$2"
  local scenario
  local count=0

  while IFS= read -r scenario; do
    [ -n "$scenario" ] || continue
    record_check "$category" "$path" "$scenario" "INTRO_E2E_SCENARIO=all scenario"
    count=$((count + 1))
  done < <(
    awk '
      /^[[:space:]]*all\)/ { in_all = 1; next }
      in_all && /^[[:space:]]*;;/ { in_all = 0; next }
      in_all {
        line = $0
        while (match(line, /scenario_[A-Za-z0-9_]+/)) {
          print substr(line, RSTART, RLENGTH)
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$path"
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract INTRO_E2E_SCENARIO=all scenarios"
  fi
}

expand_routing_smoke() {
  local category="$1"
  local path="$2"
  local scenario
  local count=0

  while IFS= read -r scenario; do
    [ -n "$scenario" ] || continue
    case "$category:$scenario" in
      1to1:S*|1to1:X*|group:G*)
        record_check "$category" "$path" "$scenario" "routing smoke scenario"
        count=$((count + 1))
        ;;
    esac
  done < <(
    awk '
      /_check\(/ { pending = 1 }
      pending {
        line = $0
        if (match(line, /\047[SGX][0-9]+\047/)) {
          print substr(line, RSTART + 1, RLENGTH - 2)
          pending = 0
        }
        if (/\);/) {
          pending = 0
        }
      }
    ' "$path"
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract $category routing smoke scenarios"
  fi
}

expand_push_decrypt() {
  local category="$1"
  local path="$2"
  local id payload scope description lower
  local count=0

  while IFS='|' read -r id payload scope description; do
    [ -n "$id" ] || continue
    lower="$(lowercase "$payload $description")"
    case "$category" in
      1to1)
        case "$lower" in *one_to_one*|*1:1*) ;; *) continue ;; esac
        ;;
      group)
        case "$lower" in *group*) ;; *) continue ;; esac
        ;;
    esac
    record_check "$category" "$path" "$id" "push-decrypt scope=$scope $description"
    count=$((count + 1))
  done < <(
    awk '
      /^[[:space:]]*"S-/ {
        line = $0
        sub(/^[[:space:]]*"/, "", line)
        sub(/"[[:space:]]*,?[[:space:]]*$/, "", line)
        print line
      }
    ' "$path"
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract $category push-decrypt scenarios"
  fi
}

expand_ios_notification_tap() {
  local category="$1"
  local path="$2"
  local fixture mode label lower
  local count=0

  while IFS='|' read -r fixture mode label; do
    [ -n "$fixture" ] || continue
    lower="$(lowercase "$fixture $label")"
    case "$category" in
      1to1)
        case "$lower" in *one_to_one*) ;; *) continue ;; esac
        ;;
      group)
        case "$lower" in *group*) ;; *) continue ;; esac
        ;;
    esac
    record_check "$category" "$path" "$label" "notification tap fixture=$fixture mode=$mode"
    count=$((count + 1))
  done < <(
    awk '
      /run_scenario / {
        line = $0
        a = ""; b = ""; c = ""
        while (match(line, /"[^"]*"/)) {
          token = substr(line, RSTART + 1, RLENGTH - 2)
          a = b
          b = c
          c = token
          line = substr(line, RSTART + RLENGTH)
        }
        if (a != "" && b != "" && c != "") {
          print a "|" b "|" c
        }
      }
    ' "$path"
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract $category iOS notification tap scenarios"
  fi
}

expand_notification_sound() {
  local category="$1"
  local path="$2"
  local id description lower
  local count=0

  while IFS='|' read -r id description; do
    [ -n "$id" ] || continue
    lower="$(lowercase "$description")"
    case "$category" in
      1to1)
        case "$lower" in *1:1*|*conversation*) ;; *) [ "$id" = "S4" ] || continue ;; esac
        ;;
      group)
        case "$lower" in *group*) ;; *) continue ;; esac
        ;;
    esac
    record_check "$category" "$path" "$id" "$description"
    count=$((count + 1))
  done < <(
    awk '
      /_runScenario\(/ { in_block = 1; id = ""; description = "" }
      in_block && index($0, "id: \047") {
        line = $0
        sub(/^.*id: \047/, "", line)
        sub(/\047.*/, "", line)
        id = line
      }
      in_block && index($0, "description: \047") {
        line = $0
        sub(/^.*description: \047/, "", line)
        sub(/\047.*/, "", line)
        description = line
      }
      in_block && /^[[:space:]]*\)[,;]?[[:space:]]*$/ {
        if (id != "") {
          print id "|" description
        }
        in_block = 0
      }
    ' "$path"
  )

  if [ "$count" -eq 0 ]; then
    record_expansion_error "$path" "could not extract $category notification sound scenarios"
  fi
}

expand_record_to_checks() {
  local category="$1"
  local kind="$2"
  local path="$3"
  local note="$4"
  local count

  case "$category" in
    1to1|group|intro) ;;
    *) return ;;
  esac

  case "$kind" in
    runner|test) ;;
    *) return ;;
  esac

  case "$path" in
    smoke_test_friends.sh)
      expand_intro_smoke "$category" "$path"
      return
      ;;
    integration_test/scripts/run_routing_smoke_e2e.dart)
      expand_routing_smoke "$category" "$path"
      return
      ;;
    scripts/smoke_test_push_decrypt_simulator.sh)
      expand_push_decrypt "$category" "$path"
      return
      ;;
    scripts/run_ios_notification_tap_ui_smoke.sh)
      expand_ios_notification_tap "$category" "$path"
      return
      ;;
    integration_test/scripts/run_notification_sound_smoke.dart)
      expand_notification_sound "$category" "$path"
      return
      ;;
  esac

  if [ "$kind" = "runner" ] && expand_runner_target_tests "$category" "$path" "$note"; then
    return
  fi

  if [ "$kind" = "test" ]; then
    count="$(expand_dart_test_declarations "$category" "$path" "$path" "$note")"
    if [ "$count" -gt 0 ]; then
      return
    fi
    record_expansion_error "$path" "no Dart test declarations found for $category classification"
    return
  fi

  record_check "$category" "$path" "$(basename "$path")" "$note"
}

emit_failures_if_any() {
  local unclassified_count="$1"
  local expansion_error_count="$2"

  if [ "$expansion_error_count" -gt 0 ]; then
    printf 'Expansion errors (%s)\n' "$expansion_error_count" >&2
    awk -F '\t' '{ printf "  - %s - %s\n", $1, $2 }' "$expansion_errors_file" | sort >&2
  fi

  if [ "$unclassified_count" -gt 0 ]; then
    printf 'FAIL: %s candidate(s) are unclassified.\n' "$unclassified_count" >&2
    printf 'Add a classification rule or narrow the discovery pattern.\n' >&2
    return 1
  fi

  if [ "$expansion_error_count" -gt 0 ]; then
    printf 'FAIL: %s classified candidate(s) could not be expanded into checks/scenarios.\n' "$expansion_error_count" >&2
    return 1
  fi

  return 0
}

while IFS= read -r path; do
  [ -n "$path" ] || continue
  classify_path "$path"
done < <(discover_candidates)

while IFS=$'\t' read -r category kind path note; do
  [ -n "$category" ] || continue
  expand_record_to_checks "$category" "$kind" "$path" "$note"
done <"$records_file"

unclassified_count="$(awk -F '\t' '$1 == "unclassified" { count++ } END { print count + 0 }' "$records_file")"
expansion_error_count="$(awk 'END { print NR + 0 }' "$expansion_errors_file")"

case "$output_mode" in
  records-tsv)
    emit_failures_if_any "$unclassified_count" "$expansion_error_count"
    cat "$records_file"
    exit 0
    ;;
  checks-tsv)
    emit_failures_if_any "$unclassified_count" "$expansion_error_count"
    cat "$checks_file"
    exit 0
    ;;
esac

printf 'Reliability simulation discovery\n'
printf 'Root: %s\n' "$ROOT_DIR"

print_category "1to1" "1:1 entrypoints/files"
print_category "group" "Group entrypoints/files"
print_category "intro" "Intro entrypoints/files"
print_category "support" "Support"
print_category "ignored" "Ignored"
print_category "unclassified" "Unclassified"

printf '\nExpanded runnable checks/scenarios\n'
print_check_category "1to1" "1:1 checks/scenarios"
print_check_category "group" "Group checks/scenarios"
print_check_category "intro" "Intro checks/scenarios"

if [ "$expansion_error_count" -gt 0 ]; then
  printf '\nExpansion errors (%s)\n' "$expansion_error_count"
  awk -F '\t' '{ printf "  - %s - %s\n", $1, $2 }' "$expansion_errors_file" | sort
fi

emit_failures_if_any "$unclassified_count" "$expansion_error_count"

printf '\nPASS: all discovered simulator/E2E candidates are classified or explicitly ignored, and known tests/scenarios expanded.\n'
