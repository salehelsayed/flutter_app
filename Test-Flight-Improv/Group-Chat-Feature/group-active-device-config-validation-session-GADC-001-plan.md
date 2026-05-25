# Group Active Device Config Validation Session GADC-001 Plan

Status: accepted/closed

## Execution Progress

- 2026-05-24 CEST - Executor landed the focused native Go implementation and tests in `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/bridge/bridge.go`, and `go-mknoon/bridge/bridge_test.go`.
- The landed scope matches this plan's active-device admission boundary: malformed active device entries are rejected before accepted group state through native join, update, and refresh paths, and bridge join/update callers get failure responses for the same malformed active-device input.
- The compatibility boundary stayed intact: legacy no-device `PeerId` libp2p strictness remains intentionally out of scope, and inactive/revoked historical device records remain tolerated.

## QA Verdict

- Verdict: accepted.
- QA reviewer reported no blocking findings.
- Controller reran the focused node and bridge gates plus Go binding/checksum hygiene listed in `Final Evidence`; all passed.

## Closure Verdict

- Verdict: closed for active-device config admission only.
- Future work should reopen this session only for a real regression where malformed active device entries can enter native group state, bridge join/update incorrectly returns success for the same malformed active-device configs, or the documented compatibility boundaries are accidentally tightened.
- Residual-only items are legacy no-device account-like `PeerId` tolerance and inactive/revoked historical-device tolerance. Those were accepted differences, not gaps left by this session.

## Final Evidence

