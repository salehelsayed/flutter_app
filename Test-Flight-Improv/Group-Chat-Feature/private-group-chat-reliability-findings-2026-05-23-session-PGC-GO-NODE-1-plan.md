Status: execution-ready

# Session PGC-GO-NODE-1 Plan

## Planning Progress

- 2026-05-23 23:18:23 CEST - Arbiter completed. Files inspected since last update: final reviewer pass and patched plan. Decision/blocker: no structural blockers remain; plan is execution-ready. Next action: hand off to executor when requested.
- 2026-05-23 23:18:23 CEST - Arbiter started. Files inspected since last update: final reviewer pass. Decision/blocker: classify final reviewer result and stop if no structural blockers remain. Next action: final execution-ready decision.
- 2026-05-23 23:18:23 CEST - Reviewer completed. Files inspected since last update: patched plan scope, implementation steps, test commands, and scope guard. Decision/blocker: sufficient as-is; `node.go`/Node-field expansion is now forbidden and production scope is `pubsub.go`. Next action: final arbiter pass.
- 2026-05-23 23:18:23 CEST - Reviewer started. Files inspected since last update: patched plan after one structural-blocker fix. Decision/blocker: verify no missing files, stale assumptions, weak decomposition, or overengineering remain. Next action: final sufficiency verdict.
- 2026-05-23 23:17:26 CEST - Arbiter completed. Files inspected since last update: reviewer findings and draft plan scope sections. Decision/blocker: one structural blocker classified: `node.go`/Node-field seam allowance conflicts with requested `pubsub.go` production scope. Next action: patch plan once, then run final reviewer and arbiter pass.

## reviewer pass

Sufficiency: sufficient with one required adjustment.

Missing files/tests/gates: the draft has exact direct tests and Go gates. It should remove `go-mknoon/node/node.go` as an implementation-scope escape hatch and keep any optional leave mutex probe inside `go-mknoon/node/pubsub.go` or existing test hooks only.

Stale or incorrect assumptions: the source matrix says PGC-011 is open, but the dirty worktree already contains partial outbound device-binding code and tests. The draft handles that with a regression-first stop condition.

Overengineering risk: allowing a new `Node` field or lifecycle state machine would broaden the requested pubsub-file scope. The plan should permit only narrow two-phase lock splitting and a tiny private hook in `pubsub.go` if a leave cleanup assertion cannot be proven otherwise.

Decomposition: rows PGC-011 and PGC-012 are narrow enough for one Go session as long as no Dart, relay, protocol, or lifecycle rewrite work is added.

Minimum needed for sufficiency: remove `node.go` as a production candidate, forbid new `Node` fields, and constrain any test seam to `pubsub.go`.

## arbiter decision

Structural blockers:

- The draft allowed `go-mknoon/node/node.go` or a new `Node` field as a possible test seam. That conflicts with the requested production scope: PGC-011 and PGC-012 changes in `go-mknoon/node/pubsub.go`.

Incremental details:

- Exact new test names may be adjusted by the executor if equivalent names are clearer, but the command must remain focused on the same PGC-011/PGC-012 behaviors.

Accepted differences:

- The plan intentionally treats existing dirty PGC-011 work as possible current-code evidence rather than assuming the source matrix is fully current.

Arbiter action: patch the structural blocker once, then run one final reviewer pass and one final arbiter pass.

## final reviewer pass

Sufficiency: sufficient as-is.

Missing files/tests/gates: none. The plan names exact production scope, direct regression tests, existing safety tests, package/module Go gates, formatting, and diff hygiene.

Stale or incorrect assumptions: none remaining. The plan explicitly handles the current dirty-worktree PGC-011 partial implementation and still treats PGC-012 as open based on current code.

Overengineering: controlled. New `Node` fields, `node.go` edits, broad lifecycle rewrites, Dart edits, relay edits, and protocol changes are explicitly forbidden.

Minimum needed to implement safely: follow the regression-first order and stop/reclassify if PGC-012 requires a broader lifecycle state machine.

## final arbiter decision

Structural blockers: none.

Incremental details intentionally deferred:

- The executor may choose equivalent PGC-prefixed test names if the same behaviors and commands remain focused.

Accepted differences intentionally left unchanged:

- Existing dirty PGC-011 work is treated as possible current-code evidence instead of being duplicated.
- Forwarded-author validator tests remain supporting evidence, not closure for outbound preflight.

Final verdict: `execution-ready`.

## Execution Progress

- 2026-05-23 23:30:00 CEST - Contract extracted locally because this environment has no sub-agent spawning tool. Files inspected: this plan, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_inbox_test.go`, and `go-mknoon/node/node.go`. Decision/blocker: execution is safe with local sequential fallback; dirty PGC-011 work is present and must be preserved. Next action: add missing focused PGC-011/PGC-012 regressions in `pubsub_test.go`.
- 2026-05-24 00:16:00 CEST - Executor completed scoped implementation. Files touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, and this plan note. Decision/blocker: PGC-011 outbound preflight regressions and PGC-012 mutex narrowing regressions are in place; `JoinGroupTopic`/`LeaveGroupTopic` now avoid holding `n.mu` across pubsub subscribe/cancel/close/unregister work. Next action: final QA summary.
- 2026-05-24 00:16:00 CEST - Required gates recorded. `go test ./node -run 'TestPGC011PublishGroupMessageRejectsInvalidDeviceBeforePublish|TestPGC011SendGroupMessageReliableRejectsInvalidDeviceBeforeInboxStore|TestPGC011PublishGroupReactionRejectsInvalidDeviceBeforePublish|TestPGC012JoinGroupTopicSubscribeHookRunsOutsideNodeMutex|TestPGC012LeaveGroupTopicCleanupRunsOutsideNodeMutex'` passed. Focused safety command for device-binding, forwarded-author, reliable-send, and join/leave tests passed. `go test ./node` and `go test ./...` failed on unrelated `TestGroupInboxRetrieveCursor_DefaultsLimitWhenZero` in `go-mknoon/node/group_inbox_test.go:1735`; isolated rerun reproduced `expected error (fake relays unreachable)`. `git diff --check` passed. Final execution verdict: scoped PGC-GO-NODE-1 accepted with unrelated broad-gate failure outside allowed edit scope.

## real scope

Rows in scope:

- `PGC-011`: outbound Go group publish paths must fail before local publish or group-inbox store when the claimed logical author, device id, transport peer id, device signing key, or key package does not match the active member/device binding that inbound validators would accept.
- `PGC-012`: `JoinGroupTopic` and `LeaveGroupTopic` in `go-mknoon/node/pubsub.go` must not hold `n.mu` while running pubsub network operations or hooks: validator register/unregister, topic join, topic subscribe, subscription cancel, topic close.

Files in implementation scope:

- `go-mknoon/node/pubsub.go`
- focused Go tests under `go-mknoon/node`, preferably `pubsub_test.go`; `group_inbox_test.go` is allowed only for a reliable-send no-inbox-store proof if existing helpers make that the smallest test.

Out of scope:

- Dart/Flutter group send, drain, listener, repository, migration, and UI behavior.
- Relay-server recipient ACL work (`PGC-015`).
- Envelope AAD/header protocol migration (`PGC-017`).
- Broad libp2p, rendezvous, discovery, or retry architecture changes beyond the lock-scope split needed for `JoinGroupTopic` and `LeaveGroupTopic`.

## closure bar

The session is good enough when:

- Invalid outbound author/device metadata is rejected synchronously by `PublishGroupMessage`, `SendGroupMessageReliable`, and `PublishGroupReaction` before `topic.Publish` and before `GroupInboxStore`.
- Valid legacy-member sends and valid deviceful sends still publish/sign with the expected member/device metadata.
- `JoinGroupTopic` and `LeaveGroupTopic` copy or remove shared node state under `n.mu`, then run pubsub operations outside `n.mu`.
- Concurrent join/leave/update tests continue to pass without new `register topic validator` races, leaked group maps, or changed duplicate-join semantics.
- Focused Go tests and the exact gates below pass, or any failure is classified as a pre-existing unrelated failure with evidence.

## source of truth

Authoritative order when sources disagree:

1. Current worktree code and direct tests.
2. `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`, rows `PGC-011` and `PGC-012`.
3. `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`, session `PGC-GO-NODE-1`.
4. `Test-Flight-Improv/test-gate-definitions.md` and `Test-Flight-Improv/test-gates-reference.md` for broad gate context.

Current-code caveat: the worktree already has uncommitted `PGC-011`-like changes in `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go`. The executor must inspect and preserve those edits, not overwrite them from a stale matrix assumption.

## session classification

`implementation-ready`

The session can proceed without prerequisites, but it is regression-first. If the current dirty-worktree PGC-011 changes already pass the required focused outbound validation tests, the executor should treat PGC-011 as covered by current worktree state and avoid duplicating it. PGC-012 still requires implementation because current `JoinGroupTopic` and `LeaveGroupTopic` hold `n.mu` across pubsub operations.

## exact problem statement

`PGC-011`: inbound validation rejects forged or stale sender/device envelopes, but outbound APIs can otherwise build, store, or publish an envelope that peers will reject. User-visible impact is a false local success path: a message or reaction can look sent or stored locally while recipients reject it.

`PGC-012`: `JoinGroupTopic` and `LeaveGroupTopic` currently hold the node mutex while calling pubsub register/join/subscribe/cancel/close/unregister. User-visible impact is avoidable lock contention or deadlock under startup/resume/leave/rejoin when pubsub operations or test hooks re-enter node state.

Must stay unchanged:

- Valid legacy-member group messages and reactions.
- Valid deviceful group messages, reliable sends, and reactions.
- Inbound validator semantics for non-member, unbound-device, unauthorized-writer, bad-signature, and forwarded-author handling.
- Existing leave cleanup outcome: group topic/subscription/config/key/cancel state is removed after leave.

## files and repos to inspect next

Production:

- `go-mknoon/node/pubsub.go`

Tests:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/multi_relay_test.go`

