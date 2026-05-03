import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const groupKeyRepairReasonOfflineMissingKey = 'offline_missing_key';
const groupKeyRepairReasonLiveDiagnostic = 'live_decryption_failed';

class GroupKeyRepairRequest {
  final String groupId;
  final int keyEpoch;
  final String reason;
  final String? messageId;

  const GroupKeyRepairRequest({
    required this.groupId,
    required this.keyEpoch,
    required this.reason,
    this.messageId,
  });
}

class GroupPendingKeyRepairRetryRequest {
  final String groupId;
  final int keyEpoch;

  const GroupPendingKeyRepairRetryRequest({
    required this.groupId,
    required this.keyEpoch,
  });
}

typedef RequestGroupKeyRepair =
    FutureOr<void> Function(GroupKeyRepairRequest request);

typedef RetryPendingGroupKeyRepairs =
    Future<void> Function(GroupPendingKeyRepairRetryRequest request);

typedef ReplayGroupEnvelope = Future<void> Function(Map<String, dynamic> data);

Future<void> emitGroupKeyRepairRequest(GroupKeyRepairRequest request) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_KEY_REPAIR_REQUESTED',
    details: {
      'groupId': _safeId(request.groupId),
      'keyEpoch': request.keyEpoch,
      'reason': request.reason,
      if (request.messageId != null) 'messageId': _safeId(request.messageId!),
    },
  );
}

String offlineGroupPendingKeyRepairId({
  required String groupId,
  required String messageId,
}) {
  return 'offline:$groupId:$messageId';
}

String liveGroupPendingKeyRepairId({
  required String groupId,
  required String senderPeerId,
  required int keyEpoch,
  required int? localKeyEpoch,
}) {
  return 'live:$groupId:$senderPeerId:$keyEpoch:${localKeyEpoch ?? -1}';
}

Future<bool> queueMissingGroupReplayKeyRepairFromEnvelope({
  required GroupPendingKeyRepairRepository pendingKeyRepairRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required Map<String, dynamic> relayEnvelope,
  required Map<String, dynamic> replayEnvelope,
  required RequestGroupKeyRepair requestGroupKeyRepair,
}) async {
  if (!isGroupOfflineReplayEnvelope(replayEnvelope)) return false;

  final payloadType =
      replayEnvelope['payloadType'] as String? ??
      groupOfflineReplayPayloadTypeMessage;
  if (payloadType != groupOfflineReplayPayloadTypeMessage) {
    return false;
  }

  final messageId = (replayEnvelope['messageId'] as String?)?.trim();
  if (messageId == null || messageId.isEmpty) {
    return false;
  }

  final keyEpoch = replayEnvelope['keyEpoch'] as int;
  final senderPeerId = (relayEnvelope['from'] as String?)?.trim();
  final now = DateTime.now().toUtc();
  final repairId = offlineGroupPendingKeyRepairId(
    groupId: groupId,
    messageId: messageId,
  );
  final upsert = await pendingKeyRepairRepo.upsertPendingRepair(
    GroupPendingKeyRepair(
      id: repairId,
      groupId: groupId,
      messageId: messageId,
      senderPeerId: senderPeerId == null || senderPeerId.isEmpty
          ? null
          : senderPeerId,
      transportPeerId: senderPeerId == null || senderPeerId.isEmpty
          ? null
          : senderPeerId,
      payloadType: payloadType,
      keyEpoch: keyEpoch,
      replayEnvelopeJson: jsonEncode(replayEnvelope),
      status: groupPendingKeyRepairStatusPendingKey,
      triggerCount: 1,
      attempts: 0,
      createdAt: now,
      updatedAt: now,
    ),
  );

  final existingMessage = await msgRepo.getMessage(messageId);
  if (existingMessage == null) {
    await msgRepo.saveMessage(
      GroupMessage(
        id: messageId,
        groupId: groupId,
        senderPeerId: senderPeerId == null || senderPeerId.isEmpty
            ? 'unknown'
            : senderPeerId,
        transportPeerId: senderPeerId == null || senderPeerId.isEmpty
            ? null
            : senderPeerId,
        senderUsername: null,
        text: groupPendingKeyRepairPlaceholderText,
        timestamp: _parseRelayTimestamp(relayEnvelope['timestamp']) ?? now,
        keyGeneration: keyEpoch,
        status: groupPendingKeyRepairStatusPendingKey,
        isIncoming: true,
        createdAt: now,
      ),
    );
  }

  if (upsert.created) {
    await requestGroupKeyRepair(
      GroupKeyRepairRequest(
        groupId: groupId,
        keyEpoch: keyEpoch,
        reason: groupKeyRepairReasonOfflineMissingKey,
        messageId: messageId,
      ),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PENDING_KEY_REPAIR_QUEUED',
      details: {
        'groupId': _safeId(groupId),
        'messageId': _safeId(messageId),
        'keyEpoch': keyEpoch,
      },
    );
  }

  return true;
}

