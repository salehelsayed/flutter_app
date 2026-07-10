import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

bool? _isTextOnlyInboxRetryPayload(String retryPayload) {
  try {
    final parsed = jsonDecode(retryPayload) as Map<String, dynamic>;
    final messageRaw = parsed['message'];
    if (messageRaw is! String || messageRaw.isEmpty) return false;

    final message = jsonDecode(messageRaw) as Map<String, dynamic>;
    final media = message['media'];
    return media is! List || media.isEmpty;
  } catch (_) {
    return null;
  }
}

bool? _isTextOnlyWireEnvelope(String wireEnvelope) {
  try {
    final parsed = jsonDecode(wireEnvelope) as Map<String, dynamic>;
    final media = parsed['media'];
    return media is! List || media.isEmpty;
  } catch (_) {
    return null;
  }
}

bool _isTextOnlyRetryPayload(GroupMessage msg) {
  var sawAnyPayload = false;
  var sawTextOnly = false;

  final retryPayload = msg.inboxRetryPayload;
  if (retryPayload != null && retryPayload.isNotEmpty) {
    sawAnyPayload = true;
    final retryOnly = _isTextOnlyInboxRetryPayload(retryPayload);
    if (retryOnly == false) return false;
    if (retryOnly == true) sawTextOnly = true;
  }

  final wireEnvelope = msg.wireEnvelope;
  if (wireEnvelope != null && wireEnvelope.isNotEmpty) {
    sawAnyPayload = true;
    final wireOnly = _isTextOnlyWireEnvelope(wireEnvelope);
    if (wireOnly == false) return false;
    if (wireOnly == true) sawTextOnly = true;
  }

  return sawAnyPayload && sawTextOnly;
}

String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

final Map<String, Future<int>> _singleMessageRetryInFlight = {};

// Finding 05 Phase 4: exponential backoff + terminal cap for failed outgoing
// group-message retries. Base 30s doubling per attempt, capped at 30 minutes;
// after [_groupMaxRetryAttempts] consecutive failed attempts the row flips to
// the terminal `send_failed` status and is no longer auto-retried.
const Duration _groupRetryBackoffBase = Duration(seconds: 30);
const Duration _groupRetryBackoffCap = Duration(minutes: 30);
const int _groupMaxRetryAttempts = 10;

Duration _groupRetryBackoffDelay(int attempt) {
  final baseMs = _groupRetryBackoffBase.inMilliseconds;
  final capMs = _groupRetryBackoffCap.inMilliseconds;
  final shift = attempt.clamp(0, 20);
  final raw = baseMs * (1 << shift);
  return Duration(milliseconds: raw > capMs ? capMs : raw);
}

/// Records a failed re-send: schedules the next attempt with exponential
/// backoff and flips the row to terminal `send_failed` once the attempt budget
/// is exhausted, so a permanently-undeliverable send stops being retried.
Future<void> _recordGroupRetryBackoff(
  GroupMessageRepository groupMsgRepo,
  GroupMessage msg,
) async {
  final newAttempt = msg.retryAttemptCount + 1;
  final terminal = newAttempt >= _groupMaxRetryAttempts;
  final nextEligibleAt = DateTime.now().toUtc().add(
    _groupRetryBackoffDelay(newAttempt),
  );
  await groupMsgRepo.recordRetryFailure(
    msg.id,
    nextEligibleAt: nextEligibleAt,
    markTerminal: terminal,
  );
  emitFlowEvent(
    layer: 'FL',
    event: terminal
        ? 'RETRY_FAILED_GROUP_MESSAGES_TERMINAL'
        : 'RETRY_FAILED_GROUP_MESSAGES_BACKOFF',
    details: {
      'messageId': _shortId(msg.id),
      'attempt': newAttempt,
      'nextEligibleAtMs': nextEligibleAt.millisecondsSinceEpoch,
    },
  );
}

bool _isRetryableOutgoingMessage(GroupMessage message) {
  if (message.isIncoming) return false;
  // Manual single-message retry re-arms the terminal `send_failed` status too;
  // the background loader (getRetryableOutgoingMessages) excludes it via SQL.
  return message.status == 'failed' ||
      message.status == 'pending' ||
      message.status == GroupMessage.statusSendFailed;
}

