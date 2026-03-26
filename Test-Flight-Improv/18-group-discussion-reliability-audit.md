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

The main gaps are:

1. failed group retries are still text-only,
2. ordinary group media does not persist the parent message row early enough to match the stronger voice path,
3. group sends are not intentionally serialized per thread at the UI boundary,
4. group status semantics are still receipt-less, so reliability should be communicated as `sent` / `pending` rather than pretending the system has 1:1-style delivery proof.

That is enough to define a lean reliability plan without inventing a bigger subsystem.

---

## Reference Comparison With 1:1

| Reliability Property | 1:1 Reference | Current Group State | Gap |
|---|---|---|---|
| Durable text send | Strong pre-persist send contract on the main conversation path | Already strong | No material gap for core text send |
| Failed-send retry for media / voice | Failed retries can reload persisted attachments and resend | Failed group retry is still text-only | High |
| Send-then-lock durability for media | Conversation media/voice paths persist enough local state for retry/recovery | Voice is strong; ordinary group media still starts upload before the parent row exists | High |
| Sequential send behavior | Main entry path is more tightly constrained by its send flow | Group send is not intentionally serialized per thread | Medium |
| Delivery semantics | 1:1 has stronger unacked/retry meaning | Group remains receipt-less and inbox-backed | Medium, but mostly a semantics / UX honesty issue |

**User-trust standard:** if a user sends text, media, or voice into a group and immediately locks the phone, the message should still either send or recover cleanly on resume. Text is already close. Voice is close. Ordinary media is the main remaining weak spot.

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
| 1 | Failed group retries are text-only | A media/voice message that uploads successfully but fails at publish is not retried like 1:1 | High |
| 2 | Ordinary group media lacks early parent-row persistence | Lock / pause / kill during media upload can leave durable attachment rows without the parent message row that resume retry expects | High |
| 3 | No explicit per-thread send serialization | Fast successive sends can overlap instead of being intentionally ordered through one local queue/guard | Medium |
| 4 | Outgoing group status is still receipt-less | Users can trust `sent` / `pending`, but not true end-user receipt; this needs clean semantics, not new protocol complexity | Medium |

---

## Detailed Findings

### 1. Failed Group Retries Are Still Text-Only

`retry_failed_group_messages_use_case.dart` explicitly retries only text-only failed rows. It checks the persisted payloads and skips messages that still carry media metadata.

Current evidence:

- `retry_failed_group_messages_use_case.dart`
  - comments state that rows carrying media/voice retry metadata are skipped until later phases
  - `_isTextOnlyRetryPayload(...)` rejects rows that still contain `media`
- `retry_failed_group_messages_use_case_test.dart`
  - locks this behavior in with `skips rows that still carry media retry metadata`

Why this matters:

- 1:1 already retries failed messages by reloading persisted attachments and resending them through the same message contract.
- Group chat currently splits retry behavior:
  - `retryIncompleteGroupUploads()` covers uploads that never finished
  - `retryFailedGroupMessages()` covers failed text sends
- What is still weaker than 1:1 is the middle case:
  - upload finished,
  - publish failed,
  - message still has media,
  - retry path skips it instead of resending it.

Lean recommendation:

- Keep the existing split between `retryIncompleteGroupUploads()` and `retryFailedGroupMessages()`.
- Extend `retryFailedGroupMessages()` to reuse already-persisted `done` attachments the same way 1:1 does.
- Do not build a generic send-job framework.

### 2. Ordinary Group Media Still Lags Behind Voice On Durable Parent-Row Persistence

The ordinary media path in `group_conversation_wired.dart` prepares durable `upload_pending` attachment rows before upload, but it does not persist the parent `GroupMessage` row before the upload begins. The voice path does.

Current evidence:

- Text send path:
  - `send_group_message_use_case.dart` pre-persists the outgoing row before bridge calls
