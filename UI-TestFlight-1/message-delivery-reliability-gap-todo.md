# Message Delivery Reliability — Gap TODO Addendum

**Purpose:** This document captures the concrete gaps discovered while reviewing the updated implementation plan in [message-delivery-reliability-tdd-plan.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/UI-TestFlight-1/message-delivery-reliability-tdd-plan.md), and defines the minimum additional work required to make that plan sufficient for the `1:1` send-then-lock bug.

**Primary bug being fixed:** A user writes a `1:1` message, taps Send, and immediately locks/backgrounds the device. The send does not complete reliably, the sender can be left with a permanent `sending` row, the recipient may not receive the message, and the recipient may receive no notification.

**Scope of this addendum:**
- In scope: `1:1` text, media, and voice messages
- Out of scope: group-send durability / group-send retry semantics

**Status:** The current plan is directionally correct, but not yet sufficient as written. This addendum defines the missing TODOs and the exact outcomes expected from each.

---

## Addendum Overview

### Gap Map

| Gap | What Is Missing | Why It Matters |
|---|---|---|
| **Gap 1** — Background Task Reality | Section 3 is written as if it were Swift-only, but the real fix spans Dart call sites + Dart bridge + Swift bridge | Without the Dart-side wiring, iOS background execution cannot protect the actual send window |
| **Gap 2** — Already-Online / Paused Lifecycle Recovery | The current plan does not fully close the `already online` retry hole or the `paused` transition gap | The app can still leave messages stranded until an arbitrary later state change |
| **Gap 3** — Unsafe `upload_pending` Row Design | Placeholder attachment rows can survive after successful upload and be re-read / re-retried | Media and voice recovery can duplicate attachments or re-upload work unnecessarily |
| **Gap 4** — Media/Voice Retry Semantics | Recovery upload failure is treated too terminally; relative paths are not safely resolved; active long uploads can be misclassified as abandoned | `1:1` media and voice remain unreliable even if text is improved |
| **Gap 5** — Pre-Upload File Durability | The plan persists metadata before upload, but not the actual file into durable managed storage | Voice and media pre-upload recovery is only best-effort, not reliable |
| **Gap 6** — Inbox-First Side Effects | Section 4 overstates what early inbox store guarantees and does not account for push/dedup side effects | A naïve “always store in inbox first” change can create duplicate push/delivery behavior |
| **Gap 7** — UI Status Refresh | The live conversation screen ignores `sending -> failed` repo changes | Recovery can work in the DB while the sender still sees a permanent spinner |
| **Gap 8** — Acceptance Proof Quality | The current test plan simulates recovery in places where it must instead prove the real path | The plan can appear green without actually fixing the bug |

---

## Gap 1: Section 3 Must Be a Dart + Swift Change

### Problem statement

Section 3 currently reads as if the iOS background-task fix is largely a Swift concern. That is not how the actual runtime path works.

Today:
- there are no `bg:begin` / `bg:end` bridge commands in the iOS bridge
- there are no corresponding Dart bridge helpers
- the live send call sites in the conversation UI and voice flow do not bracket the vulnerable send window with a background assertion

This means the plan's current Section 3 framing is too narrow. The actual fix surface is:
- iOS bridge
- Dart bridge client / helper surface
- `conversation_wired.dart` send path
- `sendVoiceMessage` call path
- any local-transfer voice branch that still needs background protection

### TODO

- Rewrite Section 3 to explicitly state: **this is a Dart + Swift bridge fix**, not a Swift-only slice.
- Add bridge commands for background task begin/end in:
  - [GoBridge.swift](/Users/I560101/Project-Sat/mknoon-2/flutter_app/ios/Runner/GoBridge.swift)
  - the Dart bridge surface in [go_bridge_client.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/bridge/go_bridge_client.dart)
- Wrap the real 1:1 send windows in:
  - [conversation_wired.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/screens/conversation_wired.dart)
  - [send_voice_message_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/application/send_voice_message_use_case.dart)
