# GM-028 Session Plan: Empty PeerId Rejection Before Config Install

Status: ready for closure audit after controller race recovery

## Planning Progress

- 2026-05-11T14:59:49Z | Evidence Collector started | Files inspected since last update: `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`, target plan path existence check | Decision/blocker: plan artifact created for GM-028; no blocker yet | Next action: inspect the source matrix row, breakdown row, GM-027 closure context, and direct group membership/publish code/tests.
- 2026-05-11T15:01:31Z | Evidence Collector completed / Planner started | Files inspected since last update: source matrix GM-027/GM-028 rows; breakdown GM-027 closure and row 44 / GM-028 entries; `group_config_payload.dart`; `add_group_member_use_case.dart`; `remove_group_member_use_case.dart`; `group_message_listener.dart`; `group_key_update_listener.dart`; `send_group_message_use_case.dart`; `bridge_group_helpers.dart`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/group_inbox.go`; direct Flutter/Go tests; `Test-Flight-Improv/test-gate-definitions.md`; `git status --short` | Decision/blocker: GM-028 remains Open and lacks exact row-owned proof; GM-027 deliverable-identity filtering helps but does not prove empty PeerId rejection or publish/discovery preflight safety. Existing worktree is dirty across likely owner files. | Next action: draft a narrow implementation-ready code+test plan with regression-first gates and dirty-state guard.
- 2026-05-11T15:02:44Z | Planner completed / Reviewer started | Files inspected since last update: no new files; synthesized collected evidence into this GM-028 draft | Decision/blocker: draft is implementation-ready and regression-first; direct product changes are conditional on exact GM-028 RED results, but the session is not docs-only because no current concrete tests prove the row. | Next action: review sufficiency for missing files, stale assumptions, overbroad scope, and closure/gate completeness.
- 2026-05-11T15:04:37Z | Reviewer completed / Arbiter started | Files inspected since last update: this GM-028 plan draft and section checklist | Decision/blocker: sufficient with adjustments; no structural blocker after adding conditional `group_key_update_listener_test.dart` coverage and targeted analyzer to the gate contract. | Next action: arbitrate reviewer findings and finalize execution-ready status if no structural blocker remains.
- 2026-05-11T15:05:11Z | Arbiter completed | Files inspected since last update: this GM-028 reviewer-adjusted plan | Decision/blocker: no structural blockers remain; incremental details are deferred to execution evidence. The plan is execution-ready for GM-028 only. | Next action: hand off to implementation; do not write source-matrix closure or any final program verdict in this planning pass.

## Final Verdict

Final verdict: GM-028 is `execution-ready` / `implementation-ready` for one code-and-test session. It should not be closed by GM-027 evidence alone. Existing GM-027 deliverable-identity filtering is relevant prior art, but GM-028 still needs row-owned proof that an explicitly empty or whitespace `peerId` is rejected before config install and cannot inflate publish/discovery preflight or durable recipient targets.

## Execution Progress

- 2026-05-11T15:06:47Z | Contract extracted / Executor spawn pending | Files inspected or touched: this GM-028 plan; `Test-Flight-Improv/test-gate-definitions.md`; `git status --short` | Decision/blocker: execution contract is explicit; source matrix and session-breakdown are out of execution write scope; worktree is dirty in expected GM-027/group files and must be preserved. | Next action: spawn isolated Executor with GM-028 scope, regression-first instructions, and required direct gates.
- 2026-05-11T15:07:11Z | Executor spawned/running | Files inspected or touched: this GM-028 plan | Command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -a never -s danger-full-access -C /Users/I560101/Project-Sat/mknoon-2/flutter_app` | Decision/blocker: none yet. | Next action: wait for Executor result, then inspect landed code/test/doc evidence before spawning QA Reviewer.
- 2026-05-11T15:07:33Z | Executor spawn command corrected | Files inspected or touched: this GM-028 plan | Command result: first spawn failed before agent materialization because approval policy flag must be top-level for this CLI. | Decision/blocker: no child work occurred; relaunching with corrected top-level `codex -a never exec ...` form. | Next action: wait for Executor result.
- 2026-05-11T15:08:58Z | Executor local pass started | Files inspected or touched: this GM-028 plan; `git status --short`; dirty diffs for `group_config_payload.dart`, `add_group_member_use_case.dart`, `group_message_listener.dart`, `send_group_message_use_case.dart`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/group_inbox.go`; existing GM-027 test neighborhoods in add/listener/send/remove/smoke/Go tests | Decision/blocker: no exact GM-028 selectors exist yet; prior GM-027 code appears to cover several shared normalization paths, while Go inbox request construction currently preserves blank recipients and needs row-owned proof. | Next action: add GM-028 regressions first, then run focused selectors for RED/GREEN evidence before any product patch.
- 2026-05-11T15:12:46Z | GM-028 regressions added / focused RED-GREEN run starting | Files inspected or touched: `add_group_member_use_case_test.dart`, `group_message_listener_test.dart`, `member_removal_integration_test.dart`, `send_group_message_use_case_test.dart`, `group_membership_smoke_test.dart`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_inbox_test.go` | Decision/blocker: tests are additive and use whitespace top-level `peerId` with otherwise valid key/device fields; no production code patched yet. | Next action: run exact GM-028 focused selectors and classify any failures before fixing.
- 2026-05-11T15:13:54Z | Focused RED/GREEN evidence collected / narrow Go fix applied | Files inspected or touched: `go-mknoon/node/group_inbox.go`; focused test outputs for Flutter GM-028 selectors and Go node selector | Command results: `flutter test --no-pub ...add_group_member_use_case_test.dart --plain-name 'GM-028'` PASS; `...group_message_listener_test.dart --plain-name 'GM-028'` PASS; `...member_removal_integration_test.dart --plain-name 'GM-028'` PASS; `...send_group_message_use_case_test.dart --plain-name 'GM-028'` PASS; `...group_membership_smoke_test.dart --plain-name 'GM-028'` PASS; `go test ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1` RED only on `TestGM028BuildGroupInboxStoreRequestDropsBlankRecipientPeerIds` because blank/whitespace recipients were forwarded. | Decision/blocker: Dart product changes not needed; patched only `buildGroupInboxStoreRequest` to trim/drop blank recipients before marshaling. | Next action: format touched files and rerun focused Go/Flutter selectors, then adjacent GM-027/direct gates.
- 2026-05-11T15:15:11Z | Focused GREEN confirmed / adjacent gates starting | Files inspected or touched: formatted GM-028 Dart and Go tests plus `go-mknoon/node/group_inbox.go` | Command results: post-format GM-028 Flutter selectors all PASS; `go test ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1` PASS; `go test -race ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1` PASS. | Decision/blocker: only required product patch remains Go inbox recipient normalization; no Flutter product patch needed. | Next action: run GM-027 focused selectors, direct suites, analyzer, named gates, and hygiene.
- 2026-05-11T15:17:34Z | Adjacent direct suites and GM-027 shared-path checks complete | Files inspected or touched: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `go-mknoon/node/group_inbox.go`, `go-mknoon/node/group_inbox_test.go`, `go-mknoon/node/pubsub_test.go` | Command results: GM-027 focused Flutter selectors in add/listener/send/smoke all PASS; full direct Flutter suites for add/listener/member_removal/send/smoke all PASS; `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` PASS; `go test ./node -run 'GroupInbox|GroupTopicValidator|UpdateGroupConfig|GroupDiscovery|GM027|GM028' -count=1` PASS. | Decision/blocker: GM-027 behavior preserved after the shared inbox helper change; no key-update listener code changed, so the conditional GM-028 key-update selector was not applicable. | Next action: run targeted analyzer and named gates.
- 2026-05-11T15:18:08Z | Analyzer and group gate complete | Files inspected or touched: targeted Dart owner files and tests listed in this plan; `scripts/run_test_gates.sh` output | Command results: targeted `dart analyze ...` exited 0 with 18 info-level existing style diagnostics in `bridge_group_helpers.dart`, `group_key_update_listener.dart`, and `group_key_update_listener_test.dart`; `./scripts/run_test_gates.sh groups` PASS with all tests passed. | Decision/blocker: analyzer produced no errors or warnings and no GM-028-touched lint blocker; group gate confirms the new `GM-028 empty PeerId add event does not persist or block valid delivery` smoke coverage. | Next action: run completeness and diff hygiene.
- 2026-05-11T15:19:08Z | Executor evidence complete / ready for QA handoff | Files inspected or touched: `git status --short`; `git diff --check`; GM-028 plan heartbeat | Command results: `./scripts/run_test_gates.sh completeness-check` PASS with `731/731 test files classified`; `git diff --check` PASS; `git status --short` still shows broad prior dirty state plus GM-028 touched files, with no unrelated files reverted. | Decision/blocker: row-owned regressions prove existing Dart guards already cover empty/whitespace peer IDs; only Go inbox request construction needed a product guard to trim/drop blank recipients while preserving valid recipients. Residual uncertainty: final matrix/session-breakdown closure remains outside Executor scope. | Next action: hand off to QA Reviewer.
- 2026-05-11T15:20:55Z | QA Reviewer spawned/running | Files inspected or touched: this GM-028 plan | Command: `codex -a never exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -C /Users/I560101/Project-Sat/mknoon-2/flutter_app` | Decision/blocker: none yet; reviewer is read-only and scoped to GM-028 landed diffs, plan evidence, and required gates. | Next action: wait for QA verdict and run a bounded fix pass only if blocking issues are found.
- 2026-05-11T15:24:19Z | QA Reviewer completed | Files inspected or touched: this GM-028 plan, GM-028-owned diffs, row-owned tests, and `go-mknoon/node/group_inbox.go` | Command results: reviewer reran `git diff --check`, `(cd go-mknoon && go test ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1)`, and `(cd go-mknoon && go test -race ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1)`; all PASS. | Decision/blocker: QA verdict `accepted_with_explicit_follow_up`; no blocking issues. Non-blocking follow-up is the later closure/audit pass for source matrix and session-breakdown rows. | Next action: write final execution verdict in this GM-028 plan only.
- 2026-05-11T15:24:19Z | Final execution verdict written | Files inspected or touched: this GM-028 plan | Decision/blocker: GM-028 execution is accepted with explicit follow-up; no fix pass required; source matrix, session-breakdown closure rows, and final program verdict were intentionally not modified in this execution. | Next action: later closure/audit pass may close GM-028 using this row-owned evidence.
- 2026-05-11T15:25:36Z | Controller focused rerun found repo-owned race | Files inspected or touched: focused GM-028 Flutter selector output, Go non-race selector output, Go race selector output, `go-mknoon/node/node.go` | Command results: controller reran `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/member_removal_integration_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-028'` and it passed with `00:01 +5: All tests passed!`; controller reran `(cd go-mknoon && go test ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1)` and it passed; controller reran `(cd go-mknoon && go test -race ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1)` and it failed with a race between `Node.Stop` clearing `n.eventSub`/node lifecycle state and `watchConnectionEvents` reading `n.eventSub.Out()`. | Decision/blocker: race is repo-owned and blocks GM-028 closure because the source row explicitly requires race-detector safety. | Next action: patch the narrow node lifecycle race before closure.
- 2026-05-11T15:28:07Z | Controller race recovery completed | Files inspected or touched: `go-mknoon/node/node.go`; this GM-028 plan | Decision/blocker: `watchConnectionEvents` now receives the startup event subscription as an argument and returns early for nil, so the watcher no longer reads `n.eventSub` after `Stop` can close and clear that shared field. `gofmt -w go-mknoon/node/node.go` passed. Controller rerun `(cd go-mknoon && go test -race ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1)` passed with `ok github.com/mknoon/go-mknoon/node 1.888s`. | Next action: rerun non-race Go selector and diff hygiene, then hand GM-028 to closure audit.

