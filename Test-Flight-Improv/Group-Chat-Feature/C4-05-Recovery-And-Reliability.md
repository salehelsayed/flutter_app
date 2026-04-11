# C4 Model: Recovery & Reliability

> Standalone C4 architecture document for the **Recovery & Reliability** action in the Group Messaging feature.

---

## Level 1: System Context

```
+------------------+          +---------------------------+
|   Group Member   |          |   mknoon Mobile App       |
|   (Person)       |<---------|   (Software System)       |
|                  | catches  |                           |
+------------------+   up     +---------------------------+
                                     |            |
                                     | drain      | rejoin / publish
                                     v            v
                              +----------------+ +-----------+
                              | Relay Server   | | libp2p    |
                              | Group Inbox    | | GossipSub |
                              | (Ext Sys)      | | (Ext Sys) |
                              +----------------+ +-----------+
```

### Actors & Systems

| Element | Type | Description |
|---------|------|-------------|
| Group Member | Person | User who was offline, backgrounded, or affected by a node/relay recovery and needs the discussion thread to converge again |
| mknoon Mobile App | Software System | Rejoins group topics, drains relay-backed backlog, retries failed group work, and keeps local SQLCipher state consistent with replayed traffic |
| Relay Server Group Inbox | External System | Store-and-forward group inbox on the relay path. In this repo, the relay server code defaults group inbox TTL to 7 days, the app also ignores non-system backlog older than 7 days during replay, and relay-server tests cover shared-backend cursor continuation across relay instances |
| libp2p GossipSub | External System | Real-time group topic mesh used for live discussion delivery; topics are rejoined on cold start, foreground resume, and retrier-driven continuity recovery after in-place or watchdog relay recovery |

### Recovery Scenarios

1. **Cold Start After Node Start**: `StartupRouter._doStartP2P()` fire-and-forget rejoin runs after `startP2PNode()` succeeds; backlog drain follows when `groupMessageRepository` is available
2. **Foreground Resume**: `handleAppResumed()` rechecks bridge/P2P health, drains the 1:1 inbox, then performs group rejoin + optional recovery acknowledgement + drain and follow-on retries
3. **Relay Recovery / Watchdog Restart**: Flutter rejoins topics after in-place or watchdog relay recovery; Go sets `needsGroupRecovery` when watchdog/full-restart recovery requires topic rejoin, and Flutter conditionally acknowledges it after a clean rejoin
4. **Stuck / Failed Outgoing Group Messages**: paused/hidden lifecycle handling and the 30-second stuck-sending sweep both move outbound rows into the retry path, and retryable `status='failed'` rows are retried in place when prerequisites still exist
5. **Failed Inbox Stores / Incomplete Uploads**: relay inbox store retries and media re-upload retries repair partially completed outbound work
6. **Scoped Single-Group Catch-Up**: `drainGroupOfflineInboxForGroup()` is used when only one discussion needs replay, such as notification-open prep and accepted group invites

---

## Level 2: Container

```
+------------------------------------------------------------------------+
|                          mknoon Mobile App                             |
|                                                                        |
|  +--------------------------+  +----------------------+  +-----------+  |
|  | StartupRouter /          |->| Dart Recovery        |->| Go Native |  |
|  | AppLifecycle /           |  | Orchestrators +      |  | Bridge    |  |
|  | PendingMessageRetrier    |  | Group Use Cases      |  |           |  |
|  +--------------------------+  +----------------------+  +-----------+  |
|                                   |             |             |         |
|                                   v             v             v         |
|                            +-----------+  +-------------+  +---------+  |
|                            | SQLCipher |  | GroupMsg    |  | Relay   |  |
|                            | DB        |  | Listener    |  | Server  |  |
|                            | (state)   |  | (replay)    |  | (inbox) |  |
|                            +-----------+  +-------------+  +---------+  |
+------------------------------------------------------------------------+
```

### Containers

