Status: execution-ready

# Group Media Unavailable Refresh Session 01 Plan

## Planning Progress

- 2026-05-29 06:11:35 CEST - Evidence Collector completed. Files inspected: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/shared/widgets/media/media_grid_cell.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/conversation/application/download_media_use_case.dart`, direct group/media tests, gate docs, and reliability-sim dry-run list. Decision: likely stale open-route `mediaMap`/download-refresh seam; existing tests cover reopen, download persistence, and true unavailable/quarantine states, but not live recipient UI refresh after background group image download. Next action: Planner.
- 2026-05-29 06:13:31 CEST - Planner started. Files inspected since last update: `GroupConversationWired._applyMessageUpdate`, `MediaGridCell`, `MediaThumbnailImage`, `media_stable_id_smoke_test.dart`, `run_media_delivery_ui_smoke.dart`, `$run-flutter-reliability-sims` usage. Decision: draft should require a failing open-route refresh regression before any production edit, then preserve true unavailable/quarantine behavior. Next action: write mandatory plan sections.
- 2026-05-29 06:13:31 CEST - Planner completed. Files inspected since last update: this plan only. Decision: status advanced to `planning-draft`; reviewer and arbiter have not run, so this is not execution-ready. Next action: run Reviewer before implementation.
- 2026-05-29 06:16:27 CEST - Reviewer completed. Files inspected since last update: this plan, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `scripts/run_reliability_simulations.sh`, `scripts/check_reliability_simulation_discovery.sh`, `integration_test/scripts/run_media_delivery_ui_smoke.dart`, `integration_test/media_stable_id_smoke_test.dart`, and direct test selector search hits. Decision: sufficient with no structural blockers; status advanced to `reviewer-pass`. Next action: Arbiter before execution-ready.
- 2026-05-29 06:17:33 CEST - Arbiter completed. Files inspected since last update: this plan, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `integration_test/scripts/run_media_delivery_ui_smoke.dart`, `integration_test/media_stable_id_smoke_test.dart`, and `$run-flutter-reliability-sims` wrapper existence. Decision: no structural blockers remain; reviewer details are incremental or accepted differences, so status advanced to `execution-ready`. Next action: execution may start from the regression-first step in this plan.

## Evidence Notes

- Likely production seams: `GroupConversationWired._loadMessages()` loads `_mediaMap` then fire-and-forgets `_downloadPendingMedia(...)`; `_startListening()` applies `GroupMessageListener.groupMessageStream` updates; `_resolveAttachmentsForDisplay(...)` can convert missing done files back to pending; `GroupConversationScreen` renders `mediaMap[message.id] ?? message.media`; `MediaGridCell` shows `media_unavailable` for integrity/policy failures and delegates image-file load errors from `MediaThumbnailImage`.
- Incoming group media path: `GroupMessageListener` persists the incoming message/attachments, emits the message, then fire-and-forget `_autoDownloadMedia(...)` downloads pending attachments and re-emits the same message so UI can refresh.
- Current coverage: `group_conversation_wired_test.dart` covers GMAR-004 reopen hydration, route reopen message hydration, incoming no-key quarantine, and MD-012 unavailable retry repair; `group_conversation_screen_test.dart` and `media_grid_cell_test.dart` cover true unavailable/quarantined UI; `group_message_listener_test.dart`, `handle_incoming_group_message_use_case_test.dart`, `group_media_fanout_test.dart`, and `foreground_group_push_drain_test.dart` cover pending/done/failed download repository state.
- Simulator/gate evidence: `integration_test/media_stable_id_smoke_test.dart` already has `group conversation open re-downloads missing media from stored attachment rows on simulator` and `announcement image send normalizes final attachment ids on simulator`; `group_new_member_media_simulator_proof_test.dart` covers video/voice render/play/reopen on `GroupConversationScreen`. Reliability dry-run lists `integration_test/scripts/run_media_delivery_ui_smoke.dart` as group command #115, which runs `media_stable_id_smoke_test.dart`.
- Gap: no inspected test proves an already-open recipient group route transitions from pending/loading or temporary image failure to rendered image immediately after the background group download completes, without leaving/re-entering.

## Reviewer Findings

Sufficiency: sufficient with adjustments applied. The plan includes all mandatory sections, keeps the behavior change narrow, requires the direct host regression before production edits, preserves true unavailable/quarantine behavior, includes an explicit `$run-flutter-reliability-sims` closure gate for group media/avatar behavior, and gives exact focused, named, simulator, and hygiene commands.

Blocking issues: none found in Reviewer pass.

Non-blocking details:

- The direct regression and simulator scenario names are intentionally proposed selectors; the executor must add them before relying on the exact `--plain-name` command or the simulator smoke as closure evidence.
- The reliability wrapper supports `--only <path>`, and discovery classifies `integration_test/scripts/run_media_delivery_ui_smoke.dart` as a group runner. The fallback `--list` plus current-number command is appropriate if path selection drifts.
- `./scripts/run_test_gates.sh groups` is the correct named host gate from `Test-Flight-Improv/test-gate-definitions.md`; simulator closure remains mandatory and cannot be replaced by host gates.
- Known failures are interpreted narrowly enough: unrelated pre-existing gate failures or dirty worktree failures do not close or block this session unless they hit the direct media refresh/unavailable tests or files changed by the session.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers: none. The plan has a real scope, regression-first contract, explicit closure bar, source-of-truth ordering, named host gate, mandatory `$run-flutter-reliability-sims` simulator closure, known-failure interpretation, done criteria, and stop conditions for stale/already-covered evidence.

Incremental details intentionally deferred:

- The direct host regression selector and simulator scenario name are proposed names; the executor must add or adjust them before relying on those exact selectors.
- If the reliability wrapper path selector drifts, the executor should use the documented `--list` fallback and current command number.
- Extra listener/shared-widget selectors remain conditional on which seam the first failing regression identifies.

Accepted differences intentionally left unchanged:

- 1:1 media behavior remains out of scope for this group media session.
- Video and voice expansion remains conditional on shared-root-cause evidence.
- Reopen hydration coverage remains useful evidence but is not accepted as closure for the already-open route symptom.

## Execution Progress

- 2026-05-29 06:18:20 CEST - Contract extracted. Scope: already-open group recipient image media refresh without route reopen; preserve true unavailable/quarantine behavior. Code-entry files: `group_conversation_wired.dart`, `group_conversation_screen.dart`, `media_grid_cell.dart`, `media_thumbnail_image.dart`, `group_message_listener.dart`, `download_media_use_case.dart`. Required first test: direct `group_conversation_wired_test.dart` regression. Required closure: focused preservation tests, `./scripts/run_test_gates.sh groups`, `$run-flutter-reliability-sims` media delivery UI smoke, and `git diff --check`. Next action: spawn isolated Executor.
- 2026-05-29 06:18:39 CEST - Executor spawned/running. Agent: `019e71f4-99b1-79b0-add3-eea5b4d5d8e0`. Assigned files: direct group conversation media test, smallest production refresh seam, simulator smoke extension, and required gates. Next action: wait for executor result.
- 2026-05-29 06:19:02 CEST - Executor contract read in workspace. Files inspected: this plan, `test/features/groups/presentation/group_conversation_wired_test.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `integration_test/media_stable_id_smoke_test.dart`, and dirty-worktree status. Decision: proceed regression-first and preserve unrelated dirty files. Next action: inspect existing media refresh helpers and write direct failing regression.
- 2026-05-29 06:20:45 CEST - Owner seam inspected. Files inspected: `GroupConversationWired._applyMessageUpdate`, `_loadResolvedAttachmentsForMessage`, `_resolveAttachmentsForDisplay`, `MediaGridCell`, `MediaThumbnailImage`, and existing GMAR/MD-012 tests. Decision: route already reloads attachment rows; direct regression will target the same mounted group route after a temporary same-path image load failure, proving whether shared thumbnail retry is the stale seam. Next action: add the direct regression before production edits.
- 2026-05-29 06:21:37 CEST - Direct regression added first. Files touched: `test/features/groups/presentation/group_conversation_wired_test.dart`. Command starting: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming group image refreshes on open recipient route after background download without reopen'`. Next action: confirm RED before production edits.
- 2026-05-29 06:26:43 CEST - Direct regression confirmed RED after tightening to the live open-route pending attachment path. Command result: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming group image refreshes on open recipient route after background download without reopen'` failed because the visible media remained `pending` instead of `done` and no route-local download completed. Decision: failing seam is `GroupConversationWired._applyMessageUpdate` not invoking the existing pending-media download path for live message updates. Next action: apply smallest production fix in `group_conversation_wired.dart`.
- 2026-05-29 06:31:16 CEST - Production fix and simulator scenario added. Files touched: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `integration_test/media_stable_id_smoke_test.dart`. Decision: `_applyMessageUpdate` now invokes existing `_downloadPendingMedia` only for the updated message when resolved attachments are recoverable; simulator smoke gained `group recipient open route refreshes downloaded image without reopen on simulator`. Direct selector was rerun and passed after the fix. Next action: run required preservation selectors and gates.
- 2026-05-29 06:32:19 CEST - Focused selectors completed. Commands passed: direct regression selector; `MD-012 quarantined visual media shows unavailable placeholder and retry control`; `MD-012 read-only group rows can retry unavailable incoming media without resend controls`; `MD-012 retrying quarantined incoming media downloads only the targeted attachment`; `MD-012 failed repair keeps media quarantined and clears unsafe file`. Extra direct integration selector `flutter test --no-pub integration_test/media_stable_id_smoke_test.dart --plain-name 'group recipient open route refreshes downloaded image without reopen on simulator'` could not start because Flutter found multiple connected devices and required `-d`. Next action: run required named groups gate and device resolver smoke.
- 2026-05-29 06:34:45 CEST - Required groups gate completed with one failure. Command: `./scripts/run_test_gates.sh groups`; result: failed at `test/features/groups/integration/group_messaging_smoke_test.dart` selector `GE-017 seeded random membership operations preserve invariants`, with the remaining group gate run reporting `+311 -1`. Triage command: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-017 seeded random membership operations preserve invariants'`; result: passed. Classification: required-gate failure is unrelated/flaky and outside this media-refresh change, not caused by touched files. Next action: run required `run_with_devices` media delivery UI smoke.
- 2026-05-29 06:37:32 CEST - Required simulator-backed closure gate passed. Command: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_media_delivery_ui_smoke.dart`; resolved one-device simulator `38FECA55-03C1-4907-BD9D-8E64BF8E3469` (`iPhone 17 Pro`); selected command `#115`; result: `PASS: #115 integration_test/scripts/run_media_delivery_ui_smoke.dart` and `PASS: reliability simulations completed for scope: group`. New scenario `group recipient open route refreshes downloaded image without reopen on simulator` ran in this smoke and passed. Command `git diff --check`; result: passed. Next action: final executor summary.
- 2026-05-29 06:40:22 CEST - QA Reviewer started. Files inspected: this plan, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and `integration_test/media_stable_id_smoke_test.dart`. Evidence inspected: relevant diffs, new direct regression, simulator scenario, required direct selector list, groups-gate failure classification, focused GE-017 rerun, required simulator smoke pass, and `git diff --check` pass. Decision: full groups rerun is not required under this plan because the only broad-gate failure was triaged to an unrelated/flaky membership selector outside the touched media-refresh scope and that selector passed on focused rerun. Next action: complete QA verdict.
- 2026-05-29 06:40:22 CEST - QA Reviewer completed. Blocking issues: none. Non-blocking follow-ups: none. Final QA recommendation: accepted.
- 2026-05-29 06:42:12 CEST - Final execution verdict written. Verdict: accepted. Blocking issues: none. Non-blocking follow-ups: none. Required simulator closure and direct regressions passed; broad groups-gate GE-017 failure was triaged as unrelated/flaky and passed on focused rerun.

