import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_invite_auth.dart';
import 'package:flutter_app/features/groups/application/group_invite_send_latency_trace.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Result of sending a group invite.
enum SendGroupInviteResult {
  success,
  queued,
  nodeNotRunning,
  encryptionRequired,
  invalidPayload,
  sendFailed,
}

class GroupInviteAttempt {
  final String peerId;
  final String? username;
  final SendGroupInviteResult result;

  /// The exact invite id minted for this recipient, so the delivery-attempt
  /// row can persist it for a later revocation match (HOLE-4).
  final String? inviteId;

  const GroupInviteAttempt({
    required this.peerId,
    this.username,
    required this.result,
    this.inviteId,
  });

  bool get wasDelivered =>
      result == SendGroupInviteResult.success ||
      result == SendGroupInviteResult.queued;

  String get displayName {
    final trimmed = username?.trim();
    return trimmed != null && trimmed.isNotEmpty ? trimmed : peerId;
  }

  String get failureLabel {
    switch (result) {
      case SendGroupInviteResult.success:
        return 'delivered';
      case SendGroupInviteResult.queued:
        return 'queued';
      case SendGroupInviteResult.nodeNotRunning:
        return 'node stopped';
      case SendGroupInviteResult.encryptionRequired:
        return 'missing secure key';
      case SendGroupInviteResult.invalidPayload:
        return 'invalid invite payload';
      case SendGroupInviteResult.sendFailed:
        return 'delivery failed';
    }
  }
}

class GroupInviteBatchResult {
  final List<GroupInviteAttempt> attempts;

  const GroupInviteBatchResult({required this.attempts});

  int get successCount =>
      attempts.where((attempt) => attempt.wasDelivered).length;

  List<GroupInviteAttempt> get failures => attempts
      .where((attempt) => !attempt.wasDelivered)
      .toList(growable: false);

  bool get hasFailures => failures.isNotEmpty;