| Container | Technology | Responsibility |
|-----------|------------|----------------|
| StartupRouter / AppLifecycle / PendingMessageRetrier | Dart / Flutter | Triggers group recovery from three entry points: startup does rejoin + optional drain only, resume does rejoin/drain plus follow-on retries, and `PendingMessageRetrier` runs both a gated continuity sweep (rejoin + drain) and a separate full retry pass. AppLifecycle also uses paused/hidden handling to transition in-flight group sends to `failed` before suspension. Separate scoped callers use `drainGroupOfflineInboxForGroup()` for one-group catch-up |
| P2PService / NodeState | Dart | In-memory source of truth for `needsGroupRecovery`, `lastRecoveryMethod`, `relayState`, and relay-health-derived continuity decisions |
| Dart Recovery Orchestrators + Group Use Cases | Dart | `handleAppResumed()` and `PendingMessageRetrier` order `rejoinGroupTopics()`, `drainGroupOfflineInbox()`, `recoverStuckSendingGroupMessages()`, `retryIncompleteGroupUploads()`, `retryFailedGroupMessages()`, and `retryFailedGroupInboxStores()`. `handleAppPaused()` pre-commits group `sending` rows to `failed` so later recovery can pick them up |
| Go Native Bridge | Go / gomobile | Executes `group:join`, `group:publish`, `group:inboxStore`, `group:inboxRetrieveCursor`, and `group:acknowledgeRecovery` against the running Go node |
| SQLCipher DB | SQLite + SQLCipher | Source of truth for group membership, message rows, retry payloads, attachment retry counters, and backlog retention metadata. Relay session state is not stored here |
| GroupMessageListener | Dart | Replays regular and system envelopes through the live listener path so replayed messages hit the same persistence, dedupe, and side-effect code as live traffic |
| Relay Server | External | Stores group inbox backlog and serves cursor-paginated non-destructive reads over the relay path. In this repo, both the relay server backlog TTL and the client's replay cutoff use 7-day windows |

---

## Level 3: Component

### Recovery Pipeline

```
+------------------------------------------------------------------------+
|                    Group Recovery Entry Points                         |
|                                                                        |
|  StartupRouter._doStartP2P()                                           |
|  handleAppResumed()                                                    |
|  PendingMessageRetrier (_runGroupContinuitySweepIfNeeded / _retryIfNeeded)
|       |                                                                |
|       v                                                                |
|  resume/retrier derive reason from needsGroupRecovery +               |
|  lastRecoveryMethod; startup uses RejoinReason.startup               |
|       |                                                                |
|       v                                                                |
|  +---------------------------+                                         |
|  | runWithGroupRecoveryGate  |  <-- activity marker used by startup,   |
|  | isGroupRecoveryInProgress |      the resume branch with group drain,|
|  +---------------------------+      and retrier continuity sweep scopes |
|       |                                                                |
|       v                                                                |
|  +------+                                                              |
|  |rejoin|                                                              |
|  |Topics|                                                              |
|  +------+                                                              |
|       |                                                                |
|       v                                                                |
|  +---------------------------+                                         |
|  | acknowledgeRecovery()     |  <-- only when Go requested recovery    |
|  |                           |      and rejoin finished with 0 errors   |
|  +---------------------------+                                         |
|       |                                                                |
|       v                                                                |
|  +------+                                                              |
|  |drain |  <-- groups drained in parallel via Future.wait; reactions   |
|  |Inbox |      are handled before listener replay                      |
|  +------+                                                              |
|       |                                                                |
|       v                                                                |
|  +------+  +------+  +------+      ...      +-----------------------+  |
|  |recover|  |retry |  |retry |               | retryFailedGroup     |  |
|  |Stuck  |  |Upload|  |Failed|               | InboxStores          |  |
|  |Sends  |  |s     |  |Msgs  |               +-----------------------+  |
|  +------+  +------+  +------+                                        |
|                                                                        |
|  Fault isolation comes from caller try/catch blocks; re-entry         |
|  suppression comes from _isResuming / _isRetrying /                   |
|  _isGroupContinuitySweeping / external-recovery guards, not from      |
|  GroupRecoveryGate itself                                             |
+------------------------------------------------------------------------+
```

### Components

