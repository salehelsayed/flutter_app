# GL-013 UpdateGroupKey(nil) Missing-Key Behavior Plan

Status: execution-ready

## Planning Progress

- 2026-05-10T06:26:00+02:00 | current role: Arbiter completed | files inspected since last update: reviewer findings and full GL-013 plan | decision/blocker: no structural blockers remain; plan is execution-ready for a later implementation session | next action: stop planning and report the compact final verdict.
- 2026-05-10T06:25:00+02:00 | current role: Reviewer completed / Arbiter started | files inspected since last update: full GL-013 draft plan | decision/blocker: plan is sufficient as-is; no structural blocker found; only incremental cautions about keeping the validator-bypass test narrow and Dart checks non-production | next action: arbitrate findings, classify deferred details/accepted differences, and finalize readiness if no structural blocker remains.
- 2026-05-10T06:23:00+02:00 | current role: Reviewer started | files inspected since last update: GL-013 draft plan | decision/blocker: review will test sufficiency of the RED regression, diagnostic shape, gate contract, and scope guard | next action: classify missing files/tests/gates, stale assumptions, overengineering, and minimum adjustments.
- 2026-05-10T06:22:00+02:00 | current role: Planner completed | files inspected since last update: no new files; draft synthesized from evidence | decision/blocker: smallest coherent GL-013 plan is Go-only: prove key deletion/send disablement, prove validator missing-key diagnostics, then fix subscription-side missing-key silent drop if the RED test confirms it | next action: run Reviewer against scope, tests, gates, and stale assumptions.
- 2026-05-10T06:20:00+02:00 | current role: Planner started | files inspected since last update: no new files; planning from collected GL-013 evidence | decision/blocker: draft will stay Go-only unless reviewer finds a missing app/bridge contract | next action: write mandatory plan sections with direct regressions, exact code seams, gates, and scope guard.

## Execution Progress

