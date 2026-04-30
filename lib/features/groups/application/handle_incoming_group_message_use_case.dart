import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const _maxIncomingMessageFutureClockSkew = Duration(minutes: 5);

/// Handles an incoming group message.
///
/// Verifies the group exists and the sender is a known member.
/// Checks for duplicates before saving. Returns the persisted [GroupMessage]
/// or null if the message was ignored.
Future<GroupMessage?> handleIncomingGroupMessage({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String senderId,
  required String senderUsername,
  required int keyEpoch,
  required String text,
  required String timestamp,
  String? selfPeerId,
  String? messageId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
  AppendGroupEventLogEntry? appendGroupEventLogEntry,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
    },
  );

  final sanitizedText = sanitizeMessageText(text);
  final mediaValidation = _validateIncomingMediaDescriptors(media);
  if (!mediaValidation.isValid) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_REJECTED_INVALID_MEDIA',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        'messageId': messageId,
        'reason': mediaValidation.reason,
      },
    );
    return null;
  }

  // Prefer messageId-based dedupe before any group/member lookups when event-log
  // tamper gating is not installed. If DB-002 logging is installed, the log
  // checks replay/tamper before dedupe can silently ignore a changed duplicate.
  if (appendGroupEventLogEntry == null &&
      messageId != null &&
      messageId.isNotEmpty) {
    final existsById = await msgRepo.existsByMessageId(messageId);
    if (existsById) {
      await _enrichExistingDuplicateMessage(
        msgRepo: msgRepo,
        messageId: messageId,
        quotedMessageId: quotedMessageId,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'dedupeBy': 'messageId',
        },
      );
      return null;
    }
  }

  // 1. Load group from repo (if not found, ignore)
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_UNKNOWN_GROUP',
      details: {},
    );
    return null;
  }

  // Parse timestamp before applying membership-boundary checks.
  final now = DateTime.now().toUtc();

  final normalizedTimestamp = _normalizeIncomingMessageTimestamp(
    timestamp: timestamp,
    receivedAt: now,
    groupId: groupId,
    senderId: senderId,
  );

  final dissolvedAt = group.dissolvedAt?.toUtc();
  if (group.isDissolved &&
      (dissolvedAt == null || !normalizedTimestamp.isBefore(dissolvedAt))) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_DISSOLVED_AFTER_CUTOFF',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        if (dissolvedAt != null) 'dissolvedAt': dissolvedAt.toIso8601String(),
      },
    );
    return null;
  }

  // 2. Check sender is a member (optional: allow messages from non-members
  //    in case member list is stale; log a warning)
  final member = await groupRepo.getMember(groupId, senderId);
  if (member == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_UNKNOWN_SENDER',
      details: {
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      },
    );

    final removalCutoff = await msgRepo.getLatestRemovalTimestampForSender(
      groupId,
      senderId,
    );
    if (removalCutoff != null && !normalizedTimestamp.isBefore(removalCutoff)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'cutoffAt': removalCutoff.toIso8601String(),
        },
      );
      return null;
    }

    // Still process the message — member list may be stale or the message
    // crossed the accepted removal boundary before the persisted cutoff.
  }
  final sanitizedSenderUsername = sanitizeUsername(senderUsername).trim();

  if (appendGroupEventLogEntry != null) {
    final sourceEventId = messageId != null && messageId.isNotEmpty
        ? messageId
        : 'message:$groupId:$senderId:${normalizedTimestamp.toIso8601String()}:$sanitizedText';
    await appendGroupEventLogEntry(
      groupId: groupId,
      eventType: 'message',
      sourcePeerId: senderId,
      sourceEventId: sourceEventId,
      sourceTimestamp: normalizedTimestamp.toIso8601String(),
      payload: {
        'messageId': messageId,
        'groupId': groupId,
        'senderId': senderId,
        'senderUsername': sanitizedSenderUsername,
        'text': sanitizedText,
        'timestamp': normalizedTimestamp.toIso8601String(),
        'keyEpoch': keyEpoch,
        'quotedMessageId': quotedMessageId,
        'media': media ?? const <Map<String, dynamic>>[],
      },
    );
  }

  if (messageId != null && messageId.isNotEmpty) {
    final existsById = await msgRepo.existsByMessageId(messageId);
    if (existsById) {
      await _enrichExistingDuplicateMessage(
        msgRepo: msgRepo,
        messageId: messageId,
        quotedMessageId: quotedMessageId,
        media: media,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
          'dedupeBy': 'messageId',
        },
      );
      return null;
    }
  }

  if (member != null &&
      sanitizedSenderUsername.isNotEmpty &&
      member.username?.trim() != sanitizedSenderUsername) {
    await groupRepo.saveMember(
      GroupMember(
        groupId: member.groupId,
        peerId: member.peerId,
        username: sanitizedSenderUsername,
        role: member.role,
        publicKey: member.publicKey,
        mlKemPublicKey: member.mlKemPublicKey,
        joinedAt: member.joinedAt,
      ),
    );
  }

  // Fallback: content-based dedupe for messages without a messageId.
  final isDuplicate = await msgRepo.existsByContent(
    groupId,
    senderId,
    sanitizedText,
    normalizedTimestamp,
  );
  if (isDuplicate) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        'dedupeBy': 'content',
      },
    );
    return null;
  }

  // 4. Use wire messageId if provided, otherwise generate one
  final resolvedMessageId = (messageId != null && messageId.isNotEmpty)
      ? messageId
      : const Uuid().v4();
  final isSelfDelivery = selfPeerId != null && senderId == selfPeerId;

  // 5. Create GroupMessage (isIncoming: true)
  final message = GroupMessage(
    id: resolvedMessageId,
    groupId: groupId,
    senderPeerId: senderId,
    senderUsername: sanitizedSenderUsername,
    text: sanitizedText,
    timestamp: normalizedTimestamp,
    quotedMessageId: quotedMessageId,
    keyGeneration: keyEpoch,
    status: isSelfDelivery ? 'sent' : 'delivered',
    isIncoming: !isSelfDelivery,
    createdAt: now,
  );

  // 6. Save to repo
  await msgRepo.saveMessage(message);

  // 7. Save media attachments (pending for relay download)
  await _saveIncomingMediaAttachments(
    messageId: resolvedMessageId,
    media: media,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
    details: {
      'messageId': resolvedMessageId.length > 8
          ? resolvedMessageId.substring(0, 8)
          : resolvedMessageId,
    },
  );

  return message;
}

