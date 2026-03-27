# Reliability Audit: Group Discussions vs 1:1 Chat

**Reference Standard:** current 1:1 durability / retry / recovery behavior
**Goal:** identify the smallest set of changes needed to make group discussions feel as trustworthy as 1:1 for text, media, and voice
**Constraint:** do not overengineer; prefer narrow reliability closures over new architecture
**Out of Scope:** announcement writer-enforcement proof remains a separate announcement-auth concern and is intentionally excluded from this discussion reliability audit

---

## Executive Summary

Group discussions are already strong on the basic architecture:

- outgoing group text sends are pre-persisted before bridge publish,
- relay inbox fallback is durable,
- group inbox retry exists,
- resume recovery already rejoin/drain/recover/retry in a sensible order,
- durable voice and media upload machinery already exists,
- and lock/unmount background-task protection is already covered on the wired send paths.

If 1:1 chat is the reference, the remaining work is narrower than the old reports suggested.

The main gaps are now narrower:

1. voice publish-failure retry still lacks the same producer-side completed-attachment durability that ordinary media now has,
2. group status semantics are still receipt-less, so reliability should be communicated as `sent` / `pending` rather than pretending the system has 1:1-style delivery proof.

Historical note:
- the earlier ordinary-media parent-row durability gap is now closed in the current Flutter tree:
  - `group_conversation_wired.dart` pre-persists the parent row before ordinary-media upload
  - `group_conversation_wired_test.dart` directly pins the success, upload-failure, `groupNotFound`, and `unauthorized` contracts
  - `retry_incomplete_group_uploads_use_case_test.dart` pins the missing-parent retry dependency
- the ordinary-media failed-send retry gap is also now closed in the current Flutter tree:
  - `retry_failed_group_messages_use_case.dart` reloads persisted `done` attachments and resends them in place
  - `retry_failed_group_messages_use_case_test.dart` pins wire-envelope-only ordinary-media retry plus the `upload_pending` skip contract
  - `main_resume_group_upload_wiring_test.dart` pins the `lib/main.dart` resume wiring seam for `mediaAttachmentRepository`
- the explicit one-thread send-serialization gap is also now closed in the current Flutter tree:
  - `group_conversation_wired.dart` owns one shared `_isSending` guard for `_onSend(...)` and `_onRecordStop()`
  - `group_conversation_screen.dart` passes `isSending` through to `ComposeArea`
  - `group_conversation_wired_test.dart` pins blocked second-send and blocked voice-stop/text-send overlap behavior
  - `group_conversation_screen_test.dart` pins the compose affordance wiring

That is enough to define a lean reliability plan without inventing a bigger subsystem.

---

## Reference Comparison With 1:1

| Reliability Property | 1:1 Reference | Current Group State | Gap |
|---|---|---|---|
| Durable text send | Strong pre-persist send contract on the main conversation path | Already strong | No material gap for core text send |
| Failed-send retry for media / voice | Failed retries can reload persisted attachments and resend | Ordinary media publish-failure retry is landed from persisted `done` attachments; voice still lacks a completed-attachment producer seam before publish failure | Remaining voice-only gap |
| Send-then-lock durability for media | Conversation media/voice paths persist enough local state for retry/recovery | Voice is strong, and ordinary group media now pre-persists the parent row before upload | Closed in current Flutter tree |
| Sequential send behavior | Main entry path is more tightly constrained by its send flow | Group send path now blocks overlapping local send pipelines in one thread with direct widget proof | Closed in current Flutter tree |
| Delivery semantics | 1:1 has stronger unacked/retry meaning | Group remains receipt-less and inbox-backed | Medium, but mostly a semantics / UX honesty issue |

**User-trust standard:** if a user sends text, media, or voice into a group and immediately locks the phone, the message should still either send or recover cleanly on resume. Text is already close. Ordinary media is now close on both the parent-row and publish-failure retry seams. Voice still has a narrower publish-failure retry residual because the completed attachment is not persisted before that failure window.

---

## Already Strong

