# 1. Title and Type

- Title: `Transport Badge Truth Audit`
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/Transport-Badges-Feature/transport-badges-audit.md`
- Affected area: `1:1 conversation transport labeling across sender save flow, receiver receive flow, and badge rendering`

# 2. Problem Statement

Users read the transport badge on a conversation row as an explanation of how a message actually moved: local WiFi, live Go direct, live Go relay, or inbox. Today that trust breaks in a reproducible network-transition sequence.

When one side first talks over mobile-data-era Go transport and both devices later become local peers on the same WiFi, the sender can show the WiFi badge class while the receiver still shows relay or direct for the same message. From the user’s point of view, the badge is then no longer evidence of the actual transport path; it becomes a mixture of real path data and local-peer visibility.

That is a product problem even when message delivery itself succeeds. The badge is currently part of how users and QA interpret network behavior. If the sender shows WiFi, users expect the message to have actually used WiFi. If the sender shows relay, users expect relay. If the sender shows inbox, users expect inbox.

# 3. Impact Analysis

- Who is affected:
  - both participants in 1:1 conversations that surface per-message transport
    badges
  - QA and debugging workflows that rely on the badge to explain actual
    transport behavior
- When it appears:
  - after network-topology changes, especially `4G/mobile-data first, same
    WiFi later`
  - when local discovery and an already-open Go connection coexist
  - when a message gets only one physical delivery over Go, so receiver-side
    duplicate upgrade never has a chance to correct the stored row
- Severity:
  - medium user-facing trust issue
  - no repo evidence here suggests message loss from this badge problem alone,
    but the badge semantics are misleading
- Frequency:
  - the user reproduced the mismatch on a real Android + iPhone pair
  - the current code makes that sequence structurally possible whenever local
    peer visibility and a warm Go connection overlap
- Confusion cost:
  - high for a diagnostic affordance, because the UI implies path truth while
    the sender can currently derive the WiFi badge from locality rather than
    from the actual send path

# 4. Current State

## Badge source of truth

- The conversation UI renders transport directly from
  `ConversationMessage.transport` in
  `lib/features/conversation/presentation/widgets/letter_card.dart`.
- The user-visible badge classes are:
  - `wifi` and `local` -> WiFi icon
  - `direct` and legacy `reuse` -> direct icon
  - `relay` -> relay icon
  - `inbox` -> inbox icon
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
  directly proves that `local` and `wifi` intentionally render the same WiFi
  badge class.

## Sender transport truth today

- `sendChatMessage(...)` in `lib/features/conversation/application/send_chat_message_use_case.dart` persists the outgoing row from whichever send path it decides won.
- The send flow checks for an already-known peer connection before it launches the local-vs-Go race.
- That reuse gate is currently:
  `p2pService.currentState.connections.any((c) => c.peerId == targetPeerId)`. It does not use the service’s stricter `isConnectedToPeer(...)` helper that requires `status == 'connected'`.
- On the reuse fast path, the sender uses `sendMessageWithReply(...)`, which is a Go/libp2p send, not the local WiFi WebSocket path.
- The bridge contract already exposes actual Go transport on send:
  `lib/core/bridge/p2p_bridge_client.dart` documents `transport: "direct|relay"`, and `lib/core/services/p2p_service_impl.dart` forwards that into `SendMessageResult.transport`.
- The problem is in `_resolveGoSendTransport(...)` inside
  `send_chat_message_use_case.dart`:
  - when `preserveLocalPeerLabel` is true
  - and `p2pService.isLocalPeer(peerId)` is true
  - it returns `local` before it even looks at the actual Go-reported
    `sendResult.transport`
- That means the sender can stamp the WiFi badge class for a Go send merely because the peer is visible on local WiFi.
- By contrast, the later direct/race path and relay-probe path do consult the actual `sendResult.transport` first, so the main sender badge-risk is concentrated in the reuse fast path.
- `inbox` is already explicit on the sender side in
  `send_chat_message_use_case.dart`,
  `retry_unacked_messages_use_case.dart`, and
  `retry_failed_messages_use_case.dart`; once a row is tagged `inbox`, the UI
  has a direct badge mapping for it.

## Receiver transport truth today

- Local WiFi receives enter the unified message stream from
  `LocalP2PService`/`LocalWsServer` with `transport: 'wifi'` in
  `lib/core/services/p2p_service_impl.dart`.
- Go-backed receives come from the bridge event `message:received`.
  `go-mknoon/node/transport_label_test.go` proves the Go node emits:
  - `direct` for non-circuit streams
  - `relay` for circuit-backed streams
- `test/core/services/p2p_service_impl_test.dart` proves that when the bridge
  provides incoming transport, Flutter keeps that explicit value instead of
  letting mixed peer state override it.
- If the bridge does not provide a transport, `P2PServiceImpl` still has a
  compatibility fallback that infers from current peer state:
  relay wins if any multiaddr contains `/p2p-circuit`, otherwise direct.
- `handleIncomingChatMessage(...)` in
  `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  persists the incoming `transport` directly on first store.