- 2026-05-10T06:37:50+02:00 | phase: final execution verdict | files inspected or touched: GL-013 plan | command: none | decision/blocker: accepted; QA Reviewer handoff has no blocking findings and all plan-required gates are recorded PASS | next action: stop; closure docs/source matrix/breakdown remain for closure phase.
- 2026-05-10T06:36:53+02:00 | phase: QA Reviewer completed | files inspected or touched: GL-013 plan, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go` | command: `(cd go-mknoon && go test ./node -run '^TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator$|^TestGL013HandleGroupSubscriptionEmitsDecryptionFailedAfterKeyRemoval$' -count=1)` PASS; `(cd go-mknoon && go test -race ./node -run '^TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator$|^TestGL013HandleGroupSubscriptionEmitsDecryptionFailedAfterKeyRemoval$' -count=1)` PASS; `git diff --check` PASS | decision/blocker: no blocking GL-013 QA findings; Executor-recorded adjacent/row/Flutter/groups gate evidence satisfies required gate contract | next action: report QA verdict ready_for_acceptance.
- 2026-05-10T06:34:21+02:00 | phase: QA Reviewer spawned/running | files inspected or touched: GL-013 plan and Executor handoff evidence | command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app --sandbox danger-full-access` | decision/blocker: Executor completed with code/test/doc delta and required gate evidence; spawn isolated QA Reviewer for sufficiency review | next action: wait bounded interval, then inspect QA result and plan heartbeat.
- 2026-05-10T06:33:15+02:00 | phase: Executor completed | files inspected or touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, GL-013 plan | command: `git status --short`; `git diff --stat`; `git diff -- go-mknoon/node/pubsub.go go-mknoon/node/pubsub_key_rotation_grace_test.go go-mknoon/node/pubsub_decryption_failure_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-013-plan.md` | decision/blocker: GL-013 implementation and required verification complete; broader dirty worktree remains and was preserved | next action: ready for QA review.
- 2026-05-10T06:33:00+02:00 | phase: diff hygiene passed | files inspected or touched: GL-013 plan | command: `git diff --check` | decision/blocker: PASS | next action: inspect final diff/status and hand off to QA.
- 2026-05-10T06:32:51+02:00 | phase: groups gate passed | files inspected or touched: GL-013 plan | command: `./scripts/run_test_gates.sh groups` | decision/blocker: PASS | next action: run `git diff --check`.
- 2026-05-10T06:32:32+02:00 | phase: Flutter startup smoke passed | files inspected or touched: GL-013 plan | command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` | decision/blocker: PASS | next action: run named groups gate.
- 2026-05-10T06:32:13+02:00 | phase: row Go sweep passed | files inspected or touched: GL-013 plan | command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` | decision/blocker: PASS | next action: run required Flutter startup rejoin smoke.
- 2026-05-10T06:31:49+02:00 | phase: adjacent Go sweep passed | files inspected or touched: GL-013 plan | command: `(cd go-mknoon && go test ./node -run 'UpdateGroupKey|HandleGroupSubscription_EmitsDecryptionFailed|HandleGroupSubscription_DecryptsPreviousEpoch|HandleGroupSubscription_DropsPreviousEpoch' -count=1)` | decision/blocker: PASS | next action: run row Go sweep.
- 2026-05-10T06:31:35+02:00 | phase: focused GL-013 race proof passed | files inspected or touched: GL-013 plan | command: `(cd go-mknoon && go test -race ./node -run '^TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator$|^TestGL013HandleGroupSubscriptionEmitsDecryptionFailedAfterKeyRemoval$' -count=1)` | decision/blocker: PASS | next action: run adjacent decrypt/key-rotation sweep.
- 2026-05-10T06:31:25+02:00 | phase: focused GL-013 test passed | files inspected or touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, GL-013 plan | command: `(cd go-mknoon && go test ./node -run '^TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator$|^TestGL013HandleGroupSubscriptionEmitsDecryptionFailedAfterKeyRemoval$' -count=1)` | decision/blocker: PASS after production fix | next action: run focused GL-013 race proof.
- 2026-05-10T06:31:10+02:00 | phase: production fix applied | files inspected or touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, GL-013 plan | command: `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_key_rotation_grace_test.go go-mknoon/node/pubsub_decryption_failure_test.go` | decision/blocker: added nil-key guards in publish/reaction/validator paths and centralized `group:decryption_failed` emission so handler missing-key branch reports `missing group key info` without `localKeyEpoch` | next action: rerun focused GL-013 command and then required gates.
- 2026-05-10T06:30:16+02:00 | phase: focused RED captured | files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, GL-013 plan | command: `(cd go-mknoon && go test ./node -run '^TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator$|^TestGL013HandleGroupSubscriptionEmitsDecryptionFailedAfterKeyRemoval$' -count=1)` | decision/blocker: expected RED isolated to subscription-side missing-key diagnostic; log shows `No key info ... skipping message`, while key-removal send/validator path passed | next action: edit `go-mknoon/node/pubsub.go` missing-key branch and nil key guards.
- 2026-05-10T06:28:40+02:00 | phase: GL-013 regressions added | files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, GL-013 plan | command: `gofmt -w go-mknoon/node/pubsub_key_rotation_grace_test.go go-mknoon/node/pubsub_decryption_failure_test.go` | decision/blocker: added key-removal send/validator regression and subscription accepted-then-key-removed diagnostic regression; no production code edited yet | next action: run focused direct command for expected RED evidence.
- 2026-05-10T06:27:58+02:00 | phase: Executor started / contract re-extracted | files inspected or touched: GL-013 plan, implementation-execution skill, Go libp2p skill, resilience plan, repo map, git status, dirty diffs for `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/pubsub_test.go`, relevant pubsub/test helper code | command: none | decision/blocker: proceed with GL-013 only; preserve existing adjacent dirty changes; first edit will add the two row-owned regressions before production changes | next action: add GL-013 tests and run focused direct command for RED evidence.
- 2026-05-10T06:25:21+02:00 | phase: contract extracted | files inspected or touched: GL-013 plan, git status, Go pubsub diffs, `go-mknoon/node/pubsub.go`, `go-mknoon/node/*_test.go`, `Test-Flight-Improv/test-gate-definitions.md` references | command: none | decision/blocker: execution contract is concrete, Go-only unless tests prove otherwise; required tests/gates captured from plan; dirty worktree contains unrelated and adjacent changes that must be preserved | next action: spawn fresh Executor agent with the bounded GL-013 contract.
- 2026-05-10T06:25:49+02:00 | phase: Executor spawned/running | files inspected or touched: GL-013 plan | command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app --sandbox danger-full-access -a never` | decision/blocker: child materialization available through local Codex CLI; Executor will receive only the bounded GL-013 implementation contract | next action: wait bounded interval, then inspect repo/test evidence.
- 2026-05-10T06:26:26+02:00 | phase: Executor spawn retry | files inspected or touched: GL-013 plan | command: initial `codex exec ... -a never` attempt exited before child materialization with CLI argument error | decision/blocker: invocation issue only, not a child no-progress result; retry with approval policy as a top-level Codex option | next action: spawn corrected Executor command.

## Evidence Collector Notes

- Source matrix row GL-013 is P0/Open and asks for `UpdateGroupKey(G, nil)`, then publish/receive/event inspection. Expected behavior: publish fails as not joined/missing key; inbound emits missing-key/decryption diagnostics; no bogus message appears.
- Breakdown row GL-013 is `needs_code_and_tests`, `implementation-ready`, code changes plus tests. It names `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, Go pubsub tests, `group_startup_rejoin_smoke_test.dart`, and lifecycle recovery tests as likely surfaces, but current evidence does not require Dart/Flutter production edits.
- `go-mknoon/node/pubsub.go::UpdateGroupKey` already handles nil by `delete(n.groupKeys, groupId)` and returns. `GetGroupKeyInfo` therefore returns nil after nil update.
- `PublishGroupMessage` and `PublishGroupReaction` already read `n.groupKeys[groupId]` and fail closed with `group not joined: <groupId>` when the key entry is absent after nil update. They currently guard map absence but not an impossible-through-API present nil key.
- `groupTopicValidator` emits `group:validation_rejected` with `reason: "missing_key"` when the key map entry is absent, so validator-side missing-key diagnostics already exist for topic validation.
- `decryptGroupEnvelopePayload` returns `missing group key info` for nil key info and existing GL-006 test coverage pins that helper behavior, but this does not prove subscription delivery emits a diagnostic after `UpdateGroupKey(nil)`.
- `handleGroupSubscription` parses the envelope and skips self, then if `!keyOk` logs `[PUBSUB] No key info...` and continues without `group:decryption_failed`. That is the concrete GL-013 diagnostic gap.
- Existing `pubsub_decryption_failure_test.go` tests prove wrong-key, tampered nonce, and tampered ciphertext emit `group:decryption_failed` with `groupId`, `senderId`, `keyEpoch`, `localKeyEpoch`, `error`, and no `group_message:received`.
- Flutter diagnostic plumbing already forwards `group:decryption_failed` and `group_pending_key_repair_service.dart` can queue live repair placeholders when `groupId`, `senderId`, and `keyEpoch` are present; `localKeyEpoch` is optional.
- GL-006 nil join tests cover rejecting nil key at join, no group state, publish fails as not joined, pure validator `reject:no_key`, and decrypt helper missing-key error. GL-013 must cover a joined group whose key is later removed.
- Dirty worktree already includes unrelated and adjacent changes in Go, Dart, source matrix, breakdown, and gate docs. Implementation must preserve those changes and touch only GL-013-owned lines/tests.
- GL-014 older epoch and GL-015 same-epoch mismatch have tests present in the current dirty tree (`TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent`, `TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial`), but their matrix rows remain separate and must not be bundled into GL-013.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define `./scripts/run_test_gates.sh groups` for group send/receive/retry/resume behavior, and the breakdown requires `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` for GL rows.

