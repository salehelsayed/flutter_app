import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
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

/// Retries failed outgoing group messages.
///
/// Loads identity, queries failed rows, then re-sends each text-only row via
/// [sendGroupMessage] with the original messageId + timestamp so the DB row
/// is updated in-place. Rows that still carry media/voice retry metadata are
/// skipped until the durable media/voice phases land.
///
/// Returns the count of successfully retried messages.
/// Non-fatal: catches errors per-message and continues with the next.
Future<int> retryFailedGroupMessages({
  required GroupMessageRepository groupMsgRepo,
  required GroupRepository groupRepo,
  required IdentityRepository identityRepo,
  required Bridge bridge,
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

  final failedMessages = await groupMsgRepo.getFailedOutgoingMessages();
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
    if (!_isTextOnlyRetryPayload(msg)) {
      skippedCount++;
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_SKIPPED_UNSUPPORTED',
        details: {
          'messageId': _shortId(msg.id),
          'reason': msg.inboxRetryPayload == null
              ? 'missing_retry_payload'
              : 'has_media_or_invalid_payload',
        },
      );
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
        emitTimingEvent: false,
      );

      if (result == SendGroupMessageResult.success ||
          result == SendGroupMessageResult.successNoPeers) {
        successCount++;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_SUCCESS',
          details: {'messageId': _shortId(msg.id), 'result': result.name},
        );
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_STILL_FAILED',
          details: {'messageId': _shortId(msg.id), 'result': result.name},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_STILL_FAILED',
        details: {'messageId': _shortId(msg.id), 'error': e.toString()},
      );
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
