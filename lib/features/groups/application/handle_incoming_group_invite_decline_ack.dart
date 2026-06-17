import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_decline_ack_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

enum HandleGroupInviteDeclineAckResult {
  declined,
  invalidPayload,
  decryptionFailed,
  ignored,
}

/// Handles an inbound decline-ack at the inviter: decrypt → verify the inner
/// signed payload AND that `declinedByPeerId == message.from` (spoof guard,
/// mirroring the revocation `revokedByPeerId == message.from` check) → flip the
/// per-peer delivery-attempt row to `declined` (joined-wins is enforced by the
/// repository so a decline-then-rejoin stays joined).
Future<HandleGroupInviteDeclineAckResult> handleIncomingGroupInviteDeclineAck({
  required ChatMessage message,
  required GroupInviteDeliveryAttemptRepository? deliveryRepo,
  required Bridge bridge,
  String? ownMlKemSecretKey,
  DateTime? now,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_DECLINE_ACK_HANDLE_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  final envelope = GroupInviteDeclineAckPayload.parseEncryptedEnvelope(
    message.content,
  );
  if (envelope == null) {
    return HandleGroupInviteDeclineAckResult.invalidPayload;
  }

  final envelopeSenderPeerId = envelope['senderPeerId'] as String;
  if (envelopeSenderPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_HANDLE_SENDER_MISMATCH',
      details: {},
    );
    return HandleGroupInviteDeclineAckResult.invalidPayload;
  }

  if (ownMlKemSecretKey == null || ownMlKemSecretKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_HANDLE_NO_SECRET_KEY',
      details: {},
    );
    return HandleGroupInviteDeclineAckResult.decryptionFailed;
  }

  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  late final GroupInviteDeclineAckPayload payload;
  try {
    final decryptResult = await callDecryptMessage(
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
      kem: encrypted['kem'] as String,
      ciphertext: encrypted['ciphertext'] as String,
      nonce: encrypted['nonce'] as String,
    );
    if (decryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_DECLINE_ACK_HANDLE_DECRYPT_FAILED',
        details: {'errorCode': decryptResult['errorCode']},
      );
      return HandleGroupInviteDeclineAckResult.decryptionFailed;
    }
    final plaintext = decryptResult['plaintext'] as String;
    final parsed = GroupInviteDeclineAckPayload.fromInnerJson(plaintext);
    if (parsed == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_DECLINE_ACK_HANDLE_INVALID_PAYLOAD',
        details: {},
      );
      return HandleGroupInviteDeclineAckResult.invalidPayload;
    }
    payload = parsed;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_HANDLE_DECRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return HandleGroupInviteDeclineAckResult.decryptionFailed;
  }

  // Spoof guard: a peer may only mark ITSELF as declined.
  if (payload.declinedByPeerId != message.from) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_ACK_HANDLE_PAYLOAD_SENDER_MISMATCH',
      details: {},
    );
    return HandleGroupInviteDeclineAckResult.invalidPayload;
  }

  await deliveryRepo?.markDeclined(
    groupId: payload.groupId,
    peerId: message.from,
    declinedAt: (now ?? DateTime.now()).toUtc(),
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_DECLINE_ACK_HANDLE_SUCCESS',
    details: {
      'groupId': payload.groupId.length > 8
          ? payload.groupId.substring(0, 8)
          : payload.groupId,
    },
  );
  return HandleGroupInviteDeclineAckResult.declined;
}
