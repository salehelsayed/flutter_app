# GPF-001 - Forwarded GossipSub Validator Uses Signed PubSub Author

Status: executed-accepted

## Planning Progress

- 2026-05-23 19:34:00 CEST - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan written with RED-first tests, minimum production edit, and Go-only scope guard. Next action: run sufficiency review.
- 2026-05-23 19:35:19 CEST - Reviewer started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md`. Decision/blocker: review draft against mandatory sections, regression contract, and scope guard. Next action: record sufficiency findings.
- 2026-05-23 19:35:52 CEST - Reviewer completed. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md`. Decision/blocker: sufficient after tightening the new regression test name and construction guidance; no structural blocker remaining. Next action: run arbiter classification.
- 2026-05-23 19:36:28 CEST - Arbiter started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md`. Decision/blocker: classify reviewer findings and decide execution readiness. Next action: record final arbiter decision.
- 2026-05-23 19:36:47 CEST - Arbiter completed. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md`. Decision/blocker: no structural blocker remains; status set to `execution-ready`. Next action: execute with `$implementation-execution-qa-orchestrator` when requested.

## Execution Progress

- 2026-05-23 19:38:47 CEST - Contract extracted. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/go.mod`, `go-mknoon/third_party/go-libp2p-pubsub/pubsub.go`, `go-mknoon/third_party/go-libp2p-pubsub/validation.go`. Decision/blocker: scope is Go-node-only; add RED live-validator test first, then change two live validator binding call sites to use `msg.GetFrom().String()`. Next action: add RED regression in `go-mknoon/node/pubsub_test.go`.
- 2026-05-23 19:38:47 CEST - Executor running. Files inspected since last update: none. Decision/blocker: no nested sub-agent spawn tool is available in this environment; proceeding as the isolated execution agent with the skill's local sequential fallback contract. Next action: make the RED-only test edit.
- 2026-05-23 19:40:40 CEST - RED test added. Files touched since last update: `go-mknoon/node/pubsub_test.go`. Decision/blocker: added `TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages` only; production remains unchanged. Command currently running: none. Next action: gofmt the test file, then run the required targeted RED command.
- 2026-05-23 19:40:57 CEST - Targeted RED command started. Files touched since last update: `go-mknoon/node/pubsub_test.go`. Command currently running: `cd go-mknoon && go test ./node -count=1 -run 'TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice|TestGroupTopicValidator_DeviceRejectsUnboundSibling'`. Decision/blocker: expecting forwarded accept subtests to fail before production fix. Next action: capture RED result.
- 2026-05-23 19:41:16 CEST - Targeted RED command finished. Files touched since last update: none. Command finished: `cd go-mknoon && go test ./node -count=1 -run 'TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice|TestGroupTopicValidator_DeviceRejectsUnboundSibling'`. Decision/blocker: expected RED confirmed; `forwarded_author_transport_match_accepts` and `forwarded_device_bound_author_accepts` failed with `ValidationReject`, while forged mismatch stayed rejected. Next action: apply minimum production fix in `go-mknoon/node/pubsub.go`.
- 2026-05-23 19:41:43 CEST - Production fix applied. Files touched since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`. Decision/blocker: `Node.groupTopicValidator` now derives `originTransportPeerId` from `msg.GetFrom().String()` and passes it to both transport-envelope binding and device binding; diagnostics still use callback `pid`. Next action: rerun the required targeted command after the fix.
- 2026-05-23 19:41:58 CEST - Targeted post-fix command started. Files touched since last update: none. Command currently running: `cd go-mknoon && go test ./node -count=1 -run 'TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice|TestGroupTopicValidator_DeviceRejectsUnboundSibling'`. Decision/blocker: verify RED regressions now pass while pure mismatch/device guards remain covered. Next action: capture post-fix targeted result.
- 2026-05-23 19:42:19 CEST - Targeted post-fix command finished. Files touched since last update: none. Command finished: `cd go-mknoon && go test ./node -count=1 -run 'TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice|TestGroupTopicValidator_DeviceRejectsUnboundSibling'`. Decision/blocker: passed (`ok github.com/mknoon/go-mknoon/node 0.648s`). Next action: run required full module-local `go test ./node`.
- 2026-05-23 19:42:35 CEST - Full Go node gate started. Files touched since last update: none. Command currently running: `cd go-mknoon && go test ./node`. Decision/blocker: required full module-local validation. Next action: capture full gate result.
- 2026-05-23 19:50:07 CEST - Full Go node gate finished. Files touched since last update: none. Command finished: `cd go-mknoon && go test ./node`. Decision/blocker: failed with exit code 1 after 422.784s, but terminal output was too large and truncated before failing test names. Next action: rerun into a local log for failure-name triage before any fix attempt.
- 2026-05-23 19:59:03 CEST - Failure triage completed. Files inspected since last update: `/tmp/gpf001-go-test-node.log`, `go-mknoon/node/pubsub_authorization_forward_test.go`, `go-mknoon/node/group_inbox_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_test.go`. Decision/blocker: logged rerun of `cd go-mknoon && go test ./node` failed after 419.479s; one validator-adjacent failure is `TestSV004ForgedSenderIdentityOrSignatureRejectsWithSafeDiagnostics/claimed_sender_over_wrong_transport_peer`, caused by a handcrafted message with no `pb.Message.From`; other failures are unrelated group inbox/config tests. Next action: apply a narrow fix-pass fallback for missing PubSub author without editing out-of-scope fixtures.
- 2026-05-23 19:59:27 CEST - Fix pass applied. Files touched since last update: `go-mknoon/node/pubsub.go`. Decision/blocker: `originTransportPeerId` still comes from `msg.GetFrom().String()` when present, with a fallback to `pid.String()` only for handcrafted/no-author validator inputs to preserve existing rejection logic. Next action: run the previously failing validator diagnostic test, then rerun required targeted and full commands.
- 2026-05-23 20:00:09 CEST - Fix-pass validator check finished. Files touched since last update: none. Command finished: `cd go-mknoon && go test ./node -count=1 -run 'TestSV004ForgedSenderIdentityOrSignatureRejectsWithSafeDiagnostics'`. Decision/blocker: passed (`ok github.com/mknoon/go-mknoon/node 0.621s`). Next action: rerun required targeted command after fix pass.
- 2026-05-23 20:00:40 CEST - Targeted post-fix-pass command finished. Files touched since last update: none. Command finished: `cd go-mknoon && go test ./node -count=1 -run 'TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice|TestGroupTopicValidator_DeviceRejectsUnboundSibling'`. Decision/blocker: passed (`ok github.com/mknoon/go-mknoon/node 0.349s`). Next action: rerun required full `go test ./node` for final evidence.

