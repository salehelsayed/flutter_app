# Group Simulator Feature Test Files

Generated on 2026-06-14 from the reliability simulator discovery scripts.

This inventory is the distinct file-level coverage for:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
```

The current group simulator discovery expands to 24 distinct group entries:
12 direct simulator test files and 12 runner/orchestrator files. The expanded
check matrix has **181 group rows** (was 174; +7 from new gap-coverage rows
landed 2026-06-14 — see changelog below).

## Changelog — new gap-coverage rows (2026-06-14)

Added per `Group-Chat-Feature/NEW-SIM-ROWS-AUTHORING-PLAYBOOK.md`
(analyze + discovery gated; behavior validated on device run):

| Row | Scenario / test | Host | Δrows | Expect |
| --- | --- | --- | --- | --- |
| H01 | `private_voluntary_leave_convergence` | `run_group_multi_party_device_real.dart` | +1 | green |
| L01 | `private_media_reaction_roundtrip` | `run_group_multi_party_device_real.dart` | +1 | green |
| K04 | "stacked group message taps route … without misrouting" | `notification_open_ui_smoke_test.dart` (counts twice: direct test + runner) | +2 | green |
| C07 | `private_override_removal_nonconvergence` | `run_group_multi_party_device_real.dart` | +1 | divergence |
| B02 | `private_stale_roster_recipient_omission` | `run_group_multi_party_device_real.dart` | +1 | **RED by design** |
| I01 | `private_online_dissolve_convergence` (new harness `dissolveGroup` driver + import) | `run_group_multi_party_device_real.dart` | +1 | green (B4-fixed build) |

All six gated: `flutter analyze` clean + `group --list` count 174→181, no expansion errors.
Behavior is validated on a device/sim run.

**K01** (muted-FCM-leak) was intentionally NOT added to a sim file: recon confirmed
the foreground drain path already honors mute (would be green, not the intended RED).
The real leak is the **host-layer** FCM eligibility resolver
(`resolve_group_notification_route_target_use_case.dart`, never reads `isMuted`). The
true RED spec was landed there instead, in the **host gate** (`$run-flutter-host-gates`,
NOT the sim matrix):
`test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
→ test `'RED: suppresses FCM display for a current member of a MUTED group'`. Confirmed
**RED** (`flutter test`: `Expected: false, Actual: <true>`; the other 15 tests pass). It
turns green only when `resolveGroupMessageNotificationDisplayEligibility` is fixed to
suppress muted groups.

## Direct Simulator Test Files

| File | Discovery note |
| --- | --- |
| `integration_test/cold_start_message_render_simulator_test.dart` | group simulator smoke test |
| `integration_test/foreground_group_push_drain_test.dart` | foreground group push drain test |
| `integration_test/group_admin_metadata_convergence_simulator_test.dart` | group simulator/E2E test |
| `integration_test/group_delete_preserves_friends_simulator_test.dart` | group simulator/E2E test |
| `integration_test/group_invite_accept_spinner_simulator_test.dart` | group simulator/E2E test |
| `integration_test/group_new_member_media_simulator_proof_test.dart` | group simulator/E2E test |
| `integration_test/group_real_crypto_onboarding_test.dart` | group simulator/E2E test |
| `integration_test/group_recovery_cli_e2e_test.dart` | group simulator/E2E test |
| `integration_test/group_recovery_e2e_test.dart` | group simulator/E2E test |
| `integration_test/media_stable_id_smoke_test.dart` | group simulator smoke test |
| `integration_test/multi_relay_failover_test.dart` | group simulator/E2E test |
| `integration_test/notification_open_ui_smoke_test.dart` | notification-open smoke includes group rows |

## Runner And Orchestrator Files

| File | Discovery note |
| --- | --- |
| `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart` | group simulator/E2E orchestrator |
| `integration_test/scripts/run_group_invite_status_matrix_sim.dart` | group simulator/E2E orchestrator |
| `integration_test/scripts/run_group_multi_device_real.dart` | group simulator/E2E orchestrator |
| `integration_test/scripts/run_group_multi_party_device_real.dart` | group simulator/E2E orchestrator |
| `integration_test/scripts/run_group_recovery_e2e.dart` | group simulator/E2E orchestrator |
| `integration_test/scripts/run_media_delivery_ui_smoke.dart` | group media simulator smoke |
| `integration_test/scripts/run_media_stable_id_smoke.dart` | group media simulator smoke |
| `integration_test/scripts/run_notification_open_ui_smoke.dart` | notification-open smoke includes group rows |
| `integration_test/scripts/run_notification_sound_smoke.dart` | notification sound smoke includes group rows |
| `integration_test/scripts/run_routing_smoke_e2e.dart` | two-simulator group routing smoke |
| `scripts/run_ios_notification_tap_ui_smoke.sh` | iOS notification tap smoke includes group rows |
| `scripts/smoke_test_push_decrypt_simulator.sh` | group push-decrypt simulator smoke rows |

## Refresh Commands

Use these to regenerate or audit this file-level inventory:

```bash
./scripts/check_reliability_simulation_discovery.sh --records-tsv \
  | awk -F '\t' '$1 == "group" {print}'

./scripts/check_reliability_simulation_discovery.sh --checks-tsv \
  | awk -F '\t' '$1 == "group" {print}'

"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
```

