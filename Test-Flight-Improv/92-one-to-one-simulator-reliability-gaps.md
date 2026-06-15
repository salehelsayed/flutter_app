# 1. Title and Type

- Title: 1:1 simulator reliability proof gaps
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/92-one-to-one-simulator-reliability-gaps.md`

# 2. Problem Statement

Users need 1:1 chat reliability to be proven in device-context journeys, not
only through host-side or isolated integration tests. The current simulator
coverage exercises many important 1:1 paths, but several receiver-visible
outcomes are still accepted as pending, best-effort, or indirectly covered.

That creates uncertainty around the exact user-visible result after offline
inbox recovery, lifecycle interruptions, message deletion, media/voice delivery,
edits, local-only deletes, and notification/read-state flows. From a user's
perspective, these are the moments where the app can look successful on one
device while the other device does not show the expected conversation state.

# 3. Impact Analysis

- Affected users: people relying on 1:1 chat across mobile lifecycle changes,
  offline periods, media/voice sending, message edits, deletes, and notification
  entry points.
- When it appears: most likely during simulator-relevant device contexts such as
  app restart, node restart, inbox drain, foreground/background transitions,
  notification routing, and receiver-side media handling.
- Severity: medium for test confidence, high if one of these weakly asserted
  paths hides a real delivery or state-sync regression.
- Frequency: repo evidence does not prove a production frequency. The issue is
  that current automated evidence leaves some receiver-visible outcomes only
  partially proven.
- Confusion cost: users may see a send, delete, edit, notification, or media
  event complete on one side while the other side does not visibly converge.

# 4. Current State

- `integration_test/scripts/run_routing_smoke_e2e.dart` is the main
  two-simulator 1:1 and group smoke orchestrator. It already covers 1:1 cold
  send, warm send, offline inbox, reconnect, bidirectional messaging, stale
  connection recovery, all-paths-fail, lifecycle, batch inbox, delete, ACK under
  load, voice/media upload, larger media transfer, local WiFi, relay probe,
  restart, background/foreground, and relay failover.
- In the offline inbox scenario, the orchestrator records Bob's receive timing
  but passes on Alice's inbox store success even if Bob's drain is still pending:
  `integration_test/scripts/run_routing_smoke_e2e.dart`.
- In the batch inbox scenario, the orchestrator passes when Alice stores all
  five messages. Bob's receive side is described as async, and the Bob harness
  treats message receipt as best-effort:
  `integration_test/scripts/run_routing_smoke_e2e.dart` and
  `integration_test/routing_smoke_bob_harness.dart`.
- In the full lifecycle scenario, Bob can record the offline inbox message as
  pending and the orchestrator still passes on timeline length:
  `integration_test/routing_smoke_bob_harness.dart` and
  `integration_test/scripts/run_routing_smoke_e2e.dart`.
- In the delete-for-everyone scenario, Bob confirms that the original message
  arrived, while the harness comments that it does not yet assert the deletion
  tombstone or deleted state: `integration_test/routing_smoke_bob_harness.dart`.
- In voice/media simulator smoke, Alice-side upload metrics are checked, but the
  Bob harness does not assert the Dart-side receiver-visible media or voice
  state: `integration_test/scripts/run_routing_smoke_e2e.dart` and
  `integration_test/routing_smoke_bob_harness.dart`.
- The coverage audit records several adjacent but not direct 1:1 proofs:
  - voice send/receive and source loading exist, but no audible two-peer
    playback proof: `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
  - sender edit, receiver same-ID edit apply, and edited indicator exist
    separately, but no two-user edit roundtrip exists.
  - local-only delete exists, but no explicit unaffected-recipient assertion
    exists.
  - multiple notifications, multiple senders, read badges, and Feed readback
    are covered in pieces, but some combined device-context paths remain thin.
- The Report 50 TODO is closed and says there are no still-open blockers for
  that rollout. It also keeps residual-only stronger-evidence items around Feed
  unread UX, voice/media/device-specific confidence, and long-tail lifecycle or
  transport paths: `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`.

# 5. Scope Clarification

In scope:

- Receiver-visible 1:1 simulator confidence for offline inbox recovery.
- Receiver-visible 1:1 simulator confidence for batch inbox drain.
- Receiver-visible 1:1 simulator confidence for lifecycle inbox recovery.
- Receiver-visible 1:1 simulator confidence for delete-for-everyone.
- Receiver-visible 1:1 simulator confidence for media and voice messages.
- Two-user observable proof for edit-message and local-only delete behavior.
- Combined notification/read-state simulator confidence where current evidence
  is split across smaller tests.

Non-goals:

- This spec does not change product behavior.
- This spec does not reopen Report 50 as a product blocker.
- This spec does not require camera automation.
- This spec does not require real-device or manual audio verification.
- This spec does not define implementation seams, file ownership, or rollout
  sessions.
