Status: execution-ready

# LP-002 PubSub Authorization Before Accept Or Forward Plan

## Planning Progress

- 2026-04-30 20:56:24 CEST - Evidence Collector started. Files inspected since last update: `libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, `libp2p_group_chat_missing_test_matrix_full_with_rules.md`, `test-inventory.md`, existing LP-002 plan path check, `git status --short`. Decision/blocker: LP-002 is confirmed as `Partial`, `repo_external_proof`, `evidence-gated`; no prior LP-002 plan file exists; dirty tree contains unrelated existing edits that must be preserved. Next action: inspect LP-002 owner files, current Go tests, and gate definitions before drafting.
- 2026-04-30 20:59:23 CEST - Evidence Collector completed; Planner started. Files inspected since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/rendezvous.go`, `go-mknoon/node/node.go`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge`, `go-mknoon/cmd/testpeer`, `go-mknoon/third_party/go-libp2p-pubsub/validation.go`, `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md`, directly relevant integration-test harness list. Decision/blocker: existing repo evidence proves validator rejection before decrypted payload handling, but not live three-peer forward suppression, explicit scored-router behavior, or rate-limited privacy-safe diagnostics. Next action: draft an evidence-gated execution plan that starts with repo-owned proof and implements only observed gaps.
- 2026-04-30 21:01:13 CEST - Planner completed; Reviewer completed. Files inspected since last update: drafted LP-002 plan content and mandatory-section checklist. Decision/blocker: plan is sufficient with adjustments; tighten the attacker publish mechanism, device/proof profile, and failure classification before arbiter. Next action: apply reviewer adjustments and run arbiter classification.
- 2026-04-30 21:02:01 CEST - Arbiter completed. Files inspected since last update: reviewer-adjusted LP-002 plan. Decision/blocker: no structural blockers; deferred items are implementation details or accepted differences; plan is execution-ready. Next action: run scoped `git diff --check` for the touched plan file only.

## Final Verdict

Final verdict: LP-002 is execution-ready as an evidence-gated, implementation-committed closure session. The next execution should add or collect repo-owned proof first, then implement only the exact behavior gap exposed by that proof. It must not be treated as acceptance-only while the source row remains `Partial`.

## Final Plan

### real scope

LP-002 owns only PubSub authorization before local accept or network forward for group topics. The session may touch Go PubSub validation, Go-only diagnostics/trace plumbing, and focused tests that prove unauthorized member, removed-member, and stale-sender traffic is rejected before app callbacks, decrypted payload parsing, or forwarding.

The expected next execution path is:

1. Add repo-owned Go proof for the remaining LP-002 gaps.
2. If the proof passes against existing behavior, update closure docs with the new evidence and do not edit production code.
3. If the proof fails, implement the smallest Go-layer behavior needed for the observed failure, then rerun the same proof and gates.

This session does not own group membership convergence, invite authorization, key epoch repair, offline inbox authorization, push payload privacy, broad diagnostics export, relay backend storage rules, or Flutter UI behavior except for a minimal bridge/diagnostics assertion if Go emits a new owned diagnostic event.

### closure bar

LP-002 is good enough only when the repo has direct evidence that unauthorized group PubSub traffic:

- returns `pubsub.ValidationReject` before decrypted payload handling for message, reaction, membership, metadata, and key-rotation payload shapes;
- is not delivered to `handleGroupSubscription`, does not emit `group_message:received` or `group_reaction:received`, and does not mutate group state;
- is not forwarded from an intermediate subscribed peer to a third subscribed peer in a three-peer topology where the attacker can reach the intermediate peer but not the final peer directly;
- has explicit peer-score behavior proven at the level the product actually enables: either production-enabled scoring is observed, or a scored vendored `go-libp2p-pubsub` harness proves `ValidationReject` produces `RejectValidationFailed` and a score penalty while the matrix/inventory records that production currently does not configure app-specific peer score parameters;
- emits, records, or intentionally documents privacy-safe reject diagnostics that are bounded under repeated unauthorized attempts. Covered closure requires a test that the diagnostic/log path excludes plaintext, ciphertext, nonce, keys, group name/description, full multiaddrs, and raw envelope data, and enforces a rate limit or aggregation contract.

If live device/relay proof is unavailable, the row may still gain host/raw-protocol evidence, but it must not claim live relay/device closure. If peer-score or diagnostics remain unimplemented or unproved, the source row must stay `Partial` with the exact remaining gap.

### source of truth

- Current Go code and tests are authoritative for behavior.
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md` is authoritative for LP-002 row status and closure wording.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` is authoritative for inventory evidence.
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md` is authoritative for row disposition, ordering, and plan path.
- `Test-Flight-Improv/test-gate-definitions.md` defines named gates, but `scripts/run_test_gates.sh` wins on any command disagreement.
- `go-mknoon/third_party/go-libp2p-pubsub/validation.go` is authoritative for the vendored PubSub validation semantics used by this repo, not the upstream internet docs.

