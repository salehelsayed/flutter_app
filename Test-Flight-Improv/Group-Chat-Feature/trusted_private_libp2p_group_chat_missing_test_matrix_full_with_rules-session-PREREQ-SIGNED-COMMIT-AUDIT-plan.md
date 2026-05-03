Status: accepted; final QA passed

# PREREQ-SIGNED-COMMIT-AUDIT Plan

## Planning Progress

| Time | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T15:12:13+02:00 | Arbiter completed | Reviewer findings, adjusted test list, closure bar, scope guard, migration stop rule, accepted differences | No structural blockers remain. Incremental details are documented; signed audit rather than MLS commits is an accepted implementation shape for this prerequisite if tests prove the contract. | Execute with RED-first tests, code, gates, and no source-row closure overclaims. |
| 2026-05-01T15:10:52+02:00 | Reviewer completed; Arbiter started | Full draft plan, signed transition family list, production sender search for system payloads, direct test list, gate contract, migration stop condition | Plan is sufficient with small adjustments: name `member_added` receive-side tests explicitly and include presentation direct tests if sender hooks are touched. Adjustments applied in this pass. | Classify findings and finalize if no structural blockers remain. |
| 2026-05-01T15:08:25+02:00 | Planner completed; Reviewer started | Source rows, inventory rows, breakdown prerequisite row, current DB/event-log/key/listener/Go evidence, and gate definitions | Draft plan is implementation-ready as a narrow signed transition audit prerequisite. New schema is expected only if the executor chooses first-class indexed audit columns; otherwise the existing event-log payload can carry audit data. | Review for missing files, closure overclaims, migration stop rules, and test/gate sufficiency. |
| 2026-05-01T15:05:21+02:00 | Evidence Collector completed; Planner started | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md` EK-004/EK-012/DB-012 rows and prerequisite owner table; `test-inventory.md` EK-004/EK-012/DB-012 entries; session breakdown PREREQ-SIGNED-COMMIT-AUDIT row and final verdict; `group_event_log_db_helpers.dart`; migration `060`; `lib/main.dart`; listener/key-update/role/Go PubSub owner files; direct tests/gate definitions | Evidence supports a repo-owned implementation plan: current log is hash-chained and replay-aware but not actor-signed commit/transition/audit; DB version is already `62`, so new schema work must reserve the next free migration at execution time. | Draft narrow code+tests plan with EK-004/EK-012/DB-012 closure limits and explicit non-goals. |
| 2026-05-01T15:03:47+02:00 | Evidence Collector started | `implementation-plan-orchestrator/SKILL.md`; `git status --short`; target plan path existence check; initial `rg` for `PREREQ-SIGNED-COMMIT-AUDIT`, `EK-004`, `EK-012`, `DB-012` | Target plan file was missing; repo has many pre-existing dirty files, so this session will own only this new plan artifact. | Read source matrix rows, inventory entries, reopened prerequisite row, and relevant code/tests before drafting. |

## Execution Progress

| Time | Phase | Files inspected or touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T16:15:23+02:00 | final QA accepted | this plan; source matrix; test inventory; session breakdown; signed-audit, group listener, direct key-update listener, key-rotation, role-update, presentation sender-hook, and Go signature-guard paths | Final QA found no blocking findings. Direct append-wired `group_key_update` signed audit is mandatory before key update/save/log side effects; event-log evidence stores hashes/audit identifiers rather than raw `encryptedKey` or raw signatures; docs keep EK-004, EK-012, and DB-012 `Partial` with narrowed blockers. Reruns passed: focused PREREQ Flutter `+8`, presentation PREREQ `+2`, Go invalid-signature regex, `./scripts/run_test_gates.sh groups` `+101`, `./scripts/run_test_gates.sh completeness-check` `700/700`, and `git diff --check`. | Mark breakdown row `PREREQ-SIGNED-COMMIT-AUDIT` accepted/qa_passed and continue to the next prerequisite. |
| 2026-05-01T16:06:10+02:00 | fix-pass docs and hygiene green | source matrix, test inventory, session breakdown, this plan; `git diff --check` | Docs no longer state direct key-update audit is optional. EK-004, EK-012, and DB-012 remain `Partial`; no row moved to `Covered`. Post-doc `git diff --check` passed. | Hand off fix-pass-completed result to final isolated QA. |
| 2026-05-01T16:05:08+02:00 | fix-pass verification green | `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`; `lib/features/groups/application/group_key_update_listener.dart`; direct key-update tests; required gates | QA blocker fixed: direct distributed `group_key_update` plaintext now carries stable per-recipient `sourceEventId`, shared `eventAt`, and `signedTransitionAudit` while preserving the canonical key-update signature; append-wired listener requires and verifies that audit before `group:updateKey`, key save, or event-log append; direct key-update event-log payloads store hashes/audit identifiers instead of raw `encryptedKey`. Required fix-pass commands passed: rotate PREREQ `+2`, listener PREREQ `+2`, full listener `+26`, full rotation `+18`, groups gate `+101`, completeness `700/700`, and pre-doc `git diff --check`. | Update docs/rows without moving EK-004, EK-012, or DB-012 to `Covered`, then rerun `git diff --check`. |
| 2026-05-01T15:46:12+02:00 | final executor hygiene green | docs stale-blocker grep; `git diff --check` | Source matrix, inventory, and breakdown no longer contain stale signed-audit/commit-transition blocker names for this prerequisite. Final `git diff --check` passed after docs updates. | Hand off executor-completed result to isolated QA. |
| 2026-05-01T15:44:59+02:00 | executor docs updated | source matrix, test inventory, session breakdown, this plan | Recorded executor-completed evidence after green gates only. No source row moved to `Covered`; EK-004, EK-012, and DB-012 remain `Partial` with narrowed blockers. | Run final doc hygiene and diff checks, then hand off to isolated QA. |
| 2026-05-01T15:39:25+02:00 | required gates green | Go group topic validator regex; `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check`; `git diff --check` | Remaining required gates passed: Go regex 1 test with 10 subtests; groups gate 101 tests; completeness check 700/700 files classified; diff check clean. No schema migration was added. | Update source matrix, inventory, breakdown, and final plan verdict without overclaiming row coverage. |
| 2026-05-01T15:38:25+02:00 | conditional presentation directs green | `test/features/groups/presentation/contact_picker_wired_test.dart`; `test/features/groups/presentation/group_info_wired_test.dart` | Added PREREQ-named presentation assertions for signed system transition audit emission. Conditional directs now pass: contact picker PREREQ 1 test; group info PREREQ 1 test. | Run remaining required Go regex and named gates. |
| 2026-05-01T15:36:19+02:00 | conditional presentation direct gap found | `test/features/groups/presentation/contact_picker_wired_test.dart`; `test/features/groups/presentation/group_info_wired_test.dart` | Full impacted application direct tests are green, but the conditional presentation command `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'` ran zero tests because the touched sender-hook suites lacked PREREQ-named presentation coverage. | Add narrow PREREQ-named presentation tests for signed audit payload emission, then rerun the conditional presentation commands. |
| 2026-05-01T15:30:51+02:00 | focused PREREQ tests green | signed audit helper, event log helper, group listener, direct key-update listener, key rotation sender, PREREQ tests | Added no-migration signed transition audit helper, listener-side signed audit rejection/idempotency, direct key-update audit persistence, key-rotated sender audit, and focused tests. Focused PREREQ commands now pass: DB helper 5 tests; listener PREREQ 2 tests; direct key-update PREREQ 1 test; role helper PREREQ 1 test; key rotation PREREQ 1 test. | Run full impacted direct files and fix compile/behavior issues without widening scope. |
| 2026-05-01T15:23:32+02:00 | RED evidence captured | focused helper/listener/key/role/rotation tests; `go-mknoon/node/pubsub_test.go` | RED confirmed: DB helper PREREQ test fails because conflict reason is legacy `conflicting replay` rather than privacy-safe `conflicting_replay`; Flutter PREREQ tests fail to compile because `signed_group_transition_audit.dart` and its APIs do not exist. Go regex passes existing outer signature guard, 1 test with 10 subtests. | Implement narrow signed transition audit helper, listener verification, direct key-update audit, and sender-side signed audit payloads. |
| 2026-05-01T15:21:47+02:00 | RED tests added | `test/core/database/helpers/group_event_log_db_helpers_test.dart`; `test/features/groups/application/group_message_listener_test.dart`; `test/features/groups/application/group_key_update_listener_test.dart`; `test/features/groups/application/update_group_member_role_use_case_test.dart`; `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` | Added focused PREREQ signed-audit tests before production changes. Tests require the new shared signed transition audit helper and missing-audit rejection path, which current code does not yet provide. | Run focused RED commands and record failures. |
| 2026-05-01T15:16:17+02:00 | executor contract extracted | this plan; `git status --short`; `lib/main.dart`; `lib/core/database/migrations/` | Executor scope extracted. Dirty tree is broad and pre-existing across owner files. `lib/main.dart` remains at database version `62`; migrations end at `062_group_member_device_identities.dart`; no schema migration reserved. | Inspect current owner-file diffs, then add RED tests for signed transition audit before production changes. |
| 2026-05-01T15:14:35+02:00 | controller contract extracted | `git status --short`; `lib/main.dart`; this plan | Dirty tree confirmed with many pre-existing group/chat/migration edits. DB version is `62` with migrations through `062_group_member_device_identities.dart`; no session-owned schema migration is reserved yet. Exact scope, direct tests, named gates, non-goals, and source-row movement limits extracted from this plan. | Spawn isolated Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`. |

## real scope

This session owns the signed audit or signed commit-transition prerequisite for the EK-004, EK-012, and DB-012 blockers that explicitly name signed audit, signed commit/transition replay, complete replay-signature equivalence, commit-transition apply, and transition diagnostics.

Implement the narrowest viable model for the current architecture: a signed group transition audit record, carried inside security-relevant group system events and persisted in the existing tamper-evident event log. A full MLS commit protocol is not required if the signed audit record proves the same closure properties for the shipped transition families.

Required signed transition families:

- `group_created`, preserving the existing signed initial create event and aligning it with the shared audit schema.
- `members_added` and `member_added` where the shipped listener still accepts the single-member form.
- `member_removed`, including voluntary leave as the current ban-equivalent shipped removal path.
- `member_role_updated`.
- `group_metadata_updated`, preserving the existing signed metadata actor envelope and either adapting it to the shared audit schema or nesting it under the shared audit envelope.
- `group_dissolved`.
- `key_rotated`.
- Direct `group_key_update`, preserving the existing canonical key-update signature while adding it to the signed transition/audit proof and replay diagnostics.

The audit record must bind at least:

- `schemaVersion`, `transitionType`, `groupId`, `sourceEventId`, and `eventAt`.
- actor member id plus actor device id, actor transport Peer ID, and actor signing public key or key package id when present.
- transition subject fields, such as added/removed member ids, role before/after, metadata config hash, dissolve actor, key epoch, or recipient key-update target.
- the canonical pre-transition state hash or previous signed transition hash.
- the canonical post-transition state hash or transition output hash.
- `signatureAlgorithm`, canonical `signedPayload`, and actor `signature`.

What does not change:

- No welcome/key-package lifecycle, key-package freshness/tombstones, weak-package validation, wrong-recipient welcome repair, or admission repair UX. Those remain `PREREQ-WELCOME-KEY-PACKAGE`.
- No future-epoch pending queue, missing-key repair trigger, live decryption placeholder lifecycle, or pending-key repair UI. Those remain `PREREQ-FUTURE-EPOCH-KEY-REPAIR`.
- No group receipts, durable sync cursor, receipt transaction boundary, ban/unban product model, remote message delete product model, or history gap repair protocol.
- No broad transport rewrite, relay-store protocol rewrite, group role redesign, contact trust UI, or safety-number UI.

## closure bar

This prerequisite is good enough when code and tests prove all of the following for the shipped transition families:

- Locally authored transition system events include a signed canonical audit payload before live publish, offline replay storage, event-log append, or local timeline-only transition rows are treated as durable evidence.
- Receive-side `GroupMessageListener` rejects missing, malformed, mismatched, stale-previous-hash, wrong-actor, wrong-device, wrong-transport, and invalid-signature audit payloads before group/member/key/message/timeline persistence, `group:updateConfig`, `group:updateKey`, event-log append, listener stream emission, or local notification side effects.
- Offline replay routes enforce the same signed audit verification as live PubSub delivery for the signed transition families. An event accepted live with the same signed payload is idempotent through offline replay; a replay with changed transition body, actor, timestamp, prior hash, target, or signature fails before mutation.
- The event log remains hash-chained and tamper-evident, and it can surface privacy-safe diagnostics for conflicting replay or fork/gap evidence without storing private keys, plaintext secrets, raw signatures in logs, or raw peer addresses in diagnostics.
- Exact duplicate signed transitions are idempotent. Conflicting replays with the same source event id fail. A transition signed against a stale or incompatible previous transition/audit hash is rejected or quarantined with a privacy-safe diagnostic instead of silently applying.
- Existing valid group send, invite, key rotation, role update, metadata update, membership replay, and direct key-update behavior stays green.

Source row movement after this prerequisite:

- EK-004 may move to `Covered` only if implementation also proves complete security-relevant event-family signature coverage and complete offline replay signature equivalence for all shipped event families. If any shipped family still accepts unsigned or replay-divergent mutation, leave EK-004 `Partial` and update only the blocker note.
- EK-012 may only drop or narrow the signed commit/transition replay and transition diagnostic blockers if signed transition replay/idempotency evidence is complete. EK-012 remains `Partial` if first-class key-package replay/freshness/tombstone work is still missing.
- DB-012 may only drop or narrow the commit-transition apply blocker if signed transition idempotency is complete for the named transition families. DB-012 remains `Partial` while bans, remote message deletes, receipts, key-package transitions, or the all-family idempotency matrix are missing.

## source of truth

- Active plan: this file after it reaches `Status: execution-ready`.
- Source matrix: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, rows EK-004, EK-012, DB-012, and the remaining-partial prerequisite table.
- Evidence inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, entries EK-004, EK-012, DB-012, and DB-002.
- Session breakdown: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, reopened prerequisite row `PREREQ-SIGNED-COMMIT-AUDIT` and final program verdict.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Current code and direct tests beat stale prose. If a document claims a row is covered but code/tests do not prove it, implementation must update the document truthfully rather than coding to stale text.

## session classification

`implementation-ready`

Reason: the missing signed transition/audit model is repo-owned. The likely code and test surfaces are available, host/fake-network proof is sufficient to start, and the previous prerequisite `PREREQ-DEVICE-IDENTITY` is accepted. There is no external fixture blocker for this planning session.

## exact problem statement

Current evidence proves several adjacent pieces but not this prerequisite:

- `group_event_log_db_helpers.dart` provides a per-group hash chain, deterministic canonical payloads, source-event uniqueness, exact duplicate idempotency, conflicting replay rejection, and chain verification.
- `create_group_use_case.dart` already signs the initial `group_created` event into the event-log payload.
- `group_message_listener.dart` appends accepted membership, role, metadata, dissolve, and `key_rotated` system events to the event log and verifies signed metadata actor envelopes, stale watermarks, authorization, and config hashes.
- `group_key_update_listener.dart` verifies direct `group_key_update` signatures before `group:updateKey`, log append, or key save.
- `go-mknoon/node/pubsub.go` validates v3 PubSub envelope membership, device/transport binding, epoch, and signature before accept.

The missing piece is a single signed transition/audit contract for all security-relevant group state transitions. Most shipped system events still rely on the Go encrypted envelope signature plus app authorization/watermarks, and offline replay rehydrates decrypted system text through the listener without a first-class signed transition record that can independently prove actor, previous state, next state, replay equivalence, and fork/gap diagnostics.

User-visible behavior that must improve: forged, replayed, reordered, or tampered group state transitions cannot silently mutate membership, roles, metadata, dissolve state, or key state after live delivery, offline replay, resume, or duplicate delivery.

Behavior that must stay unchanged: valid group membership changes, role changes, metadata changes, key rotation, direct key updates, normal messages/reactions, invite flows, and fake-network group integration must remain green.

## files and repos to inspect next

Production files expected to change or be directly inspected:

- `lib/core/database/helpers/group_event_log_db_helpers.dart`
- `lib/core/database/migrations/<next>_group_event_log_signed_audit.dart` only if first-class audit columns are required
- `lib/main.dart` only if a new migration is required
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart` only for its current `members_added` sender hook
- `lib/features/groups/presentation/screens/group_info_wired.dart` only for current `member_removed`, `member_role_updated`, and `group_metadata_updated` sender hooks
- `lib/features/groups/application/group_offline_replay_envelope.dart` and `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` only if replay metadata must carry audit fields outside the encrypted plaintext
- `go-mknoon/node/pubsub.go` as a guard file; do not change the Go envelope protocol unless the Dart-side signed audit cannot satisfy closure without it

