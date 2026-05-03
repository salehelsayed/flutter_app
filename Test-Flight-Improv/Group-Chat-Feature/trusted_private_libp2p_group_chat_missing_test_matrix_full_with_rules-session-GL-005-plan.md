# GL-005 Session Plan: Private-Only Visibility and Discoverability

Status: execution-ready

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-04-30T22:43:00+02:00 | Evidence Collector completed | `lib/features/groups/application/create_group_use_case.dart`; `lib/features/groups/application/create_group_with_members_use_case.dart`; `lib/features/groups/application/group_invite_listener.dart`; `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`; `lib/features/groups/presentation/screens/group_list_wired.dart`; `lib/features/groups/domain/models/group_model.dart`; `lib/core/bridge/bridge_group_helpers.dart`; `go-mknoon/node/pubsub.go`; `go-mknoon/bridge/bridge.go`; direct tests named by the breakdown | GL-005 is not already closed. Existing code is invite/listing based, but guard tests do not yet pin every private-only surface, and raw bridge group creation accepts a string `groupType` without validation. | Draft a regression-first, row-owned plan that starts with tests and patches only if they expose a real open route. |
| 2026-04-30T22:43:00+02:00 | Planner started | Evidence collector findings | No blocker. Classification remains `implementation-ready` and `needs_tests_only` with conditional row-owned patches if guard tests fail. | Write mandatory plan sections, gates, scope guard, dirty-worktree rule, and regression contract. |
| 2026-04-30T22:48:00+02:00 | Planner completed | Same evidence set plus `go-mknoon/bridge/bridge_test.go` and `test/core/bridge/bridge_group_helpers_test.dart` as conditional raw-bridge evidence | Draft plan written. The plan keeps GL-005 row-owned, starts with tests, and allows only exact guard fixes for discovered public/open routes. | Run strict reviewer pass for missing gates, stale assumptions, and scope drift. |
| 2026-04-30T22:52:00+02:00 | Reviewer completed | Full draft plan | Sufficient with no structural blocker. Raw bridge work is conditional, and the plan includes direct tests, named gate, closure docs, scope guard, dirty-worktree handling, and regression contract. | Arbiter should classify incremental details and finalize if no structural blocker appears. |
| 2026-04-30T22:55:00+02:00 | Arbiter completed | Full reviewer-pass plan | No structural blockers. Incremental details are documented and intentionally deferred. Plan is reusable and execution-ready. | Stop planning; do not execute this plan in this turn. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Command | Decision/blocker | Next action |
| --- | --- | --- | --- | --- | --- |
| 2026-04-30T22:41:23+02:00 | Orchestrator started before contract extraction | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-005-plan.md`; `implementation-execution-qa-orchestrator/SKILL.md`; `git status --short` | `git status --short`; `sed -n '1,260p' ...session-GL-005-plan.md`; `sed -n '1,220p' .../implementation-execution-qa-orchestrator/SKILL.md` | Dirty state contains pre-existing modified session breakdown artifact and untracked GL-005 plan; preserve both. | Extract execution contract and record exact scope/tests/gates before spawning Executor. |
| 2026-04-30T22:41:23+02:00 | Contract extracted | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-005-plan.md`; `implementation-execution-qa-orchestrator/SKILL.md` | `sed -n '261,520p' ...session-GL-005-plan.md`; `rg -n "^## Execution Progress|^## Final|verdict|done criteria|named gate" ...session-GL-005-plan.md`; `codex --help`; `codex exec --help` | Contract is execution-ready: GL-005 only, tests first, patch only concrete public/open routes exposed by tests, direct Flutter/Go tests plus `./scripts/run_test_gates.sh groups` and `git diff --check`; `codex exec` is available for spawned Executor/QA agents with `model=gpt-5.5` and `model_reasoning_effort=xhigh`. | Spawn Executor child for first implementation pass. |
| 2026-04-30T22:42:20+02:00 | Executor spawned/running | Plan and row-owned owner suites listed in contract | `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C ... --output-last-message /tmp/gl005-executor-result.md -` | Spawned Executor will add GL-005 guard tests first, patch only a concrete public/open route exposed by those tests, run required direct tests/gates as feasible, and preserve unrelated dirty files. | Wait for Executor result, then inspect files and evidence before QA. |
| 2026-04-30T22:43:13+02:00 | Executor spawn retry | No repo files touched beyond this progress row | `codex exec ... -a never ...` | Initial CLI invocation failed before child materialization because `-a` is a top-level flag, not an `exec` subcommand flag. | Relaunch Executor with corrected top-level approval flag ordering. |
| 2026-04-30T22:44:16+02:00 | Executor running | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-005-plan.md`; `implementation-execution-qa-orchestrator/SKILL.md`; `git status --short` | `git status --short`; `sed -n ...GL-005-plan.md`; `sed -n ...implementation-execution-qa-orchestrator/SKILL.md` | Executor contract accepted for GL-005 only. Dirty state still shows pre-existing modified session breakdown artifact and untracked GL-005 plan; preserve unrelated changes. | Inspect row-owned tests and add GL-005 guard tests before any production patch. |
| 2026-04-30T22:54:19+02:00 | Executor completed | `test/features/groups/application/create_group_use_case_test.dart`; `test/features/groups/application/create_group_with_members_use_case_test.dart`; `test/features/groups/application/group_invite_listener_test.dart`; `test/features/groups/presentation/group_list_wired_test.dart`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/bridge/bridge_test.go`; `go-mknoon/bridge/bridge.go` | Direct Flutter suites, Go node targeted regex, Go bridge regex, `./scripts/run_test_gates.sh groups`, `git diff --check`; broad Go node regex logged to `/tmp/gl005-go-node-broad.json` | Added GL-005 guards for create/config/invite/list/discovery. Conditional raw bridge guard first failed because unsupported public/open group types reached node join as `GROUP_ERROR`; patched `GroupCreate` to reject non-`chat`/`announcement`/`qa` group types with `INVALID_INPUT`. All direct commands passed except broad Go node regex, which failed only in known LP-006 `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` sender/transport mismatch path; GL-005 did not touch that publish path. | Ready for QA with known unrelated LP-006 caveat. |
| 2026-04-30T22:55:53+02:00 | Required tests/gates completed after Executor | `/tmp/gl005-executor-result.md`; `/tmp/gl005-go-node-broad.json`; GL-005 diff | `sed -n '1,220p' /tmp/gl005-executor-result.md`; `rg -n '"Action":"fail"|TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers|sender/transport|FAIL' /tmp/gl005-go-node-broad.json`; `git status --short`; `git diff --stat` | Executor handoff records all direct Flutter tests, targeted Go node tests, conditional bridge tests, `./scripts/run_test_gates.sh groups`, and `git diff --check` passing; broad Go node regex has only known LP-006 zero-peer sender/transport mismatch failure in `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers`. | Spawn QA Reviewer to verify scope, tests, known-failure classification, and closure sufficiency. |
| 2026-04-30T22:55:53+02:00 | QA Reviewer spawned/running | Plan, Executor handoff, GL-005 diff, known-failure log | `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C ... --output-last-message /tmp/gl005-qa-result.md -` | Separate QA Reviewer will inspect scope adherence, regressions, required test/gate evidence, and whether missing closure docs are blocking under this execution contract. | Wait for QA result; run one fix pass only if QA reports blocking issues. |
| 2026-04-30T22:59:25+02:00 | QA Reviewer completed | `/tmp/gl005-qa-result.md`; GL-005 diff; `/tmp/gl005-go-node-broad.json` | QA reran changed Flutter owner suites; `cd go-mknoon && go test ./bridge -run 'GroupCreate_GL005RejectsUnsupportedPublicOrOpenGroupTypes|GroupCreate_MissingFields' -v`; `cd go-mknoon && go test ./node -run 'TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse' -v`; `git diff --check` | QA found no blocking issues. Source matrix and `test-inventory.md` closure-doc updates are non-blocking follow-up for the closure agent under the user instruction; execution evidence is present in this plan and test output. | Stop per QA stop rule; no fix pass. |
| 2026-04-30T22:59:25+02:00 | Fix pass and final QA skipped | N/A | N/A | First QA pass found no blocking issues, so the bounded loop stops without an Executor fix pass or final QA pass. | Write final execution verdict. |
| 2026-04-30T22:59:25+02:00 | Final verdict written | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-GL-005-plan.md` | N/A | Final execution verdict: accepted. | Hand final summary to user. |

## Execution Verdict

Final execution verdict: accepted.

Spawned-agent isolation used: yes. Executor and QA Reviewer ran as separate `codex exec` agents with `model=gpt-5.5` and `model_reasoning_effort=xhigh`.

Local sequential fallback used: no.

Files changed by GL-005 execution:

- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/application/group_invite_listener_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/bridge/bridge.go`
- This GL-005 plan execution progress/verdict section