  String describeFailures({int limit = 3}) {
    final failures = this.failures;
    if (failures.isEmpty) return '';
    final labels = failures
        .take(limit)
        .map((attempt) => '${attempt.displayName} (${attempt.failureLabel})')
        .toList(growable: false);
    final hiddenCount = failures.length - labels.length;
    if (hiddenCount > 0) {
      labels.add('+$hiddenCount more');
    }
    return labels.join(', ');
  }
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
  required GroupRepository groupRepo,
  required String recipientPeerId,
  required String? recipientMlKemPublicKey,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  String? senderDeviceId,
  required String groupId,
  required String groupKey,
  required int keyEpoch,
  required Map<String, dynamic> groupConfig,
  String? recipientDeviceId,
  GroupInviteReusePolicy reusePolicy = GroupInviteReusePolicy.singleUse,
  // When supplied, the caller controls the invite id so it can persist the
  // same id on the delivery-attempt row (HOLE-4). Otherwise a fresh id is
  // minted internally as before.
  String? inviteIdOverride,
  GroupInviteLatencyTrace? latencyTrace,
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
    latencyTrace?.endPreFanout(
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      outcome: 'node_not_running',
    );
    return SendGroupInviteResult.nodeNotRunning;
  }

  // 3. Build payload
  final now = DateTime.now().toUtc();
  final currentFreshnessState = await loadCurrentInviteMembershipFreshnessState(
    groupRepo: groupRepo,
    groupId: groupId,
    inviterPeerId: senderPeerId,
    trustedInviterPublicKey: senderPublicKey,
  );
  if (currentFreshnessState == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INVALID_PAYLOAD',
      details: {'reason': 'sender_not_currently_authorized'},
    );
    latencyTrace?.endPreFanout(
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      outcome: 'invalid_payload',
    );
    return SendGroupInviteResult.invalidPayload;
  }
  final effectiveGroupConfig = currentFreshnessState.groupConfig;
  final latestKey = await groupRepo.getLatestKey(groupId);
  if (!_matchesLatestGroupKey(
    latestKey: latestKey,
    suppliedGroupKey: groupKey,
    suppliedKeyEpoch: keyEpoch,
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INVALID_PAYLOAD',
      details: {'reason': 'stale_group_key_material'},
    );
    latencyTrace?.endPreFanout(
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      outcome: 'invalid_payload',
    );
    return SendGroupInviteResult.invalidPayload;
  }
  final recipientDevice = _resolveRecipientDeviceBinding(
    groupConfig: effectiveGroupConfig,
    recipientPeerId: recipientPeerId,
    requestedDeviceId: recipientDeviceId,
    requestedMlKemPublicKey: recipientMlKemPublicKey,
  );
  final recipientEncryptionKey =
      recipientDevice?.mlKemPublicKey ?? recipientMlKemPublicKey;
  if (recipientEncryptionKey == null || recipientEncryptionKey.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_ENCRYPTION_REQUIRED',
      details: {},
    );
    latencyTrace?.endPreFanout(
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      outcome: 'encryption_required',
    );
    return SendGroupInviteResult.encryptionRequired;
  }
  if (recipientDevice == null &&
      (recipientDeviceId?.trim().isNotEmpty == true ||
          _recipientHasRegisteredDevices(
            effectiveGroupConfig,
            recipientPeerId,
          ))) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INVALID_PAYLOAD',
      details: {'reason': 'recipient_device_not_registered'},
    );
    latencyTrace?.endPreFanout(
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      outcome: 'invalid_payload',
    );
    return SendGroupInviteResult.invalidPayload;
  }
  final senderDevice = _resolveSenderDeviceBinding(
    groupConfig: effectiveGroupConfig,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    requestedDeviceId: senderDeviceId,
  );
  final inviteId = inviteIdOverride ?? _uuid.v4();
  final invitePolicy = _deriveInvitePolicy(
    recipientPeerId: recipientPeerId,
    recipientDevice: recipientDevice,
    keyEpoch: keyEpoch,
    groupConfig: effectiveGroupConfig,
    now: now,
    reusePolicy: reusePolicy,
  );
  final welcomeKeyPackage = recipientDevice == null || invitePolicy == null
      ? null
      : _buildWelcomeKeyPackage(
          recipientPeerId: recipientPeerId,
          recipientDevice: recipientDevice,
          inviteId: inviteId,
          groupId: groupId,
          keyEpoch: keyEpoch,
          issuedAt: now,
          expiresAt: invitePolicy.expiresAt,
        );
  if (groupKey.trim().isEmpty ||
      invitePolicy == null ||
      (recipientDevice != null && welcomeKeyPackage == null) ||
      senderPublicKey.trim().isEmpty ||
      senderPrivateKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INVALID_PAYLOAD',
      details: {
        'recipientPeerId': recipientPeerId.length > 10
            ? recipientPeerId.substring(0, 10)
            : recipientPeerId,
        'keyEpoch': keyEpoch,
      },
    );
    latencyTrace?.endPreFanout(
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: 'invalid_payload',
    );
    return SendGroupInviteResult.invalidPayload;
  }

  final payload = GroupInvitePayload(
    id: inviteId,
    groupId: groupId,
    groupKey: groupKey,
    keyEpoch: keyEpoch,
    groupConfig: effectiveGroupConfig,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    timestamp: now.toIso8601String(),
    recipientPeerId: recipientPeerId,
    recipientDeviceId: recipientDevice?.deviceId,
    recipientTransportPeerId: recipientDevice?.transportPeerId,
    recipientMlKemPublicKey: recipientDevice?.mlKemPublicKey,
    recipientKeyPackageId: recipientDevice?.keyPackageId,
    recipientKeyPackagePublicMaterial:
        recipientDevice?.keyPackagePublicMaterial,
    welcomeKeyPackage: welcomeKeyPackage,
    senderDeviceId: senderDevice?.deviceId,
    senderTransportPeerId: senderDevice?.transportPeerId,
    senderDeviceSigningPublicKey: senderDevice?.deviceSigningPublicKey,
    senderKeyPackageId: senderDevice?.keyPackageId,
    invitePolicy: invitePolicy,
    membershipFreshnessProof: currentFreshnessState.buildProof(
      inviteId: inviteId,
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      recipientDeviceId: recipientDevice?.deviceId,
      recipientTransportPeerId: recipientDevice?.transportPeerId,
      recipientMlKemPublicKey: recipientDevice?.mlKemPublicKey,
      recipientKeyPackageId: recipientDevice?.keyPackageId,
      recipientKeyPackagePublicMaterial:
          recipientDevice?.keyPackagePublicMaterial,
      inviterDeviceId: senderDevice?.deviceId,
      inviterTransportPeerId: senderDevice?.transportPeerId,
      inviterDeviceSigningPublicKey: senderDevice?.deviceSigningPublicKey,
      inviterKeyPackageId: senderDevice?.keyPackageId,
      keyEpoch: keyEpoch,
      issuedAt: now,
    ),
  );
  if (!payload.isInvitePolicyValid(validationTime: now)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INVALID_PAYLOAD',
      details: {'reason': 'policy_validation_failed'},
    );
    latencyTrace?.endPreFanout(
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: 'invalid_payload',
    );
    return SendGroupInviteResult.invalidPayload;
  }
  if (!isInviterAuthorizedBySignedSnapshot(
    payload: payload,
    trustedInviterPublicKey: senderPublicKey,
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INVALID_PAYLOAD',
      details: {'reason': 'sender_not_authorized'},
    );
    latencyTrace?.endPreFanout(
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: 'invalid_payload',
    );
    return SendGroupInviteResult.invalidPayload;
  }

  final canonicalInvitePayload = payload.canonicalInviteSignedPayload();
  late final GroupInvitePayload signedPayload;
  latencyTrace?.endPreFanout(
    groupId: groupId,
    inviteId: inviteId,
    recipientPeerId: recipientPeerId,
    outcome: 'ready',
  );
  latencyTrace?.begin(
    GroupInviteLatencyPhase.sign,
    groupId: groupId,
    inviteId: inviteId,
    recipientPeerId: recipientPeerId,
  );
  try {
    final signResponse = await callSignPayload(
      bridge: bridge,
      dataToSign: canonicalInvitePayload,
      privateKey: senderPrivateKey,
    );
    final signature = signResponse['signature'] as String?;
    if (signResponse['ok'] != true ||
        signature == null ||
        signature.trim().isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_SEND_INVALID_PAYLOAD',
        details: {'reason': 'sign_failed'},
      );
      latencyTrace?.end(
        GroupInviteLatencyPhase.sign,
        groupId: groupId,
        inviteId: inviteId,
        recipientPeerId: recipientPeerId,
        outcome: 'failed',
      );
      return SendGroupInviteResult.invalidPayload;
    }
    signedPayload = payload.withInviteSignature(
      signature: signature,
      signedPayload: canonicalInvitePayload,
    );
    latencyTrace?.end(
      GroupInviteLatencyPhase.sign,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: 'signed',
    );
  } catch (e) {
    latencyTrace?.end(
      GroupInviteLatencyPhase.sign,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: 'error',
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INVALID_PAYLOAD',
      details: {'reason': 'sign_error', 'error': e.toString()},
    );
    return SendGroupInviteResult.invalidPayload;
  }

  // 4. Encrypt inner JSON
  String envelopeJson;
  latencyTrace?.begin(
    GroupInviteLatencyPhase.encrypt,
    groupId: groupId,
    inviteId: inviteId,
    recipientPeerId: recipientPeerId,
  );
  try {
    final innerJson = signedPayload.toInnerJson();
    final encryptResult = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientEncryptionKey,
      plaintext: innerJson,
    );

    if (encryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_SEND_ENCRYPT_FAILED',
        details: {'errorCode': encryptResult['errorCode']},
      );
      latencyTrace?.end(
        GroupInviteLatencyPhase.encrypt,
        groupId: groupId,
        inviteId: inviteId,
        recipientPeerId: recipientPeerId,
        outcome: 'failed',
      );
      return SendGroupInviteResult.sendFailed;
    }

    // 5. Build v2 envelope
    envelopeJson = GroupInvitePayload.buildEncryptedEnvelope(
      senderPeerId: senderPeerId,
      inviteId: signedPayload.id,
      senderUsername: senderUsername,
      groupId: groupId,
      groupName: effectiveGroupConfig['name'] as String?,
      kem: encryptResult['kem'] as String,
      ciphertext: encryptResult['ciphertext'] as String,
      nonce: encryptResult['nonce'] as String,
    );
    latencyTrace?.end(
      GroupInviteLatencyPhase.encrypt,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: 'encrypted',
    );
  } catch (e) {
    latencyTrace?.end(
      GroupInviteLatencyPhase.encrypt,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: 'error',
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    return SendGroupInviteResult.sendFailed;
  }

  // 6. Send via P2P, with inbox fallback
  final deliveryPeerId = recipientDevice?.transportPeerId ?? recipientPeerId;
  final envelopeSha256 = latencyTrace == null
      ? null
      : sha256.convert(utf8.encode(envelopeJson)).toString();
  final connectionState = latencyTrace == null
      ? null
      : _observeInviteLatencyConnectionState(p2pService, deliveryPeerId);
  latencyTrace?.begin(
    GroupInviteLatencyPhase.live,
    groupId: groupId,
    inviteId: inviteId,
    recipientPeerId: recipientPeerId,
    details: <String, Object?>{
      'connectionState': connectionState,
      'envelopeSha256': envelopeSha256,
    },
  );
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
    final sent = await p2pService.sendMessage(deliveryPeerId, envelopeJson);
    latencyTrace?.end(
      GroupInviteLatencyPhase.live,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: sent ? 'acknowledged' : 'unacknowledged',
      details: <String, Object?>{
        'acknowledged': sent,
        'connectionState': connectionState,
        'envelopeSha256': envelopeSha256,
        'transport': sent ? 'direct' : 'none',
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_DIRECT_RESULT',
      details: {'sent': sent},
    );
    if (sent) {
      latencyTrace?.skip(
        GroupInviteLatencyPhase.inbox,
        groupId: groupId,
        inviteId: inviteId,
        recipientPeerId: recipientPeerId,
        details: const <String, Object?>{'inboxStoreCount': 0},
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_SEND_SUCCESS',
        details: {'via': 'direct'},
      );
      return SendGroupInviteResult.success;
    }
  } catch (e) {
    latencyTrace?.end(
      GroupInviteLatencyPhase.live,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: 'error',
      details: <String, Object?>{
        'acknowledged': false,
        'connectionState': connectionState,
        'envelopeSha256': envelopeSha256,
        'transport': 'none',
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_DIRECT_FAILED',
      details: {'error': e.toString()},
    );
  }

  // Inbox fallback
  latencyTrace?.begin(
    GroupInviteLatencyPhase.inbox,
    groupId: groupId,
    inviteId: inviteId,
    recipientPeerId: recipientPeerId,
    details: <String, Object?>{
      'envelopeSha256': envelopeSha256,
      'inboxStoreCount': 1,
    },
  );
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
    final stored = await p2pService.storeInInbox(deliveryPeerId, envelopeJson);
    latencyTrace?.end(
      GroupInviteLatencyPhase.inbox,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: stored ? 'stored' : 'not_stored',
      details: <String, Object?>{
        'envelopeSha256': envelopeSha256,
        'inboxStoreCount': 1,
        'transport': stored ? 'inbox' : 'none',
      },
    );
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
      return SendGroupInviteResult.queued;
    }
  } catch (e) {
    latencyTrace?.end(
      GroupInviteLatencyPhase.inbox,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: 'error',
      details: <String, Object?>{
        'envelopeSha256': envelopeSha256,
        'inboxStoreCount': 1,
        'transport': 'none',
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SEND_INBOX_FAILED',
      details: {'error': e.toString()},
    );
  }

  emitFlowEvent(layer: 'FL', event: 'GROUP_INVITE_SEND_FAILED', details: {});
  return SendGroupInviteResult.sendFailed;
}

