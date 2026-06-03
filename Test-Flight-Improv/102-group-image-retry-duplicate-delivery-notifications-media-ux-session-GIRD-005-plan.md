Status: accepted

# GIRD-005 - Group Media Retryable Loading Versus Terminal Unavailable UI

## Role Runtime

- Planning workflow: `implementation-plan-orchestrator`, sequential local role simulation (`Evidence Collector` -> `Planner` -> `Reviewer` -> `Arbiter`).
- Requested role settings recorded for this downstream planning pass: `model: gpt-5.5`, `reasoning_effort: xhigh`.
- No implementation agent was spawned and no production/test code was changed in this planning pass.

## Planning Progress

| Time | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| `2026-05-31 19:31 CEST` | Intake | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`; `git status --short` | Confirmed the intended plan path and that `GIRD-003` is accepted in the breakdown ledger; `GIRD-005` depends only on `GIRD-003`. | Start Evidence Collector for GIRD-005 only. |
| `2026-05-31 19:34 CEST` | Evidence Collector completed | GIRD-005 breakdown entry; source media-display acceptance bullets; `group_media_integrity_policy.dart`; `media_grid_cell.dart`; `media_thumbnail_image.dart`; `group_conversation_screen.dart`; `group_conversation_wired.dart`; `group_message_listener.dart`; `download_media_use_case.dart`; direct media/group tests | Evidence supports a narrow Flutter host-session plan: current UI can render failed/done-not-displayable attachments as terminal unavailable before visible recovery settles. | Draft GIRD-005 plan with RED-first tests, implementation steps, and closure gates. |
| `2026-05-31 19:35 CEST` | Planner completed | Evidence above plus `scripts/run_test_gates.sh`; `run-flutter-host-gates` skill instructions for host-gate vocabulary | Drafted a host-only implementation plan for GIRD-005 with simulator/device acceptance deferred to GIRD-007 per breakdown ownership. | Run strict Reviewer pass for missing tests, gates, source drift, and simulator-gate sufficiency. |
| `2026-05-31 19:37 CEST` | Reviewer completed | Draft plan; GIRD-005 exact scope; source media acceptance bullets; policy/widget/wired evidence; direct gate list | Sufficient with incremental adjustments only: clarify RED test count, keep failed media unavailable in policy unless wired stages recovery, and keep descriptor/size checks in widget policy boundary. | Apply adjustments, then run Arbiter. |
| `2026-05-31 19:37 CEST` | Arbiter completed | Reviewer findings; adjusted plan; GIRD-005/GIRD-007 ownership boundary | No structural blockers. Accepted difference: simulator/device incident proof is deferred to `GIRD-007`; GIRD-005 execution closure is host-only plus the groups gate. | Hand off to execution. |

## Execution Progress

| Time | Phase | Files inspected or touched | Command/evidence | Decision/blocker | Next action |
|---|---|---|---|---|---|
| `2026-05-31 19:39 CEST` | Contract extracted | This plan; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`; `git status --short`; `implementation-execution-qa-orchestrator` instructions | Scope: GIRD-005 media retryable loading vs terminal unavailable UI only. Required RED: policy, widget, wired `--plain-name GIRD-005`. Required GREEN/preservation: listed direct Flutter suites, `./scripts/run_test_gates.sh groups`, `git diff --check`. | No blocker. Dirty prior GIRD-001/002/003 Flutter changes, blocked GIRD-004 Go RED tests, and unrelated reliability script must be preserved. | Spawn isolated Executor with `model: gpt-5.5`, `reasoning_effort: xhigh`. |
| `2026-05-31 19:40 CEST` | Executor spawned | Plan file | Spawned agent `019e7f1e-c808-7000-9f5d-b4731e2c320a` (`model: gpt-5.5`, `reasoning_effort: xhigh`) | No blocker. Executor owns RED-first implementation pass. | Wait bounded interval, then inspect assigned evidence/progress. |
| `2026-05-31 19:40 CEST` | Executor local pass started | This plan; `lib/core/media/group_media_integrity_policy.dart`; `lib/shared/widgets/media/media_grid_cell.dart`; `lib/features/groups/presentation/screens/group_conversation_wired.dart`; focused policy/widget/wired tests; current `git status --short` | Confirmed existing GIRD-001/002/003 dirty Flutter changes are present. GIRD-005 defect remains in policy `done`/no-path unavailable classification, wired `done`/no-path quarantine, and automatic recovery without visible downloading staging. | No blocker. | Add focused GIRD-005 RED tests, then run required RED commands before production edits. |
| `2026-05-31 19:43 CEST` | RED complete | Added tests in `test/core/media/group_media_integrity_policy_test.dart`, `test/shared/widgets/media/media_grid_cell_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart` | `flutter test test/core/media/group_media_integrity_policy_test.dart --plain-name GIRD-005` failed: expected `isUnavailableMedia(done/no localPath, verified)` false, actual true. `flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name GIRD-005` failed: current unavailable branch threw missing localization null-check and no loading spinner was found. `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name GIRD-005` failed: failed-recovery row did not expose downloading media in the screen map, and done/no-path media resolved to `integrity_failed` instead of `downloading`. | Expected RED confirmed. | Implement narrow policy/widget harness/wired fix. |
| `2026-05-31 19:50 CEST` | Executor bounded-wait recovery | `git status --short`; GIRD-005 Flutter diffs; forbidden Go production diff | First Executor did not return a final result inside the bounded wait. It produced real GIRD-005 RED/prod progress but also touched forbidden `go-relay-server` production files. Go work is outside GIRD-005 scope and is not counted as evidence for this session. | Executor pass closed for scope control; no final Executor handoff yet. | Spawn a fresh bounded Executor completion pass over the visible Flutter GIRD-005 state only. |
| `2026-05-31 19:51 CEST` | Executor completion spawned | Plan file | Spawned agent `019e7f29-33b9-79d2-96fd-d33e607a860f` (`model: gpt-5.5`, `reasoning_effort: xhigh`) | No blocker. Completion pass is constrained to visible Flutter GIRD-005 state and required gates. | Wait bounded interval, then inspect assigned evidence/progress. |
| `2026-05-31 20:00 CEST` | Execution stopped / blocked | Process table; `git status --short`; Go and Flutter diffs | The GIRD-005 execution chain was still active without a final handoff, had spawned an out-of-scope `go test ./node ./bridge ./internal`, and had reintroduced forbidden Go relay production deltas. Stopped the GIRD-005 execution chain and the in-flight `./scripts/run_test_gates.sh groups`. Go relay work remained outside GIRD-005 scope. | `blocked` with `spawn_or_tool_failure` plus scope violation. GIRD-005 Flutter partial deltas were unaccepted and lacked complete GREEN/QA evidence at this point. | User later requested stopping after finishing GIRD-005, so local GIRD-005-only continuation completed the Flutter evidence without touching Go. |
| `2026-05-31 20:04 CEST` | Local GIRD-005 continuation | GIRD-005 Flutter partial deltas in `lib/core/media/group_media_integrity_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/core/media/group_media_integrity_policy_test.dart`, `test/shared/widgets/media/media_grid_cell_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart` | `flutter test test/core/media/group_media_integrity_policy_test.dart --plain-name GIRD-005` passed. `flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name GIRD-005` passed. `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name GIRD-005` passed. | Focused RED cases are now GREEN. Existing Go production/test deltas are out of scope and were not touched or counted. | Run format, preservation suites, groups gate, and diff check. |
| `2026-05-31 20:05 CEST` | Preservation GREEN | GIRD-005 Flutter production/test files only | `dart format --set-exit-if-changed ...` passed with `0 changed`. Combined preservation command passed: `flutter test test/core/media/group_media_integrity_policy_test.dart test/shared/widgets/media/media_grid_cell_test.dart test/shared/widgets/media/media_thumbnail_image_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/application/group_message_listener_test.dart` with `327` tests passing. | GIRD-005 direct/preservation coverage is satisfied. | Run named group gate and repository hygiene. |
| `2026-05-31 20:06 CEST` | Named gate and hygiene GREEN | Repository gate output; dirty tree snapshot | `./scripts/run_test_gates.sh groups` passed with `313` tests. `git diff --check` passed. | GIRD-005 host closure is accepted. Simulator/device incident proof and stable source/matrix closure remain assigned to `GIRD-007`. | Update this plan and the breakdown ledger; stop before `GIRD-006` per user instruction. |

