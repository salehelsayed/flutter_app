Status: execution-ready

# GM-031 Plan - Membership Mutation Updates Known-Member Dial Targets

## Planning Progress

- 2026-05-11 18:42:00 CEST - Planner completed. Files inspected since last update: this GM-031 plan draft. Decision/blocker: draft is regression-first and implementation-ready, with conditional Go product scope only if the exact known-member dial regression fails. Next action: run Reviewer on proof fidelity, selector/gate sufficiency, and over-scope risk.
- 2026-05-11 18:42:00 CEST - Reviewer started. Files inspected since last update: this GM-031 plan draft; mandatory section checklist; Go target/dial seams. Decision/blocker: review focus is whether stale top-level peer IDs are proven as actual dialable peers and whether the plan avoids an evidence-only downgrade. Next action: record sufficiency findings and patch material gaps once.
- 2026-05-11 18:42:36 CEST - Reviewer completed. Files inspected since last update: this GM-031 plan with reviewer adjustments. Decision/blocker: sufficient with adjustments; stale top-level peer IDs are now required to be real local nodes and event capture now includes all `known_member_*` dial events. Next action: run Arbiter and classify findings.
- 2026-05-11 18:42:36 CEST - Arbiter started. Files inspected since last update: reviewer findings; adjusted plan; mandatory output checklist. Decision/blocker: no apparent structural blocker; reviewer changes appear incremental. Next action: finalize arbiter decision and execution-ready status if no blocker remains.
- 2026-05-11 18:42:54 CEST - Arbiter completed. Files inspected since last update: final GM-031 plan; reviewer findings; exact selector/gate contract. Decision/blocker: no structural blockers remain; reviewer adjustments are incremental details and accepted differences are documented. Next action: hand off for execution of GM-031 only.

## Evidence Summary