/// Retries failed outgoing group messages.
///
/// Loads identity, queries failed rows, then re-sends each eligible row via
/// [sendGroupMessage] with the original messageId + timestamp so the DB row
/// is updated in-place.
///
/// Text-only failed rows retry directly.
/// Media/voice failed rows retry only when persisted attachments for that
/// message are already complete (`downloadStatus == 'done'`).
/// Rows whose persisted attachments are still `upload_pending` remain owned by
/// `retryIncompleteGroupUploads(...)` and are skipped here.
///
/// Returns the count of successfully retried messages.
/// Non-fatal: catches errors per-message and continues with the next.
Future<int> retryFailedGroupMessages({
  required GroupMessageRepository groupMsgRepo,
  required GroupRepository groupRepo,
  required IdentityRepository identityRepo,
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
}) {
  return _retryFailedGroupMessagesInternal(
    groupMsgRepo: groupMsgRepo,
    groupRepo: groupRepo,
    identityRepo: identityRepo,
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepo,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    loadFailedMessages: groupMsgRepo.getRetryableOutgoingMessages,
  );
}

/// Retries one failed outgoing group message in place.
Future<int> retryFailedGroupMessage({
  required String messageId,
  required GroupMessageRepository groupMsgRepo,
  required GroupRepository groupRepo,
  required IdentityRepository identityRepo,
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
}) {
  final normalizedMessageId = messageId.trim();
  if (normalizedMessageId.isEmpty) {
    return Future<int>.value(0);
  }
  final inFlight = _singleMessageRetryInFlight[normalizedMessageId];
  if (inFlight != null) {
    return inFlight;
  }

  final retryFuture = _retryFailedGroupMessagesInternal(
    groupMsgRepo: groupMsgRepo,
    groupRepo: groupRepo,
    identityRepo: identityRepo,
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepo,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    loadFailedMessages: () async {
      final message = await groupMsgRepo.getMessage(normalizedMessageId);
      if (message == null || !_isRetryableOutgoingMessage(message)) {
        return const <GroupMessage>[];
      }
      // A user-initiated retry of a terminal `send_failed` row re-arms it with
      // a fresh attempt budget before the normal send path re-attempts it.
      if (message.status == GroupMessage.statusSendFailed) {
        await groupMsgRepo.resetRetryStateForManualRetry(message.id);
        final rearmed = await groupMsgRepo.getMessage(message.id);
        return rearmed != null
            ? <GroupMessage>[rearmed]
            : const <GroupMessage>[];
      }
      return <GroupMessage>[message];
    },
  );
  _singleMessageRetryInFlight[normalizedMessageId] = retryFuture;
  return retryFuture.whenComplete(() {
    final current = _singleMessageRetryInFlight[normalizedMessageId];
    if (identical(current, retryFuture)) {
      _singleMessageRetryInFlight.remove(normalizedMessageId);
    }
  });
}

Future<int> _retryFailedGroupMessagesInternal({
  required GroupMessageRepository groupMsgRepo,
  required GroupRepository groupRepo,
  required IdentityRepository identityRepo,
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  required Future<List<GroupMessage>> Function() loadFailedMessages,
}) async {
  final retryStopwatch = Stopwatch()..start();
  void emitRetryTiming({
    required String outcome,
    required int total,
    required int succeeded,
    required int skippedUnsupported,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_MESSAGES_TIMING',
      details: {
        'elapsedMs': retryStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'total': total,
        'succeeded': succeeded,
        'skippedUnsupported': skippedUnsupported,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_GROUP_MESSAGES_START',
    details: {},
  );

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_MESSAGES_COMPLETE',
      details: {'total': 0, 'succeeded': 0, 'skippedUnsupported': 0},
    );
    emitRetryTiming(
      outcome: 'no_identity',
      total: 0,
      succeeded: 0,
      skippedUnsupported: 0,
    );
    return 0;
  }

  final failedMessages = await loadFailedMessages();
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_GROUP_MESSAGES_FOUND',
    details: {'count': failedMessages.length},
  );

  if (failedMessages.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_MESSAGES_COMPLETE',
      details: {'total': 0, 'succeeded': 0, 'skippedUnsupported': 0},
    );
    emitRetryTiming(
      outcome: 'none',
      total: 0,
      succeeded: 0,
      skippedUnsupported: 0,
    );
    return 0;
  }

  var successCount = 0;
  var skippedCount = 0;

  for (final msg in failedMessages) {
    final outcome = await _retryFailedGroupMessageCandidate(
      msg: msg,
      groupMsgRepo: groupMsgRepo,
      groupRepo: groupRepo,
      bridge: bridge,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identity: identity,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    );
    if (outcome.retried) {
      successCount++;
    } else if (outcome.skippedUnsupported) {
      skippedCount++;
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_GROUP_MESSAGES_COMPLETE',
    details: {
      'total': failedMessages.length,
      'succeeded': successCount,
      'skippedUnsupported': skippedCount,
    },
  );
  emitRetryTiming(
    outcome: 'complete',
    total: failedMessages.length,
    succeeded: successCount,
    skippedUnsupported: skippedCount,
  );

  return successCount;
}

