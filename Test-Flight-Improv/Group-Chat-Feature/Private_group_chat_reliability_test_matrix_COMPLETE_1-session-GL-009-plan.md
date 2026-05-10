# GL-009 Leave Validator Lifecycle Plan

Status: execution-ready

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
Breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Session: GL-009
Disposition from breakdown: `needs_tests_only`, `implementation-ready`, tests only

## Planning Progress

- `2026-05-10T03:04:18Z` - Role: Arbiter completed. Files inspected since last update: reviewer-pass plan, tightened test shape, exact commands, scope guard, accepted differences. Decision/blocker: no structural blockers remain; tests-only remains valid; plan is execution-ready. Next action: hand off to executor without implementing in this planning session.
- `2026-05-10T03:03:26Z` - Role: Reviewer completed / Arbiter started. Files inspected since last update: draft plan mandatory sections, exact test commands, GL-009 source row wording, raw publish helper evidence, direct validator helper evidence. Decision/blocker: sufficient with adjustment; tightened the plan to one exact two-node raw-publish plus direct-validator proof path so execution is not ambiguous. Next action: Arbiter classifies review findings and finalizes readiness if no structural blocker remains.
- `2026-05-10T03:01:38Z` - Role: Planner completed / Reviewer started. Files inspected since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/node.go`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`. Decision/blocker: drafted tests-only execution plan; no production code need found. Next action: review sufficiency, gate contract, and scope guard.
- `2026-05-10T03:01:38Z` - Role: Evidence Collector completed / Planner started. Files inspected since last update: source matrix GL-009 row, breakdown GL-009 row inventory/rationale/ordered session, `LeaveGroupTopic`, validator registration/unregistration in `JoinGroupTopic`, `groupTopicValidator`, GL-003/GL-004 retry tests, existing leave and GL-008 tests, raw envelope helpers, gate definitions, dirty worktree status. Decision/blocker: current code already unregisters on leave; missing coverage is row-owned proof after leave/rejoin. Next action: draft the narrow GL-009 tests-only plan.
- `2026-05-10T02:57:59Z` - Role: Evidence Collector started. Files inspected since last update: none beyond intake. Decision/blocker: Starting repo evidence pass focused on GL-009 only. Next action: inspect source matrix, breakdown, leave API, topic validator registration/unregistration, GL-003/GL-004 retry tests, leave tests, raw envelope helpers, and test gate definitions.

## Execution Progress

