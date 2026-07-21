import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const groupKeyRepairReasonOfflineMissingKey = 'offline_missing_key';
const groupKeyRepairReasonLiveDiagnostic = 'live_decryption_failed';
const groupKeyRepairReasonReceivedMessageEpochMissingLocalKey =
    'received_message_epoch_missing_local_key';
const groupKeyRepairReasonKeyUpdateApplyFailed = 'key_update_apply_failed';
const groupKeyRepairReasonSameEpochKeyConflict = 'same_epoch_key_conflict';
const groupKeyRepairReasonDirectMembershipUpdateDeferred =
    'direct_membership_update_deferred';

/// Hard cap on confirmed-crypto-failure retries before a keyed group repair is
/// branded permanently undecryptable. Key-absence and transient/ambiguous
/// failures never count toward this — only authenticity failures with the key
/// present (see [_isConfirmedGroupReplayCryptoFailure]).
const kGroupKeyRepairMaxAttempts = 5;

/// A no-envelope `live:` placeholder whose real message never arrives is
/// self-cleared (row + message DELETED, NOT branded undecryptable) once it is
/// older than this — otherwise, under bounded-finalize + the resume/backoff
/// sweep, it would wait forever with no ciphertext to recover.
const liveGroupNoEnvelopeRepairTtl = Duration(hours: 24);

DateTime _defaultGroupRepairNowUtc() => DateTime.now().toUtc();

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

/// Wire type for the active key-pull request (Slice 2 / UDM-G). Old peers route
/// this unknown type to `unknownMessageStream` → harmless drop, so backward-compat
/// is free.
const groupKeyRepairRequestType = 'group_key_repair_request';

/// Ed25519 — same algorithm the signed group key-update / transition audit uses.
const groupKeyRepairRequestSignatureAlgorithm = 'ed25519';

/// Canonical, stable JSON over the request fields the requester signs. The
/// responder rebuilds this identically and verifies the signature against the
/// requester's bound device signing key (UDM-G threat-model gate #1).
String canonicalGroupKeyRepairRequestSignedPayload({
  required String groupId,
  required int keyEpoch,
  required String requesterPeerId,
  required String requesterDeviceId,
}) {
  return jsonEncode({
    'type': groupKeyRepairRequestType,
    'groupId': groupId,
    'keyEpoch': keyEpoch,
    'requesterPeerId': requesterPeerId,
    'requesterDeviceId': requesterDeviceId,
  });
}

/// Builds the outbound signed `group_key_repair_request` envelope. The signature
/// covers [canonicalGroupKeyRepairRequestSignedPayload] over the same four
/// fields, signed via [callSignPayload] with the requester's device private key.
///
/// Returns `null` when signing fails (no private key, bridge error) — the caller
/// degrades to the FLOW-log fallback rather than sending an unsigned request.
Future<Map<String, dynamic>?> buildSignedGroupKeyRepairRequestEnvelope({
  required Bridge bridge,
  required String groupId,
  required int keyEpoch,
  required String requesterPeerId,
  required String requesterDeviceId,
  required String requesterPrivateKey,
}) async {
  final signedPayload = canonicalGroupKeyRepairRequestSignedPayload(
    groupId: groupId,
    keyEpoch: keyEpoch,
    requesterPeerId: requesterPeerId,
    requesterDeviceId: requesterDeviceId,
  );
  final signResult = await callSignPayload(
    bridge: bridge,
    dataToSign: signedPayload,
    privateKey: requesterPrivateKey,
  );
  final signature = signResult['signature'];
  if (signResult['ok'] != true || signature is! String || signature.isEmpty) {
    return null;
  }
  return {
    'type': groupKeyRepairRequestType,
    'version': '1',
    'payload': {
      'groupId': groupId,
      'keyEpoch': keyEpoch,
      'requesterPeerId': requesterPeerId,
      'requesterDeviceId': requesterDeviceId,
      'signatureAlgorithm': groupKeyRepairRequestSignatureAlgorithm,
      'signedPayload': signedPayload,
      'signature': signature,
    },
  };
}