## real scope

Change only the Go group key nil-update behavior and row-owned tests:

- pin that `UpdateGroupKey(groupId, nil)` removes local key material while leaving the joined topic/config repairable;
- pin that local message and reaction publish fail honestly after key removal with empty message id / zero peer count for messages and no topic publish;
- pin that normal inbound validation after key removal emits a missing-key diagnostic and rejects the envelope;
- add the smallest production fix needed so subscription-side delivery that observes the key removed after validation emits `group:decryption_failed` instead of silently logging and dropping;
- preserve existing wrong-key, tampered nonce, tampered ciphertext, payload parse, previous-key grace, older-epoch, and same-epoch behaviors.

Do not change Dart/Flutter production code, bridge request shape, group recovery/rejoin workflow, key distribution, previous-key grace policy, older/same-epoch update semantics, or later remove/re-add privacy rows.

## closure bar

GL-013 is good enough when:

- `GetGroupKeyInfo(groupId)` returns nil after `UpdateGroupKey(groupId, nil)`;
- `PublishGroupMessage` after nil key update returns `("", 0, error)` with an honest not-joined/missing-key style error and no panic;
- `PublishGroupReaction` after nil key update returns an honest not-joined/missing-key style error and no panic;
- the real `groupTopicValidator` rejects an otherwise valid envelope after key removal and emits `group:validation_rejected` with `reason: "missing_key"`;
- if a validated/subscription-delivered envelope is handled after the local key was removed, `handleGroupSubscription` emits `group:decryption_failed` containing at least `groupId`, `senderId`, `keyEpoch`, `error: "missing group key info"`, and `decryptMs`, with `localKeyEpoch` absent or null because no local key exists;
- no `group_message:received` or `group_reaction:received` is emitted for missing-key inbound traffic;
- focused Go, race, row Go sweep, required Flutter smoke, named groups gate, and diff hygiene pass or any unrelated pre-existing failure is classified precisely.

