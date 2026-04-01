# 35 - Cancelled Video Upload Still Sends Session Breakdown

## Decomposition artifact updated

- Artifact path: `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`
- Proposal/source doc path: `Test-Flight-Improv/35-cancelled-video-upload-still-sends.md`
- Decomposition date: `2026-03-31`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `1`

## Overall closure bar

This report is closed only when the reopened 1:1 cancel seam is trustworthy again without reopening the broader cancelable-upload program:

- once the user’s cancel action is accepted in the direct conversation video-upload flow, that same attempt no longer falls through into `sendChatMessage(...)`, later retry, or recipient delivery
- the sender-facing outcome for a cancelled video is no longer the ordinary `Failed to upload media. Try again.` path when the in-flight upload future settles after cancel
- direct regression proof covers the late-boundary cases the current repo is missing: video plus caption, cancel during an in-flight upload that later fails, and cancel accepted near the final send boundary
- stable 1:1 and cancelable-upload maintenance docs are refreshed to reflect the reopened regression accurately without overclaiming mid-stream transport abort or inventing a new upload architecture

## Final program acceptance

- Closure verdict: `closed`
- Acceptance date: `2026-03-31`
- What is now closed:
  - `ConversationWired` now re-reads accepted cancel immediately after
    `uploadMediaFn(...)` returns and again after relay tracking stops, so the
    same cancelled video attempt no longer falls through into the ordinary
    upload-failure snackbar or the later `sendChatMessage(...)` path
  - direct wired regressions now cover video plus caption cancel, cancel
    requested before a later upload failure resolves, and explicit final-send
    suppression for the cancelled attempt
  - the accepted repo state passed the two direct
    `conversation_wired_test.dart` cancel regressions, the named `1to1` gate,
    and the `baseline` gate on this multi-device machine via
    `FLUTTER_DEVICE_ID=macos`
  - the stable 1:1 and cancelable-upload closure refs now describe Report `35`
    as a narrow reopen and reclose of the already-landed Report `24` program
- Residual-only items:
  - none
- Still-open items:
  - none
- Reopen only on real regression:
  - if an accepted cancel again falls through into the ordinary
    `Failed to upload media. Try again.` path
  - if an accepted cancel no longer suppresses the later
    `sendChatMessage(...)` / recipient-delivery path for that same attempt
  - if the video-plus-caption or cancel-before-failure-resolves regressions
    stop holding

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/35-cancelled-video-upload-still-sends.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- `Test-Flight-Improv/00-INDEX.md`

Current repo facts that govern the closed seam:

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/core/services/pending_message_retrier.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`

Facts that materially shape the accepted closure state:

- current code already contains the shared 1:1 cancel affordance,
  optimistic-row persistence, failed-row retry/delete controls, and the
  existing `failed` / `upload_failed` terminal model; Report `35` did not
  reopen that broader program
- `conversation_wired.dart` now re-checks accepted cancel immediately after
  `uploadMediaFn(...)` returns and again after `_stopRelayUploadTracking()`
  completes, so late-boundary cancel no longer falls through into the ordinary
  upload-failure snackbar or later `sendChatMessageFn(...)` path
- `conversation_wired_test.dart` now directly proves video plus caption cancel,
  cancel-followed-by-upload-failure, and explicit send suppression for the
  cancelled attempt without needing a wider 1:1 integration harness
- the stable 1:1 closure reference and the older Report `24` breakdown remain
  the broader closure owners; this report is the accepted narrow reopen and
  reclose for one late-boundary 1:1 regression

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Plan file state | Local fallbacks used | Final execution verdict | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Reopen late-boundary 1:1 video cancel semantics and proof` | `implementation-ready` | `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-1-plan.md` | none | `accepted` | `materialized 2026-03-31; reused as the accepted execution contract after the spawned planning step no-progressed` | `planning / execution / closure` | `accepted` | `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`, `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`, `Test-Flight-Improv/00-INDEX.md` | Accepted on `2026-03-31` after landing the late cancel re-checks in `conversation_wired.dart`, the direct video cancel regressions in `conversation_wired_test.dart`, the two targeted widget tests, `./scripts/run_test_gates.sh 1to1`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. The first baseline attempt hit only the local multi-device selection issue and was rerun with an explicit device id. |

## Ordered session breakdown

### Session 1

