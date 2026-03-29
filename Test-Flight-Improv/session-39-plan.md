# Session 39 Plan — Shared Attachment Budget And Overflow UX Across In-App And Hydrated Entry Points

## Real Scope

What changes in this session:

- add one shared pending-media budget contract for 1:1 and group composers
- enforce the settled general-media cap across:
  - in-app gallery/camera attachment flows in `ConversationWired`
  - in-app gallery/camera attachment flows in `GroupConversationWired`
  - hydrated `initialAttachments` / route-entry attachment paths used by share
    and feed launchers
- preserve the separate `10`-attachment count limit while adding the new
  cumulative byte budget
- add the attach-time overflow UX with `Compress` and `Cancel` behavior for
  candidate attachments that would push the pending selection over the budget
- prevent share/feed-hydrated attachments from bypassing the same budget logic
  by threading the needed pending-media metadata into the conversation/group
  hydration seam

What does not change in this session:

- no relay/local transport cap changes; Session `38` already owns that
- no upload progress banner, leave guard, or wake-lock work; that remains
  Session `40`
- no receiver download progress or background upload architecture
- no change to the in-app voice recorder contract
- no stable closure-doc refresh; that remains Session `41`

---

## Closure Bar

This session is sufficient when all of the following are true:

- 1:1 and group composers reject pending-attachment selections that would put
  the message over the general-media budget
- the overflow behavior is deterministic for:
  - a single oversized candidate
  - cumulative overflow across multiple pending attachments
- selecting `Compress` recomputes only the new candidate attachments with the
  compressed quality path and rechecks the budget before attach
- selecting `Cancel` leaves the existing pending attachments intact and does not
  attach the overflowing candidates
- hydrated attachments entering through share/feed route launchers use the same
  budget math instead of bypassing it
- compressed-quality flows budget-check the processed outputs
- original-quality flows budget-check the preserved raw-size budget metadata for
  the newly selected items
- the direct widget/integration tests prove 1:1, groups, and share/feed route
  entry behavior without requiring giant files

---

## Source Of Truth

Authoritative sources for this session:

- proposal and breakdown:
  - `Test-Flight-Improv/22-media-transfer-size-limit.md`
  - `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- regression/gate policy:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- current composer and hydration behavior:
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/share/presentation/screens/share_target_picker_wired.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/core/media/image_processor.dart`
- current tests:
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/share/presentation/share_target_picker_wired_test.dart`
  - `test/features/share/integration/share_to_contact_smoke_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/core/media/image_processor_test.dart`

Conflict rules:

- landed code from Session `38` fixes the transport cap and wins over older
  prose
- current screen code and widget tests beat stale product wording when they
  disagree about existing processing behavior
- `test-gate-definitions.md` and `scripts/run_test_gates.sh` win on gate scope

---

## Session Classification

`implementation-ready`

Why:

- the shared-path gap is concrete in current code:
  - in-app attachment paths process media, then append without any size-budget
    enforcement
  - hydrated `initialAttachments` are mapped directly into pending state and
    therefore bypass any future attach-time budget logic unless the hydration
    seam changes too
- the exact ownership boundary is now clear after Session `38`

---

## Exact Problem Statement

The current pending-media flow has two repo-visible inconsistencies:

1. in-app attach flows process selected media and only enforce the count limit
   (`10`), not the new general-media byte budget
2. hydrated route-entry attachments from share/feed arrive through
   `initialAttachments` and are inserted directly into pending state, so they
   would remain a bypass even if the in-app pick handlers gained budget checks

There is also one subtle budgeting requirement that current code does not carry
as explicit data:

- compressed-quality flows should budget-check the processed files
- original-quality flows should budget-check the preserved raw-size input for
  the selected candidates, even if current processing still strips metadata or
  uses highest-quality transcode behavior later

What must improve:

- pending media needs an explicit budget-bytes value that can survive route
  hydration
- the overflow UX needs to operate on candidate attachments consistently in both
  1:1 and group composers
- share/feed launchers need to pass the same pending-media metadata so hydrated
  entries do not bypass the contract

What must stay unchanged:

- voice recorder stays out of this contract
- attachment count limit remains `10`
- no upload-state UI changes yet

---

## Files And Repos To Inspect Next

Production files:

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/share/presentation/screens/share_target_picker_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- one small shared helper/model file under `lib/core/media/` or
  `lib/features/conversation/presentation/` for pending-media budget metadata
- `lib/core/media/image_processor.dart`

Primary tests:

- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/share/presentation/share_target_picker_wired_test.dart`
- `test/features/share/integration/share_to_contact_smoke_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart` if the route
  launchers are touched
- one direct helper/unit test under `test/core/media/` if a shared pending-media
  budget helper is introduced

Docs to update later, not in this session:

- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `UI-10-Media/media-client-spec.md`

---

## Existing Tests Covering This Area

Already covered:

- conversation and group screens already prove:
  - initial shared text hydration
  - initial attachment preview hydration
  - media processing progress behavior
  - upload failure restores composer state
- share picker tests already prove:
  - target selection routes into conversation/group screens
  - shared files are processed once on target selection
- share smoke tests already prove:
  - shared files become pending attachments in the destination composer

Missing:

- a deterministic budget-overflow regression for 1:1 composer attach flows
- a deterministic budget-overflow regression for group composer attach flows
- proof that `initialAttachments` hydration uses the same budget contract and is
  not a bypass
- proof that the candidate budget bytes differ between compressed and original
  quality handling
- proof that `Cancel` preserves existing pending attachments while rejecting the
  new overflowing ones

---

## Regression / Tests To Add First

Add these tests first:

1. `test/features/conversation/presentation/screens/conversation_wired_test.dart`
   - single-file overflow on attach shows the warning
   - `Cancel` leaves existing pending attachments intact
   - `Compress` accepts the candidate when compressed output fits
   - hydrated initial attachments over the limit do not bypass the warning

2. `test/features/groups/presentation/group_conversation_wired_test.dart`
   - same attach/hydration overflow proof for group composer

3. `test/features/share/presentation/share_target_picker_wired_test.dart`
   - share route passes pending-media budget metadata through to the destination
     conversation/group screen so hydration can apply the same contract

4. `test/core/media/` direct helper test if a shared pending-media budget helper
   or model is introduced
   - original-quality candidate keeps raw-size budget bytes
   - compressed-quality candidate uses processed-size budget bytes

Do not create large files; use a test-only budget override so small fixtures can
hit the same branch conditions.

---

## Step-By-Step Implementation Plan

1. Introduce a small shared pending-media model/helper that can carry:
   - attached file path
   - budget bytes used for cumulative-limit math
   - optional width/height/duration metadata
2. Add a test-only configurable attachment budget limit to
   `ConversationWired` and `GroupConversationWired`, defaulting to `5 GB`.
3. Refactor in-app pick handlers in `ConversationWired` to:
   - prepare candidate pending-media entries with the correct budget bytes
   - run shared overflow resolution before appending to pending state
   - support `Compress` and `Cancel` on overflow
4. Apply the same logic in `GroupConversationWired`.
5. Thread the pending-media model through share target selection so hydrated
   conversation/group entry uses the same budget metadata instead of a bare
   `File` list.
6. If needed, thread the same metadata through feed launchers for route-entry
   attachment hydration; if that happens, run the feed gate.
7. Keep `initialAttachments` compatibility where needed for existing callers and
   tests, but make the hydrated path prefer the richer pending-media metadata
   when present.
8. Run direct tests, then required named gates.

Stop rule inside implementation:

- if preserving raw-size budget metadata through hydrated entry points cannot be
  done without touching feed/share launchers, accept those narrow launcher
  changes and run the additional gate rather than inventing a second-class
  hydration contract
- do not widen into upload progress or bridge changes

---

## Risks And Edge Cases

- original-quality budgeting can silently drift back to processed-size math if
  the raw-size budget bytes are not preserved alongside the processed file
- hydrated share/feed attachments can stay a bypass if the richer pending-media
  metadata is dropped during navigation
- compressing only the overflowing candidates must not mutate or replace the
  already-pending attachments
- non-processable files such as audio/PDF may still be over budget after a
  `Compress` attempt; the UX must fail honestly instead of pretending the attach
  succeeded
- route-hydration dialogs triggered during screen init need to run after the
  first frame so they do not race widget build

---

## Exact Tests And Gates To Run

Direct tests:

- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/share/presentation/share_target_picker_wired_test.dart`
- `flutter test test/features/share/integration/share_to_contact_smoke_test.dart`
- direct helper/unit test under `test/core/media/` if added
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  only if feed launcher code is touched

Required named gates:

- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh feed`
  only if feed launcher code is touched

Not required by default:

- `./scripts/run_test_gates.sh transport`
- `./scripts/run_test_gates.sh completeness-check`
  - only if a new test file needs explicit gate classification

---

## Known-Failure Interpretation

- no current target-area known failure is documented in the sources read for
  this session
- missing-plugin warnings in unrelated notification/profile-picture helpers
  inside existing gate runs are not Session `39` blockers when the tests still
  pass
- treat any red gate as a blocker only if it is new or widened by the pending
  media budget changes

---

## Done Criteria

- 1:1 and group attach flows enforce the shared general-media budget
- hydrated route-entry attachments no longer bypass the same budget logic
- overflow UX supports `Compress` and `Cancel`
- compressed and original quality paths use the intended budget inputs
- direct regressions pass
- required named gates pass

---

## Scope Guard

- do not change the transport cap, relay retention, or voice-message limit
- do not add upload-progress UI, wake locks, or leave-confirmation behavior
- do not redesign image/video processing behavior beyond what is needed to carry
  correct budget metadata
- do not create new closure docs in this session

---

## Accepted Differences / Intentionally Out Of Scope

- voice messages remain outside the shared attachment-budget contract
- receiver-side download UX remains unchanged
- if a non-processable file is still over budget after `Compress`, the session
  can show an honest failure message instead of inventing a special audio/PDF
  compressor
- stale media specs remain deferred to Session `41`

---

## Dependency Impact

- Session `40` depends on this session to settle the final pending-attachment
  ingress contract before it layers upload-state UI on top of the same screens
- if this session changes feed launcher code, Session `41` must record that the
  `feed` gate became part of the acceptance evidence for this rollout
- if this session blocks, Session `40` should not continue because it revisits
  the same conversation/group screen seams