Likely test files:

- `test/core/database/helpers/group_event_log_db_helpers_test.dart`
- `test/core/database/migrations/<next>_group_event_log_signed_audit_test.dart` only if a migration is added
- `test/core/database/integration/full_migration_chain_test.dart` only if a migration is added
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/update_group_member_role_use_case_test.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` if the offline inbox path needs a separate end-to-end replay assertion beyond `handleReplayEnvelope`
- `test/features/groups/application/member_removal_integration_test.dart` if voluntary leave/removal key rotation fixtures need signed audit payload updates
- `test/features/groups/presentation/contact_picker_wired_test.dart` if `contact_picker_wired.dart` sender wiring changes
- `test/features/groups/presentation/group_info_wired_test.dart` if `group_info_wired.dart` sender wiring changes
- `go-mknoon/node/pubsub_test.go`

Dirty-worktree handling:

- Start execution with `git status --short`.
- Before editing any expected owner file, inspect its current diff. Many files are already dirty from prior sessions; do not revert, restage, or overwrite unrelated edits.
- If an owner file has concurrent unrelated edits, make the smallest additive patch that works with those edits. If that is impossible, stop and report the conflict.
- Do not touch source matrix, inventory, or breakdown during implementation until code and tests pass and closure evidence is ready.

Migration/version stop conditions:

- Current `lib/main.dart` uses database version `62` and migrations through `062_group_member_device_identities.dart`.
- Prefer no schema migration if signed audit data can be stored and verified through existing `canonical_payload` plus helper-level parsing.
- If first-class audit columns or indexes are needed, reserve the next free migration number at execution time, expected `063`. Stop and refresh the plan if another dirty-tree change already claimed `063`, if `lib/main.dart` is no longer at version `62`, or if the full migration chain cannot be updated without overwriting another session.

## existing tests covering this area

Existing positive coverage:

- `test/core/database/helpers/group_event_log_db_helpers_test.dart` proves deterministic canonical payloads, per-group hash chain, exact duplicate idempotency, conflicting replay rejection, and row tamper verification.
- `test/core/database/migrations/060_group_event_log_test.dart` and `test/core/database/integration/full_migration_chain_test.dart` cover the current event-log table and full chain.
- `test/features/groups/application/create_group_use_case_test.dart` proves the initial `group_created` event is signed and appended without private-key leakage.
- `test/features/groups/application/group_message_listener_test.dart` covers DB-002 event-log append/replay behavior for membership and metadata events, metadata actor signature rejection, role replay, duplicate shipped system events, stale membership/metadata watermarks, unauthorized mutation rejection, dissolve idempotency, and live duplicate notification suppression.
- `test/features/groups/application/group_key_update_listener_test.dart` covers direct key-update signature verification, tampered replay rejection, exact duplicate replay idempotency, and key save/update behavior.
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` covers direct key-update signing and key-rotation broadcast behavior.
- `go-mknoon/node/pubsub_test.go` covers invalid signatures for current security event families at the Go PubSub envelope layer.