Future<GroupMessage?> queueLiveGroupDecryptionFailureRepair({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required GroupPendingKeyRepairRepository pendingKeyRepairRepo,
  required Map<String, dynamic> diagnostic,
  required RequestGroupKeyRepair requestGroupKeyRepair,
}) async {
  if (diagnostic['event'] != 'group:decryption_failed') return null;
  final groupId = (diagnostic['groupId'] as String?)?.trim();
  if (groupId == null || groupId.isEmpty) return null;
  if (await groupRepo.getGroup(groupId) == null) return null;

  final senderPeerId =
      (diagnostic['senderId'] as String?)?.trim().isNotEmpty == true
      ? (diagnostic['senderId'] as String).trim()
      : 'unknown';
  final keyEpoch = _readInt(diagnostic['keyEpoch']);
  if (keyEpoch == null) return null;
  final localKeyEpoch = _readInt(diagnostic['localKeyEpoch']);
  final repairId = liveGroupPendingKeyRepairId(
    groupId: groupId,
    senderPeerId: senderPeerId,
    keyEpoch: keyEpoch,
    localKeyEpoch: localKeyEpoch,
  );
  final now = DateTime.now().toUtc();
  final upsert = await pendingKeyRepairRepo.upsertPendingRepair(
    GroupPendingKeyRepair(
      id: repairId,
      groupId: groupId,
      messageId: repairId,
      senderPeerId: senderPeerId,
      transportPeerId: senderPeerId == 'unknown' ? null : senderPeerId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      keyEpoch: keyEpoch,
      replayEnvelopeJson: null,
      status: groupPendingKeyRepairStatusPendingKey,
      triggerCount: 1,
      attempts: 0,
      lastError: diagnostic['error'] as String?,
      createdAt: now,
      updatedAt: now,
    ),
  );

  if (!upsert.created) {
    return null;
  }

  final placeholder = GroupMessage(
    id: repairId,
    groupId: groupId,
    senderPeerId: senderPeerId,
    transportPeerId: senderPeerId == 'unknown' ? null : senderPeerId,
    senderUsername: null,
    text: groupPendingKeyRepairPlaceholderText,
    timestamp: now,
    keyGeneration: keyEpoch,
    status: groupPendingKeyRepairStatusPendingKey,
    isIncoming: true,
    createdAt: now,
  );
  await msgRepo.saveMessage(placeholder);
  await requestGroupKeyRepair(
    GroupKeyRepairRequest(
      groupId: groupId,
      keyEpoch: keyEpoch,
      reason: groupKeyRepairReasonLiveDiagnostic,
      messageId: repairId,
    ),
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_LIVE_DECRYPTION_REPAIR_PLACEHOLDER_SAVED',
    details: {
      'groupId': _safeId(groupId),
      'messageId': _safeId(repairId),
      'keyEpoch': keyEpoch,
    },
  );
  return placeholder;
}

class GroupPendingKeyRepairRunner {
  final Bridge bridge;
  final GroupRepository groupRepo;
  final GroupMessageRepository msgRepo;
  final GroupPendingKeyRepairRepository pendingKeyRepairRepo;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final ReactionRepository? reactionRepo;
  final ReplayGroupEnvelope? replayGroupEnvelope;

  GroupPendingKeyRepairRunner({
    required this.bridge,
    required this.groupRepo,
    required this.msgRepo,
    required this.pendingKeyRepairRepo,
    this.mediaAttachmentRepo,
    this.reactionRepo,
    this.replayGroupEnvelope,
  });

  Future<void> retryPendingRepairsForRequest(
    GroupPendingKeyRepairRetryRequest request,
  ) async {
    await retryPendingRepairsForKey(
      groupId: request.groupId,
      keyEpoch: request.keyEpoch,
    );
  }

  Future<int> retryPendingRepairsForKey({
    required String groupId,
    required int keyEpoch,
  }) async {
    final repairs = await pendingKeyRepairRepo.getPendingRepairsForGroupEpoch(
      groupId: groupId,
      keyEpoch: keyEpoch,
    );
    var repairedCount = 0;
    for (final repair in repairs) {
      final repaired = await _retryOne(repair);
      if (repaired) repairedCount++;
    }
    return repairedCount;
  }

