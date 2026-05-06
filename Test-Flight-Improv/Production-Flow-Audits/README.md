# Production Flow Audits

State for the **production-flow-integrity-auditor** agent. The agent traces
user-facing flows through the *production* codebase (not tests) to find
places where the wiring breaks in ways the user feels but tests don't catch.

## Files

- **`flows.md`** — The registry of flows you want audited. You curate this.
  Add a new block whenever a new user-facing path crosses a boundary worth
  watching (OS callback, native ↔ Dart channel, push, deep link, background
  task, file picker, biometrics, etc.). The agent only audits flows listed
  here.

- **`ledger.md`** — The agent's per-flow audit state. One row per flow:
  last-audited commit SHA, last-audited date, status, link to the latest
  findings file. The agent reads this on entry, decides what to audit /
  re-audit / skip, and writes back when done.

- **`findings/<flow-slug>-<date>.md`** — One file per audit run that found
  something. Each finding inside is a YAML block with id, severity,
  what-user-sees, chain-break-at, suggested fix, status.

## Triage workflow

1. Run the agent.
2. Open new / updated findings files under `findings/`.
3. For each finding, decide and edit `status:` directly:
   - `triaged` — you've read it, doing nothing yet
   - `in-progress` — work has started
   - `fixed` — verified resolved
   - `wont-fix` — accepted as-is, with a one-line rationale appended
   - `duplicate-of: <id>` — points to another finding
4. The agent never overwrites a status you've set. On its next run, it
   re-checks `open` and `triaged` findings against the current code; if a
   finding is no longer reproducible it adds a `now-clean` marker; if a
   `fixed` flow regresses it appends a `regressed` finding with a new id.

## Re-audit rules (for the agent)

- `not-yet-audited` flows → audit.
- Flow's last-audited SHA differs from `HEAD`, AND any file the flow
  touches has changed since → re-audit.
- Otherwise → skip.
- User can force re-audit by deleting the row, editing `Last audited (SHA)`
  to `—`, or invoking the agent with `--force <flow-name>`.

## Candidate messaging flows (pick which to register)

Shortlist of high-value 1:1 and group-chat flows not yet in `flows.md`.
Each entry: slug, what the user does → expects, the boundary that makes
this worth tracing, and the silent-break risk. Promote the ones you want
into `flows.md` with full origin/destination/boundary blocks.

### 1:1 chat

1. **`chat-send-direct-online`** — User taps send in `ConversationWired` →
   peer sees the letter card live within ~1s.
   *Boundary:* Dart encrypt (ML-KEM/AES-GCM) → Go bridge → libp2p stream →
   peer's `ChatMessageListener` → DB → UI stream.
   *Risk:* v2 envelope mismatch, missing ML-KEM key on contact, listener
   filter drops `isIncoming` wrong, stream not broadcast.

2. **`chat-receive-while-backgrounded`** — Peer is backgrounded when a 1:1
   message arrives → notification fires → on resume the message is in the
   conversation (no duplicates, no missing).
   *Boundary:* libp2p inbox → `flutter_notification_service` → OS notif →
   app resume → `drainOfflineInbox` → DB → stream.
   *Risk:* drain ordering vs live listener, double-insert, lost message if
   drain runs before listeners attach.

3. **`chat-receive-cold-start`** — App killed, peer sends 3 messages, user
   relaunches → all 3 appear in order in the right thread.
   *Boundary:* cold start → DI chain init → P2PService start →
   `drainOfflineInbox` (guarded by `isStarted`) → listeners → UI.
   *Risk:* drain before `isStarted` flips, duplicate inserts on relaunch,
   ordering across inbox vs live stream.

4. **`contact-request-handshake-to-first-message`** — A scans B's QR →
   contact request sent → B accepts → A can send and B receives.
   *Boundary:* QR scan → contact request payload (carries ML-KEM pub) →
   accept → both DBs updated → first encrypt round-trip.
   *Risk:* missing `mlkem` field on either side falls back to v1
   plaintext silently, accept without ML-KEM persistence.