DateTime _normalizeIncomingMessageTimestamp({
  required String timestamp,
  required DateTime receivedAt,
  required String groupId,
  required String senderId,
}) {
  final parsedTimestamp = DateTime.tryParse(timestamp)?.toUtc();
  if (parsedTimestamp == null) {
    return receivedAt;
  }

  final latestAllowed = receivedAt.add(_maxIncomingMessageFutureClockSkew);
  if (!parsedTimestamp.isAfter(latestAllowed)) {
    return parsedTimestamp;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_FUTURE_TIMESTAMP_CLAMPED',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      'timestamp': parsedTimestamp.toIso8601String(),
    },
  );
  return receivedAt;
}

Future<void> _enrichExistingDuplicateMessage({
  required GroupMessageRepository msgRepo,
  required String messageId,
  String? quotedMessageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  final existing = await msgRepo.getMessage(messageId);
  if (existing != null &&
      (existing.quotedMessageId == null || existing.quotedMessageId!.isEmpty) &&
      quotedMessageId != null &&
      quotedMessageId.isNotEmpty) {
    await msgRepo.saveMessage(
      existing.copyWith(quotedMessageId: quotedMessageId),
    );
  }

  await _saveIncomingMediaAttachments(
    messageId: messageId,
    media: media,
    mediaAttachmentRepo: mediaAttachmentRepo,
  );
}

Future<void> _saveIncomingMediaAttachments({
  required String messageId,
  List<Map<String, dynamic>>? media,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (media == null || mediaAttachmentRepo == null) return;

  final existingAttachments = await mediaAttachmentRepo
      .getAttachmentsForMessage(messageId);
  final existingIds = existingAttachments
      .map((attachment) => attachment.id)
      .toSet();

  for (final rawAttachment in media) {
    final attachment =
        GroupMediaMimePolicy.sanitizeWireAttachment(
          rawAttachment,
          messageId: messageId,
        ).copyWith(
          contentHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            _optionalString(rawAttachment, 'contentHash'),
          ),
          thumbnailHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            _optionalString(rawAttachment, 'thumbnailHash'),
          ),
        );
    if (!existingIds.add(attachment.id)) continue;
    await mediaAttachmentRepo.saveAttachment(attachment);
  }
}

