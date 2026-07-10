import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

void main() {
  test(
    'GML-06 batch egress requalifies current rows and honors native cap',
    () async {
      final messages = _RecordingMessageRepository();
      final media = InMemoryMediaAttachmentRepository();
      final egress = _RecordingEgressService();
      final coordinator = GroupSharedMediaBatchActionsCoordinator(
        messageRepository: messages,
        mediaAttachmentRepository: media,
        egressService: egress,
        mediaFileManager: FakeMediaFileManager(),
        fileExists: (_) async => true,
        requestIdFactory: () => 'gml-batch',
      );
      final identities = <GroupSharedMediaIdentity>[];
      for (var index = 0; index < 10; index++) {
        final messageId = 'm$index';
        final attachmentId = 'a$index';
        await messages.saveMessage(_message(messageId));
        await media.saveAttachment(
          _attachment(
            attachmentId,
            messageId,
            localPath: 'media/group-a/$attachmentId.jpg',
          ),
          owner: MediaOwnerLane.group,
        );
        identities.add(
          GroupSharedMediaIdentity(
            groupId: 'group-a',
            messageId: messageId,
            attachmentId: attachmentId,
          ),
        );
      }
      egress.outcomes['a4'] = MediaEgressItemOutcome.permissionDenied;

      final result = await coordinator.performBatchEgress(
        identities: identities,
        destination: MediaEgressDestination.files,
      );
      expect(egress.calls, hasLength(1));
      expect(egress.calls.single.map((candidate) => candidate.attachmentId), [
        for (var index = 0; index < 10; index++) 'a$index',
      ]);
      expect(result.failedIds, {'a4'});
      expect(result.succeededIds, hasLength(9));

      messages.getCalls.clear();
      egress.calls.clear();
      await expectLater(
        coordinator.performBatchEgress(
          identities: [
            ...identities,
            const GroupSharedMediaIdentity(
              groupId: 'group-a',
              messageId: 'm10',
              attachmentId: 'a10',
            ),
          ],
          destination: MediaEgressDestination.photos,
        ),
        throwsArgumentError,
      );
      expect(messages.getCalls, isEmpty);
      expect(egress.calls, isEmpty);

      await expectLater(
        coordinator.performBatchEgress(
          identities: [
            identities.first,
            const GroupSharedMediaIdentity(
              groupId: 'group-b',
              messageId: 'foreign',
              attachmentId: 'foreign',
            ),
          ],
          destination: MediaEgressDestination.photos,
        ),
        throwsArgumentError,
      );
      expect(messages.getCalls, isEmpty);
      expect(egress.calls, isEmpty);

      await messages.saveMessage(_message('outgoing', isIncoming: false));
      await media.saveAttachment(
        _attachment(
          'outgoing-a',
          'outgoing',
          localPath: 'media/group-a/outgoing-a.jpg',
        ),
        owner: MediaOwnerLane.group,
      );
      final denied = await coordinator.performBatchEgress(
        identities: const [
          GroupSharedMediaIdentity(
            groupId: 'group-a',
            messageId: 'outgoing',
            attachmentId: 'outgoing-a',
          ),
        ],
        destination: MediaEgressDestination.photos,
      );
      expect(
        denied.items.single.denial,
        GroupSharedMediaPreflightDenial.notIncoming,
      );
    },
  );

  test(
    'GML-08 delete reconciles void coordinator outcomes before clearing selection',
    () async {
      final messages = InMemoryGroupMessageRepository();
      await messages.saveMessage(_message('parent-a'));
      await messages.saveMessage(_message('parent-b'));
      final coordinator = _SelectiveDeleteCoordinator(
        repository: messages,
        deletedIds: {'parent-a'},
      );
      const identities = [
        GroupSharedMediaIdentity(
          groupId: 'group-a',
          messageId: 'parent-a',
          attachmentId: 'a1',
        ),
        GroupSharedMediaIdentity(
          groupId: 'group-a',
          messageId: 'parent-a',
          attachmentId: 'a2',
        ),
        GroupSharedMediaIdentity(
          groupId: 'group-a',
          messageId: 'parent-b',
          attachmentId: 'b1',
        ),
      ];

      final result = await deleteGroupSharedMediaSelection(
        identities: identities,
        messageRepository: messages,
        coordinator: coordinator,
      );
      expect(coordinator.calls, ['parent-a', 'parent-b']);
      expect(result.deletedMessageIds, {'parent-a'});
      expect(result.deletedAttachmentIds, {'a1', 'a2'});
      expect(result.failedMessageIds, {'parent-b'});
      expect(result.failedAttachmentIds, {'b1'});
      expect(await messages.getMessage('parent-b'), isNotNull);
    },
  );
}

class _RecordingMessageRepository extends InMemoryGroupMessageRepository {
  final List<String> getCalls = [];

  @override
  Future<GroupMessage?> getMessage(String id) {
    getCalls.add(id);
    return super.getMessage(id);
  }
}

class _RecordingEgressService extends ReceivedMediaEgressService {
  final List<List<ReceivedMediaEgressCandidate>> calls = [];
  final Map<String, MediaEgressItemOutcome> outcomes = {};

  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    calls.add(selection);
    return MediaEgressResult(
      requestId: requestId,
      outcome: MediaEgressOutcome.partial,
      items: [
        for (final candidate in selection)
          MediaEgressItemResult(
            attachmentId: candidate.attachmentId,
            outcome:
                outcomes[candidate.attachmentId] ??
                MediaEgressItemOutcome.saved,
          ),
      ],
    );
  }
}

class _SelectiveDeleteCoordinator implements GroupMediaDeleteForMeCoordinator {
  _SelectiveDeleteCoordinator({
    required this.repository,
    required this.deletedIds,
  });

  final InMemoryGroupMessageRepository repository;
  final Set<String> deletedIds;
  final List<String> calls = [];

  @override
  Future<void> deleteForMe({
    required String groupId,
    required String messageId,
  }) async {
    calls.add(messageId);
    if (deletedIds.contains(messageId)) {
      await repository.deleteMessage(messageId);
    }
  }
}

GroupMessage _message(String id, {bool isIncoming = true}) => GroupMessage(
  id: id,
  groupId: 'group-a',
  senderPeerId: isIncoming ? 'peer' : 'self',
  text: id,
  timestamp: DateTime.utc(2026, 7, 10),
  isIncoming: isIncoming,
  createdAt: DateTime.utc(2026, 7, 10),
);

MediaAttachment _attachment(
  String id,
  String messageId, {
  required String localPath,
}) => MediaAttachment(
  id: id,
  messageId: messageId,
  mime: 'image/jpeg',
  size: 64,
  mediaType: 'image',
  localPath: localPath,
  downloadStatus: 'done',
  createdAt: '2026-07-10T00:00:00.000Z',
  contentHash: validHash,
  encryptionKeyBase64: 'a2V5',
  encryptionNonce: 'bm9uY2U=',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
);

const validHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