String _observeInviteLatencyConnectionState(
  P2PService p2pService,
  String deliveryPeerId,
) {
  try {
    return p2pService.isConnectedToPeer(deliveryPeerId)
        ? 'connected'
        : 'not_connected';
  } catch (_) {
    return 'unknown';
  }
}

bool _matchesLatestGroupKey({
  required GroupKeyInfo? latestKey,
  required String suppliedGroupKey,
  required int suppliedKeyEpoch,
}) {
  final latestMaterial = latestKey?.encryptedKey.trim();
  final suppliedMaterial = suppliedGroupKey.trim();
  return latestKey != null &&
      latestMaterial != null &&
      latestMaterial.isNotEmpty &&
      suppliedMaterial.isNotEmpty &&
      latestKey.keyGeneration == suppliedKeyEpoch &&
      latestMaterial == suppliedMaterial;
}

bool _recipientHasRegisteredDevices(
  Map<String, dynamic> groupConfig,
  String recipientPeerId,
) {
  final member = _recipientMember(groupConfig, recipientPeerId);
  if (member == null) {
    return false;
  }
  return GroupMemberDeviceIdentity.listFromJson(member['devices']).isNotEmpty;
}

/// Sends group invites to multiple recipients in parallel via [Future.wait].
///
/// Each invite is independent — different recipient, different encryption.
/// Returns the per-recipient delivery outcome. Individual failures are caught
/// and logged, never propagated.
Future<GroupInviteBatchResult> sendGroupInvitesInParallel({
  required P2PService p2pService,
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  String? senderDeviceId,
  required String groupId,
  required String groupKey,
  required int keyEpoch,
  required Map<String, dynamic> groupConfig,
  required List<({String peerId, String? username, String? mlKemPublicKey})>
  recipients,
  GroupInviteReusePolicy reusePolicy = GroupInviteReusePolicy.singleUse,
  GroupInviteLatencyTrace? latencyTrace,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITES_PARALLEL_BEGIN',
    details: {
      'count': recipients.length,
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  final currentFreshnessState = await loadCurrentInviteMembershipFreshnessState(
    groupRepo: groupRepo,
    groupId: groupId,
    inviterPeerId: senderPeerId,
    trustedInviterPublicKey: senderPublicKey,
  );
  final targetConfig = currentFreshnessState?.groupConfig ?? groupConfig;
  final targets = _expandInviteRecipientsForRegisteredDevices(
    recipients: recipients,
    groupConfig: targetConfig,
  );

  final attempts = await Future.wait(
    targets.map((r) async {
      // Mint the invite id here so it can be persisted on the delivery-attempt
      // row for a later revocation match (HOLE-4), even if the send throws.
      final inviteId = _uuid.v4();
      try {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          groupRepo: groupRepo,
          recipientPeerId: r.peerId,
          recipientMlKemPublicKey: r.mlKemPublicKey,
          senderPeerId: senderPeerId,
          senderPublicKey: senderPublicKey,
          senderPrivateKey: senderPrivateKey,
          senderUsername: senderUsername,
          senderDeviceId: senderDeviceId,
          groupId: groupId,
          groupKey: groupKey,
          keyEpoch: keyEpoch,
          groupConfig: groupConfig,
          recipientDeviceId: r.recipientDeviceId,
          reusePolicy: reusePolicy,
          inviteIdOverride: inviteId,
          latencyTrace: latencyTrace,
        );
        return GroupInviteAttempt(
          peerId: r.peerId,
          username: r.username,
          result: result,
          inviteId: inviteId,
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITES_PARALLEL_SINGLE_ERROR',
          details: {'peerId': r.peerId, 'error': e.toString()},
        );
        return GroupInviteAttempt(
          peerId: r.peerId,
          username: r.username,
          result: SendGroupInviteResult.sendFailed,
          inviteId: inviteId,
        );
      }
    }),
  );

  final summary = GroupInviteBatchResult(attempts: attempts);
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITES_PARALLEL_DONE',
    details: {'sent': summary.successCount, 'total': attempts.length},
  );
  return summary;
}

