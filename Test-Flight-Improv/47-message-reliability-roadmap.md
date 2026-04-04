# Message Reliability Roadmap

## Purpose

This roadmap is mknoon-specific. It is not trying to turn mknoon into Berty or
Status.

The goal is simpler:

- define what makes 1:1 messaging **reliable enough** for mknoon
- separate the **remaining no-loss blocker** from useful but non-blocking
  hardening work
- keep future sessions focused on the seams that actually matter

This doc should be read together with:

- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/46-deferred-direct-ack-plan.md`

## Reliable-Enough 1:1 Bar

For mknoon, 1:1 messaging is reliable enough when all of these remain true:

1. direct chat ACK never makes the sender think a message was delivered unless
   the receiver reached a terminal local outcome
2. relay inbox rows are never deleted before they are durably staged or
   committed locally
3. main send surfaces persist a durable optimistic row and wire envelope before
   risky transport work
4. failed, unacked, or interrupted rows keep a retry path while the app is
   online and on resume
5. message status semantics stay honest:
   - `delivered` is transport / inbox delivery, not read
   - direct is an optimization
   - inbox is the durable safety net

If the bar above holds, mknoon has trustworthy 1:1 messaging for current
product scope.

Everything else in this doc is either:

- a blocker required to keep that bar true
- or follow-on hardening that improves confidence, diagnosis, or suspended-app
  behavior

## Current State

### Already Landed Foundations

These are not roadmap gaps anymore:

- **Deferred direct ACK for chat messages**
  - direct chat ACK now waits for Flutter confirmation via nonce
  - timeout means no ACK, so sender falls back to inbox / retry behavior
- **Periodic retry while online**
  - failed and unacked rows already retry on state change and on the existing
    5-minute periodic sweep while the app is online
- **Durable optimistic send on main surfaces**
  - the main conversation send path and feed inline-reply path already save an
    optimistic row before `sendChatMessage(...)`
  - once a `messageId` exists, the send use case persists `wireEnvelope` before
    the risky transport race
- **Durable staging-based inbox recovery exists**
  - relay-backed inbox recovery already has the right architecture:
    `retrieve_pending` -> local stage -> `ack`

### Current Capability Snapshot

| Capability | mknoon current | Meaning for this roadmap |
|---|---|---|
| Direct chat ACK semantics | Deferred nonce-based ACK after receiver-side terminal outcome | Landed foundation |
| Store-and-forward | Relay inbox with staging + ack | Correct architecture, but one fallback seam remains |
| Retry while online | State-change retry + periodic 5-minute sweep | Landed foundation |
| Retry while OS-suspended | No guaranteed sweep while Dart isolate is suspended | Hardening, not current blocker |
| End-to-end sender confirmation | No separate `confirmed` state beyond delivered/inbox semantics | Optional hardening |
| Loss detection | No sequence-gap detection | Optional hardening |
| Receive-path diagnostics | FLOW logs exist, but recoverable dropped envelopes are not journaled durably | Hardening |

## Blocker Track: Core No-Loss Contract

This is the only remaining blocker I would put on the critical path for
trustworthy 1:1 messaging.

### Blocker B1: Remove destructive inbox fallbacks completely

#### Why it matters

The current inbox architecture is mostly correct, but one bad fallback shape
still exists:

- `retrieve_pending` is supposed to keep messages safe on the relay until they
  are durably staged locally
- when that path hits certain errors, current code can still fall back to the
  destructive legacy retrieve path
- that reintroduces the exact class of failure we are trying to eliminate:
  relay rows can disappear before local durable commit

#### Remaining dangerous seams

The dangerous seam is not just "`_inboxStagingRepository` can be null".

Even when staging exists, `_retrievePendingInboxPage(...)` currently falls back
to destructive legacy retrieve when:

- `callP2PInboxRetrievePending(...)` throws
- `retrieve_pending` returns `ok != true`
- a page contains unstageable raw messages and the whole page is abandoned

In those cases, `_retrieveInboxPage(...)` can still delete from relay before
local durable commit.

#### Required fix

1. Make `_inboxStagingRepository` non-nullable in practice and contract.
2. Delete `fallbackToLegacyRetrieve(...)` entirely.
3. For `retrieve_pending` exception / error cases:
   - do not switch to destructive retrieve
   - leave messages on the relay
   - return a safe no-progress result and retry on the next drain cycle
4. For partially bad pages:
   - stage valid entries
   - skip only the malformed ones
   - do not drop the entire page back to destructive retrieve
5. Remove the legacy destructive helper once nothing valid still depends on it.

#### Files

- `lib/core/services/p2p_service_impl.dart`
- `lib/main.dart`

#### Closure bar for this blocker

This blocker is closed when:

- there is no remaining production path from `retrieve_pending` to destructive
  `retrieve`
- relay rows are only deleted after durable local stage / ack
- direct regression proves inbox drain does not lose messages when staging or
  parsing partially fails

### Audit A1: Enforce durable send contract across all send entry points

This is not the main blocker, but it should ride the same session because it is
cheap and directly adjacent.

#### Why it matters

The main send surfaces already look correct:

- optimistic row written first
- `messageId` passed into `sendChatMessage(...)`
- wire envelope persisted before the transport race

The residual risk is not the main UI flows. The residual risk is any edge entry
point that still calls `sendChatMessage(messageId: null)`.

#### Required fix

1. Audit every `sendChatMessage(...)` caller.
2. Confirm the current real send surfaces always provide `messageId`.
3. If safe, tighten the API so `messageId` becomes required for normal send
   entry points rather than relying on convention.

#### Files

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- any caller that still relies on nullable `messageId`

## Hardening Track A: Truth And Diagnostics

These items improve trust and diagnosis, but they are not blockers for
reliable-enough 1:1 once Blocker B1 is closed.

### Hardening H1: Dropped-message local journal

#### Why it matters

Some receive-path failures are still only visible through logs. That is bad for
debugging and bad for recovery.

The right shape here is not “count more logs.” The right shape is:

- durably store recoverable dropped envelopes
- persist why they were rejected
- replay them on resume or when prerequisites appear

#### Good target scope

- store recoverable failures such as:
  - `missingMlKemSecret`
  - `decryptionFailed`
  - other retryable parse / staging outcomes if proven recoverable
- keep permanent or intentional outcomes out of replay:
  - `blockedSender`
  - `duplicate`
  - explicit permanent rejects

#### Files

- new `lib/core/inbox/dropped_message_repository.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`

### Hardening H2: End-to-end delivery receipts

#### Why it matters

Current sender-visible semantics are honest enough for current closure, but they
do not provide a stronger “recipient definitely has it” state.

If product wants a stronger sender-facing truth model, the right step is not to
change `delivered` to mean more than it does today. The right step is to add a
new stronger state.

#### Good target scope

- keep `delivered` honest as transport / inbox-backed delivery
- add a new sender-visible `confirmed` state only when the recipient sends a
  delivery receipt after durable local handling

This is optional hardening. It is not required to make the system reliable
enough.

#### Files

- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/core/services/incoming_message_router.dart`
- any UI rendering that should show `confirmed`

