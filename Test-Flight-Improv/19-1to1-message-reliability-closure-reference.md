# Closure Reference: Reliable 1:1 Messaging

**Purpose:** define what "reliable enough" means for current 1:1 text/media/voice messaging in this repo so future work does not reopen product-scope or architecture-scope debates by accident.

---

## Closure Statement

The current 1:1 system should be treated as **reliably closed for core messaging** when all of these remain true:

1. sender-side text/media/voice sends persist enough local state before risky network edges,
2. interruption and retry paths can recover `sending`, failed, incomplete-upload, and unacked states,
3. offline delivery can fall back to relay inbox, fetched inbox rows stage
   durably before ack/delete, automatic warm-start/resume/drain paths stay on
   the staged `retrieve_pending` contract instead of falling back to
   destructive `inbox:retrieve`, and notification-open recovery can surface
   them through the shared prepare-before-route contract,
4. receive-side decrypt, dedup, exact staged-envelope reject handling, and
   media-download behavior remain operationally safe,
5. message statuses stay honest delivery statuses, not fake read receipts,
6. new outgoing and incoming 1:1 rows on Go/libp2p paths keep honest
   transport semantics: actual `direct` vs `relay` from stream truth when the
   bridge provides it, explicit `wifi`, `local`, and `inbox` semantics stay
   unchanged, and legacy `reuse` remains an explicit old-row fallback only,
7. direct incoming Go/libp2p 1:1 chat ACKs are emitted only after Flutter
   reaches a receiver-side terminal disposition for that message nonce, while
   no-confirm or retryable receive outcomes stay unacked so sender-side inbox
   fallback or retry can remain truthful,
8. ordinary outbound 1:1 chat, edit, media, voice, and delete transport is
   encrypted v2 or fail-closed before send, inbox store, new outbound
   `wireEnvelope` persistence, or voice upload; persisted legacy v1 chat and
   deletion `wireEnvelope` rows are not replayed by retry shortcuts,
9. failed outgoing text recovery is a same-attempt recovery path: the visible
   failed row remains the canonical target, normal Edit is not used as resend,
   restored-composer sends retry or clear that same row instead of creating a
   second outgoing copy, and already-settled rows stay out of failed/unacked
   retry replay windows.

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
- Failed outgoing text rows now have a direct visible recovery affordance using
  targeted same-row retry. Failed rows are excluded from normal Edit so a
  never-delivered message is recovered as first delivery, not as an
  `actionEdit` payload.
- The restored-composer duplicate seam is closed for unchanged failed drafts:
  tapping Send retries the original failed row, and if automatic retry has
  already settled that row, the composer state clears without creating a new
  message ID.
- Manual recovery, automatic failed-row retry, unacked retry, and later
  periodic sweeps now have direct proof that already-settled rows remain
  no-op from the user-visible history perspective.
- Those proofs mean foreground retry-after-network-return and
  lock-after-failure resume recovery are part of current closure, while
  indefinite retry during full OS suspension is still not a promise this repo
  should overclaim.

### 3. Offline inbox fallback

- Direct send failure can fall back to relay inbox persistence.
- Inbox-backed delivery is treated as a real success path, not just a best-effort hint.
- This is one of the main reasons 1:1 currently deserves the "trustworthy" label.
- Ordinary outbound chat, edit, media, voice, and delete flows now require
  recipient ML-KEM key material and a bridge before transport work that could
  expose message content. Missing key material fails closed before direct send,
  local send, relay inbox store, new outbound `wireEnvelope` persistence, or
  voice media upload.
- Failed and unacked retry shortcuts keep encrypted v2 `wireEnvelope` replay
  support, but they no longer replay legacy v1 or versionless `chat_message`
  and `message_deletion` envelopes. Failed retry can re-enter the normal
  encrypted resend path when contact key material exists; unacked legacy rows
  move to a non-replaying failure path.
- Inbound legacy v1 chat and deletion parsing remains intentionally supported
  for old rows and mixed-version peers. Removing inbound v1 compatibility is a
  separate migration/sunset decision, not part of current reliability closure.
- Relay-backed inbox recovery now uses staged `retrieve_pending` plus explicit
  `ack`, with a durable local staging table so fetched inbox rows survive
  restart/resume until they are committed or exactly rejected.
- Automatic warm start, resume, and explicit `drainOfflineInbox()` now stay on
  the durable stage-then-ack path; `retrieve_pending` exception or `ok != true`
  returns safe no-progress instead of switching to destructive
  `inbox:retrieve`.
- Mixed valid-plus-malformed pending pages now still stage and replay valid
  entries while skipped malformed rows emit explicit telemetry instead of
  dropping the whole page back to destructive retrieve.
- Notification-opened 1:1 routes now prepare inbox catch-up before navigation
  across terminated remote, warm remote, terminated local, and warm local app
  entry points instead of letting some app-root handlers route immediately.

### 4. Receive-path operability

- `handle_incoming_chat_message_use_case.dart` now explicitly classifies decrypt failures instead of silently collapsing them into generic failure.
- Post-fetch staged chat rejects now preserve exact outcomes such as
  `missingMlKemSecret`, `duplicate`, `editMissingOriginal`, and other
  permanent-vs-retryable branches instead of disappearing as unclassified
  loss.