| Component | File | Responsibility |
|-----------|------|----------------|
| `StartupRouter._doStartP2P()` | `lib/features/identity/presentation/startup_router.dart` | After `startP2PNode()` succeeds, fire-and-forget wraps startup group rejoin and optional backlog drain in `runWithGroupRecoveryGate()` |
| `handleAppResumed()` | `lib/core/lifecycle/handle_app_resumed.dart` | Foreground resume recovery: bridge health check, P2P health check, 1:1 drain, then group rejoin/ack/drain when both repos exist, or rejoin/ack without `GroupRecoveryGate` when only `groupRepo` exists, followed by retry steps when resume recovery is enabled |
| `handleAppPaused()` | `lib/core/lifecycle/handle_app_paused.dart` | Preventive reliability hook for `paused` / `hidden`: transitions local group `sending` rows to `failed` before the OS suspends the app |
| `PendingMessageRetrier` | `lib/core/services/pending_message_retrier.dart` | Already-online timer bootstrap, online-transition debounce, periodic retry timer, periodic continuity sweep timer, immediate `needsGroupRecovery` sweep, strict retry ordering, optional recovery acknowledgement, and skip behavior while an external resume recovery is already active |
| `GroupRecoveryGate` | `lib/features/groups/application/group_recovery_gate.dart` | Re-entrant activity counter (`_activeDepth`) exposed through `isGroupRecoveryInProgress()`. It marks active recovery scopes but does not itself reject or serialize concurrent callers; downstream use cases read the flag to reject membership mutations, metadata updates, and announcement sends during active recovery |
| `rejoinGroupTopics()` | `lib/features/groups/application/rejoin_group_topics_use_case.dart` | Iterates all groups, skips dissolved groups and groups without a stored key, builds `groupConfig`, and calls `callGroupJoinWithConfig()` per group |
| `drainGroupOfflineInbox()` | `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` | Drains all groups in parallel with cursor pagination, applies the 7-day client-side backlog retention cutoff, persists expired/retained backlog timestamps on `GroupModel`, routes `group_reaction` payloads directly when `reactionRepo` is available, and replays system/regular envelopes through `GroupMessageListener` when available; without a listener, all remaining payloads fall back to `handleIncomingGroupMessage()`, so system side effects are not replayed |
| `retryFailedGroupMessages()` | `lib/features/groups/application/retry_failed_group_messages_use_case.dart` | Loads all failed outgoing rows, retries only supported candidates (text-only retry payloads or media rows with persisted `downloadStatus == 'done'` attachments), and skips unsupported rows in place |
| `recoverStuckSendingGroupMessages()` | `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart` | Marks outgoing `status='sending'` rows older than 30 seconds as `failed` so later retry steps can pick them up |
| `retryFailedGroupInboxStores()` | `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart` | Loads rows with `inbox_stored=0` and cached `inbox_retry_payload`, retries relay store up to the use-case limit (default 20), then clears retry payload on success |
| `retryIncompleteGroupUploads()` | `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` | Loads `upload_pending` attachments from the shared media repository, groups them by message ID, uploads pending attachments in parallel per message, and re-sends only when the parent message still meets final-send preconditions |
| `callGroupInboxRetrieveWithCursor()` | `lib/core/bridge/bridge_group_helpers.dart` | Bridge helper for typed cursor-based inbox retrieval; throws on bridge error and returns `GroupInboxPage(messages, cursor)` |
| `callGroupAcknowledgeRecovery()` | `lib/core/bridge/bridge_group_helpers.dart` | Bridge helper that clears Go's pending `needsGroupRecovery` flag after Flutter successfully rejoined topics |
| `GroupMessageListener.handleReplayEnvelope()` | `lib/features/groups/application/group_message_listener.dart` | Replays regular and system envelopes through the same live listener path; reaction payloads are handled earlier by `handleIncomingGroupReaction()` |

### Recovery Sequence Diagram

```
StartupRouter._doStartP2P()
  |
  +--> startP2PNode()
  +--> if success:
         runWithGroupRecoveryGate(() async {
           await rejoinGroupTopics(
             bridge: widget.bridge,
             groupRepo: groupRepo,
           );
           if (groupMsgRepo != null) {
             await drainGroupOfflineInbox(...);
           }
         })

WidgetsBindingObserver.didChangeAppLifecycleState(resumed)
  |
  +--> _MyAppState._onResumed()
         if (_isResuming) return
         _isResuming = true
         await handleAppResumed(...)
           await bridge.checkHealth()
           if unhealthy -> bridge.reinitialize()
           await p2pService.performImmediateHealthCheck()
           await p2pService.drainOfflineInbox()   // 1:1 inbox, not group inbox

           if (enableResumeGroupRecovery &&
               groupRepo != null &&
               groupMsgRepo != null) {
             await runWithGroupRecoveryGate(() async {
               needsGroupRecovery =
                   p2pService.currentState.needsGroupRecovery ?? false
               reason = needsGroupRecovery
                   ? RejoinReason.nodeRequestedRecovery
                   : p2pService.lastRecoveryMethod == 'watchdog_restart'
                       ? RejoinReason.watchdogRestart
                       : RejoinReason.inPlaceRecovery

               rejoinResult = await rejoinGroupTopics(reason: reason)

               if (needsGroupRecovery && rejoinResult.errorCount == 0) {
                 await callGroupAcknowledgeRecovery(bridge)
               }

               await drainGroupOfflineInbox(...)
             })
           } else if (enableResumeGroupRecovery && groupRepo != null) {
             // Rejoin + optional acknowledgement still run, but this branch is
             // not wrapped in GroupRecoveryGate and there is no group backlog
             // drain without groupMsgRepo.
           }

           await recoverStuckSendingGroupMessages()
           await retryIncompleteGroupUploads()
           await retryFailedGroupMessages()
           ... non-group retry steps omitted here ...
           await retryFailedGroupInboxStores()
         _isResuming = false

WidgetsBindingObserver.didChangeAppLifecycleState(paused/hidden)
  |
  +--> _MyAppState._onPaused()
         unawaited(handleAppPaused(...))
           await groupMsgRepo.transitionSendingToFailed()

PendingMessageRetrier.start()
  |
  +--> if already online when start() runs:
  |    _startOnlineTimers()
  |      debounce -> _retryIfNeeded()
  |      periodic retry timer -> _retryIfNeeded()
  |      periodic continuity timer -> _runGroupContinuitySweepIfNeeded()
  |
  +--> on online transition:
  |    _startOnlineTimers()
  |      debounce -> _retryIfNeeded()
  |      periodic retry timer -> _retryIfNeeded()
  |      periodic continuity timer -> _runGroupContinuitySweepIfNeeded()
  |
  +--> on needsGroupRecovery false->true while already online:
  |      unawaited(_runGroupContinuitySweepIfNeeded())
  |
  +--> _runGroupContinuitySweepIfNeeded()
  |      if (_isGroupContinuitySweeping || _isRetrying) return
  |      if (!_isGroupRecoveryEnabled()) return
  |      if (external recovery in progress) return
  |      await runWithGroupRecoveryGate(() async {
  |        await _runGroupRejoinIfNeeded()   // may acknowledge recovery
  |        await drainGroupOfflineInbox()
  |      })
  |
  +--> _retryIfNeeded()
         if (_isRetrying) return
         if (external recovery in progress) return
         await _runGroupRejoinIfNeeded()     // no GroupRecoveryGate wrapper here
         await drainGroupOfflineInbox()
         await recoverStuckSendingGroupMessages()
         await retryIncompleteGroupUploads()
         await retryFailedGroupMessages()
         ... non-group retry steps omitted here ...
         await retryFailedGroupInboxStores()
```

