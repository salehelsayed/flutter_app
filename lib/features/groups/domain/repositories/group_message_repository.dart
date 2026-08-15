import 'dart:async';

import '../models/group_message.dart';
import '../models/group_message_receipt.dart';

const groupRemovalCutoffMessageIdPrefix = 'sys-member_removed_cutoff';

bool isGroupRemovalCutoffMessageId(String id) =>
    id.startsWith('$groupRemovalCutoffMessageIdPrefix:');

String buildGroupRemovalCutoffMessageId({
  required String groupId,
  required String senderPeerId,
  required DateTime removedAt,
}) {
  return '$groupRemovalCutoffMessageIdPrefix:'
      '$groupId:$senderPeerId:${removedAt.toUtc().microsecondsSinceEpoch}';
}

/// Repository interface for managing group messages.
abstract class GroupMessageRepository {
  /// Saves a message to the database. Replaces if ID already exists.
  Future<void> saveMessage(GroupMessage message);

  /// Retrieves a page of messages for a group in deterministic timeline order.
  ///
  /// Unrelated messages are ordered by timestamp ASC, id ASC. Quoted replies
  /// are placed after their quoted parent when both rows are loaded.
  ///
  /// Returns at most [limit] messages starting at [offset].
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  });

  /// Retrieves a single message by ID.
  Future<GroupMessage?> getMessage(String id);

  /// Retrieves the first visible row with a shared logical delivery identity.
  ///
  /// Implementations without this indexed lookup return null so existing
  /// lightweight fakes remain conservative and never infer content identity.
  Future<GroupMessage?> getMessageByLogicalDeliveryId(
    String groupId,
    String senderPeerId,
    String logicalDeliveryId,
  ) async => null;

  /// 235: the migration-069 local-deletion tombstone's group id for a
  /// message, or null when the message is not locally deleted.
  ///
  /// Implementations without tombstone access return null so lightweight
  /// fakes stay conservative (no tombstone knowledge -> incoming reactions
  /// keep their pre-235 buffering behavior).
  Future<String?> getLocalDeletionGroupId(String messageId) async => null;

  /// Retrieves the most recent message for a group.
  Future<GroupMessage?> getLatestMessage(String groupId);

  /// Updates the delivery status of a message.
  Future<void> updateMessageStatus(String id, String status);

  /// Transitions all outgoing messages with status='sending' to status='failed'.
  Future<int> transitionSendingToFailed();

  /// Returns the total number of messages in a group.
  Future<int> getMessageCount(String groupId);

  /// Returns the number of unread incoming messages in a group.
  Future<int> getUnreadCount(String groupId);

  /// Returns the total number of unread incoming messages across all groups.
  Future<int> getTotalUnreadCount();

  /// Marks all unread incoming messages in a group as read.
  Future<void> markAsRead(String groupId);

  /// Deletes a single message by ID.
  Future<void> deleteMessage(String id);

  /// Deletes all messages for a group. Returns the number of deleted messages.
  Future<int> deleteMessagesForGroup(String groupId);

  /// Returns true if a message with the same content already exists.
  Future<bool> existsByContent(
    String groupId,
    String senderPeerId,
    String text,
    DateTime timestamp,
  );

  /// Returns true if a message with the given ID already exists.
  Future<bool> existsByMessageId(String messageId);

  /// Returns the latest persisted synthetic removal-event timestamp for the
  /// given sender in this group, if one exists.
  ///
  /// Implementations may override this for indexed lookups. The default keeps
  /// compatibility for lightweight test doubles that do not need this query.
  Future<DateTime?> getLatestRemovalTimestampForSender(
    String groupId,
    String senderPeerId,
  ) async => null;

  /// Returns the latest persisted synthetic system-event timestamp for a
  /// deterministic target row, if one exists.
  Future<DateTime?> getLatestSystemEventTimestampForTarget(
    String groupId, {
    required String eventType,
    required String targetId,
  }) async {
    final prefix = 'sys-$eventType:$groupId:$targetId:';
    const pageSize = 500;
    var offset = 0;
    DateTime? latest;
    while (true) {
      final page = await getMessagesPage(
        groupId,
        limit: pageSize,
        offset: offset,
      );
      for (final message in page) {
        if (!message.id.startsWith(prefix)) {
          continue;
        }
        final timestamp = message.timestamp.toUtc();
        if (latest == null || timestamp.isAfter(latest)) {
          latest = timestamp;
        }
      }
      if (page.length < pageSize) {
        break;
      }
      offset += page.length;
    }
    return latest;
  }

  /// Retrieves all outgoing messages with status='failed'.
  ///
  /// Used by the retry service to find messages that need re-sending.
  Future<List<GroupMessage>> getFailedOutgoingMessages();

  /// Retrieves outgoing messages eligible for send retry.
  ///
  /// The default keeps older repository doubles compatible. Implementations
  /// with durable `pending` in-doubt rows should override this to include
  /// pending rows that still have retry evidence.
  Future<List<GroupMessage>> getRetryableOutgoingMessages() =>
      getFailedOutgoingMessages();

  /// Finding 05 Phase 4: records a failed background retry attempt — increments
  /// the attempt counter, schedules the exponential-backoff window, and (when
  /// [markTerminal]) flips the row to the terminal `send_failed` status so it is
  /// no longer auto-retried. Default no-op keeps lightweight doubles compatible.
  Future<void> recordRetryFailure(
    String id, {
    required DateTime nextEligibleAt,
    required bool markTerminal,
  }) async {}

  /// Clears the retry-backoff window for every retryable outgoing row so the
  /// next pass re-attempts them immediately (a reconnect grants one immediate
  /// attempt). Returns the number of rows re-armed. Default no-op.
  Future<int> clearRetryBackoff() async => 0;

  /// Re-arms a terminal `send_failed` row for a user-initiated manual retry:
  /// resets the attempt counter + backoff and returns the row to the retryable
  /// `failed` status. Default no-op.
  Future<void> resetRetryStateForManualRetry(String id) async {}

  /// Transitions all outgoing messages with status='sending' that are older
  /// than [olderThan] to status='failed', so the retry service picks them up.
  ///
  /// Returns the count of rows updated.
  Future<int> recoverStuckSendingMessages({required Duration olderThan});

  /// Loads outgoing messages where inbox store failed and retry payload exists.
  ///
  /// Returns messages with `is_incoming = 0`, `inbox_stored = 0`,
  /// `status IN ('sent', 'pending', 'queued_offline')`, and
  /// `inbox_retry_payload IS NOT NULL` (210b: the repush lane also self-heals
  /// queued-offline rows, settling them to 'sent').
  Future<List<GroupMessage>> getMessagesWithFailedInboxStore({
    int limit = 20,
    bool strictContentOnly = false,
    int offset = 0,
  });

  /// Updates the inbox_stored flag for a message.
  Future<void> updateInboxStored(String id, {required bool stored});

  /// Updates (or clears) the inbox_retry_payload for a message.
  Future<void> updateInboxRetryPayload(String id, String? payload);

  /// Updates (or clears) the wire_envelope for a message.
  Future<void> updateWireEnvelope(String id, String? envelope);

  /// Loads the durable group inbox cursor for the next replay request.
  Future<String?> getInboxCursor(String groupId) async => null;

  /// Loads durable group message receipts for a message.
  Future<List<GroupMessageReceipt>> getReceiptsForMessage(
    String groupId,
    String messageId, {
    String? receiptType,
  }) async => const [];

  /// Runs inbox page application through one repository-owned transaction.
  ///
  /// Implementations without durable transaction support fall back to applying
  /// through this repository and do not advance durable cursor/receipt state.
  Future<void> runInboxPageTransaction({
    required String groupId,
    required String nextCursor,
    required Future<void> Function(GroupMessageRepository transactionRepo)
    apply,
    List<GroupMessageReceipt> receipts = const [],
    List<String> markReadMessageIds = const [],
  }) async {
    await apply(this);
  }
}

