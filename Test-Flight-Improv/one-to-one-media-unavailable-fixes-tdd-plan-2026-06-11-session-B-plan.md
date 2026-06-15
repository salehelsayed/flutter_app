# Session B Receiver Commit And Orphan Adoption Plan

Status: accepted_with_explicit_follow_up

Source doc: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`  
Breakdown: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`  
Session: B Receiver Commit And Orphan Adoption

## Planning Progress

- 2026-06-11 16:42:28 CEST | Role: Arbiter completed | Files inspected since last update: full Session B draft and mandatory-section coverage | Decision/blocker: no structural blockers remain; plan is execution-ready and Session B can proceed to implementation. Spawned planner child wrote the draft but was terminated after a silent bounded interval before final promotion; local reviewer/arbiter completed the promotion. | Next action: execute Session B with failing-first tests and scoped owner-file edits.
- 2026-06-11 16:42:28 CEST | Role: Reviewer completed | Files inspected since last update: `## real scope` through `## dependency impact` in this plan | Decision/blocker: sufficient as-is; exact target files, regression-first tests, host gates, simulator deferral, source checklist ledger, dirty-worktree guard, and accepted direct-hash difference are explicit. | Next action: arbiter classification.
- 2026-06-11 16:38:22 CEST | Role: Planner started | Files inspected since last update: Evidence Collector notes in this file | Decision/blocker: Session B remains a narrow Flutter receiver-persistence plan in `DownloadMediaUseCase`; no production-code edits in planning | Next action: draft mandatory plan sections with focused regressions, closure bar, gates, and dirty-worktree guard.
- 2026-06-11 16:38:22 CEST | Role: Evidence Collector completed | Files inspected since last update: source plan, session breakdown, debug report excerpts, `test-gate-definitions.md`, `codebase-test-inventory.md`, graphify query output, `download_media_use_case.dart`, `download_media_use_case_test.dart`, `media_file_manager.dart`, `media_attachment_repository.dart`, focused git diffs | Decision/blocker: current code repairs stored local paths but does not explicitly adopt an existing deterministic canonical file before bridge download; direct cleanup can still target the canonical output path on failure | Next action: build the smallest execution plan around canonical adoption and current-attempt cleanup ownership.
- 2026-06-11 16:36:01 CEST | Role: Evidence Collector started | Files inspected since last update: graphify skill instructions | Decision/blocker: existing `graphify-out/graph.json` requires scoped `graphify query` evidence before raw source browsing | Next action: inspect source plan, breakdown, gate definitions, graph query output, and direct receiver media code/tests.

## Execution Progress