List<
  ({
    String peerId,
    String? username,
    String? mlKemPublicKey,
    String? recipientDeviceId,
  })
>
_expandInviteRecipientsForRegisteredDevices({
  required List<({String peerId, String? username, String? mlKemPublicKey})>
  recipients,
  required Map<String, dynamic> groupConfig,
}) {
  final targets =
      <
        ({
          String peerId,
          String? username,
          String? mlKemPublicKey,
          String? recipientDeviceId,
        })
      >[];
  for (final recipient in recipients) {
    final member = _recipientMember(groupConfig, recipient.peerId);
    final activeDevices = GroupMemberDeviceIdentity.listFromJson(
      member?['devices'],
    ).where((device) => device.isActive).toList(growable: false);
    if (activeDevices.isEmpty) {
      targets.add((
        peerId: recipient.peerId,
        username: recipient.username,
        mlKemPublicKey: recipient.mlKemPublicKey,
        recipientDeviceId: null,
      ));
      continue;
    }
    for (final device in activeDevices) {
      targets.add((
        peerId: recipient.peerId,
        username: recipient.username,
        mlKemPublicKey: device.mlKemPublicKey,
        recipientDeviceId: device.deviceId,
      ));
    }
  }
  return targets;
}

GroupInvitePolicy? _deriveInvitePolicy({
  required String recipientPeerId,
  required GroupMemberDeviceIdentity? recipientDevice,
  required int keyEpoch,
  required Map<String, dynamic> groupConfig,
  required DateTime now,
  required GroupInviteReusePolicy reusePolicy,
}) {
  final recipient = recipientPeerId.trim();
  if (recipient.isEmpty || keyEpoch <= 0) {
    return null;
  }

  final recipientMember = _recipientMember(groupConfig, recipient);
  if (recipientMember == null) {
    return null;
  }

  final role = recipientMember['role'];
  if (role is! String || role.trim().isEmpty) {
    return null;
  }

  final expiresAt = now.toUtc().add(pendingGroupInviteTtl);
  final keyPackageId = recipientDevice?.keyPackageId?.trim();
  final keyPackagePublicMaterial = recipientDevice?.keyPackagePublicMaterial
      ?.trim();

  return GroupInvitePolicy(
    expiresAt: expiresAt,
    allowedDevices: [recipientDevice?.deviceId ?? recipient],
    assignedRole: role,
    canInviteOthers: _deriveCanInviteOthers(
      role,
      recipientMember['permissions'],
    ),
    joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
    keyEpoch: keyEpoch,
    reusePolicy: reusePolicy,
    welcomeKeyPackageId: keyPackageId != null && keyPackageId.isNotEmpty
        ? keyPackageId
        : null,
    welcomeKeyPackagePublicMaterialHash:
        keyPackagePublicMaterial != null && keyPackagePublicMaterial.isNotEmpty
        ? GroupWelcomeKeyPackage.hashPublicMaterial(keyPackagePublicMaterial)
        : null,
    welcomeKeyPackageExpiresAt: keyPackageId != null && keyPackageId.isNotEmpty
        ? expiresAt
        : null,
  );
}

