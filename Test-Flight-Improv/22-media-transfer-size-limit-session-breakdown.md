# Decomposition Artifact Updated

## Recommended plan count

`4`

## Decomposition artifact

- Artifact path: `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- Proposal/source doc path: `Test-Flight-Improv/22-media-transfer-size-limit.md`
- Downstream workflow rule: plan exactly one session at a time with `$implementation-plan-orchestrator`, then execute it with `$implementation-execution-qa-orchestrator`, then close it with `$implementation-closure-audit-orchestrator`.
- Downstream refresh rule: every later session must be refreshed against landed code before execution; do not assume this breakdown freezes implementation details across sessions.

## Overall closure bar

All general media attachment paths that the current repo actually supports for chat must honor one settled post-processing size budget end-to-end, with no 100 MB vs original-quality contradiction left in the live 1:1, group, share-seeded, relay, or local-discovery paths.

Closure is reached only when all of the following are true:

- relay upload and local discovery accept the same settled general-media cap without leaving the relay on a count-only retention policy that becomes operationally unsafe at 5 GB
- voice recordings sent through `send_voice_message_use_case.dart` still keep the separate 100 MB sanity limit
- 1:1 and group attachment entry points apply the same size-budget rule after quality processing, including hydrated/shared attachments that arrive through existing `initialAttachments` entry paths
- users get immediate foreground-only upload protection with honest active-upload UX; the repo still does not overclaim true background-upload support
- the existing 1:1 and group closure docs, plus stale media specs, are updated so the repo promise matches the landed code and tests

## Source of truth

Primary proposal and policy docs:

- `Test-Flight-Improv/22-media-transfer-size-limit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`

Current-code reality checks that overrule stale prose when they disagree:

- `go-relay-server/media.go`
- `go-relay-server/media_test.go`
- `go-mknoon/node/media.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/crypto/file_crypto.go`
- `lib/core/local_discovery/local_media_server.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`

Stale-but-relevant media specs that must be treated as secondary evidence only:

- `UI-10-Media/media-server-spec.md`
- `UI-10-Media/media-client-spec.md`

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Execution verdict | Closure docs touched | Blocker note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `38` | Relay/local 5 GB cap and byte-safe retention contract | `evidence-gated` | `Test-Flight-Improv/session-38-plan.md` | none | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | closed in Session `41`; stable closure/docs refreshed | none |
| `39` | Shared attachment budget and overflow UX across in-app and hydrated entry points | `implementation-ready` | `Test-Flight-Improv/session-39-plan.md` | `38` | `accepted` | `accepted` | closed in Session `41`; stable closure/docs refreshed | none |
| `40` | Active upload progress, leave guard, and wake lock across chat send surfaces | `implementation-ready` | `Test-Flight-Improv/session-40-plan.md` | `39` | `accepted` | `accepted` | closed in Session `41`; stable closure/docs refreshed | none |
| `41` | Cross-slice acceptance and closure refresh | `closure-only` | `Test-Flight-Improv/session-41-plan.md` | `38`, `39`, `40` | `accepted` | `accepted` | `19`, `20`, gate defs, `UI-10-Media`, breakdown refreshed | none |

## Ordered session breakdown

### Session 38

- Title: Relay/local 5 GB cap and byte-safe retention contract
- Session id: `38`
- Session classification: `evidence-gated`
- Intended plan file: `Test-Flight-Improv/session-38-plan.md`
- Exact scope:
  decide and land the safe transport-side contract before broad Flutter UI work.
  The current relay still uses `maxMediaPerPeer = 50` count-based pruning in `go-relay-server/media.go`; at a 5 GB object cap that becomes a potential 250 GB per-recipient retention window. This session owns whatever relay-side retention adjustment or explicit bounded-cap decision is needed so the 5 GB product claim is not operationally reckless.
- Exact scope:
  after the relay-side retention decision is settled, align the live transport limits that are currently hardcoded at 100 MB in `go-relay-server/media.go` and `lib/core/local_discovery/local_media_server.dart`, while preserving the separate 100 MB voice-recording limit in `lib/features/conversation/application/send_voice_message_use_case.dart`.
- Exact scope:
  reconcile direct tests around over-limit rejection, zero-byte rejection, local-offer rejection, partial-upload cleanup, and any relay pruning/TTL behavior that changes because of the new cap math.
- Why it is its own session:
  this is the relay/local transport contract seam plus server-operability closure, not a Flutter attach-flow or upload-UX change. The unresolved storage-policy ambiguity is real repo evidence, so it must be contained up front instead of leaking into later UI sessions.
- Likely code-entry files:
  `go-relay-server/media.go`
- Likely code-entry files:
  `go-relay-server/media_test.go`
- Likely code-entry files:
  `lib/core/local_discovery/local_media_server.dart`
- Likely code-entry files:
  `test/core/local_discovery/local_media_server_test.dart`
- Likely code-entry files:
  `lib/features/conversation/application/send_voice_message_use_case.dart`
- Likely code-entry files:
  `test/features/conversation/application/send_voice_message_use_case_test.dart`
- Likely code-entry files:
  `UI-10-Media/media-server-spec.md`
- Likely direct tests/regressions:
  `go-relay-server/media_test.go`
- Likely direct tests/regressions:
  `test/core/local_discovery/local_media_server_test.dart`
- Likely direct tests/regressions:
  `test/core/local_discovery/local_media_integration_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/application/send_voice_message_use_case_test.dart`
- Likely named gates:
  `baseline`
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Likely named gates:
  `transport` only if the landed solution changes resume/startup/media-recovery wiring rather than staying inside pure size-policy seams
- Matrix/closure docs to update when done:
  defer closure and spec updates to Session `41`; do not partially refresh `19`, `20`, or `UI-10-Media/*` mid-rollout
- Dependency on earlier sessions:
  none

### Session 39

- Title: Shared attachment budget and overflow UX across in-app and hydrated entry points
- Session id: `39`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/session-39-plan.md`
- Exact scope:
  implement one shared attachment-budget contract across the existing chat entry points that can seed pending attachments: in-app attach actions inside `ConversationWired` and `GroupConversationWired`, plus hydrated `initialAttachments` paths already used by share and other route entry points.
- Exact scope:
  enforce the settled general-media cap after quality processing, not before it. For compressed preferences, media must be processed first and only then budget-checked. For original preferences, raw file sizes are the budget input. The 10-attachment count limit remains separate and unchanged.
- Exact scope:
  add the over-limit warning flow with `Compress` and `Cancel` semantics for single-file overflow and cumulative overflow, while keeping the in-app voice-recorder path out of this contract.
- Exact scope:
  if share-seeded attachments currently bypass the new budget logic, move the minimum amount of processing/validation into a shared helper or hydration pass so share does not stay a size-limit bypass.
- Why it is its own session:
  this is a Flutter attachment-ingress seam with deterministic attach/hydration regressions. It is narrower than the relay/local transport contract and different from the active-upload progress/wake-lock contract.
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_wired.dart`
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely code-entry files:
  `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- Likely code-entry files:
  `lib/core/media/image_processor.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_screen.dart` only if dialog text or hydration-time presentation has to move there
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely direct tests/regressions:
  the same group-side attach-budget contract now also carries row-owned closure
  proof for `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  row `UX-007` via the targeted overflow/compress regressions added on
  `2026-04-05`
- Likely direct tests/regressions:
  `test/features/share/integration/share_to_contact_smoke_test.dart`
- Likely direct tests/regressions:
  `test/features/share/presentation/share_target_picker_wired_test.dart`
- Likely direct tests/regressions:
  `test/core/media/image_processor_test.dart`
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Likely named gates:
  `baseline`
- Likely named gates:
  `feed` only if the implementation touches feed-side route launchers instead of keeping the new contract inside the shared conversation/group hydration paths
- Matrix/closure docs to update when done:
  defer final closure/spec refresh to Session `41`
- Dependency on earlier sessions:
  Session `38`

### Session 40

- Title: Active upload progress, leave guard, and wake lock across chat send surfaces
- Session id: `40`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/session-40-plan.md`
- Exact scope:
  add honest active-upload UI for the existing 1:1 and group send surfaces: visible upload banner, aggregate progress text, foreground warning text, leave-confirmation behavior, and wake-lock lifetime that remains active until the last upload finishes, fails, or is cancelled.
- Exact scope:
  if real upload byte progress does not currently reach Flutter, land the minimal bridge/progress plumbing needed for the banner in the same session. The proposal language is byte-based, so this session should not silently degrade to an indeterminate spinner without recording that scope change explicitly.
- Exact scope:
  keep this session upload-only. Do not widen it into receiver download progress, true background upload architecture, or broader lifecycle redesign.
- Why it is its own session:
  this is the active-upload state seam spanning progress plumbing plus foreground protection UX. It touches different code paths and acceptance proof than Session `39`, even though both later sessions revisit the same conversation/group files.
- Likely code-entry files:
  `lib/core/bridge/bridge.dart`
- Likely code-entry files:
  `lib/core/bridge/go_bridge_client.dart`
- Likely code-entry files:
  `lib/core/bridge/p2p_bridge_client.dart`
- Likely code-entry files:
  `go-mknoon/bridge/bridge.go`
- Likely code-entry files:
  `go-mknoon/node/media.go`
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_wired.dart`
- Likely code-entry files:
  `lib/features/conversation/presentation/screens/conversation_screen.dart`
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- Likely code-entry files:
  `pubspec.yaml`
- Likely direct tests/regressions:
  `test/core/bridge/go_bridge_client_test.dart`
- Likely direct tests/regressions:
  `test/core/bridge/p2p_bridge_client_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- Likely direct tests/regressions:
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- Likely direct tests/regressions:
  `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Likely named gates:
  `baseline`
- Likely named gates:
  `transport` only if the implementation ends up changing app-resume/bootstrap wiring instead of staying inside active-upload UI and bridge progress delivery
- Matrix/closure docs to update when done:
  defer final closure/spec refresh to Session `41`
- Dependency on earlier sessions:
  Session `39`

### Session 41

- Title: Cross-slice acceptance and closure refresh
- Session id: `41`
- Session classification: `closure-only`
- Intended plan file: `Test-Flight-Improv/session-41-plan.md`
- Exact scope:
  run the cross-slice acceptance pass after Sessions `38`-`40` land, then update the stable closure/spec docs so the repo promise matches the new transport cap, attach-time contract, and foreground-only upload protection.
- Exact scope:
  update the existing closure references instead of inventing a new media-size matrix doc. The stable closure owners for this work are the current 1:1 and group reliability references plus the gate-definition doc if new tests must be classified.
- Exact scope:
  refresh stale `UI-10-Media` docs that still claim 100 MB or describe old progress/encryption assumptions that are no longer the chat-attachment source of truth.
- Why it is its own session:
  multiple earlier slices change user-visible behavior and stale documentation in different parts of the tree. One closure owner is required so the repo does not land code while leaving the living docs contradictory.
- Likely code-entry files:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Likely code-entry files:
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Likely code-entry files:
  `Test-Flight-Improv/test-gate-definitions.md`
- Likely code-entry files:
  `UI-10-Media/media-server-spec.md`
- Likely code-entry files:
  `UI-10-Media/media-client-spec.md`
- Likely direct tests/regressions:
  rerun the exact direct suites added or changed in Sessions `38`, `39`, and `40`
- Likely direct tests/regressions:
  run `./scripts/run_test_gates.sh completeness-check` if any new test files or gate classifications were added
- Likely named gates:
  `baseline`
- Likely named gates:
  `1to1`
- Likely named gates:
  `groups`
- Likely named gates:
  `feed` only if Session `39` touched feed-side route launchers
- Likely named gates:
  `transport` only if Session `38` or `40` changed resume/bootstrap/device-backed media-recovery wiring
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Matrix/closure docs to update when done:
  `Test-Flight-Improv/test-gate-definitions.md` if new tests require explicit classification
- Matrix/closure docs to update when done:
  `UI-10-Media/media-server-spec.md`
- Matrix/closure docs to update when done:
  `UI-10-Media/media-client-spec.md`
- Dependency on earlier sessions:
  Sessions `38`, `39`, and `40`

## Why this is not fewer sessions

- Session `38` cannot be merged into the Flutter UI sessions safely because the current relay uses count-only pruning. The 5 GB product claim needs a settled transport/storage contract before the UI advertises it broadly.
- Session `39` cannot be merged into Session `40` safely because attach-time budget enforcement and active-upload progress/wake-lock are different seams with different first-proof regressions. One is about file selection and pending-attachment state; the other is about in-flight upload state and bridge/UI coordination.
- Session `41` cannot disappear because the stable closure docs for both 1:1 and groups would otherwise stay stale, and `UI-10-Media/*` is already stale enough that code alone is not sufficient closure.

## Why this is not more sessions

- Do not split 1:1 vs group attach-time enforcement into separate plans. The two composers duplicate the same pending-attachment contract, and shipping only one side would leave an obvious bypass for the same user-visible feature.
- Do not split share-seeded entry points into their own plan unless later code inspection proves they cannot be covered by the same hydrated-attachment contract. Right now they already feed the same `initialAttachments` seam and therefore belong with Session `39`.
- Do not split wake lock away from the upload banner/progress session. The user-facing promise is one coherent slice: active uploads remain visible and protected while they run.
- Do not create a standalone voice-message session. Voice staying at 100 MB is a regression guard inside Session `38`, not an independent feature seam.
- Do not invent a new media-size closure matrix doc. Existing stable closure references and gate definitions are the right long-lived docs to extend.

## Regression and gate contract

- Use `Test-Flight-Improv/14-regression-test-strategy.md` as the policy/rationale reference and `Test-Flight-Improv/test-gate-definitions.md` as the execution source of truth.
- Session `38` should start with direct transport-side regressions in `go-relay-server/media_test.go`, `test/core/local_discovery/local_media_server_test.dart`, and the voice-limit regression, then run the named gates required by the shared chat-media contract that was changed.
- Session `39` should add deterministic attach/hydration regressions before implementation and then run `1to1`, `groups`, and `baseline`; `feed` is conditional only if feed launcher code changes.
- Session `40` should add the direct bridge/UI upload-state regressions before implementation and then run `1to1`, `groups`, and `baseline`; `transport` is conditional only if resume/bootstrap wiring changes.
- Session `41` owns the final rerun of the exact direct suites touched across Sessions `38`-`40`, the named gates they require, and `completeness-check` if new test files were added or reclassified.

## Matrix update contract

- Do not create a new matrix doc for media-size work.
- Session `41` is the single closure owner for the stable docs that should change:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`,
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`,
  and `Test-Flight-Improv/test-gate-definitions.md` if new tests need explicit classification.
- Session `41` also refreshes the stale secondary media specs in `UI-10-Media/media-server-spec.md` and `UI-10-Media/media-client-spec.md`.

## Structural blockers remaining

- None after the relay/storage ambiguity was isolated into evidence-gated Session `38`.
- The decomposition is safe to execute because the only real unresolved product/architecture ambiguity now has an explicit owner and stop rule instead of being smuggled into later UI sessions.

## Accepted differences intentionally left unchanged

- Voice recordings remain outside the 5 GB general-media increase and keep the existing 100 MB validation path.
- The proposal's download-side wake-lock/progress mention is not treated as in-scope product truth here because the solution section and the live code both frame the new foreground protection around uploads, not downloads.
- `UI-10-Media/media-client-spec.md` still describes an older whole-file media-encryption flow for chat attachments; current chat media upload code is already raw-file streaming through `media:upload`, so that stale spec should be refreshed in Session `41` rather than used to expand current implementation scope.
- No new test matrix doc is introduced for this feature.

## Exact docs/files used as evidence

- `Test-Flight-Improv/22-media-transfer-size-limit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `UI-10-Media/media-client-spec.md`
- `UI-10-Media/media-server-spec.md`
- `go-relay-server/media.go`
- `go-relay-server/media_test.go`
- `go-mknoon/node/media.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/crypto/file_crypto.go`
- `lib/core/local_discovery/local_media_server.dart`
- `test/core/local_discovery/local_media_server_test.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The session count is the minimum set that still isolates the real structural seam difference: transport/storage policy, attach-time budget enforcement, active-upload foreground protection, and final closure.
- Later sessions are sequenced to avoid overlapping uncontrolled edits in `conversation_wired.dart` and `group_conversation_wired.dart`.
- The only unresolved ambiguity in the proposal is treated as `evidence-gated` instead of being allowed to poison the implementation-ready sessions.
- Existing stable closure docs are reused as the final documentation target, so this work will close into repo-maintainable references instead of leaving the proposal doc as the only record.