## source of truth

Authoritative, in order:

1. Current Go code/tests in `go-mknoon/node`, especially `pubsub.go`, `pubsub_key_rotation_grace_test.go`, `pubsub_decryption_failure_test.go`, and `pubsub_test.go`.
2. `Test-Flight-Improv/test-gate-definitions.md` plus `scripts/run_test_gates.sh` for named gates; if they disagree, the script wins.
3. Source matrix row GL-013 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
4. Breakdown row GL-013 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

Current code/tests beat stale prose. GL-006 nil join and GL-012 nil config closure evidence remain separate and must not be reopened.

## session classification

`implementation-ready`

## exact problem statement

`UpdateGroupKey(groupId, nil)` currently removes the key map entry, so local publish paths already fail once the key is gone. The uncovered reliability gap is the inbound diagnostic contract: validator-side missing-key rejection exists, but `handleGroupSubscription` has a missing-key branch that only logs and continues. If an envelope reaches the subscription after validation but before/while the local key is removed, the app gets no `group:decryption_failed` diagnostic and therefore no live key-repair signal.

User-visible behavior to improve: a local key removal must disable sends and decrypts honestly, with observable missing-key diagnostics and no bogus rendered message.

Must stay unchanged: nil key at join remains rejected by GL-006, nil config update remains GL-012, older epoch GL-014 and same-epoch mismatch GL-015 stay separate, and valid key rotation / grace-window decrypt behavior is preserved.