- 2026-06-11 18:36:02 CEST | Phase: local QA completed / final verdict written | Files inspected/touched: `lib/features/conversation/application/download_media_use_case.dart`, `test/features/conversation/application/download_media_use_case_test.dart`, this plan | Command/log: local QA reviewed the Session B diff, verified direct `.part` staging, canonical orphan adoption before bridge calls, staged-only cleanup on failure, relative-path persistence with absolute return path, and group-media branch preservation; `git diff --check -- lib/features/conversation/application/download_media_use_case.dart test/features/conversation/application/download_media_use_case_test.dart Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-B-plan.md` passed with no whitespace errors. | Decision/blocker: final verdict `accepted_with_explicit_follow_up`; no blocking Session B issues remain. Nested Executor/QA child tooling was unavailable, so the explicitly allowed bounded local sequential fallback was used and recorded. | Next action: Session F still owns simulator acceptance and overall source-plan closure with the targeted 1:1 media journey command.
- 2026-06-11 18:26:06 CEST | Phase: graph update completed / local QA started | Files inspected/touched: `graphify-out/graph.json`, `graphify-out/GRAPH_REPORT.md`, graphify backup artifacts | Command/log: `graphify update .` completed: AST extraction `5032/5032 files`, backed up curated graph files under `2026-06-11/`, skipped `graph.html` because the graph has `94506` nodes over the 5000-node HTML limit, rebuilt `94506` nodes / `165099` edges / `4134` communities, and updated `graphify-out/graph.json` plus `GRAPH_REPORT.md`. | Decision/blocker: graph update completed; no product blocker. | Next action: local QA review of scoped diffs and final verdict.
- 2026-06-11 18:20:33 CEST | Phase: baseline gate passed / graph update starting | Files inspected/touched: no new files | Command/log: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed. The earlier unqualified baseline failure is classified as environment/device-selection; with the documented explicit `macos` selector, host baseline printed `00:56 +110: All tests passed!`, `integration_test/loading_states_smoke_test.dart` printed `00:04 +7: All tests passed!`, and `integration_test/posts_phase1_fake_test.dart` printed `00:00 +1: All tests passed!`. | Decision/blocker: required baseline evidence is satisfied; no gate blocker. | Next action: run `graphify update .` after code changes.
- 2026-06-11 18:12:27 CEST | Phase: baseline failure triaged / explicit-device rerun starting | Files inspected/touched: `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md` | Command/log: script inspection showed `baseline` runs host tests first, then `integration_test/loading_states_smoke_test.dart` and `integration_test/posts_phase1_fake_test.dart` one at a time; `integration_test_args` only passes `-d` when `FLUTTER_DEVICE_ID` is set. Gate definitions note prior baseline revalidation used `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` and warn to set `FLUTTER_DEVICE_ID` when multiple Flutter targets are attached. | Decision/blocker: baseline first failure classified environment/device-selection, not Session B code; retrying the same named gate with explicit `macos` selector is the focused triage rerun. | Next action: run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- 2026-06-11 18:07:12 CEST | Phase: baseline gate failed / triage pending | Files inspected/touched: no new files | Command/log: `./scripts/run_test_gates.sh baseline` exited 1 after a host test batch printed `00:57 +110: All tests passed!`; the trailing failure was Flutter device selection: "More than one device connected; please specify a device with the '-d <deviceId>' flag" followed by "No devices are connected." No redirected log path. | Decision/blocker: classification state `pending_triage`; failure appears environment/device-selection related, not Session B code, but script contents need inspection before final classification. | Next action: focused triage command `sed -n '1,220p' scripts/run_test_gates.sh` to identify the baseline device-backed step and determine whether rerun with an explicit host/device selector is appropriate.
- 2026-06-11 18:05:19 CEST | Phase: named gate `1to1` passed / `baseline` starting | Files inspected/touched: no new files | Command/log: `./scripts/run_test_gates.sh 1to1` passed (`00:07 +74: All tests passed!`). | Decision/blocker: no `1to1` gate blocker. | Next action: run `./scripts/run_test_gates.sh baseline` because Flutter production code changed.
- 2026-06-11 17:58:32 CEST | Phase: direct suite passed / named gates starting | Files inspected/touched: `lib/features/conversation/application/download_media_use_case.dart`, `test/features/conversation/application/download_media_use_case_test.dart` | Command/log: `flutter test test/features/conversation/application/download_media_use_case_test.dart` passed all tests, including Session B regressions, stored-local-path repair, in-flight dedupe, and existing group-media policy coverage. | Decision/blocker: no direct-suite blocker. | Next action: run `./scripts/run_test_gates.sh 1to1`, then `./scripts/run_test_gates.sh baseline`.
- 2026-06-11 17:57:18 CEST | Phase: Executor implementation completed / focused GREEN verification completed | Files inspected/touched: `lib/features/conversation/application/download_media_use_case.dart`, `test/features/conversation/application/download_media_use_case_test.dart` | Command/log: implemented direct canonical orphan adoption, `.part` staging for direct downloads, staged cleanup ownership, and promotion after validation. Re-ran all four plain-name regressions; each passed: canonical adoption skipped bridge, not-found cleanup preserved canonical, validation-failure cleanup preserved canonical, and staged promotion stored only the relative canonical path. | Decision/blocker: no blocker in focused regressions. | Next action: run `flutter test test/features/conversation/application/download_media_use_case_test.dart` for full direct suite coverage.
- 2026-06-11 17:48:32 CEST | Phase: RED verification completed | Files inspected/touched: `test/features/conversation/application/download_media_use_case_test.dart` | Command/log: `flutter test test/features/conversation/application/download_media_use_case_test.dart --plain-name "downloadMedia adopts canonical file before bridge download"` failed because result was null after bridge `not found` and cleanup deleted the canonical file; `--plain-name "downloadMedia does not delete pre-existing canonical file when bridge returns not found"` failed because file existence was false after cleanup; `--plain-name "downloadMedia validation failure after bridge success does not delete a pre-existing canonical file"` failed because invalid-file cleanup deleted the pre-existing canonical file; `--plain-name "downloadMedia promotes staged file only after validation"` failed because bridge `outputPath` was the canonical path, not a staging path. | Decision/blocker: RED failures match Session B expected current behavior; no unrelated test blocker. | Next action: implement canonical orphan adoption plus direct staging/current-attempt cleanup ownership in `DownloadMediaUseCase`.
- 2026-06-11 17:45:14 CEST | Phase: RED tests added / failing-first verification starting | Files inspected/touched: `test/features/conversation/application/download_media_use_case_test.dart` | Command/log: added Session B direct regressions for canonical orphan adoption, not-found cleanup preservation, validation-failure preservation, and the conditional staged-promotion proof because direct downloads currently target the canonical path. | Decision/blocker: no blocker; production code not edited yet. | Next action: run the three required direct `--plain-name` tests and the staged-promotion plain-name test to capture RED evidence.
- 2026-06-11 17:26:52 CEST | Phase: contract extracted / local fallback started | Files inspected/touched: plan, breakdown, `lib/features/conversation/application/download_media_use_case.dart` diff, `test/features/conversation/application/download_media_use_case_test.dart` diff, `graphify-arch` query | Command/log: `graphify query "Session B receiver commit orphan adoption DownloadMediaUseCase MediaAttachmentRepository updateLocalPath localPath null canonical file bridge download" .` returned the Session B seam around `download_media_use_case.dart`, `MediaAttachment`, and `updateLocalPath`; `git diff -- ...download_media_use_case.dart ...download_media_use_case_test.dart` showed existing dirty adjacent local-path repair/group-media changes. | Decision/blocker: nested `spawn_agent`/child-agent tooling is not available in this session, so the explicitly allowed bounded local sequential fallback is in use; no product/test blocker found. Scope remains Session B owner files only. | Next action: add the required failing-first Session B plain-name regressions before production edits.
- 2026-06-11 16:46:00 CEST | Phase: execution child spawn failed | Files inspected/touched: this plan only | Command/log: `codex -m gpt-5.5 -c model_reasoning_effort='"xhigh"' ... exec --output-last-message /tmp/mknoon_session_B_execution.out ...` exited 1 before reading the execution skill beyond startup; CLI error reported a usage-limit lockout and said to try again at `Jul 11th, 2026 3:50 PM` | Decision/blocker: blocked, blocker class `spawn_or_tool_failure`. The required fresh Session B execution/QA child context is not available, and no isolated execution child materialized that could safely use the execution skill's local fallback. | Next action: resume Session B from this execution-ready plan when spawned Codex child contexts are available, or obtain explicit user direction to use a non-spawned local execution path despite the execution isolation contract.