Pre-existing dirty file preserved and not owned by this execution: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.

Tests added or updated:

- GL-005 create payload guard for supported `chat`/`announcement`/`qa` variants and absence of public/open route fields.
- GL-005 selected-member-only config, `members_added`, and invite fanout guard.
- GL-005 public-preview-shaped unknown/blocked invite rejection guard with no pending/group/key/join state.
- GL-005 group-list guard proving only persisted active groups and valid pending invite rows render.
- GL-005 Go discovery guard proving non-members are filtered before dial/use.
- Conditional raw bridge guard proving unsupported public/open `groupType` values are rejected.

Production change:

- `go-mknoon/bridge/bridge.go` now validates `GroupCreate` `groupType` against `chat`, `announcement`, and `qa` before joining a topic. This was justified by the new bridge guard failing red when unsupported values reached topic join and returned `GROUP_ERROR`.

Exact tests and gates run:

- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart` - passed.
- `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart` - passed.
- `flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart` - passed.
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart` - passed.
- `flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart` - passed.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` - passed.
- `cd go-mknoon && go test ./node -run "GL005|GroupRendezvousNamespace|GroupTopicAndRendezvousNamespace|FilterDiscoveredGroupMembers|DiscoverAndConnectGroupPeers|GroupDiscovery" -v` - passed.
- `cd go-mknoon && go test ./node -run "Group|PubSub|Rendezvous" -v` - failed only in known unrelated LP-006 `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` sender/transport mismatch path; evidence captured in `/tmp/gl005-go-node-broad.json`.
- `cd go-mknoon && go test ./bridge -run "GroupCreate|GroupJoinTopic" -v` - passed.
- `./scripts/run_test_gates.sh groups` - passed.
- `git diff --check` - passed.
- QA reran the changed Flutter owner suites together - passed.
- QA reran `cd go-mknoon && go test ./bridge -run 'GroupCreate_GL005RejectsUnsupportedPublicOrOpenGroupTypes|GroupCreate_MissingFields' -v` - passed.
- QA reran `cd go-mknoon && go test ./node -run 'TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse' -v` - passed.

Blocking issues remaining: none.

Non-blocking follow-up deferred: closure agent should update the source matrix GL-005 row and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` with this exact evidence. This was intentionally not done in this execution pass per the user instruction to prefer leaving source matrix/test-inventory closure updates to the closure agent.