- Title: Reopen late-boundary 1:1 video cancel semantics and proof
- Session id: `1`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-1-plan.md`
- Exact scope:
  - harden the direct-conversation attachment upload flow so an accepted cancel request cannot fall through into the ordinary upload-failure snackbar path or the later `sendChatMessage(...)` call for that same attempt
  - keep the canceled attempt out of later retry and delivery for the same message row, while staying inside the repo’s existing `failed` / `upload_failed` model unless current code proves a stronger change is unavoidable
  - add direct regressions for the missing cases called out by Report `35`: single video with caption, cancel during an in-flight upload that later resolves as failure, and cancel accepted near the final send boundary
  - add the smallest maintainable proof that the accepted cancel action suppresses recipient-visible delivery, whether through explicit `sendChatMessage(...)` suppression in the wired test seam or a narrowly justified 1:1 integration proof if the direct seam alone is not sufficient
  - refresh the stable maintenance docs for this reopened regression after the code and tests land
- Why it is its own session:
  - this is one coherent reopened seam in the existing 1:1 conversation upload controller
  - it shares one direct regression family, one named-gate contract, and one closure bar
  - the broader cancelable-upload primitives, group parity, and old closure rollout already landed under Report `24`
- Likely code-entry files:
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart` only if the final plan needs a small callback-timing or state-threading adjustment
  - `lib/features/conversation/presentation/widgets/upload_progress_banner.dart` only if the current banner contract needs a minimal affordance-state adjustment
  - `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart` only if the final fix needs a narrow guard beyond the existing terminalization call
- Likely direct tests/regressions:
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/conversation/integration/media_attachment_flow_test.dart` only if a recipient-side proof is required beyond the wired send-suppression seam
  - `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart` only if the landed fix changes retry-state ownership or terminalization behavior
- Likely named gates:
  - `1to1`
  - `baseline`
  - `feed` only if the final implementation leaks into feed-owned 1:1 entry points or shared feed conversation rendering
  - `transport` only if the final implementation changes lifecycle, resume, reconnect, or startup-owned retry wiring rather than staying inside the direct conversation send path
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`
- Dependency on earlier sessions:
  - none

## Why this is not fewer sessions

- This cannot safely collapse to chat-only guidance because the repo’s stable closure refs currently say this seam is closed; a real code-plus-regression session is required before those docs can stay trustworthy.
- The reopened bug is already narrow enough that one doc-scoped implementation session is the minimum safe set: it must own both the cancel-boundary behavior and the proof that accepted cancel suppresses the final send path.

## Why this is not more sessions

- Do not recreate Report `24`’s old multi-session program. The repository, database primitives, shared cancel affordance, failed-row actions, and prior closure docs already exist.
- Splitting “late cancel boundary,” “video-specific regression,” and “closure refresh” into separate sessions would add bookkeeping without independent verification value because they all ride the same 1:1 conversation upload seam and the same `1to1` plus `baseline` gate contract.
- A separate acceptance-only session is not justified unless planning later proves that the smallest trustworthy delivery proof must widen into a heavier integration harness. Current repo evidence does not require that split up front.

## Regression and gate contract

- Use `Test-Flight-Improv/14-regression-test-strategy.md` as the policy reference and `Test-Flight-Improv/test-gate-definitions.md` as the execution source of truth.
- Add the exact direct regression first for the reopened cancel seam before broadening implementation.
- Run the exact direct suites for touched files, with `conversation_wired_test.dart` as the primary required direct suite.
- Run `./scripts/run_test_gates.sh 1to1` because this changes shared 1:1 send/upload/retry behavior.
- Run `./scripts/run_test_gates.sh baseline` because Flutter production code in the conversation flow is expected to change.
- Run `./scripts/run_test_gates.sh feed` only if the final implementation leaks into feed-originated 1:1 entry points or shared feed conversation rendering.
- Run `./scripts/run_test_gates.sh transport` only if the fix stops being local to the 1:1 conversation send path and starts changing lifecycle, resume, reconnect, inbox-drain, or transport fallback wiring.

## Matrix update contract

- Reuse the existing stable maintenance docs instead of inventing a new cancel-upload matrix doc.
- Session `1` owns the closure refresh in its downstream closure-audit pass.
- The stable 1:1 closure reference should describe the reopened seam honestly after the fix lands.
- The old Report `24` closure-owner artifact should be updated to note that Report `35` was a real narrow regression reopen rather than a new broad cancelable-upload program.
- `00-INDEX.md` should be refreshed so the new report and its doc-scoped breakdown are discoverable inside the existing maintenance map.

## Structural blockers remaining

- none
- Mergeable sessions: none
- Required splits: none

## Accepted differences intentionally left unchanged

- no mid-stream transport abort promise:
  already-started upload transport work may still settle internally; the user-facing closure bar is that cancel no longer causes final send, later retry, or recipient delivery
- no new `cancelled` status model by default:
  stay inside the existing `failed` plus attachment `upload_failed` contract unless current code proves a stronger state change is unavoidable
- no group or announcement reopen:
  this report is only for the reopened 1:1 video cancel seam
- no named-gate definition change by default:
  use the existing `1to1` and `baseline` gates unless the final implementation materially widens scope

## Exact docs/files used as evidence

- `Test-Flight-Improv/35-cancelled-video-upload-still-sends.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- `Test-Flight-Improv/00-INDEX.md`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/core/services/pending_message_retrier.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The reopened bug is isolated to an existing 1:1 maintenance seam with known code-entry files and known gate ownership.
- One doc-scoped session is enough to leave the repo in a meaningful verified state: fix the late cancel behavior, prove the final send is suppressed, rerun the right gates, then refresh the stable closure docs.
- There are no unresolved structural blockers, missing ownership questions, or missing maintenance docs that require another decomposition pass before planning.