GroupWelcomeKeyPackage? _buildWelcomeKeyPackage({
  required String recipientPeerId,
  required GroupMemberDeviceIdentity recipientDevice,
  required String inviteId,
  required String groupId,
  required int keyEpoch,
  required DateTime issuedAt,
  required DateTime expiresAt,
}) {
  final keyPackageId = recipientDevice.keyPackageId?.trim();
  final keyPackagePublicMaterial = recipientDevice.keyPackagePublicMaterial
      ?.trim();
  final recipientMlKemPublicKey = recipientDevice.mlKemPublicKey?.trim();
  if (keyPackageId == null ||
      keyPackageId.isEmpty ||
      keyPackagePublicMaterial == null ||
      keyPackagePublicMaterial.isEmpty ||
      recipientMlKemPublicKey == null ||
      recipientMlKemPublicKey.isEmpty) {
    return null;
  }
  final package = GroupWelcomeKeyPackage.create(
    packageId: keyPackageId,
    publicMaterial: keyPackagePublicMaterial,
    recipientPeerId: recipientPeerId,
    recipientDeviceId: recipientDevice.deviceId,
    recipientTransportPeerId: recipientDevice.transportPeerId,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    inviteId: inviteId,
    groupId: groupId,
    keyEpoch: keyEpoch,
    issuedAt: issuedAt,
    expiresAt: expiresAt,
  );
  return package.isStructurallyValid(at: issuedAt) ? package : null;
}