## Evidence Collector Notes

- Source scope: `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md` says trusted-private groups are private, invite-only, and not public chat rooms. Public listing, public discoverability, open auto-join, public join requests, and public-room workflows are out of release scope unless later enabled. The GL-005 expected result is that only invited or authorized identities can discover usable metadata or join material.
- Breakdown scope: GL-005 is `Open`, `needs_tests_only`, `implementation-ready`, and must add focused tests for private-only admission/listing surfaces. It may patch only if guard tests expose an open route.
- Dirty worktree: `git status --short` showed a pre-existing modified `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`. The implementation must preserve that user/controller change and keep this session scoped to GL-005 changes.
- Product model: `GroupType` in `lib/features/groups/domain/models/group_model.dart` has only `chat`, `announcement`, and `qa`. It does not expose public/private visibility or open-join fields.
- Create flow: `createGroup` passes `type.toValue()` to `callGroupCreate`, persists only the creator/admin member, uses `/mknoon/group/$groupId` fallback topic naming, and stores key material only after bridge create/keygen succeeds.
- Create-with-members flow: `createGroupWithMembers` creates a group, adds only `selectedContacts` as members, builds `groupConfig` from persisted members, updates Go config, publishes a `members_added` payload with added members, and sends per-recipient P2P invites only to successfully added contacts.
- Invite intake: `GroupInviteListener` checks blocked senders before pending storage. `handle_incoming_group_invite_use_case.dart` rejects invalid payloads, transport-sender mismatch, recipient mismatch, unknown senders, revoked/consumed pending copies, duplicate groups, and empty key material before local group/key state or `group:join`.
- Listing surface: `GroupListWired` loads only `groupRepo.getActiveGroups()` plus pending invite rows supplied by `GroupInviteListener.pendingInviteRepo`; there is no public catalog/read API in this screen.
- Go topic/discovery surface: `JoinGroupTopic` joins `/mknoon/group/<groupId>`, stores config/key, starts subscription and discovery. `groupRendezvousNamespace` also returns `/mknoon/group/<groupId>`. Discovery filters discovered peers against `groupConfigs[groupId].Members` when that config is present. Existing `pubsub_test.go` already covers namespace shape, metadata minimization, and helper-level non-member filtering, but not the full GL-005 private-only guard matrix.
- Potential exposed gap to test first: `go-mknoon/bridge/bridge.go` documents allowed `groupType` values as `chat|announcement|qa`, but `GroupCreate` currently casts the incoming string into `node.GroupType` without explicit validation. Direct raw bridge tests for `public`, `private`, `broadcast`, `discoverable`, or `openJoin` style flags may expose a real creation-route gap.