- `2026-05-10T03:06:20Z` - Phase: contract extracted. Files inspected or touched: this plan, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/group_security_harness_test.go`. Decision/blocker: execution contract is tests-only, scoped to one GL-009 Go regression in `go-mknoon/node/pubsub_delivery_test.go`; required commands are the direct GL-009 test, row Go sweep, Flutter startup rejoin smoke, and `git diff --check`; groups gate remains conditional only if production or Flutter/Dart group behavior changes. Next action: spawn isolated Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- `2026-05-10T03:07:11Z` - Phase: Executor spawn retry. Files inspected or touched: this plan. Decision/blocker: first `codex exec` launch failed before child materialization because approval/sandbox flags were passed after the `exec` subcommand; no child work or file edits occurred. Next action: retry Executor spawn with corrected top-level CLI flag order.
- `2026-05-10T03:08:10Z` - Phase: Executor running. Files inspected or touched: this plan, current diffs for `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`, helper/validator snippets in `go-mknoon/node/group_security_harness_test.go` and `go-mknoon/node/pubsub.go`. Decision/blocker: existing dirty changes are unrelated GL-001..GL-008 tests; GL-009 remains a single tests-only addition in `go-mknoon/node/pubsub_delivery_test.go`. Next action: add or verify `TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey`.
- `2026-05-10T03:09:30Z` - Phase: Executor child stopped / local fallback started. Files inspected or touched: this plan, `go-mknoon/node/pubsub_delivery_test.go`. Decision/blocker: spawned Executor materialized but did not produce the GL-009 test, required command evidence, or trustworthy handoff after the bounded wait plus one progress-based extension; child was terminated and classified `spawn_or_tool_failure` for the Executor step. Next action: use the skill's bounded local sequential fallback for Executor responsibilities, then local QA.
- `2026-05-10T03:10:59Z` - Phase: local Executor edit completed. Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`. Decision/blocker: added `TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey` plus test-local validation-reject and stale-marker absence helpers; no production, Dart/Flutter, matrix, or breakdown files were edited by this GL-009 fallback pass. Next action: run the required direct GL-009 regression.
- `2026-05-10T03:13:10Z` - Phase: direct GL-009 regression failed / test-shape fix applied. Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`, libp2p pubsub publish validation path. Command: `(cd go-mknoon && go test ./node -run 'TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey' -count=1)`. Decision/blocker: failure was not duplicate-validator or stale receiver behavior; stale raw publish was rejected by nodeA's own latest local validator before fanout (`topic publish: validation failed`). Classified as GL-009 test-shape issue, not production gap; updated the test to unregister only nodeA's local validator before the raw stale publish so nodeB's post-rejoin validator is exercised. Next action: rerun the required direct GL-009 regression.
- `2026-05-10T03:13:34Z` - Phase: direct GL-009 regression passed. Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`. Command: `(cd go-mknoon && go test ./node -run 'TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey' -count=1)`. Decision/blocker: passed in 1.644s; no production scope correction required. Next action: run the required row Go sweep.
- `2026-05-10T03:14:06Z` - Phase: row Go sweep passed. Files inspected or touched: none. Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)`. Decision/blocker: passed in 12.963s. Next action: run the required Flutter startup rejoin smoke.
- `2026-05-10T03:14:39Z` - Phase: Flutter startup rejoin smoke passed. Files inspected or touched: none. Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Decision/blocker: all tests passed. Next action: run required `git diff --check`.
- `2026-05-10T03:15:04Z` - Phase: diff hygiene passed / local QA started. Files inspected or touched: none. Command: `git diff --check`. Decision/blocker: passed with no whitespace errors. Next action: perform local QA Reviewer pass over scope, diffs, required evidence, and done criteria.
- `2026-05-10T03:15:30Z` - Phase: local QA completed / final verdict written. Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`, this plan. Decision/blocker: no blocking QA issues; GL-009 regression exists, proves same-group leave/rejoin succeeds, latest raw envelope delivers, stale old config/key raw envelope is rejected by nodeB after rejoin, and latest-key/old-signer direct validator rejects; all required commands passed. Final verdict: `accepted`.
- `2026-05-10T03:15:48Z` - Phase: final diff hygiene rerun passed. Files inspected or touched: none. Command: `git diff --check`. Decision/blocker: passed after final plan-progress edit. Final verdict remains: `accepted`.

## Evidence Collected

- Source matrix row GL-009 requires: joined group G, call `LeaveGroupTopic(G)`, rejoin G, then publish valid and invalid envelopes; expected result is that the old validator is gone and the new validator uses only the latest config/key.
- Breakdown row GL-009 is still `Open`, `needs_tests_only`, `implementation-ready`, and points to this plan path. GL-008 is already closed; GL-010 remains separate.
- `go-mknoon/node/pubsub.go::JoinGroupTopic` registers the topic validator before topic join and now unregisters it on join failure and subscribe failure. GL-003 and GL-004 tests cover those partial-join retry cases.
- `go-mknoon/node/pubsub.go::LeaveGroupTopic` cancels discovery and subscription, closes/deletes the topic, then calls `n.pubsub.UnregisterTopicValidator(topicName)` before deleting group config/key.
- `groupTopicValidator` reads `n.groupConfigs[groupId]` and `n.groupKeys[groupId]` at validation time, so a post-rejoin proof must distinguish latest state from stale config/key by using changed signing public key and key epoch/key material.
- Existing leave tests prove discovery context cleanup, map cleanup, publish/reaction fail as `group not joined`, and GL-008 post-leave silence. They do not prove validator unregistration or latest config/key validation after rejoin.
- Raw envelope helpers exist in `go-mknoon/node/group_security_harness_test.go` (`buildGroupEnvelopeWithPlaintext`, `publishRawGroupEnvelope`) and `go-mknoon/node/pubsub_delivery_test.go` (`waitForCollectedEventContaining`). Direct validator helpers already exist in `go-mknoon/node/pubsub_test.go`.
- `Test-Flight-Improv/test-gate-definitions.md` defines the Group Messaging Gate for group send/receive/retry/resume/invite/announcement behavior changes; a Go tests-only validator lifecycle proof does not require the full Flutter groups gate unless implementation changes Flutter/Dart or user-visible group behavior.