### session classification

`evidence-gated`

The row is `repo_external_proof`, but current repo evidence is incomplete. The next session should collect/add repo-owned Go raw-protocol evidence first, then implement missing behavior only if that evidence exposes a real forwarding, scoring, or diagnostics gap.

### exact problem statement

LP-002 is still `Partial` because the repo proves the validator rejects removed or non-member senders before decrypted payload handling, but does not directly prove the full user-risk boundary: an unauthorized peer must not cause another member to accept, forward, score incorrectly, or emit unsafe/unbounded diagnostics.

The user-visible behavior that must improve is confidence that removed, stale, or non-member devices cannot inject or propagate group messages, reactions, metadata changes, membership changes, or key-rotation events through PubSub after removal. Existing valid member send, receive, reaction, key, rendezvous, and group inbox behavior must stay unchanged.

### files and repos to inspect next

Production and vendored behavior:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/events.go`
- `go-mknoon/third_party/go-libp2p-pubsub/validation.go`
- `go-mknoon/third_party/go-libp2p-pubsub/score.go`

Direct tests and harnesses:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/protocol_version_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/cmd/testpeer`
- `integration_test/transport_e2e_test.dart`
- `integration_test/group_multi_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`

Docs to update only during closure execution:

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- this LP-002 plan, and the breakdown ledger only after execution reaches a truthful closure state

### existing tests covering this area

- `go-mknoon/node/pubsub_test.go` includes `TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward`, which calls the real `groupTopicValidator` and proves a removed/non-member sender is rejected for group message, reaction, membership, metadata, and key-rotation payload shapes.
- `go-mknoon/node/pubsub_test.go` includes adjacent validator tests for invalid signatures, added/removed members after config updates, announcement write authorization, empty member lists, and accepted listed members.
- `go-mknoon/node/pubsub_delivery_test.go` covers live member publish and receive behavior, topic peer counts, warm retry for missing known members, and duplicate message delivery visibility.
- `go-mknoon/node/pubsub_decryption_failure_test.go` covers decrypt and parse failures after authorization, and proves those failures emit diagnostics instead of fake group message callbacks.
- `go-mknoon/third_party/go-libp2p-pubsub/validation.go` states that `ValidationAccept` is delivered and forwarded, while `ValidationReject` is not delivered or forwarded and should be penalized by peer scoring routers.

Missing coverage:

- no LP-002-owned live three-peer topology proves an intermediate member rejects and suppresses forwarding to a third peer;
- no production or test-only scored-router assertion proves what happens to the unauthorized peer score;
- no focused proof shows validator reject diagnostics are privacy-safe and rate-limited under repeated unauthorized sends.

### regression/tests to add first

Add proof before production edits. Suggested test names are intentionally exact so execution can use narrow `go test -run` gates:

- `TestGroupTopicValidator_LiveThreePeerRejectDoesNotReachOrForward` in `go-mknoon/node/pubsub_delivery_test.go`: build a three-node topology with attacker X connected to member B, member B connected to member C, and no X-to-C connection. Because production `PublishGroupMessage` correctly rejects local non-member publishes, either give X a local-only stale config that includes itself while B/C use the current config that excludes X, or publish the crafted v3 envelope through X's raw topic handle in the test harness. The envelope sender must match X's transport peer id so the test proves the non-member path, not the sender/transport mismatch path. Assert B receives no `group_message:received` or `group_reaction:received`, C receives no event, and any raw tracer or test subscription evidence shows B rejected without forwarding.
- `TestGroupTopicValidator_RejectPenalizesScoredPeerWhenPeerScoringEnabled` in a Go PubSub-focused test: use the vendored PubSub scored-router APIs or a narrow test hook to prove `ValidationReject` maps to `RejectValidationFailed` and a negative invalid-message score when scoring is enabled. Do not claim production scoring if production `initPubSub` still does not configure `WithPeerScore`.
- `TestGroupTopicValidator_RejectDiagnosticsArePrivacySafeAndRateLimited` in `go-mknoon/node/pubsub_test.go` or a small diagnostics-focused Go test: burst repeated unauthorized envelopes and assert the observable diagnostic/log contract uses reason codes/counts, redacts sensitive material, and emits at a bounded cadence.

If these tests pass without production changes, close with evidence only. If one fails, implement only the failed seam.

### step-by-step implementation plan

1. Reconfirm the LP-002 row is still `Partial` and no other worker already added an LP-002 closure plan or tests.
2. Inspect current diffs in the LP-002 owner files before editing. Preserve unrelated dirty-tree changes and avoid reverting existing source or doc edits.
3. Add the three-peer live suppression proof first. Prefer existing local-node helpers in `pubsub_delivery_test.go` and `group_security_harness_test.go`; keep topology explicit so X is not directly connected to C.
4. Run the direct LP-002 Go proof command. If live suppression passes, record that evidence. If it fails because B forwards or emits app events, patch `go-mknoon/node/pubsub.go` or `go-mknoon/node/node.go` narrowly so validation rejects before delivery/forward in the observed path, then rerun.
5. Add peer-score proof. If production scoring is not configured, do not enable broad peer scoring just to satisfy the row unless the test proves the absence creates a concrete abuse or forwarding gap. Instead, prove the vendored scored-router behavior and record production scoring as an accepted current architecture difference unless the row owner decides production scoring is required.
6. Add diagnostics proof. If current logging is unbounded or leaks sensitive material, implement a small Go-layer reject diagnostic helper or rate limiter near the validator path. Keep output to reason, group/topic identifier or safe fingerprint, optional short peer fingerprint, count, and window; never include plaintext, ciphertext, nonce, keys, raw envelope, group name/description, or multiaddrs.
7. If a new diagnostic crosses the bridge, add the narrow bridge event test and, only if needed, the directly relevant Flutter diagnostics listener test. Do not touch group UI.
8. Run focused Go tests, then broad Go group/raw-protocol tests, then canonical group gates when source changed.
9. Update LP-002 source matrix and test inventory only after tests pass, with exact commands and whether closure is `Covered`, still `Partial`, or fixture-blocked. Update the breakdown ledger only if execution reaches a true planning/execution progress or closure note.
10. Stop if evidence shows the remaining gap is only unavailable live device/relay fixture. Do not fabricate closure from skipped or unconfigured device runs.

### risks and edge cases

- GossipSub mesh formation is nondeterministic. The three-peer test must force or verify the connection graph before publish so a direct X-to-C path cannot hide forwarding.
- `WithFloodPublish(true)` intentionally sends to all connected peers for valid messages. The regression must prove invalid messages are rejected before that forwarding path, not weaken valid member fanout.
- Validator rejection happens before decryption, so tests should assert no decrypt, parse, or app callback side effects rather than only checking return codes.
- Peer-score behavior depends on whether scoring is enabled. Vendored library semantics are useful evidence, but production score claims require production configuration or explicit doc wording that no production peer score is configured.
- Repeated unauthorized sends can become a log/diagnostic flood. A privacy-safe diagnostic that is not rate-limited does not close LP-002.
- Existing dirty source edits in the worktree may affect Go behavior. Execution must inspect diffs before patching and must not revert unrelated worker changes.