## real scope

This session owns GL-005 only: prove that trusted-private group visibility and discoverability remain invite-only across creation, local listing, pending invite preview, and Go topic/rendezvous discovery.

In scope:

- Add focused tests to the row-owned suites named by the breakdown.
- Verify create payloads and group config payloads do not expose public visibility, public discovery, invite-link, open-join, or public-preview fields.
- Verify local group listing shows only persisted active groups and pending invite rows created by the invite listener/storage path.
- Verify unauthorized, non-contact, blocked, wrong-recipient, invalid, or public-preview-shaped invite traffic cannot create a pending row, local group row, key row, or `group:join` call.
- Verify Go rendezvous discovery does not turn discovered non-members into usable group peers when a group config is present.
- If tests expose a real gap, patch only that exact GL-005 route.

Out of scope:

- Building public groups, invite links, open join requests, public moderation, anti-spam, report workflows, ban policy, or server-authoritative rosters.
- Reworking the group membership architecture, per-device identity model, invite signatures, revocation semantics, or real-network relay topology.
- Closing IJ-009, IJ-013, LP-002, LP-003, or SP rows; those have separate sessions.

## closure bar

GL-005 is good enough when repo tests prove that:

- Product create flows can create only supported trusted group variants (`chat`, `announcement`, `qa`) and do not send public visibility/open-join flags.
- Group metadata and join material appear only through owned local state or pending invites from accepted invite-intake rules.
- Unauthorized identities D/X cannot get a pending preview, active list row, group key, local group state, or bridge join from listing, invite, or discovery surfaces covered by this row.
- Go discovery either uses group-scoped opaque identifiers or filters non-members before dialing/using discovered peers.
- The source matrix row can later be updated from `Open` only with concrete file, test, and gate evidence.

## source of truth

Authoritative sources, in order:

1. Current code and tests in the row-owned files.
2. `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, row `GL-005`.
3. `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, session `GL-005`.
4. `scripts/run_test_gates.sh` for named gate execution.
5. `Test-Flight-Improv/test-gate-definitions.md` for gate intent when the script and docs agree.
6. `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` for existing evidence and known residuals.

If prose conflicts with current code or tests, current code and tests win. If gate prose conflicts with `scripts/run_test_gates.sh`, the script wins.

## session classification

`implementation-ready`

This is still a `needs_tests_only` row at intake. Implementation must begin by adding guard tests. Product or Go code changes are allowed only if those tests expose a concrete private-only gap in a GL-005 surface.

## exact problem statement

The product now scopes group chat to trusted, private, invite-only groups, but GL-005 has no direct row-owned proof that public listing/discoverability/open join routes are hidden or rejected across the current creation, invite, listing, and rendezvous surfaces.

The risky behavior to prevent is any route where D or X can see usable group metadata, get pending preview rows, receive group join material, create group/key state, join a group topic, or get dialed as a group peer without being an invited/current authorized member.

User-visible behavior that must improve: the shipped app must keep group list and pending-invite surfaces truthful to private membership/invite state only.

Behavior that must stay unchanged: trusted invite creation, pending invite review, explicit accept, existing active group listing, group topic join for valid invite material, and member-only group delivery.

## files and repos to inspect next

Primary owner production files:

- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/rendezvous.go`

Primary owner tests:

- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/application/group_invite_listener_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `go-mknoon/node/pubsub_test.go`

Conditional inspect/patch files only if regression tests expose a public/open create route:

- `lib/core/bridge/bridge_group_helpers.dart`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`

## existing tests covering this area

Existing coverage to preserve:

- `create_group_use_case_test.dart` covers successful create, creator/admin persistence, key persistence, signed initial event behavior, canonical `/mknoon/group/<groupId>` fallback, and announcement type persistence.
- `create_group_with_members_use_case_test.dart` covers selected contact member persistence, config update payloads, `members_added` publish payloads, invite fanout, excluded failed member fanout, config-sync rollback, and announcement propagation.
- `group_invite_listener_test.dart` covers valid invite storage as pending, unknown sender rejection, duplicate group rejection, decrypt failure, blocked sender rejection, duplicate pending invite replacement, and no immediate join on pending invite storage.
- `handle_incoming_group_invite_use_case_test.dart` covers unknown sender, sender mismatch, bound-recipient mismatch, invalid payload, empty join material, decryption failure, materialized accept, and group join payload behavior.
- `group_list_wired_test.dart` covers active group loading, pending invite loading, pending invite stream refresh, accept/decline flows, repair-pending behavior, and load error handling.
- `go-mknoon/node/pubsub_test.go` covers namespace shape, metadata minimization, filter helper behavior, validator non-member rejection, join/leave state, config updates, and discovery fallback.
- `./scripts/run_test_gates.sh groups` includes `group_membership_smoke_test.dart` and other group messaging/invite/resume smoke suites.

Missing GL-005 proof:

- No test explicitly asserts product create/config/invite payloads omit public visibility, public listing, open join, invite-link, or discoverable flags.
- No test explicitly ties group-list visibility to active groups plus valid pending invites while rejecting public-preview-shaped or unauthorized invite metadata.
- No full-path Go discovery test proves non-members returned by rendezvous are ignored before becoming usable group peers for a configured private group.
- No raw bridge guard test proves `GroupCreate` rejects unsupported public/open `groupType` values even though the bridge comment documents only `chat|announcement|qa`.

## regression/tests to add first

Add tests before any implementation patch:

1. `create_group_use_case_test.dart`
   - Add a GL-005 test that calls `createGroup` for each supported `GroupType` and inspects the `group:create` payload.
   - Assert `groupType` is one of `chat`, `announcement`, `qa`.
   - Assert payload omits `visibility`, `isPublic`, `discoverable`, `openJoin`, `joinPolicy`, `inviteLink`, `publicPreview`, `publicListing`, and equivalent public/open flags.