Future<({bool retried, bool skippedUnsupported})>
_retryFailedGroupMessageCandidate({
  required GroupMessage msg,
  required GroupMessageRepository groupMsgRepo,
  required GroupRepository groupRepo,
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required dynamic identity,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
}) async {
  final retryPayloadAvailable =
      (msg.inboxRetryPayload?.isNotEmpty ?? false) ||
      (msg.wireEnvelope?.isNotEmpty ?? false);
  final textOnlyRetry = _isTextOnlyRetryPayload(msg);
  final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
    msg.id,
    owner: MediaOwnerLane.group,
  );
  final hasPendingUploadAttachments = attachments.any(
    (attachment) => attachment.downloadStatus == 'upload_pending',
  );
  final canRetryWithPersistedAttachments =
      attachments.isNotEmpty &&
      attachments.every((attachment) => attachment.downloadStatus == 'done');

  List<MediaAttachment>? retryAttachments;
  if (textOnlyRetry) {
    retryAttachments = null;
  } else if (canRetryWithPersistedAttachments) {
    retryAttachments = attachments;
  } else {
    var reason = 'has_media_or_invalid_payload';
    if (!retryPayloadAvailable) {
      reason = 'missing_retry_payload';
    } else if (hasPendingUploadAttachments) {
      reason = 'incomplete_media_attachments';
    } else if (attachments.isEmpty) {
      reason = 'missing_media_attachments';
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_SKIPPED_UNSUPPORTED',
      details: {'messageId': _shortId(msg.id), 'reason': reason},
    );
    return (retried: false, skippedUnsupported: true);
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
      logicalDeliveryId: msg.logicalDeliveryId ?? msg.id,
      timestamp: msg.timestamp,
      quotedMessageId: msg.quotedMessageId,
      isForwarded: msg.isForwarded,
      mediaAttachments: retryAttachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      emitTimingEvent: false,
    );

    if (result == SendGroupMessageResult.success ||
        result == SendGroupMessageResult.successNoPeers) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_SUCCESS',
        details: {'messageId': _shortId(msg.id), 'result': result.name},
      );
      return (retried: true, skippedUnsupported: false);
    }

    if (result == SendGroupMessageResult.queuedOffline) {
      // 210b: the re-drive resolved to publish-without-custody — the row is
      // now durably 'queued_offline' with its repush payload armed and has
      // LEFT the failed/pending retry lane (the repush pass owns it until
      // custody). Not a failure: no STILL_FAILED mislabel and no backoff
      // bookkeeping (whose status predicate would no-op on this row anyway).
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_QUEUED_OFFLINE',
        details: {'messageId': _shortId(msg.id), 'result': result.name},
      );
      return (retried: true, skippedUnsupported: false);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_STILL_FAILED',
      details: {'messageId': _shortId(msg.id), 'result': result.name},
    );
    await _recordGroupRetryBackoff(groupMsgRepo, msg);
    return (retried: false, skippedUnsupported: false);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_STILL_FAILED',
      details: {'messageId': _shortId(msg.id), 'error': e.toString()},
    );
    await _recordGroupRetryBackoff(groupMsgRepo, msg);
    return (retried: false, skippedUnsupported: false);
  }
}