5. **`chat-notification-tap-during-locked-device`** — Android phone is
   locked, notification arrives, user unlocks → taps → lands on the right
   thread without re-routing or duplicate route.
   *Boundary:* notification PendingIntent → `MainActivity.onNewIntent` →
   plugin → Dart route handler with lock-window gating.
   *Risk:* `onNewIntent` not overridden (the bug you just fixed),
   lock-window race re-routes after unlock, `_initialPayloadConsumed`
   double-fires.

### Group chat

6. **`group-message-send-receive-live`** — User in group taps send → all
   online members see the message via GossipSub within ~1s.
   *Boundary:* Dart encrypt (v3) → Go `topic.Publish` (`WithFloodPublish`)
   → mesh → remote `GroupMessageListener` → decrypt → DB → UI stream.
   *Risk:* `Publish` returns nil but no peers in mesh, both peers connected
   to relay but not to each other, `group:publish_debug` shows zero peers.

7. **`group-rejoin-on-app-restart`** — User is in 3 active groups, kills
   the app, relaunches → all 3 groups resume receiving live messages
   without re-invitation.
   *Boundary:* cold start → `rejoinGroupTopics` use case →
   `callGroupJoinWithConfig` per group → pubsub re-subscribe → discovery
   loop → mesh formation.
   *Risk:* rejoin fires before bridge ready, one group's failure aborts
   the loop, discovery loop never registers because relay not ready.

8. **`group-invite-accept-to-first-receive`** — User receives a group
   invite via P2P inbox → accepts → joins topic → sees their first live
   group message and any backfilled history.
   *Boundary:* P2P inbox relay (store-and-forward) → invite payload →
   accept → `callGroupJoinWithConfig` → rendezvous register → discover +
   `DialPeerViaRelay` → first GossipSub message.
   *Risk:* accept persists but join not called, rendezvous namespace
   mismatch, dial-via-relay fails silently.

9. **`group-notification-tap-route`** — Group message notification arrives
   → user taps → lands on the *group* conversation (not a 1:1 thread for
   the sender).
   *Boundary:* `GroupMessageListener` → notification with
   `NotificationRouteTarget` (group variant) → tap → `onNewIntent` →
   `_handleNotificationRouteTarget` → `GroupConversationWired`.
   *Risk:* payload serialization confuses group vs 1:1, route handler
   falls through to 1:1 path, group tracker key (`'group:$groupId'`)
   mismatch suppresses or duplicates notif.

10. **`group-peer-discovery-via-relay`** — Two members on different
    networks both join a group → become reachable to each other via
    circuit relay → GossipSub mesh forms → messages flow both ways.
    *Boundary:* `groupPeerDiscoveryLoop` → relayReady gate → rendezvous
    register on `/mknoon/group/<groupId>` → discover → `DialPeerViaRelay`
    → libp2p connection → mesh.
    *Risk:* relay never ready, discovery loop runs once and stops, dial
    succeeds but mesh never includes the peer (publish reaches no one).

### Notifications

These traverse the local-notification plugin, the remote push pipeline
(FCM/APNs), and the suppression/dedup logic that decides whether to
post at all. Many of these are exactly the kinds of "fires in test,
silent on hardware" flows the auditor is built for.

1. **`notification-permission-request-on-first-launch`** — Fresh install →
    first launch → user prompted for notification permission → choice is
    persisted and registration proceeds (or is skipped) accordingly.
    *Boundary:* `requestPushPermissionUseCase` → OS permission dialog
    (UNUserNotificationCenter / NotificationManager) → result →
    `pushRegistrationCoordinator` → token store.
    *Risk:* permission granted but registration never runs, denial leaves
    coordinator in a retry loop, iOS provisional vs full silently mixed.

2. **`push-token-register-on-launch`** — App starts → FCM/APNs token
    obtained → registered with the relay/server → token persisted to
    `PushTokenStore` so it isn't re-registered every launch.
    *Boundary:* native push registration callback → `registerPushTokenUseCase`
    → bridge → server → `PushTokenStoreImpl`.
    *Risk:* token rotates and old token still on server, register fires
    before bridge ready, store write fails and re-registers every launch.