/// Real outbound active key-pull (UDM-G). Implements [RequestGroupKeyRepair]:
/// when fired it builds a signed [groupKeyRepairRequestType] envelope and sends
/// it directly to the group admin/creator's transport peer, falling back to the
/// admin's relay inbox if the direct send fails. Keeps the FLOW-log behaviour of
/// [emitGroupKeyRepairRequest] for observability.
///
/// Constructed once at startup with closures over the live `p2pService`
/// send/inbox + the local identity getters; threaded to the direct
/// `requestGroupKeyRepair:` call sites in place of the bare log-only stub.
class GroupKeyRepairRequestSender {
  final Bridge bridge;
  final GroupRepository groupRepo;
  final Future<String?> Function() getOwnPeerId;
  final Future<String?> Function() getOwnDeviceId;
  final Future<String?> Function() getOwnPrivateKey;
  final Future<bool> Function(String peerId, String message) sendP2PMessage;
  final Future<bool> Function(String peerId, String message)?
  storeP2PMessageInInbox;
  final Duration sendTimeout;

  GroupKeyRepairRequestSender({
    required this.bridge,
    required this.groupRepo,
    required this.getOwnPeerId,
    required this.getOwnDeviceId,
    required this.getOwnPrivateKey,
    required this.sendP2PMessage,
    this.storeP2PMessageInInbox,
    this.sendTimeout = const Duration(seconds: 5),
  });

  Future<void> call(GroupKeyRepairRequest request) async {
    // Always emit the diagnostic so the existing GROUP_KEY_REPAIR_REQUESTED
    // observability stays intact regardless of send outcome.
    await emitGroupKeyRepairRequest(request);

    await runSelfRemovedGroupLifecycleLeaf<void>(
      groupRepo: groupRepo,
      groupId: request.groupId,
      action: (_) => _sendForActiveGroup(request),
    );
  }

  Future<void> _sendForActiveGroup(GroupKeyRepairRequest request) async {
    try {
      final requesterPeerId = (await getOwnPeerId())?.trim();
      final requesterDeviceId = (await getOwnDeviceId())?.trim();
      final requesterPrivateKey = await getOwnPrivateKey();
      if (requesterPeerId == null ||
          requesterPeerId.isEmpty ||
          requesterDeviceId == null ||
          requesterDeviceId.isEmpty ||
          requesterPrivateKey == null ||
          requesterPrivateKey.isEmpty) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_REPAIR_REQUEST_SEND_NO_IDENTITY',
          details: {
            'groupId': _safeId(request.groupId),
            'keyEpoch': request.keyEpoch,
          },
        );
        return;
      }