/// Atomic completion for one previously-qualified relay-inbox retry.
///
/// Implementations compare the complete expected outgoing tuple and current
/// unmarked group parent in the same transaction that records custody. A late
/// completion from an older membership window therefore becomes a typed no-op
/// after removal terminalization or a later accepted re-entry.
abstract interface class GroupInboxStoreRetryCompletionRepository {
  Future<bool> completeInboxStoreRetry(GroupMessage expected);
}

abstract interface class GroupInboxStoreRetryPayloadCasRepository {
  Future<bool> replaceInboxRetryPayloadIfExact(
    GroupMessage expected,
    String replacement,
  );
}

/// Atomic finalization for locally-authored protected content. Event evidence
/// and the outgoing projection transition either both commit or both roll
/// back when the exact retry owner changed.
abstract interface class GroupMessageStrictContentCompletionRepository {
  Future<bool> completeStrictContentIfExact(
    GroupMessage expected, {
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  });
}

/// Atomic zero-target strict authoring. The outgoing owner is never observable
/// without its final protected event/projection evidence.
abstract interface class GroupMessageStrictLocalTerminalRepository {
  Future<bool> stageAndCompleteStrictLocalContent(
    GroupMessage message, {
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  });
}

/// Atomic nonempty-ACL owner preparation before the first network store.
abstract interface class GroupMessageStrictPreparedRepository {
  Future<bool> stageStrictContentPrepared(
    GroupMessage message, {
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> preparedEventPayload,
  });
}