| Area | Evidence | Quality |
|------|----------|---------|
| Text send durability | `send_group_message_use_case.dart` pre-persists `sending` row + `wireEnvelope` + `inboxRetryPayload` before bridge calls | Strong |
| Inbox fallback | publish + inbox store run concurrently; `inboxStored` / `inboxRetryPayload` are persisted | Strong |
| Resume recovery order | `handle_app_resumed.dart` runs rejoin -> drain -> recover stuck -> retry incomplete uploads -> retry failed group messages | Strong |
| Pause safety | `handle_app_paused.dart` transitions in-flight group `sending` rows to `failed` for later retry | Strong |
| Voice durability | group voice path saves durable `upload_pending` attachment and parent message row before upload | Strong |
| Media retry substrate | `retry_incomplete_group_uploads_use_case.dart` re-uploads durable pending attachments and re-sends once per message | Strong |
| Lock / unmount behavior | `group_conversation_wired_bg_task_test.dart` proves background-task protection across lock/unmount flows | Strong |

---

## Missing To Reach 1:1-Level Trust

| # | Gap | Why It Matters | Priority |
|---|-----|----------------|----------|
| 1 | Voice publish-failure retry is still incomplete | A voice message that uploads successfully but fails at publish still lacks the same persisted completed-attachment retry path that 1:1 has | Medium |
| 2 | Outgoing group status is still receipt-less | Users can trust `sent` / `pending`, but not true end-user receipt; this needs clean semantics, not new protocol complexity | Medium |

---

## Detailed Findings

### 1. Ordinary-Media Failed Retry Parity Is Landed; Voice Publish-Failure Retry Still Has A Narrow Residual

`retry_failed_group_messages_use_case.dart` no longer retries only text rows. It now reloads persisted attachments and resends rows whose attachment set is already complete. What still remains narrower than 1:1 is the voice producer seam before publish failure.

Current evidence:

- `retry_failed_group_messages_use_case.dart`
  - retries failed rows with persisted `done` attachments
  - keeps `upload_pending` attachment sets owned by `retryIncompleteGroupUploads(...)`
- `retry_failed_group_messages_use_case_test.dart`
  - proves ordinary-media retry from persisted `done` attachments
  - proves `upload_pending` attachments are still skipped here
  - proves media rows with no resendable persisted attachments are still skipped
- `main_resume_group_upload_wiring_test.dart`
  - proves `lib/main.dart` passes `mediaAttachmentRepository` into `retryFailedGroupMessages(...)` on resume
- `group_conversation_wired.dart`
  - ordinary media persists its durable state strongly enough for the retry use case to reload completed attachments later
- voice path in `group_conversation_wired.dart`
  - still pre-persists `upload_pending` state before upload
  - still does not persist a completed attachment row before the publish-failure window

Why this matters:

- Ordinary group media no longer has the old “upload finished, publish failed, retry skipped it” gap.
- The remaining weaker-than-1:1 case on this axis is voice publish failure after upload, because there is still no persisted completed attachment row to reload in that window.

Lean recommendation:

- Keep the existing split between `retryIncompleteGroupUploads()` and `retryFailedGroupMessages()`.
- Treat ordinary-media retry parity as closed baseline behavior.
- If voice publish-failure parity is reopened later, close the producer-side completed-attachment durability gap first rather than building a generic send-job framework.

### 2. Ordinary Group Media Parent-Row Durability Is Now Closed In The Current Flutter Tree

This used to be one of the main reliability gaps. It is now landed in the repo and should be treated as closed baseline behavior, not remaining implementation work.

Current evidence:

- `group_conversation_wired.dart`
  - saves the optimistic parent `GroupMessage` row before ordinary-media upload starts
  - uses explicit cleanup for `groupNotFound` / `unauthorized` after that early save
- `group_conversation_wired_test.dart`
  - proves the parent row exists before upload completes
  - proves upload failure leaves the parent row `failed` while keeping durable pending attachments retryable
  - proves the explicit `groupNotFound` / `unauthorized` cleanup contract