- Source row GM-031 in `Private_group_chat_reliability_test_matrix_COMPLETE_1.md` is Open: "Membership mutation updates known-member dial targets"; scenario is D added with an active transport device and C removed; expected dial targets match active devices/current members, not removed users or stale `PeerId` fields.
- Session breakdown row GM-031 is `needs_code_and_tests` / `implementation-ready`; it names broad Flutter group membership files plus `go-mknoon/node/pubsub.go` and `group_inbox.go`, but the exact row behavior is the Go known-member dial path.
- Go test-name evidence: `go test ./node -list 'GM031|GM-031|MembershipMutationUpdatesKnownMemberDialTargets'` produced no test names and exited `ok`, so there is no exact GM-031 proof.
- Adjacent evidence exists but does not close GM-031: GM-030 proves rendezvous discovery filtering after A/B/C to A/B/D mutation; GM-023 proves inactive shadow transport is not dialed; GM-027/028 prove malformed or blank members do not inflate target counts.
- Current Go production target selection is centered in `go-mknoon/node/pubsub.go`: `activeGroupMemberDialTargets` normalizes members, prefers active devices, validates libp2p peer IDs, de-duplicates targets, and falls back to `member.PeerId` only when the member has no device rows. `dialKnownGroupMembers`, `dialKnownGroupMembersDirectOnly`, `countConnectedGroupMembers`, `expectedConnectedGroupMembers`, and `countRemoteGroupMembers` all use that helper.
- Dart membership identity handling is relevant for upstream config shape: `GroupMember.activeDevices`, `activeDevicesWithLegacyFallback`, and `GroupMemberDeviceIdentity.transportPeerId` are first-class in `group_member.dart`; `group_config_payload.dart` normalizes/dedupes members and devices and requires deliverable identity for locally produced config members.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`; the named Group Messaging Gate is `./scripts/run_test_gates.sh groups`, and `completeness-check` is required only when gate/classification docs or new test files need classification.

## real scope

Own exactly GM-031: after group config membership mutates from old active members to current active members, `dialKnownGroupMembers` and the shared known-target helper must dial only the current active transport peer IDs for current members.

The row-owned proof should model:

- admin/self plus B and removed C in the old config
- admin/self plus B and newly added D in the current config
- B and D each have active device `TransportPeerId` values that differ from their top-level `PeerId`
- removed C has peerstore addresses from the previous config and must not be dialed
- stale top-level `PeerId` fields for B/D are valid, dialable local-node peer IDs and must not be dialed when active device transports exist

Default execution posture is code-and-tests-ready, with Go regression first. Product changes are allowed only if the exact GM-031 regression fails or inspection during execution finds `dialKnownGroupMembers` bypassing active device transport targets.

Out of scope in this session:

- source matrix closure edits
- session breakdown closure row edits or final program verdict edits
- broad Flutter membership feature changes unless the Go regression proves Flutter emits an invalid current config shape
- simulator/real-device proof by default
- durable inbox recipient selection or group inbox behavior unless a GM-031 failure directly traces to known-member dial target state

## closure bar

GM-031 is good enough when one exact row-owned regression proves the known-member dial path after membership mutation:

- the stored current config replaces the old C entry with D
- active dial targets are exactly B-device and D-device transport peer IDs
- stale B/D top-level `PeerId` values are valid local-node peer IDs and are not dialed when active device transports are present
- removed C's previous transport peer is not dialed even if its addresses remain in the peerstore
- `dialKnownGroupMembers` actually connects or attempts only the expected active device transports
- expected/remote counts continue to match those active device targets
- adjacent GM-023/027/028/030 Go selectors still pass

If the new regression passes without product changes, the session can close as tests-backed GM-031 evidence, not docs-only evidence. If it fails, the minimal product fix must land before closure.

## source of truth

1. Current code and tests win over stale prose.
2. Source matrix row GM-031 defines the scenario and expected behavior.
3. Session breakdown row GM-031 defines classification and required plan path.
4. `go-mknoon/node/pubsub.go` is authoritative for known-member dial target selection and counts.
5. `go-mknoon/node/pubsub_test.go` is the preferred direct regression location.
6. `Test-Flight-Improv/test-gate-definitions.md` plus `scripts/run_test_gates.sh` are authoritative for named gates.
7. GM-023/027/028/030 plans and tests are authoritative only for overlap risks; they do not close GM-031.

## session classification

`implementation-ready`

Breakdown disposition remains `needs_code_and_tests`. Treat execution as test-first code-and-tests work because no exact GM-031 proof exists. Do not downgrade to evidence-only or acceptance-only during this planning pass.

## exact problem statement

The unproven risk is that known-member recovery can keep dialing stale top-level `member.PeerId` values after membership mutation, instead of dialing the active device transport peer IDs for current members. In a multi-device/private-group model, that can leave newly added D undiscovered, keep removed C reachable, or inflate expected connected-member counts with stale identity fields.

User-visible behavior that must improve: after D is added and C removed, foreground recovery and publish preflight known-member dialing should reconnect the current members' active transport devices, not removed users or stale peer IDs.

Behavior that must stay unchanged: GM-023 active-shadow selection, GM-027 invalid member filtering, GM-028 blank peer filtering, GM-030 rendezvous allowed-member filtering, relay fallback behavior, cooldown/in-flight behavior, and legacy member fallback for members with no device rows.

## files and repos to inspect next

Production files:

- `go-mknoon/node/pubsub.go`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`

Direct tests:

- `go-mknoon/node/pubsub_test.go`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

Gate/infra docs:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Inspect Flutter files/tests only if the Go regression fails because config payloads do not contain active device transport identities or because stale `PeerId` fields are being emitted from Dart.

## existing tests covering this area

- `TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate` proves a removed member is excluded from known-member and rendezvous dialing after config update, but it uses top-level peer IDs and does not prove device transport targets.
- `TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter` proves discovery/rendezvous filtering after old admin/B/C to current admin/B/D config, but it does not call `dialKnownGroupMembers` for active device transport peers.
- `TestGM023GroupPeerDiscoveryUsesActiveDeviceAfterInactiveShadow` proves inactive shadow transport is not dialed from discovery or known-member recovery, but it is an inactive-shadow duplicate case, not the D-added/C-removed membership mutation row.
- `TestGM027InvalidDeviceLessPeerIDDoesNotInflateGroupTargets` proves invalid device-less entries are excluded from targets and counts.
- `TestGM028EmptyPeerIDDoesNotInflateDiscoveryOrPublishPreflight` proves blank top-level peer entries are dropped before target/count inflation.
- Dart add/listener/send/membership tests cover device identity normalization and deliverable identity filtering for prior rows, but there is no exact GM-031 selector.

