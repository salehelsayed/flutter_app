# Closure Reference: Reliable Group Discussions

**Purpose:** define what "reliable enough" means for current group discussion text/media/voice messaging in this repo without pretending group chat has identical transport semantics to 1:1 chat.

---

## Architecture Note

Group discussions are **not** 1:1 chat with more recipients.

Current group reliability is built on:

- pre-persisted local sender state,
- concurrent publish + inbox fallback,
- resume-oriented recovery,
- receipt-less publish semantics,
- and local one-thread send serialization.

This closure reference is therefore a **sender-trust closure**, not a promise of per-recipient ACK proof.

---

## Closure Statement

The current group discussion system should be treated as **reliably closed for core messaging** when all of these remain true:

1. outgoing text/media/voice messages persist enough local state before publish/upload risk,
2. interruption and resume recovery can rejoin, drain, recover, and retry without losing sender work,
3. ordinary media remains durable across send-then-lock and publish-failure retry paths,
4. one conversation screen does not run overlapping local send pipelines,
5. user-visible statuses stay honest for a receipt-less group transport model.

This is the closure bar for current group discussions.

---

## What Current Closure Already Includes

### 1. Durable sender-side text path

- `send_group_message_use_case.dart` pre-persists the outgoing row before bridge publish work.
- The send path carries enough local state for later retry/recovery through `wireEnvelope`, `inboxStored`, and `inboxRetryPayload`.

### 2. Durable ordinary-media path

- `group_conversation_wired.dart` now persists the parent `GroupMessage` row before ordinary-media upload starts.
- `retry_incomplete_group_uploads_use_case.dart` and `retry_failed_group_messages_use_case.dart` now give ordinary media the intended retry/recovery shape.
- This closes the earlier ordinary-media parent-row and publish-failure retry gaps.

### 3. Strong resume-oriented recovery

The current group flow already has meaningful recovery on resume:

- topic rejoin
- group inbox drain
- stuck-send recovery
- incomplete-upload retry
- failed-send retry

That is enough for the current group closure bar when combined with durable local persistence.

### 4. Explicit one-thread send serialization

- `group_conversation_wired.dart` owns a shared local send guard
- `group_conversation_screen.dart` threads `isSending` into `ComposeArea`

This means one group conversation screen now intentionally prevents overlapping local send pipelines instead of relying on luck.

### 5. Honest group status semantics

Current closure treats these as the meaningful outgoing statuses:

- `sending`
- `sent`
- `pending`
- `failed`

That is the correct level of honesty for a publish + inbox-backed, receipt-less group system.

---

## Accepted Architectural Differences From 1:1

These differences are real and do **not** automatically mean group discussions are unreliable:

1. group publish is receipt-less; it does not prove end-user receipt the way 1:1 ACK/inbox logic is stronger,
2. `sent` in groups means accepted into the current publish path, not "every member definitely received it",
3. `pending` in groups honestly means inbox-backed / no-live-peer style fallback, not a failure,
4. local ordering is intentionally serialized per conversation screen, but distributed total ordering is not guaranteed.

Future work may strengthen those areas, but they are not required to keep the current group system trustworthy.

---

## Current Residual Caveat

There is still one narrow residual worth remembering:

- voice publish-failure retry is weaker than ordinary-media retry because the producer-side completed-attachment seam is still narrower in the current tree

This is **not** a reason to reopen the whole group reliability program. It is the one specific residual to reopen only if it becomes a real escaped bug or clearly justified trust gap.

---

## What Is Not Required For Group Reliability Closure

These are intentionally **not** part of the current closure bar:

- group ACK / per-recipient delivery proof
- read receipts
- total ordering across devices
- heavy outbox/job architecture
- broad status-model redesign
- announcement authorization proof
- search, scheduling, analytics, or other product-scope features

Those may be future product or protocol work, but they are not prerequisites for trusting the current group send path.

---

## When To Reopen Group Reliability

Reopen this area only if one of these happens:

1. a send surface bypasses the current durable pre-persist contract,
2. ordinary media loses parent-row or publish-failure retry parity,
3. resume recovery stops restoring sender work safely,
4. the one-thread send guard regresses,
5. voice publish-failure retry becomes a real escaped bug or clearly justified trust gap,
6. a direct regression or named gate proves an escaped bug in shared group send/retry/recovery behavior.

Do **not** reopen group reliability just because someone notices that group semantics are weaker than 1:1 in the abstract.

---

## Required Regression Contract

When touching shared group discussion reliability code:

1. add the direct regression first for the exact seam,
2. run the exact direct suite for the changed files,
3. run `./scripts/run_test_gates.sh groups`,
4. run `./scripts/run_test_gates.sh baseline` when Flutter production code changes,
5. run `./scripts/run_test_gates.sh transport` only when lifecycle, startup, resume, reconnect, or device-backed media recovery wiring changes,
6. run `./scripts/run_test_gates.sh 1to1` as well if shared 1:1 retry/transport infrastructure is touched.

Use `Test-Flight-Improv/test-gate-definitions.md` as the execution source of truth and `Test-Flight-Improv/14-regression-test-strategy.md` as the policy/rationale reference.

---

## Bottom Line

The current repo already supports **trustworthy group discussion messaging for text/media/voice** under the current architecture, with one narrow residual around voice publish-failure retry.

Future changes should preserve:

- durable local sender state,
- inbox-backed recovery,
- resume-oriented repair,
- one-thread send determinism,
- and honest receipt-less status semantics.

Anything beyond that should be treated as new product/protocol scope unless a real regression proves otherwise.
