# Background delivery task audit

Follow-up: both confirmed issues are now fixed locally; see `sender-fixes.md`
for the implementation and current validation. The sections below retain the
pre-fix audit findings and evidence.

The sender has two separate retry owners. Ordinary unacknowledged-message retry
requires the current parent to remain `sent`, rechecks the exact saved envelope
before egress, and skips envelopes owned by the durable transfer outbox. The
durable outbox instead completes only after the exact relay acceptance contract
is confirmed. A delivered/read parent alone does not complete that independent
transfer.

## Confirmed protections

- Valid relay acceptance removes the exact outbox incarnation, including when
  the parent is already delivered or removed. A UI publication failure after
  database commit does not recreate the completed task.
- Ordinary delivery receipt settlement atomically marks delivery and clears the
  retry envelope. A late retry completion preserves an already delivered state.
- The retrier does not blindly resend all previously sent messages: it queries
  unfinished work and rechecks current state before ordinary retry egress.

## Confirmed permanently rejected task issue

Some legacy outbox envelopes have obsolete diagnostic metadata outside the
encrypted payload. The relay permanently rejects this format. Existing repair
logic deliberately leaves such a saved envelope unchanged when its parent has
already advanced to delivered/read. The task therefore remains eligible for
future retry despite the permanent rejection.

Text transfer retry has no maximum age or attempt count; its query bounds batch
size, not lifetime. This is a repair/retirement issue for permanently rejected
tasks. An arbitrary age cutoff for all pending messages would risk losing valid
delivery work and is not the proposed fix.

The relay refuses these obsolete envelopes before storing or pushing them, so
this confirmed issue cannot itself produce the reported notification. It also
means the new seven-day notification suppression horizon should not be described
as permanent exactly-once delivery.

Source: `lib/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart`
lines 260–284 (repair guards), 155 (batch query), and 365 (attempt increment).
The delivered/read successor is covered in
`test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart`
lines 247–283.

## Confirmed early receipt race

A delivery receipt received while the parent is still `sending` is deliberately
refused. The send path subsequently repairs this ordering when it obtains an
explicit committed acknowledgement. When the native result is instead
`sent: true, acked: false` and relay storage fails, the message finishes as `sent`
with its retry envelope retained despite the valid receipt already received.

The isolated `early_receipt_counterexample_test.dart` calls the real send and
receipt use cases with the existing repository fake. It injects an exact,
peer-bound receipt during the awaited send. The expected `delivered` assertion
fails with actual `sent`. Two controls pass: an explicit native acknowledgement
repairs the state, and another receipt arriving after send settlement repairs it.
The fake's refusal of `sending` is also asserted by the existing production
database tests. `lib/core/services/p2p_service_impl.dart:1381` exposes the tested
non-acknowledged send result in production.

This demonstrates an application-level race; it does not establish that this
particular incident followed that path or constitute a device/network replay.
The test and log remain under incident artifacts, outside normal test discovery.

A targeted fix should preserve a valid receipt for the exact staged sending
generation, retaining peer authorization, mutation-event matching, fanout
generation checks, and private-media rules. It must not use delivery receipt
settlement to erase separate immutable relay transfer obligations.

## Validation

Flutter SDK 3.47.2, as pinned by `.fvmrc`:

- 98 tests passed across the pending retrier, unacknowledged retry, delivery
  receipt, outgoing settlement writer, and database settlement suites. Log:
  `background-retry-audit-tests.log`.
- 32 tests passed across the direct inbox outbox drain and database helper suites.
- The early receipt counterexample has one intentional regression failure and
  two passing controls (`early-receipt-counterexample.log`).
- The exact relay diagnostic-envelope regression passes with explicit
  `GOTOOLCHAIN=go1.25.0` (0.913 seconds;
  `background-task-diagnostic-rejection-go125.log`). The initial broader
  diagnostic run did not record its inherited toolchain and is not used as
  toolchain-verified proof.

This audit made no sender production changes. The previously tested relay
notification fix remains local and undeployed.
