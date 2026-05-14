# GM-027 Unknown Peer ID Cannot Be Added As Ghost Member Plan

Status: accepted_with_explicit_follow_up - ready for closure audit

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-11 16:15:57 CEST | Evidence Collector started | `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` GM-027 row; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` GM-027 row and nearby GM-024/GM-025 recovery context; `git status --short` | GM-027 is the single active planning session; source row is Open, breakdown row 43 is implementation-ready / needs_code_and_tests. Existing dirty worktree confirmed and must be guarded. | Collect concrete code/test evidence from the likely GM-027 surfaces before drafting the implementation plan. |
| 2026-05-11 16:19:03 CEST | Evidence Collector completed / Planner started | `add_group_member_use_case.dart`; `remove_group_member_use_case.dart`; `group_message_listener.dart`; `group_key_update_listener.dart`; `group_config_payload.dart`; `group_member.dart`; `send_group_message_use_case.dart`; `rotate_and_distribute_group_key_use_case.dart`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/group.go`; `go-mknoon/node/group_inbox.go`; direct Flutter/Go tests; `Test-Flight-Improv/test-gate-definitions.md` | Current code can persist non-empty members with no deliverable device/key identity; Go discovery falls back to `member.PeerId` for device-less members, and send fallback recipient lists include any non-empty peer ID. No row-owned GM-027 regression exists yet. | Draft a narrow implementation-ready plan with rejection at add/listener boundaries plus defensive Go filtering and direct regressions. |
| 2026-05-11 16:21:22 CEST | Planner completed / Reviewer started | No new files; synthesized evidence into this GM-027 draft. | Draft is code-and-tests, not docs-only. It adds `send_group_message_use_case.dart` because durable recipients are part of GM-027's expected behavior. | Review for missing tests/gates, stale assumptions, excessive validation scope, and whether the row can close without a simulator proof. |
| 2026-05-11 16:21:59 CEST | Reviewer completed / Arbiter started | This GM-027 plan draft only. | Sufficient with adjustments: require direct send-use-case regression for recipient filtering, make listener regression explicit, and add targeted analyzer. No structural blocker remains after patch. | Arbitrate adjusted plan for structural blockers, incremental details, and accepted differences. |
| 2026-05-11 16:22:35 CEST | Arbiter completed | This GM-027 plan after reviewer adjustments. | No structural blockers remain. Incremental details are deferred to execution: exact helper placement and whether Go inbox needs an extra guard. The plan is execution-ready for GM-027 only. | Hand off to implementation without writing source-matrix closure or a final program verdict. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-11 16:24:40 CEST | Controller contract extraction | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-027-plan.md`; `git status --short`; `codex exec --help` | GM-027 is execution-ready with required RED regressions, Flutter/Go production fixes, focused tests, adjacent gates, and dirty-state guard. `codex exec` is available for spawned Executor/QA isolation with `gpt-5.5` and `model_reasoning_effort=xhigh`. | Spawn isolated Executor for GM-027 only. |
| 2026-05-11 16:28:12 CEST | Executor contract and dirty-state guard | This plan file; `git status --short`; owner-file diffs for Flutter application/tests and `go-mknoon/node/pubsub.go` / `pubsub_test.go` | Worktree was already dirty from prior accepted sessions, including several owner files. Executor preserved unrelated dirty state and scoped GM-027 edits to row-owned files plus one remove-overlap fixture repair proved by an adjacent test failure. | Add exact GM-027 RED regressions before production changes. |
| 2026-05-11 16:33:44 CEST | RED regressions | `add_group_member_use_case_test.dart`; `group_message_listener_test.dart`; `send_group_message_use_case_test.dart`; `group_membership_smoke_test.dart`; `go-mknoon/node/pubsub_test.go` | Exact GM-027 selectors failed before the fix as expected: invalid add saved/synced, inbound invalid member persisted, durable recipients included the ghost, smoke add succeeded, and Go counted the malformed device-less target. | Implement narrow Flutter validation/filtering and Go target filtering. |
| 2026-05-11 16:38:51 CEST | Production implementation | `group_config_payload.dart`; `add_group_member_use_case.dart`; `group_message_listener.dart`; `send_group_message_use_case.dart`; `go-mknoon/node/pubsub.go` | Added shared Flutter deliverable-identity filtering without strict libp2p decode; rejected invalid local adds before save/config sync; skipped invalid inbound membership rows; excluded pre-existing ghosts from durable recipients; added Go `peer.Decode` filtering for dial/expected targets. | Run focused GM-027 selectors and adjacent suites. |
| 2026-05-11 16:42:08 CEST | Focused GM-027 verification | Required Flutter GM-027 selectors; Go focused selector | Required selectors passed after the fix. One parallel Flutter integration attempt hit native-assets `lipo` startup-lock failure, then the same command passed when rerun sequentially; no GM-027 assertion failure remained. | Run adjacent suites, analyzer, gates, and whitespace check. |
| 2026-05-11 16:43:57 CEST | Adjacent validation and handoff | Adjacent group application/integration suites; targeted analyzer; `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check`; `git diff --check` | All attempted adjacent validations passed. The adjacent removal integration suite exposed a stale fixed-time fixture after send-recipient filtering; repaired the fixture in the remove-overlap test and reran it green. Broad `groups` and `completeness-check` gates passed. | Hand off to QA Reviewer; do not update source matrix, session-breakdown closure rows, or final program verdict. |
| 2026-05-11 16:49:00 CEST | QA Reviewer completed | Read-only review of GM-027 plan evidence, Flutter/Go product diffs, GM-027 regressions, touched overlap fixture, source-matrix/breakdown dirty-state scope, and focused reruns. | QA verdict: `accepted_with_explicit_follow_up`; no blocking findings. QA reran focused Flutter GM-027 selectors in one sequential command and Go `TestGM027|TestGM023|TestFindMember_DuplicatePeerId`; both passed. `git diff --check` passed. | Controller finalization: record final execution verdict in this GM-027 plan only. |
| 2026-05-11 16:50:19 CEST | Controller final verdict | This GM-027 plan file; `/tmp/gm027-executor-final.md`; `/tmp/gm027-qa-final.md`; scoped `git diff --name-only`; process check for stale QA child. | Executor completed, QA output file exists, and no stale nested QA process remains. Source matrix, session-breakdown closure rows, and final program verdict remain intentionally untouched by this execution pass. | Return final response with verdict, files changed, pass/fail evidence, residual risk, and closure readiness. |

## Executor Handoff Summary

Status: ready for QA review. GM-027 was implemented with code-and-test evidence; source matrix closure, session-breakdown closure rows, and final program verdict were intentionally left untouched.

Files changed for this executor pass:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `go-mknoon/node/pubsub.go`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `go-mknoon/node/pubsub_test.go`
- `test/features/groups/application/member_removal_integration_test.dart` only for the adjacent removal fixture repair proved by the direct suite.

Tests added or updated:

- Added GM-027 add-member regression proving an undeliverable unknown target is rejected before local save or `group:updateConfig`.
- Added GM-027 listener regression proving invalid `member_added` and `members_added` payloads do not persist ghosts or sync them into config.
- Added GM-027 send regression proving a pre-existing ghost is excluded from durable `recipientPeerIds` and retry evidence.
- Added GM-027 membership smoke proving invalid add does not inflate recipients or block valid delivery.
- Added Go GM-027 regression proving malformed device-less targets are excluded from expected/dial target counts.
- Updated legacy/fake-member fixtures with deliverable fallback identity where they represented valid members.

Validation evidence:

- RED before production: all exact GM-027 Flutter selectors and the Go focused selector failed for the expected ghost-member/counting reasons.
- PASS: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-027'`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-027'`
- PASS: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-027'`
- PASS after sequential rerun: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-027'`
- PASS: `(cd go-mknoon && go test ./node -run 'TestGM027|TestGM023|TestFindMember_DuplicatePeerId')`
- PASS: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart`
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- PASS: `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`
- PASS after one warning fix: `dart analyze lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_config_payload.dart lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- PASS: `./scripts/run_test_gates.sh groups`
- PASS: `./scripts/run_test_gates.sh completeness-check`
- PASS: `git diff --check`