Missing coverage:

- No shared signed transition/audit schema spans all security-relevant system event families.
- No receive-side test proves unsigned `members_added`, `member_removed`, `member_role_updated`, `group_dissolved`, or `key_rotated` system events fail before mutation solely because their transition audit is missing.
- No offline replay test proves signed transition audit equivalence between live and inbox-delivered system payloads.
- No test proves stale previous-transition hash or forked signed transition diagnostics.
- No DB helper test proves signed transition/audit hash chaining separate from ordinary chat-message event-log entries.

## regression/tests to add first

Add RED tests before production changes:

- In `group_event_log_db_helpers_test.dart`, add a signed transition audit group proving exact duplicate signed transition append is idempotent, conflicting same source event id fails, stale previous transition hash or forked same-previous transition is detected, and privacy-safe violation reasons do not include raw signatures or secrets.
- In `group_message_listener_test.dart`, add `PREREQ-SIGNED-COMMIT-AUDIT` tests for at least `member_added`, `members_added`, `member_removed`, `member_role_updated`, `group_metadata_updated`, `group_dissolved`, and `key_rotated`: missing or tampered audit is rejected before state, timeline, bridge, event-log, stream, or notification side effects; valid signed audit applies; exact duplicate replay remains idempotent.
- Add one offline replay test through `handleReplayEnvelope` or `drain_group_offline_inbox_use_case_test.dart` proving a valid signed transition applies the same as live and a modified replay fails before mutation.
- In `group_key_update_listener_test.dart`, add a direct key-update audit/log proof that the existing verified signature is retained as transition evidence and that changed replay stays blocked before key persistence.
- In `update_group_member_role_use_case_test.dart` and `rotate_and_distribute_group_key_use_case_test.dart`, add sender-side proof that locally authored role/key-rotation transition payloads include signed audit data before publish/replay storage.
- In `go-mknoon/node/pubsub_test.go`, keep or extend the existing invalid-signature event-family proof so outer PubSub signatures remain required. If no Go production change is made, this is still a regression guard.