## Final Execution Verdict

Verdict: accepted.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Safety summary: the direct regression reproduced the stale open-route group image refresh bug before the fix, then passed after the `_applyMessageUpdate` change. The simulator media delivery UI smoke now includes and passed the already-open group recipient refresh scenario. True unavailable/quarantined media preservation selectors passed. The only broad `groups` gate failure was isolated to unrelated `GE-017` membership invariants and passed on focused rerun, so QA accepted the session under this plan's known-failure interpretation.

## real scope

Fix only the group recipient conversation UI refresh path where an incoming group image can remain on the `Media unavailable` placeholder until the route is rebuilt. The intended behavior is that an already-open recipient group conversation moves from loading/temporary image failure/unavailable placeholder to the rendered image as soon as the background download produces a valid local file and attachment row.

In scope:

- The open `GroupConversationWired` route state update after group media attachment rows change.
- The shared media thumbnail/cell reload behavior only if the direct regression proves the stale placeholder is caused by a same-path `Image.file`/thumbnail refresh issue.
- Direct host widget coverage and a simulator smoke extension for this exact already-open recipient journey.

Out of scope:

- Group send fanout, upload, durable inbox targeting, membership, key repair, notification routing, media encryption policy, media size/mime policy, retry UX, and visual redesign.
- Changing the meaning of true unavailable/quarantined media. Integrity-failed, oversized, invalid descriptor, and missing-encryption incoming media must still show the unavailable placeholder and retry affordance where currently expected.