GroupMediaValidationResult _validateIncomingMediaDescriptors(
  List<Map<String, dynamic>>? media,
) {
  if (media == null || media.isEmpty) {
    return const GroupMediaValidationResult.valid();
  }

  for (final rawAttachment in media) {
    final rawMime = rawAttachment['mime'];
    final rawMediaType = rawAttachment['mediaType'];
    final mime = rawMime is String ? rawMime : null;
    final mediaType = rawMediaType is String ? rawMediaType : null;
    final validation = GroupMediaMimePolicy.validateDescriptor(
      mime: mime,
      mediaType: mediaType,
    );
    if (!validation.isValid) return validation;

    final contentHashValidation = _validateRequiredStringDigestField(
      rawAttachment,
      'contentHash',
      malformedReason: 'malformed_content_hash',
    );
    if (!contentHashValidation.isValid) return contentHashValidation;

    final encryptionKeyValidation = _validateRequiredStringField(
      rawAttachment,
      'encryptionKeyBase64',
      missingReason: 'missing_media_encryption_metadata',
      malformedReason: 'malformed_media_encryption_metadata',
    );
    if (!encryptionKeyValidation.isValid) return encryptionKeyValidation;

    final encryptionNonceValidation = _validateRequiredStringField(
      rawAttachment,
      'encryptionNonce',
      missingReason: 'missing_media_encryption_metadata',
      malformedReason: 'malformed_media_encryption_metadata',
    );
    if (!encryptionNonceValidation.isValid) return encryptionNonceValidation;

    final rawEncryptionScheme = rawAttachment['encryptionScheme'];
    if (rawEncryptionScheme != null &&
        rawEncryptionScheme != kMediaAttachmentEncryptionSchemeBlobAesGcmV1) {
      return const GroupMediaValidationResult.invalid(
        'unsupported_media_encryption_scheme',
      );
    }

    final thumbnailHashValidation = _validateOptionalStringDigestField(
      rawAttachment,
      'thumbnailHash',
      malformedReason: 'malformed_thumbnail_hash',
    );
    if (!thumbnailHashValidation.isValid) return thumbnailHashValidation;
  }

  final sizeValidation = GroupMediaSizePolicy.validateRawDescriptors(media);
  if (!sizeValidation.isValid) return sizeValidation;

  return const GroupMediaValidationResult.valid();
}

String? _optionalString(Map<String, dynamic> value, String key) {
  final raw = value[key];
  return raw is String ? raw : null;
}

GroupMediaValidationResult _validateRequiredStringDigestField(
  Map<String, dynamic> value,
  String key, {
  required String malformedReason,
}) {
  final raw = value[key];
  if (raw != null && raw is! String) {
    return GroupMediaValidationResult.invalid(malformedReason);
  }
  return GroupMediaIntegrityPolicy.validateRequiredContentHash(raw as String?);
}

GroupMediaValidationResult _validateRequiredStringField(
  Map<String, dynamic> value,
  String key, {
  required String missingReason,
  required String malformedReason,
}) {
  final raw = value[key];
  if (raw == null) {
    return GroupMediaValidationResult.invalid(missingReason);
  }
  if (raw is! String || raw.trim().isEmpty) {
    return GroupMediaValidationResult.invalid(malformedReason);
  }
  return const GroupMediaValidationResult.valid();
}

GroupMediaValidationResult _validateOptionalStringDigestField(
  Map<String, dynamic> value,
  String key, {
  required String malformedReason,
}) {
  final raw = value[key];
  if (raw != null && raw is! String) {
    return GroupMediaValidationResult.invalid(malformedReason);
  }
  return GroupMediaIntegrityPolicy.validateOptionalThumbnailHash(
    raw as String?,
  );
}