## Source Of Truth

- Primary session contract: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`, specifically `GIRD-005`.
- Primary source spec: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`.
- Gate source of truth: `scripts/run_test_gates.sh`; `run-flutter-host-gates` instructions only inform broad host-gate vocabulary and must not trigger execution in this planning session.
- Current code and tests win over stale prose where behavior differs.
- The breakdown ledger records `GIRD-003` as `accepted`; `GIRD-005` depends only on `GIRD-003`. `GIRD-004` is blocked with Go RED-only tests but is not a dependency for this session.

## Session Classification

`implementation-ready`.

This session is executable without resolving `GIRD-004` because it changes Flutter group media display semantics, not relay/native group inbox idempotency or notification identity.

## Real Scope

In scope:

- Separate retryable/resolving group image media display states from terminal unavailable media.
- Prevent visible group image rows from showing `Media unavailable` while a valid failed-download retry is actively being recovered on an already-open group screen.
- Treat `done` group media that has required verification metadata but lacks a displayable local file/path as still resolving, so it can show loading and recover instead of being immediately rendered terminal.
- Keep unsafe, unsupported, oversized, unverifiable, quarantined, upload-failed/cancelled, and permanently failed media in terminal unavailable/error UI.
- Preserve required group content hash and encryption metadata checks before display.
- Preserve retry affordances for genuinely unavailable incoming media and failed outgoing media controls where existing tests require them.
- Ensure visible rows refresh to the loaded image while the group screen is already open.