2. `create_group_with_members_use_case_test.dart`
   - Add a GL-005 test that creates a group with selected contacts plus an unselected contact present in fixture scope.
   - Assert stored members, `group:updateConfig`, `members_added`, and invite fanout include only creator plus successfully added selected contacts.
   - Assert no public/open visibility flags appear in config, publish, or invite payloads.

3. `group_invite_listener_test.dart` and/or `handle_incoming_group_invite_use_case_test.dart`
   - Add a GL-005 test for a public-preview-shaped `group_invite` payload from an unknown or blocked sender.
   - Assert no pending invite row, no pending stream event, no group row, no key row, and no `group:join`.
   - Add a wrong-recipient or unbound public-looking payload variant only if it does not duplicate IJ-009/IJ-013 coverage.

4. `group_list_wired_test.dart`
   - Add a GL-005 widget test proving the shipped list renders only persisted active groups and valid pending-invite rows from `pendingInviteRepo`.
   - Assert no row appears from a plain stream event or public preview unless the pending invite repository contains a valid pending invite.

5. `go-mknoon/node/pubsub_test.go`
   - Add a GL-005 test around discovery filtering for a configured group: rendezvous returns one member and one non-member; only the configured member is eligible for dialing/use, and the non-member is counted/ignored.
   - If practical without real network flake, test `discoverAndConnectGroupPeers`; otherwise add a focused helper-level regression with a name that documents GL-005 private-only discovery.

6. Conditional raw bridge guard
   - Add `go-mknoon/bridge/bridge_test.go` coverage only if the implementation treats raw bridge `groupType` as a private-only creation route.
   - The test should assert `GroupCreate` rejects unsupported values such as `public`, `private`, `broadcast`, `discoverable`, and empty/open-join-shaped input with `INVALID_INPUT`.
   - If this fails, patch `go-mknoon/bridge/bridge.go` with explicit enum validation and keep Flutter bridge-helper tests aligned with supported values only.

## step-by-step implementation plan

1. Start from the dirty worktree:
   - Run `git status --short`.
   - Confirm the pre-existing modified breakdown artifact is still unrelated.
   - Do not revert or reformat it.

2. Add regression tests in the direct owner suites first:
   - Prefer adding to existing files over creating new files.
   - Use existing fakes: `FakeBridge`, `PassthroughCryptoBridge`, `FakeP2PService`, `InMemoryGroupRepository`, `InMemoryPendingGroupInviteRepository`, and current widget harnesses.
   - Prefix or name tests with GL-005 language where useful for closure traceability.

3. Run the smallest direct test set that covers the newly added assertions.

4. If all new tests pass without product changes:
   - Do not change product code.
   - Record that GL-005 is closed by new guard tests against existing behavior.

5. If a new test exposes an open route:
   - Patch only the exposed route.
   - Likely narrow fixes are:
     - remove public/open fields from payload construction if any were emitted,
     - add explicit allowed `groupType` validation in `go-mknoon/bridge/bridge.go`,
     - fail closed in Go discovery when a configured private group cannot produce an allowed member set,
     - or keep pending invite/list rendering gated on valid repository state only.
   - Do not change invite signatures, revocation, device identity, ban policy, or public group product behavior.

6. Rerun direct tests, the named group gate, and `git diff --check`.

7. Update closure docs only after tests pass:
   - Source matrix row `GL-005` must become `Closed` or `Covered` with concrete files, tests, commands, and caveats.
   - `test-inventory.md` must record the GL-005 evidence.
   - The session breakdown ledger can be updated by the pipeline controller after execution/closure, not by this plan.

Stop if the first regression pass proves the requested route belongs to another row such as IJ-009, IJ-013, LP-002, LP-003, or SP-002. Record the accepted difference instead of broadening GL-005.

## risks and edge cases