## closure bar

Good enough means the direct regression fails before the production fix, passes after the smallest production change, and proves the same recipient route refreshes without a route pop/push or full reload by user action. The UI must not show `Media unavailable` once the attachment is valid, downloaded, and renderable; it must still show unavailable for real integrity/policy failures.

Because this is group media on Flutter/mobile, host tests are not sufficient for final closure. Closure also requires a simulator-backed group reliability proof through `$run-flutter-reliability-sims` using the media delivery UI smoke path, after adding or extending a simulator scenario that covers the already-open group recipient refresh.

## source of truth

Authoritative sources, in order on disagreement:

- Current production code in `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/shared/widgets/media/media_grid_cell.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, and `lib/features/groups/application/group_message_listener.dart`.
- Direct tests in `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, and `test/shared/widgets/media/media_grid_cell_test.dart`.
- Simulator proof in `integration_test/media_stable_id_smoke_test.dart` as launched by `integration_test/scripts/run_media_delivery_ui_smoke.dart`.
- Gate definitions in `Test-Flight-Improv/test-gate-definitions.md`; use this file over stale gate prose elsewhere.
- This plan is the active scope contract unless reviewer evidence proves it stale.

## session classification

`implementation-ready`

The failure is narrow enough to plan and execute one implementation session. Arbiter found no structural blockers, so this plan is execution-ready.

