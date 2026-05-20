# INTEGRATE-NW-007 Minimal Integration Contract

Status: accepted

Session id: `INTEGRATE-NW-007`

Source row: `NW-007 | Topic peer count zero does not clear member list or disable recovery | P0 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-007-plan.md`
- Source inventory evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Do not recreate or rerun the historical implementation plan. This contract governs only importing and verifying the already-accepted NW-007 row delta into the main checkout.

## Current-Main Classification

NW-007 was partially present in main. The production send path already treats `topicPeers == 0` with a successful durable inbox store as `successNoPeers`, persists the outgoing row as `sent`, keeps recipient receipt claims false, and records `liveFanoutState=zero_peers`.

The exact row-owned proof selectors were missing from main, and the integration breakdown/test inventory still marked NW-007 as pending or absent. Therefore this row was not `skipped_already_present`. Only the missing meaningful NW-007 row-owned test/doc delta was accepted.

## Import Scope

Allowed row-owned imports:

- durable-recipient and no-receipt selector in `test/features/groups/application/send_group_message_use_case_test.dart`
- UI active-member/recovery-banner selector in `test/features/groups/presentation/group_conversation_wired_test.dart`
- resume recovery gate/member/key preservation selector in `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- fake-network rejoin/drain/member/key preservation selector in `test/features/groups/integration/group_resume_recovery_test.dart`
- one concise `test-inventory.md` row

Affected preservation-only adjustment:

- the existing generic zero-topic-peer widget test in `group_conversation_wired_test.dart` now seeds the current user plus one active recipient before sending. This keeps the test on the zero-topic-peer path under the already-accepted GM-032 empty-membership guard; a memberless private chat send is correctly classified as `groupDissolved`.

Not imported: production code, Go/native files, runner scenarios, criteria files, live harness files, relay shared-state architecture, NW-006 disconnect semantics, NW-008 duplicate connection paths, NW-009 relay probe behavior, source docs, COMPLETE_1 docs, notification/media/Android/physical-iOS work, or unrelated worktree changes.

## Verification

Focused checks run:

```sh
dart format test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'NW-007'
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'NW-007'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-007'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-007'
```

Affected-row preservation checks run:

```sh
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'DE-007|NW-006'
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'sending a message with zero topic peers keeps the row sent and does not restore the draft'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'NW-006'
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --name 'NW-006|IR-018 recovery gate stays active until pending replay drain completes'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'DE-007|NW-006'
```

Analyzer and hygiene checks run:

```sh
dart analyze test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart
dart analyze test/features/groups/application/send_group_message_use_case_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/features/groups/integration/group_resume_recovery_test.dart
```

Results:

- Dart format: PASS
- focused NW-007 durable-recipient selector: PASS (`+1`)
- focused NW-007 UI selector: PASS (`+1`, rerun after the preservation-only widget fixture seed)
- focused NW-007 lifecycle selector: PASS (`+1`)
- focused NW-007 fake-network selector: PASS (`+1`)
- affected DE-007/NW-006 send selectors: PASS (`+2`)
- affected generic zero-topic-peer widget selector: initially reproduced the stale memberless-fixture `groupDissolved` path, then PASS (`+1`) after the preservation-only active-member seed
- affected NW-006 lifecycle selector: PASS (`+1`)
- affected DE-007/NW-006 fake-network selectors: PASS (`+2`)
- combined lifecycle preservation command also reran the preserved accepted-row IR-018 selector; NW-006 passed, while IR-018 failed at `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart:941` with `Expected: not null / Actual: <null>`. This matches the existing accepted-row IR-018 fixture-aging residual and was not repaired in NW-007.
- scoped analyzer over all four touched test files remains red only on pre-existing `test/features/groups/presentation/group_conversation_wired_test.dart:230:10` (`unused_element_parameter` on `_DownloadRepairBridge.mime`), outside the NW-007 edits.
- scoped analyzer over the other three touched files: PASS (`No issues found!`)

Preflight before execution found no stale proof runner processes, no ambient `MKNOON_` env, and the required iOS 26.2 devices booted and available for later live-proof rows:

- Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`

No relay env, shared directory, run id, or live simulator proof is required or claimed for NW-007 because the historical source row marks 3-party E2E as `N/A`.

## Final Execution Verdict

Verdict: `accepted`

NW-007 is accepted in main. The row-owned proof establishes that a zero live topic peer count does not imply empty membership or removal: active recipients stay in durable inbox targeting, no delivery/read receipt is claimed from the zero-peer publish alone, recovery remains active through rejoin/drain, UI remains writable with recovery state visible, and fake-network replay recovery converges without member/key mutation.

Residual classifications from earlier integration rows are preserved unchanged: non-row `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, `GM-029`, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, sampled retained-history drain follow-up invariant, sampled `ML-008`, sampled COMPLETE_1 `GI-017`, sampled replay-window residuals `GM-033`/`GK-023`/`GI-019`, drain `GEK003` and `GE-018`, full-listener notification/self-peer-cache failures, strict-analyzer pre-existing infos/warnings, completeness classification failure, and `KE-007`/`KE-009` blocked-conflict records remain for future row-owned/follow-up work.