### device/relay/proof profile

Required local proof profile:

- Host-only Go raw-protocol proof is the primary LP-002 closure path. It should use local libp2p hosts or raw topic publishing to avoid depending on external relay availability.
- The three-peer proof must use a chain topology, X -> B -> C, and must assert no X -> C connection exists before the unauthorized publish.
- The diagnostic proof can be host-only if it exercises the same validator path used by production `JoinGroupTopic`.

Supporting real-stack profile:

- `group-real-network-nightly` is supporting evidence when a configured device and relay addresses are available. It is not a substitute for the row-owned raw proof because the current gate runs `integration_test/multi_relay_failover_test.dart`, not a dedicated LP-002 unauthorized-forward test.
- `integration_test/scripts/run_group_multi_device_real.dart` is optional paired-device evidence if execution adds an LP-002 harness role or can adapt the existing CLI peer fixture without broadening scope.

Unavailable fixture handling:

- Missing `FLUTTER_DEVICE_ID`, empty `MKNOON_RELAY_ADDRESSES`, no paired device, or unreachable relay is `fixture-unavailable`. It blocks live-device or relay claims only.
- A fixture-unavailable result must leave the row `Partial` if live/relay evidence is the only missing closure item. It must not fail host-only proof and must not be recorded as a pass.

### failure/blocker classification

- `direct-lp002-proof-red`: any failure in the direct LP-002 Go proof command. Treat as session-owned and implement the smallest fix for the observed PubSub authorization, forwarding, scoring, or diagnostics gap.
- `diagnostics-contract-red`: unauthorized traffic is rejected, but diagnostics/logs leak sensitive material or are unbounded. Treat as session-owned; implement only bounded privacy-safe reject diagnostics.
- `peer-score-unavailable`: production has no peer-score configuration and only vendored scored-router proof exists. This is not a code failure by itself, but it prevents overclaiming production score behavior unless the matrix/inventory records the accepted architecture difference.
- `fixture-unavailable`: configured device, paired device, or relay evidence could not run. Do not mark Covered from this; keep the missing live proof explicit.
- `broad-gate-unrelated-red`: broad group or Flutter integration gate fails outside LP-002 after the direct proof passes. Preserve the failure details and route to the owning row; do not patch unrelated code in LP-002 execution.

### exact tests and gates to run

Direct LP-002 proof commands:

```bash
cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward|TestGroupTopicValidator_LiveThreePeerRejectDoesNotReachOrForward|TestGroupTopicValidator_RejectPenalizesScoredPeerWhenPeerScoringEnabled|TestGroupTopicValidator_RejectDiagnosticsArePrivacySafeAndRateLimited' -count=1 -v
```

Raw-protocol and adjacent Go evidence:

```bash
cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -count=1 -v
```

If bridge diagnostics or `cmd/testpeer` are touched:

```bash
cd go-mknoon && go test ./bridge ./cmd/testpeer -run 'Group|PubSub|Diagnostics|Inbox' -count=1 -v
```

Canonical group gates when Go or bridge behavior changes:

```bash
./scripts/run_test_gates.sh groups
flutter test --no-pub test/features/groups/integration
```

Device/relay proof profile:

```bash
FLUTTER_DEVICE_ID=<device-id> MKNOON_RELAY_ADDRESSES=<comma-separated-relay-multiaddrs> ./scripts/run_test_gates.sh group-real-network-nightly
```

Optional two-device/CLI real-stack proof when a paired device lab is available:

```bash
dart run integration_test/scripts/run_group_multi_device_real.dart -d <primary-device-id>,<sibling-device-id>
```

Hygiene after all touched files:

```bash
git diff --check -- go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_delivery_test.go go-mknoon/node/node.go go-mknoon/bridge go-mknoon/cmd/testpeer Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-002-plan.md
```

For this planning pass only, run the scoped doc hygiene command:

```bash
git diff --check -- Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-002-plan.md
```

### known-failure interpretation

No LP-002-specific known red test was identified during planning. A failure in the direct LP-002 Go command is session-owned until proven otherwise.