Accepted residuals / QA notes:

- Flutter validation intentionally treats a non-empty legacy `publicKey` as deliverable to preserve existing fake-peer host tests and legacy fixtures; strict libp2p peer ID syntax remains in Go target selection.
- One parallel Flutter test attempt failed before execution with native-assets `lipo` startup-lock output; the identical integration selector passed when rerun sequentially.
- The shared worktree remains dirty with unrelated prior-session edits and untracked plan docs; this executor did not revert or claim those changes.

## QA Review Summary

Final execution verdict: `accepted_with_explicit_follow_up`.

Blocking findings: none.

QA-reviewed behavior:

- Local add-member now rejects an undeliverable unknown target before repository save or `group:updateConfig`.
- Inbound `member_added` and `members_added` handling skips invalid entries before local save, timeline emission, and normalized config sync.
- Send durable recipient selection excludes pre-existing ghosts from `recipientPeerIds` and persisted retry payloads.
- Go discovery/count paths use strict `peer.Decode` filtering for malformed device-less dial targets.
- GM-024/GM-025 overlap stayed green through adjacent suites and gates.

QA-rerun evidence:

- PASS: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-027'`
- PASS: `(cd go-mknoon && go test ./node -run 'TestGM027|TestGM023|TestFindMember_DuplicatePeerId')`
- PASS: `git diff --check`