## Final Execution Verdict

Final execution verdict: ready for closure audit after controller recovery.

GM-028 now has row-owned proof for empty/whitespace top-level `peerId` rejection before save/config sync, inbound `member_added` / `members_added` and authoritative snapshot normalization, stale/corrupt local blank-member exclusion during config-producing operations, durable recipient/retry filtering, Go publish/discovery expected-count safety, and group inbox blank-recipient filtering.

Product changes were limited to `go-mknoon/node/group_inbox.go`, where `buildGroupInboxStoreRequest` now trims and drops blank recipient peer IDs before marshaling while preserving valid recipients, plus the controller recovery in `go-mknoon/node/node.go`, where `watchConnectionEvents` uses the startup subscription argument instead of reading `n.eventSub` after `Stop` can close and clear it. The new Flutter GM-028 regressions passed against existing Dart guards, so no Flutter production patch was needed.

Required focused selectors, Go `-race`, adjacent GM-027 checks, direct suites, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` passed. QA found no blocking issues. The only explicit follow-up is a later closure/audit pass to update the GM-028 source matrix and session-breakdown closure rows; this execution did not modify those artifacts or any final program verdict.

## Final Plan

### real scope

Own exactly source row GM-028: `Member with empty PeerId is rejected before config install`.

In scope:

- Add exact GM-028 regressions for empty or whitespace top-level `peerId` in local add, inbound `member_added` / `members_added`, authoritative config snapshots, stale/corrupt local member state, Go discovery target counts, Go publish preflight expected counts, and Go group inbox recipient request construction if current behavior forwards blank recipients.
- Implement only the minimum missing guards exposed by those regressions. Expected guard surfaces are peer ID trimming/rejection before save/config sync, normalized config payload construction, listener authoritative snapshot install, send/durable recipient filtering, Go config cloning/discovery target derivation, and Go group inbox request recipient filtering.
- Keep fake peer IDs valid in Flutter tests where existing host tests rely on them. Strict libp2p peer decoding belongs on the Go dial/discovery side unless the exact GM-028 failure proves otherwise.

Out of scope:

- No source matrix closure edit in this implementation plan.
- No final program verdict.
- No broad redesign of membership identity, key-package binding, onboarding, or simulator proof harnesses unless a GM-028 regression proves that path is the failing path.

### closure bar

GM-028 is good enough only when concrete row-owned evidence shows all of the following:

- A local add with empty or whitespace `peerId`, even if it carries otherwise deliverable key/device fields, fails before local save and before `group:updateConfig`.
- An inbound malformed `member_added` or `members_added` payload with empty or whitespace `peerId` is ignored before local persistence and before config install as an active member; any bridge config sync uses a normalized config that excludes the malformed member.
- A malformed empty-peer member already present in local state cannot survive the next config-producing operation or appear in durable `recipientPeerIds` / retry payloads.
- Go `UpdateGroupConfig` / config cloning / discovery target calculation exclude empty-peer members, including entries that contain otherwise valid device transport data.
- Publish preflight expected-member counts and discovery counters are based only on valid non-empty remote targets and cannot wait on, dial, or count the malformed empty-peer member.
- If Go group inbox request construction can receive blank `recipientPeerIds`, it trims/drops them before marshaling while preserving valid recipients.
- Source matrix row GM-028 can later be changed from Open to Covered/Closed with exact tests and command evidence from this session.

### source of truth

Authoritative sources, in order:

- Current code and tests in this repo.
- Source matrix row GM-028 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- Breakdown row 44 / GM-028 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`; if they disagree, the script wins.
- GM-027 closure docs only define the boundary: they prove no-key/no-device and malformed device-less ghost handling, not this empty-peer row.