## regression/tests to add first

Add a Go regression in `go-mknoon/node/pubsub_test.go`, proposed name:

```text
TestGM031MembershipMutationUpdatesKnownMemberDialTargets
```

The test should:

1. Start local nodes for admin, B active device, C removed device, D active device, stale B top-level peer, and stale D top-level peer. The stale B/D top-level peers must be actual nodes with peerstore addresses so the test can prove they were not dialed.
2. Build an old config with admin, B, and C. For B/C, use top-level logical member `PeerId` values that are valid but not the active device transport IDs; include active device entries where `TransportPeerId` is the actual local node peer ID. Use a real removed C device node for C's transport.
3. Build a current config with admin, B, and D. B and D must each have active devices whose `TransportPeerId` is the intended dial target and whose top-level `PeerId` is a different valid stale local-node peer.
4. Install old config, then update to current config through `UpdateGroupConfig`.
5. Add peerstore addresses for active B/D devices, removed C's old device, and stale B/D top-level peers.
6. Assert `activeGroupMemberDialTargets(storedConfig, admin.PeerId())` and `countRemoteGroupMembers` are exactly B-device and D-device.
7. Call `admin.dialKnownGroupMembers(groupId, true)`.
8. Call `admin.dialKnownGroupMembers(groupId, true)` and collect peer IDs from every emitted `known_member_*` discovery event, including success, failed, topic-missing, and pre-relay variants if the helper is reused.
9. Assert B-device and D-device reach `network.Connected`; removed C device and stale top-level B/D peers remain not connected.
10. Assert the `direct_dial` summary event reports `totalMembers == 2`. Do not require `membersConnected == 2` unless the test has joined topic peers, because the current direct dial path can emit `known_member_topic_missing` after a network connection when the peer is not yet live in the topic.
11. Assert no collected known-member dial event names removed C or stale B/D top-level peer IDs.

This is the row-owned regression because it exercises the exact known-member dial method, not just the helper and not just rendezvous discovery.

## step-by-step implementation plan

1. Re-read owner diffs for `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go`; preserve unrelated dirty changes.
2. Add `TestGM031MembershipMutationUpdatesKnownMemberDialTargets` in `go-mknoon/node/pubsub_test.go` near GM-030/GM-023 tests.
3. Reuse existing local-node helpers, `setFakeRelays`, peerstore address setup, `waitForRP017Connectedness`, and the event collector instead of adding a new harness.
4. Run the exact GM-031 Go selector before product changes. If it passes, do not modify production code.
5. If it fails because `activeGroupMemberDialTargets` emits top-level `member.PeerId` despite active device transport IDs, patch only `go-mknoon/node/pubsub.go` target selection so active deliverable device transport IDs win and legacy `member.PeerId` fallback applies only when there are no usable device identities.
6. If it fails because `UpdateGroupConfig` or normalization keeps removed C/stale duplicates, patch only the config normalization path needed for this row and rerun GM-022/023/027/028/030 selectors.
7. If it fails because Flutter is producing current config without active devices, stop and inspect the named Flutter config producer/listener files before changing Go behavior. Add the smallest Flutter test selector only if that exact producer gap is proven.
8. Run `gofmt -w go-mknoon/node/pubsub_test.go` and, if touched, `gofmt -w go-mknoon/node/pubsub.go`.
9. Run required Go selectors and race selectors if production Go code changed.
10. Run `git diff --check`.
11. Do not edit the source matrix, session breakdown closure rows, or final program verdict in this execution session unless a later closure-specific pass asks for it.

## risks and edge cases

