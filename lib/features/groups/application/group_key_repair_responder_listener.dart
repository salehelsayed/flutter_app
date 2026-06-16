import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Targeted single-device key (re)delivery used by the responder. Signature
/// mirrors [distributeGroupKeyAtEpochToPeer] so production wires that function
/// directly while tests inject a fake that records its arguments. Returns the
/// number of device targets that confirmed delivery.
typedef DistributeGroupKeyAtEpochToPeer =
    Future<int> Function({
      required String groupId,
      required String peerId,
      required int keyEpoch,
    });

/// Admin-side responder for the active key-pull (Slice 2 / UDM-G).
///
/// Subscribes to [groupKeyRepairRequestStream] (the new router case). For each
/// signed `group_key_repair_request`:
///   1. verifies the requester's signature against their bound device signing
///      key (threat-model gate #1);
///   2. authorizes — the requester is/was a member entitled to the requested
///      epoch AND self holds rotate/creator rights (gate #2);
///   3. rate-limits per `(requester, groupId, epoch)` in-memory (gate #3);
///   4. loads `getKeyByGeneration(groupId, keyEpoch)` — null ⇒ no-op (never mint
///      a new epoch);
///   5. re-runs a SINGLE-device key delivery for the requester at the EXACT
///      requested epoch via [distributeGroupKeyAtEpochToPeer] (gate #4 — ML-KEM
///      encrypt-to-recipient-device).
///
/// It NEVER calls `group:updateKey` / `rotateAndDistributeGroupKey` /
/// `getLatestKey` — a repair response advances no epoch.
class GroupKeyRepairResponderListener {
  final Stream<ChatMessage> _stream;
  final GroupRepository _groupRepo;
  final Bridge _bridge;
  final Future<String?> Function() _getOwnPeerId;
  final DistributeGroupKeyAtEpochToPeer _distributeGroupKeyAtEpochToPeer;

  /// Per-(requester, groupId, epoch) re-deliveries already served this process
  /// lifetime. In-memory only (resets on restart — the window is the process
  /// lifetime, kept conservative deliberately).
  final Map<String, int> _servedByKey = {};

  /// Cap on re-deliveries per `(requester, groupId, epoch)` before the responder
  /// rate-limits and sends nothing.
  final int maxRedeliveriesPerKey;

  StreamSubscription<ChatMessage>? _subscription;
  Future<void> _processing = Future<void>.value();

  GroupKeyRepairResponderListener({
    required Stream<ChatMessage> groupKeyRepairRequestStream,
    required GroupRepository groupRepo,
    required Bridge bridge,
    required Future<String?> Function() getOwnPeerId,
    required DistributeGroupKeyAtEpochToPeer distributeGroupKeyAtEpochToPeer,
    this.maxRedeliveriesPerKey = 1,
  }) : _stream = groupKeyRepairRequestStream,
       _groupRepo = groupRepo,
       _bridge = bridge,
       _getOwnPeerId = getOwnPeerId,
       _distributeGroupKeyAtEpochToPeer = distributeGroupKeyAtEpochToPeer;

