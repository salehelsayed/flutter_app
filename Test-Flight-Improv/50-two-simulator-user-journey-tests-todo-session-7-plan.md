# Session 7 Plan: 1:1 lifecycle, offline-pairing, and transport-transition journey proof

## Real scope

- Close the remaining Session 7 coverage asks for `5.4`, `6.3`, `15.4`,
  `16.1`, `16.3`, `16.4`, `17.2`, and `17.3` from
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
- Treat `6.3`, `17.2`, and `17.3` as the likeliest real missing proofs:
  both-sides-offline catch-up, post-migration receive continuity, and
  post-restore receive continuity.
- Revalidate `5.4`, `15.4`, `16.1`, `16.3`, and `16.4` against newer current
  repo evidence before adding any more tests, because the original audit does
  not yet account for the later WiFi/relay fallback and repeated lifecycle
  suites.
- Do not widen into a new transport harness, relay redesign, or startup
  architecture change unless a direct failing proof forces it.

## Closure bar

Session 7 is good enough when the repo has direct automated evidence that:

- both peers can queue offline 1:1 messages and recover them without loss or
  duplication when they come back together,
- a migrated database can still accept and surface a newly arrived incoming
  message on the current schema,
- a mnemonic-restored identity can still receive a queued message through the
  normal conversation listener path, and
- the remaining transport/lifecycle rows are either honestly reclassified as
  already covered by current repo evidence or tightened with one narrow extra
  proof only if that refresh exposes a real uncovered product contract.

The session should stay test-only unless one of those proofs exposes a real
production bug.

## Source of truth

- Active controller doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Coverage matrix and gap statements:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md`

When docs disagree with current repo evidence, repo evidence wins.

## Session classification

`implementation-ready`

## Exact problem statement

The lifecycle and transport area already has more current evidence than the
coverage audit records, but the remaining proof is uneven:

- `test/core/resilience/f1_wifi_relay_fallback_test.dart`,
  `test/core/lifecycle/connectivity_lifecycle_test.dart`, and
  `integration_test/transport_e2e_test.dart` already cover the practical
  WiFi/direct/relay transition seam more directly than the older audit note
  suggests for `5.4` and `16.1`.
- `test/core/lifecycle/background_reconnect_smoke_test.dart`,
  `test/integration/rapid_lock_unlock_integration_test.dart`, and
  `test/core/resilience/network_chaos_test.dart` already provide strong
  repeated-cycle, delayed-delivery, and flapping-adjacent evidence for
  `16.3` and `16.4`.
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
  plus `test/integration/notification_tap_smoke_test.dart` already prove the
  live cold-start push -> drain -> route contract, while
  `test/features/identity/presentation/screens/startup_router_recovery_test.dart`
  codifies that auto-restoring from a surviving secure-store mnemonic is not a
  live startup-router contract right now. That means `15.4` must be closed
  against the actual current startup behavior rather than an unlanded
  auto-restore assumption.
- The genuinely thin evidence is still:
  - `6.3` both peers offline, then both online later
  - `17.2` incoming-message continuity after schema migration
  - `17.3` incoming-message continuity after mnemonic restore on a new device

The goal is to add only those missing proofs and then record the honest
reclassification for the rest.

## Files and repos to inspect next

Primary direct tests:

- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/identity/application/restore_identity_use_case_test.dart`

Current evidence to revalidate before adding more:

- `test/core/lifecycle/background_reconnect_smoke_test.dart`
- `test/core/lifecycle/connectivity_lifecycle_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/resilience/network_chaos_test.dart`
- `test/core/resilience/soak_test.dart`
- `test/core/resilience/f1_wifi_relay_fallback_test.dart`
- `test/integration/rapid_lock_unlock_integration_test.dart`
- `integration_test/background_reconnect_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`
- `integration_test/transport_e2e_test.dart`
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart`

Production files only if a failing proof exposes a real bug:

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/identity/application/restore_identity_use_case.dart`
- `lib/features/identity/presentation/startup_router.dart`

## Existing tests covering this area

- `f1_wifi_relay_fallback_test.dart` already directly proves WiFi-first send,
  WiFi timeout to direct, WiFi timeout to inbox, and stable WiFi/relay/WiFi
  transitions.
- `background_reconnect_smoke_test.dart` already proves slow recovery,
  repeated background/foreground cycles, and state-stream consistency.
- `connectivity_lifecycle_test.dart` already proves relay crash recovery,
  network transition, concurrent resume, and long-background recovery.
- `network_chaos_test.dart` already proves delayed delivery and inbox fallback
  under fault injection.
- `startup_router_notification_open_test.dart` already proves cold-start inbox
  drain before route handling for the live push-open contract.
