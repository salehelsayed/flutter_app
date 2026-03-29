# Closure Reference: Reliable 1:1 Messaging

**Purpose:** define what "reliable enough" means for current 1:1 text/media/voice messaging in this repo so future work does not reopen product-scope or architecture-scope debates by accident.

---

## Closure Statement

The current 1:1 system should be treated as **reliably closed for core messaging** when all of these remain true:

1. sender-side text/media/voice sends persist enough local state before risky network edges,
2. interruption and retry paths can recover `sending`, failed, incomplete-upload, and unacked states,
3. offline delivery can fall back to relay inbox and heal automatically when connectivity returns,
4. receive-side decrypt, dedup, and media-download behavior remains operationally safe,
5. message statuses stay honest delivery statuses, not fake read receipts,
6. new outgoing and incoming 1:1 rows on Go/libp2p paths keep honest
   transport semantics: actual `direct` vs `relay` from stream truth when the
   bridge provides it, explicit `wifi`, `local`, and `inbox` semantics stay
   unchanged, and legacy `reuse` remains an explicit old-row fallback only.

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

- The repo now explicitly proves the user-visible failure seam where a send can
  fail during transport loss, show a failed state, then heal the same row
  exactly once after online transition while the app stays open.
- The repo also explicitly proves the adjacent seam where that failed row
  survives pause/lock and heals exactly once on resume.
- Those proofs mean foreground retry-after-network-return and
  lock-after-failure resume recovery are part of current closure, while
  indefinite retry during full OS suspension is still not a promise this repo
  should overclaim.

### 3. Offline inbox fallback

- Direct send failure can fall back to relay inbox persistence.
- Inbox-backed delivery is treated as a real success path, not just a best-effort hint.
- This is one of the main reasons 1:1 currently deserves the "trustworthy" label.

### 4. Receive-path operability

- `handle_incoming_chat_message_use_case.dart` now explicitly classifies decrypt failures instead of silently collapsing them into generic failure.
- `download_media_use_case.dart` now deduplicates overlapping downloads through an in-flight guard.
- Incoming media metadata and receive-side download behavior are already part of the normal path, not an unimplemented future system.

### 5. Honest status and transport semantics

- `delivered` means transport ACK or inbox-backed delivery, not "the other user read it."
- `markConversationRead` remains local unread-state management, not a sender-visible read-receipt protocol.
- New outgoing Go/libp2p 1:1 sends now persist actual stream-truth `direct`
  vs `relay`, including the already-connected fast path, direct discover/send,
  and relay-probe success.
- New incoming Go-backed 1:1 rows now persist the actual inbound stream
  transport when the bridge provides it, instead of letting mixed direct+relay
  peer state override the message truth.
- `wifi`, `local`, and `inbox` semantics stay explicit and unchanged.
- Flutter-side peer-state inference remains compatibility fallback only for
  older untagged bridge payloads, not the primary truth path for new messages.
- Legacy rows that still contain `reuse` intentionally keep rendering as the
  direct-like fallback until a separate aging-out or migration decision exists.

### 6. Settled attachment budget and foreground upload protection

- Ordinary 1:1 attachments now use the settled `5 GB` general-media budget
  across the live composer entry points that matter in this repo:
  in-app attach flows plus hydrated/share/feed entry paths that reuse the same
  pending-media state.
- The in-app voice recorder keeps its separate `100 MB` sanity limit; that
  remains a recorder-specific safeguard, not the ordinary attachment budget.
- The current 1:1 conversation surfaces now show honest foreground upload
  protection for active relay uploads:
  - aggregate byte progress
  - the warning copy `Keep the app open until the upload completes`
  - leave confirmation while an upload is active
  - a ref-counted wake lock that stays held until the last active relay upload
    finishes, fails, or is cancelled
- Active relay uploads now also expose a user-controlled cancel path in the
  live 1:1 conversation surface, but the maintenance promise stays honest:
  - cancel does not interrupt an in-flight upload RPC mid-stream
  - it takes effect at the next safe boundary, restores the composer snapshot,
    terminalizes the optimistic row to `failed`, and marks durable pending
    attachments `upload_failed`