---

## Level 4: Code

### drainGroupOfflineInbox() Use Case

```dart
// lib/features/groups/application/drain_group_offline_inbox_use_case.dart

Future<void> drainGroupOfflineInbox({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  GroupMessageListener? groupMessageListener,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  final groups = await groupRepo.getAllGroups();

  await Future.wait(
    groups.map((group) async {
      await _drainGroupInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: group.id,
        mediaAttachmentRepo: mediaAttachmentRepo,
        reactionRepo: reactionRepo,
        groupMessageListener: groupMessageListener,
        drainAllPages: drainAllPages,
        pageSize: pageSize,
      );
    }),
  );
}

Future<void> _drainGroupInbox({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  GroupMessageListener? groupMessageListener,
  bool drainAllPages = true,
  int pageSize = 50,
}) async {
  final retentionCutoff = groupBacklogRetentionCutoff(DateTime.now().toUtc());
  String cursor = '';
  DateTime? latestExpiredBacklogAt;
  DateTime? latestRetainedBacklogAt;
  var sawTimestampedRetentionPayload = false;

  do {
    final result = await callGroupInboxRetrieveWithCursor(
      bridge,
      groupId,
      cursor,
      pageSize,
    );

    for (final msg in result.messages) {
      final payload = decodeInboxMessage(msg, groupId);
      final text = payload['text'] as String? ?? '';
      final timestamp =
          payload['timestamp'] as String? ??
          DateTime.now().toUtc().toIso8601String();
      final parsedTimestamp = _tryParseUtcTimestamp(timestamp);
      final isSystemPayload = text.startsWith('{"__sys":');

      if (!isSystemPayload && parsedTimestamp != null) {
        sawTimestampedRetentionPayload = true;
        if (parsedTimestamp.isBefore(retentionCutoff)) {
          latestExpiredBacklogAt = _latestTimestamp(
            latestExpiredBacklogAt,
            parsedTimestamp,
          );
          continue;
        }
        latestRetainedBacklogAt = _latestTimestamp(
          latestRetainedBacklogAt,
          parsedTimestamp,
        );
      }

      if (payload['type'] == 'group_reaction' && reactionRepo != null) {
        final reactionJson = payload['reaction'] as String? ?? '';
        if (reactionJson.isNotEmpty) {
          await handleIncomingGroupReaction(
            groupRepo: groupRepo,
            reactionRepo: reactionRepo,
            groupId: groupId,
            senderId:
                payload['senderId'] as String? ??
                (msg['from'] as String? ?? ''),
            reactionJson: reactionJson,
          );
        }
        continue;
      }

      final mediaRaw = payload['media'] as List<dynamic>?;
      final media = mediaRaw?.cast<Map<String, dynamic>>();
      final resolvedGroupId = payload['groupId'] as String? ?? groupId;
      final senderId =
          payload['senderId'] as String? ?? (msg['from'] as String? ?? '');
      final senderUsername = payload['senderUsername'] as String? ?? '';
      final keyEpoch = payload['keyEpoch'] as int? ?? 0;

      if (groupMessageListener != null && isSystemPayload) {
        await groupMessageListener.handleReplayEnvelope({
          'groupId': resolvedGroupId,
          'senderId': senderId,
          'senderUsername': senderUsername,
          'keyEpoch': keyEpoch,
          'text': text,
          'timestamp': timestamp,
          if (payload['messageId'] is String) 'messageId': payload['messageId'],
          if (payload['quotedMessageId'] is String)
            'quotedMessageId': payload['quotedMessageId'],
          if (media != null) 'media': media,
        });

        if (isSystemPayload &&
            await groupRepo.getGroup(resolvedGroupId) == null) {
          return; // system replay removed the group locally
        }
        continue;
      }

      if (groupMessageListener != null) {
        await groupMessageListener.handleReplayEnvelope({
          'groupId': resolvedGroupId,
          'senderId': senderId,
          'senderUsername': senderUsername,
          'keyEpoch': keyEpoch,
          'text': text,
          'timestamp': timestamp,
          if (payload['messageId'] is String) 'messageId': payload['messageId'],
          if (payload['quotedMessageId'] is String)
            'quotedMessageId': payload['quotedMessageId'],
          if (media != null) 'media': media,
        });
        continue;
      }

      // Without a listener, all remaining payloads fall back here.
      // That includes system payloads and, if reactionRepo is absent,
      // reaction payloads too.
      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: resolvedGroupId,
        senderId: senderId,
        senderUsername: senderUsername,
        keyEpoch: keyEpoch,
        text: text,
        timestamp: timestamp,
        messageId: payload['messageId'] as String?,
        quotedMessageId: payload['quotedMessageId'] as String?,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
    }

    cursor = result.cursor;
  } while (cursor.isNotEmpty && drainAllPages);

  await _persistRetentionState(
    groupRepo: groupRepo,
    groupId: groupId,
    sawTimestampedRetentionPayload: sawTimestampedRetentionPayload,
    latestExpiredBacklogAt: latestExpiredBacklogAt,
    latestRetainedBacklogAt: latestRetainedBacklogAt,
  );
}
```