## Hardening Track B: Suspended-App Reliability

### Hardening H3: Retry while the app is OS-suspended

#### Why it matters

mknoon already retries while online and on resume. The remaining gap is the
fully suspended state:

- Dart timers freeze
- no periodic retry fires
- failed or unacked rows wait until resume unless another wakeup happens

This is real hardening value, but it is not the same thing as the current
no-loss blocker.

#### Good target scope

- iOS `BGAppRefreshTask`
- Android `WorkManager`
- bounded retry wake sequence:
  - bridge health check
  - inbox drain
  - retry failed
  - retry unacked

#### Files

- `ios/Runner/AppDelegate.swift`
- Android app bootstrap / activity / worker wiring
- new `lib/core/lifecycle/background_retry_task.dart`

## Hardening Track C: Loss Detection

### Hardening H4: Sequence-gap detection

#### Why it matters

Prevention is better than diagnosis, but detection still helps if a future seam
escapes.

That said, this is the highest-complexity hardening item in the roadmap and the
easiest one to overbuild.

#### Good target scope

- per-conversation monotonic sequence number
- receiver tracks last seen sequence per sender
- detect missing ranges
- only add retransmit or user-facing gap UI if incidents justify the added
  complexity

This should not be ahead of Blocker B1, dropped-message journaling, or
suspended-app retry.

#### Files

- `message_payload.dart`
- `handle_incoming_chat_message_use_case.dart`
- `message_repository.dart`

## Recommended Implementation Order

```text
DONE:
- Deferred direct ACK for chat messages
- Periodic retry while online
- Durable optimistic send on the main 1:1 surfaces

Session 1:
- Blocker B1: remove destructive inbox fallbacks completely
- Audit A1: verify / enforce messageId contract for sendChatMessage callers

Result:
- remaining no-loss blocker is removed
- mknoon reaches the reliable-enough 1:1 bar if regressions pass

Session 2:
- Hardening H1: dropped-message local journal

Session 3:
- Hardening H3: OS-suspended retry

Session 4:
- Hardening H2: delivery receipts / confirmed state
  only if product wants stronger sender-visible certainty

Session 5:
- Hardening H4: sequence-gap detection
  only if incidents justify the added protocol and storage complexity
```

## Process Rules

Every future 1:1 reliability change should follow these rules:

1. **Direct is an optimization, inbox is the durable safety net**
   - if direct handling does not complete safely, the message must land in a
     durable retryable path rather than disappear
2. **Never delete before durable stage**
   - any fallback that trades safety for progress is wrong for this subsystem
3. **Add the escaped-seam regression first**
   - every production escape should get a direct regression before the fix
4. **Do not silently inflate status semantics**
   - `delivered` should stay honest
   - stronger semantics need a new explicit state
5. **Keep blocker work separate from stronger-semantics work**
   - remove no-loss blockers first
   - then add diagnosis, suspended-app behavior, and stronger confirmation

## Design Principles

Lessons taken from Berty and Status, adapted for mknoon:

1. **ACK means locally safe for the current contract**
2. **Every message needs a safety net**
3. **Detection is useful, but prevention comes first**
4. **Sender-visible confidence should be explicit, not inferred**
5. **Silent drops are bugs**

## Bottom Line

mknoon does not need a brand-new messaging architecture to become trustworthy
for 1:1.

It needs:

- the already-landed deferred direct ACK path
- one more blocker fix: remove destructive inbox fallbacks completely
- then disciplined hardening in the right order

That is the shortest credible path to reliable 1:1 messaging in this repo.