abstract interface class GroupMessageStrictPreparedTerminalRepository {
  Future<bool> hasExactStrictContentPrepared(
    GroupMessage expected, {
    required Map<String, Object?> eventPayload,
  });

  Future<bool> terminalizeStrictContentPreparedIfExact(
    GroupMessage expected, {
    required Map<String, Object?> preparedEventPayload,
    required String terminalSourcePeerId,
    required String terminalSourceEventId,
    required String terminalSourceTimestamp,
    required Map<String, Object?> terminalEventPayload,
  });
}

/// Production-backed eligibility check for a protected reaction target. This
/// includes attachment rows that are intentionally not hydrated on the group
/// message model.
abstract interface class GroupMessageStrictReactionTargetRepository {
  Future<bool> isStrictReactionTargetEligible(GroupMessage expected);
}

/// Narrow durable authority for device-local group private-media lifecycle.
///
/// Kept separate from the broad repository surface so lightweight group fakes
/// remain source-compatible. Privacy-sensitive callers require this capability
/// explicitly and fail closed when it is unavailable.
abstract class GroupPrivateMediaLifecycleRepository {
  Future<GroupMessage?> loadGroupPrivateMediaMessage(String messageId);

  Future<bool> anchorOutgoingGroupPrivateMediaCustody(
    String messageId, {
    required int nowMs,
  });

  Future<bool> consumeGroupPrivateMedia(String messageId, {required int nowMs});

  Future<bool> advanceGroupPrivateMediaClock(
    String messageId, {
    required int nowMs,
  });

  Future<int?> loadNextGroupPrivateMediaExpiryAtMs();

  Future<List<GroupMessage>> loadActiveGroupPrivateMediaDisappearing({
    int limit = 100,
  });

  Future<List<GroupMessage>> loadGroupPrivateMediaRecoveryCandidates({
    int limit = 100,
  });

  Future<bool> rotateGroupPrivateMediaRecoveryCandidate(
    String messageId, {
    required int nowMs,
  });

  Future<bool> completeGroupPrivateMediaCleanup(String messageId);
}

/// Authoritative local-deletion qualification for privacy-sensitive readers.
///
/// [unknown] is distinct from a proven clear source. Callers must fail closed
/// when the capability is absent or cannot establish the current state.
enum GroupMessageLocalDeletionState { knownClear, deleted, unknown }

