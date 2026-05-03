import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Listens for incoming group_key_update messages (1:1 P2P) and saves
/// the new group key to the local repository.
///
/// These messages are sent by an admin after key rotation (e.g. after
/// removing a member). The new key is encrypted with the recipient's
/// ML-KEM public key.
class GroupKeyUpdateListener {
  final Stream<ChatMessage> _stream;
  final GroupRepository _groupRepo;
  final Bridge _bridge;
  final Future<String?> Function() _getOwnMlKemSecretKey;
  final Future<String?> Function()? _getOwnPeerId;
  final Future<String?> Function()? _getOwnDeviceId;
  final AppendGroupEventLogEntry? _appendGroupEventLogEntry;
  final RetryPendingGroupKeyRepairs? _retryPendingGroupKeyRepairs;
  final Map<String, String> _acceptedSignedTransitionAuditHashesBySourceId = {};

  StreamSubscription<ChatMessage>? _subscription;

  GroupKeyUpdateListener({
    required Stream<ChatMessage> groupKeyUpdateStream,
    required GroupRepository groupRepo,
    required Bridge bridge,
    required Future<String?> Function() getOwnMlKemSecretKey,
    Future<String?> Function()? getOwnPeerId,
    Future<String?> Function()? getOwnDeviceId,
    AppendGroupEventLogEntry? appendGroupEventLogEntry,
    RetryPendingGroupKeyRepairs? retryPendingGroupKeyRepairs,
  }) : _stream = groupKeyUpdateStream,
       _groupRepo = groupRepo,
       _bridge = bridge,
       _getOwnMlKemSecretKey = getOwnMlKemSecretKey,
       _getOwnPeerId = getOwnPeerId,
       _getOwnDeviceId = getOwnDeviceId,
       _appendGroupEventLogEntry = appendGroupEventLogEntry,
       _retryPendingGroupKeyRepairs = retryPendingGroupKeyRepairs;

  void start() {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_KEY_UPDATE_LISTENER_START',
      details: {},
    );