- Multi-device rows can accidentally prove only top-level peer behavior if B/D top-level `PeerId` equals the transport peer ID. The GM-031 test must make those values different.
- Stale top-level `PeerId` values that are invalid or have no peerstore addresses would not prove a dial avoidance contract. Use real local nodes for stale B/D top-level peer IDs.
- `activeGroupMemberDialTargets` currently falls back to `member.PeerId` for legacy no-device members. Do not remove that fallback unless the exact failure proves it is incorrectly used when devices exist.
- A member with only revoked or malformed devices currently bypasses top-level fallback because `len(member.Devices) > 0` causes a `continue`. Preserve or change that only if the GM-031 test exposes it as the cause and adjacent GM-023/027/028 tests remain green.
- Direct connections may exist at the libp2p network layer before topic mesh readiness. Assert known-member dial target event peer IDs and network connectedness, not full message delivery or topic-live success.
- Cooldown/in-flight state can hide a dial attempt. Use `ignoreCooldown: true` for the exact `dialKnownGroupMembers` call and fresh nodes/group IDs.
- Prior dirty worktree changes in Go/Flutter group files are accepted session state and must not be reverted.

## exact tests and gates to run

Test-name proof before editing if desired:

```bash
(cd go-mknoon && go test ./node -list 'GM031|GM-031|MembershipMutationUpdatesKnownMemberDialTargets')
```

Required focused Go selector after adding the test:

```bash
(cd go-mknoon && go test ./node -run 'TestGM031|TestGM030|TestGM023|TestGM027|TestGM028|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate' -count=1)
```

If Go production code changes, also run:

```bash
(cd go-mknoon && go test -race ./node -run 'TestGM031|TestGM030|TestGM023|TestGM027|TestGM028|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate' -count=1)
```

If only Go test code changes and the exact selector passes, race is optional but recommended; document the skip if not run.

If Flutter product/config producer code changes, run the focused impacted selectors:

```bash
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-031'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-031'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-031'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-031'
```

If those GM-031 Flutter selectors do not exist and Flutter code is changed, add the minimal exact selector in the touched owner file before changing product behavior.

Named gates:

```bash
./scripts/run_test_gates.sh groups
```

Run `groups` if Flutter group send/receive/retry/resume/invite/membership behavior changes. For Go-only target-selection changes, focused Go selectors plus race and `git diff --check` are sufficient unless execution changes Flutter group behavior or the reviewer requests broader group proof.

Completeness:

```bash
./scripts/run_test_gates.sh completeness-check
```

Run only if gate docs/classification change or execution adds a new Flutter `*_test.dart` file. Adding a new Go test function to an existing Go test file does not require completeness-check.

Always run:

```bash
gofmt -l go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go
git diff --check
```

Limit the `gofmt -l` file list to files that exist or were touched.

## known-failure interpretation

- A failure in `TestGM031MembershipMutationUpdatesKnownMemberDialTargets` is row-owned and blocks closure.
- A failure in GM-023/027/028/030/RP017 adjacent selectors blocks closure if it involves active device selection, removed-member filtering, invalid/blank target exclusion, expected counts, or known/discovered dialing.
- A broad Flutter `groups` failure is relevant only if execution touches Flutter group behavior or the failure is attributable to GM-031 changes. Otherwise, require exact focused Go proof plus documented residual attribution.
- Race failures in `go test -race ./node` after Go production changes are blockers unless independently reproduced outside the GM-031 diff and unrelated to touched code.
- Existing dirty worktree files and prior accepted-session changes are not GM-031 evidence and must not be reverted or claimed as new work.

## done criteria

- The exact GM-031 Go regression exists in `go-mknoon/node/pubsub_test.go`.
- The regression proves B/D active device transport targets are dialed and removed C plus stale top-level `PeerId` values are not.
- Required focused Go selector passes.
- If Go production code changed, the required race selector passes.
- If Flutter product code changed, row-owned Flutter selectors exist and pass, and the named `groups` gate passes or has exact non-GM-031 residual attribution.
- Formatting and whitespace checks pass.
- The plan/execution notes preserve source matrix and session-breakdown closure rows for a later closure pass.