### session classification

`implementation-ready`.

This is not `acceptance-only`, `evidence-gated`, or `stale/already-covered` because no current concrete GM-028 test proves the row. Execution may discover that existing GM-027 product changes already satisfy a new GM-028 regression, but that conclusion is only acceptable after the row-owned regressions exist and pass.

### exact problem statement

GM-028 targets a malformed membership add/config event where the member's top-level `peerId` is empty or whitespace. The user-visible risk is reliability degradation: a blank member must not be saved, installed into Go config, counted as an expected discovery/publish target, included in durable recipients, or cause panic/race behavior during publish/discovery.

What must improve:

- Empty-peer members are rejected or normalized out before config install.
- Publish and discovery preflight remain bounded by real deliverable members.
- Existing valid A/B delivery remains unchanged after the malformed event.

What must stay unchanged:

- Valid members with non-empty peer IDs continue to add, remove, sync, publish, and receive.
- GM-027 fake-peer host tests remain supported in Flutter; Go remains responsible for libp2p peer ID validation where dialing happens.
- Legacy publicKey-only hardening remains outside GM-028 unless it is necessary to reject an empty top-level `peerId`.

### files and repos to inspect next

Production files likely owned by GM-028:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart` only if blank recipient or publish payload filtering fails at the Flutter bridge boundary.
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

Direct tests likely owned by GM-028:

- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart` only if execution changes `group_key_update_listener.dart`.
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart` as an adjacent guard, and only as a GM-028 test if onboarding/key delivery is implicated.
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_inbox_test.go`

