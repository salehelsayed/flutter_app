import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_pending_work_manifest.dart';

class MigrationPendingWorkManifestBuilder {
  const MigrationPendingWorkManifestBuilder();

  MigrationPendingWorkManifest build({
    Iterable<String> fileManifestRelativePaths = const [],
    Iterable<Map<String, Object?>> oneToOneMessageRows = const [],
    Iterable<Map<String, Object?>> oneToOneUnackedMessageRows = const [],
    Iterable<Map<String, Object?>> chatMediaRows = const [],
    Iterable<Map<String, Object?>> postMediaUploadRows = const [],
    Iterable<Map<String, Object?>> postRows = const [],
    Iterable<Map<String, Object?>> postRecipientDeliveryRows = const [],
    Iterable<Map<String, Object?>> postFollowOnEventRows = const [],
    Iterable<Map<String, Object?>> postFollowOnRecipientDeliveryRows = const [],
    Iterable<Map<String, Object?>> introductionOutboxRows = const [],
    Iterable<Map<String, Object?>> pendingIntroductionResponseRows = const [],
    Iterable<Map<String, Object?>> groupMessageRows = const [],
    Iterable<Map<String, Object?>> groupInboxRetryRows = const [],
    Iterable<Map<String, Object?>> groupPendingKeyRepairRows = const [],
    Iterable<Map<String, Object?>> groupPendingMembershipRows = const [],
    Iterable<Map<String, Object?>> groupReactionReplayRows = const [],
    bool strictInputValidation = false,
  }) {
    final items = <MigrationPendingWorkManifestItem>[];
    final issues = <MigrationPendingWorkManifestIssue>[];
    final fileManifestPaths = fileManifestRelativePaths
        .map(_normalizeRelativePath)
        .where((path) => path.isNotEmpty)
        .toSet();

    for (final row in oneToOneMessageRows) {
      _addOneToOneMessageRetry(
        items: items,
        issues: issues,
        row: row,
        strictInputValidation: strictInputValidation,
      );
    }
    for (final row in oneToOneUnackedMessageRows) {
      _addOneToOneUnackedInboxStore(
        items: items,
        issues: issues,
        row: row,
        strictInputValidation: strictInputValidation,
      );
    }
    for (final row in chatMediaRows) {
      _addChatMediaUpload(
        items: items,
        issues: issues,
        row: row,
        fileManifestPaths: fileManifestPaths,
      );
    }
    for (final row in postMediaUploadRows) {
      _addPostMediaUpload(
        items: items,
        issues: issues,
        row: row,
        fileManifestPaths: fileManifestPaths,
      );
    }
    for (final row in postRows) {
      _addPostDelivery(
        items: items,
        issues: issues,
        row: row,
        strictInputValidation: strictInputValidation,
      );
    }
    for (final row in postRecipientDeliveryRows) {
      _addPostRecipientDelivery(
        items: items,
        issues: issues,
        row: row,
        strictInputValidation: strictInputValidation,
      );
    }

    final followOnEventsById = <String, Map<String, Object?>>{};
    for (final row in postFollowOnEventRows) {
      final eventId = _stringValue(row['event_id']);
      if (eventId != null) {
        followOnEventsById[eventId] = row;
      }
    }
    for (final row in postFollowOnRecipientDeliveryRows) {
      _addPostFollowOn(
        items: items,
        issues: issues,
        row: row,
        eventRow: followOnEventsById[_stringValue(row['event_id'])],
        strictInputValidation: strictInputValidation,
      );
    }

    for (final row in introductionOutboxRows) {
      _addIntroductionOutbox(
        items: items,
        issues: issues,
        row: row,
        strictInputValidation: strictInputValidation,
      );
    }
    for (final row in pendingIntroductionResponseRows) {
      _addPendingIntroductionResponse(items: items, issues: issues, row: row);
    }
    for (final row in groupMessageRows) {
      _addGroupMessageRetry(
        items: items,
        issues: issues,
        row: row,
        strictInputValidation: strictInputValidation,
      );
    }
    for (final row in groupInboxRetryRows) {
      _addGroupInboxStoreRetry(
        items: items,
        issues: issues,
        row: row,
        strictInputValidation: strictInputValidation,
      );
    }
    for (final row in groupPendingKeyRepairRows) {
      _addGroupPendingKeyRepair(items: items, issues: issues, row: row);
    }
    for (final row in groupPendingMembershipRows) {
      _addGroupPendingMembership(items: items, issues: issues, row: row);
    }
    for (final row in groupReactionReplayRows) {
      _addGroupReactionReplay(
        items: items,
        issues: issues,
        row: row,
        strictInputValidation: strictInputValidation,
      );
    }

    items.sort(_compareItems);
    issues.sort(_compareIssues);
    return MigrationPendingWorkManifest(items: items, issues: issues);
  }