These tests should fail on the current tree because most current system event fixtures omit a signed transition audit record.

## step-by-step implementation plan

1. Reconfirm dirty state and migration number.

2. Add or adapt a small canonical signed transition audit helper. Prefer a focused application helper over ad hoc JSON in screens. The helper should build canonical payloads, sign with `payload.sign`, verify with `payload.verify`, compute a stable audit hash, and expose privacy-safe diagnostic reasons.

3. Extend event-log helper behavior for transition audits. If no migration is used, parse audit fields from `canonical_payload` and derive latest transition hash from signed transition entries. If a migration is used, add explicit audit columns and indexes, wire migration/version, and update full-chain tests.

4. Preserve and align the existing signed `group_created` event. Do not regress its rollback-on-sign-failure behavior.

5. Add signed audit payloads to local transition senders:

- `create_group_with_members_use_case.dart` and `contact_picker_wired.dart` for `members_added`.
- `broadcast_voluntary_leave_use_case.dart` and the removal path in `group_info_wired.dart` for `member_removed`.
- `update_group_member_role_use_case.dart` or a nearby application helper, plus the current role-change sender in `group_info_wired.dart`, for `member_role_updated`.
- `group_config_payload.dart` and the metadata sender path for `group_metadata_updated`, preserving existing metadata actor signature compatibility.
- `dissolve_group_use_case.dart` for `group_dissolved`.
- `rotate_and_distribute_group_key_use_case.dart` for `key_rotated`.
- `group_key_update_listener.dart` event-log payload for direct `group_key_update`, preserving the existing canonical key-update signature as audit evidence.

