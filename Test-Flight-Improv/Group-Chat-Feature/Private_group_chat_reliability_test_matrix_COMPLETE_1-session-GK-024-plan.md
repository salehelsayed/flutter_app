# GK-024 Session Plan: Late-Joiner Pre-Join History Entitlement

Status: accepted/closed

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-024`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 18:01:25 CEST | Evidence Collector started | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`; `implementation-plan-orchestrator/SKILL.md` | GK-024 source row and breakdown row 75 confirmed as open/evidence-gated; no concrete blocker. | Inspect row-owned group key, envelope, inbox/replay code and direct tests before drafting the plan. |
| 2026-05-12 18:03:00 CEST | Evidence Collector completed | `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `lib/features/groups/application/group_offline_replay_envelope.dart`; `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Current removed-window replay checks use persisted removal cutoffs, but there is no general self late-join lower-bound. A late joiner with `selfPeerId` can still render a pre-join replay if it decrypts, and a pre-join old-key replay can queue key repair before membership-window filtering. | Reclassify from evidence-gated to implementation-ready and execute the smallest app-layer guard plus row-owned regression. |
| 2026-05-12 18:03:00 CEST | Reviewer completed | Same files plus GK-023 adjacent regression evidence in `drain_group_offline_inbox_use_case_test.dart` | Plan is sufficient with host-only proof. Device/relay proof is supplemental because the change is local membership-window filtering and no bridge, transport, or relay behavior should change. | Execute focused code/test change, then run focused and groups gate proof. |
| 2026-05-12 18:03:00 CEST | Arbiter completed | Source row GK-024, breakdown row 75, current code/test seams | No structural blocker. The session owns only GK-024; GK-025 envelope tampering and later rows remain out of scope. | Spawn execution/QA for this plan. |

## Real Scope

Own exactly `GK-024`: a member who joins after older group messages must not decrypt, repair, persist, or render pre-join history unless a future explicit product entitlement says otherwise.

In scope:

- Add a local membership-window lower-bound for the current user when `selfPeerId` is available.
- Skip replay inbox message envelopes whose relay timestamp is before the local user's `joinedAt` before decrypt/key-repair work.
- Keep a decoded-message lower-bound in `handleIncomingGroupMessage` so live/replay paths also reject plaintext messages timestamped before the local user's `joinedAt`.
- Add an exact GK-024 regression in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.

Out of scope:

- Relay ACL design, recipient storage semantics, device-lab proof, key-epoch cryptography changes, and any GK-025+ envelope tampering behavior.
- Product support for explicit pre-join history entitlement; no such entitlement is defined in this source row.

## Closure Bar

GK-024 may close only when:

- The source matrix row `GK-024` is updated to `Covered` with concrete file/test/gate evidence.
- The exact row-owned regression proves a late-joining member skips pre-join replay records by id/plaintext, does not queue pending key repair for old-key pre-join backlog, does not persist an undecryptable placeholder for that backlog, and renders a post-join replay exactly once.
- Focused GK-024 test, adjacent GK-023/GK-024 replay selector, replay signature support test, `./scripts/run_test_gates.sh groups`, `dart format --set-exit-if-changed`, and `git diff --check` pass.

## Source Of Truth

- Source matrix row `GK-024` is authoritative for row closure.
- Breakdown row 75 is authoritative for session ownership and ledger updates.
- Current code wins over stale prose:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_offline_replay_envelope.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

## Session Classification

`implementation-ready`

The row started as `needs_repo_evidence` / `evidence-gated`, but inspection found a repo-owned implementation gap: the current membership-window guard handles removed-window replay, not first-join pre-join replay.

## Exact Problem Statement

When Dana joins a private group after Alice and Bob have already sent messages, Dana's offline replay path must not turn older relay records into visible messages or key-repair prompts. Current code can process a decryptable pre-join replay because sender membership is valid, and it can queue a missing-key repair for an old-key pre-join replay before any self membership lower-bound is checked.

The expected user behavior is that Dana sees only messages at or after Dana's membership epoch/window, while post-join messages continue to render normally.

## Files And Repos To Inspect Next

