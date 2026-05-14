# GK-023 Session Plan - Re-added member cannot decrypt removed-window backlog

Status: accepted/closed

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-023`

## Scope

Own exactly `GK-023`: C is re-added with a new key, retrieves all relay records, membership windows are applied, removed-window backlog records remain hidden/skipped, and post-readd records render.

This is a row-owned replay/membership-window proof. Do not reopen broader GM/GI/GE rows, and do not change relay, transport, crypto wire format, device harness, or membership product rules unless the focused GK-023 regression proves current behavior is missing.

## Evidence State

- Planning intake found the source row unresolved with only a generic "Prevents history leakage" note.
- Planning intake found breakdown row 74 missing an exact row-owned `GK-023` regression.
- Existing adjacent test `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GM-033 replay resume rejects removed-window messages after self re-add` already exercised the same app-layer replay path: C drains one page, receives a self-removal cutoff, is re-added with a later membership timestamp and epoch, then drains all relay records. It proves the removed-window message id/text is absent while the post-readd message renders once.
- Closure now records the row-named GK-023 proof in the source matrix and breakdown ledgers.

## Implementation Steps

1. Add an exact row-owned regression in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, near the existing GM-033 removed-window replay test.
2. Name the test `GK-023 re-added member skips removed-window replay and renders post-readd replay`.
3. Build the scenario with Alice, Bob, and Charlie:
   - C has an initial membership and E1.
   - C drains an allowed pre-removal replay page and persists the cursor.
   - C receives a trusted self-removal system event, which persists the removal cutoff and clears the local group.
   - C is re-added with `joinedAt == readdAt` and receives E2.
   - The relay page after the cursor returns all backlog records, including a removed-window E1 record, a post-readd E2 record, and a duplicate removed-window E1 record.
4. Assert removed-window records are not persisted or rendered by id or plaintext, post-readd E2 renders exactly once, no pending key repair is queued for the removed-window message, the cursor completes, and the self-removed-window-after-rejoin flow event is emitted.
5. If the focused test fails because production behavior leaks removed-window plaintext or queues repair/decrypt work for removed-window records, reclassify GK-023 as `needs_code_and_tests` and fix the narrow app-layer membership-window owner files before closure.

## Test/Gate Plan

Focused proof:

```sh
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-023 re-added member skips removed-window replay and renders post-readd replay'
```

Adjacent replay proof:

```sh
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GK-023 re-added member skips removed-window replay and renders post-readd replay|GM-033 replay resume rejects removed-window messages after self re-add'
```

Replay signature support:

```sh
flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart
```

Group gate:

```sh
./scripts/run_test_gates.sh groups
```

Hygiene:

```sh
dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
git diff --check
```

## Done Criteria

- `GK-023` source matrix row is updated to `Covered` with concrete file/test/gate evidence.
- The breakdown Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 74, and Ordered Session Breakdown row 74 all record `GK-023` as covered/accepted.
- This plan records the final execution verdict and closure note.
- No final program verdict is written while later source rows remain unresolved.

## Scope Guard

Allowed files:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- this plan file

Production code changes are out of scope unless the focused GK-023 test exposes a repo-owned implementation gap in membership-window replay filtering.

## Device/Relay Proof Profile

Profile: `host-only`.

The row requires app-layer replay/decrypt/render proof for relay records already returned to the client. A Flutter host unit/application test against `drainGroupOfflineInbox`, signed offline replay envelopes, local repositories, membership windows, and key epochs is sufficient closure evidence for this session. Real device, simulator, and relay ACL proof are supplemental because this row does not require changing transport, relay storage, simulator harness, OS notification, or multi-device code.

## Execution Progress

- `2026-05-12T15:31:50Z` - Contract extracted. Scope is GK-023 only; writable files narrowed by user instruction to `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` and this plan. Source matrix and breakdown closure ledgers are explicitly out of scope for this execution step. Spawned Executor/QA isolation is unavailable in this tool environment; using bounded local sequential fallback with file-backed evidence.
- `2026-05-12T15:32:37Z` - Local Executor running. Inspected adjacent `GM-033 replay resume rejects removed-window messages after self re-add` in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; adding exact row-owned GK-023 regression beside it with the same replay/membership-window owner path.
- `2026-05-12T15:35:27Z` - Local Executor completed test addition. Touched `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` and this plan only. `dart format test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` completed with no changes after formatting. Focused GK-023 proof passed. Adjacent GK-023/GM-033 replay proof passed. Replay signature support `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart` passed. Next action: run `./scripts/run_test_gates.sh groups`.
- `2026-05-12T15:37:25Z` - Group gate and hygiene completed. `./scripts/run_test_gates.sh groups` passed. `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed with `0 changed`. `git diff --check` passed. Local QA Reviewer inspected scope and evidence: no blocking issues for scoped GK-023 execution; source matrix and breakdown closure updates remain intentionally deferred per user instruction.

## Final Execution Verdict

Final verdict: `accepted`

Spawned-agent isolation used: no; nested agent spawning is unavailable in this tool environment.

Local sequential fallback used: yes.

Files changed in this scoped execution:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-023-plan.md`

Tests added or updated:

- Added `GK-023 re-added member skips removed-window replay and renders post-readd replay` near the existing GM-033 removed-window replay test.

Exact tests and gates run:

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-023 re-added member skips removed-window replay and renders post-readd replay'` - passed.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GK-023 re-added member skips removed-window replay and renders post-readd replay|GM-033 replay resume rejects removed-window messages after self re-add'` - passed.
- `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart` - passed.
- `./scripts/run_test_gates.sh groups` - passed.
- `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` - passed.
- `git diff --check` - passed.

Blocking issues remaining: none for the scoped GK-023 test implementation.

Why this session is safe to consider complete:

- The row-owned regression proves a re-added member skips removed-window replay records by id/plaintext, renders the post-readd replay exactly once, avoids pending key repair for the removed-window message, completes the cursor, and emits the self-removed-window-after-rejoin flow event. The focused, adjacent, signature, groups gate, format, and diff-check commands all passed.

## Closure Note

Closure verdict: `accepted/closed`.

The source matrix row `GK-023` is now `Covered`, and the breakdown Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 74, and Ordered Session Breakdown row 74 all record GK-023 as `covered/accepted` with concrete evidence. No production, relay, transport, or device harness code changed. Residual-only: none for GK-023. GK-024 remains the next unresolved P0 row, so no final program verdict was written.