## files and repos to inspect next

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/node.go`
- `go-mknoon/bridge/bridge.go` only to confirm no bridge behavior changed
- `lib/core/bridge/go_bridge_client.dart` and `lib/features/groups/application/group_pending_key_repair_service.dart` only if diagnostic field shape changes beyond the existing optional `localKeyEpoch`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

- `TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState` covers nil key at join time and publish after rejected join, not key removal after a successful join.
- `TestGroupTopicValidator_NilKeyRejectsNoKeyAndDecryptReportsMissingKey` covers the pure validator helper and `decryptGroupEnvelopePayload(nil)`, not the real validator event or subscription handler after `UpdateGroupKey(nil)`.
- `TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline` covers valid forward rotation.
- Current dirty-tree tests `TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent` and `TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial` cover GL-014/GL-015-adjacent behavior, but those rows remain separate.
- `TestHandleGroupSubscription_EmitsDecryptionFailedEvent`, `...ForTamperedNonce`, and `...ForTamperedCiphertext` cover decryption diagnostics when a local key exists but decrypt fails.
- `TestHandleGroupSubscription_DecryptsPreviousEpochDuringGrace` and `...DropsPreviousEpochAfterGraceExpires` cover previous-key grace delivery/rejection.

Missing: a GL-013 direct test that starts from joined state, calls `UpdateGroupKey(nil)`, proves key removal disables publish/reaction, proves real validator missing-key diagnostics, and proves subscription-side missing-key handling emits `group:decryption_failed` rather than silently dropping.

## regression/tests to add first

Add tests before production edits:

1. `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator`
   - Start a node with an event collector, join a valid group with key epoch E, and verify `GetGroupKeyInfo` is present.
   - Build an otherwise valid envelope for a configured sender.
   - Call `UpdateGroupKey(groupId, nil)`.
   - Assert `GetGroupKeyInfo(groupId) == nil`.
   - Assert `PublishGroupMessage` returns empty message id, zero peer count, and an error containing `group not joined` or `missing key`.
   - Assert `PublishGroupReaction` returns an error containing `group not joined` or `missing key`.
   - Invoke the real `groupTopicValidator(groupId)` with the valid envelope and sender transport peer; assert `pubsub.ValidationReject`.
   - Assert the collector receives `group:validation_rejected` with `reason: "missing_key"` and the envelope `keyEpoch`.

2. `go-mknoon/node/pubsub_decryption_failure_test.go::TestGL013HandleGroupSubscriptionEmitsDecryptionFailedAfterKeyRemoval`
   - Start two local nodes and join both to the same group/key.
   - Install a collector on the receiver and connect the nodes.
   - Disable only the receiver's topic validator in the test, or otherwise use a narrow existing test seam, so the subscription handler can observe a valid envelope after key removal. Document this as exercising the validator/handler race path, not normal missing-key validation.
   - Call `receiver.UpdateGroupKey(groupId, nil)`.
   - Publish a valid raw group envelope from the sender.
   - Expect `group:decryption_failed` with `groupId`, `senderId`, `keyEpoch`, `error` containing `missing group key info`, and `decryptMs`; `localKeyEpoch` should be absent or null.
   - Assert no `group_message:received` and no `group_reaction:received` event appears.

If test 2 passes before production edits, stop and reclassify the production part as already covered. Expected current result is RED because `handleGroupSubscription` logs `No key info` and continues without emitting a diagnostic.

## step-by-step implementation plan

1. Before editing, inspect current dirty diffs for `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, and `go-mknoon/node/pubsub_test.go`; preserve unrelated GL-006, GL-012, GL-014, GL-015, and user changes.
2. Add the two GL-013 tests above and run the focused direct command. Record RED evidence only for the missing-key subscription diagnostic gap; if send/validator assertions fail, refine the production plan before editing.
3. In `go-mknoon/node/pubsub.go`, treat absent or nil `keyInfo` as missing key consistently in these read paths:
   - `PublishGroupMessage` guard;
   - `PublishGroupReaction` guard;
   - `groupTopicValidator` missing-key branch;
   - `handleGroupSubscription` missing-key branch.
