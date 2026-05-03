# LP-002 Session Plan - PubSub Authorization Before Accept Or Forward

Status: execution-ready

## Planning Progress

- 2026-04-30T21:09:42Z - Evidence Collector started. Files inspected since last update: `implementation-plan-orchestrator/SKILL.md`, `git status --short`. Decision/blocker: LP-002 row and intended plan path are confirmed; worktree already has user-owned changes, so this pass will only edit this plan artifact. Next action: inspect row docs, current PubSub authorization code/tests, gate definitions, and live device/relay availability.
- 2026-04-30T21:12:58Z - Evidence Collector completed; Planner started. Files inspected since last update: source matrix LP-002 row, session breakdown LP-002 entry, `test-inventory.md`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/config.go`, `go-mknoon/cmd/testpeer/commands.go`, `integration_test/scripts/run_group_multi_device_real.dart`, `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md`. Device checks run: `flutter devices --machine`, `xcrun simctl list devices available`, `adb devices`, `$HOME/Library/Android/sdk/platform-tools/adb devices`, `printenv MKNOON_RELAY_ADDRESSES`, `printenv MKNOON_RELAY_ADDR`. Decision/blocker: current repo has pure validator proof but lacks live three-peer forward suppression, app-owned peer-score configuration/proof, and rate-limited privacy-safe authorization diagnostics; local device inventory is sufficient for host/simulator support but multi-relay env is unset. Next action: draft a row-owned proof-first implementation plan with device/relay profile and exact gates.
- 2026-04-30T21:16:52Z - Planner completed; Reviewer started. Files inspected since last update: draft plan content only. Decision/blocker: draft contains all mandatory sections and a Device/Relay Proof Profile; review focus is closure sufficiency, peer-score handling, diagnostics exactness, and scope drift. Next action: apply reviewer sufficiency check.
- 2026-04-30T21:16:52Z - Reviewer completed; Arbiter started. Files inspected since last update: draft plan content only. Decision/blocker: sufficient with adjustments; no structural blocker found, but diagnostics rate limiting needed a concrete assertion to prevent vague implementation. Next action: arbitrate review finding and finalize or patch once.
- 2026-04-30T21:17:41Z - Arbiter completed. Files inspected since last update: reviewer-adjusted plan content only. Decision/blocker: no structural blockers remain; peer-score enablement is an accepted out-of-scope architecture difference unless later evidence proves it required. Next action: execute this plan in a separate implementation session.

## Execution Progress

- 2026-04-30T21:19:25Z - Contract extraction starting. Files inspected or touched: this LP-002 plan, `implementation-execution-qa-orchestrator/SKILL.md`, `git status --short`. Command currently running: none. Decision/blocker: plan is present and execution-ready; dirty worktree contains pre-existing GL-005/doc/test changes that must be preserved. Next action: extract exact LP-002 execution contract before coding.
- 2026-04-30T21:20:11Z - Contract extracted. Files inspected or touched: this LP-002 plan, `implementation-execution-qa-orchestrator/SKILL.md`, `git status --short`, Codex CLI help. Command currently running: none. Decision/blocker: scope is LP-002 only; add proof-first Go tests in a new `go-mknoon/node/*_test.go` file, patch only PubSub validator-adjacent diagnostics if tests expose a gap, preserve dirty GL-005/doc/test changes, do not update source matrix/test inventory/breakdown ledger, run focused Go tests, owner Go suite as feasible, applicable gates only if Dart-visible behavior changes, and `git diff --check`. Next action: spawn the Executor agent with model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-04-30T21:20:30Z - Executor spawn starting. Files inspected or touched: this LP-002 plan. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -s danger-full-access -a never -C /Users/I560101/Project-Sat/mknoon-2/flutter_app`. Decision/blocker: no blocker; spawned Executor will own implementation/test pass only. Next action: wait for Executor result, then spawn QA Reviewer.
- 2026-04-30T21:21:06Z - Executor spawn retry. Files inspected or touched: this LP-002 plan. Command currently running: corrected `codex -a never -s danger-full-access -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" exec -C /Users/I560101/Project-Sat/mknoon-2/flutter_app`. Decision/blocker: first spawn command failed before child work because `-a` was placed after `exec`; no child code/test/doc delta occurred. Next action: retry Executor spawn with corrected top-level approval flag.
- 2026-04-30T21:21:43Z - Executor spawned/running. Files inspected or touched: this LP-002 plan. Command currently running: `codex -a never -s danger-full-access -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" exec -C /Users/I560101/Project-Sat/mknoon-2/flutter_app -o /tmp/lp002-executor-result.md -` (session `019de044-bd2e-7d82-bab7-b2ffdf1ca022`). Decision/blocker: spawned Executor materialized successfully; waiting for implementation/test handoff evidence. Next action: inspect Executor result and repo delta before spawning QA.
- 2026-04-30T21:22:00Z - Executor attached and starting implementation pass. Files inspected or touched: this LP-002 plan. Command currently running: none. Decision/blocker: plan read; scope is limited to LP-002 Go proof tests and minimal validator diagnostics if exposed by those tests, with closure docs reserved for a later agent. Next action: inspect dirty worktree and current PubSub implementation/test helpers before editing.
- 2026-04-30T21:23:03Z - Executor inspection in progress. Files inspected or touched: this LP-002 plan, `implementation-execution-qa-orchestrator/SKILL.md`, `git status --short`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/` listing. Command currently running: none. Decision/blocker: dirty worktree includes unrelated GL-005/doc/test deltas; existing helpers cover local node startup, raw envelope publish, peer waits, and event collection. Next action: add a new LP-002 Go test file without editing dirty helper files.
- 2026-04-30T21:25:45Z - Executor spawn closed for no-progress fallback. Files inspected or touched: this LP-002 plan, `git status --short`, `go-mknoon/node/` listing, LP-002 search results. Command currently running: none. Decision/blocker: spawned Executor produced inspection/progress notes but no code/test delta or trustworthy handoff after the bounded wait extension; classified as `spawn_or_tool_failure` for nested Executor materialization. Next action: use the local sequential fallback in this already-dedicated LP-002 execution context, starting with the Executor responsibilities.
- 2026-04-30T21:28:26Z - Local fallback Executor running. Files inspected or touched: this LP-002 plan, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/node_test.go`, `go-mknoon/node/benchmark_harness_test.go`. Command currently running: none. Decision/blocker: existing helpers are sufficient; production patch, if needed, will stay limited to validator diagnostics and Node diagnostic state. Next action: add the LP-002 test file and minimal diagnostics helper.
- 2026-04-30T21:31:13Z - Local fallback Executor implementation pass completed; focused test starting. Files inspected or touched: `go-mknoon/node/pubsub_authorization_forward_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, this LP-002 plan. Command currently running: `cd go-mknoon && go test ./node -run 'TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward|TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited|TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward' -v`. Decision/blocker: added live X-B-C raw PubSub proof and privacy-safe/rate-limited diagnostics proof; diagnostics helper hashes identifiers and rate-limits repeated validator rejects without changing validation returns. Next action: record focused test result.
- 2026-04-30T21:32:07Z - Focused test failed; Executor fix in progress. Files inspected or touched: `go-mknoon/node/pubsub_authorization_forward_test.go`, `go-mknoon/node/pubsub.go`, this LP-002 plan. Command finished: `cd go-mknoon && go test ./node -run 'TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward|TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited|TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward' -v` failed. Decision/blocker: live X-B-C test passed; diagnostics test used a synthetic non-canonical peer ID and hit `peer_mismatch` before `non_member`, so test data must use generated canonical peer IDs for the intended non-member authorization path. Next action: patch diagnostics test data and rerun the focused command.
- 2026-04-30T21:33:19Z - Focused test passed; owner Go suite starting. Files inspected or touched: `go-mknoon/node/pubsub_authorization_forward_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, this LP-002 plan. Command finished: `cd go-mknoon && go test ./node -run 'TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward|TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited|TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward' -v` passed. Decision/blocker: LP-002 focused proof is green after decoding generated peer IDs before validator calls. Next action: run `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v`.
- 2026-04-30T21:34:34Z - Owner Go suite failed; failure classification in progress. Files inspected or touched: this LP-002 plan. Command finished: `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` failed. Decision/blocker: visible failure includes dirty-worktree bridge test `TestGroupPublish_ResponseIncludesTopicPeers` rejecting a sender/transport peer mismatch, which is not a return-path change from LP-002 diagnostics; full package-level failure inventory is needed because output was truncated. Next action: rerun package slices and record precise failures.
- 2026-04-30T21:36:39Z - Owner Go suite classified; diff check starting. Files inspected or touched: `/tmp/lp002-node-owner.log`, `/tmp/lp002-bridge-owner.log`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/node/pubsub.go`, this LP-002 plan. Commands finished: `cd go-mknoon && go test ./node -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` failed only at `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers`; `cd go-mknoon && go test ./bridge -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` failed only at `TestGroupPublish_ResponseIncludesTopicPeers`; `cd go-mknoon && go test ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` passed. Decision/blocker: both failures publish with sender IDs that do not match the local libp2p transport peer; the peer-mismatch rejection condition existed before LP-002 and the LP-002 patch only changes diagnostics/logging around unchanged reject returns. Classified as unrelated pre-existing owner-suite failures in the current dirty worktree. Flutter `groups` gate not required because no Dart-visible behavior or bridge contract was changed. Next action: run `git diff --check`.
- 2026-04-30T21:37:13Z - Diff check passed; local fallback QA starting. Files inspected or touched: this LP-002 plan. Command finished: `git diff --check` passed. Decision/blocker: no whitespace/errors in diff. Next action: perform QA sufficiency review for scope adherence, required tests, gate evidence, and remaining blockers.
- 2026-04-30T21:38:01Z - Local QA found test-quality fix; local fix pass starting. Files inspected or touched: `go-mknoon/node/pubsub_authorization_forward_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, this LP-002 plan. Command currently running: none. Decision/blocker: no behavior blocker, but QA found the diagnostics log capture should be safe while PubSub goroutines write and the privacy assertion should include the second sender's envelope fields after that sender logs. Next action: patch the LP-002 test helper/assertions, rerun focused tests and `git diff --check`, then perform final QA.
- 2026-04-30T21:38:59Z - Local fix pass completed; final QA starting. Files inspected or touched: `go-mknoon/node/pubsub_authorization_forward_test.go`, this LP-002 plan. Commands finished: `cd go-mknoon && go test ./node -run 'TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward|TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited|TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward' -v` passed; `git diff --check` passed. Decision/blocker: LP-002 focused proof remains green after test-helper tightening. Next action: perform final QA and write final execution verdict.
- 2026-04-30T21:39:42Z - Final QA completed; final verdict work starting. Files inspected or touched: `go-mknoon/node/pubsub_authorization_forward_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `/tmp/lp002-node-owner.log`, `/tmp/lp002-bridge-owner.log`, this LP-002 plan. Command currently running: none. Decision/blocker: LP-002 scope, tests, diagnostics, and primary host-only three-node proof are sufficient; owner-suite residual failures are documented as pre-existing sender/transport mismatch tests outside the LP-002 diagnostics change. Next action: write final execution verdict.
- 2026-04-30T21:40:08Z - Final execution verdict written. Files inspected or touched: this LP-002 plan. Command currently running: none. Decision/blocker: `accepted`; no LP-002 blocking issues remain. Next action: stop and report files changed plus test/gate results.
- 2026-04-30T21:40:59Z - Post-verdict diff check passed. Files inspected or touched: this LP-002 plan. Command finished: `git diff --check` passed after final verdict doc update. Decision/blocker: no whitespace/errors. Next action: final response.

## real scope

This session owns LP-002 only: unauthorized PubSub group envelopes from a non-member, stale member, or removed member must be rejected before local state mutation, before decrypted payload handling, and before any downstream forward path can deliver the message to another peer.

In scope:

- Add row-owned Go proof for a live X-B-C PubSub topology where X has stale local group state and publishes unauthorized `group_message`, `group_reaction`, membership, metadata, and key-rotation payload shapes.
- Prove B rejects before emitting `group_message:received`, `group_reaction:received`, `group:payload_parse_failed`, or `group:decryption_failed`.
- Prove C does not receive X's payload through B when C has no direct connection to X.
- Add privacy-safe, rate-limited authorization reject diagnostics if the first proof shows current logging is not sufficient for LP-002.
- Add repo code only in LP-002 owner files when a proof fails or when diagnostic requirements are demonstrably missing.
- Update the source matrix row and `test-inventory.md` only after concrete file-and-test evidence exists.

Out of scope:

- Broad group governance, role matrices, invite revocation, packet-capture tooling, relay architecture, app UI changes, push behavior, offline inbox semantics, key repair, or transport bootstrap modernization.
- Enabling or tuning production GossipSub peer scoring unless current LP-002 proof shows that rejection-before-forward cannot be closed without it. Current evidence found no app-owned `WithPeerScore` configuration.

## closure bar

LP-002 is good enough when repo-owned evidence proves all of the following:

- The real Go `groupTopicValidator` rejects removed or non-member senders for message, reaction, membership, metadata, and key-rotation payload shapes with `pubsub.ValidationReject`.
- A live three-node raw-Go PubSub topology proves unauthorized traffic is not locally accepted on the first authorized receiver and is not forwarded through that receiver to another authorized peer.
- No rejected unauthorized payload is decrypted, parsed into app state, or emitted as a normal group message/reaction event.
- Authorization reject diagnostics contain no plaintext payload, group name, public key, private key, encrypted body, nonce, signature, or full transport multiaddr, and repeated rejects from the same sender/group/reason are rate-limited.
- Any app-owned peer-score claim is either directly proven or explicitly marked non-applicable because this repo does not configure GossipSub peer scoring.
- The source matrix row moves to `Closed` or `Covered` only with the exact test files, test names, and passing commands recorded.

## source of truth

- Current code and tests win over stale prose.
- `scripts/run_test_gates.sh` wins when named gate membership conflicts with `Test-Flight-Improv/test-gate-definitions.md`.
- LP-002 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md` is the acceptance contract.
- The LP-002 session breakdown entry controls the session boundary and allows repo code/tests only if proof exposes a gap.
- `test-inventory.md` is the current coverage inventory and already states why LP-002 remains Partial.

## session classification

evidence-gated

This is not acceptance-only or doc-only. The session must add proof first, then implement the smallest repo-owned fix if that proof exposes a gap. Current intake already shows at least one likely implementation gap: rate-limited privacy-safe authorization diagnostics are not directly implemented or tested.

## exact problem statement

LP-002 currently has partial validator proof in `go-mknoon/node/pubsub_test.go`: `TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward` rejects a removed/non-member sender across message, reaction, membership, metadata, and key-rotation payload shapes before decrypted payload handling.

The remaining risk is live PubSub behavior:

- X can have stale local group state and publish to the old topic.
- B may reject X locally, but LP-002 does not yet prove B's rejection suppresses forwarding to C in a real PubSub topology.
- The code logs validator rejects directly through `log.Printf`, but there is no explicit rate limiter and no test that diagnostics stay privacy-safe under repeated unauthorized payloads.
- `go-mknoon/node/initPubSub` configures `pubsub.NewGossipSub(..., pubsub.WithFloodPublish(true))` and current repo search found no app-owned `WithPeerScore` or `PeerScoreParams` configuration, so peer-score behavior cannot be claimed as app-owned LP-002 coverage unless implementation adds it intentionally or the row accepts it as non-applicable.

User-visible behavior that must improve: unauthorized group traffic from stale or removed members must not appear as delivered messages, reactions, metadata, membership, or key events on any authorized peer, and diagnostics must help operators without leaking sensitive group content or spamming logs.

Behavior that must stay unchanged: authorized members still publish and receive group messages/reactions, announcement writer restrictions still reject non-admin messages while allowing member reactions, and group peer discovery/fanout behavior stays otherwise unchanged.

## files and repos to inspect next

Production files:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/event_dispatcher.go`
- `go-mknoon/node/config.go`
- `go-mknoon/bridge/bridge.go` only if bridge-level publish or diagnostics surface changes become necessary
- `go-mknoon/cmd/testpeer/commands.go` only if a raw external proof command is needed after Go in-process proof is insufficient

Tests and harness files:

- Prefer new row-owned tests in `go-mknoon/node/pubsub_authorization_forward_test.go` or another new `go-mknoon/node/*_test.go` file to avoid colliding with the currently dirty `go-mknoon/node/pubsub_test.go`.
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/protocol_version_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/cmd/testpeer/commands_test.go` only if testpeer changes are needed
- `integration_test/transport_e2e_test.dart`
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`

Docs/gates:

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

- `go-mknoon/node/pubsub_test.go` has `TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward`, proving real validator rejection for removed/non-member message, reaction, membership, metadata, and key-rotation payload shapes before decrypted payload handling.
- `go-mknoon/node/pubsub_test.go` has `TestGroupTopicValidator_RejectsRemovedMemberAfterConfigUpdate`, proving pure validation moves from accept to reject after a member is removed from config.
- `go-mknoon/node/pubsub_test.go` has signature, spoofing, announcement non-admin, transport-peer mismatch, and empty-member rejection tests around the same validator.
- `go-mknoon/node/pubsub_delivery_test.go` has live local-node publish and peer-count/fanout tests, including three-node topology tests, but not unauthorized X-B-C reject-before-forward coverage.
- `go-mknoon/node/pubsub_decryption_failure_test.go` proves wrong-key and malformed-payload cases do not emit normal receive events, using the raw publish helper style needed for LP-002.
- `go-mknoon/node/group_security_harness_test.go` provides raw envelope publish and event collector helpers, but currently only has helper coverage plus a mutation sanity test.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` classify `groups` as the frozen group messaging gate and `group-real-network-nightly` as fixture-backed multi-relay proof.

Missing:

- A live authorized receiver that rejects unauthorized PubSub traffic and does not forward it to a downstream authorized peer.
- Diagnostics proof for rate limiting and privacy safety under repeated unauthorized event-family payloads.
- App-owned peer-score proof. Current code does not configure peer scoring, so this should be treated as non-applicable or follow-up unless the row owner requires enabling scoring.

## regression/tests to add first

Add tests before production changes:

1. `TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward`
   - Location: new `go-mknoon/node/pubsub_authorization_forward_test.go`.
   - Build local nodes X, B, and C with `RelayAddresses: []string{}`.
   - Use a stale config on X that includes X as a member and a current config on B/C that excludes X.
   - Connect X only to B and B only to C.
   - Publish raw signed envelopes from X for:
     - `group_message`
     - `group_reaction`
     - membership system payload
     - metadata system payload
     - key-rotation system payload
   - Assert B has no normal receive, reaction receive, payload parse failure, or decryption failure event.
   - Assert C has no normal receive, reaction receive, payload parse failure, or decryption failure event, proving B did not forward X's rejected payload.

2. `TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited`
   - Location: new `go-mknoon/node/pubsub_authorization_forward_test.go` or new focused diagnostics test file.
   - Capture validator diagnostic output while repeatedly submitting unauthorized envelopes containing unique plaintext sentinels, public keys, signatures, and encrypted payload fields.
   - Assert diagnostics do not include plaintext payload contents, public/private keys, signatures, nonces, ciphertext, group name, or full multiaddrs.
   - Assert repeated rejects for the same group/sender/transport/reason are rate-limited by a deterministic package-level window. The executor may choose the exact constant name, but the test should submit at least five immediate rejects for one key and expect at most one emitted diagnostic for that key during the window, while a different reason or sender may still emit its first diagnostic.
   - This test is expected to fail on current code if direct `log.Printf` calls remain unthrottled.

3. Optional peer-score check only if required by the row owner:
   - First assert app config reality with a narrow code search or test comment: `initPubSub` has no `WithPeerScore`.
   - Do not add peer-score behavior inside LP-002 unless the reject-before-forward proof fails without it or the source row explicitly requires production scoring. Enabling peer scoring is transport-wide and should be a separate plan if required.

## step-by-step implementation plan

1. Re-run `git status --short` and read the current dirty contents of any target file before editing. Preserve all user-owned changes.
2. Add the LP-002 live X-B-C raw PubSub regression test in a new Go test file under `go-mknoon/node/`.
3. Run the focused Go test. If it passes without product changes, record it as forward-path proof and do not touch forwarding, discovery, or GossipSub configuration.
4. Add the LP-002 diagnostics regression test.
5. Run the focused diagnostics test. If it fails only because diagnostics are not rate-limited or privacy-safe, implement the smallest validator diagnostic helper:
   - Replace direct authorization reject `log.Printf` calls in `groupTopicValidator` with a helper that accepts reason, group ID, sender ID, transport peer ID, and fixed metadata only.
   - Hash or truncate identifiers in diagnostics; do not log payload, ciphertext, nonce, signature, public key, private key, group name, or multiaddr.
   - Rate-limit repeated diagnostics by group/reason/sender/transport fingerprint.
   - Keep validation return values unchanged.
6. Re-run the focused tests until they pass.
7. Run the LP-002 Go owner suite and the broader Go group/pubsub gate command.
8. Run Flutter group gates only if Go/bridge behavior that can affect Dart group flows changed. Use `groups` as the named gate source of truth.
9. Run device/relay supporting proof only if the host raw-Go proof cannot close the forward path, or if row review requires real-network backing. Do not let a missing multi-relay fixture masquerade as closure evidence.
10. Update `test-inventory.md` and the source matrix LP-002 row only after passing proof exists. The row may move to `Covered` or `Closed` only with concrete file/test/command evidence.
11. Stop. Do not absorb LP-003, RP-017, SP-001, EK-004, or ER-* rows.

## risks and edge cases

- Stale local state: X may still have the old group key and old config while B/C have removed X.
- Forward topology: if X and C become directly connected, C's absence of a receive event no longer proves B suppressed forwarding. Keep topology X-B-C with no X-C direct connection.
- FloodPublish: `WithFloodPublish(true)` may send to all directly connected topic peers; the test must avoid direct X-C connectivity.
- PubSub validation timing: use bounded waits for topic peer counts before publishing and bounded negative assertions after publishing.
- Diagnostics privacy: logs must not include decrypted payload, plaintext system event contents, keys, signatures, nonces, ciphertext, group names, or full network multiaddrs.
- Rate limiting: repeated unauthorized payloads should not flood logs, but the first diagnostic per group/sender/reason must remain available enough to debug policy rejects.
- Peer scoring: current app does not configure peer scoring. Treat this as an accepted current architecture difference unless explicit LP-002 evidence proves that score configuration is necessary for forward suppression.
- Dirty worktree: `go-mknoon/node/pubsub_test.go`, docs, and other files are already modified before this plan; implementation must not revert or overwrite those changes.

## exact tests and gates to run

Focused first runs:

```bash
cd go-mknoon && go test ./node -run 'TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward|TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited|TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward' -v
```

Owner Go suite:

```bash
cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v
```

Named and direct Flutter gates if Go bridge or Dart-visible group behavior changes:

```bash
./scripts/run_test_gates.sh groups
flutter test --no-pub test/features/groups/integration
```

Device/relay supporting gate only when fixture proof is required:

```bash
MKNOON_RELAY_ADDRESSES='<relay-multiaddr-1>,<relay-multiaddr-2>' FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 ./scripts/run_test_gates.sh group-real-network-nightly
```

Three-party/device-lab supporting run only if the host raw-Go proof is rejected as insufficient and a compatible LP-002 injection harness already exists or is explicitly authorized:

```bash
MKNOON_RELAY_ADDRESSES='<relay-multiaddr-1>,<relay-multiaddr-2>' dart run integration_test/scripts/run_group_multi_device_real.dart -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Always finish with:

```bash
git diff --check
```

## Device/Relay Proof Profile

LP-002 primary closure profile: host-only, three-party, raw-Go/libp2p proof.

Required closure evidence:

- A three-local-node Go test that exercises X-B-C live PubSub topology and unauthorized event-family payloads.
- No `FLUTTER_DEVICE_ID` is required for that primary closure evidence.
- A single `FLUTTER_DEVICE_ID` only selects the Flutter host target for Flutter integration-backed gates; it does not create a three-party device-lab topology by itself.

Live availability checked on 2026-04-30:

- `flutter devices --machine` reported:
  - Android emulator: `emulator-5554`, `sdk gphone16k arm64`, Android 17 API 37.
  - Physical iOS: `00008030-001A6D2801BB802E`, `Saleh's iPhone`, iOS 26.3.1.
  - iOS simulator: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone 17 Pro, iOS 26.1, booted.
  - iOS simulator: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone Air, iOS 26.1, booted.
  - iOS simulator: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, iPhone 17, iOS 26.1, booted.
  - iOS simulator: `1B098DFF-6294-407A-A209-BBF360893485`, iPhone 16e, iOS 26.1, booted.
  - macOS target: `macos`.
  - Chrome target: `chrome`.
- `xcrun simctl list devices available` confirmed the same iOS 26.1 booted simulator IDs plus additional shutdown iOS simulators.
- `adb devices` was not on `PATH`; `$HOME/Library/Android/sdk/platform-tools/adb devices` reported `emulator-5554 device`.
- `MKNOON_RELAY_ADDRESSES` is unset in this shell.
- `MKNOON_RELAY_ADDR` is unset in this shell.
- Repo defaults exist in `go-mknoon/node/config.go`: `DefaultRelayAddress` and `DefaultQUICRelay`. These defaults are not enough for `group-real-network-nightly`, because `scripts/run_test_gates.sh group-real-network-nightly` passes `MKNOON_REQUIRE_MULTI_RELAY=true` and `integration_test/multi_relay_failover_test.dart` requires at least two comma-separated `MKNOON_RELAY_ADDRESSES`.

Supporting evidence classification:

- `group-real-network-nightly` is multi-relay supporting evidence and is external-fixture-blocked until at least two relay multiaddrs are provided.
- `integration_test/scripts/run_group_multi_device_real.dart` is paired-device plus CLI-peer supporting evidence. Its defaults match available booted simulators: primary `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, sibling `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. It is not LP-002 closure evidence unless an LP-002 unauthorized injection harness is available or explicitly added under this row.
- Current LP-002 should not require packet capture for closure if the raw-Go live forward-path test passes and diagnostics tests pass.

## known-failure interpretation

- If the newly added LP-002 tests fail before implementation, treat that as expected red proof for the missing row-owned behavior.
- If `group-real-network-nightly` fails with `MKNOON_REQUIRE_MULTI_RELAY=true requires at least two comma-separated MKNOON_RELAY_ADDRESSES`, classify it as a fixture blocker, not a product regression.
- If unrelated dirty-worktree tests fail before any LP-002 edits, capture the exact failing command and do not attribute it to LP-002 unless it involves the new tests or touched files.
- After LP-002 code changes, any new failure in the focused Go tests, owner Go suite, `groups` gate, or `git diff --check` is a regression to fix or explicitly block on.

## done criteria

- New LP-002 live forward-path test exists and passes.
- New LP-002 diagnostics privacy/rate-limit test exists and passes.
- Any needed production change is limited to PubSub authorization diagnostics or validator-adjacent helper code.
- Existing validator tests still pass.
- Owner Go suite command passes or any pre-existing unrelated failure is documented with evidence.
- `git diff --check` passes.
- `test-inventory.md` and the LP-002 source matrix row are updated only after proof passes, with exact file names, test names, and commands.
- The row is not marked `Closed` or `Covered` without concrete repo-owned evidence.

## scope guard

Do not:

- Change group membership semantics beyond reject-before-accept/forward.
- Change encryption, signing, key rotation, or payload parsing behavior except as needed to keep diagnostics from leaking data.
- Change relay server behavior.
- Add broad peer scoring, pubsub mesh tuning, or scoring thresholds in this session unless the proof shows reject-before-forward cannot close without it.
- Add a new generalized multi-device orchestrator.
- Reclassify LP-002 as acceptance-only, doc-only, or already-covered before the missing live proof and diagnostics proof exist.
- Edit unrelated dirty files or revert user-owned changes.

Overengineering would include building a general security event pipeline, adding packet capture infrastructure, changing all group diagnostics outside PubSub authorization, or widening to all security rows.

## accepted differences / intentionally out of scope

- App-owned peer scoring is intentionally out of scope unless LP-002 evidence proves it is required. Current repo evidence found no `WithPeerScore` or `PeerScoreParams` in `go-mknoon/node`, so the LP-002 closure should not claim production peer scoring unless that changes under an explicitly reviewed scope.
- Device-lab and multi-relay proof are supporting evidence for LP-002, not required primary closure evidence, as long as host raw-Go live topology proof covers the accept and forward path.
- Packet capture is not required when raw-Go event assertions can prove that unauthorized payloads do not reach authorized receivers.

## dependency impact

- LP-003 can reuse the live topology and negative-forward helpers for unsubscribe-after-removal proof.
- RP-017 can reuse the stale/removed X model for removed-peer isolation but must own dialing and continued-publish behavior separately.
- EK-004 and SP-001 can cite the validator/event-family proof only for PubSub envelope authorization, not every protocol.
- ER-001 can reuse the privacy-safe diagnostics helper if later rows need invalid-signature diagnostic coverage.
- If LP-002 remains blocked on peer-score product scope, later rows must not cite peer-score behavior as covered.

## dirty-worktree handling

Current intake saw pre-existing modifications in:

- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/pubsub_test.go`
- several Dart group tests
- untracked GL-005 plan file

Implementation must preserve those changes. Prefer adding a new LP-002 Go test file instead of appending to the dirty `pubsub_test.go`. If an implementation must edit a dirty file, read the current content first and make only the smallest compatible patch.

## regression contract

The implementation must keep these contracts green:

- Unauthorized PubSub payloads return `pubsub.ValidationReject`.
- Unauthorized payloads are not decrypted or parsed into normal group events.
- Rejected payloads do not forward through an authorized peer to another authorized peer.
- Authorized group message and reaction flows remain unchanged.
- Announcement group write authorization remains unchanged.
- Diagnostics are privacy-safe and rate-limited without hiding the first useful reject signal.
- Named gate definitions are not widened unless a new test file is added under a category that requires classification.

## Final verdict

execution-ready

This plan is implementation-safe for LP-002. It keeps the first implementation step to test/proof, treats app peer scoring as non-applicable unless explicitly required by later evidence, and avoids device/relay closure claims without configured fixtures.

## Reviewer pass

Reviewer result: sufficient with adjustments.

- Missing files/tests/gates: no structural omissions. The direct Go proof, owner Go suite, named `groups` gate, optional fixture-backed `group-real-network-nightly`, paired-device supporting runner, and `git diff --check` are named.
- Stale or incorrect assumptions: no stale source-of-truth issue found. The plan correctly treats `scripts/run_test_gates.sh` as the named-gate authority and current code as the behavior authority.
- Overengineering risk: peer scoring and device-lab proof are correctly guarded as supporting or accepted differences unless explicitly required.
- Decomposition: sufficient. The first implementation action is a live proof test, and production code is limited to diagnostics unless proof exposes another gap.
- Minimum adjustment applied: make the rate-limit assertion concrete enough for implementation.

## Final plan

Use a proof-first Go implementation session:

1. Add live X-B-C unauthorized PubSub forward-suppression proof.
2. Add diagnostics privacy/rate-limit proof.
3. Implement only the minimal PubSub diagnostic helper if the diagnostics proof fails.
4. Keep peer scoring out of production scope unless reject-before-forward cannot be closed without it.
5. Run focused Go, owner Go, group gates if needed, and `git diff --check`.
6. Update LP-002 source/inventory docs only after evidence exists.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Exact names of helper functions and rate-limit interval constants should be chosen during implementation after reading current `Node` locking patterns.
- Whether diagnostics use hash-only or hash-plus-short-prefix identifiers can be decided during implementation, as long as full IDs and sensitive payload fields are not logged.

## Accepted differences intentionally left unchanged

- No packet-capture requirement for primary closure.
- No production peer-score enablement unless the row owner explicitly requires it.
- No new device-lab harness unless host raw-Go proof cannot exercise the forward path.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/config.go`
- `go-mknoon/go.mod`
- `go-mknoon/cmd/testpeer/main.go`
- `go-mknoon/cmd/testpeer/commands.go`
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`

## Why the plan is safe or unsafe to implement now

Safe to implement now because it is row-owned, starts with direct proof, uses new test files to avoid dirty-file conflicts, limits production code changes to PubSub authorization diagnostics if needed, keeps transport and relay proof as supporting evidence, and has explicit stop rules for peer-score/product-scope questions.

## Final execution verdict

Final verdict: accepted.

Spawned-agent isolation used: attempted. A spawned Executor was launched with model `gpt-5.5` and reasoning effort `xhigh`, but it stalled after inspection and produced no code/test handoff after the bounded wait extension. Local sequential fallback used: yes, for Executor, QA, one fix pass, and final QA in this dedicated LP-002 execution context.

Files changed by LP-002 execution:

- `go-mknoon/node/pubsub_authorization_forward_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-002-plan.md`

Tests added or updated:

- `TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward`
- `TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited`

Evidence captured:

- Host-only three-local-node raw Go proof covers X-B-C unauthorized `group_message`, `group_reaction`, membership, metadata, and key-rotation payload shapes.
- The live proof asserts node X is not directly connected to node C, node B logs exactly one non-member validator reject per payload, and neither B nor C emits `group_message:received`, `group_reaction:received`, `group:payload_parse_failed`, or `group:decryption_failed`.
- Diagnostics proof asserts hashed identifiers, no plaintext/key/signature/nonce/ciphertext/group-name/full-multiaddr leakage, one emitted diagnostic for five immediate repeated rejects, a first diagnostic for a different sender, and a new diagnostic after the deterministic rate-limit window.

Exact tests and gates run:

- `cd go-mknoon && go test ./node -run 'TestLP002UnauthorizedRawPubSubRejectsBeforeAcceptAndForward|TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited|TestGroupTopicValidator_RejectsUnauthorizedEventFamiliesBeforeForward' -v` - passed after test-data fix; rerun after QA fix also passed.
- `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` - failed in current dirty worktree due existing sender/transport mismatch tests, not LP-002 diagnostics.
- `cd go-mknoon && go test ./node -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` - failed only at `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers`; the test publishes with `senderPeerId := "sender-zero"` while the local transport peer is the node peer ID.
- `cd go-mknoon && go test ./bridge -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` - failed only at `TestGroupPublish_ResponseIncludesTopicPeers`; the bridge test creates an identity separate from the started node key and publishes with that non-transport sender peer ID.
- `cd go-mknoon && go test ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` - passed.
- `git diff --check` - passed.

Named Flutter gates:

- `./scripts/run_test_gates.sh groups` and `flutter test --no-pub test/features/groups/integration` were not run because LP-002 changed Go validator diagnostics/logging and tests only; no Dart-visible group behavior or bridge API contract changed.
- Device/relay supporting gates were not run because LP-002 primary closure evidence is the host-only three-party raw Go proof and multi-relay fixture proof is not required.

Blocking issues remaining:

- None for LP-002.

Non-blocking follow-ups deferred:

- Current owner-suite failures in `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `TestGroupPublish_ResponseIncludesTopicPeers` should be handled outside LP-002. They exercise sender IDs that do not match the local libp2p transport peer and fail against the pre-existing validator peer-binding rule.

Why this session is safe to consider complete:

- The implementation stays inside LP-002: one new row-owned Go test file plus minimal PubSub validator diagnostic state/helper changes. Validator accept/reject semantics are unchanged.
- Required LP-002 focused proof is passing, `git diff --check` is clean, no reserved source matrix/test inventory/session breakdown ledger updates were made, and the only broader owner-suite failures are documented as unrelated pre-existing dirty-worktree failures.