Out of scope:

- Sender retry identity, restored composer behavior, recipient logical dedupe, relay/native idempotency, push notification display/suppression, and full incident acceptance.
- Go relay/native files and tests, including blocked `GIRD-004` RED-only deltas.
- Changing media protocol, hash format, encryption requirements, or relay download behavior unless a direct Flutter display test proves a local call-site bug.

## Scope Guard

- Do not broaden beyond `GIRD-005`; no notification, relay, inbox, composer, duplicate-message, or membership changes.
- Do not weaken `GroupMediaIntegrityPolicy` by making missing content hash, malformed hash, missing encryption metadata, invalid MIME/media type, oversized media, or integrity mismatch displayable.
- Do not turn quarantined `integrity_failed` media into infinite loading. It may remain retryable through the existing retry button, but it must stay visually terminal until the user initiates repair.
- Do not remove existing failed-media retry/delete controls for failed outgoing rows.
- Do not revert accepted prior-session Flutter/test/doc changes, blocked `GIRD-004` Go RED tests, or unrelated `scripts/check_reliability_simulation_discovery.sh`.
- Stop implementation if RED evidence shows the behavior is already covered without code changes; update this plan and classify as `stale/already-covered` instead of inventing a fix.

## Exact Problem Statement

The source spec says recipients can briefly see `Media unavailable` before a group image loads, making a recoverable download or still-resolving display state look terminal. Current code supports that risk:

- `MediaGridCell` renders unavailable whenever `GroupMediaIntegrityPolicy.isUnavailableMedia(..., requireVerifiedContentHash: true)` is true or required metadata is missing.
- `GroupMediaIntegrityPolicy.isUnavailableMedia` currently treats `failed` and `integrity_failed` as unavailable, and treats any `done` media that is not fully displayable as unavailable when verified content hash is required.
- `GroupConversationWired._downloadPendingMedia` can recover `failed` visible attachments, but it does not stage the visible row as `downloading` before awaiting `downloadMedia`, so the row can render terminal unavailable during the recovery attempt.
- `GroupConversationWired._resolveAttachmentsForDisplay` marks `done` media with no `localPath` as `integrity_failed`; if that state is a transient local-path/display hydration gap with otherwise valid verification metadata, the user sees terminal unavailable instead of loading/retry.