  void start() {
    if (_subscription != null) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_KEY_REPAIR_RESPONDER_START',
      details: {},
    );
    _subscription = _stream.listen(
      _enqueue,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_REPAIR_RESPONDER_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void _enqueue(ChatMessage message) {
    _processing = _processing.then((_) => _handle(message));
  }

  Future<void> _handle(ChatMessage message) async {
    try {
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      if (json['type'] != groupKeyRepairRequestType) return;
      final payload = json['payload'];
      if (payload is! Map<String, dynamic>) return;

      final groupId = (payload['groupId'] as String?)?.trim();
      final keyEpoch = _readInt(payload['keyEpoch']);
      final requesterPeerId = (payload['requesterPeerId'] as String?)?.trim();
      final requesterDeviceId = (payload['requesterDeviceId'] as String?)
          ?.trim();
      final signatureAlgorithm = (payload['signatureAlgorithm'] as String?)
          ?.trim();
      final signedPayload = (payload['signedPayload'] as String?);
      final signature = (payload['signature'] as String?);

      if (groupId == null ||
          groupId.isEmpty ||
          keyEpoch == null ||
          requesterPeerId == null ||
          requesterPeerId.isEmpty ||
          requesterDeviceId == null ||
          requesterDeviceId.isEmpty ||
          signedPayload == null ||
          signedPayload.isEmpty ||
          signature == null ||
          signature.isEmpty) {
        _emitUnauthorized(groupId, keyEpoch, 'malformed_request');
        return;
      }

      final group = await _groupRepo.getGroup(groupId);
      if (group == null || group.isDissolved) {
        _emitUnauthorized(groupId, keyEpoch, 'group_not_found_or_dissolved');
        return;
      }

      // (gate #2a) Self must hold rotate/creator rights to act as responder.
      final ownPeerId = (await _getOwnPeerId())?.trim();
      if (ownPeerId == null || ownPeerId.isEmpty) {
        _emitUnauthorized(groupId, keyEpoch, 'no_self_identity');
        return;
      }
      final selfMember = await _groupRepo.getMember(groupId, ownPeerId);
      final selfCanRotate =
          selfMember?.permissions.allows(
            GroupMemberPermission.rotateKeys,
            selfMember.role,
          ) ??
          false;
      if (!selfCanRotate && group.createdBy != ownPeerId) {
        _emitUnauthorized(groupId, keyEpoch, 'self_not_authorized');
        return;
      }

      // (gate #2b) Requester must be a current member entitled to this epoch.
      final requesterMember = await _groupRepo.getMember(
        groupId,
        requesterPeerId,
      );
      if (requesterMember == null) {
        _emitUnauthorized(groupId, keyEpoch, 'requester_not_member');
        return;
      }

      // (gate #1) Verify the request signature against the requester's bound
      // device signing key — never an arbitrary key from the wire.
      final device = requesterMember.findDeviceById(
        requesterDeviceId,
        allowLegacyFallback: requesterMember.devices.isEmpty,
      );
      final requesterSigningKey = device?.deviceSigningPublicKey.trim();
      if (requesterSigningKey == null || requesterSigningKey.isEmpty) {
        _emitUnauthorized(groupId, keyEpoch, 'requester_device_unbound');
        return;
      }
      if (signatureAlgorithm != groupKeyRepairRequestSignatureAlgorithm) {
        _emitUnauthorized(groupId, keyEpoch, 'unsupported_signature_algorithm');
        return;
      }
      final expectedSignedPayload =
          canonicalGroupKeyRepairRequestSignedPayload(
        groupId: groupId,
        keyEpoch: keyEpoch,
        requesterPeerId: requesterPeerId,
        requesterDeviceId: requesterDeviceId,
      );
      if (signedPayload != expectedSignedPayload) {
        _emitUnauthorized(groupId, keyEpoch, 'signed_payload_mismatch');
        return;
      }
      final signatureValid = await callVerifyPayload(
        bridge: _bridge,
        publicKey: requesterSigningKey,
        data: signedPayload,
        signature: signature,
      );
      if (!signatureValid) {
        _emitUnauthorized(groupId, keyEpoch, 'invalid_signature');
        return;
      }

      // (gate #3) Rate-limit per (requester, groupId, epoch).
      final rateKey = '$requesterPeerId:$groupId:$keyEpoch';
      final served = _servedByKey[rateKey] ?? 0;
      if (served >= maxRedeliveriesPerKey) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_REPAIR_RESPONDER_RATE_LIMITED',
          details: {
            'groupId': _safeId(groupId),
            'keyEpoch': keyEpoch,
            'requesterPeerId': _safeId(requesterPeerId),
          },
        );
        return;
      }

      // (gate #4) Only re-deliver an epoch we actually hold. Never mint.
      final epochKey = await _groupRepo.getKeyByGeneration(groupId, keyEpoch);
      if (epochKey == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_REPAIR_RESPONDER_EPOCH_NOT_HELD',
          details: {'groupId': _safeId(groupId), 'keyEpoch': keyEpoch},
        );
        return;
      }

      // Count the attempt BEFORE delivery so a flood is capped even if delivery
      // returns 0 (the requester re-sends; the responder must not retry forever).
      _servedByKey[rateKey] = served + 1;

      final delivered = await _distributeGroupKeyAtEpochToPeer(
        groupId: groupId,
        peerId: requesterPeerId,
        keyEpoch: keyEpoch,
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_REPAIR_RESPONDER_ACCEPTED',
        details: {
          'groupId': _safeId(groupId),
          'keyEpoch': keyEpoch,
          'requesterPeerId': _safeId(requesterPeerId),
          'deliveredDeviceCount': delivered,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_REPAIR_RESPONDER_HANDLE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _emitUnauthorized(String? groupId, int? keyEpoch, String reason) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_KEY_REPAIR_RESPONDER_UNAUTHORIZED',
      details: {
        if (groupId != null) 'groupId': _safeId(groupId),
        'keyEpoch': ?keyEpoch,
        'reason': reason,
      },
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
  }
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String _safeId(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;