- Direct incoming Go-backed 1:1 `chat_message` envelopes now carry a
  confirmation nonce through the bridge, and `chat_message_listener.dart`
  resolves that nonce exactly once from the receiver-side terminal branch.
- Stored, duplicate, and accepted-drop branches such as `blockedSender` can
  confirm the nonce and allow a direct ACK; retryable or unresolved branches
  such as `missingMlKemSecret`, `decryptionFailed`, `unknownSender`,
  `editMissingOriginal`, listener loss, or timeout do not confirm, so the
  sender stays unacked instead of seeing false direct delivery.
- `download_media_use_case.dart` now deduplicates overlapping downloads through an in-flight guard.
- Incoming media metadata and receive-side download behavior are already part of the normal path, not an unimplemented future system.

### 5. Honest status and transport semantics

- `delivered` means transport ACK or inbox-backed delivery, not "the other user read it."
- On Go/libp2p direct 1:1 chat sends, a raw frame read is no longer enough to
  count as transport ACK. `delivered` now requires either receiver-side nonce
  confirmation for the direct path or the existing inbox-backed delivery path.
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
  - the late-boundary Report `35` seam is now reclosed inside that same
    contract: if cancel is accepted before an upload future later resolves or
    before the composer leaves upload mode, the sender still gets the cancel
    outcome and that same attempt does not fall through into the final
    `sendChatMessage(...)` / recipient-delivery path
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
- Non-chat direct messages remain on the accepted lighter confirmation model;
  the deferred direct-ack contract in Report `46` is intentionally scoped to
  incoming 1:1 `chat_message` envelopes.
- Report `48` intentionally removed only the automatic inbox-drain fallback
  path; the public `retrieveInbox()` API remains out of scope until a separate
  caller/cleanup decision justifies changing it.
- No DB migration backfills old rows already stored as `transport: 'reuse'`.
- Sessions 34 and 36 did not make the named transport gate invoke the
  standalone CLI orchestrator automatically. The direct
  `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>`
  command remains separate maintenance-time proof when those seams change.
- Session 36 kept proof retention in the Dart orchestrator instead of changing
  the `testpeer` collector lifecycle or widening into shared Flutter / Go 1:1
  transport code.
- Sessions 47 and Report 35 keep cancel as next-safe-boundary terminalization
  rather than inventing mid-stream transport aborts or a new `cancelled`
  status model.
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
3. offline inbox fallback stops behaving like a real delivery path, or
   automatic inbox drain regresses from durable `retrieve_pending` back to
   destructive `inbox:retrieve`,
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
   cancel, late upload-failure override, final-send suppression after accepted
   cancel, targeted failed-media retry/delete, or bounded owned-file cleanup),
   or the repo starts overclaiming true background upload behavior,
10. a named gate or direct regression proves an escaped bug in the shared 1:1 path,
11. the reviewed standalone CLI-backed seams regress: honest transport-truth
   acceptance in `A1` / `A4` / `A2` / `A5` / `D4` / `A7`, no-address self-heal
   recovery in `A8` / `A8b` / `C3`, content-based `B8` / `G6`
   synchronization, or retained receiver-proof verification for `E8`,
   `RECV-A1`, `RECV-A4`, or `RECV-A6` in the direct standalone command,
12. notification-opened 1:1 routes can again navigate before staged inbox
   recovery or exact post-fetch disposition handling makes the pending message
   visible or diagnosable.
13. direct Go/libp2p 1:1 chat ACK can again happen before the receiver reaches
    a terminal nonce-confirmed disposition, or an unacked direct send stops
    truthfully handing off to inbox-backed delivery when that fallback is
    available.

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
7. when the shared direct-ack seam changes, include one sender-side no-confirm
   proof plus one sender inbox-handoff proof so the repo does not regress back
   to false direct `delivered`.

For shared 1:1 inbox-recovery / notification-open trust seams, the direct
proof should keep covering:

- staged relay fetch -> durable local record -> later `ack` ordering
- restart/resume replay of staged inbox rows that were fetched earlier but not
  yet committed
- automatic warm start, resume, and explicit `drainOfflineInbox()` staying on
  `retrieve_pending` -> stage -> `ack` without any automatic
  `inbox:retrieve` fallback on exception or `ok != true`
- mixed valid-plus-malformed `retrieve_pending` pages still staging/replaying
  valid rows while skipped malformed rows are logged and not acked
- exact staged-envelope reject outcomes for retryable vs permanent drops
- prepare-before-route sequencing on terminated remote, warm remote,
  terminated local, and warm local notification-open entry points

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
- accepted video-plus-caption cancel still suppressing the later
  `sendChatMessage(...)` path for that same attempt
- cancel requested before an upload future later resolves as failure still
  surfacing `Upload cancelled.` instead of the ordinary upload-failure path
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
- durable inbox-backed fallback and automatic drain,
- automatic retry/recovery,
- receive-path operability,
- honest status and transport semantics for new rows,
- the settled general-media size contract,
- and honest foreground-only upload protection plus safe-boundary failed-media
  recovery controls while relay uploads are active.

Everything else should be treated as separate product scope unless a real regression proves otherwise.