## exact problem statement

A group recipient can see an incoming image row as `Media unavailable` even after the media becomes locally available; the image appears only after leaving and re-entering the group conversation. That creates a stale open-route UI state and makes a successful media delivery look broken.

The user-visible improvement is seamless: while the recipient stays in the conversation, the media row should update from loading/temporary failure to the actual image after background download completion. Existing behavior for true unavailable media must stay unchanged: quarantined/integrity-failed media remains blocked, cannot open, and exposes the existing retry control where applicable.

## files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/conversation/application/download_media_use_case.dart`

Tests and simulator files:

- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `integration_test/media_stable_id_smoke_test.dart`
- `integration_test/scripts/run_media_delivery_ui_smoke.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

Covered:

- `test/features/groups/presentation/group_conversation_wired_test.dart` covers reopen hydration, route reuse cleanup, missing/done media re-download on route load, incoming no-key quarantine, and MD-012 retry of quarantined incoming media.
- `test/features/groups/presentation/group_conversation_screen_test.dart` covers true unavailable/quarantined visual media and retry controls.
- `test/shared/widgets/media/media_grid_cell_test.dart` covers shared media cell placeholder behavior.
- `test/features/groups/application/group_message_listener_test.dart` and adjacent application/integration tests cover incoming group message persistence, attachment rows, download status, and fanout/storage behavior.
- `integration_test/media_stable_id_smoke_test.dart` covers group route open re-download of missing stored media on a simulator, but the route starts from persisted rows rather than proving a live already-open recipient refresh.

Missing:

- No inspected test proves that an already-open group recipient route refreshes the visible image immediately after the background group media download completes.
- No inspected simulator scenario pins the reported leave/re-enter symptom.

## regression/tests to add first

Add the direct regression before any production edit:

- In `test/features/groups/presentation/group_conversation_wired_test.dart`, add a widget test named close to `incoming group image refreshes on open recipient route after background download without reopen`.
- Set up a group recipient route with `GroupConversationWired`, a persisted incoming message, and a pending or temporarily unrenderable image attachment that initially shows loading or the unavailable placeholder.
- While the route remains mounted, simulate the background download completion by updating the same attachment row to a valid `done` image with a real local file and valid group media integrity metadata, then re-emit the same group message through the listener stream or call the existing listener path used by `_autoDownloadMedia`.
- Assert without unmounting/rebuilding the route that `GroupConversationScreen.mediaMap[messageId]` contains the `done` attachment, `Media unavailable` is absent, the media cell can open, and the rendered image/thumbnail is present.
- The test must fail on the current bug. If it passes as written, stop production work and tighten the regression to reproduce the exact stale path: same local path created after an `Image.file` error, image cache reuse, pending-to-done transition, or listener re-emit with stale message media.

Add or extend the simulator proof before closure:

- In `integration_test/media_stable_id_smoke_test.dart`, add a scenario named close to `group recipient open route refreshes downloaded image without reopen on simulator`.
- Keep it narrow: use the existing fake repositories/bridge style from the group media stable-ID smoke, mount `GroupConversationWired`, trigger download completion while the route stays open, and assert the image renders without `pumpWidget(const SizedBox.shrink())` or route reopen.
- `integration_test/scripts/run_media_delivery_ui_smoke.dart` should remain the runner unless reviewer evidence shows a narrower existing group simulator command is better.

## step-by-step implementation plan

1. Write the direct `group_conversation_wired_test.dart` regression first and confirm it fails for the stale open-route state.
2. If the direct regression cannot reproduce the issue with a listener re-emit and attachment row update, test the lower shared-widget path in `media_grid_cell_test.dart` or `media_thumbnail_image` behavior using a same-path missing-file-then-created image. Stop and record evidence if production already satisfies the reported route seam.
3. Apply the smallest production fix at the failing seam:
   - Prefer refreshing `_mediaMap` from `mediaAttachmentRepo` when the listener reports a message whose attachments may have changed.
   - If the failure is image-provider caching with the same file path, force a thumbnail/image reload only for the changed attachment, without changing unavailable policy.
   - If the failure is `_downloadPendingMedia` state, update only that pending-to-done map update path.
4. Preserve true unavailable media behavior by rerunning the MD-012/unavailable tests and avoiding policy changes in `GroupMediaIntegrityPolicy`.
5. Add or extend the simulator scenario in `media_stable_id_smoke_test.dart` to prove the already-open group recipient route refreshes on a real Flutter device/simulator.
6. Run the exact focused tests and gates below. If simulators are unavailable, classify closure as evidence-gated instead of complete.

## risks and edge cases

- Same `localPath` after a prior `Image.file` error may keep a stale image provider or widget state unless the cell/thumbnail reloads deliberately.
- A listener re-emits the same `GroupMessage` after download; UI must refresh from durable attachment rows, not from stale `message.media`.
- Missing local files for a `done` attachment should still downgrade to recoverable pending and re-download where current behavior expects that.
- Integrity-failed or missing-encryption incoming media must not become displayable because of a broad refresh.
- The fix must not disturb scroll position, visible read marking, duplicate message ordering, or route reuse cleanup.
- Background download completion after widget disposal must remain guarded by `mounted`.

## exact tests and gates to run

Direct regression first:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming group image refreshes on open recipient route after background download without reopen'
```