- `retry_incomplete_group_uploads_use_case_test.dart`
  - proves retry recovery still depends on the parent row and skips missing-parent upload sets

What this changes:

- ordinary media now matches the stronger voice path on the parent-row durability seam
- the remaining reliability work should move on to failed-send retry parity and explicit local sequencing rather than reopening this already-landed fix

### 3. Explicit Group Send Serialization Is Now Landed In One Thread

The earlier “group sends are not intentionally serialized” gap is now closed in the current Flutter tree and should be treated as landed baseline behavior.

Current evidence:

- `compose_area.dart`
  - the send button already checks `!widget.isSending`
- `group_conversation_screen.dart`
  - now passes `isSending` into `ComposeArea(...)`
- `group_conversation_wired.dart`
  - now owns one shared `_isSending` guard through `_tryBeginSendFlow()` / `_endSendFlow()`
  - uses that guard from both `_onSend(...)` and `_onRecordStop()`
- `group_conversation_wired_test.dart`
  - proves a second text send is blocked while the first send is in flight and is released after success
  - proves a voice send blocks a text send while the voice pipeline is active and is released after failure
- `group_conversation_screen_test.dart`
  - proves the `isSending` affordance is threaded into the compose path

Why this matters:

- You said group sending should feel fast and sequential.
- The repo now intentionally enforces “one local send pipeline at a time” in a single group conversation screen.
- That closes the earlier overlapping send/publish/inbox-store risk without adding a heavier queue/outbox system.

Lean recommendation:

- Treat the explicit one-thread send guard as closed baseline behavior.
- Preserve the existing direct regressions if this seam changes again.

### 4. Group Status Semantics Are Weaker Than 1:1, And That Is Fine If They Stay Honest

The group model supports statuses such as `sending`, `pending`, `sent`, `delivered`, and `failed`, but the current send path only gives strong outgoing meaning to:

- `sending`
- `sent`
- `pending`
- `failed`

Current evidence:

- `group_message.dart` defines the wider status vocabulary
- `send_group_message_use_case.dart`
  - returns `sent` when publish succeeds and peers are present
  - returns `pending` when `topicPeers == 0` and inbox store succeeds

Why this matters:

- Group publish remains receipt-less by design.
- `topicPeers` is a useful snapshot, not proof of end-user receipt.
- That means group reliability should aim for:
  - durable local send,
  - durable inbox fallback,
  - robust retry/recovery,
  - and honest user-visible states.

Lean recommendation:

- Do not add an ACK/receipt protocol just to make groups “feel like 1:1”.
- Keep `pending` as the honest “inbox-backed, no live peers” state.
- Keep `sent` as “accepted into the current publish path,” not “everyone received it.”

---

## Recommended Lean Reliability Plan

### P0 — Close The Real Reliability Gaps

1. Preserve the landed ordinary-media failed-send retry parity and only reopen this area if voice publish-failure parity becomes worth a separate narrow follow-up.

### P1 — Preserve Determinism

2. Preserve the landed one-thread send guard and its direct regressions if this seam is touched again.

### P2 — Keep Semantics Honest

4. Keep group status UX aligned with the current transport truth:
   - `sending`
   - `sent`
   - `pending`
   - `failed`
5. Do not pretend group chat has 1:1-style delivery proof when it does not.

### Expected Result

After those three narrow fixes, group discussions should be reliable enough for users to trust:

- text messages that are sent right before pause / lock / resume,
- voice messages that already have the stronger durable upload path,
- media messages that now have parent-row parity with voice,
- and fast consecutive sends that should stay locally ordered without adding a heavy outbox system.

---

## Required Test Contract

This audit should follow the regression rules from `14-regression-test-strategy.md`, not invent a separate test policy.

### Minimum Rule For Any Group Reliability Change

When improving one of the reliability gaps in this report, do all of the following:

1. add or update the direct regression test that proves the exact gap,
2. run the direct suite for the files you changed,
3. run the **Group Messaging Gate**,
4. run the **Baseline Gate**,
5. run the **Startup / Transport Gate** only if the change touches pause/resume, bootstrap, transport fallback, device-backed media persistence, or lock/unlock recovery behavior.