### rejoinGroupTopics() Use Case

```dart
// lib/features/groups/application/rejoin_group_topics_use_case.dart

enum RejoinReason {
  startup,
  watchdogRestart,
  nodeRequestedRecovery,
  inPlaceRecovery,
}

class RejoinGroupTopicsResult {
  final int joinedGroupCount;
  final int skippedNoKeyCount;
  final int errorCount;
  final bool skipped;
  /* constructor omitted */
}

Future<RejoinGroupTopicsResult> rejoinGroupTopics({
  required Bridge bridge,
  required GroupRepository groupRepo,
  RejoinReason reason = RejoinReason.startup,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_REJOIN_TOPICS_BEGIN',
    details: {'reason': reason.name},
  );

  final groups = await groupRepo.getAllGroups();
  var joinedGroupCount = 0;
  var skippedNoKeyCount = 0;
  var errorCount = 0;

  for (final group in groups) {
    try {
      if (group.isDissolved) continue;

      final keyInfo = await groupRepo.getLatestKey(group.id);
      if (keyInfo == null) {
        skippedNoKeyCount++;
        continue;
      }

      final members = await groupRepo.getMembers(group.id);
      final groupConfig = buildGroupConfigPayload(group, members);

      await callGroupJoinWithConfig(
        bridge,
        groupId: group.id,
        groupConfig: groupConfig,
        groupKey: keyInfo.encryptedKey,
        keyEpoch: keyInfo.keyGeneration,
      );
      joinedGroupCount++;
    } catch (e) {
      errorCount++;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REJOIN_TOPICS_ERROR',
        details: {'groupId': group.id, 'error': e.toString()},
      );
    }
  }

  return RejoinGroupTopicsResult(
    joinedGroupCount: joinedGroupCount,
    skippedNoKeyCount: skippedNoKeyCount,
    errorCount: errorCount,
    skipped: false,
  );
}
```

### retryFailedGroupMessages() Use Case