- Production:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- Tests:
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/application/group_offline_replay_envelope_test.dart`
- Docs to update during closure:
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
  - this plan file

## Existing Tests Covering This Area

- `GM-033 replay resume rejects removed-window messages after self re-add` covers removed-window replay after a self-removal cutoff.
- `GK-023 re-added member skips removed-window replay and renders post-readd replay` covers the row-owned re-add removed-window case.
- Existing backlog retention tests cover age-based retention, not local membership entitlement.
- No exact `GK-024` regression currently proves first-join pre-join replay is skipped for a late joiner.

## Regression/Tests To Add First

Add `GK-024 late-joining member skips pre-join replay and renders post-join replay` in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, adjacent to GK-023.

The regression should:

- Create Alice/Bob/Dana with Dana `joinedAt == joinAt`.
- Store only Dana's current key epoch locally.
- Put two pre-join replay records in Dana's inbox:
  - one old-key pre-join record that would otherwise create a missing-key repair/placeholder
  - one current-key pre-join record that would otherwise be decryptable and render
- Put one post-join current-key record in the same replay page.
- Drain with `selfPeerId: danaPeerId`.
- Assert both pre-join ids/plaintexts are absent.
- Assert no pending repair/request exists for the old-key pre-join message.
- Assert no undecryptable or pending-key placeholder was persisted for either pre-join message.
- Assert the post-join message renders exactly once.
- Assert the cursor completes.
- Assert the row-owned skip flow event is emitted for the pre-join records.

## Step-By-Step Implementation Plan

1. In `drain_group_offline_inbox_use_case.dart`, add a small helper that skips `group_message` offline replay envelopes before decrypt when:
   - `selfPeerId` is non-empty
   - the local self member exists in the group
   - relay timestamp is parseable
   - relay timestamp is before the local self member `joinedAt`
2. Call that helper before `decodeInboxMessage` in both normal and deferred replay processing loops so old-key pre-join records do not queue key repair or placeholders.
3. Emit a focused flow event such as `GROUP_DRAIN_OFFLINE_INBOX_PRE_JOIN_REPLAY_SKIPPED` with safe ids and timestamps.
4. In `handle_incoming_group_message_use_case.dart`, reuse the resolved `selfPeerId` branch to reject decoded non-system messages whose normalized payload timestamp is before the local self member `joinedAt`. Emit a focused flow event such as `GROUP_HANDLE_INCOMING_MSG_BEFORE_SELF_JOINED`.
5. Add the GK-024 regression described above.
6. Run focused tests, adjacent replay tests, replay signature support, groups gate, format, and diff check.
7. Close docs only after the evidence is green.

## Risks And Edge Cases

- Relay timestamp is metadata, so it must only be used to fail closed before decrypt; decoded payload timestamp remains the stronger post-decrypt guard.
- Callers that do not pass `selfPeerId` cannot enforce the local user lower-bound; current app/harness paths already pass `selfPeerId` for resume/device drains.
- System membership events at or after the local join timestamp must still process. Pre-join system-message replay is outside Dana's membership window and can fail closed.
- The change must not disturb GK-023 removed-window cutoff logic or key repair for valid post-join missing-key messages.

## Exact Tests And Gates To Run

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-024 late-joining member skips pre-join replay and renders post-join replay'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GK-024 late-joining member skips pre-join replay and renders post-join replay|GK-023 re-added member skips removed-window replay and renders post-readd replay|GM-033 replay resume rejects removed-window messages after self re-add'`
- `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart`
- `./scripts/run_test_gates.sh groups`
- `dart format --set-exit-if-changed lib/features/groups/application/drain_group_offline_inbox_use_case.dart lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `git diff --check`

## Known-Failure Interpretation

No known failures are accepted for the focused GK-024 test, adjacent GK-023/GM-033 selector, replay signature support, groups gate, format, or `git diff --check`. If a broad unrelated dirty-worktree failure appears, capture the exact failing command and prove whether it is outside GK-024 before closure.

## Done Criteria

- Production guard and exact GK-024 regression are landed.
- All required tests/gates pass.
- Source matrix row GK-024 is `Covered` with concrete evidence.
- Breakdown Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 75, and Ordered Session Breakdown row 75 all record GK-024 as `covered/accepted`.
- Final program verdict remains unset while GK-025 and later unresolved rows remain.

## Scope Guard

Do not:

- Modify Go crypto, Go pubsub, relay inbox storage, relay ACLs, device harnesses, or database schema for this row.
- Add product UI for opting into pre-join history.
- Change removed-window cutoff behavior beyond preserving it under adjacent tests.
- Reclassify GK-025 or later rows as covered from this work.

## Accepted Differences / Intentionally Out Of Scope

- Host-only Flutter replay proof is sufficient for this row because the change is app-layer membership-window filtering and no relay/transport/device code should change.
- Relay-side recipient filtering remains supplemental; the app must still fail closed if the relay returns pre-join records.
- Explicit pre-join entitlement is product-scope undefined and intentionally not implemented.

## Dependency Impact

GK-024 closes the late-join entitlement prerequisite for later key/envelope rows. If this session fails, later rows involving durable replay history should not claim complete membership-window coverage from GK-024.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Command | Decision/blocker | Next action |
|---|---|---|---|---|---|
| 2026-05-12 18:11:16 CEST | Contract extraction started | `implementation-execution-qa-orchestrator/SKILL.md`; this GK-024 plan; `git status --short` | `sed -n '1,260p' /Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`; `sed -n '1,260p' Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-024-plan.md`; `git status --short` | Plan is execution-ready; worktree is dirty with unrelated changes, including owned files. No implementation/test status yet. | Complete contract extraction and inspect owner-file diffs before spawning Executor. |
| 2026-05-12 18:11:34 CEST | Contract extracted | This GK-024 plan; owned file diff check for `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | `git diff -- lib/features/groups/application/drain_group_offline_inbox_use_case.dart lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-024-plan.md`; `codex exec --help` | Scope: only GK-024 behavior in the two production files, the one drain test file, and this plan progress/verdict. Required regression/test/gates identified. `codex exec` is available for isolated Executor/QA spawning. | Spawn Executor with model `gpt-5.5` and `reasoning_effort=xhigh`; implementation/tests have not started. |
| 2026-05-12 18:14:49 CEST | Narrow child resumed and inspected | This GK-024 plan; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `lib/features/groups/application/group_offline_replay_envelope.dart`; `git status --short`; owned-file diff | `sed -n ...`; `rg -n ...`; `git status --short`; `git diff -- lib/features/groups/application/drain_group_offline_inbox_use_case.dart lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-024-plan.md` | No GK-024 code/test changes applied yet by this child. Existing dirty worktree includes prior edits in owned files; no blocker, but edits must layer without reverting those changes. | Patch pre-decrypt replay skip, decoded self-join guard, and exact GK-024 regression, then run required evidence commands. |
| 2026-05-12 18:25:00 CEST | Implementation patched | `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | `dart format lib/features/groups/application/drain_group_offline_inbox_use_case.dart lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Added pre-decrypt pre-join replay skip before normal and deferred replay decode; added decoded self-join lower-bound guard for replay drains; added exact GK-024 regression. Formatting completed. | Run focused GK-024 evidence and adjacent replay selector. |
| 2026-05-12 18:29:00 CEST | Focused evidence passed | Same owned production and test files | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-024 late-joining member skips pre-join replay and renders post-join replay'`; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GK-024 late-joining member skips pre-join replay and renders post-join replay|GK-023 re-added member skips removed-window replay and renders post-readd replay|GM-033 replay resume rejects removed-window messages after self re-add'`; `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart` | Focused GK-024 regression passed; adjacent GK-023/GM-033 selector passed; replay envelope support test passed. | Run full groups gate. |
| 2026-05-12 18:35:00 CEST | Groups gate triaged and fixed | `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | `./scripts/run_test_gates.sh groups`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IJ010 concurrent direct invite accepts converge membership epoch and delivery' --reporter compact` | Initial broad gate failures were GK-024-caused: the decoded self-join lower-bound was too broad for live smoke fixtures with materialized current local membership timestamps. Guard was narrowed to replay drain/repaired-history call sites while preserving removed-window checks; direct IJ010 repro passed after the fix. | Re-run required evidence commands after narrowing. |
| 2026-05-12 18:39:19 CEST | Required evidence complete | All owned files plus GK-024 plan progress/verdict | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-024 late-joining member skips pre-join replay and renders post-join replay'`; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GK-024 late-joining member skips pre-join replay and renders post-join replay|GK-023 re-added member skips removed-window replay and renders post-readd replay|GM-033 replay resume rejects removed-window messages after self re-add'`; `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart`; `./scripts/run_test_gates.sh groups`; `dart format --set-exit-if-changed lib/features/groups/application/drain_group_offline_inbox_use_case.dart lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` | Required focused regression passed, required adjacent selector passed, replay envelope test passed, groups gate passed, format check passed with no changes, and whitespace diff check passed. | Mark final execution verdict accepted for GK-024. |

## Final Execution Verdict

`accepted`

GK-024 is accepted for this execution slice. The implementation now skips `group_message` offline replay envelopes before decrypt/key-repair when relay metadata proves the record predates the local self member's `joinedAt`, enforces the decoded non-system lower-bound for replay drain/repaired-history application, preserves existing removed-window behavior, and covers the row with `GK-024 late-joining member skips pre-join replay and renders post-join replay`. All required evidence commands above passed.

## Closure Note

`closed/accepted` at 2026-05-12 18:43 CEST. Source matrix GK-024 is `Covered`; breakdown row 75 is `covered/accepted`. Closure evidence is the production replay entitlement guards in `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` and `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, the exact GK-024 regression in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, focused and adjacent replay passes, replay envelope support, IJ010 repro, `./scripts/run_test_gates.sh groups`, format, and `git diff --check`. Residual-only none for GK-024; GK-025 remains the next unresolved P0 row.