## 1. real scope

Add or verify one row-owned Go regression for GL-009. The expected execution remains tests-only unless the new regression proves current `LeaveGroupTopic` fails to unregister the validator.

In scope:
- Prove leave unregisters the libp2p topic validator by showing same-group `JoinGroupTopic` succeeds after `LeaveGroupTopic`.
- Prove post-rejoin validation accepts an envelope signed/encrypted with the latest config/key.
- Prove stale pre-leave config/key envelopes are rejected after rejoin.
- Preserve GL-008 leave silence as closed and GL-010 unknown-group leave as separate.

Out of scope:
- Dart/Flutter behavior, bridge command payloads, rejoin use-case orchestration, lifecycle recovery, relay/inbox behavior, database schema, and group UI.
- Changing validator authorization semantics unless the GL-009 regression fails for a real product reason.

## 2. closure bar

GL-009 is good enough when a test using real `JoinGroupTopic` and `LeaveGroupTopic` proves:
- the second join for the same group succeeds after leave, which would fail with libp2p's duplicate-validator error if the old validator remained registered;
- latest config/key envelopes validate or deliver after rejoin;
- stale pre-leave key/config envelopes are rejected after rejoin;
- no production or Dart/Flutter code is changed unless the test exposes a real failure.

## 3. source of truth

- Current code and tests beat stale matrix prose.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gate scope; if they disagree, the script wins for execution.
- Source matrix row GL-009 and the breakdown GL-009 entries define row ownership.
- This plan becomes the active execution contract for GL-009 once marked `execution-ready`.

## 4. session classification

`implementation-ready`.

Scope type: tests-only. Repo evidence does not currently justify code changes because `LeaveGroupTopic` already calls `UnregisterTopicValidator` for the group topic. If the new regression fails for duplicate validator on rejoin or stale validator behavior, execution must stop and reclassify GL-009 to code+tests with the failing evidence.

## 5. exact problem statement

The repo has current code that appears to unregister a group topic validator on leave, but there is no GL-009-owned regression proving the leave/rejoin validator lifecycle. A stale validator would break remove/re-add or app rejoin by either preventing a new validator registration with a duplicate-validator error or by allowing validation assumptions from an old membership/key window to survive.

User-visible behavior that must improve: after leaving and rejoining a private group, the app should accept only messages valid under the latest group config/key and reject stale envelopes from the old join window.

Must stay unchanged: leave remains quiet after GL-008, unknown leave remains GL-010, duplicate join behavior remains GL-002, partial join cleanup remains GL-003/GL-004, and latest validator authorization rules remain the existing `groupTopicValidator` rules.

## 6. files and repos to inspect next

- `go-mknoon/node/pubsub.go`: `JoinGroupTopic`, `LeaveGroupTopic`, `groupTopicValidator`, `verifyGroupEnvelopeSignature`, `groupEnvelopeMatchesTransportPeer`.
- `go-mknoon/node/pubsub_delivery_test.go`: exact test home for the two-node raw publish proof plus direct validator stale-config assertion.
- `go-mknoon/node/pubsub_test.go`: helper reference only; do not edit unless current dirty diffs make `pubsub_delivery_test.go` unsafe to touch.
- `go-mknoon/node/group_security_harness_test.go`: raw group envelope builders and `publishRawGroupEnvelope`.
- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`: GL-008 leave-silence context; inspect but do not edit unless reusing helpers is cleaner.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`: gate source.

## 7. existing tests covering this area

- `TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry` covers validator cleanup after `RegisterTopicValidator` succeeds and topic join fails.
- `TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry` covers validator cleanup after topic join succeeds and subscribe fails.
- `TestLeaveGroupTopic_CancelsDiscoveryContext` covers discovery context removal.
- `TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish` covers topic/subscription/config/key cleanup and local publish/reaction failing after leave.
- `TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave` covers active discovery/subscription silence after leave.

Missing before GL-009:
- no test leaves a successfully joined group, rejoins the same group, and proves no stale topic validator remains;
- no test proves validation after rejoin uses latest config/key rather than stale pre-leave material.

