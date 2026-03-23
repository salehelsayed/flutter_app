# Message Delivery Reliability Review TODO

This is the minimum follow-up still needed to make the **current** plan
sufficient for the `1:1` send-then-lock bug.

Scope:
- In scope: `1:1` text, media, and voice
- Out of scope: group sending and group durability

Current verdict:
- The plan is **much closer** than before.
- The lifecycle/retrier design is now in good shape.
- The real caller coverage for background protection is now in good shape.
- The remaining blockers are mostly concentrated in:
  - Part G media/voice recovery consistency
  - one inbox-handoff edge case in Section 4
  - final acceptance proof quality

## P0 blockers

- Make the voice relay fallback explicitly obey the Stable-ID contract.
  - The plan now fixes stable IDs in the main media/local-WiFi flows, but it
    still does not clearly thread the same pre-generated voice attachment ID
    through the relay fallback path via `sendVoiceMessage()` ->
    `uploadMedia(blobId:)`.
  - What I expect to see:
    - `sendVoiceMessage()` explicitly accepts/forwards the stable attachment ID
      into `uploadMedia`
    - [`send_voice_message_use_case.dart`](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/application/send_voice_message_use_case.dart)
      is named in the affected-files list for this contract
    - the voice relay path is no longer a hidden exception that can recreate
      placeholder/orphan attachment rows

- Remove the old conflicting `retryIncompleteUploads` behavior from the plan.
  - The document still contains earlier Part G blocks/tests that encode the
    old behavior where the first upload failure becomes terminal and all rows
    are marked `upload_failed`.
  - Later sections correctly introduce path resolution, transient retryability,
    stable IDs, and better recovery behavior, but the plan still has two
    competing implementations of the same use case.
  - What I expect to see:
    - one canonical `retryIncompleteUploads` design in the document
    - transient upload failure remains retryable
    - any superseded earlier tests/snippets are removed or clearly marked
      obsolete

- Add an idempotent inbox-handoff rule for the “inbox accepted, local save not
  yet updated” crash window.
  - Current Section 4 is much better because it keeps direct-first behavior and
    avoids unconditional optimistic inbox store.
  - But the plan still needs one explicit rule for this edge case:
    - relay inbox accepted
    - app dies before local row is updated to reflect that
    - resume/retry replays the same wire envelope and can hit inbox again
  - What I expect to see:
    - a concrete guard in retry logic or persisted state rule that makes inbox
      handoff idempotent enough for this path
    - not just “skip if `transport == 'inbox'`”, because that state may not
      have been saved yet before the crash

- Replace the remaining synthetic media/voice acceptance proof with the real
  recovery path.
  - Text acceptance is now much better.
  - Media and voice still stop short of proving the exact planned path because
    the B.1 sketches still resume through `retryFailedMessages()` with key media
    plumbing commented out, instead of clearly driving `retryIncompleteUploads()`
    with real `upload_pending` rows as the acceptance proof.
  - What I expect to see:
    - the media acceptance proof explicitly runs the `upload_pending` ->
      `retryIncompleteUploads()` path
    - the voice acceptance proof explicitly runs the same real recovery path
    - no commented-out “production prerequisite” parameters in the main
      acceptance snippets

## P1 required corrections

- Prove the local voice/WiFi branch strongly enough for `1:1` coverage.
  - The implementation plan now covers the branch much better than before.
  - The remaining problem is proof strength: the main Section 6 acceptance path
    still demonstrates relay re-upload recovery, while local WiFi is mostly
    left to a separate unit test / smoke scenario.
  - For a sufficient plan, this can be handled by:
    - one explicit end-to-end acceptance or smoke row for interrupted
      `sendLocalMedia()` in `1:1` voice, or
    - one clear statement that the relay fallback proof is the acceptance bar
      and the local-WiFi branch is covered by dedicated focused tests

- Clean up stale Section 3 summary wording.
  - The detailed Section 3 design is now correct: presentation-layer ownership,
    `_onSend`, `_onVoiceRecordingStopped`, `_onInlineSend`, and no bg-task work
    inside `sendVoiceMessage()` / `sendChatMessage()`.
  - The top summary text still says the old thing.
  - What I expect to see:
    - summary and section-map wording updated to match the final canonical
      ownership model

- Clean up stale Section 4 wording/examples left over from the older plan.
  - The plan title and later explanation are now direct-first, but a few stale
    lines still mention optimistic inbox-store possibilities in examples/smoke.
  - What I expect to see:
    - `IF-2` and related wording updated so the final document never implies
      unconditional inbox-first is still the chosen contract

- Decide whether Section 5.4 is local-notification quality only, or true
  background-push body correctness.
  - If the requirement is only “recipient gets a notification,” the current
    generic server push body is acceptable and Section 5.4 should stay scoped to
    local/in-app notification quality.
  - If the requirement is specifically “backgrounded recipient sees `Photo` /
    `Voice message` in the system push,” then the plan still needs relay/server
    push-body work too.
  - What I expect to see:
    - one explicit scope decision
    - matching acceptance assertions

- Update stale relay payload tests for `sender_id`.
  - Flutter-side stale tests are already covered by the plan.
  - The Go relay tests that still assert `from` also need to be updated if this
    section remains in scope.

- Keep group noise out of the final sufficiency readout.
  - Group notification rows and group parity notes should not be used as part
    of the “is this `1:1` plan sufficient?” decision.

## Sufficient-plan bar

If you fix the `P0` items above, I would call this a **sufficient**
implementation plan for the `1:1` bug.

As written today, I would still answer **not yet sufficient**, mainly because:
- the voice relay fallback is not explicitly stable-ID-safe in the plan
- Part G still contains conflicting old vs new recovery behavior
- the inbox-handoff edge case is not fully specified
- the final media/voice acceptance proof still does not cleanly drive the exact
  planned recovery path