## Evidence Collected

- The source plan classifies Session B as `implementation-ready` and scopes it to receiver local-path commit/orphan adoption in `DownloadMediaUseCase`.
- The session breakdown narrows Session B to `lib/features/conversation/application/download_media_use_case.dart` and `test/features/conversation/application/download_media_use_case_test.dart`.
- The debug report identifies the concrete failure: relay auto-delete can happen after native writes `outputPath`, while Flutter commits `local_path` only after the bridge returns; if the app dies or DB update fails in between, retry can miss the canonical orphan and later cleanup can delete it.
- Current `downloadMedia` first repairs only candidates with a stored `localPath`; it does not discover an existing deterministic canonical file when the attachment row has `localPath == null`.
- Current direct failure cleanup tracks `cleanupAbsolutePath`/`cleanupDownloadPath` and, for non-group media, deletes `absolutePath` on bridge failure or exception. That path is also the deterministic canonical file path for the attachment.
- Group-media code already has separate encrypted-companion and plaintext preservation logic, but Session B is a direct 1:1 receiver cleanup/adoption slice. Do not generalize into group policy.
- Direct upload tests currently expect direct `contentHash` to be null; the `MediaAttachment` model documents `contentHash` as a group relay blob hash. Direct canonical-file validation should therefore use existence and expected size, and hash validation only if an existing direct hash contract is found during implementation.
- `test/features/conversation/application/download_media_use_case_test.dart` already has fakes and helper seams for pre-creating canonical files, mutating bridge responses, observing bridge call count, and checking repository local-path/status updates.
- The current dirty worktree already modifies `download_media_use_case.dart` and its test. Execution must inspect and preserve those changes instead of reverting to HEAD.
- `test-gate-definitions.md` says the `1to1` gate runs when shared 1:1 send, retry, upload, listener, inbox, or feed-originated 1:1 entry points change. `transport` is for bridge/resume/reconnect/transport fallback/app bootstrap changes and should not be required unless Session B widens.