## 8. regression/tests to add first

Add one focused Go regression named similar to:

```text
TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey
```

Exact shape:
- Put the test in `go-mknoon/node/pubsub_delivery_test.go`.
- Use two local nodes: node A as raw publisher and node B as the leave/rejoin receiver with a `testEventCollector`.
- First join node B to group G with old node-A signing public key and old group key/epoch.
- Call `nodeB.LeaveGroupTopic(G)`.
- Rejoin node B to the same group ID with latest node-A signing public key and latest group key/epoch.
- Assert rejoin succeeds. This is the validator-unregistration proof because libp2p rejects duplicate validators for a topic.
- Join node A with the latest config/key, connect A to B, and wait for one group topic peer.
- Publish a latest valid envelope from node A with `publishRawGroupEnvelope`; assert node B receives the marker.
- Publish one stale old-key/old-config envelope from node A with `publishRawGroupEnvelope`; assert node B emits `group:validation_rejected` with `reason=bad_signature_or_epoch` and the old key epoch, and assert the stale marker is not received.
- Add a direct `nodeB.groupTopicValidator(G)` assertion for a latest-key/latest-epoch envelope signed by the old pre-leave signing key. This avoids diagnostic-throttle ambiguity while proving latest config/public-key state is used.

## 9. step-by-step implementation plan

1. Inspect current diffs for `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` before editing; preserve unrelated dirty work.
2. Add the GL-009 regression in `go-mknoon/node/pubsub_delivery_test.go`.
3. Generate old and latest sender key pairs plus old/latest group keys. Use the same group ID for both joins.
4. Join with old config/key, then call `LeaveGroupTopic`.
5. Rejoin with latest config/key and fail the test if `JoinGroupTopic` returns a duplicate-validator or any other error.
6. Assert latest envelope acceptance using raw publish plus collector delivery.
7. Assert stale pre-leave envelope rejection with one raw invalid publish and one direct validator call:
   - raw stale old-key/old-config envelope should produce `group:validation_rejected` and no stale marker delivery;
   - direct latest-key envelope signed by the old signing key should return `pubsub.ValidationReject`.
8. Run the direct test. Because current code already appears correct, this test is expected to pass without production changes. If it fails for the intended GL-009 reason, stop and reclassify to code+tests before touching production code.
9. Run the row Go sweep and the startup rejoin smoke listed below.
10. Run `git diff --check`.

## 10. risks and edge cases

- Rejoin proof must use the same group ID; a new group ID would not test duplicate validator cleanup.
- Stale config/key proof must change both signing public key and group key/epoch, otherwise the test may not distinguish old state from latest state.
- Validator diagnostics throttle repeated same-reason events for one minute, so do not require multiple `group:validation_rejected` events with the same reason/group/sender/peer unless the test controls `pubsubRejectDiagNow`.
- Raw publish tests can be timing-sensitive; keep only one raw invalid publish and use the direct validator for the second stale-config proof.
- GL-010 unknown leave and stop-time validator cleanup are not part of this row.

## 11. exact tests and gates to run

Required direct regression:

```bash
(cd go-mknoon && go test ./node -run 'TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey' -count=1)
```