## scope guard

Do not:

- rewrite group membership schemas
- change durable inbox recipient semantics
- alter relay fallback, cooldown, or in-flight dial scheduling beyond target selection
- remove legacy no-device `member.PeerId` fallback unless exact GM-031 evidence proves it is unsafe in a device-backed member case
- close GM-030, GA-023, GP-011, or later rows
- broaden into simulator, real-crypto onboarding, or multi-party harness work unless a focused host test proves the local seam cannot cover the row

Overengineering in this session would be adding a new target-selection service, a new cross-language identity schema, or broad Flutter config rewrites when one Go known-member dial regression and a small helper patch can prove the row.

## accepted differences / intentionally out of scope

- Rendezvous discovery filtering is GM-030; GM-031 only uses that as adjacent evidence.
- Inactive shadow authorization/discovery is GM-023; GM-031 only preserves that behavior.
- Invalid/blank member rejection is GM-027/GM-028; GM-031 only preserves those target filters.
- Legacy public-key-only/no-device members may still dial top-level `member.PeerId`; GM-031 targets device-backed active members.
- No simulator or physical-device proof is required by default because the row is the Go known-member dial target seam.

## dependency impact

Later group reliability rows can depend on GM-031 only after it has row-owned evidence that known-member dialing follows current active device transport targets. If GM-031 exposes a production bug, rows that rely on quick foreground recovery, publish preflight recovery, or active-device counts should wait for the narrow fix and race proof.

If GM-031 lands as Go test-only evidence, later rows may treat known-member dial target selection as covered for D-added/C-removed active-device configs, but they still need their own proofs for revoked devices, generic rendezvous filtering, partition healing, or simulator routing.

## Reviewer Findings

Reviewer verdict: sufficient with adjustments already applied.

- Missing proof detail fixed: stale B/D top-level `PeerId` values must be valid local-node peers with peerstore addresses, not arbitrary strings.
- Event assertion fixed: the regression should collect all `known_member_*` event peer IDs and should not require `membersConnected == 2` unless the test explicitly establishes live topic peers.
- Gate contract is sufficient: focused Go selector is required, race is required if Go production changes, Flutter selectors and `groups` gate are conditional on Flutter product changes, and completeness-check is conditional on new Flutter test files or gate docs.
- The plan is decomposed enough: execution owns one Go regression first and only touches production when the exact assertion fails.
- No overengineering found after the adjustments; simulator/real-device proof remains intentionally out of scope.

## Arbiter Decision

Final arbiter classification:

- Structural blockers: none.
- Incremental details accepted into the plan: stale top-level B/D `PeerId` values must be real local-node peers, and event assertions should capture every `known_member_*` peer ID without requiring live-topic success.
- Accepted differences intentionally left unchanged: no simulator/physical proof by default, no Flutter code path unless the Go regression exposes a config-production gap, no durable inbox changes, no source matrix/session-breakdown closure edits, and no final program verdict edits.

Final verdict: execution-ready for exactly GM-031. Proceed with the Go regression first, then apply the minimal product change only if that regression fails.

## Execution Progress