Failures in broad Flutter group gates or unrelated Go tests must be triaged against the current dirty tree and source row ownership. If the direct LP-002 command passes and a broad gate fails outside PubSub authorization, forwarding, score, or diagnostics, record it as unrelated/pre-existing only with the exact failing test and owning row. A missing `FLUTTER_DEVICE_ID` or empty `MKNOON_RELAY_ADDRESSES` for `group-real-network-nightly` is fixture-unavailable evidence, not a product pass or fail.

### done criteria

- The direct LP-002 Go proof command passes with live three-peer suppression, peer-score behavior, and diagnostics privacy/rate-limit evidence included or explicitly narrowed.
- Valid member PubSub send, receive, reaction, key, and group integration behavior still passes through the broad Go and group gates listed above.
- Source matrix LP-002 and test inventory LP-002 are updated with exact evidence and truthful status. Move to `Covered` only if all closure-bar items are proven. Leave `Partial` if live device/relay, production peer-score, or diagnostics proof remains missing.
- Any production change is limited to LP-002 owner files and is justified by a failing proof.
- `git diff --check` passes for all touched files.

### scope guard

Do not:

- edit production code during the planning pass;
- broaden into invite authorization, offline inbox authorization, ban semantics, key repair, relay storage policy, diagnostics export, push notifications, or Flutter UI;
- enable a broad peer scoring policy without evidence that production requires it for LP-002 closure;
- weaken valid group fanout or `WithFloodPublish(true)`;
- claim live-device or relay closure from skipped, unconfigured, or unavailable fixture runs;
- mark the row acceptance-only or stale while the source row remains `Partial`.

### accepted differences / intentionally out of scope

- The row is about group PubSub. Direct 1:1 stream protocols and group offline inbox authorization are separate rows.
- Production currently initializes GossipSub with `WithFloodPublish(true)` and no explicit peer-score options in the inspected `initPubSub`; proving vendored scored-router behavior is acceptable evidence only if the matrix/inventory also records that production scoring is not currently configured.
- `group:decryption_failed` and `group:payload_parse_failed` diagnostics cover post-authorization malformed or undecryptable payloads. They do not close pre-authorization reject diagnostics by themselves.
- Real device/relay evidence is valuable supporting proof, but host/raw-protocol evidence can still narrow LP-002 if device fixtures are unavailable. The source row must state exactly what remains unproved.

### dependency impact

LP-002 sits early in the P0 libp2p topology/security block. LP-003, LP-011, LP-013, SP-001, SP-002, ER-001, and broader diagnostics rows may rely on LP-002 evidence to avoid reopening base PubSub authorization. If LP-002 discovers missing production scoring or diagnostics primitives, later security/diagnostics plans should reuse that narrow primitive instead of inventing separate reject telemetry.

If LP-002 remains `Partial` because live fixtures or production peer-score policy are unavailable, later rows may still proceed but must not cite LP-002 as complete live authorization proof.

## Structural Blockers Remaining

Arbiter result: no structural blockers remaining.

## Incremental Details Intentionally Deferred

- Exact raw tracer implementation details are deferred to execution because the existing local-node helpers already provide a viable starting point.
- Exact diagnostic event naming is deferred until execution proves whether a new diagnostic helper is needed.

## Accepted Differences Intentionally Left Unchanged

- Production peer scoring is not configured in inspected `initPubSub`; this plan does not require enabling broad scoring unless evidence shows it is necessary for LP-002 closure.
- Device/relay proof remains supporting unless a dedicated LP-002 unauthorized-forward live harness is added.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/events.go`
- `go-mknoon/cmd/testpeer`
- `go-mknoon/third_party/go-libp2p-pubsub/validation.go`
- `go-mknoon/third_party/go-libp2p-pubsub/score.go`
- `integration_test/group_multi_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`

## Why The Plan Is Safe Or Unsafe To Implement Now

Arbiter safety verdict: safe to implement now. The plan starts with observable proof, preserves valid group behavior, avoids production edits unless proof fails, and prevents overclaiming when live device or relay fixtures are unavailable.