Docs to update only after execution closes:

- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-23-session-breakdown.md`

## existing tests covering this area

- `pubsub_test.go` has current dirty-worktree outbound device-binding tests: `TestGroupPublishDeviceBinding_DevicefulMissingExplicitDeviceFailsWhenAmbiguous`, `TestGroupPublishDeviceBinding_DevicefulSingleLocalDeviceDefaultsAndSigns`, `TestGroupPublishDeviceBinding_DevicefulWrongDevicePublicKeyFails`, and `TestGroupReactionDeviceBinding_DevicefulMissingExplicitDeviceFailsWhenAmbiguous`.
- `pubsub_test.go` has forwarded author validator coverage in `TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages`.
- `group_inbox_test.go` has reliable send coverage in `TestSendGroupMessageReliableStoresExactEnvelopeForActiveRecipients` and `TestSendGroupMessageReliableReturnsLiveOnlyWhenInboxStoreFails`.
- `pubsub_unsubscribe_exit_paths_test.go` covers leave cleanup/delivery behavior in `TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit`, `TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub`, and `TestGO010JoinLeaveRecoveryCyclesDoNotLeakGroupGoroutines`.
- `pubsub_test.go` covers duplicate join and concurrent join/leave/update behavior, including `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree`, `TestJoinGroupTopic_RejectsDoubleJoin`, and `TestJoinGroupTopic_DuplicateJoinPreservesExistingState`.

Missing coverage:

- A PGC-011 reliable-send failure test proving invalid device metadata returns before `GroupInboxStore`.
- A PGC-011 reaction failure test for wrong explicit device public key or revoked/missing device, not only ambiguous local device.
- A PGC-012 join test proving subscribe hook code can observe/acquire `n.mu` while subscribe runs.
- A PGC-012 leave test proving cancel/close/unregister work does not run under `n.mu`, plus a concurrent rejoin guard that avoids stale validator races.

## regression/tests to add first

Add these tests before production changes unless the current dirty worktree already contains equivalent tests:

- `TestPGC011PublishGroupMessageRejectsInvalidDeviceBeforePublish`: configure a deviceful member, pass mismatched `senderDevicePublicKey` or `senderTransportPeerId`, and assert `PublishGroupMessage` returns the sender-device error without emitting publish debug or delivering to a peer.
- `TestPGC011SendGroupMessageReliableRejectsInvalidDeviceBeforeInboxStore`: configure a fake relay inbox handler and at least one recipient, pass invalid sender device metadata to `SendGroupMessageReliable`, assert an error and assert no inbox request is observed.
- `TestPGC011PublishGroupReactionRejectsInvalidDeviceBeforePublish`: configure a deviceful member and pass wrong explicit device public key or revoked device metadata to `PublishGroupReaction`, asserting a sender-device error.
- `TestPGC012JoinGroupTopicSubscribeHookRunsOutsideNodeMutex`: use `joinGroupTopicSubscribeHook` to attempt a timed `n.mu.RLock` before calling `topic.Subscribe`; pre-fix it should fail because join holds `n.mu`, post-fix it should pass.
- `TestPGC012LeaveGroupTopicCleanupRunsOutsideNodeMutex`: use existing hooks where possible. If a seam is unavoidable, keep it private and package-local inside `go-mknoon/node/pubsub.go`; do not add a `Node` field or edit `node.go`. Assert cleanup can acquire `n.mu` while cancel/close/unregister work runs, or prove the same behavior with a focused concurrent leave/rejoin/update test.

These regressions prove the actual seams: outbound false success before publish/store, and mutex release around pubsub operations.

## step-by-step implementation plan

1. Re-read current dirty diffs for `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go`. Do not reset or replace them. If another agent has already implemented PGC-011, keep that code and only add missing focused tests.
2. Add the PGC-011 regressions first. If existing tests already cover one branch, rename nothing unless needed; add only the missing reliable-send no-inbox-store and reaction wrong-device cases.
3. For PGC-011 production, ensure all three outbound paths call the same binding/preflight before encryption/signing and before any publish/store:
   - `PublishGroupMessage`
   - `SendGroupMessageReliable`
   - `PublishGroupReaction`
4. Keep the preflight aligned with inbound `activeMemberDeviceForEnvelope`: active device only, matching local transport peer id, matching explicit device id/transport/key/package when supplied, fallback to legacy member identity only when the member has no device roster.
5. Stop PGC-011 work if focused tests prove current worktree behavior already satisfies the closure bar. Do not invent new author models or change inbound validator policy.
6. Add the PGC-012 join mutex regression with `joinGroupTopicSubscribeHook`.
7. Refactor `JoinGroupTopic` into short lock phases:
   - lock to validate started pubsub state, duplicate join, nil config/key, and identity uniqueness; clone config/key and capture `pubsub`/`ctx`;
   - unlock for `RegisterTopicValidator`, `Join`, and `Subscribe`;
   - lock again to commit maps and cancel funcs; re-check duplicate join before commit and clean up the newly-created pubsub resources if a concurrent join won the race.
8. Add the PGC-012 leave mutex regression. If proving leave cleanup requires a seam, add the smallest private package-level seam in `go-mknoon/node/pubsub.go` and keep it unavailable to external callers; do not add fields to `Node`.
9. Refactor `LeaveGroupTopic` so shared maps are read/updated under `n.mu`, but `Cancel`, `Topic.Close`, and `UnregisterTopicValidator` run after releasing `n.mu`.
10. Preserve duplicate-join and leave semantics. If narrowing introduces a stale validator race during concurrent leave/rejoin, fix only inside `pubsub.go`, for example by ordered cleanup/retry around stale validator registration. If the fix needs a new lifecycle state field or broader state machine, stop and reclassify rather than expanding this session.
11. Run gofmt on touched Go files.
12. Run the exact focused tests and gates below.
13. Only after code/tests pass, update the source matrix rows `PGC-011` and `PGC-012` and the breakdown ledger with evidence. Do not update closure docs during the implementation phase if tests are red.

## risks and edge cases

- Dirty-worktree overlap: existing uncommitted PGC-011 edits must be preserved and tested, not overwritten.
- Reliable send can store to inbox and publish concurrently; invalid sender/device metadata must fail before either goroutine starts.
- Deviceful accounts with multiple active local devices must fail unless the caller supplies an unambiguous active device.
- Legacy no-device members must continue using the sender peer id and sender public key compatibility path.
- Join duplicate race after moving network calls outside the lock must not leave stray validators/topics/subscriptions.
- Leave/rejoin race must not allow a new join to fail because an old validator is still registered, and must not leave old topic/subscription state reachable after leave returns.
- `Stop`/startup/resume paths may share group maps and cancel funcs; lock narrowing must not introduce map races.

## exact tests and gates to run

Direct regression command after adding PGC tests:

```bash
cd go-mknoon && go test ./node -run 'TestPGC011PublishGroupMessageRejectsInvalidDeviceBeforePublish|TestPGC011SendGroupMessageReliableRejectsInvalidDeviceBeforeInboxStore|TestPGC011PublishGroupReactionRejectsInvalidDeviceBeforePublish|TestPGC012JoinGroupTopicSubscribeHookRunsOutsideNodeMutex|TestPGC012LeaveGroupTopicCleanupRunsOutsideNodeMutex'
```

Existing focused safety command:

```bash
cd go-mknoon && go test ./node -run 'TestGroupPublishDeviceBinding|TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages|TestSendGroupMessageReliableStoresExactEnvelopeForActiveRecipients|TestSendGroupMessageReliableReturnsLiveOnlyWhenInboxStoreFails|TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree|TestJoinGroupTopic_RejectsDoubleJoin|TestJoinGroupTopic_DuplicateJoinPreservesExistingState|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit|TestBB009LeaveRemovesTopicSubscriptionForValidatorsAndPubSub|TestGO010JoinLeaveRecoveryCyclesDoNotLeakGroupGoroutines'
```

Package/module gates:

```bash
cd go-mknoon && go test ./node
cd go-mknoon && go test ./...
git diff --check
```

Formatting:

```bash
cd go-mknoon && gofmt -w node/pubsub.go node/pubsub_test.go node/group_inbox_test.go
```

Only include `node/group_inbox_test.go` in `gofmt` if the reliable-send no-inbox-store regression is placed there.

## known-failure interpretation

- Failures in the new PGC-011/PGC-012 tests are blockers until fixed or proven to be invalid tests.
- Failures in existing Go node tests touched by group topic lifecycle, reliable send, outbound publish, or inbound validation are presumed regressions unless a clean pre-change run proves otherwise.
- Failures outside `go-mknoon` are not part of this session unless `go test ./...` exposes a Go module failure caused by the pubsub changes.
- Known historical Flutter/simulator gate issues from `test-gate-definitions.md` are not relevant to this Go-only session and must not be used to expand scope into Flutter or device work.

## done criteria

- PGC-011 direct tests pass for message, reliable send, and reaction invalid device metadata.
- PGC-012 direct tests pass for join and leave mutex narrowing.
- Existing focused safety tests pass.
- `cd go-mknoon && go test ./node` passes.
- `cd go-mknoon && go test ./...` passes or has a documented unrelated pre-existing failure.
- `git diff --check` passes.
- Source matrix rows `PGC-011` and `PGC-012` and the session breakdown ledger are updated only with exact test evidence.

## scope guard

Do not:

- Edit Dart/Flutter files.
- Edit relay-server files.
- Change group envelope crypto/AAD/signature format.
- Change group membership, role, invite, key rotation, offline drain, or DB semantics.
- Add public APIs for test-only lock inspection.
- Add new `Node` fields or edit `go-mknoon/node/node.go`.
- Convert pubsub lifecycle into a new state machine unless a focused test proves a stale-validator or rejoin race that cannot be fixed with the narrow two-phase approach.
- Run broad device/simulator gates for this Go-only session.
- Revert or overwrite existing dirty-worktree edits in `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, or the untracked source docs.

## accepted differences / intentionally out of scope

- This session accepts the current v3 envelope signature/AAD design and does not try to close `PGC-017`.
- This session does not make relay recipient ACL mandatory; that belongs to `PGC-RELAY-1`.
- This session does not change Dart-side local sent/pending status; that belongs to `PGC-SEND-1`.
- This session may leave existing forwarded-author validator tests as supporting coverage, not as PGC-011 closure, because PGC-011 is specifically outbound preflight.

## dependency impact

- `PGC-SEND-1` can rely on Go reliable send failing fast for invalid sender/device metadata once PGC-011 is closed, but it must still own Dart local status behavior.
- `PGC-LISTENER-1` and `PGC-DRAIN-1` can rely on inbound Go validator semantics staying unchanged.
- Later group lifecycle/recovery work depends on PGC-012 not introducing join/leave races or leaked group topic state.
- If PGC-012 needs a larger lifecycle-state rewrite, stop and reclassify the row as requiring a dedicated Go pubsub lifecycle session rather than expanding this plan.