  void _addOneToOneMessageRetry({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required bool strictInputValidation,
  }) {
    if (_boolish(row['is_incoming'])) {
      return;
    }
    final status = _stringValue(row['status']);
    if (!_isOneToOneMessageRetryStatus(status)) {
      _addTerminalIssueIfNeeded(
        issues: issues,
        strictInputValidation: strictInputValidation,
        status: status,
        sourceTable: 'messages',
        sourceId: _sourceId(row['id'], 'unknown-message'),
        kind: MigrationPendingWorkItemKind.oneToOneMessageRetry,
      );
      return;
    }

    final sourceId = _stringValue(row['id']);
    final targetPeerId = _stringValue(row['contact_peer_id']);
    final senderPeerId = _stringValue(row['sender_peer_id']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'messages',
        sourceId: 'unknown-message',
        kind: MigrationPendingWorkItemKind.oneToOneMessageRetry,
      );
    }
    if (targetPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingTargetPeerId,
        sourceTable: 'messages',
        sourceId: sourceId ?? 'unknown-message',
        kind: MigrationPendingWorkItemKind.oneToOneMessageRetry,
      );
    }
    if (senderPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSenderPeerId,
        sourceTable: 'messages',
        sourceId: sourceId ?? 'unknown-message',
        kind: MigrationPendingWorkItemKind.oneToOneMessageRetry,
      );
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.oneToOneMessageRetry,
        sourceTable: 'messages',
        sourceId: sourceId!,
        currentStatus: status,
        relatedIds: _ids({
          'target_peer_id': targetPeerId,
          'sender_peer_id': senderPeerId,
          'message_id': sourceId,
        }),
        metadata: _metadata({
          'transport': _stringValue(row['transport']),
          'wire_envelope_sha256': _hashNullable(
            _stringValue(row['wire_envelope']),
          ),
        }),
      ),
    );
  }

  void _addOneToOneUnackedInboxStore({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required bool strictInputValidation,
  }) {
    if (_boolish(row['is_incoming'])) {
      return;
    }
    final status = _stringValue(row['status']);
    if (status != 'sent') {
      _addTerminalIssueIfNeeded(
        issues: issues,
        strictInputValidation: strictInputValidation,
        status: status,
        sourceTable: 'messages',
        sourceId: _sourceId(row['id'], 'unknown-message'),
        kind: MigrationPendingWorkItemKind.oneToOneUnackedInboxStore,
      );
      return;
    }

    final sourceId = _stringValue(row['id']);
    final targetPeerId = _stringValue(row['contact_peer_id']);
    final senderPeerId = _stringValue(row['sender_peer_id']);
    final payload = _stringValue(row['wire_envelope']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'messages',
        sourceId: 'unknown-message',
        kind: MigrationPendingWorkItemKind.oneToOneUnackedInboxStore,
      );
    }
    if (targetPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingTargetPeerId,
        sourceTable: 'messages',
        sourceId: sourceId ?? 'unknown-message',
        kind: MigrationPendingWorkItemKind.oneToOneUnackedInboxStore,
      );
    }
    if (senderPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSenderPeerId,
        sourceTable: 'messages',
        sourceId: sourceId ?? 'unknown-message',
        kind: MigrationPendingWorkItemKind.oneToOneUnackedInboxStore,
      );
    }
    if (!_validatePayload(
      issues: issues,
      payload: payload,
      sourceTable: 'messages',
      sourceId: sourceId ?? 'unknown-message',
      kind: MigrationPendingWorkItemKind.oneToOneUnackedInboxStore,
    )) {
      blocked = true;
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.oneToOneUnackedInboxStore,
        sourceTable: 'messages',
        sourceId: sourceId!,
        currentStatus: status,
        relatedIds: _ids({
          'target_peer_id': targetPeerId,
          'sender_peer_id': senderPeerId,
          'message_id': sourceId,
        }),
        metadata: {'payload_sha256': _hash(payload!)},
      ),
    );
  }

  void _addChatMediaUpload({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required Set<String> fileManifestPaths,
  }) {
    if (_stringValue(row['download_status']) != 'upload_pending') {
      return;
    }
    final sourceId = _stringValue(row['id']);
    final messageId = _stringValue(row['message_id']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'media_attachments',
        sourceId: 'unknown-media',
        kind: MigrationPendingWorkItemKind.chatMediaUpload,
      );
    }
    if (messageId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingMessageId,
        sourceTable: 'media_attachments',
        sourceId: sourceId ?? 'unknown-media',
        kind: MigrationPendingWorkItemKind.chatMediaUpload,
      );
    }
    final requiredPath = _requiredAppOwnedFilePath(
      issues: issues,
      fileManifestPaths: fileManifestPaths,
      storedPath: _stringValue(row['local_path']),
      sourceTable: 'media_attachments',
      sourceId: sourceId ?? 'unknown-media',
      kind: MigrationPendingWorkItemKind.chatMediaUpload,
    );
    if (requiredPath == null) {
      blocked = true;
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.chatMediaUpload,
        sourceTable: 'media_attachments',
        sourceId: sourceId!,
        currentStatus: 'upload_pending',
        relatedIds: _ids({'message_id': messageId}),
        requiredFileRelativePaths: [requiredPath!],
      ),
    );
  }

  void _addPostMediaUpload({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required Set<String> fileManifestPaths,
  }) {
    final postId = _stringValue(row['post_id']);
    final position = _intValue(row['position']);
    final sourceId = postId == null
        ? 'unknown-post'
        : '$postId:${position ?? 0}';
    var blocked = false;
    if (postId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingPostId,
        sourceTable: 'post_media_upload_recovery',
        sourceId: sourceId,
        kind: MigrationPendingWorkItemKind.postMediaUpload,
      );
    }
    final requiredPath = _requiredAppOwnedFilePath(
      issues: issues,
      fileManifestPaths: fileManifestPaths,
      storedPath: _stringValue(row['local_file_path']),
      sourceTable: 'post_media_upload_recovery',
      sourceId: sourceId,
      kind: MigrationPendingWorkItemKind.postMediaUpload,
    );
    if (requiredPath == null) {
      blocked = true;
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.postMediaUpload,
        sourceTable: 'post_media_upload_recovery',
        sourceId: sourceId,
        currentStatus: 'upload_pending',
        relatedIds: _ids({'post_id': postId}),
        requiredFileRelativePaths: [requiredPath!],
        metadata: _metadata({
          'position': position,
          'mime': _stringValue(row['mime']),
          'media_kind': _stringValue(row['kind']),
        }),
      ),
    );
  }

  void _addPostDelivery({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required bool strictInputValidation,
  }) {
    if (_boolish(row['is_incoming'])) {
      return;
    }
    final status = _stringValue(row['delivery_status']);
    if (!_isPostDeliveryRetryStatus(status)) {
      _addTerminalIssueIfNeeded(
        issues: issues,
        strictInputValidation: strictInputValidation,
        status: status,
        sourceTable: 'posts',
        sourceId: _sourceId(row['post_id'], 'unknown-post'),
        kind: MigrationPendingWorkItemKind.postDelivery,
      );
      return;
    }

    final postId = _stringValue(row['post_id']);
    if (postId == null) {
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingPostId,
        sourceTable: 'posts',
        sourceId: 'unknown-post',
        kind: MigrationPendingWorkItemKind.postDelivery,
      );
      return;
    }
    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.postDelivery,
        sourceTable: 'posts',
        sourceId: postId,
        currentStatus: status,
        relatedIds: _ids({
          'post_id': postId,
          'event_id': _stringValue(row['event_id']),
          'sender_peer_id': _stringValue(row['sender_peer_id']),
        }),
      ),
    );
  }

  void _addPostRecipientDelivery({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required bool strictInputValidation,
  }) {
    final status = _stringValue(row['delivery_status']);
    if (!_isRecipientDeliveryRetryStatus(status)) {
      _addTerminalIssueIfNeeded(
        issues: issues,
        strictInputValidation: strictInputValidation,
        status: status,
        sourceTable: 'post_recipients',
        sourceId: _postRecipientSourceId(row),
        kind: MigrationPendingWorkItemKind.postDelivery,
      );
      return;
    }

    final postId = _stringValue(row['post_id']);
    final ownerId = _stringValue(row['delivery_owner_id']) ?? postId;
    final recipientPeerId = _stringValue(row['recipient_peer_id']);
    var blocked = false;
    if (postId == null && ownerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingPostId,
        sourceTable: 'post_recipients',
        sourceId: _postRecipientSourceId(row),
        kind: MigrationPendingWorkItemKind.postDelivery,
      );
    }
    if (recipientPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingTargetPeerId,
        sourceTable: 'post_recipients',
        sourceId: _postRecipientSourceId(row),
        kind: MigrationPendingWorkItemKind.postDelivery,
      );
    }
    if (blocked) {
      return;
    }

    final ownerKind = _stringValue(row['delivery_owner_kind']) ?? 'post';
    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.postDelivery,
        sourceTable: 'post_recipients',
        sourceId: '${ownerId!}:$recipientPeerId',
        currentStatus: status,
        relatedIds: _ids({
          'post_id': postId ?? ownerId,
          'delivery_owner_kind': ownerKind,
          'delivery_owner_id': ownerId,
          'recipient_peer_id': recipientPeerId,
        }),
        metadata: _metadata({
          'delivery_path': _stringValue(row['delivery_path']),
        }),
      ),
    );
  }

  void _addPostFollowOn({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required Map<String, Object?>? eventRow,
    required bool strictInputValidation,
  }) {
    final status = _stringValue(row['delivery_status']);
    if (!_isRecipientDeliveryRetryStatus(status)) {
      _addTerminalIssueIfNeeded(
        issues: issues,
        strictInputValidation: strictInputValidation,
        status: status,
        sourceTable: 'post_follow_on_outbox_recipient_deliveries',
        sourceId: _postFollowOnSourceId(row),
        kind: MigrationPendingWorkItemKind.postFollowOn,
      );
      return;
    }

    final eventId = _stringValue(row['event_id']);
    final recipientPeerId = _stringValue(row['recipient_peer_id']);
    final postId = eventRow == null ? null : _stringValue(eventRow['post_id']);
    final rawEnvelope = eventRow == null
        ? null
        : _stringValue(eventRow['raw_envelope']);
    var blocked = false;
    if (eventId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'post_follow_on_outbox_recipient_deliveries',
        sourceId: 'unknown-follow-on',
        kind: MigrationPendingWorkItemKind.postFollowOn,
      );
    }
    if (postId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingPostId,
        sourceTable: 'post_follow_on_outbox_events',
        sourceId: eventId ?? 'unknown-follow-on',
        kind: MigrationPendingWorkItemKind.postFollowOn,
      );
    }
    if (recipientPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingTargetPeerId,
        sourceTable: 'post_follow_on_outbox_recipient_deliveries',
        sourceId: eventId ?? 'unknown-follow-on',
        kind: MigrationPendingWorkItemKind.postFollowOn,
      );
    }
    if (!_validatePayload(
      issues: issues,
      payload: rawEnvelope,
      sourceTable: 'post_follow_on_outbox_events',
      sourceId: eventId ?? 'unknown-follow-on',
      kind: MigrationPendingWorkItemKind.postFollowOn,
    )) {
      blocked = true;
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.postFollowOn,
        sourceTable: 'post_follow_on_outbox_recipient_deliveries',
        sourceId: '$eventId:$recipientPeerId',
        currentStatus: status,
        relatedIds: _ids({
          'event_id': eventId,
          'post_id': postId,
          'comment_id': _stringValue(eventRow!['comment_id']),
          'sender_peer_id': _stringValue(eventRow['sender_peer_id']),
          'recipient_peer_id': recipientPeerId,
        }),
        metadata: _metadata({
          'event_type': _stringValue(eventRow['event_type']),
          'payload_sha256': _hash(rawEnvelope!),
          'delivery_path': _stringValue(row['delivery_path']),
        }),
      ),
    );
  }

  void _addIntroductionOutbox({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required bool strictInputValidation,
  }) {
    final status = _stringValue(row['delivery_status']);
    final deliveryPath = _stringValue(row['delivery_path']);
    if (!_isIntroductionOutboxRetryStatus(status, deliveryPath)) {
      _addTerminalIssueIfNeeded(
        issues: issues,
        strictInputValidation: strictInputValidation,
        status: status,
        sourceTable: 'introduction_outbox_deliveries',
        sourceId: _sourceId(row['delivery_id'], 'unknown-intro-delivery'),
        kind: MigrationPendingWorkItemKind.introductionOutbox,
      );
      return;
    }

    final sourceId = _stringValue(row['delivery_id']);
    final introductionId = _stringValue(row['introduction_id']);
    final targetPeerId = _stringValue(row['target_peer_id']);
    final senderPeerId = _stringValue(row['sender_peer_id']);
    final rawEnvelope = _stringValue(row['raw_envelope']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'introduction_outbox_deliveries',
        sourceId: 'unknown-intro-delivery',
        kind: MigrationPendingWorkItemKind.introductionOutbox,
      );
    }
    if (introductionId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingMessageId,
        sourceTable: 'introduction_outbox_deliveries',
        sourceId: sourceId ?? 'unknown-intro-delivery',
        kind: MigrationPendingWorkItemKind.introductionOutbox,
      );
    }
    if (targetPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingTargetPeerId,
        sourceTable: 'introduction_outbox_deliveries',
        sourceId: sourceId ?? 'unknown-intro-delivery',
        kind: MigrationPendingWorkItemKind.introductionOutbox,
      );
    }
    if (senderPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSenderPeerId,
        sourceTable: 'introduction_outbox_deliveries',
        sourceId: sourceId ?? 'unknown-intro-delivery',
        kind: MigrationPendingWorkItemKind.introductionOutbox,
      );
    }
    if (!_validatePayload(
      issues: issues,
      payload: rawEnvelope,
      sourceTable: 'introduction_outbox_deliveries',
      sourceId: sourceId ?? 'unknown-intro-delivery',
      kind: MigrationPendingWorkItemKind.introductionOutbox,
    )) {
      blocked = true;
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.introductionOutbox,
        sourceTable: 'introduction_outbox_deliveries',
        sourceId: sourceId!,
        currentStatus: status,
        relatedIds: _ids({
          'introduction_id': introductionId,
          'target_peer_id': targetPeerId,
          'sender_peer_id': senderPeerId,
          'action': _stringValue(row['action']),
        }),
        metadata: _metadata({
          'payload_sha256': _hash(rawEnvelope!),
          'delivery_path': deliveryPath,
        }),
      ),
    );
  }

  void _addPendingIntroductionResponse({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
  }) {
    final sourceId = _stringValue(row['response_key']);
    final introductionId = _stringValue(row['introduction_id']);
    final responderId = _stringValue(row['responder_id']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'pending_introduction_responses',
        sourceId: 'unknown-intro-response',
        kind: MigrationPendingWorkItemKind.pendingIntroductionResponse,
      );
    }
    if (introductionId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingMessageId,
        sourceTable: 'pending_introduction_responses',
        sourceId: sourceId ?? 'unknown-intro-response',
        kind: MigrationPendingWorkItemKind.pendingIntroductionResponse,
      );
    }
    if (responderId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingTargetPeerId,
        sourceTable: 'pending_introduction_responses',
        sourceId: sourceId ?? 'unknown-intro-response',
        kind: MigrationPendingWorkItemKind.pendingIntroductionResponse,
      );
    }
    if (blocked) {
      return;
    }
    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.pendingIntroductionResponse,
        sourceTable: 'pending_introduction_responses',
        sourceId: sourceId!,
        currentStatus: 'pending',
        relatedIds: _ids({
          'introduction_id': introductionId,
          'responder_id': responderId,
          'transport_sender_peer_id': _stringValue(
            row['transport_sender_peer_id'],
          ),
          'action': _stringValue(row['action']),
        }),
      ),
    );
  }

  void _addGroupMessageRetry({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required bool strictInputValidation,
  }) {
    if (_boolish(row['is_incoming'])) {
      return;
    }
    final status = _stringValue(row['status']);
    if (!_isGroupMessageRetryStatus(status)) {
      _addTerminalIssueIfNeeded(
        issues: issues,
        strictInputValidation: strictInputValidation,
        status: status,
        sourceTable: 'group_messages',
        sourceId: _sourceId(row['id'], 'unknown-group-message'),
        kind: MigrationPendingWorkItemKind.groupMessageRetry,
      );
      return;
    }

    final sourceId = _stringValue(row['id']);
    final groupId = _stringValue(row['group_id']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'group_messages',
        sourceId: 'unknown-group-message',
        kind: MigrationPendingWorkItemKind.groupMessageRetry,
      );
    }
    if (groupId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingGroupId,
        sourceTable: 'group_messages',
        sourceId: sourceId ?? 'unknown-group-message',
        kind: MigrationPendingWorkItemKind.groupMessageRetry,
      );
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.groupMessageRetry,
        sourceTable: 'group_messages',
        sourceId: sourceId!,
        currentStatus: status,
        relatedIds: _ids({
          'group_id': groupId,
          'message_id': sourceId,
          'sender_peer_id': _stringValue(row['sender_peer_id']),
          'logical_delivery_id': _stringValue(row['logical_delivery_id']),
        }),
        metadata: _metadata({
          'key_generation': _intValue(row['key_generation']),
          'wire_envelope_sha256': _hashNullable(
            _stringValue(row['wire_envelope']),
          ),
        }),
      ),
    );
  }

  void _addGroupInboxStoreRetry({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required bool strictInputValidation,
  }) {
    if (_boolish(row['is_incoming'])) {
      return;
    }
    final status = _stringValue(row['status']);
    if (!_isGroupInboxRetryStatus(status)) {
      _addTerminalIssueIfNeeded(
        issues: issues,
        strictInputValidation: strictInputValidation,
        status: status,
        sourceTable: 'group_messages',
        sourceId: _sourceId(row['id'], 'unknown-group-message'),
        kind: MigrationPendingWorkItemKind.groupInboxStoreRetry,
      );
      return;
    }
    final sourceId = _stringValue(row['id']);
    final groupId = _stringValue(row['group_id']);
    final payload = _stringValue(row['inbox_retry_payload']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'group_messages',
        sourceId: 'unknown-group-message',
        kind: MigrationPendingWorkItemKind.groupInboxStoreRetry,
      );
    }
    if (groupId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingGroupId,
        sourceTable: 'group_messages',
        sourceId: sourceId ?? 'unknown-group-message',
        kind: MigrationPendingWorkItemKind.groupInboxStoreRetry,
      );
    }
    if (!_validatePayload(
      issues: issues,
      payload: payload,
      sourceTable: 'group_messages',
      sourceId: sourceId ?? 'unknown-group-message',
      kind: MigrationPendingWorkItemKind.groupInboxStoreRetry,
    )) {
      blocked = true;
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.groupInboxStoreRetry,
        sourceTable: 'group_messages',
        sourceId: sourceId!,
        currentStatus: status,
        relatedIds: _ids({
          'group_id': groupId,
          'message_id': sourceId,
          'sender_peer_id': _stringValue(row['sender_peer_id']),
        }),
        metadata: {'payload_sha256': _hash(payload!)},
      ),
    );
  }

  void _addGroupPendingKeyRepair({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
  }) {
    final sourceId = _stringValue(row['id']);
    final groupId = _stringValue(row['group_id']);
    final messageId = _stringValue(row['message_id']);
    final payload = _stringValue(row['replay_envelope_json']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'group_pending_key_repairs',
        sourceId: 'unknown-key-repair',
        kind: MigrationPendingWorkItemKind.groupPendingKeyRepair,
      );
    }
    if (groupId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingGroupId,
        sourceTable: 'group_pending_key_repairs',
        sourceId: sourceId ?? 'unknown-key-repair',
        kind: MigrationPendingWorkItemKind.groupPendingKeyRepair,
      );
    }
    if (messageId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingMessageId,
        sourceTable: 'group_pending_key_repairs',
        sourceId: sourceId ?? 'unknown-key-repair',
        kind: MigrationPendingWorkItemKind.groupPendingKeyRepair,
      );
    }
    if (!_validatePayload(
      issues: issues,
      payload: payload,
      sourceTable: 'group_pending_key_repairs',
      sourceId: sourceId ?? 'unknown-key-repair',
      kind: MigrationPendingWorkItemKind.groupPendingKeyRepair,
    )) {
      blocked = true;
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.groupPendingKeyRepair,
        sourceTable: 'group_pending_key_repairs',
        sourceId: sourceId!,
        currentStatus: _stringValue(row['status']),
        relatedIds: _ids({
          'group_id': groupId,
          'message_id': messageId,
          'sender_peer_id': _stringValue(row['sender_peer_id']),
          'transport_peer_id': _stringValue(row['transport_peer_id']),
        }),
        metadata: _metadata({
          'payload_type': _stringValue(row['payload_type']),
          'key_epoch': _intValue(row['key_epoch']),
          'payload_sha256': _hash(payload!),
          'attempts': _intValue(row['attempts']),
        }),
      ),
    );
  }

  void _addGroupPendingMembership({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
  }) {
    final sourceId = _stringValue(row['id']);
    final groupId = _stringValue(row['group_id']);
    final senderPeerId = _stringValue(row['sender_peer_id']);
    final payload = _stringValue(row['payload_json']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'group_pending_membership_messages',
        sourceId: 'unknown-membership-message',
        kind: MigrationPendingWorkItemKind.groupPendingMembership,
      );
    }
    if (groupId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingGroupId,
        sourceTable: 'group_pending_membership_messages',
        sourceId: sourceId ?? 'unknown-membership-message',
        kind: MigrationPendingWorkItemKind.groupPendingMembership,
      );
    }
    if (senderPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSenderPeerId,
        sourceTable: 'group_pending_membership_messages',
        sourceId: sourceId ?? 'unknown-membership-message',
        kind: MigrationPendingWorkItemKind.groupPendingMembership,
      );
    }
    if (!_validatePayload(
      issues: issues,
      payload: payload,
      sourceTable: 'group_pending_membership_messages',
      sourceId: sourceId ?? 'unknown-membership-message',
      kind: MigrationPendingWorkItemKind.groupPendingMembership,
    )) {
      blocked = true;
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.groupPendingMembership,
        sourceTable: 'group_pending_membership_messages',
        sourceId: sourceId!,
        currentStatus: 'pending',
        relatedIds: _ids({
          'group_id': groupId,
          'sender_peer_id': senderPeerId,
          'message_id': _stringValue(row['message_id']),
        }),
        metadata: _metadata({
          'payload_sha256': _hash(payload!),
          'received_at': _stringValue(row['received_at']),
        }),
      ),
    );
  }

  void _addGroupReactionReplay({
    required List<MigrationPendingWorkManifestItem> items,
    required List<MigrationPendingWorkManifestIssue> issues,
    required Map<String, Object?> row,
    required bool strictInputValidation,
  }) {
    final status = _stringValue(row['delivery_status']);
    if (!_isGroupReactionReplayStatus(status)) {
      _addTerminalIssueIfNeeded(
        issues: issues,
        strictInputValidation: strictInputValidation,
        status: status,
        sourceTable: 'group_reaction_replay_outbox',
        sourceId: _sourceId(row['reaction_id'], 'unknown-reaction'),
        kind: MigrationPendingWorkItemKind.groupReactionReplay,
      );
      return;
    }

    final sourceId = _stringValue(row['reaction_id']);
    final groupId = _stringValue(row['group_id']);
    final messageId = _stringValue(row['message_id']);
    final senderPeerId = _stringValue(row['sender_peer_id']);
    final payload = _stringValue(row['inbox_retry_payload']);
    var blocked = false;
    if (sourceId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSourceId,
        sourceTable: 'group_reaction_replay_outbox',
        sourceId: 'unknown-reaction',
        kind: MigrationPendingWorkItemKind.groupReactionReplay,
      );
    }
    if (groupId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingGroupId,
        sourceTable: 'group_reaction_replay_outbox',
        sourceId: sourceId ?? 'unknown-reaction',
        kind: MigrationPendingWorkItemKind.groupReactionReplay,
      );
    }
    if (messageId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingMessageId,
        sourceTable: 'group_reaction_replay_outbox',
        sourceId: sourceId ?? 'unknown-reaction',
        kind: MigrationPendingWorkItemKind.groupReactionReplay,
      );
    }
    if (senderPeerId == null) {
      blocked = true;
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingSenderPeerId,
        sourceTable: 'group_reaction_replay_outbox',
        sourceId: sourceId ?? 'unknown-reaction',
        kind: MigrationPendingWorkItemKind.groupReactionReplay,
      );
    }
    if (!_validatePayload(
      issues: issues,
      payload: payload,
      sourceTable: 'group_reaction_replay_outbox',
      sourceId: sourceId ?? 'unknown-reaction',
      kind: MigrationPendingWorkItemKind.groupReactionReplay,
    )) {
      blocked = true;
    }
    if (blocked) {
      return;
    }

    items.add(
      MigrationPendingWorkManifestItem(
        kind: MigrationPendingWorkItemKind.groupReactionReplay,
        sourceTable: 'group_reaction_replay_outbox',
        sourceId: sourceId!,
        currentStatus: status,
        relatedIds: _ids({
          'group_id': groupId,
          'message_id': messageId,
          'sender_peer_id': senderPeerId,
          'action': _stringValue(row['action']),
        }),
        metadata: _metadata({
          'emoji': _stringValue(row['emoji']),
          'payload_sha256': _hash(payload!),
        }),
      ),
    );
  }

  String? _requiredAppOwnedFilePath({
    required List<MigrationPendingWorkManifestIssue> issues,
    required Set<String> fileManifestPaths,
    required String? storedPath,
    required String sourceTable,
    required String sourceId,
    required MigrationPendingWorkItemKind kind,
  }) {
    if (storedPath == null) {
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingRequiredFileManifestItem,
        sourceTable: sourceTable,
        sourceId: sourceId,
        kind: kind,
      );
      return null;
    }
    if (_looksAbsolute(storedPath)) {
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.unsupportedPendingFilePath,
        sourceTable: sourceTable,
        sourceId: sourceId,
        kind: kind,
      );
      return null;
    }
    final normalized = _normalizeRelativePath(storedPath);
    if (!_isAppOwnedRelativePath(normalized)) {
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.unsupportedPendingFilePath,
        sourceTable: sourceTable,
        sourceId: sourceId,
        kind: kind,
      );
      return null;
    }
    if (!fileManifestPaths.contains(normalized)) {
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingRequiredFileManifestItem,
        sourceTable: sourceTable,
        sourceId: sourceId,
        kind: kind,
      );
      return null;
    }
    return normalized;
  }

  bool _validatePayload({
    required List<MigrationPendingWorkManifestIssue> issues,
    required String? payload,
    required String sourceTable,
    required String sourceId,
    required MigrationPendingWorkItemKind kind,
  }) {
    if (payload == null) {
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.missingRequiredPayload,
        sourceTable: sourceTable,
        sourceId: sourceId,
        kind: kind,
      );
      return false;
    }
    if (_containsSensitiveMaterial(payload)) {
      _addIssue(
        issues,
        code: MigrationPendingWorkIssueCode.sensitiveMaterialLeakage,
        sourceTable: sourceTable,
        sourceId: sourceId,
        kind: kind,
        policy: MigrationPendingWorkResumePolicy.failOnNewPhoneAfterCommit,
      );
      return false;
    }
    return true;
  }

  void _addTerminalIssueIfNeeded({
    required List<MigrationPendingWorkManifestIssue> issues,
    required bool strictInputValidation,
    required String? status,
    required String sourceTable,
    required String sourceId,
    required MigrationPendingWorkItemKind kind,
  }) {
    if (!strictInputValidation || !_isTerminalStatus(status)) {
      return;
    }
    _addIssue(
      issues,
      code: MigrationPendingWorkIssueCode.terminalRetryContradiction,
      sourceTable: sourceTable,
      sourceId: sourceId,
      kind: kind,
      policy: MigrationPendingWorkResumePolicy.failOnNewPhoneAfterCommit,
    );
  }

  void _addIssue(
    List<MigrationPendingWorkManifestIssue> issues, {
    required MigrationPendingWorkIssueCode code,
    required String sourceTable,
    required String sourceId,
    required MigrationPendingWorkItemKind kind,
    MigrationPendingWorkResumePolicy policy =
        MigrationPendingWorkResumePolicy.pauseOnNewPhoneAfterCommit,
    Map<String, String> relatedIds = const {},
  }) {
    issues.add(
      MigrationPendingWorkManifestIssue(
        code: code,
        sourceTable: sourceTable,
        sourceId: sourceId,
        kind: kind,
        policy: policy,
        relatedIds: relatedIds,
      ),
    );
  }

  static bool _isOneToOneMessageRetryStatus(String? status) {
    return status == 'failed' || status == 'sending';
  }

  static bool _isPostDeliveryRetryStatus(String? status) {
    return status == 'failed' || status == 'sending' || status == 'partial';
  }

  static bool _isRecipientDeliveryRetryStatus(String? status) {
    return status != null && status != 'delivered' && status != 'inbox';
  }

  static bool _isIntroductionOutboxRetryStatus(
    String? status,
    String? deliveryPath,
  ) {
    return status == 'failed' ||
        status == 'sending' ||
        status == 'sent' ||
        (status == 'delivered' && deliveryPath == 'inbox');
  }

  static bool _isGroupMessageRetryStatus(String? status) {
    return status == 'failed' || status == 'sending' || status == 'pending';
  }

  static bool _isGroupInboxRetryStatus(String? status) {
    return status == 'sent' || status == 'pending';
  }

  static bool _isGroupReactionReplayStatus(String? status) {
    return status == 'pending' || status == 'failed';
  }

  static bool _isTerminalStatus(String? status) {
    return status == 'delivered' ||
        status == 'inbox' ||
        status == 'stored' ||
        status == 'available';
  }

  static bool _containsSensitiveMaterial(String payload) {
    final normalized = payload.toLowerCase().replaceAll(RegExp(r'[\s\-]'), '_');
    return normalized.contains('privatekey') ||
        normalized.contains('private_key') ||
        normalized.contains('private_group_key') ||
        normalized.contains('group_private_key') ||
        normalized.contains('raw_secret') ||
        normalized.contains('secret_key') ||
        normalized.contains('seed_phrase') ||
        normalized.contains('mnemonic');
  }

  static bool _isAppOwnedRelativePath(String path) {
    return path.startsWith('media/') ||
        path.startsWith('post_media/') ||
        path.startsWith('pending_uploads/');
  }

  static bool _looksAbsolute(String path) {
    return path.startsWith('/') ||
        path.startsWith(r'\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }

  static String _normalizeRelativePath(String path) {
    return path.trim().replaceAll(r'\', '/').replaceFirst(RegExp(r'^/+'), '');
  }

  static String _sourceId(Object? value, String fallback) {
    return _stringValue(value) ?? fallback;
  }

  static String _postRecipientSourceId(Map<String, Object?> row) {
    final ownerId =
        _stringValue(row['delivery_owner_id']) ??
        _stringValue(row['post_id']) ??
        'unknown-post';
    final recipient = _stringValue(row['recipient_peer_id']) ?? 'unknown-peer';
    return '$ownerId:$recipient';
  }

  static String _postFollowOnSourceId(Map<String, Object?> row) {
    final eventId = _stringValue(row['event_id']) ?? 'unknown-follow-on';
    final recipient = _stringValue(row['recipient_peer_id']) ?? 'unknown-peer';
    return '$eventId:$recipient';
  }

  static Map<String, String> _ids(Map<String, String?> values) {
    final result = <String, String>{};
    for (final entry in values.entries) {
      final value = entry.value;
      if (value != null && value.isNotEmpty) {
        result[entry.key] = value;
      }
    }
    return result;
  }

  static Map<String, Object?> _metadata(Map<String, Object?> values) {
    final result = <String, Object?>{};
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is String && value.isEmpty) {
        continue;
      }
      result[entry.key] = value;
    }
    return result;
  }

  static String? _hashNullable(String? value) {
    return value == null ? null : _hash(value);
  }

  static String _hash(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static String? _stringValue(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static bool _boolish(Object? value) {
    return value == true || value == 1 || value == '1' || value == 'true';
  }

  static int _compareItems(
    MigrationPendingWorkManifestItem a,
    MigrationPendingWorkManifestItem b,
  ) {
    final tableCompare = a.sourceTable.compareTo(b.sourceTable);
    if (tableCompare != 0) {
      return tableCompare;
    }
    final idCompare = a.sourceId.compareTo(b.sourceId);
    if (idCompare != 0) {
      return idCompare;
    }
    return a.kind.name.compareTo(b.kind.name);
  }

  static int _compareIssues(
    MigrationPendingWorkManifestIssue a,
    MigrationPendingWorkManifestIssue b,
  ) {
    final tableCompare = a.sourceTable.compareTo(b.sourceTable);
    if (tableCompare != 0) {
      return tableCompare;
    }
    final idCompare = a.sourceId.compareTo(b.sourceId);
    if (idCompare != 0) {
      return idCompare;
    }
    return a.code.name.compareTo(b.code.name);
  }
}