- If the same message ID arrives again, the receiver can upgrade the stored row
  to a stronger transport class:
  - `wifi`/`local` outrank `direct`/`reuse`
  - `direct`/`reuse` outrank `relay`
  - `relay` outranks `inbox`
- `ChatMessageListener` in
  `lib/features/conversation/application/chat_message_listener.dart`
  re-emits the refreshed row when that duplicate-upgrade path changes only the
  metadata.

## Why the reproduced sender/receiver mismatch is consistent with current code

- First, a message sent before local WiFi availability can establish a warm Go
  connection.
- Later, both devices join the same WiFi and local discovery marks the peer as
  local via `isLocalPeer(...)`.
- The next message can hit the already-connected reuse fast path before the
  sender ever tries the explicit local WiFi send.
- That fast path still uses Go/libp2p transport but currently labels the sender
  row as `local` because the peer is local.
- The receiver, however, sees the actual single inbound Go message and stores
  `relay` or `direct` from bridge truth or compatibility inference.
- If no second local copy physically arrives, the duplicate-upgrade logic never
  runs, so the receiver has nothing to “correct.”
- Result: the same message can show a WiFi badge class on the sender and a
  relay/direct badge class on the receiver.

## Current test and document evidence

- Current tests that correctly cover parts of the badge story:
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
    proves the direct discover path persists actual Go `relay` when Go returns
    relay
  - the same file proves an already relay-backed reused connection persists
    `relay`
  - `test/core/services/p2p_service_impl_test.dart` proves incoming explicit Go
    transport wins over conflicting mixed peer state
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
    proves duplicate receive can upgrade a stored relay row to WiFi
  - `test/features/conversation/application/chat_message_listener_test.dart`
    proves the UI-facing listener re-emits that upgraded row
  - `test/core/resilience/f1_wifi_relay_fallback_test.dart` proves the normal
    same-WiFi happy path stores sender `local` and receiver `wifi`
- Current test that locks in the wrong sender behavior:
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
    contains `existing local peer persists local transport on the reuse fast path`
    and expects `message.transport == 'local'` even though the send itself uses
    `sendMessageWithReply(...)`
- Current high-value missing tests:
  - no sender test for `peer is local + warm connected Go path + actual Go
    transport is relay`
  - no sender test for `peer is local + warm connected Go path + actual Go
    transport is direct`
  - no end-to-end 1:1 sender/receiver test for the exact reproduced sequence:
    `Go/4G first, WiFi later, warm connection reused`
- Why the current WiFi fallback resilience suite does not catch the reproduced
  bug:
  - `test/shared/fakes/fake_p2p_service_integration.dart` does not publish live
    `currentState.connections`
  - its `sendMessageWithReply(...)` always returns `transport: 'direct'`
  - its `probeRelay(...)` always returns `error`
  - so `test/core/resilience/f1_wifi_relay_fallback_test.dart` never models a
    warm reused Go relay connection that coexists with `isLocalPeer == true`
- Existing repo docs currently overstate closure:
  - `Test-Flight-Improv/12-1to1-chat-use-case-audit.md` says sender-visible
    transport-truth seams are closed and reuse-fast-path/local semantics stay
    honest
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
    says new outgoing Go sends keep actual `direct` vs `relay`, including the
    already-connected fast path
  - current production code does not satisfy that claim for local-peer reuse

# 5. Scope Clarification

- In-scope user-visible expectations:
  - the badge class on a conversation message should correspond to the actual
    delivery class used for that message
  - if a message shows the WiFi badge class on the sender, the message must
    have actually used the local WiFi path
  - if a message shows relay or direct on the sender, that badge class must
    match the actual Go transport path
  - if a message shows inbox, the row must represent inbox-backed delivery
  - sender and receiver should not disagree on WiFi vs relay/direct for the
    same message because one side derived the badge from peer locality alone
- Explicit non-goals:
  - this audit does not choose or propose a routing policy such as
    `local-first`, `race`, or `probe-first`
  - this audit does not redesign icons or message-row UI
  - this audit does not cover group messages, introduction delivery badges, or
    delete tombstone transport labels, even though adjacent code shows similar
    local-label preservation patterns
  - this audit does not require collapsing raw internal values `local` and
    `wifi` into one database enum if the user-visible WiFi badge class remains
    truthful
- Accepted ambiguities for later implementation work:
  - raw sender `local` and raw receiver `wifi` are currently different internal
    values but one user-visible badge class
  - compatibility fallback for older untagged bridge payloads still exists on
    incoming Go messages; this audit records that seam but does not decide
    whether legacy fallback should be removed

# 6. Test Cases