6. Verify before apply in `group_message_listener.dart`. For transition families, parse and verify the audit against current sender membership/device binding, transition body, source event id, timestamp, expected previous transition hash, and actor public key before mutation. Reject missing/mismatched audit before calling mutation handlers or append.

7. Make offline replay use the same verification path. Prefer keeping audit inside encrypted plaintext system payloads so `handleReplayEnvelope` and live listener share enforcement. Only change replay envelope metadata if the existing path cannot prove equivalence.

8. Emit privacy-safe diagnostics for audit failures: reason codes such as `missing_signed_audit`, `signature_invalid`, `payload_mismatch`, `previous_transition_hash_mismatch`, `conflicting_replay`, or `fork_detected`, with hashed/truncated group and peer identifiers only.

9. Keep Go PubSub envelope behavior stable unless a required proof fails. If Go changes are needed, keep them to validation diagnostics or explicit envelope parsing for already existing types; a new PubSub message type or protocol version is a plan refresh trigger.

10. Run direct tests as they are added, then full direct files, named gates, and diff hygiene. Only after green evidence should the executor update source-row notes or the breakdown ledger.

Stop early if repo evidence shows a complete signed transition/audit model already exists and tests only need evidence updates. Stop and refresh if implementation requires welcome/key-package, receipt, ban/delete, history repair, or future-epoch repair work to pass these tests.