### Gate Rules To Reuse

Use the existing named gates from `test-gate-definitions.md`:

- **Group Messaging Gate**
  - `./scripts/run_test_gates.sh groups`
- **Baseline Gate**
  - `./scripts/run_test_gates.sh baseline`
- **Startup / Transport Gate** when relevant
  - `./scripts/run_test_gates.sh transport`

The point is to keep the gate definitions stable and use direct suites for the narrow change under development.

### What To Add And Run For Each Reliability Gap

| Reliability change | Regression to add first | Direct suite to run | Required gates |
|---|---|---|---|
| Keep ordinary-media failed-send retry parity closed | Preserve the existing deterministic regressions in `retry_failed_group_messages_use_case_test.dart` and the resume wiring guard in `main_resume_group_upload_wiring_test.dart` | `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/lifecycle/main_resume_group_upload_wiring_test.dart` | `groups` + `baseline`; add `transport` only if future changes alter resume/recovery behavior rather than only the local retry seam |
| Keep ordinary-media parent-row durability closed | Preserve the existing direct regressions that prove the parent row exists before upload, upload failure keeps retryable pending state, and missing-parent retry stays skipped | `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` | `groups` + `baseline`; add `transport` only if future changes cross lifecycle/recovery wiring |
| Keep explicit sequential send behavior closed in one group thread | Preserve the existing direct regressions proving blocked second-send start and compose `isSending` wiring | `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart` | `groups` + `baseline` when future production changes touch this seam |
| Clarify / tighten outgoing `pending` semantics without changing transport model | Add a direct regression around status transitions only if behavior changes | `test/features/groups/application/send_group_message_use_case_test.dart`, plus any affected presentation test | `groups` + `baseline` |

### Additional Direct Suites When Lifecycle Or Recovery Is Touched

If the implementation changes resume ordering, pause behavior, stuck-sending recovery, or upload recovery wiring, also run the relevant lifecycle direct suite:

- `test/core/lifecycle/handle_app_paused_group_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `test/core/lifecycle/pause_resume_retry_smoke_test.dart`

If the change crosses into transport or resilience behavior rather than just group orchestration, then the named `transport` gate is also required.

### Escaped-Bug Rule For Group Reliability

If a production group-chat bug escapes in any of these areas:

- media lost after send,
- voice not resent after failure,
- message lost after lock / pause / resume,
- rapid sequential sends reorder or overlap incorrectly,

then the fix should leave behind:

1. one deterministic low-layer regression test,
2. one orchestration test above it,
3. the `groups` gate run,
4. the `baseline` gate run,
5. and the `transport` gate run when the bug involved lifecycle, resume, or device-backed recovery.

That is the lean way to improve confidence without widening the permanent named gate lists.

---

## What Not To Build

- No per-member delivery receipt protocol
- No new distributed ACK layer
- No large generic outbox/send-job framework
- No group-typing/search/read-receipt/product-scope expansion in the name of “reliability”
- No broad architecture rewrite of group messaging

---

## Verdict

**Group discussion messaging is now materially close to trustworthy for core text send/retry/recovery in the current Flutter tree.** Ordinary-media parent-row durability, ordinary-media failed-send retry parity, and explicit one-thread send serialization are now landed baseline behavior.

Session 27 acceptance revalidation confirms that closure state:
- direct proofs for Sessions 24 through 26 passed in the current repo
- `./scripts/run_test_gates.sh groups` passed
- `./scripts/run_test_gates.sh baseline` passed
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport` passed after refreshing the stale `MessageRepositoryImpl` constructor wiring in `integration_test/wifi_relay_fallback_smoke_test.dart` and `integration_test/transport_e2e_test.dart`

Narrow residual note:
- voice publish-failure retry still depends on a producer-side completed-attachment durability follow-up if that seam is reopened later
- group status semantics should stay honest about `sent` / `pending` without inventing a receipt protocol

That is a narrow residual set, not a sign that group chat still needs another broad reliability architecture pass.
