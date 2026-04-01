# Session 1 Plan — Reopen Late-Boundary 1:1 Video Cancel Semantics And Proof

## real scope

What changes in this session:

- harden the direct 1:1 attachment-upload send flow so an accepted cancel
  request cannot fall through into the ordinary upload-failure snackbar path
  or the later `sendChatMessage(...)` call for that same attempt
- keep the fix inside the existing 1:1 conversation seam:
  - `ConversationWired` owns the active upload batch state
  - the repo continues to use the existing `failed` /
    `upload_failed` terminal model unless current code proves a stronger state
    change is necessary
- add direct regressions that pin the reopened Report `35` cases:
  - single video with caption
  - cancel during an in-flight upload that later resolves as failure
  - cancel accepted near the final send boundary so the final
    `sendChatMessage(...)` is still suppressed
- add the smallest trustworthy proof that accepted cancel prevents
  recipient-visible delivery:
  prefer an explicit send-suppression seam in the direct wired tests and only
  widen into a narrow 1:1 integration proof if the direct seam cannot prove it
- refresh the stable maintenance docs after the code and tests land:
  - `19-1to1-message-reliability-closure-reference.md`
  - `24-cancel-media-upload-session-breakdown.md`
  - `00-INDEX.md`
  - `35-cancelled-video-upload-still-sends-session-breakdown.md`

What does not change in this session:

- no group or announcement reopen
- no new upload architecture or mid-stream transport-abort claim
- no new message status such as `cancelled` by default
- no broad retry/lifecycle/startup redesign unless direct code evidence forces
  a tiny local guard outside `ConversationWired`
- no feed-owned 1:1 send-surface work unless the direct fix unexpectedly leaks
  there
- no gate-definition rewrite

## closure bar

Session `1` is sufficient when all of the following are true:

- once the user taps cancel on an active direct-message video upload and that
  cancel is accepted, that same attempt does not proceed into the final
  `sendChatMessage(...)` path
- if the in-flight upload later resolves as failure after cancel was already
  requested, the sender sees the cancel outcome rather than the ordinary
  `Failed to upload media. Try again.` path
- the canceled attempt does not remain retryable or later deliverable for that
  same message row
- direct regressions cover video plus caption and the late-boundary cancel
  cases that Report `35` identified as missing
- the required named gates still pass and the stable maintenance docs no longer
  overstate the reopened seam

## source of truth

Authoritative sources for this session:

- controlling scope/order artifact:
  `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`
- proposal/spec:
  `Test-Flight-Improv/35-cancelled-video-upload-still-sends.md`
- regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- named gate policy:
  `Test-Flight-Improv/test-gate-definitions.md`
- stable maintenance docs to refresh:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
  `Test-Flight-Improv/00-INDEX.md`
- current production seam:
  `lib/features/conversation/presentation/screens/conversation_wired.dart`
  `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
  `lib/features/conversation/presentation/screens/conversation_screen.dart`
  `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- current direct proofs:
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  `test/features/conversation/integration/media_attachment_flow_test.dart`
  `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`

Conflict rules:

- the session breakdown controls scope, order, and closure ownership unless
  current repo evidence proves it stale
- current code and tests beat stale closure prose
- `test-gate-definitions.md` defines the named gates, but the script remains
  the execution source of truth if doc and script disagree

Current repo evidence that governs this plan:

- `ConversationWired` still checks cancel inside the upload loop, but the later
  `sendChatMessageFn(...)` call remains after that loop and must stay
  suppressed when cancel was accepted late
- the current `uploadMediaFn(...) == null` branch still restores the composer
  with the ordinary upload-failure snackbar, which conflicts with Report `35`
  when cancel was already accepted
- the existing sender-side cancel widget test uses an image fixture and a
  successful upload completion; it does not prove the reopened video-specific
  or cancel-then-failure seams

## session classification

`implementation-ready`

## exact problem statement

Report `35` is a narrow reopen of an already-landed 1:1 cancel seam.
The current repo already has:

- the shared upload banner cancel affordance
- optimistic row persistence
- same-row failed-media retry/delete controls
- the existing `failed` / `upload_failed` terminal model