4. Add or inline a small private decryption-failure event builder so the existing decrypt-error path keeps the same event fields while the missing-key path can omit/null `localKeyEpoch` safely. Do not change the event name.
5. In `handleGroupSubscription`, after parsing and self-skip, when `!keyOk || keyInfo == nil`, emit `group:decryption_failed` with `error: "missing group key info"` and continue. Do not emit a received message or reaction.
6. Keep `UpdateGroupKey(nil)` as key deletion; do not convert it into a leave, config deletion, subscription cancel, key epoch mutation, or previous-key rotation.
7. Do not touch `go-mknoon/bridge/bridge.go`, Dart listeners, or Flutter repair services unless tests expose a diagnostic shape incompatibility. The planned event shape uses fields already accepted by the Dart repair path.
8. Run focused Go tests, focused race proof, row Go sweep, required Flutter startup smoke, named groups gate, and `git diff --check`.
9. Stop at GL-013. Do not update GL-014/GL-015 source rows, closure docs, or key-distribution behavior in this implementation session.

## risks and edge cases

- Normal missing-key inbound may be rejected by the validator before subscription delivery; the subscription diagnostic test must explicitly identify that it covers the accepted-then-key-removed race path.
- Emitting both `group:validation_rejected` and `group:decryption_failed` for the same envelope could duplicate repair placeholders. The plan keeps normal validator rejection as validation-only; the decryption event is for messages that actually reach `handleGroupSubscription`.
- A nil map value for `groupKeys[groupId]` should be treated as missing key defensively, even though public APIs should now delete or reject nil key info.
- `localKeyEpoch` must remain present for existing wrong-key decrypt failures and absent/null for no-key failures so Dart can dedupe with its existing optional handling.
- Race safety matters because `UpdateGroupKey(nil)` can happen while pubsub callbacks are active; keep all group key reads under the existing mutex pattern.

## exact tests and gates to run

Focused direct GL-013 tests:

```bash
(cd go-mknoon && go test ./node -run '^TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator$|^TestGL013HandleGroupSubscriptionEmitsDecryptionFailedAfterKeyRemoval$' -count=1)
```

Focused race proof:

```bash
(cd go-mknoon && go test -race ./node -run '^TestGL013UpdateGroupKeyNilRemovesKeyAndDisablesSendAndValidator$|^TestGL013HandleGroupSubscriptionEmitsDecryptionFailedAfterKeyRemoval$' -count=1)
```

Adjacent decrypt/key-rotation regression sweep:

```bash
(cd go-mknoon && go test ./node -run 'UpdateGroupKey|HandleGroupSubscription_EmitsDecryptionFailed|HandleGroupSubscription_DecryptsPreviousEpoch|HandleGroupSubscription_DropsPreviousEpoch' -count=1)
```