GroupMemberDeviceIdentity? _resolveRecipientDeviceBinding({
  required Map<String, dynamic> groupConfig,
  required String recipientPeerId,
  required String? requestedDeviceId,
  required String? requestedMlKemPublicKey,
}) {
  final member = _recipientMember(groupConfig, recipientPeerId);
  if (member == null) {
    return null;
  }
  final devices = GroupMemberDeviceIdentity.listFromJson(
    member['devices'],
  ).where((device) => device.isActive).toList(growable: false);
  if (devices.isEmpty) {
    return null;
  }
  final normalizedDeviceId = requestedDeviceId?.trim();
  final normalizedMlKem = requestedMlKemPublicKey?.trim();
  for (final device in devices) {
    if (normalizedDeviceId != null &&
        normalizedDeviceId.isNotEmpty &&
        device.deviceId != normalizedDeviceId) {
      continue;
    }
    if (normalizedMlKem != null &&
        normalizedMlKem.isNotEmpty &&
        device.mlKemPublicKey != normalizedMlKem) {
      continue;
    }
    return device;
  }
  return null;
}

GroupMemberDeviceIdentity? _resolveSenderDeviceBinding({
  required Map<String, dynamic> groupConfig,
  required String senderPeerId,
  required String senderPublicKey,
  required String? requestedDeviceId,
}) {
  final member = _recipientMember(groupConfig, senderPeerId);
  if (member == null) {
    return null;
  }
  final normalizedDeviceId = requestedDeviceId?.trim();
  final devices = GroupMemberDeviceIdentity.listFromJson(member['devices']);
  for (final device in devices) {
    if (!device.isActive) {
      continue;
    }
    if (normalizedDeviceId != null &&
        normalizedDeviceId.isNotEmpty &&
        device.deviceId != normalizedDeviceId) {
      continue;
    }
    if (device.deviceSigningPublicKey == senderPublicKey) {
      return device;
    }
  }
  return null;
}

Map<String, dynamic>? _recipientMember(
  Map<String, dynamic> groupConfig,
  String recipientPeerId,
) {
  final members = groupConfig['members'];
  if (members is! List) {
    return null;
  }
  for (final rawMember in members) {
    if (rawMember is! Map<String, dynamic>) {
      continue;
    }
    if (rawMember['peerId'] == recipientPeerId) {
      return rawMember;
    }
  }
  return null;
}

bool _deriveCanInviteOthers(String roleValue, Object? permissionsJson) {
  try {
    final role = MemberRole.fromValue(roleValue);
    return GroupMemberPermissions.fromJson(
      permissionsJson,
    ).allows(GroupMemberPermission.inviteMembers, role);
  } catch (_) {
    return roleValue == MemberRole.admin.toValue();
  }
}