Optional only if direct evidence proves it is needed:

- `integration_test/group_real_crypto_onboarding_test.dart`

### existing tests covering this area

Existing relevant coverage:

- GM-027 tests reject no-key/no-device local adds, ignore invalid inbound no-delivery members, exclude pre-existing ghosts from durable recipients, and filter malformed device-less Go dial targets.
- `group_config_payload.dart` currently trims and skips empty `peerId` in `normalizeGroupConfigMembers` and `normalizeGroupConfigMemberEntries`.
- `add_group_member_use_case.dart` trims `newMember.peerId` and rejects non-deliverable members before save/config sync.
- `group_message_listener.dart` ignores non-deliverable member add entries and syncs normalized authoritative configs.
- `send_group_message_use_case.dart` loads durable recipients through `hasDeliverableGroupMemberIdentity` and trimmed non-self peer IDs.
- `go-mknoon/node/pubsub.go` normalizes config members by trimming and skipping empty `PeerId`; discovery target generation also skips empty and invalid dial IDs.

Missing coverage:

- No exact `GM-028` test was found.
- No current test proves an empty or whitespace top-level `peerId` with otherwise valid key/device fields is rejected before config install.
- No current test proves Go publish/discovery expected counts after `UpdateGroupConfig` with an empty-peer member carrying a valid transport device.
- No current test proves group inbox request construction drops blank recipient peer IDs if they are passed from a caller.