  Future<bool> _retryOne(GroupPendingKeyRepair repair) async {
    await pendingKeyRepairRepo.recordAttempt(repair.id, lastError: null);
    final rawEnvelope = repair.replayEnvelopeJson;
    if (rawEnvelope == null || rawEnvelope.isEmpty) {
      await _finalizeUndecryptable(repair, 'missing replay envelope');
      return false;
    }

    try {
      final envelope = jsonDecode(rawEnvelope) as Map<String, dynamic>;
      final plaintext = await decryptGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: repair.groupId,
        envelope: envelope,
        expectedRelayPeerId: repair.transportPeerId ?? repair.senderPeerId,
      );

      if (repair.payloadType == groupOfflineReplayPayloadTypeReaction) {
        final reactions = reactionRepo;
        if (reactions == null) {
          throw StateError('missing reaction repository');
        }
        await handleIncomingGroupReaction(
          groupRepo: groupRepo,
          reactionRepo: reactions,
          groupId: repair.groupId,
          senderId: repair.senderPeerId ?? 'unknown',
          transportPeerId: repair.transportPeerId,
          reactionJson: plaintext,
        );
      } else {
        final payload = Map<String, dynamic>.from(jsonDecode(plaintext) as Map);
        payload.putIfAbsent('groupId', () => repair.groupId);
        payload.putIfAbsent('messageId', () => repair.messageId);
        payload.putIfAbsent('keyEpoch', () => repair.keyEpoch);
        if (repair.senderPeerId != null) {
          payload.putIfAbsent('senderId', () => repair.senderPeerId);
        }
        if (repair.transportPeerId != null) {
          payload.putIfAbsent('transportPeerId', () => repair.transportPeerId);
        }

        final replay = replayGroupEnvelope;
        if (replay != null) {
          await replay(payload);
        } else {
          final result = await handleIncomingGroupMessage(
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: payload['groupId'] as String,
            senderId: payload['senderId'] as String? ?? 'unknown',
            senderUsername: payload['senderUsername'] as String? ?? '',
            keyEpoch: payload['keyEpoch'] as int? ?? repair.keyEpoch,
            text: payload['text'] as String? ?? '',
            timestamp:
                payload['timestamp'] as String? ??
                DateTime.now().toUtc().toIso8601String(),
            transportPeerId: payload['transportPeerId'] as String?,
            senderDeviceId: payload['senderDeviceId'] as String?,
            messageId: payload['messageId'] as String?,
            quotedMessageId: payload['quotedMessageId'] as String?,
            media: (payload['media'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>(),
            mediaAttachmentRepo: mediaAttachmentRepo,
          );
          if (result == null) {
            throw StateError('replay validation rejected');
          }
        }
      }

      final message = await msgRepo.getMessage(repair.messageId);
      if (message != null &&
          message.status == groupPendingKeyRepairStatusPendingKey) {
        throw StateError('replay did not replace pending placeholder');
      }
      await pendingKeyRepairRepo.finalizeRepaired(repair.id);
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_PENDING_KEY_REPAIR_REPAIRED',
        details: {
          'groupId': _safeId(repair.groupId),
          'messageId': _safeId(repair.messageId),
          'keyEpoch': repair.keyEpoch,
        },
      );
      return true;
    } catch (e) {
      final key = await groupRepo.getKeyByGeneration(
        repair.groupId,
        repair.keyEpoch,
      );
      if (key == null && e.toString().contains('Missing group replay key')) {
        await pendingKeyRepairRepo.recordAttempt(
          repair.id,
          lastError: e.toString(),
        );
        return false;
      }
      await _finalizeUndecryptable(repair, e.toString());
      return false;
    }
  }

  Future<void> _finalizeUndecryptable(
    GroupPendingKeyRepair repair,
    String error,
  ) async {
    final existing = await msgRepo.getMessage(repair.messageId);
    if (existing != null) {
      await msgRepo.saveMessage(
        existing.copyWith(
          text: _groupUndecryptablePlaceholderText,
          status: groupPendingKeyRepairStatusUndecryptable,
        ),
      );
    }
    await pendingKeyRepairRepo.finalizeUndecryptable(
      repair.id,
      lastError: error,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PENDING_KEY_REPAIR_UNDECRYPTABLE',
      details: {
        'groupId': _safeId(repair.groupId),
        'messageId': _safeId(repair.messageId),
        'keyEpoch': repair.keyEpoch,
      },
    );
  }
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _parseRelayTimestamp(Object? rawTimestamp) {
  if (rawTimestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(rawTimestamp, isUtc: true);
  }
  if (rawTimestamp is double) {
    return DateTime.fromMillisecondsSinceEpoch(
      rawTimestamp.round(),
      isUtc: true,
    );
  }
  if (rawTimestamp is String) {
    final millis = int.tryParse(rawTimestamp);
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    return DateTime.tryParse(rawTimestamp)?.toUtc();
  }
  return null;
}

String _safeId(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;

const _groupUndecryptablePlaceholderText = 'Message could not be decrypted.';