    _subscription = _stream.listen(
      _handleMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  Future<void> _handleMessage(ChatMessage message) async {
    try {
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      final encrypted = json['encrypted'] as Map<String, dynamic>?;
      if (encrypted == null) return;

      final kem = encrypted['kem'] as String;
      final ciphertext = encrypted['ciphertext'] as String;
      final nonce = encrypted['nonce'] as String;

      final secretKey = await _getOwnMlKemSecretKey();
      if (secretKey == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_NO_SECRET_KEY',
          details: {},
        );
        return;
      }

      final decryptResult = await callDecryptMessage(
        bridge: _bridge,
        ownMlKemSecretKey: secretKey,
        kem: kem,
        ciphertext: ciphertext,
        nonce: nonce,
      );

      if (decryptResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_DECRYPT_FAILED',
          details: {'errorCode': decryptResult['errorCode']},
        );
        return;
      }

      final plaintext = decryptResult['plaintext'] as String;
      final keyData = jsonDecode(plaintext) as Map<String, dynamic>;
      final groupId = keyData['groupId'] as String;
      final keyGeneration = keyData['keyGeneration'] as int;
      final encryptedKey = keyData['encryptedKey'] as String;
      final sourcePeerId = keyData['sourcePeerId'] as String?;
      final sourceDeviceId = keyData['sourceDeviceId'] as String?;
      final sourceTransportPeerId = keyData['sourceTransportPeerId'] as String?;
      final recipientPeerId = keyData['recipientPeerId'] as String?;
      final recipientDeviceId = keyData['recipientDeviceId'] as String?;
      final recipientTransportPeerId =
          keyData['recipientTransportPeerId'] as String?;
      final recipientKeyPackageId = keyData['recipientKeyPackageId'] as String?;
      final signatureAlgorithm = keyData['signatureAlgorithm'] as String?;
      final signedPayload = keyData['signedPayload'] as String?;
      final signature = keyData['signature'] as String?;
      final payloadSourceEventId = _readNonEmptyString(
        keyData['sourceEventId'],
      );
      final payloadEventAt = _parseUtcTimestamp(keyData['eventAt']);
      final eventLogAppendIsWired = _appendGroupEventLogEntry != null;

      final group = await _groupRepo.getGroup(groupId);
      if (group == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_GROUP_NOT_FOUND',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'keyGeneration': keyGeneration,
          },
        );
        return;
      }

      if (group.isDissolved) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_GROUP_DISSOLVED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'keyGeneration': keyGeneration,
          },
        );
        return;
      }

      if (sourcePeerId == null || sourcePeerId.isEmpty) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_INVALID_SIGNATURE',
          details: {'reason': 'missing_source_peer'},
        );
        return;
      }

      final resolvedSourceEventId =
          payloadSourceEventId ??
          (eventLogAppendIsWired
              ? null
              : message.confirmNonce ??
                    'group_key_update:$groupId:$sourcePeerId:${message.timestamp}:$keyGeneration');
      final resolvedEventAt =
          payloadEventAt ??
          (eventLogAppendIsWired
              ? null
              : DateTime.tryParse(message.timestamp)?.toUtc() ??
                    DateTime.now().toUtc());
      if (resolvedSourceEventId == null || resolvedEventAt == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_SIGNED_AUDIT_REJECTED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'reason': 'missing_signed_audit_metadata',
          },
        );
        return;
      }

      final senderMember = await _groupRepo.getMember(groupId, sourcePeerId);
      final senderCanRotateKeys =
          senderMember?.permissions.allows(
            GroupMemberPermission.rotateKeys,
            senderMember.role,
          ) ??
          false;
      if (!senderCanRotateKeys) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_UNAUTHORIZED_SENDER',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'sourcePeerId': sourcePeerId.length > 8
                ? sourcePeerId.substring(0, 8)
                : sourcePeerId,
            'keyGeneration': keyGeneration,
          },
        );
        return;
      }

      final sourceDevice = _resolveSourceDevice(
        senderMember: senderMember!,
        sourcePeerId: sourcePeerId,
        sourceDeviceId: sourceDeviceId,
        sourceTransportPeerId: sourceTransportPeerId,
        transportPeerId: message.from,
      );
      if (sourceDevice == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_UNBOUND_SOURCE_DEVICE',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'sourcePeerId': sourcePeerId.length > 8
                ? sourcePeerId.substring(0, 8)
                : sourcePeerId,
            'keyGeneration': keyGeneration,
          },
        );
        return;
      }

      final expectedSignedPayload = sourcePeerId == null
          ? null
          : canonicalGroupKeyUpdateSignedPayload(
              groupId: groupId,
              sourcePeerId: sourcePeerId,
              sourceDeviceId: sourceDeviceId,
              sourceTransportPeerId: sourceTransportPeerId,
              recipientPeerId: recipientPeerId,
              recipientDeviceId: recipientDeviceId,
              recipientTransportPeerId: recipientTransportPeerId,
              recipientKeyPackageId: recipientKeyPackageId,
              keyGeneration: keyGeneration,
              encryptedKey: encryptedKey,
            );
      final senderPublicKey = sourceDevice.deviceSigningPublicKey;
      final hasValidSignatureEnvelope =
          signatureAlgorithm == groupKeyUpdateSignatureAlgorithm &&
          signedPayload != null &&
          signature != null &&
          signature.isNotEmpty &&
          signedPayload == expectedSignedPayload &&
          senderPublicKey.trim().isNotEmpty;

      if (!hasValidSignatureEnvelope) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_INVALID_SIGNATURE',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'sourcePeerId': sourcePeerId.length > 8
                ? sourcePeerId.substring(0, 8)
                : sourcePeerId,
            'keyGeneration': keyGeneration,
          },
        );
        return;
      }

      final verifiedSenderPublicKey = senderPublicKey;
      final verifiedSignedPayload = signedPayload!;
      final verifiedSignature = signature!;
      final signatureValid = await callVerifyPayload(
        bridge: _bridge,
        publicKey: verifiedSenderPublicKey,
        data: verifiedSignedPayload,
        signature: verifiedSignature,
      );
      if (!signatureValid) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_INVALID_SIGNATURE',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'sourcePeerId': sourcePeerId.length > 8
                ? sourcePeerId.substring(0, 8)
                : sourcePeerId,
            'keyGeneration': keyGeneration,
          },
        );
        return;
      }

      if (!await _isBoundToLocalRecipient(
        groupId: groupId,
        recipientPeerId: recipientPeerId,
        recipientDeviceId: recipientDeviceId,
        recipientTransportPeerId: recipientTransportPeerId,
        recipientKeyPackageId: recipientKeyPackageId,
        messageTo: message.to,
      )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_RECIPIENT_DEVICE_MISMATCH',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'keyGeneration': keyGeneration,
          },
        );
        return;
      }

      if (eventLogAppendIsWired &&
          !keyData.containsKey(signedGroupTransitionAuditField)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_SIGNED_AUDIT_REJECTED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'reason': 'missing_signed_audit',
          },
        );
        return;
      }

      if (keyData.containsKey(signedGroupTransitionAuditField)) {
        final signedAuditHash = signedGroupTransitionAuditHashFromPayload(
          keyData,
        );
        final acceptedHash =
            _acceptedSignedTransitionAuditHashesBySourceId[resolvedSourceEventId];
        if (acceptedHash != null) {
          if (signedAuditHash != null && acceptedHash == signedAuditHash) {
            return;
          }
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_KEY_UPDATE_LISTENER_SIGNED_AUDIT_REJECTED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'reason': 'conflicting_replay',
            },
          );
          return;
        }

        final auditCheck = await verifyGroupTransitionAudit(
          bridge: _bridge,
          containerPayload: keyData,
          groupId: groupId,
          transitionType: 'group_key_update',
          sourceEventId: resolvedSourceEventId,
          eventAt: resolvedEventAt,
          actorPeerId: sourcePeerId,
          actorUsername: senderMember.username ?? sourcePeerId,
          actorSigningPublicKey: verifiedSenderPublicKey,
          actorDeviceId: sourceDeviceId,
          actorTransportPeerId: sourceTransportPeerId,
          expectedTransitionSubject: buildGroupKeyUpdateTransitionSubject(
            groupId: groupId,
            sourcePeerId: sourcePeerId,
            sourceDeviceId: sourceDeviceId,
            sourceTransportPeerId: sourceTransportPeerId,
            recipientPeerId: recipientPeerId,
            recipientDeviceId: recipientDeviceId,
            recipientTransportPeerId: recipientTransportPeerId,
            recipientKeyPackageId: recipientKeyPackageId,
            keyGeneration: keyGeneration,
            encryptedKey: encryptedKey,
          ),
        );
        if (!auditCheck.isValid) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_KEY_UPDATE_LISTENER_SIGNED_AUDIT_REJECTED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'reason': auditCheck.failure?.reason ?? 'signature_invalid',
            },
          );
          return;
        }
        final verifiedAudit = auditCheck.verification!;

        final append = _appendGroupEventLogEntry;
        if (append != null) {
          final transitionSubject = buildGroupKeyUpdateTransitionSubject(
            groupId: groupId,
            sourcePeerId: sourcePeerId,
            sourceDeviceId: sourceDeviceId,
            sourceTransportPeerId: sourceTransportPeerId,
            recipientPeerId: recipientPeerId,
            recipientDeviceId: recipientDeviceId,
            recipientTransportPeerId: recipientTransportPeerId,
            recipientKeyPackageId: recipientKeyPackageId,
            keyGeneration: keyGeneration,
            encryptedKey: encryptedKey,
          );
          await append(
            groupId: groupId,
            eventType: 'group_key_update',
            sourcePeerId: sourcePeerId,
            sourceEventId: resolvedSourceEventId,
            sourceTimestamp: resolvedEventAt.toIso8601String(),
            payload: {
              'groupId': groupId,
              'sourcePeerId': sourcePeerId,
              'sourceDeviceId': sourceDevice.deviceId,
              'sourceTransportPeerId': sourceDevice.transportPeerId,
              if (recipientPeerId != null) 'recipientPeerId': recipientPeerId,
              if (recipientDeviceId != null)
                'recipientDeviceId': recipientDeviceId,
              'keyGeneration': keyGeneration,
              'transitionSubject': transitionSubject,
              'encryptedKeyHash': transitionSubject['encryptedKeyHash'],
              'keyUpdateSignatureAlgorithm': signatureAlgorithm,
              'keyUpdateSignedPayloadHash': _hashText(verifiedSignedPayload),
              'keyUpdateSignatureHash': _hashText(verifiedSignature),
              'signedTransitionAuditHash': verifiedAudit.auditHash,
              'signedTransitionAuditSourceEventId': verifiedAudit.sourceEventId,
              'signedTransitionAuditEventAt': verifiedAudit.eventAt
                  .toIso8601String(),
            },
          );
          _acceptedSignedTransitionAuditHashesBySourceId[resolvedSourceEventId] =
              verifiedAudit.auditHash;
        }
      }

      try {
        await callGroupUpdateKey(
          _bridge,
          groupId: groupId,
          groupKey: encryptedKey,
          keyEpoch: keyGeneration,
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_UPDATE_LISTENER_UPDATE_KEY_FAILED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'keyGeneration': keyGeneration,
            'error': e.toString(),
          },
        );
        return;
      }

      final keyInfo = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: keyGeneration,
        encryptedKey: encryptedKey,
        createdAt: DateTime.now().toUtc(),
      );
      await _groupRepo.saveKey(keyInfo);

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_UPDATE_LISTENER_SAVED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'keyGeneration': keyGeneration,
        },
      );
      await _retryPendingGroupKeyRepairs?.call(
        GroupPendingKeyRepairRetryRequest(
          groupId: groupId,
          keyEpoch: keyGeneration,
        ),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_UPDATE_LISTENER_HANDLE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
  }

  GroupMemberDeviceIdentity? _resolveSourceDevice({
    required GroupMember senderMember,
    required String sourcePeerId,
    required String? sourceDeviceId,
    required String? sourceTransportPeerId,
    required String transportPeerId,
  }) {
    final expectedTransportPeerId =
        sourceTransportPeerId?.trim().isNotEmpty == true
        ? sourceTransportPeerId!.trim()
        : transportPeerId.trim();
    if (expectedTransportPeerId.isEmpty) {
      return null;
    }
    if (transportPeerId.trim().isNotEmpty &&
        transportPeerId.trim() != expectedTransportPeerId) {
      return null;
    }

    if (sourceDeviceId?.trim().isNotEmpty == true) {
      final device = senderMember.findDeviceById(
        sourceDeviceId,
        allowLegacyFallback: senderMember.devices.isEmpty,
      );
      if (device == null || device.transportPeerId != expectedTransportPeerId) {
        return null;
      }
      return device;
    }

    return senderMember.findDeviceByTransportPeerId(
      expectedTransportPeerId,
      allowLegacyFallback: senderMember.devices.isEmpty,
    );
  }

  Future<bool> _isBoundToLocalRecipient({
    required String groupId,
    required String? recipientPeerId,
    required String? recipientDeviceId,
    required String? recipientTransportPeerId,
    required String? recipientKeyPackageId,
    required String messageTo,
  }) async {
    final hasDeviceBinding =
        recipientPeerId?.trim().isNotEmpty == true ||
        recipientDeviceId?.trim().isNotEmpty == true ||
        recipientTransportPeerId?.trim().isNotEmpty == true ||
        recipientKeyPackageId?.trim().isNotEmpty == true;
    if (!hasDeviceBinding) {
      return true;
    }

    final ownPeerId = (await _getOwnPeerId?.call())?.trim();
    if (recipientPeerId?.trim().isNotEmpty == true &&
        (ownPeerId == null || ownPeerId != recipientPeerId!.trim())) {
      return false;
    }

    final memberPeerId = recipientPeerId?.trim().isNotEmpty == true
        ? recipientPeerId!.trim()
        : ownPeerId;
    if (memberPeerId == null || memberPeerId.isEmpty) {
      return false;
    }
    final member = await _groupRepo.getMember(groupId, memberPeerId);
    if (member == null) {
      return false;
    }

    final ownDeviceId = (await _getOwnDeviceId?.call())?.trim();
    final expectedDeviceId = recipientDeviceId?.trim();
    if (expectedDeviceId == null || expectedDeviceId.isEmpty) {
      return member.devices.isEmpty;
    }
    if (ownDeviceId != null &&
        ownDeviceId.isNotEmpty &&
        ownDeviceId != expectedDeviceId) {
      return false;
    }

    final device = member.findDeviceById(
      expectedDeviceId,
      allowLegacyFallback: member.devices.isEmpty,
    );
    if (device == null) {
      return false;
    }
    final expectedTransportPeerId = recipientTransportPeerId?.trim();
    if (expectedTransportPeerId != null &&
        expectedTransportPeerId.isNotEmpty &&
        device.transportPeerId != expectedTransportPeerId) {
      return false;
    }
    if (messageTo.trim().isNotEmpty &&
        expectedTransportPeerId != null &&
        expectedTransportPeerId.isNotEmpty &&
        messageTo.trim() != expectedTransportPeerId) {
      return false;
    }
    final expectedKeyPackageId = recipientKeyPackageId?.trim();
    if (expectedKeyPackageId != null &&
        expectedKeyPackageId.isNotEmpty &&
        device.keyPackageId != expectedKeyPackageId) {
      return false;
    }
    return true;
  }

  String? _readNonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  DateTime? _parseUtcTimestamp(Object? value) {
    final text = _readNonEmptyString(value);
    return text == null ? null : DateTime.tryParse(text)?.toUtc();
  }

  String _hashText(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }
}