- Cover both:
  - upload/relay path
  - local voice transfer path before relay fallback
- Update the red-phase tests so they do not depend on calling `private` Swift methods directly.

### What I expect to see

- A testable public or internal test hook for background-task begin/end behavior
- Dart-side send call sites acquire a background assertion before entering the vulnerable upload / send / inbox handoff window
- The background assertion is ended in `finally`
- Section 3 no longer claims to be “pure Swift” or “standalone”

### Acceptance evidence

- Unit or platform tests proving `bg:begin` and `bg:end` are callable through the real bridge path
- One integration-style test proving the send path brackets work with background assertion begin/end ordering
- The updated Section 3 text names the Dart files and Swift files explicitly

---

## Gap 2: Close the Already-Online Retry Hole and Add a Real Paused Handler

### Problem statement

Two recovery gaps still exist in the live app:

1. `PendingMessageRetrier.start()` only schedules work on an offline -> online transition. If the app is already online when the retrier starts, there is no immediate sweep. See [pending_message_retrier.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/services/pending_message_retrier.dart).

2. The app currently reacts only to `resumed` in [main.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/main.dart#L1480). There is no `paused` path that proactively transitions in-flight work into a recoverable state.

The current plan mentions these ideas, but the gap review found that the practical bar is higher: the initial-online case and paused-state case both need to be treated as first-class, not incidental.

### TODO

- Update Section 1 / Section 2 to explicitly require:
  - an **initial retrier sweep** when the node is already online
  - a **real `AppLifecycleState.paused` handler** in [main.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/main.dart)
- Wire message retry callbacks into [handle_app_resumed.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/lifecycle/handle_app_resumed.dart), not just post-related callbacks
- Use conditional status transitions for paused handling:
  - only move `sending -> failed` if the row is still `sending`
  - do not overwrite a concurrently advanced `sent` / `delivered`

### What I expect to see

- `PendingMessageRetrier.start()` triggers a retry sweep immediately when the app is already online
- `handleAppResumed()` has message retry hooks, not just post retry hooks
- `didChangeAppLifecycleState` handles `paused`
- pause handling does only local DB / state work and is safe against racing successful sends

### Acceptance evidence

- A unit test for the “already online at start” case
- A lifecycle test that proves `paused` transitions `sending -> failed` only when the row has not already advanced
- A resume test that proves retry callbacks are invoked for messages even when no offline -> online transition occurs

---

## Gap 3: The `upload_pending` Placeholder Row Design Must Be Fixed Before Implementation

### Problem statement

The current plan treats `upload_pending` placeholder rows as mostly harmless temporary records. That is too weak for the current repository contract.

Current behavior:
- attachment upserts replace by attachment `id`, not by `message_id`
- `uploadMedia()` generates a new blob `id`
- attachment reads return all rows for a `message_id` with no special filtering

That means a placeholder row can remain attached to the same message even after the real uploaded attachment row exists. The consequences are:
- duplicate attachment rows on reload
- future recovery sweeps can still see the stale placeholder
- already-uploaded failed messages can be re-uploaded again instead of replayed

### TODO

- Update Parts F/G to define one of these contracts explicitly:
  - **stable attachment ID contract**: the optimistic row's id becomes the real uploaded row id
  - **replace-in-place contract**: the optimistic row is updated after upload
  - **delete-placeholder contract**: placeholder rows are removed immediately once the real uploaded row exists
- Do not leave placeholder cleanup as a later follow-up task
- Ensure `retryIncompleteUploads()` excludes messages that already have:
  - replayable `wireEnvelope`
  - completed uploaded attachment rows that should use replay, not re-upload

### What I expect to see

- Section text that states exactly how a pre-upload row becomes the post-upload row
- No message can load both a stale placeholder row and the real uploaded row after success
- Retry code distinguishes:
  - pre-upload interrupted
  - post-upload failed send

### Acceptance evidence

- A repository / DB test proving successful upload does not leave duplicate attachment rows for one message
- A retry test proving a post-upload failed message is replayed, not re-uploaded
- A load-conversation style test proving only the real attachment row remains visible after successful upload

---

## Gap 4: Media and Voice Retry Semantics Need Stronger Contracts

### Problem statement

The review found three distinct issues in the current media/voice recovery story:

1. The first recovery upload failure is treated too terminally.
2. Relative stored paths are not safely resolved before filesystem access.
3. The `30s` stuck-sending heuristic can misclassify active long-running uploads as abandoned because the app marks rows `sending` before upload even starts.

Text recovery can survive with a simpler contract. Media and voice cannot.

### TODO

- Update Parts F/G so transient re-upload failure remains retryable
  - do not convert the first failed re-upload into a terminal dead-end state
  - define a state that remains eligible for later retry
- Resolve persisted paths through [MediaFileManager](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/media/media_file_manager.dart) before checking file existence
- Refine the stale-work heuristic for media/voice
  - do not rely only on `message.timestamp < 30s`
  - use attachment-side state or a separate signal that distinguishes active upload from abandoned work

### What I expect to see

- A retry path that tolerates transient bridge/relay failures and retries later
- Retry code using resolved absolute paths, not raw DB strings
- Media/voice recovery logic does not misclassify a legitimate long upload as stuck simply because it crossed the threshold

### Acceptance evidence

- A test where the first re-upload fails and the second retry succeeds automatically later
- A test proving relative `localPath` rows are resolved and replayed correctly
- A test proving a long-running active upload is not incorrectly flipped into abandoned recovery state

---

## Gap 5: Pre-Upload File Durability Must Match the Claim

### Problem statement

The current plan claims automatic pre-upload recovery for media and especially voice. The review found that this is overstated under current code behavior.

Today:
- the optimistic row can be written before upload begins
- metadata can be persisted
- but the actual file is not copied into managed durable storage until upload succeeds

This is especially weak for voice:
- voice recordings are created in temp storage
- if the app is killed before upload completes and the temp file disappears, the metadata alone is not enough

### TODO

- Decide which contract the plan wants:
  - **strong contract**: copy pre-upload files into managed storage before the vulnerable window
  - **best-effort contract**: explicitly state that pre-upload recovery works only if the local file still exists
- If choosing the strong contract:
  - add the file copy into managed storage before upload begins
  - use that managed path for recovery
- If choosing best-effort:
  - weaken the plan language so it does not promise “user does NOT need to re-record” as a general guarantee

### What I expect to see

- The written claim in the plan matches the actual persistence behavior
- For voice, either:
  - the file is durably copied before upload starts, or
  - the plan clearly says recovery is best-effort if the file survives

### Acceptance evidence

- A test showing a pre-upload file survives app kill because it was copied to managed storage before upload
or
- explicit plan language and tests that treat missing-file recovery as an expected best-effort limitation

---

## Gap 6: Inbox-First Must Account for Push and Dedupe Side Effects

### Problem statement

Section 4 currently overstates what “inbox-first” guarantees.

Two important realities:
- early inbox store is still a network RPC, so it reduces the post-serialization gap but does not guarantee relay durability until the RPC completes
- on the relay, inbox store also triggers push send

That means a naïve “always store in inbox first” change can create:
- duplicate push notifications
- duplicate inbox copies when direct delivery also succeeds
- incorrect claims in the plan about what failure window is fully closed

### TODO

- Rewrite Section 4 language to say:
  - inbox-first **reduces** the post-serialization gap
  - it does **not fully close it** until the inbox RPC returns successfully
- Define the push/dedup contract for unconditional inbox store
  - suppress push for inbox-first writes that are merely hedging direct delivery
  - or add a dedupe / cancel path
  - or ensure the recipient-side stack dedupes cleanly and does not notify twice
- Expand Section 5 ops note:
  - Redis is not only token durability
  - if inbox-first becomes central, Redis is also message durability infrastructure

### What I expect to see

- Section 4 wording no longer says “guarantees the relay has it” before the RPC succeeds
- There is a defined approach for avoiding duplicate push / duplicate delivery
- Redis requirement is tied to inbox durability too

### Acceptance evidence

- A test where direct delivery succeeds and inbox-first does not cause duplicate user-visible notification
- A test where inbox-first succeeds, direct delivery later also succeeds, and the recipient still sees exactly one logical message
- Updated plan wording reflecting reduced-window semantics instead of guarantee semantics

---

## Gap 7: The Sender UI Must React to `sending -> failed`

### Problem statement

The current conversation screen only refreshes on repository changes for `sent` or `delivered`. See [conversation_wired.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/screens/conversation_wired.dart#L462).

That means:
- DB recovery can work
- pause handling can work
- retrier can work later
- but the sender may still stare at a permanent spinner until another refresh path happens

### TODO

- Update the active conversation screen refresh filter so it also handles the failed-recovery path
- Ensure repository-emitted `failed` updates for the active conversation repaint the visible row

### What I expect to see

- When a message is proactively marked `failed` by pause handling or stuck-send recovery, the visible row updates immediately
- The sender can see that the message is recoverable / failed instead of permanent `sending`

### Acceptance evidence

- A widget test proving repository-emitted `failed` status updates repaint the active conversation row

---

## Gap 8: The Acceptance Tests Must Prove the Real Path

### Problem statement

The current plan's acceptance proof is still too synthetic in key places.

Issues found:
- the main proof manually re-sends a fresh message instead of proving same-row recovery
- media/voice lock tests bypass the real `upload_pending` + resume-reupload path
- the Bob-side notification setup is race-prone because it duplicates listeners
- some push tests still validate legacy `from` instead of real `sender_id`

This means the suite can pass without proving the actual bug is fixed.

### TODO

- Replace the main text acceptance proof with a same-row pause/resume/retry test
- Build media and voice tests through the real path:
  - optimistic row
  - pre-upload persistence
  - pause/lock
  - resume / retryIncompleteUploads / retryFailedMessages
  - Bob delivery + Bob notification
- Do not add a second live `ChatMessageListener` for Bob in the same test harness unless the plan explicitly controls dedup semantics
- Update Flutter and Go stale tests from `from` to `sender_id` where the payload being tested is FCM routing data
- Add at least one device/TestFlight smoke per modality:
  - text
  - media
  - voice

### What I expect to see

- The primary acceptance proof uses the original message record, not a fresh send
- Media/voice tests prove the real interrupted-upload recovery path
- Push routing tests exercise `sender_id`
- Device smoke confirms the user-visible path under real lock/background conditions

### Acceptance evidence

- One high-value widget/integration proof for text
- One high-value media proof through real reupload recovery
- One high-value voice proof covering local-transfer and relay-upload interruption
- One real `sender_id` notification-routing proof
- One manual/device smoke matrix entry per modality

---

## Expected Final Shape of a Sufficient Plan

For the plan to be sufficient, I expect to see all of the following explicitly reflected in the updated document:

- Section 3 rewritten as a Dart + Swift background-task slice
- Section 1 / Section 2 expanded to close:
  - initial-online retry hole
  - paused-state transition hole
- Parts F/G rewritten so `upload_pending` rows are not left as active duplicates
- Media/voice retry semantics that tolerate transient failure and resolve stored paths correctly
- Honest pre-upload file-durability language for voice/media
- Section 4 wording narrowed from “guarantee” to “reduced window”
- A dedupe / suppress-push strategy for inbox-first
- UI refresh coverage for `sending -> failed`
- Acceptance tests that prove same-row recovery and real media/voice interruption recovery

---

## Sufficient-Enough Bar

Once the plan incorporates the TODOs in this addendum, I would consider it **sufficient enough** to implement for the `1:1` bug.

If these gaps remain unresolved, I would expect one of these outcomes after implementation:
- text improves but media/voice still regress under lock
- send recovery works internally but the sender UI still looks stuck
- inbox-first introduces duplicate push or duplicate delivery behavior
- the tests pass while the real send -> lock -> recover path is still broken