```dart
// lib/features/groups/application/retry_failed_group_messages_use_case.dart

Future<int> retryFailedGroupMessages({
  required GroupMessageRepository groupMsgRepo,
  required GroupRepository groupRepo,
  required IdentityRepository identityRepo,
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_GROUP_MESSAGES_START',
    details: {},
  );

  final identity = await identityRepo.loadIdentity();
  if (identity == null) return 0;

  final failedMessages = await groupMsgRepo.getFailedOutgoingMessages();
  var successCount = 0;

  for (final msg in failedMessages) {
    final retryPayloadAvailable =
        (msg.inboxRetryPayload?.isNotEmpty ?? false) ||
        (msg.wireEnvelope?.isNotEmpty ?? false);
    final textOnlyRetry = _isTextOnlyRetryPayload(msg);
    final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
      msg.id,
    );

    List<MediaAttachment>? retryAttachments;
    if (textOnlyRetry) {
      retryAttachments = null;
    } else if (attachments.isNotEmpty &&
        attachments.every((a) => a.downloadStatus == 'done')) {
      retryAttachments = attachments;
    } else {
      // Unsupported rows stay failed in place:
      // - missing retry payload
      // - pending uploads still owned by retryIncompleteGroupUploads()
      // - missing/dangling media attachments
      if (!retryPayloadAvailable) {
        continue;
      }
      continue;
    }

    try {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
        groupId: msg.groupId,
        text: msg.text,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: msg.senderUsername ?? identity.username,
        messageId: msg.id,
        timestamp: msg.timestamp,
        quotedMessageId: msg.quotedMessageId,
        mediaAttachments: retryAttachments,
        mediaAttachmentRepo: mediaAttachmentRepo,
        emitTimingEvent: false,
      );

      if (result == SendGroupMessageResult.success ||
          result == SendGroupMessageResult.successNoPeers) {
        successCount++;
      }
    } catch (_) {
      // Non-fatal: continue to next message
    }
  }

  return successCount;
}
```

### recoverStuckSendingGroupMessages() Use Case

```dart
// lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart

const Duration kStuckSendingGroupThreshold = Duration(seconds: 30);

Future<int> recoverStuckSendingGroupMessages({
  required GroupMessageRepository groupMsgRepo,
  Duration threshold = kStuckSendingGroupThreshold,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'RECOVER_STUCK_SENDING_GROUP_START',
    details: {'thresholdSeconds': threshold.inSeconds},
  );

  final count = await groupMsgRepo.recoverStuckSendingMessages(
    olderThan: threshold,
  );

  emitFlowEvent(
    layer: 'FL',
    event: count > 0
        ? 'RECOVER_STUCK_SENDING_GROUP_RECOVERED'
        : 'RECOVER_STUCK_SENDING_GROUP_NONE',
    details: {'count': count},
  );

  return count;
}
```

### groupRecoveryGate

`GroupRecoveryGate` tracks whether a recovery scope is active. It does not, by itself, block or serialize concurrent callers.

```dart
// lib/features/groups/application/group_recovery_gate.dart

class GroupRecoveryGate {
  int _activeDepth = 0;

  bool get isActive => _activeDepth > 0;

  void begin() {
    _activeDepth += 1;
  }

  void end() {
    if (_activeDepth == 0) return;
    _activeDepth -= 1;
  }

  Future<T> run<T>(Future<T> Function() action) async {
    begin();
    try {
      return await action();
    } finally {
      end();
    }
  }

  void resetForTest() {
    _activeDepth = 0;
  }
}

final groupRecoveryGate = GroupRecoveryGate();

const groupRecoveryPendingError =
    'Group recovery is in progress. Try again after resync completes.';

bool isGroupRecoveryInProgress() => groupRecoveryGate.isActive;

Future<T> runWithGroupRecoveryGate<T>(Future<T> Function() action) {
  return groupRecoveryGate.run(action);
}
```

### callGroupInboxRetrieveWithCursor() Bridge Helper

```dart
// lib/core/bridge/bridge_group_helpers.dart

class GroupInboxPage {
  final List<Map<String, dynamic>> messages;
  final String cursor;
  const GroupInboxPage({required this.messages, required this.cursor});
}

Future<GroupInboxPage> callGroupInboxRetrieveWithCursor(
  Bridge bridge,
  String groupId,
  String cursor,
  int limit, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final request = {
    'cmd': 'group:inboxRetrieveCursor',
    'payload': {'groupId': groupId, 'cursor': cursor, 'limit': limit},
  };

  final responseJson = await bridge.send(jsonEncode(request)).timeout(timeout);
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  if (response['ok'] != true) {
    throw BridgeCommandException(
      'group:inboxRetrieveCursor',
      response['errorCode']?.toString() ?? 'UNKNOWN',
      response['errorMessage']?.toString(),
    );
  }

  final messages =
      (response['messages'] as List<dynamic>?)
          ?.map((m) => Map<String, dynamic>.from(m as Map))
          .toList() ??
      [];
  final nextCursor = response['cursor'] as String? ?? '';

  return GroupInboxPage(messages: messages, cursor: nextCursor);
}
```

### callGroupAcknowledgeRecovery() Bridge Helper

```dart
// lib/core/bridge/bridge_group_helpers.dart

Future<void> callGroupAcknowledgeRecovery(
  Bridge bridge, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final request = {
    'cmd': 'group:acknowledgeRecovery',
    'payload': <String, dynamic>{},
  };
  final responseJson = await bridge.send(jsonEncode(request)).timeout(timeout);
  final response = jsonDecode(responseJson) as Map<String, dynamic>;

  if (response['ok'] != true) {
    throw BridgeCommandException(
      'group:acknowledgeRecovery',
      response['errorCode']?.toString() ?? 'UNKNOWN',
      response['errorMessage']?.toString(),
    );
  }

  // Clears Go's pending needsGroupRecovery flag after Flutter has
  // successfully rejoined topics.
}
```