3. **`remote-push-foreground-receive`** — Push arrives while app is in the
    foreground → no system banner, but the message lands in the
    conversation immediately (no duplicate when live P2P also delivers).
    *Boundary:* OS push → `handleForegroundRemoteMessageUseCase` →
    `recentRemoteNotificationGate` (dedup) → DB → UI stream.
    *Risk:* dedup gate keyed wrong → duplicate cards, gate too strict →
    legitimate second message dropped.

4. **`remote-push-background-receive-and-post`** — Push arrives while app
    is backgrounded → background handler decrypts preview → local
    notification posts with sender + content (or fallback if decrypt
    fails).
    *Boundary:* OS push → `backgroundMessageHandler` (isolate) →
    `pushDecryptPreview` → `showNotificationUseCase` →
    `flutter_local_notifications` → OS tray.
    *Risk:* background isolate has no DI / no ML-KEM key → decrypt fails
    silently → `backgroundPushNotificationFallback` posts a generic
    "New message" forever.

5. **`notification-suppress-while-viewing-thread`** — User has thread X
    open → message for X arrives → no notification fires; message for Y
    in same window → notification fires for Y only.
    *Boundary:* incoming message → listener → `activeConversationTracker`
    check → `showNotificationUseCase` early-returns or proceeds.
    *Risk:* tracker key mismatch (`'group:$id'` vs `id`), tracker not
    cleared on screen pop → stale suppression for hours.

6. **`notification-tap-cold-start-initial-payload`** — App killed →
    notification arrives → user taps → app cold-starts and lands directly
    on the right thread without showing feed first or double-routing.
    *Boundary:* OS launch with intent → plugin `getNotificationAppLaunchDetails`
    → `_initialPayloadConsumed` flag → `handleInitialRemoteMessageUseCase`
    → `_handleNotificationRouteTarget`.
    *Risk:* initial payload consumed twice (once in launch handler, once
    in `onNewIntent`), or feed flashes before route, or payload shape
    differs from warm-tap path.

7. **`group-notification-route-resolution`** — Group message arrives →
    notification payload must carry group identity (not sender's 1:1
    identity) → tap routes to `GroupConversationWired` for the right
    group.
    *Boundary:* `GroupMessageListener` → `resolveGroupNotificationRouteTargetUseCase`
    → `NotificationRouteTarget.toPayload` (group variant) → tray → tap →
    `fromPayload` round-trip → group route.
    *Risk:* group target serialized as 1:1 (sender peer) → tap opens
    wrong screen, group id null → falls through to feed.

8. **`notification-clear-on-thread-open`** — User taps a notification or
    just opens the thread manually → all pending notifications for that
    thread are cleared from the tray (no stale notifications after
    reading).
    *Boundary:* conversation screen `initState` /
    `activeConversationTracker` set → notification cancel call →
    `flutter_local_notifications.cancel(id)` per pending notif for that
    peer/group.
    *Risk:* cancel is keyed by an id the post-side didn't use → tray
    keeps notifications forever, or cancels everything (clears
    notifications for *other* threads too).

9. **`notification-dedup-across-push-and-p2p`** — Same logical message
    arrives via both remote push and live P2P (race) → user sees one
    notification and one message, not two.
    *Boundary:* `recentBackgroundNotificationGate` /
    `recentRemoteNotificationGate` keyed by message id / sender+timestamp
    → either side defers if the other already handled it.
    *Risk:* gate TTL too short → both fire, gate too long → second real
    message suppressed, gate keys differ between paths.

10. **`drain-on-resume-without-spam-notifying`** — App resumes after
    being backgrounded for hours → `drainOfflineInbox` pulls 50 queued
    messages → user sees them in the threads but does NOT get 50
    individual banner notifications for messages that are now already
    visible in the UI.
    *Boundary:* app lifecycle resume → `drainOfflineInbox` (guarded by
    `isStarted`) → listeners → `activeConversationTracker` /
    foreground-app check inside `showNotificationUseCase`.
    *Risk:* drain treats every drained message as "new background" and
    posts a notification for each, OR drain runs before listeners attach
    and messages are lost.