## Closure Progress

- 2026-05-23 20:19:08 CEST - Completion Auditor completed. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md`. Decision/blocker: classify `GPF-001` as closed; targeted regression evidence passed, the related `SV004` failure is fixed, and remaining full-node failures reproduce at clean detached HEAD as unrelated/pre-existing. Next action: write final closure state.
- 2026-05-23 20:19:08 CEST - Closure Writer completed. Files touched since last update: `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md`. Decision/blocker: plan status set to `executed-accepted`; breakdown ledger set to `accepted`; final program verdict persisted as `closed`. Next action: review for overclaiming and residual-only wording.
- 2026-05-23 20:19:08 CEST - Closure Reviewer completed. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md`. Decision/blocker: docs accurately close only GPF-001, preserve the full-node failure as residual-only/unrelated, and do not reopen broader group-chat or Flutter work. Next action: maintenance only unless a real forwarded-origin regression appears.

## real scope

This session changes only Go PubSub group validator behavior and its direct Go tests:

- Production target: `go-mknoon/node/pubsub.go`.
- Test target: `go-mknoon/node/pubsub_test.go`.
- Behavior target: the live group topic validator must bind a group envelope to the signed PubSub author from `msg.GetFrom()`, not to the validator callback `pid`, because `pid` is the immediate forwarding peer for forwarded GossipSub deliveries.

The intended production edit is minimum-code: derive one origin transport peer id from `msg.GetFrom()` inside `Node.groupTopicValidator`, then pass that origin id to the existing `groupEnvelopeMatchesTransportPeer(env, ...)` and `activeMemberDeviceForEnvelope(member, env, ...)` calls. Keep `pid` available for rejection diagnostics as the observed forwarding peer unless implementation evidence proves a diagnostic change is required.

This session does not change Flutter, Dart, database, relay, rendezvous, group config shape, envelope signing format, device membership rules, libp2p routing, or the vendored PubSub fork.

## closure bar

Good enough for this session means:

- A valid forwarded group message is accepted when `msg.GetFrom()` and `env.SenderTransportPeerId` identify Alice, even when the validator callback `pid` identifies Carol as the forwarding peer.
- A forged or inconsistent author/envelope combination remains rejected when `msg.GetFrom()` does not match `env.SenderTransportPeerId` or the legacy sender fallback.
- A device-bound forwarded message is accepted only when the PubSub author matches the registered device transport id and the envelope's device fields still match an active configured device.
- Existing rejection behavior for non-members, unknown groups, bad signatures, revoked/unbound devices, unauthorized writers, and group id mismatches remains unchanged.
- `cd go-mknoon && go test ./node` passes, or any failure is classified as pre-existing and unrelated with direct evidence.

## source of truth

Authoritative sources for this session:

- Current code in `go-mknoon/node/pubsub.go` wins over stale docs.
- Current tests in `go-mknoon/node/pubsub_test.go` define existing validator behavior, but tests that manually call the live validator without a PubSub `From` field are test fixtures, not proof that forwarding-peer binding is intentional.
- `go-mknoon/go.mod` is authoritative for dependency wiring; it replaces `github.com/libp2p/go-libp2p-pubsub` with `./third_party/go-libp2p-pubsub`.
- The forked PubSub implementation in `go-mknoon/third_party/go-libp2p-pubsub` is authoritative for `Message.ReceivedFrom`, `Message.GetFrom()`, and validator callback source semantics.
- `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md` is the active session contract unless repo evidence contradicts it.

On disagreement, live Go code and direct tests win first, then forked PubSub behavior, then the session breakdown.

## session classification

executed-accepted

## exact problem statement

The group topic validator currently binds group envelope identity to the validator callback `pid` by calling `groupEnvelopeMatchesTransportPeer(env, pid.String())` and `activeMemberDeviceForEnvelope(member, env, pid.String())` in `go-mknoon/node/pubsub.go`. In forked libp2p PubSub, the callback source is the immediate sender of the RPC/validation path, while `msg.GetFrom()` is the signed PubSub message author. For forwarded GossipSub messages, those can differ.

Broken behavior: a valid group message authored by Alice and forwarded by Carol can be rejected as `peer_mismatch` or `unbound_device` because the validator compares Alice's envelope/device transport fields to Carol's forwarding peer id.

Required behavior: bind the envelope/device checks to Alice's signed PubSub author id while preserving all existing envelope signature, membership, device status, group config, and writer authorization checks. Forged author/envelope mismatches must still reject.

## files and repos to inspect next

