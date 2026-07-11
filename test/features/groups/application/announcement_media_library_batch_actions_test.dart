import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

void main() {
  test(
    'AML-08 ten item egress requalifies every current row in one call and eleven is zero side effect',
    () async {
      final messages = _RecordingMessages();
      final media = InMemoryMediaAttachmentRepository();
      final egress = _RecordingEgress();
      final coordinator = GroupSharedMediaBatchActionsCoordinator(
        messageRepository: messages,
        mediaAttachmentRepository: media,
        egressService: egress,
        mediaFileManager: FakeMediaFileManager(),
        fileExists: (_) async => true,
      );
      final identities = <GroupSharedMediaIdentity>[];
      for (var i = 0; i < 10; i++) {
        await _seed(messages, media, i);
        identities.add(_identity(i));
      }
      final result = await coordinator.performBatchEgress(
        identities: identities,
        destination: MediaEgressDestination.files,
      );
      expect(result.succeededIds, hasLength(10));
      expect(egress.calls, hasLength(1));
      messages.getCalls.clear();
      await expectLater(
        coordinator.performBatchEgress(
          identities: [...identities, _identity(10)],
          destination: MediaEgressDestination.files,
        ),
        throwsArgumentError,
      );
      expect(messages.getCalls, isEmpty);
      expect(egress.calls, hasLength(1));
    },
  );

  test(
    'AML-08 lifecycle-restricted current row stays ordered and never reaches batch egress',
    () async {
      final messages = _RecordingMessages();
      final media = InMemoryMediaAttachmentRepository();
      final egress = _RecordingEgress();
      for (var i = 0; i < 3; i++) {
        await _seed(messages, media, i);
      }
      final coordinator = GroupSharedMediaBatchActionsCoordinator(
        messageRepository: messages,
        mediaAttachmentRepository: media,
        egressService: egress,
        mediaFileManager: FakeMediaFileManager(),
        isEgressRestricted: (attachment) => attachment.id == 'a1',
        fileExists: (_) async => true,
      );

      final result = await coordinator.performBatchEgress(
        identities: [_identity(0), _identity(1), _identity(2)],
        destination: MediaEgressDestination.files,
      );

      expect(result.items.map((item) => item.attachmentId), ['a0', 'a1', 'a2']);
      expect(result.succeededIds, {'a0', 'a2'});
      expect(result.failedIds, {'a1'});
      expect(
        result.items[1].denial,
        GroupSharedMediaPreflightDenial.lifecycleRestricted,
      );
      expect(egress.calls, hasLength(1));
      expect(egress.calls.single.map((candidate) => candidate.attachmentId), [
        'a0',
        'a2',
      ]);
    },
  );

  test(
    'AML-09 bookmark and clear return ordered mixed results and preserve durable siblings',
    () async {
      final messages = InMemoryGroupMessageRepository();
      final media = InMemoryMediaAttachmentRepository();
      final state = _RecordingStateRepository();
      for (var i = 0; i < 3; i++) {
        await _seed(messages, media, i);
      }
      final coordinator = GroupSharedMediaBatchActionsCoordinator(
        messageRepository: messages,
        mediaAttachmentRepository: media,
        egressService: ReceivedMediaEgressService(),
        mediaFileManager: FakeMediaFileManager(),
        stateRepository: state,
        clearLocalCopy:
            ({required scope, required attachmentId, required mime}) async =>
                attachmentId == 'a1'
                ? MediaClearLocalCopyResult.cleanupFailed
                : MediaClearLocalCopyResult.cleared,
      );
      final identities = [_identity(0), _identity(1), _identity(2)];
      final bookmarked = await coordinator.performBatchBookmark(
        identities: identities,
        bookmarked: true,
      );
      expect(bookmarked.items.map((item) => item.attachmentId), [
        'a0',
        'a1',
        'a2',
      ]);
      expect(bookmarked.succeededIds, {'a0', 'a1', 'a2'});
      expect(state.bookmarkWrites, [('a0', true), ('a1', true), ('a2', true)]);
      final cleared = await coordinator.performBatchClear(
        identities: identities,
      );
      expect(cleared.items.map((item) => item.attachmentId), [
        'a0',
        'a1',
        'a2',
      ]);
      expect(cleared.failedIds, {'a1'});
      expect(cleared.succeededIds, {'a0', 'a2'});
    },
  );
}

Future<void> _seed(
  InMemoryGroupMessageRepository messages,
  InMemoryMediaAttachmentRepository media,
  int i,
) async {
  await messages.saveMessage(
    GroupMessage(
      id: 'm$i',
      groupId: 'announcement-a',
      senderPeerId: 'peer',
      text: '$i',
      timestamp: DateTime.utc(2026, 7, 10),
      isIncoming: true,
      createdAt: DateTime.utc(2026, 7, 10),
    ),
  );
  await media.saveAttachment(
    MediaAttachment(
      id: 'a$i',
      messageId: 'm$i',
      mime: 'image/jpeg',
      size: 10,
      mediaType: 'image',
      localPath: 'media/announcement-a/a$i.jpg',
      downloadStatus: 'done',
      createdAt: '2026-07-10T00:00:00.000Z',
      contentHash:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      encryptionKeyBase64: 'a2V5',
      encryptionNonce: 'bm9uY2U=',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    ),
    owner: MediaOwnerLane.group,
  );
}

GroupSharedMediaIdentity _identity(int i) => GroupSharedMediaIdentity(
  groupId: 'announcement-a',
  messageId: 'm$i',
  attachmentId: 'a$i',
);

class _RecordingMessages extends InMemoryGroupMessageRepository {
  final List<String> getCalls = [];
  @override
  Future<GroupMessage?> getMessage(String id) {
    getCalls.add(id);
    return super.getMessage(id);
  }
}

class _RecordingEgress extends ReceivedMediaEgressService {
  final List<List<ReceivedMediaEgressCandidate>> calls = [];
  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    calls.add(selection);
    return MediaEgressResult(
      requestId: requestId,
      outcome: MediaEgressOutcome.saved,
      items: [
        for (final item in selection)
          MediaEgressItemResult(
            attachmentId: item.attachmentId,
            outcome: MediaEgressItemOutcome.saved,
          ),
      ],
    );
  }
}

class _RecordingStateRepository implements MediaLibraryStateRepository {
  final List<(String, bool)> bookmarkWrites = [];

  @override
  Future<void> setBookmarked(String id, {required bool bookmarked}) async {
    bookmarkWrites.add((id, bookmarked));
  }

  @override
  Future<void> updatePlaybackPosition(String id, int positionMs) async {}
}