### regression/tests to add first

Add regressions before production changes:

- `add_group_member_use_case_test.dart`: `GM-028 rejects empty PeerId before save or config sync`. Use `peerId: '   '` plus otherwise valid `publicKey`, `mlKemPublicKey`, and/or active device fields. Expect `StateError`, no member saved under empty/trimmed ID, and no `group:updateConfig`.
- `group_message_listener_test.dart`: `GM-028 ignores empty PeerId member_added/members_added before config install`. Send malformed system payloads whose `member` / `members` and `groupConfig.members` contain whitespace `peerId` with otherwise deliverable fields. Expect no saved blank member, no timeline message for the malformed member, and every `group:updateConfig` payload excludes blank/whitespace `peerId` while retaining valid members and a valid config state hash when present.
- `member_removal_integration_test.dart`: seed a corrupt local empty-peer member, remove a valid member, and assert the emitted config excludes the corrupt blank member and the operation does not throw or roll back.
- `send_group_message_use_case_test.dart` or `group_membership_smoke_test.dart`: seed or deliver a malformed empty-peer member, then publish from a valid member. Assert durable `recipientPeerIds` and retry payloads include only valid recipients, publish result remains success/successNoPeers as dictated by the fake bridge, and valid delivery is not blocked.
- `group_membership_smoke_test.dart`: row-owned A/B integration proof that a malformed empty-peer add event does not subscribe a blank member, does not persist on either participant, and does not prevent the next valid A-to-B delivery.
- `go-mknoon/node/pubsub_test.go`: `TestGM028EmptyPeerIDDoesNotInflateDiscoveryOrPublishPreflight`. Use `UpdateGroupConfig` or cloned config containing admin, valid Bob, and a blank/whitespace `PeerId` entry with otherwise valid device transport data. Assert stored config excludes the blank member, `activeGroupMemberDialTargets`, `countRemoteGroupMembers`, and `expectedConnectedGroupMembers` count only Bob, `findMember(config, "") == nil`, and no panic occurs.
- `go-mknoon/node/group_inbox_test.go`: add a focused GM-028 regression if `buildGroupInboxStoreRequest` currently preserves blank recipients. Expected behavior should be trimmed valid recipients only, with blanks dropped and no plaintext/envelope behavior changed.

If every exact GM-028 regression passes before production changes, stop product editing and record that current code is already behaviorally sufficient with new row-owned proof. Otherwise implement only the failing guard(s).

### step-by-step implementation plan