### App Lifecycle Wiring

```dart
// Group recovery is wired through three recovery entry points:
// 1. StartupRouter._doStartP2P() after node start succeeds
// 2. WidgetsBindingObserver.didChangeAppLifecycleState(resumed) -> _onResumed()
// 3. PendingMessageRetrier.start() for already-online timer bootstrap,
//    online transition, periodic retry, periodic continuity sweep,
//    and immediate needsGroupRecovery sweep
//
// A separate paused/hidden reliability hook transitions local 'sending' rows
// to 'failed' before process suspension.

// lib/main.dart
final pendingMessageRetrier = PendingMessageRetrier(
  p2pService: p2pService,
  messageRepo: messageRepository,
  identityRepo: repository,
  contactRepo: contactRepository,
  bridge: bridge,
  mediaAttachmentRepo: mediaAttachmentRepository,
  rejoinGroupTopicsWithRecoveryAckEligibilityFn: () async {
    final needsGroupRecovery =
        p2pService.currentState.needsGroupRecovery ?? false;
    final recoveryMethod = p2pService.lastRecoveryMethod;
    final reason = needsGroupRecovery
        ? RejoinReason.nodeRequestedRecovery
        : recoveryMethod == 'watchdog_restart'
            ? RejoinReason.watchdogRestart
            : RejoinReason.inPlaceRecovery;

    final rejoinResult = await rejoinGroupTopics(
      bridge: bridge,
      groupRepo: groupRepository,
      reason: reason,
    );

    return reason == RejoinReason.nodeRequestedRecovery &&
        rejoinResult.errorCount == 0;
  },
  acknowledgeGroupRecoveryFn: () => callGroupAcknowledgeRecovery(bridge),
  drainGroupOfflineInboxFn: () => drainGroupOfflineInbox(...),
  recoverStuckSendingGroupMessagesFn: () =>
      recoverStuckSendingGroupMessages(groupMsgRepo: groupMessageRepository),
  retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(...),
  retryFailedGroupMessagesFn: () => retryFailedGroupMessages(...),
  retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(...),
);

widget.pendingMessageRetrier.setExternalRecoveryInProgressProvider(
  () => _isResuming,
);

void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    _onResumed();
  }
  if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden) {
    _onPaused();
  }
}

void _onPaused() {
  unawaited(
    handleAppPaused(
      messageRepo: widget.messageRepository,
      groupMsgRepo: widget.groupMessageRepository,
    ),
  );
}

Future<void> _onResumed() async {
  if (_isResuming) return;
  _isResuming = true;

  try {
    await handleAppResumed(
      bridge: widget.bridge,
      p2pService: widget.p2pService,
      groupRepo: widget.groupRepository,
      groupMsgRepo: widget.groupMessageRepository,
      groupMessageListener: widget.groupMessageListener,
      mediaAttachmentRepo: widget.mediaAttachmentRepository,
      reactionRepo: widget.reactionRepository,
      recoverStuckSendingGroupMessagesFn: () =>
          recoverStuckSendingGroupMessages(
            groupMsgRepo: widget.groupMessageRepository,
          ),
      retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(
        groupRepo: widget.groupRepository,
        groupMsgRepo: widget.groupMessageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        identityRepo: widget.repository,
        mediaFileManager: widget.mediaFileManager,
      ),
      retryFailedGroupMessagesFn: () => retryFailedGroupMessages(
        groupMsgRepo: widget.groupMessageRepository,
        groupRepo: widget.groupRepository,
        identityRepo: widget.repository,
        bridge: widget.bridge,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
      ),
      retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(
        bridge: widget.bridge,
        msgRepo: widget.groupMessageRepository,
      ),
    );
  } finally {
    _isResuming = false;
  }
}

// lib/features/identity/presentation/startup_router.dart
if (result == StartNodeResult.success && groupRepo != null) {
  unawaited(
    runWithGroupRecoveryGate(() async {
      await rejoinGroupTopics(
        bridge: widget.bridge,
        groupRepo: groupRepo,
      );
      if (groupMsgRepo != null) {
        await drainGroupOfflineInbox(...);
      }
    }),
  );
}

// lib/core/services/pending_message_retrier.dart
Future<void> _runGroupContinuitySweepIfNeeded() async {
  if (_isGroupContinuitySweeping || _isRetrying) return;
  if (!_isGroupRecoveryEnabled()) return;
  if (rejoinGroupTopicsFn == null &&
      rejoinGroupTopicsWithRecoveryAckEligibilityFn == null &&
      drainGroupOfflineInboxFn == null) return;
  if (_isExternalRecoveryInProgressFn?.call() == true) return;
  await runWithGroupRecoveryGate(() async {
    await _runGroupRejoinIfNeeded(); // may acknowledge recovery
    await drainGroupOfflineInboxFn!();
  });
}

Future<void> _retryIfNeeded() async {
  if (_isRetrying) return;
  if (_isExternalRecoveryInProgressFn?.call() == true) return;
  final groupRecoveryEnabled = _isGroupRecoveryEnabled();
  if (groupRecoveryEnabled) {
    await _runGroupRejoinIfNeeded();
    await drainGroupOfflineInboxFn!();
    await recoverStuckSendingGroupMessagesFn!();
    await retryIncompleteGroupUploadsFn!();
    await retryFailedGroupMessagesFn!();
  }
  // non-group retries omitted
  if (groupRecoveryEnabled) {
    await retryFailedGroupInboxStoresFn!();
  }
}
```