## Happy path

1. Fresh same-WiFi local delivery
   - Two contacts are on the same WiFi and no warm Go connection is being
     reused.
   - One user sends a 1:1 text message.
   - Expected observable result:
     - sender shows the WiFi badge class
     - receiver shows the WiFi badge class
     - receiver sees exactly one visible message row
   - Current evidence:
     - partially covered by
       `test/core/resilience/f1_wifi_relay_fallback_test.dart`

2. Live Go direct delivery
   - Two contacts are not local peers and a message travels over a Go direct
     stream.
   - Expected observable result:
     - sender shows the direct badge class
     - receiver shows the direct badge class
   - Current evidence:
     - partial sender coverage in
       `test/features/conversation/application/send_chat_message_use_case_test.dart`
     - partial receiver transport coverage in
       `test/core/services/p2p_service_impl_test.dart`
     - no full sender/receiver conversation proof in one test today

3. Live Go relay delivery
   - Two contacts exchange a 1:1 message over a relay-backed Go path.
   - Expected observable result:
     - sender shows the relay badge class
     - receiver shows the relay badge class
   - Current evidence:
     - partial sender coverage in
       `test/features/conversation/application/send_chat_message_use_case_test.dart`
     - Go bridge/node transport coverage in
       `go-mknoon/bridge/bridge_test.go` and
       `go-mknoon/node/transport_label_test.go`
     - no Flutter sender/receiver end-to-end badge convergence proof today

4. Inbox-backed delivery
   - Live delivery is unacked or unavailable and the message is stored for
     inbox-backed delivery.
   - Expected observable result:
     - sender shows the inbox badge class
     - receiver shows the inbox badge class when the message is replayed from
       inbox
   - Current evidence:
     - partial coverage exists in
       `send_chat_message_use_case.dart` tests,
       `retry_unacked_messages_use_case.dart` tests,
       `retry_failed_messages_use_case.dart` tests, and
       `handle_incoming_chat_message_use_case_test.dart`

## Edge cases

5. 4G first, WiFi later, warm Go connection still present
   - Two phones first exchange a message while Go transport is the only live
     path.
   - Both later join the same WiFi and local discovery marks each peer local.
   - A new message is sent while the earlier Go connection is still reusable.
   - Expected observable result:
     - the new message shows the same badge class on both devices
     - peer locality alone does not flip the sender badge to WiFi
   - Current evidence:
     - no current test covers this sequence

6. Peer is local, but Go wins the live path
   - Two phones are on the same WiFi.
   - The actual delivered live copy for a message is Go direct or Go relay.
   - Expected observable result:
     - if no real local copy arrives, both sides keep the non-WiFi badge class
     - WiFi badge class only appears if the message actually used the local
       WiFi path
   - Current evidence:
     - receiver duplicate-upgrade behavior is covered
     - sender truth for this mixed case is not covered

7. Local send ambiguity after bytes may already have left the sender
   - A local send attempt does not produce a clean local success signal, but a
     recovery path later establishes durable delivery.
   - Expected observable result:
     - the final visible badge class remains truthful to the actual delivery
       class
     - sender does not over-report WiFi just because the peer is local
   - Current evidence:
     - timeout and inbox fallthrough tests exist
     - no current badge-convergence proof covers this ambiguity together with a
       warm reused Go path

## Regressions to preserve

8. Internal `local` and `wifi` values still render one WiFi badge class
   - Sender raw transport may be `local` while receiver raw transport may be
     `wifi` for a true local-path message.
   - Expected observable result:
     - both rows still show the same WiFi badge class
   - Current evidence:
     - `test/features/conversation/presentation/widgets/letter_card_test.dart`

9. Receiver-side duplicate upgrade remains intact
   - Receiver first stores a relay/direct copy and later receives the same
     message ID through the local WiFi path.
   - Expected observable result:
     - receiver upgrades the visible badge class to WiFi
     - receiver does not create a second visible message row
   - Current evidence:
     - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
     - `test/features/conversation/application/chat_message_listener_test.dart`

10. Legacy `reuse` rows remain renderable
    - Older rows still contain `reuse`.
    - Expected observable result:
      - those rows keep the existing direct-like badge class until a separate
        migration or aging decision exists
    - Current evidence:
      - `test/features/conversation/presentation/widgets/letter_card_test.dart`

## Bug regression

11. Reused Go send must not masquerade as WiFi just because the peer is local
    - A previously established Go connection exists.
    - Local discovery later marks the peer local.
    - The next message uses the already-connected reuse fast path.
    - Expected observable result:
      - if the actual send path is Go `direct` or Go `relay`, neither side
        shows the WiFi badge class for that message
      - a sender WiFi badge class must mean the message actually used the local
        WiFi send path
    - Current evidence:
      - no current regression test covers this exact case
      - an existing sender unit test currently expects the opposite behavior
