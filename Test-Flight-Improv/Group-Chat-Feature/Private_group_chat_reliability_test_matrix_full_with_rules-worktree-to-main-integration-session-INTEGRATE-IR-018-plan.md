# INTEGRATE-IR-018 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-018` / `Replay after restart drains before user is shown fully up to date`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-018-plan.md`.
- Source closure state: covered/accepted with observable recovery-gate depth, wired conversation recovery listening, UI recovering banner/loading state, lifecycle drain-before-ack proof, fake-network live-during-recovery proof, analyzer, host `groups`, completeness, and diff-hygiene evidence.
- Source proof profile: host-only. `3-Party E2E` was recommended but not required or claimed; no simulator, device-lab, relay, OS notification, or `integration_test` proof is required.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate, replace, or rerun the historical source implementation plan.

## Integration Scope

IR-018 imports only the missing row-owned restart freshness deltas:

- `lib/features/groups/application/group_recovery_gate.dart`
  - Expose observable active recovery depth so presentation can render recovery state while replay is pending.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - Listen to the recovery gate and pass `isRecovering` into the screen.
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - Show `group-recovery-banner` and keep the empty conversation in the loading shell while recovery is active.
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  - Add the two pure UI IR-018 selectors for empty-state suppression and visible live messages during recovery.
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - Add the wired selector proving live messages still appear while the recovery banner is active.
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - Add the lifecycle selector proving the gate stays active until pending replay drains and ack is withheld.
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
  - Add the fake-network selector proving live delivery during a blocked restart replay drain and exact-once live plus replay rows after recovery.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - Record IR-018 row closure and row-owned test inventory changes.

Out of scope: BB-012 fixture repair, IR-016 retention cutoff, IR-017 dispatcher overflow replay, IR-019 hidden outer-id dedupe, IR-020 local history deletion policy, notification routing, relay architecture, simulator/device proof, 3-party E2E, Android, physical iOS, macOS app-peer roles, and adjacent replay rows.

## Verification Contract

Focused selector:

```bash
flutter test --no-pub \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/features/groups/integration/group_startup_rejoin_smoke_test.dart \
  --plain-name 'IR-018'
```

Preservation and hygiene:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'loading shell'
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'loading shell'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'BB-012'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'
flutter analyze --no-pub \
  lib/features/groups/application/group_recovery_gate.dart \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/features/groups/integration/group_startup_rejoin_smoke_test.dart
dart format --set-exit-if-changed \
  lib/features/groups/application/group_recovery_gate.dart \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/features/groups/integration/group_startup_rejoin_smoke_test.dart
git diff --check
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Expected existing residual classifications to preserve:

- `groups` can remain red only on unrelated preserved residuals `BB-007`, `BB-012`, and `GM-029`.
- `completeness-check` can remain red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification.

## Verification Results

Focused selector passed:

```bash
flutter test --no-pub \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/features/groups/integration/group_startup_rejoin_smoke_test.dart \
  --plain-name 'IR-018'
```

- Result: `+5`, covering the two pure UI selectors, the wired live-during-recovery selector, the lifecycle pending-replay gate selector, and the fake-network startup live-plus-replay selector.

Preservation selectors passed:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'loading shell'
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'loading shell'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'BB-012'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'
```

- Results: pure loading shell `+1`, wired loading shell `+1`, lifecycle BB-012 `+3`, startup GL-018 `+1`, and resume GR-016 `+1`.

Hygiene and scoped analyzer:

```bash
flutter analyze --no-pub \
  lib/features/groups/application/group_recovery_gate.dart \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

- Strict scoped analyzer exited 1 only on pre-existing non-IR-018 diagnostics in touched files: deprecated `withOpacity` infos and async-context infos in `group_conversation_screen.dart`, plus private test-helper optional-parameter warnings for existing helpers.

```bash
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings \
  lib/features/groups/application/group_recovery_gate.dart \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/features/groups/integration/group_startup_rejoin_smoke_test.dart
dart format --set-exit-if-changed \
  lib/features/groups/application/group_recovery_gate.dart \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/features/groups/integration/group_startup_rejoin_smoke_test.dart
git diff --check
```

- Results: nonfatal scoped analyzer exited 0 with the classified existing diagnostics, Dart format `0 changed`, and diff hygiene passed.

Broad gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

- First attempt failed before test classification with `OS Error: No space left on device` while Flutter copied a compiler artifact under macOS temp. The controller cleared only generated Flutter build/temp artifacts (`.dart_tool/flutter_build` and stale `flutter_tools.*` temp dirs), preserving source and package metadata, then reran the gate.
- Retry result: `+219 -3`, red only on preserved non-IR-018 residuals:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`: expected not null, actual null.
  - `BB-012 restart recovery drains replay before ack and stays live`: expected length 1, actual empty `WhereIterable<GroupMessage>`.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery`: expected `MemberRole.writer`, actual `MemberRole.reader`.

```bash
./scripts/run_test_gates.sh completeness-check
```

- Result: `732/733`, red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification.

No iOS 26.2 live proof was run or required because the source row is host-only and its 3-party proof was recommended but not required or claimed.

## Closure Verdict

`INTEGRATE-IR-018` is accepted. Main now has the row-owned observable recovery gate, wired recovery listener, recovering banner/loading-state UI, and five row-owned host selectors proving restart replay remains visibly recovering until drain completion while live messages still arrive and persist exactly once.
