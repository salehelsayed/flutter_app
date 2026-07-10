import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/feed/application/load_group_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/application/load_latest_media_descriptors.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

/// Records every (method, lane) pair while forwarding to the REAL
/// database-backed repository, so a caller passing the wrong enum is caught
/// both by the recording AND by the collision fixture's behavior.
class _LaneRecordingMediaRepo
    implements MediaAttachmentRepository, MediaPreviewDescriptorLookup {
  _LaneRecordingMediaRepo(this.inner);

  final MediaRepositoryRealDbFixture inner;
  final List<(String, MediaOwnerLane)> recorded = [];

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) {
    recorded.add(('saveAttachment', owner));
    return inner.repo.saveAttachment(attachment, owner: owner);
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) {
    recorded.add(('getAttachmentsForMessage', owner));
    return inner.repo.getAttachmentsForMessage(messageId, owner: owner);
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) {
    recorded.add(('getAttachmentsForMessages', owner));
    return inner.repo.getAttachmentsForMessages(messageIds, owner: owner);
  }

  @override
  Future<Map<String, MediaPreviewDescriptor>> getMediaPreviewDescriptors(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) {
    recorded.add(('getMediaPreviewDescriptors', owner));
    return inner.repo.getMediaPreviewDescriptors(messageIds, owner: owner);
  }

  @override
  Future<void> updateLocalPath(String id, String localPath) =>
      inner.repo.updateLocalPath(id, localPath);

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) =>
      inner.repo.updateDownloadStatus(id, downloadStatus);

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) {
    recorded.add(('deleteAttachmentsForMessage', owner));
    return inner.repo.deleteAttachmentsForMessage(messageId, owner: owner);
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) =>
      inner.repo.deleteAttachmentsForContact(contactPeerId);

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) {
    recorded.add(('markUploadPendingAttachmentsFailedForMessage', owner));
    return inner.repo.markUploadPendingAttachmentsFailedForMessage(
      messageId,
      owner: owner,
    );
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() =>
      inner.repo.getPendingDownloads();

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) {
    recorded.add(('getUploadPendingAttachments', owner));
    return inner.repo.getUploadPendingAttachments(owner: owner);
  }

  List<MediaOwnerLane> lanesFor(String method) => recorded
      .where((r) => r.$1 == method)
      .map((r) => r.$2)
      .toList(growable: false);
}