## risks and edge cases

- Out-of-order signed transitions may be safer to reject with a fork/gap diagnostic than to apply. Do not silently apply a transition whose previous audit hash is incompatible with local state.
- Exact duplicate replay must remain idempotent, including live plus inbox duplicate delivery.
- Current system-event test fixtures are likely unsigned and will need targeted fixture updates. Do not weaken the production validator only to keep old unsigned fixtures passing.
- Role and metadata sender code currently lives partly in presentation wired classes. Any touched UI file should only delegate signed transition construction to an application helper, not absorb new business logic.
- Signing failures for local transitions must fail before publishing unsigned transition payloads. For mutations already applied locally before broadcast, the implementation must either sign before mutation or roll back safely on signing failure.
- Event-log diagnostics must not leak raw signatures, private keys, group keys, ciphertext, nonce, plaintext message bodies, raw group ids, or raw peer addresses.
- Device identity from `PREREQ-DEVICE-IDENTITY` should be included in signed audit payloads when present; do not fall back to unbound sender identity for new signed transitions.

## exact tests and gates to run

Direct RED/green commands:

```bash
flutter test --no-pub test/core/database/helpers/group_event_log_db_helpers_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'
flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'
cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies|TestPREREQSignedCommitAudit' -v
```

Full impacted direct files:

```bash
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart
flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart
```

