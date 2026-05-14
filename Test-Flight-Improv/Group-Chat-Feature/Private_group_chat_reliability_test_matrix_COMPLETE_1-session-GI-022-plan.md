# GI-022 Session Plan: Revoked Device Replay Rejection

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-022`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 07:24:00 CEST | Controller | Source matrix GI-022 row; breakdown row 141; existing live revoked-device Go validator coverage; `lib/features/groups/domain/models/group_member.dart`; `lib/features/groups/application/group_offline_replay_envelope.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; exact GI-021 closure artifacts | The source row remains `Open` and the breakdown marks GI-022 `needs_code_and_tests` / `implementation-ready`. Replay signature lookup already ignores inactive devices because `GroupMember.findDeviceById` and transport/signing-key lookup default to active devices, but a revoked-device replay currently collapses to generic `unknown_sender` signature failure and aborts the group drain rather than rejecting the stale device and continuing to valid same-page replay. | Add explicit revoked-device replay signature classification, make offline drain skip that rejected envelope without decrypting/rendering, and add an exact GI-022 Flutter replay regression with a revoked-device envelope followed by an active-device envelope in the same page. |

## Scope

GI-022 owns the app offline replay authorization contract for a relay-stored group message whose signed replay envelope claims a revoked device under an otherwise current group member. The row closes only when stale-device replay is rejected/hidden and valid active-device replay still proceeds.

Out of scope: live Go PubSub revoked-device validation, non-member replay, key epoch grace, duplicate replay attacks, relay authorization internals, and device-backed simulator proof.

## Execution Contract

1. Teach replay signature verification to distinguish a matched but inactive/revoked member device from an unknown sender.
2. Teach offline inbox drain to emit replay rejection evidence for revoked-device envelopes and skip them without group decrypt or timeline persistence.
3. Add `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-022 revoked-device replay is rejected while active-device replay continues`.
4. Seed a current member with one active device and one revoked device.
5. Put a revoked-device replay envelope followed by an active-device replay envelope in the same cursor page.
6. Assert the revoked message id/text is absent, the active message renders once, only the active envelope is signature-verified/decrypted, the cursor completes, and flow events report the revoked-device rejection.
7. Run focused GI-022 and adjacent replay/live device-binding selectors, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-022 offline replay proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-022'` |
| Adjacent GI-021 non-member replay guard | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-021'` |
| Adjacent replay envelope binding proof | `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name 'EK004 builds signed replay envelopes bound to sender and payload'` |
| Hygiene | `dart format --set-exit-if-changed lib/features/groups/application/group_offline_replay_envelope.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-021 artifacts. GI-022 scope is limited to replay signature classification, offline drain rejected-envelope continuation, the exact row-owned test, this plan, and closure documentation updates.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 07:34:00 CEST | Executor | Updated `lib/features/groups/application/group_offline_replay_envelope.dart` so replay signature verification distinguishes matched inactive/revoked member devices as `GroupOfflineReplaySignatureException('revoked_device')` instead of collapsing them into generic `unknown_sender`. Updated `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` so revoked-device replay emits `GROUP_DRAIN_OFFLINE_INBOX_REPLAY_SIGNATURE_REJECTED` and is skipped without decrypting/rendering or aborting the page. Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-022 revoked-device replay is rejected while active-device replay continues`, which seeds one active and one revoked device under the same member, places revoked-device replay followed by active-device replay in one cursor page, and proves revoked content is absent while active content renders once with active transport attribution. | Covered the row-owned device-revocation replay contract with code plus test evidence. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-022'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-021'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name 'EK004 builds signed replay envelopes bound to sender and payload'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'EK004 invalid or missing replay signatures abort before cursor side effects'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once'` | Passed (`+1`). |
| `dart format --set-exit-if-changed lib/features/groups/application/group_offline_replay_envelope.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed (`0 changed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-022 is covered by code-plus-test Flutter replay evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-022; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-022 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 141, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-022 ownership and must not mask a repo-owned blocker.