- Raw bridge creation may accept unsupported `groupType` values even if product UI never sends them.
- Go discovery currently treats an empty allowed-member set as "allow all" at helper level. That may be acceptable for a no-config fallback or may be too open for GL-005; tests should clarify before patching.
- Pending invite previews intentionally expose safe metadata to an invited known contact before accept. Do not remove valid pending invite review.
- Invalid public-looking invite payloads must fail without group/key state and without `group:join`.
- Group list must remain responsive to legitimate pending invite streams and active group refreshes.
- The broader Go regex from the breakdown may include a known unrelated LP-006 zero-peer failure; classify that carefully.

## exact tests and gates to run

Direct Dart tests:

```bash
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart
flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart
flutter test --no-pub test/features/groups/presentation/group_list_wired_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
```

Direct Go tests:

```bash
cd go-mknoon && go test ./node -run "GL005|GroupRendezvousNamespace|GroupTopicAndRendezvousNamespace|FilterDiscoveredGroupMembers|DiscoverAndConnectGroupPeers|GroupDiscovery" -v
cd go-mknoon && go test ./node -run "Group|PubSub|Rendezvous" -v
```

Conditional Go bridge tests if raw bridge creation is patched:

```bash
cd go-mknoon && go test ./bridge -run "GroupCreate|GroupJoinTopic" -v
```

Named gate and hygiene:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

Optional only if a new test file is created:

```bash
./scripts/run_test_gates.sh completeness-check
```

Matrix smoke scenario for closure evidence:

- `TP-SMOKE-01`: create a trusted-private group, add trusted contacts, reject non-trusted identities, and keep membership deterministic across restart.

## known-failure interpretation

- Treat failures in newly added GL-005 assertions as row-owned until proven otherwise.
- If `cd go-mknoon && go test ./node -run "Group|PubSub|Rendezvous" -v` still fails only in the pre-existing LP-006 zero-peer proof (`TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` / sender-transport mismatch) and GL-005 code did not touch that path, record it as an unrelated known failure rather than a GL-005 regression.
- If GL-005 changes touch `pubsub.go` discovery or member filtering, rerun the failing Go test and do not classify a changed failure as unrelated without evidence.
- Do not close GL-005 if any direct GL-005 test fails, if the `groups` gate regresses in a related group admission/listing path, or if `git diff --check` fails.

## done criteria

- New GL-005 tests exist in the direct owner suites and pass.
- Any exposed public/open route is patched narrowly and covered by a failing-then-passing test.
- Product behavior remains private/invite-only; no public group feature is introduced.
- Direct Flutter tests, direct Go tests, `./scripts/run_test_gates.sh groups`, and `git diff --check` pass or have clearly documented unrelated pre-existing failures.
- Source matrix row `GL-005` is updated to `Closed` or `Covered` only with concrete evidence.
- `test-inventory.md` records the GL-005 evidence and any accepted caveats.
- No unrelated dirty-worktree changes are reverted or bundled into closure.

## scope guard

This session must not:

- Add public groups, public discovery, join links, public catalog APIs, open auto-join, join request queues, moderation/reporting, or anti-spam workflows.
- Rebuild invite cryptography, device identity, key-package distribution, ban policy, or live relay/device labs.
- Change unrelated group message send/receive, media, notification, archive, dissolve, or database migration behavior.
- Expand named gates.
- Turn GL-005 into acceptance-only or evidence-only.
- Update the source matrix to `Closed` or `Covered` without passing direct tests and concrete file/test evidence.

## accepted differences / intentionally out of scope

- Safe pending invite preview for a known invited contact is intentionally in scope and should remain visible before accept.
- Invite signature and inviter authorization depth belongs to IJ-002.
- Open auto-join through copied tokens or unbound join payloads belongs primarily to IJ-009 unless discovered through GL-005 create/list/discover guard tests.
- Wrong device/recipient identity binding belongs primarily to IJ-013 unless the GL-005 public-preview test exposes group/key/list state.
- Public-room moderation, report, anti-spam, or ban workflows remain outside the trusted-private release scope.
- Real relay packet-capture or device-lab metadata minimization belongs to SP-002 unless a GL-005 direct test shows repo behavior needs a fix.