Focused preservation tests:

```bash
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'MD-012 quarantined visual media shows unavailable placeholder and retry control'
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'MD-012 read-only group rows can retry unavailable incoming media without resend controls'
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'MD-012 retrying quarantined incoming media downloads only the targeted attachment'
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'MD-012 failed repair keeps media quarantined and clears unsafe file'
```

If `MediaGridCell` or `MediaThumbnailImage` changes, also run:

```bash
flutter test --no-pub test/shared/widgets/media/media_grid_cell_test.dart
```

If `GroupMessageListener` changes, also run the focused listener selector that covers auto-download/re-emission, adding one if no exact selector exists:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name '<new or existing group media auto-download re-emits message selector>'
```

Named host gate:

```bash
./scripts/run_test_gates.sh groups
```

Simulator-backed closure gate, after extending `integration_test/media_stable_id_smoke_test.dart`:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_media_delivery_ui_smoke.dart
```

Current dry-run evidence lists `integration_test/scripts/run_media_delivery_ui_smoke.dart` as group command #115; use the path form above so the command remains valid if numbering changes. If the runner does not accept the path in the current environment, rerun the list command and use the current command number:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only <current-run_media_delivery_ui_smoke-number>
```

Final hygiene:

```bash
git diff --check
```

## known-failure interpretation

The new direct regression must fail before the production fix for the reported stale open-route state and pass after the fix. A failure in existing true-unavailable/quarantine tests is in scope and must be fixed, because it means the implementation weakened media safety behavior.

Do not classify the session as fully closed if the simulator command cannot run because devices are unavailable, Flutter cannot attach, or the reliability resolver cannot find the required simulator. In that case, record host evidence and mark closure `evidence-gated` until the simulator proof passes.

Pre-existing failures in unrelated gates or dirty worktree files are not new regressions unless the failing assertion is in one of the direct media refresh/unavailable tests above or in a file changed by this session.

## done criteria

- A direct host regression exists and proves an already-open recipient group route refreshes a downloaded image without leaving/re-entering.
- The smallest production fix makes that regression pass.
- True unavailable/quarantined media tests still pass.
- The simulator media delivery UI smoke includes the already-open group recipient refresh scenario and passes through `$run-flutter-reliability-sims`.
- No production code outside the listed scope is changed.
- `git diff --check` passes.

## scope guard

Do not redesign the media grid, alter group media policy, change encryption/hash validation, change retry copy, change send/upload flow, change group listener membership/key behavior, or broaden this into all media types unless the direct failing test proves the same bug is shared by images and the shared fix is smaller than an image-only route fix.

Overengineering includes adding a new global media refresh bus, polling attachment rows, rebuilding the whole conversation on every media event, or changing repository contracts when the existing listener re-emit/repository load path can satisfy the regression.

## accepted differences / intentionally out of scope

- 1:1 media refresh behavior is intentionally out of scope; group recipient media has its own listener, repository, integrity, and simulator proof path.
- Video and voice reopen/render coverage exists in `group_new_member_media_simulator_proof_test.dart`, but this session targets the reported image unavailable placeholder. Extend to other media types only if the direct root cause is in shared thumbnail/cell state and the same narrow fix covers them.
- Reopen hydration coverage is not enough for closure because the report is specifically about an already-open route.

## dependency impact

Later group media acceptance work can depend on this plan after the implementation session satisfies the simulator-backed closure gate. If the direct regression shows current code is already correct, downstream work should skip production changes and update the plan classification to `stale/already-covered` with the exact proof. If simulator proof remains unavailable, downstream release confidence should treat the session as evidence-gated rather than closed.