## real scope

Implement receiver-side canonical orphan adoption for direct 1:1 media downloads.

In scope:

- Add focused failing regressions in `test/features/conversation/application/download_media_use_case_test.dart`.
- Update `lib/features/conversation/application/download_media_use_case.dart` so a valid existing deterministic canonical file can be adopted before bridge download when the attachment row has no stored `localPath`.
- Ensure direct bridge failure, exception, and post-bridge validation failure cleanup do not delete a canonical file that existed before the current invocation.
- Persist the relative canonical path through `MediaAttachmentRepository.updateLocalPath`, return an absolute path for immediate UI display, and mark the attachment done only after validating the local file still exists.
- Keep existing in-flight dedupe behavior and existing stored-local-path repair behavior.

Out of scope:

- Relay media durability, multi-relay failover, local-WiFi sender fallback, direct retry UI wiring, duplicate replay repair, thumbnail fallback, group-media policy, posts/media, and broad bridge protocol changes.

## closure bar

Session B is good enough when every checklist item below is mapped to a failing-first regression and the implementation satisfies it without widening scope:

| Source checklist item | Planned proof | Closure expectation |
| --- | --- | --- |
| Adopt canonical file before bridge download | `downloadMedia adopts canonical file before bridge download` | With `localPath == null` and pending/failed status, an existing deterministic canonical file is validated, persisted as a relative path, returned as an absolute path, marked done, and `media:download` is not sent. |
| Do not delete pre-existing canonical file on bridge `not found` | `downloadMedia does not delete pre-existing canonical file when bridge returns not found` | If a bridge attempt is still needed and returns `not found`, cleanup deletes only artifacts created by that attempt and preserves a canonical file that existed before the attempt. |
| Validation failure after bridge success does not delete pre-existing canonical file | `downloadMedia validation failure after bridge success does not delete a pre-existing canonical file` | A bad relay result or invalid downloaded artifact cannot destroy a valid canonical file that was present before the current invocation. |
| Promote staged file only after validation if staging is introduced | Add `downloadMedia promotes staged file only after validation` only if the implementation introduces a staged download path | No `.part`, `.enc`, or other staging path is stored as `localPath`; promotion occurs only after validation. If no staging path is introduced, record this item as not applicable in the execution summary. |

Host tests are enough to close the Session B implementation slice, but not the full reported 1:1 media-unavailable issue. Overall source-plan closure remains simulator-gated and belongs to Session F unless this session is explicitly asked to take acceptance ownership.

## source of truth

- Active contract: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`, Session B sections.
- Ordered rollout contract: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`, Session B ledger row.
- Root-cause evidence: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`.
- Test inventory source: `Test-Flight-Improv/codebase-test-inventory.md`.
- Current production code and tests win over stale prose if there is a disagreement. Existing dirty user changes in target files must be preserved and understood before editing.

## session classification

implementation-ready

The implementation slice is ready because the target seam, failing tests, files, and host gates are concrete. The overall 1:1 media-unavailable closure remains evidence-gated by Session F simulator acceptance.

## exact problem statement

Direct 1:1 media can become unavailable when native code writes the receiver's deterministic canonical file but Flutter fails before persisting `media_attachments.local_path`. A later retry only checks stored `localPath` candidates, then attempts relay download. If the relay already auto-deleted the blob and returns `not found`, the direct cleanup path can delete the existing canonical file because it treats the deterministic output path as a failed current-attempt artifact. User-visible behavior is an incoming media message that stays unavailable even though valid bytes exist locally.

This session must make receiver retry adopt a valid canonical orphan and prevent cleanup from deleting pre-existing canonical files. It must not change sender behavior, relay semantics, UI retry wiring, or group-media quarantine rules.

## files and repos to inspect next

Production:

- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/core/media/media_file_manager.dart`
- `lib/core/media/media_file_path_convention.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`