Accepted non-blocking follow-up:

- Flutter currently accepts non-empty legacy `publicKey` alone as a deliverable fallback. QA accepted this for GM-027 because the invalid target has no device and no key material, fake peer IDs remain supported in Flutter, and strict peer ID validation is in Go. Future hardening can decide whether public-key-only legacy members should be phased out.

Closure readiness:

- GM-027 is ready for a separate closure/audit pass. This execution pass did not update the source matrix, session-breakdown closure rows, or any final program verdict.

## Evidence Collector Summary

- Source matrix row GM-027 is Open: "Unknown peer ID cannot be added as ghost member"; setup is an invite target that lacks valid peer/device info; expected behavior is rejection or failed marking without expected-peer inflation or reliability blocking.
- Breakdown row 43 classifies GM-027 as `needs_code_and_tests` and `implementation-ready`, with candidate Flutter membership/config/listener files and Go pubsub/inbox files. GM-024 recovery is now superseded by fresh focused evidence, GM-025 remains covered, and GM-027 plus later rows remain open.
- `add_group_member_use_case.dart` saves `newMember` after permission, duplicate, and membership-limit checks; it does not validate that `newMember.peerId`, device bindings, signing key, ML-KEM key, or key-package material are deliverable before `saveMember` and `group:updateConfig`.
- `GroupMember.fromConfigMap` can create a member with an empty or non-deliverable identity; `group_message_listener.dart` saves `member_added` / `members_added` data before applying the authoritative group config snapshot.
- `group_config_payload.dart` trims and deduplicates non-empty peer IDs and devices, but it does not reject a member that has no active device identity and no useful legacy key material.
- `send_group_message_use_case.dart` builds durable `recipientPeerIds` from every non-empty member peer ID except the sender, so a persisted ghost row can inflate relay inbox recipient lists.
- `go-mknoon/node/pubsub.go` normalizes config members, then `activeGroupMemberDialTargets` uses active device `TransportPeerId` when present but falls back to `member.PeerId` for members without devices; `expectedConnectedGroupMembers` and `countRemoteGroupMembers` then count those targets.
- `go-mknoon/node/group_inbox.go` serializes `recipientPeerIds` exactly as supplied; it should not be the primary filter unless implementation proves invalid recipients can still reach Go after Flutter send-path filtering.
- `group_key_update_listener.dart` already rejects key updates that are not bound to the local recipient device; `rotate_and_distribute_group_key_use_case.dart` distributes only to active devices with ML-KEM material or legacy fallback material. These are overlap guards, not the first fix point.
- Direct tests exist for add-member success, duplicate add, GM-022/GM-023 config normalization, GM-023 Go active-device target selection, durable recipients, and group onboarding, but no exact GM-027 regression currently proves that an invalid unknown peer cannot become a ghost member.
- `Test-Flight-Improv/test-gate-definitions.md` defines `./scripts/run_test_gates.sh groups` as the named gate for group send, receive, retry, resume, invite, and announcement behavior; `scripts/run_test_gates.sh` is the execution source of truth if it disagrees with the doc.
- Dirty-state evidence: the worktree already contains many modified product/test files and untracked prior plan docs. GM-027 execution must inspect owner-file diffs before editing and must not revert unrelated changes.