1. Record the dirty baseline with `git status --short`; inspect any existing diffs in files before editing them. Do not revert or restyle prior GM-027 or accepted-session changes.
2. Add the exact GM-028 focused regressions listed above. Run the focused selectors and expect RED where current code is missing proof or behavior.
3. If local add fails: keep the guard in `add_group_member_use_case.dart` at the pre-save/pre-`group:updateConfig` boundary. Ensure it trims top-level `peerId` and rejects empty even when key/device fields are present.
4. If inbound listener/config install fails: centralize the fix in `group_config_payload.dart` and call existing normalization from `group_message_listener.dart` before persistence, authoritative snapshot apply, and bridge config sync. Do not duplicate ad hoc JSON filters in multiple listener branches unless unavoidable.
5. If stale/corrupt local state survives a config-producing operation: use `buildGroupConfigPayload` / `normalizeGroupConfigMembers` from add/remove/send-adjacent paths so blank members are dropped before bridge install. Keep rollback behavior unchanged.
6. If durable recipients or retry payloads include blanks: fix `_loadGroupSendMembership` or the immediate bridge boundary to trim/drop empty peer IDs while preserving valid recipients and existing success semantics.
7. If Go discovery/publish preflight fails: update `normalizeGroupConfigMembers`, `activeGroupMemberDialTargets`, or related target-set helpers in `go-mknoon/node/pubsub.go` so empty top-level `PeerId` entries are dropped even when they contain active devices. Do not broaden to network validation in Flutter.
8. If Go inbox request construction forwards blanks: add a tiny recipient normalization helper in `go-mknoon/node/group_inbox.go` that trims/drops empty recipients and preserves valid recipient order. Deduplication is allowed only if the test proves duplicates create a row-owned problem; otherwise leave duplicate policy unchanged.
9. Rerun all focused GM-028 selectors, then adjacent GM-027 selectors because GM-028 shares the deliverable-identity filtering path.
10. Run named/direct gates below. Only after green or explicitly classified known failures may a separate closure pass update the source matrix row to Covered/Closed.

### risks and edge cases

- Empty or whitespace top-level `peerId` with otherwise valid device transport/key material must still be rejected as malformed; device identity cannot substitute for missing member identity.
- Incoming `groupConfig` snapshots may contain both valid members and malformed blank members; normalization must keep valid members and not downgrade roles/permissions.
- Existing corrupt local blank members must not cause remove/config sync rollback or durable recipient pollution.
- Publish preflight must not wait on an impossible blank target or inflate expected connected counts.
- Race/panic risk is on Go config updates and discovery/publish readers; targeted `go test -race` is required.
- Dirty worktree overlap is high in the exact owner files; implementation must preserve unrelated prior-session changes.

### exact tests and gates to run

Focused RED/GREEN selectors:

- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-028'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-028'`
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-028'`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-028'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-028'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'GM-028'` if `group_key_update_listener.dart` is changed.
- `(cd go-mknoon && go test ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1)`
- `(cd go-mknoon && go test -race ./node -run 'TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1)`

Adjacent direct suites:

- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart` if `group_key_update_listener.dart` is changed.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`
- `(cd go-mknoon && go test ./node -run 'GroupInbox|GroupTopicValidator|UpdateGroupConfig|GroupDiscovery|GM027|GM028' -count=1)`
- `dart analyze lib/features/groups/application/group_config_payload.dart lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/remove_group_member_use_case.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_key_update_listener.dart lib/features/groups/application/send_group_message_use_case.dart lib/core/bridge/bridge_group_helpers.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/member_removal_integration_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart`

Named gates and hygiene:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

Optional only if code changes touch real onboarding/crypto harness paths or direct evidence remains insufficient:

- `flutter test --no-pub integration_test/group_real_crypto_onboarding_test.dart`

### known-failure interpretation

- Focused GM-028 tests are expected to fail before the fix if behavior is missing. Those RED failures are useful evidence, not regressions.
- A broad `groups` gate failure should not be attributed to GM-028 unless a focused GM-028 selector or a touched direct suite reproduces the same issue.
- If a known pre-existing failure appears in a dirty owner file, rerun the closest focused selector and record the exact command/output. Do not mark GM-028 blocked unless the failure prevents proving the closure bar.
- Native-assets startup lock, simulator boot, or device selection failures are infrastructure issues only if the same test passes on sequential rerun or a host selector covers the same assertion. Record exact rerun evidence.

### done criteria

GM-028 execution is done when:

- Exact GM-028 regressions exist and pass.
- Any necessary code changes are limited to the listed owner files and directly explain a failed GM-028 regression.
- GM-027 focused selectors still pass or any difference is explicitly explained as non-regression.
- Go focused and `-race` selectors pass for GM-028.
- Direct Flutter suites and named `groups` / `completeness-check` gates pass, or non-GM-028 failures are documented with focused green GM-028 evidence.
- `git diff --check` passes.
- The plan or later closure artifact records concrete evidence sufficient for a separate matrix closure pass; this plan itself does not write a final program verdict.

### scope guard

Do not broaden this session into:

- General strict libp2p peer ID validation in Flutter.
- Removal/re-add identity semantics already owned by GM-021 through GM-027.
- Legacy publicKey-only member deprecation.
- Notification routing, UI member list rendering, role/permission redesign, or invite-status UX.
- Simulator or real-crypto harness changes unless exact host/Go evidence cannot prove GM-028.
- Matrix/breakdown closure edits during implementation unless a separate closure skill/session is explicitly invoked.

Overengineering signals:

- Adding a new membership validation framework instead of reusing `group_config_payload.dart` helpers.
- Rewriting listener authorization or signed-audit flow for a malformed member data issue.
- Changing valid member serialization or role permissions to reject the empty-peer case.

### accepted differences / intentionally out of scope

- GM-027 deliverable-identity filtering is accepted prior work but not accepted as GM-028 closure. GM-028 must prove the narrower empty `peerId` case because a blank top-level member identity can have different failure modes from a non-empty fake/unknown peer.
- Flutter fake peer IDs remain intentionally allowed in host tests. Go dial/discovery can and should reject invalid libp2p peer IDs.
- PublicKey-only legacy member behavior remains outside GM-028 unless the top-level `peerId` is empty.
- Real-crypto onboarding proof is not required unless implementation touches onboarding/key-delivery behavior or direct tests cannot prove config install and preflight safety.

### dependency impact

- GM-029 and later malformed-membership rows should be able to rely on GM-028's empty-peer guard as a baseline, but they must still carry row-owned proof for their own malformed shape.
- Any GM-028 change to shared deliverable-identity helpers must rerun GM-027 focused selectors because GM-027 just closed on those surfaces.
- If execution finds current code already satisfies all new GM-028 regressions without product edits, later closure should record GM-028 as covered by row-owned tests plus prior GM-027 product behavior, not as closed by GM-027 alone.

## Reviewer Pass

Verdict: sufficient with adjustments.

Reviewer answers:

- Sufficiency: sufficient once the conditional key-update test and targeted analyzer command are part of the plan.
- Missing files/tests/gates: `group_key_update_listener.dart` was listed as a possible owner file, so `group_key_update_listener_test.dart` must be required if execution touches it. A targeted Dart analyzer command is needed because this session may edit shared Dart application helpers.
- Stale assumptions: no stale source-of-truth issue found. Current code suggests several paths already trim/drop empty peer IDs, but there is no current GM-028 concrete proof, so implementation-ready remains the correct classification.
- Overengineering: no blocking overengineering. The Go inbox change is correctly conditional on a failing focused regression rather than mandatory broad recipient redesign.
- Decomposition: narrow enough; each failing seam maps to one owner helper/path and direct tests.
- Minimum adjustment applied: add conditional key-update test coverage and targeted analyzer to the exact gate contract.

## Arbiter Pass

Structural blockers: none.

Incremental details:

- Exact helper names and test fixture placement are left to execution after the RED pass.
- Whether `go-mknoon/node/group_inbox.go` needs a production change is intentionally evidence-gated by the focused blank-recipient regression.
- Whether `integration_test/group_real_crypto_onboarding_test.dart` is needed remains optional and should be decided only if direct host/Go evidence cannot prove GM-028 or onboarding/crypto code is touched.

Accepted differences:

- GM-027's deliverable-identity filtering remains accepted prior evidence but not GM-028 closure.
- Flutter host tests may continue using fake peer IDs; strict libp2p decoding remains a Go dial/discovery concern.
- Source matrix closure and final rollout verdict are intentionally outside this planning pass.

Arbiter decision: no new structural blocker; stop per the orchestrator rule.

## Structural Blockers Remaining

None.

## Incremental Details Intentionally Deferred

- Exact fixture helper extraction.
- Exact choice of `send_group_message_use_case_test.dart` versus `group_membership_smoke_test.dart` as the first durable-recipient proof if both would assert the same recipient contract.
- Go inbox normalization only if the focused test proves blank recipients can pass through that boundary.

## Accepted Differences Intentionally Left Unchanged

- No broad Flutter libp2p peer ID validation.
- No legacy publicKey-only deprecation.
- No default simulator or real-crypto proof unless host/Go evidence is insufficient or implementation touches those paths.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-027-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `git status --short`

## Why The Plan Is Safe Or Unsafe To Implement Now

Safe to implement now with dirty-state discipline. The source row is still Open, the breakdown marks GM-028 implementation-ready, the suspected owner files are concrete, the test plan is regression-first, and the scope guard prevents GM-028 from reopening broader GM-027 or real-crypto work. The main safety risk is the already dirty overlapping worktree, so execution must inspect existing diffs before editing each owner file and avoid reverting unrelated accepted-session changes.