Required row Go sweep:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
```

Required Flutter smoke because the breakdown row names startup rejoin as adjacent gate evidence:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Required diff hygiene:

```bash
git diff --check
```

Conditional only if production or Dart/Flutter group behavior changes:

```bash
./scripts/run_test_gates.sh groups
```

## 12. known-failure interpretation

- The direct GL-009 test is not expected to be RED first because this is coverage for behavior that current code appears to implement. Treat a pass as confirming the tests-only disposition.
- If the direct GL-009 test fails on rejoin with duplicate validator, that is a real GL-009 product failure and the session must be reclassified to code+tests before production edits.
- If broad row or Flutter smoke commands fail outside the new GL-009 test, classify each failure as GL-009-caused, pre-existing, unrelated-but-required, flaky, or environment/tooling. Do not fix unrelated dirty-worktree failures in this session.
- The worktree is already dirty in many Go, Flutter, and doc files. Do not revert or overwrite unrelated changes.

## 13. done criteria

- The intended test exists and is GL-009-named or clearly GL-009-owned.
- The test proves leave -> same-group rejoin succeeds after validator unregister.
- The test proves latest config/key accept and stale config/key reject after rejoin.
- Required direct regression, row Go sweep, startup rejoin smoke, and diff check pass, or non-GL-009 failures are triaged with exact output.
- No production, Dart/Flutter, bridge, relay, database, or unrelated doc changes are made unless the regression forces a scope correction.

## 14. scope guard

Do not:
- implement GL-010 unknown leave behavior;
- reopen GL-008 leave silence;
- change `groupTopicValidator` authorization semantics without a failing GL-009 proof;
- add new public test seams to production code;
- broaden into rejoin use cases, lifecycle recovery, bridge idempotency, relay/inbox replay, or Flutter UI;
- run or require device/simulator E2E beyond the listed startup rejoin smoke unless production behavior changes.

Overengineering for this row would be adding validator registry introspection APIs, new fake PubSub abstractions, broad group membership lifecycle refactors, or multi-session closure docs.

## 15. accepted differences / intentionally out of scope

- Direct validator assertion is intentionally limited to the stale-config/latest-key case because validator diagnostics throttle repeated same-reason events. Raw publish still proves the latest live path and one stale invalid publish path.
- The proof that the old validator is gone is indirect through libp2p rejoin success, matching prior accepted GL-002/GL-003/GL-004 proof style where duplicate validator registration is the observable failure.
- Stop-time cleanup is not covered by GL-009; this row is specifically `LeaveGroupTopic`.

## 16. dependency impact

Later remove/re-add, startup rejoin, membership mutation, and stale-envelope authorization rows can rely on GL-009 only after this plan lands with passing evidence. If the GL-009 regression forces code changes, later rows must not assume leave/rejoin validator lifecycle is fixed until the code+tests correction is accepted.

## Reviewer Pass

Sufficient with adjustment, now applied.

- Missing files/tests/gates: none after tightening. The exact test home is `go-mknoon/node/pubsub_delivery_test.go`; the exact direct regression, row Go sweep, startup rejoin smoke, and `git diff --check` are listed.
- Stale assumptions: none found. Current `LeaveGroupTopic` evidence supports tests-only; if execution proves otherwise, the plan has a stop-and-reclassify rule.
- Overengineering: avoided by using existing local-node, raw envelope, collector, and direct validator helpers instead of adding production seams or registry introspection.
- Decomposition: sufficient. One GL-009-owned test covers validator unregister, latest accept, stale-key reject, and stale-config reject without reopening GL-008 or GL-010.
- Minimum needed: implement the single test, run the listed commands, and do not edit production code unless the test fails for a real GL-009 reason.

## Arbiter Decision

No structural blockers remain. The plan is execution-ready.

Structural blockers:
- None.

Incremental details:
- The executor may add a tiny test-local wait helper for `group:validation_rejected` by reason/key epoch if no existing helper fits. This is not a production seam.
- The executor may use `pubsubRejectDiagNow` only if it decides to assert more than one raw invalid publish diagnostic. The plan avoids requiring that.

Accepted differences:
- Validator unregistration is proven indirectly through same-topic rejoin success because libp2p exposes duplicate validator leaks as a registration failure, not as a public registry count.
- One stale-config proof uses a direct validator call to avoid one-minute diagnostic throttling. Raw publish still proves latest live acceptance and one stale invalid rejection path.
- Full `./scripts/run_test_gates.sh groups` stays conditional because this is Go tests-only coverage, not a Dart/Flutter or user-visible group behavior change.

Final verdict:
- `execution-ready`, tests-only.

Final plan:
- Add one GL-009 Go regression in `go-mknoon/node/pubsub_delivery_test.go`.
- Do not edit production code unless the new regression fails for a real GL-009 reason and the session is explicitly reclassified.
- Run the exact direct regression, row Go sweep, startup rejoin smoke, and diff check listed above.

Why safe to implement now:
- Current production code already unregisters the validator in `LeaveGroupTopic`.
- Existing adjacent tests cover partial join cleanup and leave silence but not this row's leave/rejoin validator lifecycle.
- The plan has a narrow stop rule, exact files, exact tests, and explicit non-goals for GL-008, GL-010, Dart/Flutter, bridge, relay, database, and UI work.