- Passed: `cd go-mknoon && go test ./node -count=1 -run 'TestGroupConfigActiveDeviceValidation|TestActiveGroupInboxRecipients|TestGroupTopicValidator'`
- Passed: `cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupJoinTopic|TestSV009|TestGroupUpdateConfig'`
- Passed: `git diff --check` scoped to touched Go/generated paths.
- Passed: `scripts/ensure_go_ios_bindings.sh`
- Passed: `scripts/ensure_go_macos_bindings.sh`
- Passed: `bash scripts/ensure_go_android_bindings.sh`
- Passed: `scripts/verify_gomobile_bindings.sh all`
- Checked: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md` had no matching row for this exact bug, so no matrix row was invented or updated.

## Planning Progress

- 2026-05-24 00:08 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final plan artifact. Decision/blocker: no structural blockers remain; incremental naming details are deferred to implementation; accepted compatibility differences are documented. Next action: plan is reusable for execution.
- 2026-05-24 00:08 CEST - Arbiter started. Files inspected since last update: reviewer findings and final plan artifact. Decision/blocker: classifying reviewer findings into structural blockers, incremental details, and accepted differences. Next action: finalize execution readiness.
- 2026-05-24 00:08 CEST - Reviewer completed. Files inspected since last update: draft plan artifact only. Decision/blocker: plan is sufficient with no structural blocker; bridge preflight, legacy no-device compatibility, inactive/revoked tolerance, dirty-worktree caution, TDD RED order, and host-only gates are explicit. Next action: run arbiter classification and finalize status.
- 2026-05-24 00:08 CEST - Reviewer started. Files inspected since last update: draft plan artifact only. Decision/blocker: reviewing for missing files/tests/gates, stale assumptions, overbroad validation, and insufficient compatibility decision. Next action: record sufficiency findings.
- 2026-05-24 00:04 CEST - Planner started. Files inspected since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/group.go`, `go-mknoon/node/group_inbox.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_inbox_test.go`, `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/node/node.go`, `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: evidence is sufficient for a narrow admission-validation plan; no blocker. Next action: draft mandatory plan sections, then review for missing scope/gate details.

## Real Scope

Implement one native Go admission-validation change for group configs:

- Reject malformed **active** member device entries before config state is accepted by `JoinGroupTopic`, `UpdateGroupConfig`, and `RefreshJoinedGroupStateIfNewer`.
- For active devices only, require non-empty `deviceId`, non-empty `transportPeerId`, non-empty `deviceSigningPublicKey`, and a canonical/dialable libp2p `transportPeerId` accepted by `peer.Decode`.
- Preserve inactive/revoked historical device tolerance: devices where `groupMemberDeviceIsActive` is false must not be newly rejected for missing/legacy/invalid identity fields in this session.
- Preserve legacy no-device compatibility: members with no `devices` keep the current account-like/non-libp2p `peerId` tolerance unless existing uniqueness/canonicalization already rejects them.
- Add bridge preflight so `GroupJoinTopic` and `GroupUpdateConfig` reject the same malformed active-device configs instead of joining or returning success.

Do not change Flutter, platform bridge generated surfaces, relay server code, durable inbox storage, cryptographic key-package semantics, network dialing behavior, or simulator coverage.

## Closure Bar

This session is good enough when malformed active device configs cannot enter joined/native group state through the three requested native admission paths, bridge callers get failure responses for the same malformed active-device input, active revoked/inactive historical devices remain tolerated, and account-like legacy no-device fixtures continue to pass without broad test churn.

## Source of Truth

- Active session contract: `Test-Flight-Improv/Group-Chat-Feature/group-active-device-config-validation-session-breakdown.md`, row `GADC-001`.
- Current behavior source of truth: `go-mknoon/node/pubsub.go`, `go-mknoon/node/group.go`, `go-mknoon/node/group_inbox.go`, `go-mknoon/bridge/bridge.go`, and direct tests in `go-mknoon/node/*_test.go` plus `go-mknoon/bridge/bridge_test.go`.
- Gate source of truth for broad named gates: `Test-Flight-Improv/test-gate-definitions.md`; this session uses direct host-only Go commands from the breakdown, not Flutter named gates.
- If prose and code disagree, current code/tests win. If a dirty working tree changes these files before implementation, the implementer must re-read the touched hunks before editing.

## Session Classification

`implementation-ready`

## Exact Problem Statement

Active device configs can currently pass native admission with missing active device identity fields or an account-like/non-libp2p `transportPeerId`. Those entries later cannot be dialed as devices and can undermine sender-device binding, validator matching, active inbox recipients, and expected peer counts.

The improvement must reject malformed active device entries at config admission time while keeping two intentional compatibilities unchanged:

- Inactive/revoked historical device records may be incomplete or legacy-shaped.
- Members with no `devices` may still use old account-like peer IDs in fixtures and compatibility configs; this session must not require top-level no-device `member.peerId` values to be libp2p peer IDs.

## Files And Repos To Inspect Next

- `go-mknoon/node/pubsub.go`: shared validation helpers, `JoinGroupTopic`, `UpdateGroupConfig`, `RefreshJoinedGroupStateIfNewer`, active dial target helpers.
- `go-mknoon/node/group.go`: `GroupMemberDevice` and `GroupMember` data shape.
- `go-mknoon/node/pubsub_test.go`: native admission, refresh, topic validator, and active device tests.
- `go-mknoon/node/group_inbox_test.go`: active group inbox recipient fixture compatibility.
- `go-mknoon/bridge/bridge.go`: bridge join/update validation and error-code mapping.
- `go-mknoon/bridge/bridge_test.go`: `GroupJoinTopic`, `GroupUpdateConfig`, `TestSV009`, and active-member-material tests.

## Existing Tests Covering This Area

- `go-mknoon/node/pubsub_test.go` covers validator behavior, join/update/refresh state handling, active device sender binding, active device dial target counts, duplicate active transports, revoked/inactive sender rejection, and active-device expected peer count behavior.
- `go-mknoon/node/group_inbox_test.go` has `TestActiveGroupInboxRecipientsDerivesDeviceTransportsAndDedupe`, which proves active devices produce recipient transports, revoked devices are ignored, duplicates are deduped, and no-device legacy members still contribute their top-level peer ID.
- `go-mknoon/bridge/bridge_test.go` has `TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys`, `TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial`, and `TestGroupUpdateConfig_RejectsIncompleteActiveMemberKeyMaterial`; these reject malformed key material or missing distribution material but do not currently prove that an active device transport peer ID is a real libp2p peer ID.
- No existing `TestGroupConfigActiveDeviceValidation` test was found in `go-mknoon/node`; the breakdown's target test name is a new focused regression bucket.

## Regression/Tests To Add First

Add RED tests before implementation:

1. In `go-mknoon/node/pubsub_test.go`, add `TestGroupConfigActiveDeviceValidation`.
   - Build a valid base group config with legacy no-device members and at least one active device whose `transportPeerId` is generated from a real libp2p peer ID helper such as `generatePeerIDStr(t)`.
   - Table-test malformed active devices:
     - missing/blank `deviceId`
     - missing/blank `transportPeerId`
     - non-libp2p `transportPeerId` such as `account-like-device-peer`
     - missing/blank `deviceSigningPublicKey`
   - Prove each malformed config is rejected by native admission:
     - `JoinGroupTopic` returns `invalid group config` before storing group state.
     - `UpdateGroupConfig` does not replace an existing valid config.
     - `RefreshJoinedGroupStateIfNewer` returns `(false, err)` and preserves the existing config/key.
   - Add positive compatibility cases:
     - a legacy no-device member with an account-like `peerId` remains accepted.
     - revoked/inactive device records with missing/invalid device identity fields remain accepted and are not promoted into active dial targets.

2. In `go-mknoon/bridge/bridge_test.go`, extend or add focused bridge tests under the existing regex buckets:
   - `TestGroupJoinTopic_RejectsMalformedActiveDeviceTransportPeerId` or a new case in `TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial`, expecting `INVALID_JOIN_MATERIAL`.
   - `TestGroupUpdateConfig_RejectsMalformedActiveDeviceTransportPeerId` or a new case in `TestGroupUpdateConfig_RejectsIncompleteActiveMemberKeyMaterial`, expecting `INVALID_INPUT` and preserving the last valid config/publish behavior.
   - If adding a refresh-specific bridge proof, name it with `TestGroupJoinTopic...` because bridge refresh happens through already-joined `GroupJoinTopic` and `RefreshJoinedGroupStateIfNewer`.

3. Update active-device positive fixtures that use strings like `gakm-join-valid-transport` or `gakm-update-valid-transport` as active `transportPeerId` values to use generated real libp2p peer IDs. Do not update no-device `peerId` fixtures solely for strictness.

These tests should fail on the current behavior because active device transport strings are currently accepted by native config validation when `peer.Decode` fails.

## Step-By-Step Implementation Plan

1. Re-check dirty worktree before editing:
   - Run `git status --short`.
   - Run focused diffs for planned files, especially `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_inbox_test.go`, `go-mknoon/bridge/bridge.go`, and `go-mknoon/bridge/bridge_test.go`.
   - Preserve unrelated existing changes; do not reset or reformat unrelated hunks.

2. Add RED tests from `Regression/Tests To Add First`.
   - Keep native tests in `go-mknoon/node/pubsub_test.go` focused on admission and compatibility.
   - Keep bridge tests in `go-mknoon/bridge/bridge_test.go` focused on JSON API error mapping.
   - Do not introduce Flutter, relay, simulator, or live-network test setup.

3. Add a small native validation helper in `go-mknoon/node/pubsub.go`.
   - Suggested shape: `validateGroupConfigActiveDeviceEntries(config *GroupConfig) error`.
   - Call it from the shared config admission path currently named `validateGroupConfigIdentityUniqueness`, before or alongside existing peer/signing/transport uniqueness checks.
   - For each member device, apply strict checks only when `groupMemberDeviceIsActive(device)` is true.
   - Require `strings.TrimSpace(value) == value` and non-empty values for active `DeviceId`, `TransportPeerId`, and `DeviceSigningPublicKey`.
   - Require active `TransportPeerId` to be a canonical libp2p peer ID: `peer.Decode(trimmed)` succeeds and `pid.String() == trimmed`.
   - Return indexed errors that identify `member[i] device[j]` without logging sensitive key material.
   - Have `validateGroupConfigIdentityUniqueness` return a stable reason such as `invalid_active_device` for this helper.

4. Keep legacy no-device validation lenient in this session.
   - Do not change `groupPeerIdentityKey` to reject non-libp2p strings globally.
   - Do not make no-device `member.PeerId` values require `peer.Decode`.
   - Do not require active device `deviceId` or `deviceSigningPublicKey` to be cryptographic/libp2p identifiers; require presence and canonical trimming only.

5. Add bridge-side preflight without changing `Node.UpdateGroupConfig`'s signature.
   - Because `Node.UpdateGroupConfig` logs and returns on invalid configs, bridge code must validate before calling it.
   - Prefer a tiny exported node validation wrapper over duplicating active-device rules in `bridge.go`; for example, expose a node-package function that wraps the shared native admission helper.
   - In `GroupJoinTopic`, map active-device config validation failure to `INVALID_JOIN_MATERIAL`, matching existing join material failures.
   - In `GroupUpdateConfig`, map active-device config validation failure to `INVALID_INPUT`, matching existing update validation failures.
   - Keep existing `validateBridgeGroupConfigMemberKeyMaterial` behavior for member/device key distribution material; do not merge key-distribution policy into active-device identity validation.

6. Adjust only fixtures made invalid by the new active-device transport rule.
   - Replace active device transport strings with generated libp2p peer IDs in the narrow tests touched by this session.
   - Leave no-device account-like member IDs and revoked/inactive historical device fixtures alone unless they are part of an active malformed test case.

7. Run the exact gates and classify any failures using `Known-Failure Interpretation`.

8. Stop after the active-device admission boundary is closed. Do not broaden into cleanup of all legacy account-like group member IDs.

## Risks And Edge Cases

- Broadly tightening top-level `member.PeerId` would break many legacy no-device fixtures and is outside this session.
- Tightening revoked/inactive device entries would risk rejecting historical configs that are needed for audit, churn, or stale membership tolerance.
- `GroupUpdateConfig` has no error return, so relying only on native update rejection would still let bridge callers observe `ok: true`; bridge preflight is required.
- Existing tests may manually install group configs without admission. This session should prove admission boundaries, not retrofit every internal test fixture into a strict config factory.
- Active device `deviceSigningPublicKey` values in current tests are often simple strings, so requiring actual Ed25519/base64 key validity would be a separate key-material session and likely cause unrelated churn.

## Exact Tests And Gates To Run

Required host-only native Go gates:

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestGroupConfigActiveDeviceValidation|TestActiveGroupInboxRecipients|TestGroupTopicValidator'
cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupJoinTopic|TestSV009|TestGroupUpdateConfig'
```

Recommended hygiene after implementation:

```bash
git diff --check
```

No Flutter device, simulator, relay server, or real network proof is required for this session.

## Known-Failure Interpretation

- The new RED tests must fail before implementation specifically because malformed active device configs are accepted or bridge update returns success. A failure for missing Flutter/simulator/relay resources is irrelevant and should not be introduced by this host-only plan.
- After implementation, failures in unrelated dirty files or broad Flutter/relay suites are not session regressions unless the exact required Go gates expose them.
- If an existing `TestGroupTopicValidator...` failure predates this work, confirm by re-running before/after on the same dirty tree and document it separately; do not hide a new `invalid_active_device` regression as pre-existing.
- If bridge tests fail because active-device positive fixtures still use non-libp2p transport strings, update only those active-device fixture fields to generated peer IDs. Do not weaken the validation to keep active fixture strings passing.

## Done Criteria

- `TestGroupConfigActiveDeviceValidation` exists and proves native admission rejects malformed active devices across join, update, and refresh.
- Bridge join/update tests prove malformed active device transport IDs return failure JSON, not `ok: true`.
- Active device configs with real libp2p transport peer IDs still pass.
- Legacy no-device configs with account-like peer IDs still pass in focused tests.
- Revoked/inactive malformed historical device records remain tolerated in focused tests.
- Required host-only Go gates pass on the implementer's working tree, or any pre-existing failures are documented with before/after evidence.
- No product/test code outside the native Go node/bridge validation and direct tests is changed for this session.

## Scope Guard

Non-goals:

- Do not require top-level no-device `member.PeerId` values to be libp2p peer IDs.
- Do not change group key distribution policy, ML-KEM requirements, key package validation, or Ed25519 public-key parsing.
- Do not change `Node.UpdateGroupConfig`'s public signature unless bridge preflight proves impossible; signature churn would be over-scoped.
- Do not alter Flutter app code, platform Kotlin/Swift bridge surfaces, database migrations, relay server storage, push notifications, or real network behavior.
- Do not normalize or rewrite all legacy group fixtures.
- Do not add simulator, physical-device, relay, or full-regression gates.

Overengineering for this session would include building a full schema validator, migrating historical configs, adding cryptographic key verification beyond existing tests, or changing active inbox recipient derivation semantics beyond what is needed to keep focused tests passing.

## Accepted Differences / Intentionally Out Of Scope

- Legacy no-device members remain more permissive than active device transport identities. That is intentional because current tests and historical configs use account-like peer IDs, while active device transport peer IDs must be dialable libp2p peer IDs.
- Bridge key-material validation remains separate from native active-device identity validation. The bridge can still require ML-KEM/key-distribution material where it already does, while native admission focuses on identity fields and dialable transport peer IDs.
- Stored configs manually injected by tests may bypass admission; this session closes public/native admission entry points, not every possible internal test setup.

## Dependency Impact

- Later group reliability work can assume admitted active device entries have the identity fields needed for dial targets, sender-device binding, and validator matching.
- Later migration or cleanup work may revisit legacy no-device `member.PeerId` strictness, but only after inventorying fixtures and compatibility data.
- If this plan changes to tighten no-device validation, downstream group-chat audit sessions and many existing fixtures must be re-scoped before implementation proceeds.

## Device/Relay Proof Profile

- Proof class: host-only native Go validation.
- Device proof: none. No Flutter device, iOS simulator, Android emulator, or physical-device run is required.
- Relay proof: none. No relay server process, relay backend, push path, or live network proof is required.
- Network note: tests may generate real libp2p peer IDs, and existing Go tests may use in-process/local libp2p helpers, but the acceptance proof is config admission behavior, not relay connectivity.
- Required evidence: RED/GREEN focused Go tests in `go-mknoon/node` and `go-mknoon/bridge` using the exact commands above.

## Reviewer Pass

- Sufficiency verdict: sufficient as-is.
- Missing files/tests/gates: none structural. The likely direct files are named, and the exact node/bridge Go gates from the breakdown are included.
- Stale or incorrect assumptions: none found. The plan accounts for the current lenient `groupPeerIdentityKey` behavior and for `Node.UpdateGroupConfig` not returning an error.
- Overengineering check: acceptable. The plan avoids global schema validation, no-device peer ID strictness, cryptographic public-key parsing, and simulator/relay proof.
- Decomposition check: sufficient. RED tests, narrow native helper, bridge preflight, fixture adjustment, and host-only gates are separately ordered.
- Minimum needed for sufficiency: no further structural change. Implementation should keep the exported bridge preflight wrapper tiny and should not change `Node.UpdateGroupConfig`'s signature.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: exact exported native validation wrapper name can be chosen during implementation, provided it delegates to the shared native admission helper and avoids duplicate bridge-only rules.
- Accepted differences: no-device legacy member IDs remain account-like/non-libp2p compatible; revoked/inactive historical devices remain tolerant; bridge key-distribution validation remains separate from native active-device identity validation.
- Final verdict: execution-ready. The plan has a RED-first regression contract, exact host-only gates, a dirty-worktree caution, an explicit compatibility boundary, and a Device/Relay Proof Profile.