But the current repo does not yet prove or fully enforce the user contract for
late-boundary video cancel:

- a cancel accepted during an in-flight video upload can still fall through to
  the ordinary upload-failure path if the upload future settles as failure
- current proof does not explicitly show that accepted cancel suppresses the
  later final send for that attempt
- current proof does not cover the user-reported video-plus-caption case

User-visible behavior that must improve:

- cancel on an active video upload behaves like a final user rejection for that
  attempt
- the sender does not get the ordinary upload-failure UX after cancel was
  already accepted
- the recipient does not receive the canceled attempt

Behavior that must stay unchanged unless current code makes it impossible:

- no mid-stream transport abort promise
- no new `cancelled` status model
- no group/announcement work
- no broader retry/lifecycle architecture churn

## files and repos to inspect next

Production files:

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`

Direct tests:

- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`

Closure docs:

- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/24-cancel-media-upload-session-breakdown.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/35-cancelled-video-upload-still-sends-session-breakdown.md`

## existing tests covering this area

Already covered today:

- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  already proves sender-side cancel for a simple attachment path, same-row
  failed-media retry/delete controls, and send-failure composer restoration
- `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  already proves late-send suppression for deleted rows in incomplete-upload
  recovery
- `test/features/conversation/integration/media_attachment_flow_test.dart`
  already covers 1:1 media send/receive persistence seams that can support a
  narrow recipient-side proof if needed

Missing today:

- no direct test that uses a video fixture plus caption for cancel
- no direct test for cancel requested before an upload future later resolves as
  failure
- no direct test that explicitly captures and suppresses the final
  `sendChatMessage(...)` call when cancel lands at the last safe boundary
- no proof yet that the reopened seam stays honest in the stable closure docs

## regression/tests to add first

Add these regressions before or alongside the first production edits:

- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  should pin the late-boundary cancel path:
  - cancel during a tracked video upload with caption restores the composer
  - accepted cancel followed by a later upload failure still surfaces the
    cancel outcome rather than the ordinary upload-failure snackbar
  - accepted cancel suppresses the later final `sendChatMessage(...)` call even
    when it lands near the only upload or last upload in the batch
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  should capture the smallest trustworthy send-suppression proof for the
  canceled attempt
- use `test/features/conversation/integration/media_attachment_flow_test.dart`
  only if a direct wired send-suppression seam is not sufficient to prove the
  recipient outcome honestly
- update `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`
  only if the landed fix changes retry-state ownership or needs a new narrow
  guard there

## implementation sketch

Keep implementation bounded to the smallest seam that satisfies Report `35`:

1. Re-read the active cancel state at every post-upload and pre-send boundary
   that can still fall through into message send or ordinary failure handling.
2. Ensure the `uploadMediaFn(...) == null` path respects an already-accepted
   cancel request before surfacing the ordinary upload-failure snackbar.
3. Keep the canceled row inside the current `failed` / `upload_failed`
   contract unless direct code evidence proves that contract cannot satisfy the
   reopened bug.
4. Prefer explicit local seam proof over a heavier integration addition.

## named gates

Required:

- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh baseline`

Conditional:

- `./scripts/run_test_gates.sh feed` only if the landed fix leaks into
  feed-owned 1:1 entry points or shared feed rendering
- `./scripts/run_test_gates.sh transport` only if the landed fix changes
  lifecycle, resume, reconnect, inbox-drain, or transport fallback wiring

## done criteria

- code changes are limited to the reopened 1:1 cancel seam or a tiny adjacent
  retry guard justified by current evidence
- direct regressions for the reopened video cancel cases are present and pass
- the required named gates pass
- the stable closure docs and the current breakdown ledger are refreshed to
  reflect the reopened regression honestly
- no new broad cancel-upload program is created

## scope guard

Stop and re-evaluate if any of these become necessary:

- reopening group or announcement upload behavior
- inventing a new `cancelled` status model
- changing startup/lifecycle/transport architecture rather than fixing the
  local late-boundary 1:1 seam
- rewriting retry ownership across the whole messaging stack
- widening into unrelated video thumbnail/playback bugs