- 2026-05-11 20:53:22 CEST - Controller contract extracted. Files inspected or touched: this GM-031 plan; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; worktree status. Decision/blocker: scope is GM-031 only, regression first in `pubsub_test.go`, production Go only if the exact regression fails or inspection proves active device transport targets are bypassed, Flutter gates conditional only if Flutter product/config code changes. Next action: spawn Executor child with `model=gpt-5.5` / `reasoning_effort=xhigh`.
- 2026-05-11 20:55:00 CEST - Executor spawn attempted. Files inspected or touched: this GM-031 plan only. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ... -a never ...`. Decision/blocker: launch failed before an agent started because this `codex exec` build does not accept `-a`; no child code/doc work materialized. Next action: retry Executor spawn with approval policy passed through `-c approval_policy="never"`.
- 2026-05-11 20:56:30 CEST - Executor contract extracted. Files inspected or touched: this GM-031 plan; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`. Decision/blocker: execute GM-031 only; add exact Go regression first; do not touch production unless the exact regression fails for product behavior. Next action: add `TestGM031MembershipMutationUpdatesKnownMemberDialTargets`.
- 2026-05-11 20:58:47 CEST - GM-031 regression first run completed. Files inspected or touched: `go-mknoon/node/pubsub_test.go`. Command: `(cd go-mknoon && go test ./node -run 'TestGM031MembershipMutationUpdatesKnownMemberDialTargets' -count=1)`. Result: FAIL because the test read the async event collector before the final `direct_dial` summary and D known-member event were visible; logs showed B/D active device peers connected and no production bypass evidence. Next action: patch only the test observer to poll the collector.
- 2026-05-11 20:59:20 CEST - GM-031 regression rerun completed. Files inspected or touched: `go-mknoon/node/pubsub_test.go`. Command: `(cd go-mknoon && go test ./node -run 'TestGM031MembershipMutationUpdatesKnownMemberDialTargets' -count=1)`. Result: PASS (`ok github.com/mknoon/go-mknoon/node 0.608s`). Decision/blocker: no Go production change needed. Next action: format and run required adjacent selector.
- 2026-05-11 20:59:40 CEST - Required focused selector completed. Files inspected or touched: `go-mknoon/node/pubsub_test.go`. Commands: `gofmt -w go-mknoon/node/pubsub_test.go`; `(cd go-mknoon && go test ./node -run 'TestGM031|TestGM030|TestGM023|TestGM027|TestGM028|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate' -count=1)`. Result: PASS (`ok github.com/mknoon/go-mknoon/node 0.731s`). Decision/blocker: adjacent GM-023/027/028/030/RP017 selectors remain green. Next action: run required format listing and whitespace check.
- 2026-05-11 21:00:38 CEST - Required final checks completed. Files inspected or touched: `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; this GM-031 plan. Commands: `gofmt -l go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go`; `git diff --check`. Result: PASS; `gofmt -l` produced no output and `git diff --check` produced no output. Decision/blocker: race selector skipped because no GM-031 Go production code changed; Flutter gates skipped because no Flutter product/config code changed. Next action: hand off to QA Reviewer.
- 2026-05-11 21:02:15 CEST - QA Reviewer spawn started. Files inspected or touched: this GM-031 plan; `go-mknoon/node/pubsub_test.go`. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -c approval_policy="never" ...`. Decision/blocker: separate QA child will review scope, regression fidelity, required evidence, and gate decisions without editing code/tests. Next action: await QA Reviewer result.
- 2026-05-11 21:04:16 CEST - QA Reviewer completed. Files inspected or touched: this GM-031 plan; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub.go` inspection only; worktree status. Commands rerun: `(cd go-mknoon && go test ./node -run 'TestGM031MembershipMutationUpdatesKnownMemberDialTargets' -count=1)` PASS (`ok github.com/mknoon/go-mknoon/node 0.507s`); `(cd go-mknoon && go test ./node -run 'TestGM031|TestGM030|TestGM023|TestGM027|TestGM028|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate' -count=1)` PASS (`ok github.com/mknoon/go-mknoon/node 0.697s`); `gofmt -l go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` PASS/no output; `git diff --check` PASS/no output. Decision/blocker: no blocking QA findings; no GM-031 production edit identified, and existing `pubsub.go` dirtiness predates this row's Executor per the plan's pre-execution evidence. Next action: GM-031 accepted by QA; leave matrix/breakdown/closure verdicts for a later closure pass.
- 2026-05-11 21:05:29 CEST - Controller final verdict written. Files inspected or touched: this GM-031 plan. Decision/blocker: no fix loop required after QA accepted; GM-031 execution is accepted with no follow-up. Next action: final response with files changed, exact commands/results, residual risks, and closure readiness.

## Executor Result

- Files changed by GM-031 Executor: `go-mknoon/node/pubsub_test.go`; this GM-031 plan. `go-mknoon/node/pubsub.go` was inspected and included in `gofmt -l`, but no GM-031 production edit was made.
- Test added: `TestGM031MembershipMutationUpdatesKnownMemberDialTargets` in `go-mknoon/node/pubsub_test.go`.
- Regression coverage: old admin/B/C config updated to current admin/B/D; B and D use active device `TransportPeerId` values that differ from valid, addressable stale top-level `PeerId` nodes; removed C has prior device/top-level addresses; known-member dialing connects B/D active device transports only; removed C and stale top-level B/C/D peers are not connected or named by `known_member_*` events; `direct_dial.totalMembers == 2`; remote/expected target counts stay at 2.
- Exact tests and checks run:
  - `(cd go-mknoon && go test ./node -run 'TestGM031MembershipMutationUpdatesKnownMemberDialTargets' -count=1)` - initial FAIL due async event snapshot timing in the new test observer; patched by polling collector evidence.
  - `(cd go-mknoon && go test ./node -run 'TestGM031MembershipMutationUpdatesKnownMemberDialTargets' -count=1)` - PASS (`ok github.com/mknoon/go-mknoon/node 0.608s`).
  - `(cd go-mknoon && go test ./node -run 'TestGM031|TestGM030|TestGM023|TestGM027|TestGM028|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate' -count=1)` - PASS (`ok github.com/mknoon/go-mknoon/node 0.731s`).
  - `gofmt -l go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` - PASS, no output.
  - `git diff --check` - PASS, no output.
- Production changed: no GM-031 production code changed.
- Race/gate decision: Go race selector skipped because only Go test code changed and the required non-race selector passed. Flutter focused selectors, `groups`, and completeness gates skipped because no Flutter product/config code, gate docs, or new Flutter test files changed.
- Residual uncertainties: none from the Executor pass. QA should review only GM-031 sufficiency and be aware that unrelated accepted dirty work may already exist outside this Executor-owned delta.
- Handoff notes for QA: verify the new test remains scoped to known-member dial target selection and does not claim closure for source matrix/session-breakdown rows; no QA Reviewer role was performed by this Executor.

## QA Result

Final verdict: accepted.

- Blocking issues: none.
- Non-blocking follow-ups: none for GM-031.
- Scope adherence: accepted. QA found no source matrix, session-breakdown closure, closure-ledger, final-program-verdict, production-code, or Flutter edits attributable to this GM-031 pass. `go-mknoon/node/pubsub.go` remains dirty from prior accepted work, but the GM-031 plan already described `activeGroupMemberDialTargets` before execution and the GM-031 diff under review is the new test plus this plan evidence.
- Regression sufficiency: accepted. `TestGM031MembershipMutationUpdatesKnownMemberDialTargets` creates old admin/B/C then current admin/B/D config, gives B/D active device `TransportPeerId` values distinct from valid addressable top-level peer nodes, leaves removed C with prior device/top-level addresses, asserts helper target/count behavior is exactly B/D active device transports, calls `dialKnownGroupMembers(groupId, true)`, verifies only B/D active devices connect, and verifies all collected `known_member_*` event peer IDs exclude removed C and stale top-level B/C/D peers.
- Evidence accepted: exact GM-031 selector PASS (`ok github.com/mknoon/go-mknoon/node 0.507s`); required adjacent selector PASS (`ok github.com/mknoon/go-mknoon/node 0.697s`); `gofmt -l go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` PASS/no output; `git diff --check` PASS/no output.
- Gate decisions accepted: race selector skip is acceptable because no GM-031 Go production code changed; Flutter focused selectors, `groups`, and completeness gates are not required because no Flutter product/config code, gate docs, or new Flutter test files changed.

## Final Execution Verdict

Final verdict: accepted.

- Spawned-agent isolation used: yes. Executor and QA Reviewer ran as separate `codex exec` children with `model=gpt-5.5` and `reasoning_effort=xhigh`.
- Local sequential fallback used: no.
- Blocking issues remaining: none.
- Non-blocking follow-ups deferred: none for GM-031.
- Plan closure readiness: ready for a later closure pass. Source matrix rows, session-breakdown closure rows, closure ledger, and final program verdict were intentionally not edited in this execution pass.