## real scope

Own exactly source row GM-027: prevent an unknown or invalid invite target with no valid peer/device identity from becoming a counted group member, discovery target, durable recipient, or reliability blocker.

In scope:

- Reject undeliverable group member identities on the local add-member path before repository save or bridge config sync.
- Reject or ignore invalid `member_added` / `members_added` payload entries before they create local ghost rows from inbound system messages.
- Defensively filter malformed Go dial targets so older or externally supplied configs cannot inflate expected peer counts.
- Add row-owned host and Go regressions that prove the invalid target is absent from local members, config snapshots, durable recipient lists, and Go expected/dial counts.

Out of scope:

- Source matrix or breakdown closure edits in this planning pass.
- Product UI redesign, contact-picker behavior, broad invite-status UX, relay persistence changes, or new member status models.
- Closing GM-028's empty-peer-ID row, even if a shared helper naturally rejects empty input too.

## closure bar

GM-027 is good enough when a target lacking valid peer/device delivery identity is rejected before it can become an active group member, and any malformed config entry that still reaches Go is excluded from discovery targets and expected peer counts.

Closure requires concrete evidence that:

- `addGroupMember` fails the invalid target without saving it and without calling `group:updateConfig`.
- Inbound `member_added` / `members_added` processing does not persist an invalid target or sync it into Go config.
- Sending after the failed add remains reliable for valid members and the durable `recipientPeerIds` list contains only valid recipients.
- Go `countRemoteGroupMembers` / `expectedConnectedGroupMembers` ignore malformed device-less targets and do not attempt to dial them.
- The source matrix row is not marked `Covered` until the execution/closure pass records exact code, test, and gate evidence for GM-027.

## source of truth

1. Current code and tests win over stale prose.
2. Source matrix row GM-027 defines the user-visible behavior and P0 acceptance target.
3. Breakdown row 43 defines the active session classification and candidate files/tests.
4. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gates; the script wins on disagreement.
5. Prior GM-024 and GM-025 closure evidence is authoritative only for dependency order and overlap risks; it does not close GM-027.
6. GM-028 remains a separate source row for empty `PeerId`; do not use GM-027 closure wording to claim GM-028.

## session classification

`implementation-ready`

GM-027 is not docs-only or evidence-only. The current code has an implementation gap: there is no row-owned validation that prevents a non-empty but undeliverable member from being saved, synced, counted, or included in durable recipients.

## exact problem statement

Private group membership currently assumes that a non-empty `peerId` is enough to create or carry a member row in several paths. When an invite target has no valid peer/device information, the Flutter add/listener paths can still save a ghost member, the send path can include that peer ID in durable inbox recipients, and Go discovery can count a device-less member's `PeerId` as a dial target.

The user-visible risk is a group that looks like it has an extra member, waits for or dials an unreachable target, reports misleading expected peer counts, or marks valid sends as unreliable because a ghost recipient can never join. Valid existing A/B/C membership, re-add, permission, key rotation, and durable offline behavior must remain unchanged.

## files and repos to inspect next

Production files likely owned by GM-027:

- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `go-mknoon/node/pubsub.go`

Production files to inspect as overlap guards, but edit only if a focused regression proves they are still part of the ghost path:

- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/group.go`

Direct tests likely owned by GM-027:

- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `go-mknoon/node/pubsub_test.go`

Adjacent tests to run without broadening implementation scope:

- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/application/remove_group_member_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `go-mknoon/node/group_inbox_test.go` if `group_inbox.go` is touched

## existing tests covering this area

- `add_group_member_use_case_test.dart` covers successful add, duplicate add rejection, membership limit, bridge rollback, permission checks, and GM-022/GM-023 config normalization; it does not reject a device-less unknown member today.
- `group_message_listener_test.dart` has listener-level membership/config coverage, including duplicate `member_added` / `members_added` behavior from earlier rows, but no exact invalid-member rejection proof was found.
- `group_membership_smoke_test.dart` covers durable recipients, removals, re-adds, active shadow handling, GM-024 display/state recovery, and GM-025 role/permission re-add. GM-027 needs a focused selector that proves a failed invalid add does not contaminate recipients or delivery.
- `go-mknoon/node/pubsub_test.go` covers GM-023 active-device discovery and expected counts for inactive shadows; it does not yet prove malformed device-less members are not dial targets.
- `group_inbox_test.go` proves `recipientPeerIds` are marshaled and preserved as supplied. It is useful as an overlap guard if Go inbox filtering is introduced, but upstream filtering is the smaller first plan.

## regression/tests to add first

Add the row-owned RED regressions before production fixes:

1. `add_group_member_use_case_test.dart`: `GM-027 rejects unknown member without deliverable peer/device identity before save or config sync`.
   - Arrange an admin and a candidate with a non-empty unknown peer ID but no active device, no signing key, no ML-KEM/key-package material, and no valid legacy identity.
   - Expect `addGroupMember` to throw a clear `StateError` or typed validation error.
   - Assert `groupRepo.getMember(groupId, invalidPeerId)` is null and `bridge.commandLog` does not contain `group:updateConfig`.

2. `group_message_listener_test.dart`: `GM-027 ignores invalid member_added/members_added payload without creating a ghost`.
   - Inject a signed/accepted membership system payload whose added member lacks deliverable identity.
   - Assert the invalid member is not saved, no invalid timeline member is surfaced as an active add, and the synced config excludes it.

3. `send_group_message_use_case_test.dart`: `GM-027 pre-existing ghost member is excluded from durable recipients`.
   - Seed a valid sender, valid Bob, and a pre-existing invalid ghost row to simulate older local state.
   - Send through the use case and assert the `group:inboxStore` recipient list contains Bob only.

4. `group_membership_smoke_test.dart`: `GM-027 unknown peer add does not inflate recipients or block valid delivery`.
   - Build a valid Alice/Bob group, attempt the invalid add, start listeners/discovery-equivalent fake network, send from Alice, and inspect the `group:inboxStore` payload.
   - Assert recipients are exactly Bob, the invalid peer is absent, Alice's send succeeds, Bob receives exactly once, and no invalid subscription/member row exists.

5. `go-mknoon/node/pubsub_test.go`: `TestGM027InvalidDeviceLessPeerIDDoesNotInflateGroupTargets`.
   - Build a config with self, one valid target, and one malformed unknown device-less member.
   - Assert `countRemoteGroupMembers` and `expectedConnectedGroupMembers` count only the valid target and that known-member dialing does not attempt the malformed target.

## step-by-step implementation plan

1. Dirty-state guard: before editing, run `git status --short` and inspect `git diff --` for each owner file. Preserve all unrelated prior changes; do not revert source matrix, breakdown, or prior session docs.
2. Add the GM-027 RED tests above. Keep selectors exact so failed baselines are attributable to this row, not broad gate noise.
3. Define one narrow "deliverable group member identity" predicate in the smallest shared Flutter surface, preferably `group_config_payload.dart` unless execution proves it belongs on `GroupMember`.
   - A valid current-device member should have a trimmed non-empty member `peerId` plus at least one active device with non-empty `deviceId`, `transportPeerId`, `deviceSigningPublicKey`, and encryption/key-package material sufficient for group onboarding.
   - A legacy fallback member should have a trimmed non-empty `peerId`, non-empty signing `publicKey`, and non-empty `mlKemPublicKey`.
   - Do not use strict libp2p peer-ID decoding in Flutter because many established host/fake tests use stable fake peer IDs; perform strict transport decode only in Go where actual dial targets are used.
4. In `add_group_member_use_case.dart`, reject an invalid `newMember` before `saveMember`, membership-limit mutation, or `callGroupUpdateConfig`. Emit a concise flow event and throw a clear error message that tests can match without exposing full peer IDs.
5. In `group_message_listener.dart`, apply the same validation before saving direct `member_added` / `members_added` members and before applying authoritative snapshot members. Invalid entries should be skipped/rejected consistently so they do not become local rows or bridge config members.
6. In `group_config_payload.dart`, make config normalization exclude non-deliverable member entries or expose a helper that owner paths call before building payloads. Preserve GM-022/GM-023 duplicate and active-device preference semantics.
7. In `send_group_message_use_case.dart`, defensively build `recipientPeerIds` only from deliverable members so a pre-existing ghost row cannot keep polluting durable inbox recipients. This is a cleanup guard, not a replacement for add/listener rejection.
8. In `go-mknoon/node/pubsub.go`, make `activeGroupMemberDialTargets` ignore malformed transport targets: active devices must have decodable `TransportPeerId`; legacy fallback to `member.PeerId` must also be decodable. Keep existing active-device preference and dedup behavior.
9. Touch `go-mknoon/node/group_inbox.go` only if tests show invalid recipients can still arrive at Go after Flutter send filtering; otherwise leave it as an opaque request serializer.
10. Run focused Flutter and Go tests first, then adjacent suites and named gates. If a focused test disproves an assumed owner file, stop and narrow the implementation rather than adding broader member status machinery.
11. Do not update the source matrix or breakdown closure rows during execution unless a later closure/audit task explicitly asks for it.

## risks and edge cases

- Over-validating Flutter peer IDs would break established fake host tests and may conflate GM-027 with transport syntax validation; keep strict libp2p decode in Go target selection.
- Under-validating legacy members would keep device-less ghosts eligible for durable recipients and expected counts. Legacy fallback must require enough signing/encryption material to be deliverable.
- Inbound snapshots from older clients may include malformed members even after local add rejection; listener and Go defensive filtering are both required.
- Existing GM-022/GM-023 duplicate and inactive-shadow behavior must still prefer the active valid entry rather than dropping a valid re-add because an invalid shadow appears first.
- GM-025 authoritative snapshot permission clearing must remain intact if `group_message_listener.dart` or `GroupMember.fromConfigMap` is touched.
- Pre-existing ghost rows in local storage may exist after older builds; send-path filtering prevents reliability blocking even if a cleanup migration is outside this row.
- Dirty worktree edits in owner files may belong to prior accepted sessions; implementation must work with them, not reset them.

## exact tests and gates to run

Focused RED/GREEN tests:

```sh
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-027'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-027'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-027'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-027'
(cd go-mknoon && go test ./node -run 'TestGM027|TestGM023|TestFindMember_DuplicatePeerId')
```

Direct adjacent suites:

```sh
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
```

Named gates and hygiene:

```sh
dart analyze lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_config_payload.dart lib/features/groups/application/send_group_message_use_case.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Conditional commands:

```sh
(cd go-mknoon && go test ./node -run 'GroupInbox|TestBuildGroupInboxStoreRequest')
flutter test --no-pub integration_test/group_real_crypto_onboarding_test.dart
```

Run the Go inbox selector only if `group_inbox.go` changes. Run real-crypto onboarding only if the executor changes real onboarding/key-package behavior or host tests cannot prove the recipient and expected-peer contract.

## known-failure interpretation

- The old GM-025 note that `./scripts/run_test_gates.sh groups` was red due GM-024 is historical after the GM-024 recovery closure. Do not reuse that as a current known failure.
- If broad `groups` fails, first rerun the exact GM-027 selectors and inspect whether the failure touches GM-027 owner files, add/listener validation, send recipients, or Go target counts. Any GM-027-linked failure blocks closure.
- A pre-existing unrelated failure can be treated as residual only if it is reproducible outside the GM-027 diff, has an exact selector/log attribution, and all GM-027 focused tests plus adjacent direct suites pass.
- Dirty uncommitted changes in other rows are not evidence for GM-027 and must not be reverted or claimed.

## done criteria

- Invalid unknown member add is rejected before repo save and before `group:updateConfig`.
- Invalid inbound `member_added` / `members_added` payloads do not create active local members and do not enter the synced group config.
- A valid Alice/Bob send after the failed invalid add succeeds, Bob receives exactly once, and `recipientPeerIds` excludes the invalid peer.
- Go expected/dial target count excludes malformed device-less members while preserving valid active-device targets.
- Focused GM-027 Flutter and Go tests pass, adjacent group membership/add/listener suites pass, `groups`, `completeness-check`, and `git diff --check` pass or have tightly attributed non-GM-027 residuals.
- A later closure pass can update source matrix GM-027 to `Covered` with exact code/test/gate evidence. This planning pass does not write that closure.