### Message Status Recovery Matrix

```
+------------------+--------------------------+----------------------------------------------+
| Current Status   | Condition                | Recovery Action                              |
+------------------+--------------------------+----------------------------------------------+
| 'sending'        | app paused/hidden        | `handleAppPaused()` transitions outgoing     |
|                  |                          | rows to `failed` immediately via             |
|                  |                          | `transitionSendingToFailed()`                |
+------------------+--------------------------+----------------------------------------------+
| 'sending'        | is_incoming=0            | `recoverStuckSendingGroupMessages()`         |
|                  | older than 30s           | updates the row to `failed` via repo/DB      |
|                  |                          | and later retry steps may pick it up         |
+------------------+--------------------------+----------------------------------------------+
| 'failed'         | text-only retry payload  | Re-send via `sendGroupMessage()` with        |
|                  | available                | original messageId + timestamp               |
+------------------+--------------------------+----------------------------------------------+
| 'failed'         | persisted media          | Re-send via `sendGroupMessage()` only when   |
|                  | attachments are all done | persisted attachments are present and all    |
|                  |                          | have `downloadStatus == 'done'`              |
+------------------+--------------------------+----------------------------------------------+
| 'failed'         | no usable text-only      | Skipped in place by                          |
|                  | retry payload and no     | `retryFailedGroupMessages()` until some      |
|                  | complete persisted media | other path repairs the preconditions         |
|                  | attachments, or          |                                              |
|                  | attachments still        |                                              |
|                  | `upload_pending`         |                                              |
+------------------+--------------------------+----------------------------------------------+
| 'sent'/'pending' | inbox_stored = 0         | Re-attempt `callGroupInboxStore()` from      |
|                  | inbox_retry_payload      | cached `inboxRetryPayload` JSON              |
|                  | IS NOT NULL              | (default limit 20 per use-case run)          |
+------------------+--------------------------+----------------------------------------------+
| attachment row   | download_status =        | `retryIncompleteGroupUploads()` loads        |
|                  | 'upload_pending'         | pending attachments from the shared media    |
|                  |                          | repo, uploads pending items in parallel per  |
|                  |                          | message, increments `uploadRetryCount`, and  |
|                  |                          | terminalizes to `upload_failed` at max       |
|                  |                          | retries                                      |
+------------------+--------------------------+----------------------------------------------+
```

### Database Queries for Recovery

```sql
-- Failed outgoing messages (retryable candidates)
-- lib/core/database/helpers/group_messages_db_helpers.dart: dbLoadFailedOutgoingGroupMessages()
SELECT * FROM group_messages
WHERE status = 'failed'
  AND is_incoming = 0
ORDER BY timestamp ASC;

-- Stuck sending recovery uses an UPDATE, not the unused loader helper
-- lib/core/database/helpers/group_messages_db_helpers.dart: dbTransitionGroupSendingToFailed()
UPDATE group_messages
SET status = 'failed'
WHERE status = 'sending'
  AND is_incoming = 0
  AND timestamp < ?;

-- Failed inbox stores
-- lib/core/database/helpers/group_messages_db_helpers.dart: dbLoadGroupMessagesWithFailedInboxStore()
SELECT * FROM group_messages
WHERE is_incoming = 0
  AND inbox_stored = 0
  AND status IN ('sent', 'pending')
  AND inbox_retry_payload IS NOT NULL
ORDER BY timestamp ASC
LIMIT ?;

-- Incomplete uploads come from the shared media table first; the group use
-- case then resolves each parent message through GroupMessageRepository
-- lib/core/database/helpers/media_attachments_db_helpers.dart: dbLoadUploadPendingAttachments()
SELECT * FROM media_attachments
WHERE download_status = 'upload_pending'
ORDER BY created_at ASC
LIMIT ?;
```