Conditional direct files when touched:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'
```

If a migration is added:

```bash
flutter test --no-pub test/core/database/migrations/<next>_group_event_log_signed_audit_test.dart test/core/database/integration/full_migration_chain_test.dart
```

Named and hygiene gates:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Device/relay profile:

- This session is host-only by default.
- Do not require `group-real-network-nightly` unless implementation changes real wire/protocol behavior, bridge event routing, or a host/fake-network result exposes a real-device-only uncertainty.
- If a supporting real-network run becomes necessary, use `FLUTTER_DEVICE_ID` plus `MKNOON_RELAY_ADDRESSES` and run `./scripts/run_test_gates.sh group-real-network-nightly`; absence of those env vars is a supporting-fixture blocker, not a blocker for host implementation.

## known-failure interpretation

- The broad ad hoc `flutter test --no-pub test/features/groups/application` command has previously failed an unrelated MD-011 drain-inbox media replay test in isolation. Do not classify that known isolated MD-011 failure as a regression if the direct files and named `groups` gate listed above pass.
- Existing dirty files are not failures by themselves. Treat only new failures in touched files or plan-listed gates as blockers.
- If `go test ./node` fails outside the named regex and the focused regex passes, record it separately and do not block this session unless the failing package or test is touched by this work.

## done criteria

- The plan-listed RED tests fail before production changes or are explicitly shown already covered by current code.
- Signed transition audit generation and verification exist for all required shipped transition families.
- Missing/tampered/mismatched/stale/forked audit payloads reject before mutation, key promotion, event-log append, bridge update, listener stream, or notification side effects.
- Live and offline replay paths share the same verification behavior for signed transition families.
- Event-log replay, fork/gap, and tamper diagnostics are privacy-safe.
- Direct files, required Go regex, named `groups`, `completeness-check`, and `git diff --check` pass, with migration/full-chain tests included if schema changes.
- Source matrix, inventory, and breakdown updates, if performed after implementation, do not overclaim EK-004, EK-012, or DB-012 closure beyond the evidence.

## scope guard

Do not implement:

- welcome/key-package lifecycle, key-package replay/freshness/tombstones, weak package validation, wrong-recipient welcome repair, or package admission UI.
- future-epoch pending queue, key repair trigger, live decryption placeholder lifecycle, or post-repair retry flow.
- group receipts, read/delivery cursor tables, receipt transaction boundaries, remote message delete, ban/unban, history gap repair, or multi-peer repair.
- MLS commit protocol, multi-branch conflict resolution, account recovery, device compromise recovery, safety-number UI, or trust center UI.
- real relay/device proof as a substitute for host tests.

Overengineering signals:

- A new PubSub protocol version or envelope type when encrypted system-payload audit data is enough.
- New product UX or new remote event families just to satisfy DB-012.
- A generalized ledger framework outside group transition audit needs.
- A migration solely for convenience if existing canonical payload data can prove the contract cleanly.

## accepted differences / intentionally out of scope

- The current architecture can close this prerequisite with a signed transition audit model instead of full MLS-style commits if it proves actor signature, previous-state binding, next-state binding, replay/fork protection, and diagnostics for shipped transition families.
- First-class key-package replay remains separate even if direct `group_key_update` is brought under signed audit proof.
- Bans, remote deletes, and receipts remain absent product surfaces and must not be invented here.
- Go PubSub can remain the outer encrypted-envelope validator while Dart verifies the inner transition audit after decryption. That is acceptable if live and offline replay tests prove equivalent fail-closed behavior before state mutation.

## dependency impact

- EK-004 depends on this plan for signed audit/commit-transition and offline replay signature-equivalence blockers. It still also depends on any future-epoch replay-equivalence gaps owned by `PREREQ-FUTURE-EPOCH-KEY-REPAIR`.
- EK-012 depends on this plan for signed commit/transition replay protection, transition event log, and transition diagnostics. It still depends on `PREREQ-WELCOME-KEY-PACKAGE` for key-package replay/freshness/tombstones and may depend on remote event family decisions for all-surface diagnostics.
- DB-012 depends on this plan only for commit-transition apply/idempotency. Bans, remote message deletes, receipts, key-package transitions, and all-family matrix closure remain separate.
- ER-001-style privacy-safe diagnostics may cite this work later if invalid signed audit diagnostics are implemented, but this session should not reopen ER-001 unless a concrete regression appears.

## reviewer pass

Reviewer status: sufficient with adjustments applied.

Findings:

- Missing direct receive-side mention for `member_added`: fixed by adding it to the required listener regression set.
- Presentation sender hooks were named as possible production touch points without matching conditional presentation tests: fixed by adding conditional `contact_picker_wired_test.dart` and `group_info_wired_test.dart` direct commands.
- No stale assumptions found in the source rows or inventory entries. The plan correctly treats EK-004, EK-012, and DB-012 as Partial until concrete code/test evidence proves their named blockers.
- No overengineering finding after the plan explicitly prefers encrypted system-payload audit data and treats a new Go protocol version as a plan refresh trigger.
- Migration stop rule is sufficient: current version is `62`, no schema is preferred, and any need for `063` must be revalidated against dirty worktree state before coding.

Minimum needed for sufficiency: already patched above.

## arbiter pass

Arbiter status: pass.

Structural blockers:

- None.

Incremental details intentionally deferred:

- Executor may choose exact helper/file names for the signed audit helper.
- Executor may decide whether audit data stays inside `canonical_payload` or needs a new `063` migration, but must obey the migration stop condition before touching schema.
- Executor may add more focused direct tests if the chosen implementation touches additional sender fixtures.

Accepted differences:

- A signed transition audit model is acceptable instead of full MLS-style commits for this prerequisite, as long as actor signature, previous/next state binding, replay/fork protection, and live/offline equivalence are proven.
- Go PubSub may remain the outer encrypted-envelope validator. Dart can verify the inner signed transition audit after decrypting the system payload.
- EK-012 and DB-012 can remain Partial after this session if key-package, ban/delete, receipt, or all-family matrix blockers remain.

Final verdict: execution-ready.

## Executor Verdict

Verdict: executor-completed; QA pending.

Implementation summary:

- Added `signed_group_transition_audit.dart` with canonical signed audit generation, verification, hashing, and transition state/output binding.
- Added signed audit payloads to shipped system transition senders for `members_added`, `member_removed`, `member_role_updated`, `group_metadata_updated`, `group_dissolved`, and `key_rotated`.
- Added receive-side signed-audit rejection/idempotency for shipped system transition families. Fix pass made direct `group_key_update` signed audit mandatory on the append-wired production path, added sender-side direct audit generation before encryption, and kept legacy direct key-update compatibility only where event-log append is not wired.
- Direct key-update event-log payloads now store privacy-safe hash/audit evidence (`encryptedKeyHash`, key-update signature hashes, and signed-audit identifiers), not raw `encryptedKey` material.
- Narrowed event-log replay diagnostics to privacy-safe `conflicting_replay` source hashes.
- No schema migration was added; `lib/main.dart` stayed at database version `62`.

Tests and gates:

- RED evidence was captured before implementation: DB helper conflict diagnostic failed on legacy wording, and focused Flutter PREREQ tests failed to compile without the signed audit helper.
- Focused PREREQ commands passed: DB helper (`+5`), group message listener (`+2`), group key-update listener (`+1`), role helper (`+1`), key rotation (`+1`), contact picker presentation (`+1`), and group info presentation (`+1`).
- Full impacted direct Flutter files passed: create group/create-with-members (`+31`), group message listener (`+87`), group key-update listener (`+25`), role update (`+12`), and rotate/distribute key (`+18`).
- Go regex passed: `TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies` (`1` test, `10` subtests).
- Named gates passed: `./scripts/run_test_gates.sh groups` (`+101`), `./scripts/run_test_gates.sh completeness-check` (`700/700`), and `git diff --check`.
- Fix-pass required commands passed after the QA blocker: rotate PREREQ (`+2`), listener PREREQ (`+2`), full listener (`+26`), full rotation (`+18`), `./scripts/run_test_gates.sh groups` (`+101`), `./scripts/run_test_gates.sh completeness-check` (`700/700`), and pre-doc plus post-doc `git diff --check`.

Rows and docs:

- No source matrix row moved to `Covered`.
- EK-004 remains `Partial`; signed audit/transition evidence is narrowed, but complete all-family offline replay signature equivalence is still not proven.
- EK-012 remains `Partial`; shipped transition replay protection is narrowed, but key-package replay/freshness/tombstones, future/missing-key replay repair, and cross-surface diagnostics remain open.
- DB-012 remains `Partial`; shipped system-transition idempotency is narrowed, but bans, remote deletes, receipts, key-package transitions, and the all-family idempotency matrix remain open.
- Updated source matrix, test inventory, breakdown, and this plan after green evidence only.

## Final QA Verdict

Verdict: accepted; QA passed.

Blocking findings: none.

Final QA reran:

- `flutter test --no-pub test/core/database/helpers/group_event_log_db_helpers_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'` passed (`+8`).
- `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart --plain-name 'PREREQ-SIGNED-COMMIT-AUDIT'` passed (`+2`).
- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies|TestPREREQSignedCommitAudit' -v` passed (`TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies`, 10 subtests).
- `./scripts/run_test_gates.sh groups` passed (`+101`).
- `./scripts/run_test_gates.sh completeness-check` passed (`700/700`).
- `git diff --check` passed.

Source row decisions: accept this prerequisite only. EK-004, EK-012, and DB-012 remain `Partial`; no source row moved to `Covered`.
