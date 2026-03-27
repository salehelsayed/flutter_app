# Closure Reference: Reliable 1:1 Messaging

**Purpose:** define what "reliable enough" means for current 1:1 text/media/voice messaging in this repo so future work does not reopen product-scope or architecture-scope debates by accident.

---

## Closure Statement

The current 1:1 system should be treated as **reliably closed for core messaging** when all of these remain true:

1. sender-side text/media/voice sends persist enough local state before risky network edges,
2. interruption and retry paths can recover `sending`, failed, incomplete-upload, and unacked states,
3. offline delivery can fall back to relay inbox and heal automatically when connectivity returns,
4. receive-side decrypt, dedup, and media-download behavior remains operationally safe,
5. message statuses stay honest transport statuses, not fake read receipts.

This is the closure bar for correctness and trust. It is **not** a promise that every product feature a modern chat app could have is implemented.

---

## What Current Closure Already Includes

### 1. Durable send entry points

- `send_chat_message_use_case.dart` persists the outgoing wire envelope before risky transport work.
- The earlier feed-inline durability mismatch is closed; `feed_wired.dart` now enters the same durable send contract instead of bypassing it.
- Text, media, quote, and voice entry paths all ride the same durable recovery model.

### 2. Real retry and recovery behavior

- `recover_stuck_sending_messages_use_case.dart`
- `retry_incomplete_uploads_use_case.dart`
- `retry_failed_messages_use_case.dart`
- `retry_unacked_messages_use_case.dart`
- `pending_message_retrier.dart`

Together these give 1:1 a real auto-heal path on resume, online transition, and periodic retry sweeps.

### 3. Offline inbox fallback

- Direct send failure can fall back to relay inbox persistence.
- Inbox-backed delivery is treated as a real success path, not just a best-effort hint.
- This is one of the main reasons 1:1 currently deserves the "trustworthy" label.

### 4. Receive-path operability

- `handle_incoming_chat_message_use_case.dart` now explicitly classifies decrypt failures instead of silently collapsing them into generic failure.
- `download_media_use_case.dart` now deduplicates overlapping downloads through an in-flight guard.
- Incoming media metadata and receive-side download behavior are already part of the normal path, not an unimplemented future system.

### 5. Honest semantics

- `delivered` means transport ACK or inbox-backed delivery, not "the other user read it."
- `markConversationRead` remains local unread-state management, not a sender-visible read-receipt protocol.

---

## What Is Not Required For 1:1 Reliability Closure

These are intentionally **not** part of the closure bar:

- typing indicators
- sender-visible read receipts
- message editing/deletion
- message search
- mute controls
- persistent drafts
- auto-download preference controls
- exporter/dashboard observability work

Those may be useful product features, but their absence does not mean 1:1 messaging is unreliable.

---

## When To Reopen 1:1 Reliability

Reopen this area only if one of these happens:

1. a new or changed send surface bypasses the durable pre-persist contract,
2. text/media/voice can be lost or stranded after pause, crash, lock, resume, or temporary network failure,
3. offline inbox fallback stops behaving like a real delivery path,
4. shared retry/recovery sequencing regresses,
5. decrypt failure handling or media-download dedup regresses,
6. a named gate or direct regression proves an escaped bug in the shared 1:1 path.

Do **not** reopen 1:1 reliability just because a missing product feature was noticed.

---

## Required Regression Contract

When touching shared 1:1 reliability code:

1. add the direct regression first for the exact bug or seam,
2. run the exact direct suite for the changed files,
3. run `./scripts/run_test_gates.sh 1to1`,
4. run `./scripts/run_test_gates.sh feed` if the feed can still enter the changed 1:1 send path,
5. run `./scripts/run_test_gates.sh baseline` when Flutter production code changes,
6. run `./scripts/run_test_gates.sh transport` only when bootstrap, resume, reconnect, inbox-drain, or transport fallback wiring changes.

Use `Test-Flight-Improv/test-gate-definitions.md` as the execution source of truth and `Test-Flight-Improv/14-regression-test-strategy.md` as the policy/rationale reference.

---

## Bottom Line

The current repo already supports **trustworthy 1:1 text/media/voice messaging**. Future work should preserve:

- durable pre-persist send behavior,
- inbox-backed fallback,
- automatic retry/recovery,
- receive-path operability,
- and honest status semantics.

Everything else should be treated as separate product scope unless a real regression proves otherwise.