## dependency impact

- GL-005 is first in the trusted-private session breakdown. Later invite/admission rows should rely on GL-005 proving there is no accidental public listing/create/discover surface.
- If GL-005 exposes a raw bridge type validation gap, later bridge and invite tests should use only supported group types.
- If GL-005 exposes a Go discovery fail-open route, LP-002/LP-003/SP-002 plans should account for the tightened member filter as existing behavior.
- If GL-005 cannot close without device/relay proof, later evidence-gated topology sessions should not assume this row is resolved.

## regression contract

- First add tests that fail on any accidental public/open visibility route.
- Patch only the smallest route proven by a failing test.
- Preserve existing valid private invite, pending review, active list, group join, and member-only discovery behavior.
- Re-run direct suites plus `groups` gate before closure.
- Closure evidence must include exact files changed, exact test commands, pass/fail outcomes, and known-failure classification.

## dirty-worktree handling

- Preserve the pre-existing modified breakdown artifact.
- Before implementing, run `git status --short` and note unrelated dirty files.
- Do not use `git reset`, `git checkout --`, or broad formatters.
- If a row-owned file has unrelated user edits, inspect and work around them rather than reverting.

## Device/Relay Proof Profile

No device/relay proof profile is required for this GL-005 plan as drafted. The row can be closed through host-side Flutter tests plus Go unit/fake discovery tests because the owned gap is private-only creation/listing/pending-invite/discovery guard coverage, not real-network relay behavior. Add a device/relay proof profile only if direct evidence shows the leak exists only under simulator, real-network, relay, multi-relay, three-party, OS notification, or `integration_test` conditions.

## Reviewer Pass

Verdict: sufficient as drafted.

Sufficiency answers:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is.
- What files, tests, regressions, or gates are missing? No structural missing files. `handle_incoming_group_invite_use_case_test.dart`, `go-mknoon/bridge/bridge_test.go`, and `test/core/bridge/bridge_group_helpers_test.dart` are included as necessary direct or conditional tests even though the breakdown's likely-test list was narrower.
- What assumptions are stale or incorrect? None found. The plan treats current code/tests as stronger than stale public/private bridge-helper examples.
- What is overengineered? Raw bridge validation could become over-broad if implemented without a failing GL-005 test. The plan keeps it conditional.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It starts with direct assertions in existing suites and narrows code changes to failed guard routes only.
- What is the minimum needed to make the plan sufficient? Keep the regression-first rule, conditional bridge scope, named gate contract, source-matrix closure bar, and dirty-worktree guard.

## Arbiter Decision

Final verdict: execution-ready reusable GL-005 plan.

Final plan: use the mandatory sections above as the execution contract. Start with direct GL-005 guard tests, patch only failed guard routes, and close the row only with source-matrix and inventory evidence.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact GL-005 test names can be finalized during implementation.
- Full-path Go discovery testing may fall back to helper-level proof if a non-flaky full-path harness is not practical.
- Raw bridge validation remains conditional on a failing GL-005 guard test instead of becoming unconditional bridge cleanup.

Accepted differences intentionally left unchanged:

- Safe pending invite preview remains valid for known invited contacts.
- IJ-009, IJ-013, LP-002, LP-003, and SP-002 keep their own broader admission, identity, forward-path, unsubscribe, and metadata-minimization work.
- No device/relay proof profile is required unless direct implementation evidence shows host-side tests cannot prove the leak.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/bridge/bridge.go`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/application/group_invite_listener_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/bridge/bridge_test.go`

Why the plan is safe to implement now:

- It is row-owned to GL-005 and does not introduce public group features.
- It starts with tests and patches only routes proven open by those tests.
- It has an explicit closure bar, scope guard, regression contract, dirty-worktree rule, named gate list, known-failure handling, and documentation closure criteria.
- It does not require device/relay proof based on current evidence.