/// Optional read-only capability that distinguishes a proven clear parent
/// from a deleted parent and unavailable deletion authority.
abstract class GroupMessageLocalDeletionAuthority {
  Future<GroupMessageLocalDeletionState> getGroupMessageLocalDeletionState(
    String messageId,
  );
}

/// Optional indexed implementation of the Plan-237 anchor-window query.
abstract class GroupMessageAroundRepository {
  Future<List<GroupMessage>> getMessagesAround(
    String groupId,
    String anchorMessageId, {
    int before = 25,
    int after = 25,
  });
}

/// Compatibility-preserving typed entry point for existing lightweight fakes.
/// Production implements [GroupMessageAroundRepository]; older fakes return
/// only the exact anchor and never scan pages.
extension GroupMessageAroundReader on GroupMessageRepository {
  Future<List<GroupMessage>> getMessagesAround(
    String groupId,
    String anchorMessageId, {
    int before = 25,
    int after = 25,
  }) async {
    if (before < 0 || before > 25 || after < 0 || after > 25) {
      throw ArgumentError('before and after must each be 0..25');
    }
    final repository = this;
    if (repository is GroupMessageAroundRepository) {
      return (repository as GroupMessageAroundRepository).getMessagesAround(
        groupId,
        anchorMessageId,
        before: before,
        after: after,
      );
    }
    final anchor = await getMessage(anchorMessageId);
    if (anchor == null || anchor.groupId != groupId) return const [];
    return [anchor];
  }
}

/// Optional source for conversation-level group read commits.
///
/// Implementations emit the exact group id after every successful
/// conversation-level mark-as-read call. A no-op message update is still a
/// user-view acknowledgement and lets notification projection retire a current
/// reaction card without inventing reaction unread state.
abstract class GroupConversationReadEventSource {
  Stream<String> get groupConversationReadStream;
}

/// Local in-process notification for outgoing group row changes written by a
/// repository implementation.
class GroupOutgoingLocalMessageChange {
  const GroupOutgoingLocalMessageChange.inserted({
    required String this.groupId,
    required String this.messageId,
  }) : status = null,
       reloadRequired = false;

  const GroupOutgoingLocalMessageChange.status({
    required String this.groupId,
    required String this.messageId,
    required String this.status,
  }) : reloadRequired = false;

  const GroupOutgoingLocalMessageChange.rowsChanged({this.groupId})
    : messageId = null,
      status = null,
      reloadRequired = true;

  final String? groupId;
  final String? messageId;
  final String? status;
  final bool reloadRequired;

  bool get isInserted => !reloadRequired && messageId != null && status == null;
}

/// Optional source for UI surfaces that want repository-local outgoing status
/// changes without forcing every [GroupMessageRepository] implementation to
/// expose a stream.
abstract class GroupOutgoingLocalMessageChangeSource {
  Stream<GroupOutgoingLocalMessageChange> get outgoingLocalMessageChanges;
}

enum GroupMessageAuthorizationMutation { removed, privateLifecycle }

/// Exact post-commit group-parent mutation that can revoke current media
/// authority. A null [messageId] applies to every parent in [groupId].
class GroupMessageAuthorizationChange {
  const GroupMessageAuthorizationChange({
    required this.groupId,
    required this.messageId,
    required this.kind,
  });

  final String groupId;
  final String? messageId;
  final GroupMessageAuthorizationMutation kind;
}

/// Optional repository capability kept separate from outgoing UI status
/// events: incoming/private lifecycle and physical removals are authorization
/// changes, not synthetic message upserts.
abstract class GroupMessageAuthorizationChangeSource {
  Stream<GroupMessageAuthorizationChange> get authorizationChanges;
}

/// Optional repository capability for internal membership-window repair.
///
/// Unlike a user-initiated local deletion, this removes a message so the
/// listener can re-evaluate it after delayed membership events without leaving
/// a local deletion tombstone that would block a valid re-save.
abstract class GroupMembershipRepairDeletionRepository {
  Future<void> deleteMessageForMembershipRepair(String id);
}