- Voice path:
  - `group_conversation_wired.dart` saves both the durable pending attachment and the parent optimistic message row before upload
  - tests explicitly call out that the parent row is now present before upload
- Ordinary media path:
  - `_prepareDurableGroupMediaUploads(...)` saves durable pending attachments
  - `_onSend(...)` uploads them before `sendGroupMessage(...)` is called
  - the parent message row is not persisted until later through `sendGroupMessage(...)`
- Resume retry:
  - `retry_incomplete_group_uploads_use_case.dart` requires `groupMsgRepo.getMessage(messageId)`
  - if the parent row does not exist, it skips that pending upload set

Why this matters:

- For a simple lock/unmount case, the current background-task protection is already fairly good.
- But if the process is killed or the upload is interrupted after durable attachment rows are written and before `sendGroupMessage(...)` persists the parent row, resume retry has less to work with than the voice path.
- This is exactly the kind of “I sent media, locked my phone, and it disappeared” trust gap users feel.

Lean recommendation:

- Make ordinary group media mirror the voice path:
  - create the optimistic/durable parent `GroupMessage` row before upload starts,
  - keep `sendGroupMessage(...)` responsible for final status transitions,
  - do not redesign the whole composer.

### 3. Group Sends Are Not Intentionally Serialized Per Thread

The shared `ComposeArea` already supports disabling send while `isSending` is true, but the group conversation screen does not pass that state. `_onSend(...)` also has no local mutex or queue.

Current evidence:

- `compose_area.dart`
  - the send button already checks `!widget.isSending`
- `group_conversation_screen.dart`
  - builds `ComposeArea(...)` without `isSending`
- `group_conversation_wired.dart`
  - `_onSend(...)` has no per-thread send guard/serializer
- `group_edge_cases_smoke_test.dart`
  - the “rapid burst” test uses sequential awaits and explicitly says it is not proving concurrent real-world send serialization

Why this matters:

- You said group sending should feel fast and sequential.
- Right now it can still work, but it is not intentionally enforcing “one local send pipeline at a time.”
- That can produce overlapping send/publish/inbox-store flows when a user sends multiple messages rapidly.

Lean recommendation:

- Add a very small per-conversation send guard or FIFO serializer.
- The goal is not a durable outbox queue.
- The goal is simply:
  - preserve local send order,
  - avoid overlapping publish/inbox-store races from the same screen,
  - keep the UI deterministic.

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

1. Extend failed group retries to resend media/voice messages from persisted attachments instead of skipping them.
2. Persist the parent `GroupMessage` row before ordinary media upload begins, matching the existing voice path.

### P1 — Improve Determinism

3. Add a tiny per-thread send serializer or `isSending` guard in the group conversation flow so rapid sends stay sequential.

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
- media messages that currently need parent-row parity with voice,
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
| Extend failed group retries to resend media / voice from persisted attachments | Add a deterministic regression in `retry_failed_group_messages_use_case_test.dart` for “upload finished, publish failed, retry resends persisted media/voice” | `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart` | `groups` + `baseline` |
| Persist parent `GroupMessage` before ordinary media upload starts | Add a regression proving the parent row exists before upload begins and resume recovery can find it | `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`, `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` | `groups` + `baseline`; add `transport` if pause/resume or app-restart recovery behavior changed |
| Enforce explicit sequential send behavior in one group thread | Add a regression proving rapid consecutive sends are locally serialized instead of overlapping | `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart` | `groups` + `baseline` |
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

**Group discussion messaging is already close to trustworthy for core text send/retry/recovery.** The remaining gap to 1:1 reliability is not a giant missing architecture. It is three narrow improvements:

1. media/voice failed-send retry parity,
2. ordinary media parent-row durability parity with voice,
3. explicit sequential send behavior at the UI boundary.

If those are closed cleanly, group chat should be reliable enough for users to trust text, media, and voice sending without turning the implementation into an overbuilt subsystem.
