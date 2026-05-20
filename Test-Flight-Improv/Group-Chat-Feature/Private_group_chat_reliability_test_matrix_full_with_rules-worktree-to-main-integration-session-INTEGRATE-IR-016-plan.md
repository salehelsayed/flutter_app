# INTEGRATE-IR-016 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-016` / `Long offline retention cutoff is explicit and does not look like message loss`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-016-plan.md`.
- Source closure state: covered/accepted with direct app, fake-network, conversation UI, list UI, criteria, runner, and iOS 26.2 3-party live proof evidence.
- Source live proof run: `1778885130194`, using iOS 26.2 Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, and Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate, replace, or rerun the historical source implementation plan.

## Integration Scope

IR-016 imports only missing row-owned retention-cutoff proof artifacts:

- Production retention support is already present in main and stays unchanged:
  - `lib/features/groups/domain/models/group_backlog_retention_policy.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/presentation/group_backlog_retention_notice.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/presentation/screens/group_list_screen.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - Add `IR-016 long offline cutoff keeps retained backlog and records incomplete history`.
  - Prove multi-page expired-plus-retained replay skips expired plaintext, persists only retained backlog, records explicit expired/retained retention timestamps, and completes durable cursor progression.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - Rename and strengthen the existing equivalent mixed-window fake-network test as `IR-016 long-offline mixed-window recovery keeps retained backlog and explicit cutoff state`.
  - Backdate group/member fixtures so the cutoff is explicitly tested instead of relying on same-day membership defaults.
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  - Row-name the existing equivalent expired and mixed-window retention banner tests.
- `test/features/groups/presentation/group_list_screen_test.dart`
  - Row-name the existing equivalent expired and mixed-window group-card retention summary tests.
- `integration_test/group_multi_party_device_real_harness.dart`
  - Add `ir016` role/scenario support and `ir016RetentionCutoffProof` live proof helpers for Alice, offline-seeded/relaunched Bob, and online-control Charlie.
- `integration_test/scripts/run_group_multi_party_device_real.dart`
  - Add `ir016` scenario discovery and dispatch through the existing offline/relaunch orchestration path with IR-016-specific runtime fixture names.
- `integration_test/scripts/group_multi_party_device_criteria.dart`
  - Add `ir016` requirements, expected proof messages, and `ir016RetentionCutoffProof` validation.
- `test/integration/group_multi_party_device_criteria_test.dart`
  - Add the `ir016` scenario requirement plus valid, silent-complete rejection, and expired-message-resurrection rejection criteria selectors.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - Record IR-016 row closure and row-owned test inventory changes.

Out of scope: `IR-015` media replay breadth, `IR-017` dispatcher overflow replay, `IR-018` restart freshness, `IR-019` hidden outer-id dedupe, relay storage internals, membership entitlement cutoffs, ML-017 removed-member local history, Android, physical iOS, macOS app-peer roles, notifications, and adjacent replay rows.

## Device/Relay Proof Profile

- Profile: `three-party/device-lab`.
- Closure evidence requires a 3-party iOS 26.2 exact-relay proof.
- Current availability checks:
  - `flutter devices --machine` shows iOS 26.2 simulators:
    - Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` (`UP004 Alice iPhone 17 Pro iOS 26.2`)
    - Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9` (`UP004 Bob iPhone Air iOS 26.2`)
    - Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` (`UP004 Charlie iPhone 17 iOS 26.2`)
  - `xcrun simctl list devices available` shows the same three iOS 26.2 simulators booted.
- A single `FLUTTER_DEVICE_ID` is not sufficient for row closure; it only selects host targets for named gates.
- Required live proof command:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ir016 -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

## Verification Contract

Focused selectors:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-016'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-016'
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'IR-016'
flutter test --no-pub test/features/groups/presentation/group_list_screen_test.dart --plain-name 'IR-016'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'IR-016'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ir016 --list-scenarios
```

Preservation and hygiene:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'within-window backlog is retained|beyond-window backlog is skipped|mixed old and new cursor pages keep retained backlog|repeated drains do not resurrect expired backlog|system envelopes older than the retention cutoff|IR-015'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'IR-015|IR-016'
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'IR-016'
flutter test --no-pub test/features/groups/presentation/group_list_screen_test.dart --plain-name 'IR-016'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'IR-015|IR-016|private_history_retention'
flutter analyze --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_list_screen_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_list_screen_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
git diff --check
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Expected existing residual classifications to preserve:

- `groups` can remain red only on unrelated preserved residuals `BB-007`, `BB-012`, and `GM-029`.
- `completeness-check` can remain red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification.

## Verification Results

Focused selectors passed:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-016'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-016'
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'IR-016'
flutter test --no-pub test/features/groups/presentation/group_list_screen_test.dart --plain-name 'IR-016'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'IR-016'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ir016 --list-scenarios
```

- Results: direct replay retention `+1`, fake-network recovery `+1`, conversation UI `+2`, list UI `+2`, criteria `+3`, and `ir016` scenario discovery passed.
- The first criteria run was discarded because it hit a concurrent Flutter native-asset `lipo` race while multiple Flutter/Dart commands were running; the same selector passed on a sequential rerun.

Preservation, hygiene, and scoped analysis passed:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'within-window backlog is retained|beyond-window backlog is skipped|mixed old and new cursor pages keep retained backlog|repeated drains do not resurrect expired backlog|system envelopes older than the retention cutoff|IR-015|IR-016'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'IR-015|IR-016'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'IR-015|IR-016|private_history_retention'
flutter analyze --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_list_screen_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_list_screen_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
git diff --check
```

- Results: drain preservation `+7`, fake-network IR-015/IR-016 preservation `+2`, criteria preservation `+11`, scoped analyzer `No issues found!`, Dart format `0 changed`, and diff hygiene passed.

iOS 26.2 live proof passed:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ir016 -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

- Run id: `1779173791340`.
- Shared proof directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ir016_nIGT2C`.
- Alice device: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` (`UP004 Alice iPhone 17 Pro iOS 26.2`).
- Bob device: `279B82AE-2BB9-4924-9AAE-581870ED3FA9` (`UP004 Bob iPhone Air iOS 26.2`).
- Charlie device: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` (`UP004 Charlie iPhone 17 iOS 26.2`).
- Verdict: `ir016 proof passed: ir016 verdicts valid for alice, bob, charlie`.

Classified residual gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
# +217 -3, red only on preserved non-IR-016 residuals BB-007, BB-012, and GM-029:
# BB-007 accepted pending invite joins with exact full config and replays accepted epoch: Expected not null, Actual null.
# BB-012 restart recovery drains replay before ack and stays live: Expected an object with length of 1, Actual empty WhereIterable<GroupMessage>.
# GM-029 config version monotonicity converges across A/B/C shuffled delivery: Expected MemberRole.writer, Actual MemberRole.reader.

./scripts/run_test_gates.sh completeness-check
# 732/733, red only on unrelated test/shared/fakes/fake_group_pubsub_network_test.dart classification.
```

## Closure Verdict

`INTEGRATE-IR-016` is accepted. Main now has row-owned direct, fake-network, UI, criteria, runner, and iOS 26.2 live proof that long-offline retention cutoff is explicit, expired backlog is not resurrected, retained backlog remains visible, and incomplete-history state is distinguishable from message loss.