Tests:

- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/shared/fakes/fake_media_file_manager.dart` only if the local test fake is insufficient
- `test/shared/fakes/in_memory_media_attachment_repository.dart` only if the local test fake is replaced

Docs/gates:

- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/codebase-test-inventory.md`

## existing tests covering this area

- `downloadMedia returns updated attachment on success` covers successful direct download, DB local-path update, and immediate absolute return path.
- `stores relative path in DB for persistence` pins relative DB storage for media attachments.
- `does not let failed fallback clobber local media that links during download` covers an in-flight local-path update while the bridge later fails.
- `repairs a failed attachment when the local media file already exists` covers an existing file only when the attachment already has `localPath`.
- `PL-013 removes partial failed download and retry succeeds` covers partial current-attempt cleanup.
- `overlapping callers for the same attachment trigger only one real download` covers in-flight dedupe.
- `group download failure cleanup preserves an already committed plaintext file` covers a group-specific committed plaintext preservation case.

Missing coverage:

- No direct test covers an existing canonical file with `localPath == null`.
- No direct test proves bridge `not found` cleanup preserves a canonical file that existed before this invocation.
- No direct test proves post-bridge invalid-file cleanup preserves a pre-existing canonical file.
- No test is needed in a new file unless the implementation introduces a new helper module.

## regression/tests to add first

Add these tests before production changes and confirm they fail for the intended reason:

1. `downloadMedia adopts canonical file before bridge download`
   - Arrange `testAttachment.copyWith(size: _jpegBytes.length, localPath: null, downloadStatus: pending or failed)`.
   - Pre-create the deterministic canonical file from `fileManager.localPathForAttachment(contactPeerId: 'contact-A', blobId: attachment.id, mime: attachment.mime)`.
   - Configure the bridge to return `not found`, but assert `bridge.sendCallCount == 0` because adoption happens before bridge download.
   - Assert result is done, result `localPath` is the absolute canonical path, `mediaRepo.localPathUpdates` stores `media/contact-A/blob-download-001.jpg`, the file still exists, and no downloading/failed oscillation is recorded.

2. `downloadMedia does not delete pre-existing canonical file when bridge returns not found`
   - Arrange a pre-existing canonical file before calling `downloadMedia`.
   - Force a path where bridge download is attempted, for example by using an invalid-size pre-existing canonical file for adoption but keeping a sentinel canonical file ownership marker, or by explicitly asserting cleanup ownership before adoption is added.
   - Configure bridge response `{'ok': false, 'errorMessage': 'Blob not found'}`.
   - Assert the pre-existing canonical file remains present after the failed attempt and the attachment status is failed only if no valid adoption was possible.
   - If pre-download adoption makes a bridge attempt impossible for valid canonical files, keep this as a regression for invalid/non-adoptable pre-existing files so cleanup ownership remains pinned.

3. `downloadMedia validation failure after bridge success does not delete a pre-existing canonical file`
   - Arrange a pre-existing valid canonical file and make the bridge report success with a mismatched `size`, skip writing, or otherwise create invalid current-attempt output.
   - Assert invalid current-attempt artifacts are cleaned, but the valid pre-existing canonical file is preserved and either adopted or left available for a subsequent adoption pass.
   - If the current bridge writes directly to the canonical output path and overwrites the pre-existing file before validation, stop implementation and replan around staging or relay delete/ack semantics instead of hiding data loss.

4. `downloadMedia promotes staged file only after validation` if a staged path is introduced.
   - Assert the bridge output path is a staging path, the repository never stores that staging path, and the relative canonical path is persisted only after validation/promotion.