      final adminTransportPeerId = await _resolveAdminTransportPeerId(
        request.groupId,
      );
      if (adminTransportPeerId == null || adminTransportPeerId.isEmpty) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_REPAIR_REQUEST_NO_ADMIN_TARGET',
          details: {
            'groupId': _safeId(request.groupId),
            'keyEpoch': request.keyEpoch,
          },
        );
        return;
      }

      final envelope = await buildSignedGroupKeyRepairRequestEnvelope(
        bridge: bridge,
        groupId: request.groupId,
        keyEpoch: request.keyEpoch,
        requesterPeerId: requesterPeerId,
        requesterDeviceId: requesterDeviceId,
        requesterPrivateKey: requesterPrivateKey,
      );
      if (envelope == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_REPAIR_REQUEST_SIGN_FAILED',
          details: {
            'groupId': _safeId(request.groupId),
            'keyEpoch': request.keyEpoch,
          },
        );
        return;
      }

      final wire = jsonEncode(envelope);
      final delivered = await _sendDirectWithInboxFallback(
        transportPeerId: adminTransportPeerId,
        envelope: wire,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_REPAIR_REQUEST_SENT',
        details: {
          'groupId': _safeId(request.groupId),
          'keyEpoch': request.keyEpoch,
          'delivered': delivered,
        },
      );
    } catch (e) {
      // Never throw out of the producer chain (NSE/background-safe): a failed
      // send is no worse than today's log-only stub.
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_REPAIR_REQUEST_SEND_ERROR',
        details: {
          'groupId': _safeId(request.groupId),
          'keyEpoch': request.keyEpoch,
          'error': e.toString(),
        },
      );
    }
  }

  Future<String?> _resolveAdminTransportPeerId(String groupId) async {
    final group = await groupRepo.getGroup(groupId);
    final creatorPeerId = group?.createdBy;
    final members = await groupRepo.getMembers(groupId);

    GroupMember? admin;
    for (final member in members) {
      if (creatorPeerId != null && member.peerId == creatorPeerId) {
        admin = member;
        break;
      }
    }
    admin ??= () {
      for (final member in members) {
        if (member.permissions.allows(
          GroupMemberPermission.rotateKeys,
          member.role,
        )) {
          return member;
        }
      }
      return null;
    }();
    if (admin == null) return null;

    final devices = admin.devices.isEmpty
        ? admin.activeDevicesWithLegacyFallback()
        : admin.activeDevices;
    for (final device in devices) {
      final transport = device.transportPeerId.trim();
      if (transport.isNotEmpty) return transport;
    }
    return null;
  }

  Future<bool> _sendDirectWithInboxFallback({
    required String transportPeerId,
    required String envelope,
  }) async {
    try {
      final directFuture = sendP2PMessage(transportPeerId, envelope);
      final directSent = await directFuture.timeout(
        sendTimeout,
        onTimeout: () => false,
      );
      if (directSent) return true;
    } catch (_) {
      // fall through to inbox
    }
    final inbox = storeP2PMessageInInbox;
    if (inbox == null) return false;
    try {
      return await inbox(
        transportPeerId,
        envelope,
      ).timeout(sendTimeout, onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }
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
  String repairReason = groupKeyRepairReasonOfflineMissingKey,
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
  final replaySenderPeerId = (replayEnvelope['senderPeerId'] as String?)
      ?.trim();
  final replayTransportPeerId =
      (replayEnvelope['senderTransportPeerId'] as String?)?.trim();
  final relaySenderPeerId = (relayEnvelope['from'] as String?)?.trim();
  final senderPeerId = replaySenderPeerId?.isNotEmpty == true
      ? replaySenderPeerId
      : relaySenderPeerId;
  final transportPeerId = replayTransportPeerId?.isNotEmpty == true
      ? replayTransportPeerId
      : relaySenderPeerId;
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
      transportPeerId: transportPeerId == null || transportPeerId.isEmpty
          ? null
          : transportPeerId,
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
  await _supersedeLiveDiagnosticRepairForDurableReplay(
    pendingKeyRepairRepo: pendingKeyRepairRepo,
    msgRepo: msgRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    keyEpoch: keyEpoch,
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
        transportPeerId: transportPeerId == null || transportPeerId.isEmpty
            ? null
            : transportPeerId,
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
        reason: repairReason,
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

/// Supersedes the synthetic `live:` decryption-failure placeholder(s) for a
/// group+epoch once a real message for that epoch lands — whether via durable
/// replay or the live-delivery path. A placeholder matches when its stored
/// sender or transport peer equals EITHER [senderPeerId] or [transportPeerId];
/// the real message replaces it, so the placeholder row + its message are
/// deleted and the repair is finalized as repaired. Scoped precisely to the
/// `(groupId, keyEpoch)` pair and the matching sender — never reconstructs the
/// synthetic id (which embeds a `localKeyEpoch` the live path does not know).
Future<void> supersedeLiveGroupDecryptionRepairForDelivery({
  required GroupPendingKeyRepairRepository pendingKeyRepairRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String? senderPeerId,
  required String? transportPeerId,
  required int keyEpoch,
}) async {
  final candidates = <String>{};
  final sender = senderPeerId?.trim();
  final transport = transportPeerId?.trim();
  if (sender != null && sender.isNotEmpty) candidates.add(sender);
  if (transport != null && transport.isNotEmpty) candidates.add(transport);
  if (candidates.isEmpty) return;

  final repairs = await pendingKeyRepairRepo.getPendingRepairsForGroupEpoch(
    groupId: groupId,
    keyEpoch: keyEpoch,
  );
  var supersededCount = 0;
  for (final repair in repairs) {
    if (!candidates.any(
      (candidate) => _isLiveDiagnosticRepairForSender(repair, candidate),
    )) {
      continue;
    }
    final finalized = await finalizeGroupPendingKeyRepairIfExact(
      pendingKeyRepairRepo,
      repair,
    );
    if (!finalized) continue;
    await msgRepo.deleteMessage(repair.messageId);
    supersededCount++;
  }
  if (supersededCount == 0) return;

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_LIVE_DECRYPTION_REPAIR_SUPERSEDED',
    details: {
      'groupId': _safeId(groupId),
      'keyEpoch': keyEpoch,
      'count': supersededCount,
    },
  );
}

/// Durable-replay supersede: delegates to
/// [supersedeLiveGroupDecryptionRepairForDelivery] with only the durable
/// sender known (no standalone transport peer), preserving the original
/// single-identifier match semantics.
Future<void> _supersedeLiveDiagnosticRepairForDurableReplay({
  required GroupPendingKeyRepairRepository pendingKeyRepairRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String? senderPeerId,
  required int keyEpoch,
}) async {
  await supersedeLiveGroupDecryptionRepairForDelivery(
    pendingKeyRepairRepo: pendingKeyRepairRepo,
    msgRepo: msgRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    transportPeerId: null,
    keyEpoch: keyEpoch,
  );
}

bool _isLiveDiagnosticRepairForSender(
  GroupPendingKeyRepair repair,
  String senderPeerId,
) {
  if (!repair.id.startsWith('live:')) return false;
  if (repair.replayEnvelopeJson != null) return false;
  return repair.senderPeerId == senderPeerId ||
      repair.transportPeerId == senderPeerId;
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

Future<GroupMessage?> markOutboundGroupMessageRejectedByValidator({
  required GroupMessageRepository msgRepo,
  required Map<String, dynamic> diagnostic,
}) async {
  if (diagnostic['event'] != 'group:publish_validation_rejected') {
    return null;
  }
  final groupId = (diagnostic['groupId'] as String?)?.trim();
  final messageId = (diagnostic['messageId'] as String?)?.trim();
  if (groupId == null ||
      groupId.isEmpty ||
      messageId == null ||
      messageId.isEmpty) {
    return null;
  }

  final message = await msgRepo.getMessage(messageId);
  if (message == null || message.isIncoming || message.groupId != groupId) {
    return null;
  }

  final retryWireEnvelope =
      message.wireEnvelope ??
      jsonEncode({
        'groupId': message.groupId,
        'messageId': message.id,
        'senderPeerId': message.senderPeerId,
        if (message.senderUsername != null)
          'senderUsername': message.senderUsername,
        'text': message.text,
        if (message.quotedMessageId != null)
          'quotedMessageId': message.quotedMessageId,
      });
  final updated = message.copyWith(
    status: 'failed',
    wireEnvelope: retryWireEnvelope,
  );
  await msgRepo.saveMessage(updated);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_OUTBOUND_VALIDATION_REJECTED',
    details: {
      'groupId': _safeId(groupId),
      'messageId': _safeId(messageId),
      'reason': diagnostic['reason']?.toString() ?? 'unknown',
      if (diagnostic['keyEpoch'] != null) 'keyEpoch': diagnostic['keyEpoch'],
    },
  );
  return updated;
}

class GroupPendingKeyRepairRunner {
  final Bridge bridge;
  final GroupRepository groupRepo;
  final GroupMessageRepository msgRepo;
  final GroupPendingKeyRepairRepository pendingKeyRepairRepo;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final ReactionRepository? reactionRepo;
  final ReplayGroupEnvelope? replayGroupEnvelope;

  /// Injectable clock (UTC). Defaults to the real clock; tests inject a fixed
  /// `now` to exercise the no-envelope TTL self-clear deterministically.
  final DateTime Function() nowUtc;

  GroupPendingKeyRepairRunner({
    required this.bridge,
    required this.groupRepo,
    required this.msgRepo,
    required this.pendingKeyRepairRepo,
    this.mediaAttachmentRepo,
    this.reactionRepo,
    this.replayGroupEnvelope,
    DateTime Function()? nowUtc,
  }) : nowUtc = nowUtc ?? _defaultGroupRepairNowUtc;

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

  /// Sweeps EVERY persisted `pending_key` repair across all groups/epochs and
  /// runs each through [_retryOne]. Backs the resume sweep + backoff timer so
  /// repairs re-fire even when no fresh key-update/invite event arrives for
  /// their exact `(group, epoch)`. Internally cheap when nothing is pending.
  Future<int> retryAllPending({int limit = 200}) async {
    final repairs = await pendingKeyRepairRepo.getAllPendingRepairs(
      limit: limit,
    );
    var repairedCount = 0;
    for (final repair in repairs) {
      final repaired = await _retryOne(repair);
      if (repaired) repairedCount++;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PENDING_KEY_REPAIR_SWEEP',
      details: {'scanned': repairs.length, 'repaired': repairedCount},
    );
    return repairedCount;
  }

  Future<bool> _retryOne(GroupPendingKeyRepair repair) async {
    Map<String, dynamic>? deferredMessageReplay;
    final guarded = await runSelfRemovedGroupLifecycleLeaf<bool>(
      groupRepo: groupRepo,
      groupId: repair.groupId,
      action: (_) async {
        final current = await _reloadExactPendingRepair(repair);
        if (current == null) return false;
        return _retryOneLocked(
          current,
          deferMessageReplay: (payload) => deferredMessageReplay = payload,
        );
      },
    );
    if (!guarded.didRun) return false;

    final deferredPayload = deferredMessageReplay;
    if (deferredPayload == null) return guarded.value ?? false;

    // Every listener callback stays outside the non-reentrant membership
    // phase. Besides system membership messages, ordinary replay listeners may
    // themselves route into a same-group lifecycle owner; invoking either
    // shape while this phase is held can deadlock. Exact completion is
    // reacquired below, so a B3 transition that wins while the callback is in
    // flight terminalizes the repair and the stale completion becomes a no-op.
    final replay = replayGroupEnvelope;
    if (replay == null) return false;
    try {
      await replay(deferredPayload);
    } catch (error) {
      await _recordDeferredReplayFailure(repair, error);
      return false;
    }

    final completion = await runSelfRemovedGroupLifecycleLeaf<bool>(
      groupRepo: groupRepo,
      groupId: repair.groupId,
      action: (_) async {
        final current = await _reloadExactPendingRepair(repair);
        if (current == null) return false;
        return _finalizeSuccessfulReplay(current, deferredPayload);
      },
    );
    return completion.didRun && (completion.value ?? false);
  }

  Future<GroupPendingKeyRepair?> _reloadExactPendingRepair(
    GroupPendingKeyRepair loaded,
  ) async {
    final current = await pendingKeyRepairRepo.getRepair(loaded.id);
    if (current == null ||
        current.status != groupPendingKeyRepairStatusPendingKey ||
        !sameExactGroupPendingKeyRepair(current, loaded)) {
      return null;
    }
    return current;
  }

  Future<bool> _retryOneLocked(
    GroupPendingKeyRepair repair, {
    required void Function(Map<String, dynamic> payload) deferMessageReplay,
  }) async {
    final rawEnvelope = repair.replayEnvelopeJson;
    if (rawEnvelope == null || rawEnvelope.isEmpty) {
      // TTL self-clear: a `live:` placeholder with no replay envelope whose real
      // message never arrives would otherwise wait forever. Once stale, DELETE
      // it (message + repair) — explicitly NOT branded undecryptable, since
      // there is no ciphertext to recover and it isn't an authenticity failure.
      if (repair.id.startsWith('live:') &&
          nowUtc().difference(repair.createdAt) >=
              liveGroupNoEnvelopeRepairTtl) {
        final deleted = await deleteGroupPendingKeyRepairIfExact(
          pendingKeyRepairRepo,
          repair,
        );
        if (!deleted) return false;
        await msgRepo.deleteMessage(repair.messageId);
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_PENDING_KEY_REPAIR_SELF_CLEARED',
          details: {
            'groupId': _safeId(repair.groupId),
            'messageId': _safeId(repair.messageId),
            'keyEpoch': repair.keyEpoch,
          },
        );
        return false;
      }
      await recordGroupPendingKeyRepairAttemptIfExact(
        pendingKeyRepairRepo,
        repair,
        lastError: 'waiting for replay envelope',
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_PENDING_KEY_REPAIR_WAITING_FOR_REPLAY_ENVELOPE',
        details: {
          'groupId': _safeId(repair.groupId),
          'messageId': _safeId(repair.messageId),
          'keyEpoch': repair.keyEpoch,
        },
      );
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

      Map<String, dynamic>? replayPayload;
      if (repair.payloadType == groupOfflineReplayPayloadTypeReaction) {
        final reactions = reactionRepo;
        if (reactions == null) {
          throw StateError('missing reaction repository');
        }
        final (result, _) = await handleIncomingGroupReaction(
          groupRepo: groupRepo,
          reactionRepo: reactions,
          msgRepo: msgRepo,
          groupId: repair.groupId,
          senderId: repair.senderPeerId ?? 'unknown',
          transportPeerId: repair.transportPeerId,
          senderDeviceId: envelope['senderDeviceId'] as String?,
          senderPublicKey: envelope['senderPublicKey'] as String?,
          reactionJson: plaintext,
        );
        if (result != HandleGroupReactionResult.success) {
          throw StateError('reaction replay validation rejected: $result');
        }
      } else {
        final payload = Map<String, dynamic>.from(jsonDecode(plaintext) as Map);
        replayPayload = payload;
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
          deferMessageReplay(payload);
          return false;
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
            logicalDeliveryId: payload['logicalDeliveryId'] as String?,
            quotedMessageId: payload['quotedMessageId'] as String?,
            media: (payload['media'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>(),
            mediaAttachmentRepo: mediaAttachmentRepo,
            deliverySource: 'replay',
          );
          if (result == null) {
            throw StateError('replay validation rejected');
          }
        }
      }

      return await _finalizeSuccessfulReplay(repair, replayPayload);
    } catch (e) {
      return await _recordRetryFailureLocked(repair, e);
    }
  }

  Future<bool> _finalizeSuccessfulReplay(
    GroupPendingKeyRepair repair,
    Map<String, dynamic>? replayPayload,
  ) async {
    final message = await msgRepo.getMessage(repair.messageId);
    final deleteSystemPlaceholder =
        message != null &&
        message.status == groupPendingKeyRepairStatusPendingKey &&
        replayPayload != null &&
        _isSystemGroupReplayPayload(replayPayload);
    if (message != null &&
        message.status == groupPendingKeyRepairStatusPendingKey) {
      if (replayPayload != null && _isSystemGroupReplayPayload(replayPayload)) {
        // Delete only after the exact repair completion wins below. A same-id
        // replacement installed while replay was in flight owns the existing
        // placeholder and must survive the stale completion.
      } else {
        throw StateError('replay did not replace pending placeholder');
      }
    }
    final finalized = await finalizeGroupPendingKeyRepairIfExact(
      pendingKeyRepairRepo,
      repair,
    );
    if (!finalized) return false;
    if (deleteSystemPlaceholder) {
      await msgRepo.deleteMessage(repair.messageId);
    }
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
  }

  Future<void> _recordDeferredReplayFailure(
    GroupPendingKeyRepair loaded,
    Object error,
  ) async {
    await runSelfRemovedGroupLifecycleLeaf<void>(
      groupRepo: groupRepo,
      groupId: loaded.groupId,
      action: (_) async {
        final current = await _reloadExactPendingRepair(loaded);
        if (current != null) {
          await _recordRetryFailureLocked(current, error);
        }
      },
    );
  }

  Future<bool> _recordRetryFailureLocked(
    GroupPendingKeyRepair repair,
    Object error,
  ) async {
    final key = await groupRepo.getKeyByGeneration(
      repair.groupId,
      repair.keyEpoch,
    );
    // (1) Key still missing → NEVER terminal; key absence is recoverable
    // (the key may arrive later via key-update/distribution). Requeue.
    if (key == null) {
      await recordGroupPendingKeyRepairAttemptIfExact(
        pendingKeyRepairRepo,
        repair,
        lastError: error.toString(),
      );
      return false;
    }
    // (2) Confirmed crypto/auth failure WITH the key present → bounded: brand
    // undecryptable only once the attempt budget is exhausted, so a single
    // transient hiccup never permanently poisons the message.
    if (_isConfirmedGroupReplayCryptoFailure(error)) {
      if (repair.attempts >= kGroupKeyRepairMaxAttempts) {
        await _finalizeUndecryptable(repair, error.toString());
        return false;
      }
      await recordGroupPendingKeyRepairAttemptIfExact(
        pendingKeyRepairRepo,
        repair,
        lastError: error.toString(),
      );
      return false;
    }
    // (3) Everything else — a transient bridge/internal error
    // (BRIDGE_TIMEOUT/UNKNOWN/INTERNAL_ERROR), a not-yet-injected reaction
    // repo, an ordering StateError, an ambiguous (membership/data-timing)
    // signature reason — is non-terminal: stay pending so a later retry can
    // recover. Never brand undecryptable on a transient/ambiguous failure.
    await recordGroupPendingKeyRepairAttemptIfExact(
      pendingKeyRepairRepo,
      repair,
      lastError: error.toString(),
    );
    return false;
  }

  Future<void> _finalizeUndecryptable(
    GroupPendingKeyRepair repair,
    String error,
  ) async {
    final finalized = await finalizeGroupPendingKeyRepairUndecryptableIfExact(
      pendingKeyRepairRepo,
      repair,
      lastError: error,
    );
    if (!finalized) return;
    final existing = await msgRepo.getMessage(repair.messageId);
    if (existing != null) {
      await msgRepo.saveMessage(
        existing.copyWith(
          text: _groupUndecryptablePlaceholderText,
          status: groupPendingKeyRepairStatusUndecryptable,
        ),
      );
    }
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

/// Reasons that represent a *confirmed* authenticity/tampering failure — not a
/// transient or data/membership-timing issue. Only these may eventually
/// finalize a keyed repair as undecryptable. Ambiguous reasons (missing_*,
/// unknown_sender, revoked_device, group_mismatch, relay_sender_mismatch,
/// recipient_not_entitled, recipient_hash_mismatch) are deliberately EXCLUDED:
/// they reflect not-yet-applied membership/data, and marking them terminal
/// re-introduces false-undecryptable on a just-joined device.
const _confirmedGroupReplayCryptoFailureReasons = <String>{
  'signature_invalid',
  'signature_algorithm_invalid',
  'signed_payload_mismatch',
  'signed_payload_malformed',
  'plaintext_hash_mismatch',
  'plaintext_malformed',
  'sender_key_mismatch',
  'sender_device_mismatch',
  'sender_transport_mismatch',
};

bool _isConfirmedGroupReplayCryptoFailure(Object e) {
  // The Go group.decrypt contract returns only INTERNAL_ERROR / INVALID_INPUT
  // (no distinct AES-GCM auth errorCode), so a BridgeCommandException is NEVER a
  // confirmed crypto failure. All authenticity checks are Dart-side via
  // GroupOfflineReplaySignatureException.
  if (e is! GroupOfflineReplaySignatureException) return false;
  return _confirmedGroupReplayCryptoFailureReasons.contains(e.reason);
}

bool _isSystemGroupReplayPayload(Map<String, dynamic> payload) {
  final text = payload['text'];
  if (text is! String || text.isEmpty) return false;
  try {
    final decoded = jsonDecode(text);
    return decoded is Map && decoded['__sys'] is String;
  } catch (_) {
    return false;
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