Row Go sweep from the breakdown:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
```

Required Flutter smoke from the breakdown:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Named group gate because Go group receive/diagnostic behavior changes:

```bash
./scripts/run_test_gates.sh groups
```

Diff hygiene:

```bash
git diff --check
```

No `completeness-check` is required unless implementation edits gate definitions or adds Dart/Flutter test files.

## known-failure interpretation

- A focused pre-fix RED is expected only for the subscription-side missing-key diagnostic. If publish/reaction or validator missing-key assertions fail, that is a broader GL-013 production gap and must be handled before continuing.
- Any post-fix panic, race detector finding, compile failure, missing diagnostic, duplicate bogus `group_message:received`, or regression in existing wrong-key/tamper/grace tests is blocking.
- Existing unrelated dirty-work failures in broad Flutter gates should be recorded with exact command output and not misclassified as GL-013 unless they involve group send, receive, diagnostic forwarding, or startup rejoin behavior touched here.
- Do not remove tests from `test-gate-definitions.md` or narrow gate membership to make a gate green.

## done criteria

- GL-013 tests exist and include RED evidence for the missing subscription diagnostic gap or document that no production edit was needed.
- `UpdateGroupKey(nil)` key deletion remains intact and `GetGroupKeyInfo` returns nil.
- Local message and reaction publish fail honestly after key deletion.
- Real validator emits missing-key diagnostics and rejects inbound after key deletion.
- Subscription-side missing-key handling emits `group:decryption_failed` and no bogus received message/reaction.
- Existing decryption failure, tamper, previous-key grace, older-epoch, and same-epoch tests still pass.
- Required direct Go, race, row sweep, Flutter smoke, groups gate, and `git diff --check` evidence pass or unrelated failures are classified.
- No Dart/Flutter production code changed unless later evidence proves unavoidable.

## scope guard

Non-goals:

- no GL-014 older-epoch policy changes;
- no GL-015 same-epoch mismatch policy changes;
- no key distribution, pending key repair algorithm, invite, remove/re-add, or backlog entitlement work;
- no conversion of missing key into `LeaveGroupTopic`;
- no config deletion or GL-012 nil-config behavior changes;
- no public bridge API or Dart model shape changes;
- no broad concurrency stress harness for GL-019.

Overengineering would include adding a group state machine, new exported errors, new Flutter repair flows, new key epoch reconciliation policy, or a generalized pubsub subscription test harness when existing local node tests and a narrow validator bypass can exercise the row.

## accepted differences / intentionally out of scope

- GL-013 accepts a local key-disabled state with topic/config/subscription still present. That is distinct from leaving the group and allows later valid key repair through the existing update path.
- Normal missing-key inbound is expected to be validator-rejected with `group:validation_rejected`, not always delivered to subscription as `group:decryption_failed`. The decryption event is required for the race/path where the handler sees an envelope after the key has been removed.
- Flutter live repair behavior is intentionally left unchanged because it already accepts `group:decryption_failed` with optional `localKeyEpoch`.
- GL-014/GL-015 current tests are noted as evidence but not used to close or expand this row.

## dependency impact

- Later GL-014 and GL-015 plans can rely on missing-key nil updates being separated from stale/same-epoch update policy.
- GL-019 concurrent join/leave/update stress should include `UpdateGroupKey(nil)` only after this row lands, without duplicating GL-013's direct diagnostic tests.
- Group remove/re-add and pending-key repair rows depend on missing-key diagnostics being observable but should not reopen the local send-disable contract unless a real regression appears.

## Reviewer Findings

Verdict: sufficient as-is.

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is.
- What files, tests, regressions, or gates are missing? No structural omissions. The plan names the production seam, two row-owned Go regressions, focused race proof, adjacent decrypt/key-rotation sweep, row Go sweep, required Flutter startup smoke, groups gate, and diff hygiene.
- What assumptions are stale or incorrect? None found. Current code already deletes keys on nil update and normal validator-side missing-key diagnostics exist; the plan correctly targets the subscription-side silent drop without overclaiming normal delivery semantics.
- What is overengineered? Nothing blocking. The validator-bypass test must stay explicitly scoped to the validator/handler race path and should not become a generalized pubsub harness.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It names exact tests, exact branches, exact non-goals, and a stop rule if the focused RED test unexpectedly passes.
- What is the minimum needed to make the plan sufficient? No required change. During execution, keep Dart/Flutter inspection conditional and do not turn optional diagnostic shape checks into production edits unless a test proves incompatibility.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers: none.

Incremental details intentionally deferred:

- The implementation session may choose whether to inline the decryption-failure event map or add a private helper; either is acceptable if existing wrong-key diagnostics keep their current fields.
- The subscription diagnostic test may unregister the receiver validator or use an existing narrow seam; the implementation must document the test as covering the accepted-then-key-removed race path.

Accepted differences intentionally left unchanged:

- Normal missing-key inbound can be rejected at validation time with `group:validation_rejected` rather than subscription-delivered as `group:decryption_failed`.
- Key-disabled local state is not a leave; topic/config/subscription can remain so later valid key repair can restore behavior.
- GL-014 older epoch, GL-015 same-epoch mismatch, and later remove/re-add key-rotation rows remain separate.

Why this is safe to implement now: the plan has a narrow production seam, regression-first proof, explicit stop rules, exact gates, and a scope guard that prevents drift into Dart/Flutter, bridge APIs, key distribution, or later lifecycle stress rows.