## scope guard

Do not:

- Build a new member status or failed-invite state unless execution proves rejection cannot represent this row.
- Add broad contact discovery, user search, UI invite eligibility, or relay-state features.
- Rewrite group membership storage, key rotation, or config schemas beyond the minimal validation/filtering needed for GM-027.
- Claim GM-028 coverage for empty peer IDs or close later malformed-member rows.
- Add simulator harness scenarios unless host and Go tests are insufficient for the specific recipient/count behavior.
- Modify source matrix, breakdown closure ledgers, or final program verdict docs in this plan-only task.

## accepted differences / intentionally out of scope

- Flutter validation should not strictly decode libp2p peer IDs because the repository's host tests intentionally use fake peer IDs; Go transport target filtering is the correct place for actual `peer.Decode` checks.
- `group_inbox.go` remains an opaque serializer unless invalid recipients still reach it after Flutter send filtering.
- `group_key_update_listener.dart` is not expected to change because it already validates source and recipient device binding. It remains an overlap guard.
- Empty `PeerId` rejection may share helper code, but GM-028 remains independently open until its own row has evidence.
- Real-crypto onboarding is optional, not a default GM-027 requirement, unless implementation changes key-package onboarding semantics.

## dependency impact

GM-027 blocks the next malformed-member rows from relying on member counts and recipient lists. GM-028 should start only after GM-027 establishes the shared validation/filtering contract, but it must still prove the empty-peer-ID config-install boundary separately. Later group reliability rows should not need to carry ghost-member workarounds once GM-027 is covered.

## Planner Output

Final plan draft: `implementation-ready` with code-and-test scope. The smallest coherent fix is rejection at Flutter add/listener boundaries, shared deliverable-identity filtering for config/send paths, and Go defensive target filtering for malformed transport identities.

## Reviewer Output

- Sufficiency: sufficient with the adjustments now patched into the plan.
- Missing files/tests/gates found during review: `send_group_message_use_case_test.dart` was missing even though `send_group_message_use_case.dart` owns durable recipient filtering; targeted analyzer was also missing.
- Stale or incorrect assumptions: no current GM-024 gate failure can be treated as known residual; the plan now says the old GM-025 groups-gate note is historical only.
- Overengineering check: a new failed-member status model, strict Flutter libp2p decoding, UI invite eligibility, and simulator harness work remain out of scope unless focused tests prove they are necessary.
- Decomposition: the implementation steps are narrow enough for execution: add RED tests, implement a shared deliverable-identity predicate, apply it to add/listener/config/send paths, and add Go target filtering.
- Minimum needed: no further structural changes before arbitration.

## Arbiter Output

- Structural blockers: none.
- Incremental details: exact helper location may move between `group_config_payload.dart` and `group_member.dart`; Go inbox filtering remains conditional on focused evidence.
- Accepted differences: Flutter does not strictly decode libp2p peer IDs; GM-028 remains open; real-crypto onboarding remains conditional.
- Stop rule: no structural blocker was found after the reviewer adjustments, so planning stops here.

## Final Planning Output

Final verdict: execution-ready for exactly one session, GM-027.

Final plan: implement row-owned code and tests so unknown/non-deliverable invite targets are rejected before local save/config sync, invalid inbound membership payloads cannot create ghost members, durable recipient lists ignore pre-existing ghosts, and Go expected/dial counts ignore malformed device-less targets.

Structural blockers remaining: none.

Incremental details intentionally deferred: exact shared-helper placement; whether `go-mknoon/node/group_inbox.go` needs direct recipient filtering; whether real-crypto onboarding is needed after host proof.

Accepted differences intentionally left unchanged: no failed-member status model, no Flutter libp2p peer-ID decoding, no simulator harness by default, no GM-028 closure, and no source matrix/breakdown closure edits in this planning pass.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/group_inbox.go`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `git status --short`

Why the plan is safe to implement now: the plan has a narrow closure bar, direct RED tests, exact owner files, named gates, a dirty-state guard, and explicit non-goals. It treats repo-owned blockers as GM-027 work and leaves only conditional details to execution.