- This spec does not replace the existing host-side 1:1 Reliability Gate.

Accepted ambiguities for a later implementation pass:

- Whether voice acceptance should prove playable audio bytes, audio-player
  readiness, or both.
- Whether notification/read-state acceptance should focus on local notification
  injection, foreground notification handling, or post-open conversation state.
- Whether simulator media acceptance should require opening a viewer, proving
  local hydrated metadata, or proving successful download availability.

# 6. Test Cases

## Happy Path

- Offline inbox recovery reaches the receiver conversation:
  - Given Alice sends a 1:1 message while Bob is offline, when Bob returns and
    the app completes recovery, Bob's conversation shows that exact message once.
  - Required acceptance evidence: simulator.
  - Existing partial coverage: current offline inbox smoke records Alice's inbox
    store and may record Bob receive timing, but does not require Bob-visible
    delivery.

- Batch offline inbox recovery reaches the receiver conversation:
  - Given Alice sends five 1:1 messages while Bob is offline, when Bob returns,
    Bob's conversation shows all five messages, in order, with no duplicates.
  - Required acceptance evidence: simulator.
  - Existing partial coverage: current batch inbox smoke requires Alice to store
    five messages but treats Bob receipt as best-effort.

- Lifecycle inbox recovery has no pending receiver entry:
  - Given Alice sends a 1:1 message during a lifecycle interruption, when Bob
    restarts or resumes and recovery finishes, the receiver conversation shows
    the message and the journey has no pending receiver-visible entry.
  - Required acceptance evidence: simulator.
  - Existing partial coverage: current lifecycle smoke allows the inbox message
    to remain pending.

- Delete-for-everyone converges on both devices:
  - Given Alice sends a message and deletes it for everyone, Bob's conversation
    visibly reflects the deleted/tombstone state for that same message.
  - Required acceptance evidence: simulator and integration.
  - Existing partial coverage: host-side delete roundtrip exists; current
    simulator smoke only confirms the original message and Alice's delete send.

- Media and voice messages are receiver-visible:
  - Given Alice sends image/video/voice 1:1 content, Bob's conversation shows the
    expected attachment or voice item with receiver-side content available for
    normal interaction.
  - Required acceptance evidence: simulator.
  - Existing partial coverage: host-side media and voice tests exist; current
    simulator smoke mostly checks Alice upload metrics.

## Edge Cases

- Two-user edit roundtrip:
  - Given Alice edits a previously delivered 1:1 message, Bob's conversation
    shows the edited text for the same message identity and exposes the edited
    state expected by the product.
  - Required acceptance evidence: integration or simulator.
  - Existing partial coverage: sender edit, receiver apply, and edited indicator
    are covered separately, but not as a two-user roundtrip.

- Local-only delete leaves the recipient untouched:
  - Given Alice deletes a 1:1 message locally only, Bob's conversation still
    shows the original message unchanged.
  - Required acceptance evidence: integration or simulator.
  - Existing partial coverage: local delete behavior exists, but the unaffected
    recipient outcome is not directly asserted.

- Multiple notification messages open the correct conversation state:
  - Given multiple 1:1 messages arrive before the user opens from notification,
    the opened conversation shows the relevant unread messages and does not lose
    or duplicate them.
  - Required acceptance evidence: simulator.
  - Existing partial coverage: notification routing and Feed unread behavior are
    covered separately.

- Multiple senders remain isolated:
  - Given messages arrive from two different 1:1 senders, the app preserves the
    correct conversation targets, unread counts, and per-sender message bodies
    after notification or Feed entry.
  - Required acceptance evidence: simulator or smoke.
  - Existing partial coverage: separate sender routes and Feed unread cards are
    covered in split tests.

- Read state converges after conversation open:
  - Given a user opens a 1:1 conversation with unread messages and later returns
    to the Feed or Orbit surface, the unread badge and preview state reflect the
    read conversation.
  - Required acceptance evidence: integration or simulator.
  - Existing partial coverage: read-state rules exist, but the direct device
    walkthrough is weak.

## Regressions To Preserve

- Existing successful 1:1 sends continue to show up on the receiver side during
  cold send, warm send, reconnect, bidirectional send, stale connection recovery,
  ACK-under-load, local WiFi, relay probe, restart, and background/foreground
  journeys.
- Existing sender-side inbox-store proof remains valid where the product
  contract only requires delivery to the inbox.
- Existing host-side 1:1 reliability tests continue to protect send/receive,
  offline inbox, media, voice, incomplete upload retry, send-then-lock, stuck
  sending recovery, and quote/reply behavior.
- Existing notification routing remains conversation-targeted according to the
  accepted product contract, not Feed-expanded-card targeted.
- Existing Report 50 closure remains valid unless one of these receiver-visible
  outcomes becomes a real regression or the product contract changes.