void main() {
  // TC-228-05C: manual-retry hydration, multi-message hydration and preview
  // descriptor callers pass the correct typed lane, proven against a REAL
  // same-parent-ID collision so a wrong enum would visibly hydrate the
  // sibling lane's attachment into the wrong message.
  late MediaRepositoryRealDbFixture fixture;
  late _LaneRecordingMediaRepo recordingRepo;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
    recordingRepo = _LaneRecordingMediaRepo(fixture);

    // Collision fixture: 'msg-shared' exists as BOTH a 1:1 message of
    // contact-1 and a group message of group-1, each lane with its own
    // attachment.
    await fixture.seedDirectParent('msg-shared');
    await fixture.seedGroupParent('msg-shared');
    await fixture.repo.saveAttachment(
      const MediaAttachment(
        id: 'att-direct',
        messageId: 'msg-shared',
        mime: 'image/jpeg',
        size: 1,
        mediaType: 'image',
        downloadStatus: 'done',
        localPath: '/media/att-direct.jpg',
        createdAt: '2026-07-01T00:00:01.000Z',
      ),
      owner: MediaOwnerLane.direct,
    );
    await fixture.repo.saveAttachment(
      const MediaAttachment(
        id: 'att-group',
        messageId: 'msg-shared',
        mime: 'video/mp4',
        size: 1,
        mediaType: 'video',
        downloadStatus: 'done',
        localPath: '/media/att-group.mp4',
        createdAt: '2026-07-01T00:00:02.000Z',
      ),
      owner: MediaOwnerLane.group,
    );
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test(
    'manual retry hydration and stale cleanup preserve media owner lanes',
    () async {
      // --- Direct multi-message hydration (loadConversation) ---
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        const ConversationMessage(
          id: 'msg-shared',
          contactPeerId: 'contact-1',
          senderPeerId: 'contact-1',
          text: 'collision parent',
          timestamp: '2026-07-01T00:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-07-01T00:00:00.000Z',
        ),
      );

      final conversation = await loadConversation(
        messageRepo: messageRepo,
        contactPeerId: 'contact-1',
        mediaAttachmentRepo: recordingRepo,
      );

      // Only the direct-lane attachment hydrates into the 1:1 message; the
      // same-ID group sibling never leaks in.
      expect(conversation, hasLength(1));
      expect(
        conversation.single.media.map((a) => a.id),
        ['att-direct'],
      );
      expect(
        recordingRepo.lanesFor('getAttachmentsForMessages'),
        [MediaOwnerLane.direct],
      );

      // --- Group multi-message hydration (group feed snapshot) ---
      recordingRepo.recorded.clear();
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-1',
          name: 'Alpha',
          type: GroupType.chat,
          topicName: '/mknoon/group/group-1',
          createdAt: DateTime.utc(2026, 7, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      final groupMsgRepo = InMemoryGroupMessageRepository();
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'msg-shared',
          groupId: 'group-1',
          senderPeerId: 'peer-g',
          senderUsername: 'peer-g',
          text: 'collision group parent',
          timestamp: DateTime.utc(2026, 7, 1),
          isIncoming: true,
          createdAt: DateTime.utc(2026, 7, 1),
        ),
      );

      final snapshot = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        groupId: 'group-1',
        mediaAttachmentRepo: recordingRepo,
      );

      expect(snapshot, isNotNull);
      final snapshotMedia = snapshot!.messages
          .expand((m) => m.media)
          .map((a) => a.id)
          .toList();
      expect(snapshotMedia, ['att-group']);
      expect(
        recordingRepo.lanesFor('getAttachmentsForMessages'),
        [MediaOwnerLane.group],
      );

      // --- Preview-descriptor hydration (orbit), both lanes ---
      recordingRepo.recorded.clear();
      final directDescriptors = await loadLatestMediaDescriptors(
        mediaAttachmentRepo: recordingRepo,
        messageIds: const ['msg-shared'],
        owner: MediaOwnerLane.direct,
      );
      expect(directDescriptors['msg-shared']!.type, 'image');
      final groupDescriptors = await loadLatestMediaDescriptors(
        mediaAttachmentRepo: recordingRepo,
        messageIds: const ['msg-shared'],
        owner: MediaOwnerLane.group,
      );
      expect(groupDescriptors['msg-shared']!.type, 'video');
      expect(recordingRepo.lanesFor('getMediaPreviewDescriptors'), [
        MediaOwnerLane.direct,
        MediaOwnerLane.group,
      ]);

      // --- Stale upload-pending cleanup lanes stay isolated ---
      recordingRepo.recorded.clear();
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: 'att-direct-pending',
          messageId: 'msg-shared',
          mime: 'image/jpeg',
          size: 1,
          mediaType: 'image',
          downloadStatus: 'upload_pending',
          createdAt: '2026-07-01T00:00:03.000Z',
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: 'att-group-pending',
          messageId: 'msg-shared',
          mime: 'image/jpeg',
          size: 1,
          mediaType: 'image',
          downloadStatus: 'upload_pending',
          createdAt: '2026-07-01T00:00:04.000Z',
        ),
        owner: MediaOwnerLane.group,
      );

      final directStale = await recordingRepo.getUploadPendingAttachments(
        owner: MediaOwnerLane.direct,
      );
      expect(directStale.map((a) => a.id), ['att-direct-pending']);
      await recordingRepo.markUploadPendingAttachmentsFailedForMessage(
        'msg-shared',
        owner: MediaOwnerLane.direct,
      );
      // Direct cleanup terminalized only its lane; the group sibling's
      // pending row is untouched and still visible to the group sweep.
      final groupStale = await recordingRepo.getUploadPendingAttachments(
        owner: MediaOwnerLane.group,
      );
      expect(groupStale.map((a) => a.id), ['att-group-pending']);
      expect(
        (await fixture.rawAttachmentRow('att-direct-pending'))!['download_status'],
        'upload_failed',
      );
      expect(
        (await fixture.rawAttachmentRow('att-group-pending'))!['download_status'],
        'upload_pending',
      );
    },
  );
}
