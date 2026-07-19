import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

import '../../../shared/fakes/in_memory_message_repository.dart';

void main() {
  test('pause exact lookup preserves all 51 direct upload parents', () async {
    final messages = InMemoryMessageRepository();
    final media = _BatchMediaRepository();
    for (var index = 0; index < 51; index++) {
      final messageId = 'm-$index';
      await messages.saveMessage(
        makeSendingMessage(id: messageId, contactPeerId: 'peer-$index'),
      );
      media.rows.add(_attachment(messageId, 'a-$index', MediaOwnerLane.direct));
    }

    final result = await handleAppPaused(
      messageRepo: messages,
      mediaAttachmentRepo: media,
    );

    expect(result.transitionedCount, 0);
    expect(media.requestedIds.single, hasLength(51));
    for (var index = 0; index < 51; index++) {
      expect((await messages.getMessage('m-$index'))!.status, 'sending');
    }
  });

  test(
    'same parent id in the opposite owner lane never exempts direct',
    () async {
      final messages = InMemoryMessageRepository();
      await messages.saveMessage(makeSendingMessage(id: 'collision'));
      final media = _BatchMediaRepository()
        ..rows.add(_attachment('collision', 'group-a', MediaOwnerLane.group));

      final result = await handleAppPaused(
        messageRepo: messages,
        mediaAttachmentRepo: media,
      );

      expect(result.transitionedCount, 1);
      expect((await messages.getMessage('collision'))!.status, 'failed');
    },
  );
}

ConversationMessage makeSendingMessage({
  required String id,
  String contactPeerId = 'peer-a',
}) => ConversationMessage(
  id: id,
  contactPeerId: contactPeerId,
  senderPeerId: 'me',
  text: 'queued media',
  timestamp: '2026-01-01T00:00:00.000Z',
  status: 'sending',
  isIncoming: false,
  createdAt: '2026-01-01T00:00:00.000Z',
);

MediaAttachment _attachment(
  String messageId,
  String attachmentId,
  MediaOwnerLane owner,
) => MediaAttachment(
  id: attachmentId,
  messageId: messageId,
  mime: 'image/jpeg',
  size: 1,
  mediaType: 'image',
  localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
  downloadStatus: 'upload_pending',
  createdAt: '2026-01-01T00:00:00.000Z',
  ownerLane: owner,
);

class _BatchMediaRepository implements MediaAttachmentRepository {
  final rows = <MediaAttachment>[];
  final requestedIds = <List<String>>[];

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    requestedIds.add(List<String>.from(messageIds));
    final result = <String, List<MediaAttachment>>{};
    for (final row in rows) {
      if (row.ownerLane == owner && messageIds.contains(row.messageId)) {
        result.putIfAbsent(row.messageId, () => []).add(row);
      }
    }
    return result;
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => rows
      .where((row) => row.messageId == messageId && row.ownerLane == owner)
      .toList();

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => rows
      .where(
        (row) =>
            row.ownerLane == owner && row.downloadStatus == 'upload_pending',
      )
      .toList();

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {}

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;
}