Before implementation, inspect only:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/go.mod`
- `go-mknoon/third_party/go-libp2p-pubsub/pubsub.go`
- `go-mknoon/third_party/go-libp2p-pubsub/validation.go`
- `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md`

Do not inspect or edit Flutter/Dart files, relay code, database migrations, or the PubSub fork unless the direct Go tests reveal a repo-local compile error in those files.

## existing tests covering this area

Existing coverage:

- `validateGroupEnvelopeForTransportPeer` in `go-mknoon/node/pubsub_test.go` mirrors the validator's transport/device checks for pure tests.
- `TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender` covers accept when the supplied transport id matches the envelope sender.
- `TestGroupTopicValidator_RejectsTransportPeerIdMismatch` covers reject when the supplied transport id mismatches the envelope sender.
- `TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice` covers accept for a registered active device when supplied transport id matches the device transport id.
- `TestGroupTopicValidator_DeviceRejectsUnboundSibling` and later device tamper tests cover unbound/revoked/mismatched device rejections.
- Several live-validator tests construct `pubsub.Message{Message: &pb.Message{Data: ...}}` and pass `pid` manually. Those tests cover validator control flow and rejection events, but they generally do not set `pb.Message.From` and therefore do not cover forwarded PubSub author semantics.

Missing coverage:

- No direct regression proves that the live validator accepts a forwarded message when `msg.GetFrom()` is Alice and callback `pid` is Carol.
- No direct regression proves that the live validator still rejects when the signed PubSub author in `msg.GetFrom()` does not match `env.SenderTransportPeerId`.
- No direct regression proves that device-bound forwarded messages use the PubSub author for `activeMemberDeviceForEnvelope`, not the forwarding peer id.

Existing direct-peer tests should be adjusted carefully: keep the pure helper mismatch test as an origin/envelope mismatch guard, but do not treat it as proof that the live PubSub validator should bind to forwarding `pid`.

## regression/tests to add first

Add RED-first live-validator coverage in `go-mknoon/node/pubsub_test.go`, preferably near the existing transport/device validator tests.

Add one table-driven live-validator test named `TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages` with these subtests:

- `forwarded_author_transport_match_accepts`: build a valid envelope for Alice with `env.SenderTransportPeerId` set to Alice's transport id, preferably by using `buildTestDeviceEnvelope` with `senderDeviceId` equal to Alice's member id and no configured devices for Alice; set `pb.Message.From` to Alice's transport id; invoke `validator(context.Background(), peer.ID("carol-forwarder"), msg)`; expect `pubsub.ValidationAccept`. This must fail before the production fix because current code compares the envelope to Carol.
- `forwarded_author_envelope_mismatch_rejects`: reuse a valid Alice envelope with `env.SenderTransportPeerId` set to Alice, set `pb.Message.From` to Mallory, invoke with forwarding `pid` Carol, and expect `pubsub.ValidationReject`. This proves the fix does not accept forged PubSub author/envelope mismatches.
- `forwarded_device_bound_author_accepts`: configure Alice as a member with one active device whose `TransportPeerId` is Alice's device transport id; build a device-bound envelope with that device id, device public key, key package id, and sender transport id; set `pb.Message.From` to the device transport id; invoke with forwarding `pid` Carol; expect `pubsub.ValidationAccept`. This must fail before the production fix if either validator helper still receives Carol.

The new test should set `n.groupConfigs[groupId]` and `n.groupKeys[groupId]` directly, as existing live validator tests do. Use existing helpers such as `buildTestDeviceEnvelope`, `generateEd25519KeyPair`, and `mcrypto.GenerateGroupKey`.

Run the targeted command immediately after adding the tests and before production code changes. The expected RED result is at least the forwarded accept case failing with `ValidationReject`.

## step-by-step implementation plan

1. Add the RED table-driven test `TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages` described above in `go-mknoon/node/pubsub_test.go`.
2. Run the targeted test command and confirm the forwarded accept and device-bound forwarded accept cases fail before production code changes. If they pass before any code change, stop and re-inspect the validator/source semantics because the bug may already be fixed or the test is not exercising the seam.
3. In `go-mknoon/node/pubsub.go`, inside `Node.groupTopicValidator`, derive an `originTransportPeerId` from `msg.GetFrom().String()` after the envelope is parsed and before transport/device binding. Do not derive it from `pid`.
4. Replace only the two binding arguments in the live validator:
   - `groupEnvelopeMatchesTransportPeer(env, pid.String())` becomes `groupEnvelopeMatchesTransportPeer(env, originTransportPeerId)`.
   - `activeMemberDeviceForEnvelope(member, env, pid.String())` becomes `activeMemberDeviceForEnvelope(member, env, originTransportPeerId)`.
5. Keep rejection logging and feedback scoped to the existing `pid` unless the new tests require an explicit origin diagnostic. Diagnostic renaming is out of scope for this session.
6. Re-run the targeted tests. If the forwarded accept passes but the forged mismatch also accepts, stop and tighten the origin/envelope mismatch before running broader tests.
7. Run `cd go-mknoon && go test ./node`.
8. If existing live-validator tests fail only because their handcrafted `pubsub.Message` lacks `pb.Message.From`, adjust those fixtures minimally by setting `From: []byte(<intended sender transport id>)`; do not rewrite unrelated tests. Leave pure helper tests intact unless a name/comment is misleading enough to invite future misuse.

## risks and edge cases

- Forwarded delivery: `pid` can be Carol while signed author is Alice; this is the core regression.
- Forged author drift: a malicious peer may forward a message where PubSub author and envelope sender transport disagree; this must reject.
- Device-bound senders: the same origin id must feed both transport-peer matching and active-device lookup, otherwise device-bound forwarded messages can still reject as `unbound_device`.
- Legacy member entries without `Devices`: `groupEnvelopeMatchesTransportPeer` falls back from `SenderTransportPeerId` to `SenderId`; preserve that helper behavior.
- Handcrafted tests without `pb.Message.From`: treat failures in these tests as fixture ambiguity, not a reason to bind production behavior back to forwarding `pid`.
- Diagnostics: keeping `pid` in rejection logs may label Carol as transport peer while the rejection reason is based on Alice/Mallory author checks. Do not expand this session into a diagnostics redesign.

## exact tests and gates to run

Run from workspace root:

```sh
cd go-mknoon && go test ./node -count=1 -run 'TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice|TestGroupTopicValidator_DeviceRejectsUnboundSibling'
```

Then run:

```sh
cd go-mknoon && go test ./node
```

Named gates: none for this session. The session breakdown explicitly classifies this as Go-node-only validator behavior.

## known-failure interpretation

The RED run is expected to fail before production edits on the forwarded accept case and the device-bound forwarded accept case. The forged mismatch case may already pass before the fix because the current forwarding-peer comparison also rejects it; it must continue to pass after the fix.

For the final `go test ./node` run:

- Any failure in newly added forwarded-origin tests is blocking.
- Any failure in existing transport/device validator tests is blocking unless direct evidence shows the test was asserting the old forwarding-peer assumption for the live PubSub validator; in that case, minimally update the fixture to set `pb.Message.From` and rerun.
- Failures outside `go-mknoon/node` are out of scope because no broader gate is required.
- If `go test ./node` has a pre-existing unrelated failure, capture the failing test name and prove it reproduces without this session's changes before classifying it as non-blocking.

## done criteria

- New RED-first forwarded-origin tests exist in `go-mknoon/node/pubsub_test.go`.
- The live validator in `go-mknoon/node/pubsub.go` uses `msg.GetFrom()`-derived origin id for both transport binding and device binding.
- Forwarded Alice author via Carol is accepted.
- Forged PubSub author/envelope mismatch remains rejected.
- Device-bound forwarded Alice author via Carol is accepted.
- Existing pure transport mismatch and device unbound/revoked protections remain covered.
- Targeted Go test command passes after the fix.
- `cd go-mknoon && go test ./node` passes or has only documented pre-existing unrelated failures.

## scope guard

Do not make Flutter/Dart changes. Do not edit `go-mknoon/third_party/go-libp2p-pubsub`. Do not redesign libp2p transport, signing policy, GossipSub routing, relay behavior, rendezvous, or peer scoring. Do not change group envelope schema, app-level signature format, key epochs, membership config storage, device lifecycle semantics, or validation rejection event contracts unless a compile error directly requires a small fixture update.

Overengineering for this session includes adding new validator abstraction layers, changing helper semantics broadly, adding network integration tests, changing all validator diagnostics, or expanding into offline/retry/notification flows.

## accepted differences / intentionally out of scope

- The pure helper `validateGroupEnvelopeForTransportPeer` may continue to accept an explicit transport/origin id argument for unit testing. This is not a live PubSub source model.
- Existing direct-peer or legacy no-device tests may keep using `SenderId` as the fallback transport identity.
- Rejection diagnostics may still report the callback `pid` as the observed peer. A future diagnostics session can add signed-author hashes if needed.
- No attempt is made to validate PubSub signature policy inside application validator tests; the tests simulate the relevant `pb.Message.From` author field directly.

## dependency impact

This plan unblocks the session breakdown's single `GPF-001` implementation. Later group-chat reliability work can rely on forwarded GossipSub messages not being rejected solely because they arrived through an intermediate peer. If this plan changes to require PubSub fork edits or transport redesign, skip downstream execution and reopen the breakdown because the current Go-node-only scope would no longer be valid.

## reviewer findings

Sufficiency: sufficient with adjustments already applied.

Missing files, tests, regressions, or gates: none remaining. The targeted command now names the required new table-driven test directly, and `go test ./node` is included as the full module-local gate.

Stale or incorrect assumptions: none found. The plan is grounded in the current validator calls, direct tests, `go.mod` replacement, and forked PubSub `Message` API.

Overengineering: none found. The production plan changes only the origin id passed to two existing helper calls and avoids PubSub fork, Flutter, transport, schema, and diagnostics redesign.

Decomposition: sufficient. The RED tests isolate forwarding source, author/envelope forgery, and device-bound forwarding before a two-call-site production change.

Minimum needed to remain sufficient: keep the new test name fixed as `TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages`, run the RED command before production edits, and stop if the RED test does not fail before the fix.

## arbiter decision

Structural blockers: none.

Incremental details: none required before execution. Optional future cleanup, such as adding signed-author hashes to rejection diagnostics, is intentionally not part of this session.

Accepted differences:

- Keep the pure helper `validateGroupEnvelopeForTransportPeer` as an explicit-origin unit-test seam.
- Keep `pid` available for existing rejection diagnostics while using `msg.GetFrom()` for transport and device binding.
- Keep the PubSub fork unchanged; the repo-local fork already exposes the required `Message.GetFrom()` author and `ReceivedFrom` forwarding source distinction.

Stop rule outcome: no structural blocker remains, so planning stops here and the artifact is execution-ready.

## historical final planning output

Final planning verdict: execution-ready at planning time; superseded by the `executed-accepted` closure state above.

Final plan: add RED-first live-validator coverage for forwarded author acceptance, forged author/envelope rejection, and device-bound forwarded acceptance; then make the minimum production change in `go-mknoon/node/pubsub.go` so both existing binding helper calls receive the `msg.GetFrom()` origin id instead of callback `pid`.

Structural blockers remaining: none.

Incremental details intentionally deferred: diagnostic wording/hash improvements and broader fixture cleanup.

Accepted differences intentionally left unchanged: no Flutter/Dart work, no libp2p fork work, no transport redesign, no schema/signature redesign, and no network integration gate.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/go.mod`
- `go-mknoon/third_party/go-libp2p-pubsub/pubsub.go`
- `go-mknoon/third_party/go-libp2p-pubsub/validation.go`
- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`

Why the plan is safe to implement now: it has a narrow Go-only scope, explicit RED-first regressions for the confirmed forwarded-origin bug, exact targeted and full `go test ./node` commands, a clear closure bar, and scope guards preventing Flutter, PubSub fork, transport, schema, or diagnostics redesign.

## final execution verdict

Final verdict: executed-accepted.

What landed:

- Production changed only `go-mknoon/node/pubsub.go`: `Node.groupTopicValidator` now derives `originTransportPeerId := msg.GetFrom().String()` and falls back to `pid.String()` only when `msg.GetFrom()` is empty, then passes `originTransportPeerId` to `groupEnvelopeMatchesTransportPeer` and `activeMemberDeviceForEnvelope`.
- Tests changed only `go-mknoon/node/pubsub_test.go`: added `TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages` covering forwarded author accept, forged author/envelope mismatch reject, and device-bound forwarded accept.

RED evidence:

- Before the production fix, the targeted command failed as expected: `forwarded_author_transport_match_accepts` and `forwarded_device_bound_author_accepts` returned `ValidationReject`; the forged author/envelope mismatch case stayed rejected.

Post-fix passed commands:

```sh
cd go-mknoon && go test ./node -count=1 -run 'TestSV004ForgedSenderIdentityOrSignatureRejectsWithSafeDiagnostics|TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice|TestGroupTopicValidator_DeviceRejectsUnboundSibling'
```

Result: passed locally with `ok github.com/mknoon/go-mknoon/node 0.469s`.

```sh
git diff --check -- go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md
```

Result: passed locally.

Classified full-node result:

- `cd go-mknoon && go test ./node` remains red after the GPF-001 fix.
- Current post-fix log `/tmp/gpf001-go-test-node-postfix.log` shows remaining failures: `GI012`-`GI016`, `GA019`, `GA021`, and `GM028`.
- A clean detached HEAD worktree at `/tmp/gpf001-base-worktree` reproduced the same remaining failing subset, so those failures are classified as pre-existing and unrelated to GPF-001.
- The earlier related `SV004` failure from the first implementation was fixed by the empty-author fallback, and the focused `SV004` rerun passed.

## final QA verdict

Read-only QA verdict: accepted. The implementation is minimum-code, limited to the intended Go validator and direct Go regression test, and shows no scope drift into Flutter, relay, PubSub fork, schema, diagnostics redesign, or unrelated tests.

Read-only failure-classifier verdict: accepted. `SV004` was related to the first implementation and is fixed; remaining full-node failures are unrelated/pre-existing and reproduced at clean HEAD.

Closure reviewer verdict: accepted. The docs now record the actual landed behavior, exact passed commands, accepted difference, and residual-only full-node gate state without reopening broader product work.

## accepted differences and residual-only state

Accepted architectural difference:

- The implementation keeps an empty-author fallback to `pid.String()` for handcrafted or legacy no-author validator inputs. This preserves existing direct/no-author validation behavior and does not weaken the non-empty forwarded-author runtime path because forwarded messages with `msg.GetFrom()` still bind transport and device checks to the signed PubSub author.

Residual-only items:

- Full `cd go-mknoon && go test ./node` remains red only on pre-existing unrelated failures reproduced at clean HEAD: `GI012`-`GI016`, `GA019`, `GA021`, and `GM028`.

Still-open items for GPF-001: none.

Maintenance-time safety:

- Reopen GPF-001 only if the forwarded PubSub author regression returns: valid Alice-authored messages forwarded by Carol reject, forged author/envelope mismatches accept, or device-bound forwarded authors stop binding to the active device transport id.
- The maintenance check for this behavior is the passed combined targeted command above, plus `git diff --check` for the changed files.
