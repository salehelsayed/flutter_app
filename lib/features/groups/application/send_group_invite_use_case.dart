import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';

/// Result of sending a group invite.
enum SendGroupInviteResult {
  success,
  nodeNotRunning,
  encryptionRequired,
  sendFailed,
}

const _uuid = Uuid();

/// Sends a group invite to a contact via P2P, encrypted with ML-KEM.
///
/// Steps:
/// 1. Validate P2P node is running.
/// 2. Validate recipientMlKemPublicKey is not null.
/// 3. Build GroupInvitePayload.
/// 4. Encrypt inner JSON with callEncryptMessage.
/// 5. Build v2 envelope with GroupInvitePayload.buildEncryptedEnvelope.
/// 6. Try p2pService.sendMessage -> if fails, try p2pService.storeInInbox.
/// 7. Return result.
Future<SendGroupInviteResult> sendGroupInvite({
  required P2PService p2pService,
  required Bridge bridge,
  required String recipientPeerId,
  required String? recipientMlKemPublicKey,
  required String senderPeerId,
  required String senderUsername,
  required String groupId,
  required String groupKey,
  required int keyEpoch,
  required Map<String, dynamic> groupConfig,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_SEND_START',
    details: {
      'recipientPeerId': recipientPeerId.length > 10
          ? recipientPeerId.substring(0, 10)
          : recipientPeerId,
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  // 1. Check P2P node
  if (!p2pService.currentState.isStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_NODE_NOT_RUNNING',
      details: {},
    );
    return SendGroupInviteResult.nodeNotRunning;
  }

  // 2. Validate ML-KEM key
  if (recipientMlKemPublicKey == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_ENCRYPTION_REQUIRED',
      details: {},
    );
    return SendGroupInviteResult.encryptionRequired;
  }

  // 3. Build payload
  final payload = GroupInvitePayload(
    id: _uuid.v4(),
    groupId: groupId,
    groupKey: groupKey,
    keyEpoch: keyEpoch,
    groupConfig: groupConfig,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );

  // 4. Encrypt inner JSON
  String envelopeJson;
  try {
    final innerJson = payload.toInnerJson();
    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      plaintext: innerJson,
    );

    if (encryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_SEND_ENCRYPT_FAILED',
        details: {'errorCode': encryptResult['errorCode']},
      );
      return SendGroupInviteResult.sendFailed;
    }

    // 5. Build v2 envelope
    envelopeJson = GroupInvitePayload.buildEncryptedEnvelope(
      senderPeerId: senderPeerId,
      inviteId: payload.id,
      senderUsername: senderUsername,
      groupId: groupId,
      groupName: groupConfig['name'] as String?,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return SendGroupInviteResult.sendFailed;
  }

  // 6. Send via P2P, with inbox fallback
  try {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_DIRECT_ATTEMPT',
      details: {
        'recipientPeerId': recipientPeerId.length > 10
            ? recipientPeerId.substring(0, 10)
            : recipientPeerId,
        'envelopeLength': envelopeJson.length,
      },
    );
    final sent = await p2pService.sendMessage(recipientPeerId, envelopeJson);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_DIRECT_RESULT',
      details: {'sent': sent},
    );
    if (sent) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_SEND_SUCCESS',
        details: {'via': 'direct'},
      );
      return SendGroupInviteResult.success;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_DIRECT_FAILED',
      details: {'error': e.toString()},
    );
  }

  // Inbox fallback
  try {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INBOX_ATTEMPT',
      details: {
        'recipientPeerId': recipientPeerId.length > 10
            ? recipientPeerId.substring(0, 10)
            : recipientPeerId,
      },
    );
    final stored = await p2pService.storeInInbox(recipientPeerId, envelopeJson);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INBOX_RESULT',
      details: {'stored': stored},
    );
    if (stored) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_SEND_SUCCESS',
        details: {'via': 'inbox'},
      );
      return SendGroupInviteResult.success;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INBOX_FAILED',
      details: {'error': e.toString()},
    );
  }

  emitFlowEvent(layer: 'FL', event: 'GROUP_INVITE_SEND_FAILED', details: {});
  return SendGroupInviteResult.sendFailed;
}

/// Sends group invites to multiple recipients in parallel via [Future.wait].
///
/// Each invite is independent — different recipient, different encryption.
/// Returns the count of successful invites. Individual failures are caught
/// and logged, never propagated.
Future<int> sendGroupInvitesInParallel({
  required P2PService p2pService,
  required Bridge bridge,
  required String senderPeerId,
  required String senderUsername,
  required String groupId,
  required String groupKey,
  required int keyEpoch,
  required Map<String, dynamic> groupConfig,
  required List<({String peerId, String? mlKemPublicKey})> recipients,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITES_PARALLEL_BEGIN',
    details: {
      'count': recipients.length,
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final results = await Future.wait(
    recipients.map((r) async {
      try {
        return await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          recipientPeerId: r.peerId,
          recipientMlKemPublicKey: r.mlKemPublicKey,
          senderPeerId: senderPeerId,
          senderUsername: senderUsername,
          groupId: groupId,
          groupKey: groupKey,
          keyEpoch: keyEpoch,
          groupConfig: groupConfig,
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITES_PARALLEL_SINGLE_ERROR',
          details: {'peerId': r.peerId, 'error': e.toString()},
        );
        return SendGroupInviteResult.sendFailed;
      }
    }),
  );

  final sent = results.where((r) => r == SendGroupInviteResult.success).length;
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITES_PARALLEL_DONE',
    details: {'sent': sent, 'total': recipients.length},
  );
  return sent;
}