Do not add generic simulator or integration tests in Session B; simulator acceptance is listed in the gates section and owned by Session F unless the rollout is explicitly expanded.

## step-by-step implementation plan

1. Re-check `git status --short -- lib/features/conversation/application/download_media_use_case.dart test/features/conversation/application/download_media_use_case_test.dart` and inspect the current diff before editing. Preserve existing dirty changes.
2. Add the failing Session B tests to `test/features/conversation/application/download_media_use_case_test.dart`, using the existing local `_FakeBridge`, `_FakeMediaAttachmentRepo`, and `_FakeMediaFileManager` where possible.
3. Run the direct test file or the new `--plain-name` tests to confirm they fail for the expected current behavior.
4. In `DownloadMediaUseCase`, compute the deterministic absolute and relative canonical paths before the bridge download attempt, after the existing stored-local-path repair check.
5. Add a small local helper scoped to the use case, such as `adoptCanonicalFileIfAvailable`, that:
   - checks the deterministic canonical file exists and is non-empty;
   - validates file length equals `attachment.size` when `attachment.size > 0`;
   - does not require direct `contentHash` unless implementation evidence proves direct hashes are for local plaintext;
   - calls `mediaAttachmentRepo.updateLocalPath(attachment.id, relativePath)`;
   - verifies the committed file still exists via the existing durable-path check or equivalent;
   - returns `attachment.copyWith(localPath: absolutePath, downloadStatus: done)`.
6. Track whether the canonical file existed before this invocation and whether the current invocation created/wrote a file. Cleanup must delete only current-attempt artifacts, not pre-existing canonical files.
7. On bridge `not found`, thrown exceptions, invalid downloaded file, and validation-failure branches, preserve pre-existing canonical files. After marking failed, retry adoption once if preserving a valid canonical file can repair the row.
8. If direct bridge download cannot safely distinguish pre-existing canonical bytes from current-attempt bytes because it writes directly to `absolutePath`, introduce a staging output path for direct downloads in this session or stop and replan. Do not accept a cleanup implementation that can overwrite/delete a pre-existing valid file on validation failure.
9. Keep group-media encrypted companion, group integrity, group MIME, and group quarantine behavior unchanged except for sharing a narrowly safe helper only if it demonstrably preserves current group tests.
10. Run the focused tests and named gates below. If new test files or gate classification docs are changed, run completeness-check and update docs in the same execution session.

## risks and edge cases

- A valid canonical file may exist with no DB `localPath` after app death or DB update failure.
- A pre-existing canonical file can be overwritten if the bridge writes directly to the same `outputPath`; staging may be required to make validation-failure preservation real.
- Existing dirty changes already modified the same use case and test file, so implementation must merge with them rather than reverting.
- Direct `contentHash` is not currently a direct-media plaintext contract; requiring it could incorrectly reject valid direct attachments.
- Attachment status transitions must not oscillate through failed when adoption succeeds before bridge download.
- In-flight dedupe must still ensure overlapping callers share one adoption/download outcome.
- Existing group-media cleanup and quarantine tests must remain green; Session B should not weaken group validation.

## exact tests and gates to run

Direct failing-first tests:

```bash
flutter test test/features/conversation/application/download_media_use_case_test.dart --plain-name "downloadMedia adopts canonical file before bridge download"
flutter test test/features/conversation/application/download_media_use_case_test.dart --plain-name "downloadMedia does not delete pre-existing canonical file when bridge returns not found"
flutter test test/features/conversation/application/download_media_use_case_test.dart --plain-name "downloadMedia validation failure after bridge success does not delete a pre-existing canonical file"
```

After implementation:

```bash
flutter test test/features/conversation/application/download_media_use_case_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh baseline
```

Conditional:

```bash
./scripts/run_test_gates.sh completeness-check
```

Run `completeness-check` only if the execution adds a new test file, edits gate definitions, or changes test inventory classifications. `transport` is not required for this session unless implementation touches bridge, resume, reconnect, transport fallback, local discovery, or app bootstrap.