- `startup_router_recovery_test.dart` already proves the current startup
  router does not auto-restore from a surviving secure-store mnemonic when the
  app is in `needsIdentity`.

## Regression/tests to add first

- Extend `offline_inbox_roundtrip_test.dart` with a direct `6.3` both-offline
  then both-online catch-up proof.
- Extend `full_migration_chain_test.dart` with one post-upgrade incoming
  message persistence/load proof on the migrated schema.
- Extend `restore_identity_use_case_test.dart` with one post-restore queued
  receive proof that uses the restored peer ID in the normal fake-network
  conversation stack.
- Prefer test-only additions. Only touch production lifecycle, startup, or
  transport code if one of those three proofs fails for a real product reason.

## Step-by-step implementation plan

1. Re-read the Session 7 rows in the coverage audit and the current evidence
   files above.
2. Add the smallest both-offline roundtrip proof to
   `offline_inbox_roundtrip_test.dart`.
3. Add the smallest post-migration receive proof to
   `full_migration_chain_test.dart`.
4. Add the smallest post-restore receive proof to
   `restore_identity_use_case_test.dart`.
5. Re-run the exact direct Session 7 suites plus the newer reclassification
   suites that support the transport/lifecycle rows.
6. Run `./scripts/run_test_gates.sh 1to1`.
7. Run `./scripts/run_test_gates.sh transport`.
8. Run `./scripts/run_test_gates.sh baseline` only if execution touches shared
   startup or app-root production code.

## Risks and edge cases

- The new `6.3` proof must actually show both peers queueing while offline,
  not just one-sided inbox replay again.
- The migration proof should exercise the current repository/helper seam, not
  only raw schema shape assertions already covered elsewhere.
- The restore proof should verify message receipt with the restored peer ID,
  not just that the restore use case saved data successfully.
- Do not reopen the stale secure-store auto-restore assumption unless the live
  startup router contract changes in production code.

## Exact tests and gates to run

Direct suites required for Session 7:

```bash
flutter test --no-pub test/features/conversation/integration/offline_inbox_roundtrip_test.dart
flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart
flutter test --no-pub test/features/identity/application/restore_identity_use_case_test.dart
flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart test/core/lifecycle/background_reconnect_smoke_test.dart test/core/lifecycle/connectivity_lifecycle_test.dart test/core/resilience/network_chaos_test.dart test/core/resilience/soak_test.dart test/core/resilience/f1_wifi_relay_fallback_test.dart test/integration/rapid_lock_unlock_integration_test.dart test/features/identity/presentation/screens/startup_router_notification_open_test.dart test/features/identity/presentation/screens/startup_router_recovery_test.dart
```

Device/simulator-backed evidence to rerun for the reclassification rows:

```bash
flutter test -d macos --no-pub integration_test/background_reconnect_test.dart
flutter test -d macos --no-pub integration_test/wifi_relay_fallback_smoke_test.dart
flutter test -d macos --no-pub integration_test/transport_e2e_test.dart
```

Required named gates:

```bash
./scripts/run_test_gates.sh 1to1
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport
```

Conditional named gate:

```bash
./scripts/run_test_gates.sh baseline
```

Run `baseline` only if execution touches shared startup or app-root production
paths.

## Known-failure interpretation

- Treat unrelated dirty-worktree failures as historical noise unless one of the
  exact Session 7 direct suites or the required gates fails.
- If the device-backed transport suites still require per-file `-d macos`
  execution because multiple simulators are attached, record that explicitly
  instead of forcing a broken combined invocation.
- If a row closes by honest reclassification against newer current evidence,
  record that rather than adding redundant tests.

## Done criteria

- Session 7 has direct proof or honest reclassification for `5.4`, `6.3`,
  `15.4`, `16.1`, `16.3`, `16.4`, `17.2`, and `17.3`.
- The exact direct suites are green.
- `./scripts/run_test_gates.sh 1to1` is green.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` is green.
- No startup or transport architecture scope was pulled in unnecessarily.
- The breakdown ledger is updated with the accepted outcome and exact evidence.

## Scope guard

- No new transport harness program.
- No relay-server redesign.
- No startup-flow behavior change unless a failing proof shows a live bug.
- No intro, group, or posts work.
- No gate-definition edits unless a permanent suite classification actually
  changes.

## Accepted differences / intentionally out of scope

- Session 7 may close `15.4` by reclassifying the stale secure-store
  auto-restore assumption against the current startup-router contract rather
  than by implementing a new startup feature.
- Session 7 does not own the final matrix refresh; Session `10` still does.

## Dependency impact

- Session `7` remains independent of Sessions `1`-`6`, but Session `10`
  should refresh the lifecycle and startup rows against the landed evidence and
  accepted reclassifications.