- Failed outgoing 1:1 media rows now expose message-scoped retry/delete
  controls:
  - retry acts on the same failed row instead of creating a duplicate
    optimistic row
  - delete removes only the targeted failed row and only app-owned durable
    pending-upload files, not arbitrary stored gallery/source paths
- This closure is still intentionally foreground-only. The repo does **not**
  promise true background upload execution or download-side wake-lock behavior.

### 7. Narrow standalone CLI-backed transport closure

- `integration_test/transport_e2e_test.dart` now treats the reviewed `A1`,
  `A4`, `A2`, `A5`, `D4`, and `A7` cases as passing when they preserve honest
  live transport truth instead of relay-only assumptions.
- `go-mknoon/node/send_message_recovery_test.go` now includes
  `TestSendMessage_RetriesNoAddressesOpenErrorAfterSelfHeal`, and
  `go-mknoon/node/node.go` treats the reproduced reconnect
  `failed to dial ... no addresses` stream-open shape as retryable within the
  existing self-heal path, closing the reviewed `A8`, `A8b`, and `C3` seam
  without adding a second send architecture.
- `integration_test/transport_e2e_test.dart` and
  `integration_test/scripts/run_transport_e2e.dart` now wait for non-empty
  `B8` and `G6` signal contents instead of racing on file existence alone.
- `integration_test/scripts/run_transport_e2e.dart` now retains receiver-side
  proof across async `message:received` events, inbox retrievals, and later
  collector resets, so standalone post-verify checks do not lose evidence when
  the CLI node restarts during the run.
- The direct standalone command
  `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>`
  is back to full green for the reviewed seams: `E8`, `RECV-A1`, `RECV-A4`,
  and `RECV-A6` now pass from retained receiver-side proof instead of stale
  final-collector assumptions, and the required `transport` gate still passes.

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

## Residual-Only Items

- Removing the legacy `reuse` UI fallback is not current reliability work.
  Reopen that only after old rows have naturally aged out or a dedicated
  migration / cleanup decision is made.
- Fully suspended background retry behavior after a message has already entered
  `failed` is still not a stronger closure promise. Current closure is
  foreground online-transition healing plus resume-time recovery.
- True background upload architecture and download-side wake-lock guarantees are
  still not part of the current 1:1 closure bar.

---

## Accepted Differences

- No routing-preference, dialing-policy, retry-policy, or icon-product redesign
  was required just to make transport labels honest.
- `P2PServiceImpl._inferTransportForPeer` remains where it is as a compatibility
  fallback for older untagged bridge payloads; Sessions 31 and 32 did not
  broaden into transport-API cleanup.
- No DB migration backfills old rows already stored as `transport: 'reuse'`.
- Sessions 34 and 36 did not make the named transport gate invoke the
  standalone CLI orchestrator automatically. The direct
  `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>`
  command remains separate maintenance-time proof when those seams change.
- Session 36 kept proof retention in the Dart orchestrator instead of changing
  the `testpeer` collector lifecycle or widening into shared Flutter / Go 1:1
  transport code.
- Session 47 kept cancel as next-safe-boundary terminalization rather than
  inventing mid-stream transport aborts or a new `cancelled` status model.
- Session 47 kept failed-media recovery scoped to media rows: failed text-only
  rows do not gain generic retry/delete affordances.
- Session 47 kept delete cleanup bounded to the targeted failed row and
  app-owned durable pending-upload paths; arbitrary stored gallery/source files
  remain protected.
- A sender-visible `failed` state can still legitimately precede later
  auto-heal when the initial active send and immediate inbox handoff both miss
  during a network switch. That is now a covered recovery seam, not evidence
  that 1:1 reliability is open again.

---

## When To Reopen 1:1 Reliability

Reopen this area only if one of these happens:

1. a new or changed send surface bypasses the durable pre-persist contract,
2. text/media/voice can be lost or stranded after pause, crash, lock, resume, or temporary network failure,
3. offline inbox fallback stops behaving like a real delivery path,
4. shared retry/recovery sequencing regresses,
5. decrypt failure handling or media-download dedup regresses,
6. new outgoing or incoming 1:1 rows on shared Go/libp2p paths regress back to
   misleading transport labels, especially under mixed direct+relay peer state
   or relay-probe success,
7. failed-send recovery during network switch no longer heals on foreground
   online transition or resume-time recovery,
8. attach-time general-media budget parity regresses across in-app or hydrated
   1:1 entry paths, or in-app voice recordings stop honoring the separate
   `100 MB` sanity cap,
9. active relay upload protection regresses in the 1:1 conversation surface
   (aggregate progress, leave guard, wake-lock lifetime, next-safe-boundary
   cancel, targeted failed-media retry/delete, or bounded owned-file cleanup),
   or the repo starts overclaiming true background upload behavior,
10. a named gate or direct regression proves an escaped bug in the shared 1:1 path,
11. the reviewed standalone CLI-backed seams regress: honest transport-truth
   acceptance in `A1` / `A4` / `A2` / `A5` / `D4` / `A7`, no-address self-heal
   recovery in `A8` / `A8b` / `C3`, content-based `B8` / `G6`
   synchronization, or retained receiver-proof verification for `E8`,
   `RECV-A1`, `RECV-A4`, or `RECV-A6` in the direct standalone command.

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

For 1:1 transport-label work, the direct proof should keep covering:

- reuse fast-path resolution to `local`, `relay`, and `direct`
- explicit Go send transport winning over conflicting mixed direct+relay peer
  state
- relay-probe success and direct discover/send persisting actual stream
  transport, not a Flutter-side guess
- incoming Go-tagged transport winning over mixed peer-state inference
- additive transport preservation through bridge `message:send` responses and
  incoming `message:received` events
- the legacy `reuse` UI fallback
- the broader onboarding confidence flow that must no longer accept `reuse` for
  new sends
- failed-send during transport loss -> foreground online-transition heal of the
  same row exactly once
- failed-send during transport loss -> lock/pause -> resume heal of the same
  row exactly once
- the settled `5 GB` ordinary-attachment budget across live and hydrated 1:1
  entry paths, while keeping the recorder-only `100 MB` voice sanity limit
- active relay-upload progress, leave-confirmation, and wake-lock lifetime in
  the 1:1 conversation surface
- next-safe-boundary cancel restoring the composer snapshot while
  terminalizing the same row to `failed` plus attachment `upload_failed`
- failed outgoing media rows exposing same-row retry/delete controls without
  widening the contract to text-only failures
- delete cleanup staying bounded to the targeted row and app-owned
  pending-upload files instead of arbitrary stored gallery/source paths

For the reviewed standalone CLI-backed transport seams from Sessions 34 and 36,
maintenance-time proof is both:

- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
- `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>`

The named transport gate can execute `integration_test/transport_e2e_test.dart`
without the CLI fixture/orchestrator path, so it is necessary but not
sufficient on its own for those seams.

That direct proof should keep covering:

- honest transport-truth acceptance for the reviewed `A*` / `D4` seam set
- reconnect self-heal behavior for `A8` / `A8b` / `C3`
- content-based synchronization for `B8` and `G6`
- retained receiver-side proof surviving collector reset / restart for `E8`,
  `RECV-A1`, `RECV-A4`, and `RECV-A6`

Use `Test-Flight-Improv/test-gate-definitions.md` as the execution source of truth and `Test-Flight-Improv/14-regression-test-strategy.md` as the policy/rationale reference.

---

## Bottom Line

The current repo already supports **trustworthy 1:1 text/media/voice messaging**. Future work should preserve:

- durable pre-persist send behavior,
- inbox-backed fallback,
- automatic retry/recovery,
- receive-path operability,
- honest status and transport semantics for new rows,
- the settled general-media size contract,
- and honest foreground-only upload protection plus safe-boundary failed-media
  recovery controls while relay uploads are active.

Everything else should be treated as separate product scope unless a real regression proves otherwise.