Simulator-gated source-plan acceptance:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --repo /Users/I560101/Project-Sat/mknoon-2/flutter_app --only integration_test/scripts/run_media_message_journey_e2e.dart
```

This targeted simulator command is required before claiming the overall 1:1 media-unavailable source plan is closed. If it does not exercise canonical orphan adoption after receiver commit loss, Session F must add or extend a 1:1 media simulator scenario before closure. The full 1:1 reliability simulator gate remains Session F scope:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --repo /Users/I560101/Project-Sat/mknoon-2/flutter_app
```

## known-failure interpretation

- Treat the existing dirty worktree as user/previous-session work, not as failures caused by Session B.
- `test-gate-definitions.md` lists historical green revalidations for `baseline`, `1to1`, `transport`, and `completeness-check`; those dates are not current proof.
- If `./scripts/run_test_gates.sh 1to1` or `baseline` fails outside the Session B changed files, capture the first failing command and compare with current dirty worktree before attributing it to Session B.
- If simulator devices are unavailable, do not mark the overall source-plan closure complete. The Session B implementation can still be closed with host evidence, while the source plan remains evidence-gated for Session F.

## done criteria

- All Session B regression tests were added before production changes and failed for the intended reason.
- `DownloadMediaUseCase` adopts a valid deterministic canonical file with `localPath == null` before calling `media:download`.
- Pre-existing canonical files are not deleted by bridge `not found`, exceptions, invalid downloaded file cleanup, or validation-failure cleanup.
- Repository persists the relative canonical path and the returned attachment uses an absolute local path for immediate UI display.
- Existing stored-local-path repair, in-flight dedupe, and group-media policy tests still pass.
- Direct test file passes.
- `./scripts/run_test_gates.sh 1to1` passes, and `baseline` passes for PR-level confidence.
- Coverage ledger:
  - Canonical pre-download adoption: covered by direct regression.
  - Not-found cleanup preservation: covered by direct regression.
  - Validation-failure preservation: covered by direct regression or blocked with evidence that staging/replanning is required.
  - Staged promotion: covered if staging is introduced; otherwise explicitly recorded as not applicable.
- The final execution summary states whether Session F still owns simulator acceptance and cites the targeted simulator command above.

## scope guard

Do not:

- edit relay server, Go node media failover, local discovery, sender upload/fallback, retry UI, duplicate replay, thumbnails, posts, or group-media product policy;
- introduce broad file lifecycle abstractions outside the use case unless a small private helper is not enough;
- change the `MediaAttachmentRepository` interface unless the existing `updateLocalPath` and `updateDownloadStatus` calls cannot express the fix;
- change direct `contentHash` semantics;
- create generic `Test-Flight-Improv/session-*.md` files;
- revert or overwrite unrelated dirty changes.

Overengineering for this session includes a new global media transaction manager, a new relay acknowledgement protocol, or a broad migration of direct downloads to a new subsystem. If the bridge cannot preserve pre-existing canonical bytes without staging, add the smallest staging path needed here or stop and replan.

## accepted differences / intentionally out of scope

- Direct 1:1 media currently does not have the same content-hash contract as group media. This plan accepts size/non-empty validation for direct canonical orphan adoption unless implementation evidence proves a direct plaintext hash exists.
- Final multi-device simulator acceptance is intentionally owned by Session F in the breakdown. Session B must not claim full source-plan closure on host tests alone.
- Group media has stricter encrypted blob hash, MIME, size, and quarantine policy. This session does not attempt parity between direct and group media.
- Relay auto-delete semantics are not changed in this session. This session only ensures receiver-side preservation/adoption when local bytes already exist.

## dependency impact

- Session C can assume receiver canonical adoption/preservation semantics are settled before reasoning about local-WiFi sender fallback durability.
- Session D retry and duplicate replay repair can call `DownloadMediaUseCase` expecting it to repair canonical orphans without deleting them.
- Session F simulator acceptance must prove the overall 1:1 media-unavailable journey after Sessions A-E; if Session B cannot safely preserve canonical files without staging, Session C-D-F planning must be revisited.
- If implementation stops on a bridge direct-write/staging blocker, later sessions should not proceed as though receiver orphan adoption is solved.
