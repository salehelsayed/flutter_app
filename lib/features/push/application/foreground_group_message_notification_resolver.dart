import 'dart:ui' show Locale;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/group_notification_display_policy.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';

typedef ForegroundGroupMessageDecrypt =
    Future<String> Function({
      required String groupKey,
      required String ciphertext,
      required String nonce,
    });

/// Resolves foreground drain-error copy from recipient-owned group state.
///
/// Provider/decrypted display names are never authority. The outer transport
/// must bind to exactly one active local roster device, and ordinary encrypted
/// previews use the exact requested key generation before the shared parity and
/// privacy formatter is allowed to produce visible copy.
Future<BackgroundPushNotificationFallback?>
resolveForegroundGroupMessageNotification({
  required RemoteMessage message,
  required String? localPeerId,
  required GroupRepository groupRepository,
  required ForegroundGroupMessageDecrypt decryptGroup,
  Locale? locale,
}) async {
  final data = message.data;
  if (_trimToNull(data['type']) != 'group_message') return null;

  final groupId = _trimToNull(data['groupId']) ?? _trimToNull(data['group_id']);
  final normalizedLocalPeerId = _trimToNull(localPeerId);
  final senderTransportPeerId = _trimToNull(data['sender_transport_peer_id']);
  if (groupId == null ||
      normalizedLocalPeerId == null ||
      senderTransportPeerId == null) {
    return null;
  }

  final group = await groupRepository.getGroup(groupId);
  final localMember = await groupRepository.getMember(
    groupId,
    normalizedLocalPeerId,
  );
  final displayEligibility = evaluateGroupNotificationDisplayPolicy(
    GroupNotificationDisplayPolicyInput(
      groupExists: group != null,
      hasCurrentLocalMembership: localMember != null,
      groupType: group?.type.toValue(),
      isMuted: group?.isMuted ?? false,
      isArchived: group?.isArchived ?? false,
      isDissolved: group?.isDissolved ?? false,
      hasDissolvedAt: group?.dissolvedAt != null,
      hasSelfRemovedAt: group?.selfRemovedAt != null,
    ),
  );
  final groupName = _trimToNull(group?.name);
  if (group == null ||
      !displayEligibility.shouldDisplay ||
      localMember == null ||
      groupName == null) {
    return null;
  }

  final matches = <GroupMember>[];
  for (final member in await groupRepository.getMembers(groupId)) {
    if (member.groupId != groupId) continue;
    for (final device in member.activeDevicesWithLegacyFallback()) {
      if (device.transportPeerId == senderTransportPeerId) {
        matches.add(member);
      }
    }
  }
  if (matches.length != 1) return null;

  final sender = matches.single;
  final senderPeerId = _trimToNull(sender.peerId);
  final senderUsername = _trimToNull(sender.username);
  final outerSenderPeerId =
      _trimToNull(data['sender_id']) ??
      _trimToNull(data['senderId']) ??
      _trimToNull(data['senderPeerId']) ??
      _trimToNull(data['from']);
  final senderRoleAllowed = group.type == GroupType.announcement
      ? sender.role == MemberRole.admin
      : sender.role == MemberRole.admin || sender.role == MemberRole.writer;
  if (senderPeerId == null ||
      senderUsername == null ||
      senderPeerId == normalizedLocalPeerId ||
      (outerSenderPeerId != null && outerSenderPeerId != senderPeerId) ||
      !senderRoleAllowed) {
    return null;
  }

  final expectedMessageId = remoteNotificationMessageIdFromData(data);
  final context = GroupMessageNotificationContext(
    groupId: groupId,
    groupName: groupName,
    localPeerId: normalizedLocalPeerId,
    senderPeerId: senderPeerId,
    senderTransportPeerId: senderTransportPeerId,
    senderUsername: senderUsername,
    expectedMessageId: expectedMessageId,
  );

  final rawKeyEpoch = _trimToNull(data['keyEpoch'] ?? data['key_epoch']);
  final ciphertext = _trimToNull(data['ciphertext']);
  final nonce = _trimToNull(data['nonce']);
  final previewUnavailable = data['preview_unavailable']?.toString() == '1';
  final hasAnyEncryptedInput =
      rawKeyEpoch != null || ciphertext != null || nonce != null;

  try {
    if (previewUnavailable && !hasAnyEncryptedInput) {
      return await resolveBackgroundPushNotification(
        message,
        groupMessageContext: context,
        locale: locale,
      );
    }

    final requestedEpoch = int.tryParse(rawKeyEpoch ?? '');
    if (requestedEpoch == null ||
        requestedEpoch < 0 ||
        ciphertext == null ||
        nonce == null) {
      return null;
    }
    final key = await groupRepository.getKeyByGeneration(
      groupId,
      requestedEpoch,
    );
    final groupKey = _trimToNull(key?.encryptedKey);
    if (key == null ||
        key.groupId != groupId ||
        key.keyGeneration != requestedEpoch ||
        groupKey == null ||
        isSecureStoreReference(groupKey)) {
      return null;
    }

    return await resolveBackgroundPushNotification(
      message,
      groupMessageContext: context,
      locale: locale,
      decryptGroup:
          ({
            required groupId,
            required keyEpoch,
            required ciphertext,
            required nonce,
          }) async {
            if (groupId != context.groupId || keyEpoch != requestedEpoch) {
              throw const OrdinaryMessageNotificationIntegrityException(
                'foreground_group_decrypt_scope_mismatch',
              );
            }
            return decryptGroup(
              groupKey: groupKey,
              ciphertext: ciphertext,
              nonce: nonce,
            );
          },
    );
  } on OrdinaryMessageNotificationIntegrityException {
    return null;
  }
}

String? _trimToNull(Object? value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