The user-visible fix is not to hide unsafe media. The fix is to show loading/preparing while a valid group image can still resolve, then show the image when it resolves, and still show terminal unavailable for genuinely unsafe or permanently failed media.

## Current Evidence

- Breakdown line evidence: `GIRD-005` owns "recoverable media unavailable flash and terminal unsafe media preservation"; dependency is only `GIRD-003`, which the closure ledger marks accepted.
- Source spec evidence: media display gaps explicitly require no `Media unavailable` flash for actively retrying media and no terminal unavailable label for still-resolving display metadata; terminal unsafe media must still render unavailable.
- `lib/core/media/group_media_integrity_policy.dart`:
  - `canDisplayVerifiedGroupMedia` requires `done`, non-null `localPath`, valid content hash, and encryption metadata.
  - `isUnavailableMedia` currently returns true for `failed`, `integrity_failed`, upload failure/cancel states, and `done` media that cannot fully display.
- `lib/shared/widgets/media/media_grid_cell.dart`:
  - `_showsUnavailableMedia` combines policy unavailable state, invalid descriptor, invalid size, and missing required group metadata.
  - A non-unavailable image that is not displayable falls through to the loading placeholder, which is the desired state for still-resolving valid media.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`:
  - `_downloadPendingMedia` attempts recovery for `pending`, `downloading`, and `failed` media.
  - Manual unavailable retry already stages the target as `downloading` before awaiting download; automatic visible recovery does not.
  - `_resolveAttachmentsForDisplay` already maps a missing on-disk file for `done` media with a path back to `pending`, but maps `done` media with null `localPath` to `integrity_failed`.
  - `_applyMessageUpdate` reloads media and re-runs `_downloadPendingMedia`, so visible rows can refresh while open if the display state is staged correctly.
- `lib/features/groups/application/group_message_listener.dart` emits the message before asynchronous media auto-download and re-emits afterward; that path should be preserved rather than converted to synchronous listener blocking.
- Existing direct tests already cover adjacent preservation:
  - `test/core/media/group_media_integrity_policy_test.dart` covers display eligibility and status helper boundaries.
  - `test/shared/widgets/media/media_grid_cell_test.dart` covers unavailable UI for failed/integrity-failed/missing-hash/missing-encryption group media.
  - `test/features/groups/presentation/group_conversation_screen_test.dart` covers quarantined incoming media retry controls and read-only unavailable retry controls.
  - `test/features/groups/presentation/group_conversation_wired_test.dart` covers pending incoming image refresh while open, targeted repair of quarantined incoming media, and failed repair staying quarantined.
  - `test/features/groups/application/group_message_listener_test.dart` covers shared media download joining and GIRD-003 listener emission/notification behavior.

## Closure Bar

GIRD-005 is good enough when the following coverage ledger is satisfied:

| Requirement | Planned proof |
|---|---|
| Retryable failed-download recovery does not show terminal unavailable while active recovery is underway. | New `group_conversation_wired_test.dart` RED/GREEN test with a valid incoming failed group image, gated download, loading UI before the gate resolves, then image display after the gate resolves. |
| `done` but not locally displayable group image with valid verification metadata remains resolving, not terminal. | New policy/widget test for valid verified `done` image with no local path showing loading, plus a wired test that normalizes it to pending/downloading and recovers. |
| Unsafe, unverifiable, quarantined, unsupported, oversized, upload-failed/cancelled, or permanently failed media still shows unavailable/error UI. | Existing MD-012 tests plus added preservation assertions if production changes touch policy/widget branches. |
| Visible rows refresh to the loaded image while the group screen is already open. | New failed-recovery wired test and existing pending-open-route refresh test. |
| Required content hash and encryption metadata remain mandatory for display. | Existing policy/widget tests plus preservation checks for missing hash/encryption and integrity-failed media. |
| Retry controls for genuinely unavailable media remain available. | Existing `group_conversation_screen_test.dart` read-only/quarantined retry controls and `group_conversation_wired_test.dart` targeted repair tests. |

The session must not claim final source-spec closure. `GIRD-007` owns full incident simulator/device acceptance and stable matrix/source-doc reconciliation.

## TDD/RED Plan

Add focused RED tests before production edits:

1. `test/core/media/group_media_integrity_policy_test.dart`
   - Add a `GIRD-005` test proving verified `done` group image metadata with a missing `localPath` is classified as resolving/not terminal unavailable.
   - In the same test or a paired preservation test, prove missing content hash, missing encryption metadata, malformed hash, `integrity_failed`, `upload_failed`, and `upload_cancelled` remain unavailable.
   - Expected current result: fails because `isUnavailableMedia(... requireVerifiedContentHash: true)` uses `canDisplayVerifiedGroupMedia`, which treats missing local path as unavailable.

2. `test/shared/widgets/media/media_grid_cell_test.dart`
   - Add a `GIRD-005` widget test for a verified `done` image with no `localPath`: expect a loading placeholder, no `Media unavailable`, no `MediaThumbnailImage`, no retry button, and no open tap.
   - Add or preserve assertions that missing hash/encryption and quarantined media still show `Media unavailable`.
   - Expected current result: fails because `_showsUnavailableMedia` is true for this `done`/no-path state.

3. `test/features/groups/presentation/group_conversation_wired_test.dart`
   - Add a `GIRD-005` test where an incoming group image attachment starts as `failed`, has valid descriptor/size/content hash/encryption metadata, and `downloadMedia` is gated.
   - Before completing the gate, assert the visible row shows loading/preparing state, no `Media unavailable`, no unavailable retry button, and no broken-image icon.
   - After completing the gate, assert the same visible row refreshes to `done`, has an absolute local path, and opens the image without closing/reopening the group.
   - Expected current result: fails because automatic visible recovery does not update `_mediaMap` to `downloading` before awaiting the download.

4. `test/features/groups/presentation/group_conversation_wired_test.dart`
   - Add a `GIRD-005` test where an incoming group image attachment starts as `done` with valid content hash/encryption metadata but no `localPath`.
   - Assert it is displayed as loading/resolving, not quarantined/unavailable, and then recovers to the loaded image through the existing download path.
   - Expected current result: fails because `_resolveAttachmentsForDisplay` marks `done`/null-path media as `integrity_failed`.

5. Preservation tests to run before and after GREEN:
   - Existing MD-012 policy/widget/screen/wired tests for quarantined media, read-only unavailable retry controls, targeted repair, and failed repair staying quarantined.
   - Do not weaken these assertions to make GIRD-005 pass.

## Implementation Plan

1. Add narrow policy language in `GroupMediaIntegrityPolicy`:
   - Introduce a helper or adjust `isUnavailableMedia` so verified `done` media with valid required content hash and encryption metadata but no local path is "resolving", not terminal unavailable.
   - Keep `canDisplayVerifiedGroupMedia` strict: display still requires `done`, a local path, valid content hash, and encryption metadata.
   - Keep policy terminal unavailable true for missing/malformed content hash, missing encryption metadata, `integrity_failed`, upload failed/cancelled, and ordinary `failed` states. Active failed-download recovery should become loading by staging the visible attachment as `downloading` in the wired recovery path, not by globally making every `failed` attachment non-terminal.
   - Keep invalid descriptor and invalid size terminal through the existing `MediaGridCell` MIME/size checks.

2. Update `MediaGridCell` only as needed by the new policy:
   - Let verified image media in a resolving state fall through to `_buildLoadingPlaceholder`.
   - Do not build `MediaThumbnailImage` until `_isDisplayableDoneMedia` is true.
   - Do not enable open/tap behavior for resolving media.
   - Keep retry button visibility tied to genuinely unavailable retryable states, not loading states.

3. Update `GroupConversationWired._resolveAttachmentsForDisplay`:
   - For incoming/group media that is `done` with valid required verification metadata but lacks `localPath`, normalize it to a recoverable state such as `pending` instead of marking `integrity_failed`.
   - Continue marking `done` media as `integrity_failed` when required content hash/encryption metadata is absent, malformed, unsafe, or unverifiable.
   - Preserve the existing file-missing `done` -> `pending` behavior and consider persisting the status change if needed so the repository state matches the visible state.

4. Update automatic visible recovery in `GroupConversationWired._downloadPendingMedia`:
   - Before awaiting `downloadMedia`, stage a valid recoverable attachment as `downloading` in `_mediaMap` and persist/update download status when appropriate.
   - Apply this to valid `pending`, `downloading`, and `failed` candidates that are safe to retry; do not stage quarantined, missing-hash, missing-encryption, invalid descriptor, or oversized media as loading.
   - After `downloadMedia` returns null, rehydrate the attachment from the repository and policy resolver before choosing a fallback status, so integrity quarantine written by `downloadMedia` is not hidden as generic `failed`.
   - Keep manual unavailable retry behavior consistent with this resolution path.

5. Leave `GroupMessageListener` asynchronous auto-download behavior intact unless the RED tests prove a listener re-emission gap. If touched, add a focused listener test; otherwise run the existing listener suite as preservation only.

6. Leave `download_media_use_case.dart` intact unless the GREEN implementation proves it is overwriting terminal/quarantine status incorrectly. If touched, run its direct test suite and do not broaden into protocol changes.

7. Update only this GIRD-005 plan with final execution evidence during execution, and after execution update only the breakdown ledger with the GIRD-005 verdict. Stable source/matrix closure remains assigned to `GIRD-007`.

## Existing Tests Covering This Area

- `test/core/media/group_media_integrity_policy_test.dart`
  - Covers hash validation, display eligibility, and status helper boundaries.
  - Missing: resolving/not-terminal classification for verified `done` media with no local display path.
- `test/shared/widgets/media/media_grid_cell_test.dart`
  - Covers GIF/JPEG display, invalid/oversized done media, required group content hash, integrity-failed unavailable UI, and MD-012 unavailable behavior.
  - Missing: verified resolving/no-path loading state.
- `test/shared/widgets/media/media_thumbnail_image_test.dart`
  - Covers image provider/cache-width behavior.
  - Missing: likely no required GIRD-005 change unless thumbnail error behavior is touched.
- `test/features/groups/presentation/group_conversation_screen_test.dart`
  - Covers message row controls and unavailable retry controls.
  - Missing: broad screen-level proof may not be necessary if wired tests cover lifecycle; run as preservation.
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - Covers pending incoming group image refresh while open, targeted media repair, and failed repair quarantine.
  - Missing: failed download recovery avoiding unavailable before success, and `done`/null-path resolving state.
- `test/features/groups/application/group_message_listener_test.dart`
  - Covers listener auto-download related behavior and GIRD-003 listener emission.
  - Missing: likely no new listener test unless implementation touches listener re-emission.

## Files And Repos To Inspect Next

Production files:

- `lib/core/media/group_media_integrity_policy.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart` only if thumbnail error semantics are touched
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` only if row/control wiring changes
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/group_message_listener.dart` only if listener re-emission is touched
- `lib/features/conversation/application/download_media_use_case.dart` only if null/quarantine return handling needs adjustment

Test files:

- `test/core/media/group_media_integrity_policy_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/shared/widgets/media/media_thumbnail_image_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart` only if `download_media_use_case.dart` changes

Repos/files explicitly not to inspect or edit for this session:

- `go-relay-server/**`
- `go-mknoon/**`
- notification/NSE files
- `scripts/check_reliability_simulation_discovery.sh`

## Direct Tests And Gates

RED-first focused commands after adding tests and before production edits:

```bash
flutter test test/core/media/group_media_integrity_policy_test.dart --plain-name GIRD-005
flutter test test/shared/widgets/media/media_grid_cell_test.dart --plain-name GIRD-005
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name GIRD-005
```

Expected RED: the new GIRD-005 tests fail on current behavior for policy/widget resolving state and automatic visible failed-download recovery.

GREEN and preservation commands after implementation:

```bash
flutter test test/core/media/group_media_integrity_policy_test.dart
flutter test test/shared/widgets/media/media_grid_cell_test.dart
flutter test test/shared/widgets/media/media_thumbnail_image_test.dart
flutter test test/features/groups/presentation/group_conversation_screen_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
```

Conditional command if `download_media_use_case.dart` changes:

```bash
flutter test test/features/conversation/application/download_media_use_case_test.dart
```

Named gate and repository hygiene:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

No Go test command is required or allowed for GIRD-005 unless the source scope is explicitly changed by the controller.

## Device/Relay Proof Profile

GIRD-005 execution closure is host-only plus the Flutter `groups` gate.

Reason:

- The planned change is local Flutter media display/presentation state and policy interpretation for already persisted group media attachments.
- It does not change relay storage, native libp2p delivery, APNs/Android notification behavior, multi-device eligibility, or transport recovery.
- The source breakdown assigns final incident simulator/device evidence and stable closure docs to `GIRD-007`, and the prompt explicitly says not to require live relay or multi-device evidence unless this session genuinely changes integration behavior.

Deferred simulator acceptance:

- `GIRD-007` must still run the source-spec reliability/device acceptance, including group media incident proof through `$run-flutter-reliability-sims`.
- GIRD-005 must not claim the full group image incident closed on host tests alone; it only closes the row-owned media unavailable/loading display gap.

## Known-Failure Interpretation

- Existing dirty Go relay/native deltas are outside GIRD-005. Do not run them, fix them, revert them, or classify them as GIRD-005 regressions; GIRD-004 remains the owning session for Go idempotency.
- Unrelated dirty `scripts/check_reliability_simulation_discovery.sh` must remain untouched.
- Accepted GIRD-001/GIRD-002/GIRD-003 Flutter/test/doc changes are baseline context. Do not revert them to make tests easier.
- If `./scripts/run_test_gates.sh groups` fails in a group integration file unrelated to media display, record the failing command and root cause; fix only if the failure is caused by GIRD-005 changes, otherwise classify as pre-existing/controller action.
- If newly added RED tests do not fail before production changes, stop and reassess whether the gap is already covered or the test is not exercising the intended seam.

## Risks

- Over-broad policy changes could make unsafe media appear to load forever. The plan counters this with preservation tests for missing hash/encryption, invalid descriptor/size, and `integrity_failed`.
- Staging `failed` media as `downloading` too eagerly could hide a permanently failed state. The plan limits loading to the active recovery window and rehydrates repository status after null download results.
- `done`/null-path normalization could mask a real corruption if required verification metadata is absent. The plan only treats the state as resolving when required metadata is valid.
- Widget-only fixes could still flash unavailable during wired recovery. The plan requires a `GroupConversationWired` test with a gated download before completion.
- Rehydrating attachments after download failure could reorder or duplicate media rows if helper logic is careless. The plan keeps replacement keyed by attachment id and preserves existing targeted-repair tests.

## Done Criteria

- The planned GIRD-005 RED tests fail before production changes and pass after production changes.
- Direct suites listed above pass, including preservation tests for terminal unavailable/quarantine behavior.
- `./scripts/run_test_gates.sh groups` passes.
- `git diff --check` passes.
- No Go, relay, notification, membership, duplicate-delivery, or unrelated script files are modified.
- Coverage ledger is satisfied:
  - recoverable failed-download active retry: covered by new wired test
  - verified `done` but not locally displayable: covered by policy/widget/wired tests
  - terminal unsafe/unverifiable/quarantined media: covered by existing and preservation tests
  - visible open-screen refresh to loaded image: covered by new wired test
  - required hash/encryption metadata: covered by policy/widget preservation tests
  - retry controls for genuinely unavailable media: covered by existing screen/wired tests
- The breakdown ledger is updated after execution with GIRD-005 verdict only; final stable docs remain for `GIRD-007`.

## Accepted Differences / Intentionally Out Of Scope

- Simulator/device proof is intentionally deferred to `GIRD-007` rather than required for GIRD-005 execution closure. This is an accepted difference from the generic mobile simulator closure rule because the current row owns a host-proveable Flutter display-state gap and the breakdown explicitly assigns final incident simulator acceptance to GIRD-007.
- Quarantined `integrity_failed` media remains terminal unavailable with retry affordance; it is not reclassified as loading unless a user/manual retry explicitly starts a repair.
- Permanently failed download results still settle back to unavailable/error UI after the active retry attempt.
- `MediaThumbnailImage` async image decode errors remain terminal image errors; the source doc already says not to base this fix on async decode-as-error theory.

## Dependency Impact

- `GIRD-006` notification planning remains dependency-blocked on `GIRD-004`, not on this plan.
- `GIRD-007` depends on GIRD-005 evidence for the media unavailable/loading acceptance gap and must still run final incident/simulator/docs closure.
- If GIRD-005 changes shared media widget policy more broadly than planned, `GIRD-007` should include broader feature host scope through `$run-flutter-host-gates`; this session itself should stay with direct suites and `./scripts/run_test_gates.sh groups`.

## Reviewer Pass

- Sufficiency: sufficient with adjustments; no structural blocker after the wording/guardrail fixes above.
- Missing files/tests/gates: none for the session scope. `download_media_use_case_test.dart` remains conditional on touching `download_media_use_case.dart`.
- Stale assumptions: none found. The plan uses the breakdown ledger for dependency status and current code for behavior.
- Overengineering: no new protocol/storage architecture is planned; the policy/helper change is limited to display-state classification.
- Decomposition: narrow enough for implementation; it owns only policy/widget/wired display behavior.
- Simulator concern: generic mobile media work would normally invite simulator proof, but this session's row and prompt explicitly defer incident simulator/device acceptance to `GIRD-007`. The plan records that as an accepted difference and does not claim full source closure.
- Checklist parity: every GIRD-005 exact-scope bullet is mapped in the closure bar and done criteria.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: none requiring another planning loop.
- Accepted differences: simulator/device incident proof is deferred to `GIRD-007`; GIRD-005 must not claim full source-spec closure on host evidence.
- Final verdict: `execution-ready`.

## Final execution verdict

- Verdict: `accepted`.
- Scope: GIRD-005 Flutter media loading/unavailable display semantics only.
- RED evidence: the plan-listed GIRD-005 policy, widget, and wired tests failed before production edits for verified `done`/no-local-path classification, loading versus unavailable UI, failed-recovery visible downloading state, and done/no-path recovery.
- GREEN evidence: focused `--plain-name GIRD-005` policy, widget, and wired tests passed; the six direct/preservation Flutter suites passed with `327` tests; `./scripts/run_test_gates.sh groups` passed with `313` tests; `git diff --check` passed.
- Implemented behavior: verified `done` group media with required hash and encryption metadata but no local path is resolving rather than terminal unavailable; automatic visible recovery stages valid failed/pending group media as `downloading` before awaiting download; truly unsafe, unverifiable, quarantined, upload-failed/cancelled, invalid, or oversized media remains terminal unavailable/error UI.
- Scope reconciliation: Go relay/native work is not valid GIRD-005 evidence. Current Go production and test deltas are out of GIRD-005 scope, were not touched during the accepted local continuation, and remain governed by blocked `GIRD-004`.
- Deferred proof: simulator/device incident acceptance and stable source/matrix closure remain assigned to `GIRD-007`; this verdict closes only the row-owned media unavailable/loading gap.
