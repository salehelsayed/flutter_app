import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  test('does nothing when no targets are selected', () async {
    final identityRepository = FakeIdentityRepository()..seed(_makeIdentity());
    var processCallCount = 0;
    var contactCallCount = 0;

    final coordinator = DefaultShareBatchDeliveryCoordinator(
      identityRepository: identityRepository,
      contactRepository: InMemoryContactRepository(),
      messageRepository: InMemoryMessageRepository(),
      mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
      groupRepository: InMemoryGroupRepository(),
      groupMessageRepository: InMemoryGroupMessageRepository(),
      bridge: FakeBridge(),
      p2pService: FakeP2PService(),
      mediaFileManager: FakeMediaFileManager(),
      imageProcessor: _imageProcessor(),
      processSharedMediaFn: (_) async {
        processCallCount++;
        return const [];
      },
      sendToContactFn:
          ({
            required identity,
            required shareIntent,
            required contact,
            required processedMedia,
          }) async {
            contactCallCount++;
            return ShareBatchTargetResult(
              target: ShareTargetSelection.contact(contact),
              status: ShareBatchTargetStatus.sent,
              detail: 'Sent.',
            );
          },
    );

    final result = await coordinator.deliver(
      shareIntent: const ShareIntent(type: ShareIntentType.text, text: 'hello'),
      targets: const [],
    );

    expect(result.results, isEmpty);
    expect(processCallCount, 0);
    expect(contactCallCount, 0);
  });

  test(
    'processes shared media once before fanout across target kinds',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final processedMedia = [
        PendingComposerMedia(file: File('/tmp/shared.jpg'), budgetBytes: 42),
      ];
      var processCallCount = 0;
      List<PendingComposerMedia>? contactMedia;
      List<PendingComposerMedia>? groupMedia;

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async {
          processCallCount++;
          return processedMedia;
        },
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
            }) async {
              contactMedia = processedMedia;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
        sendToGroupFn:
            ({
              required identity,
              required shareIntent,
              required group,
              required processedMedia,
            }) async {
              groupMedia = processedMedia;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.group(group),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      final contact = _makeContact('peer-alice', 'Alice');
      final group = _makeGroup('group-1', 'Writers');

      await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: const ['/tmp/shared.jpg'],
        ),
        targets: [
          ShareTargetSelection.contact(contact),
          ShareTargetSelection.group(group),
        ],
      );

      expect(processCallCount, 1);
      expect(identical(contactMedia, processedMedia), isTrue);
      expect(identical(groupMedia, processedMedia), isTrue);
    },
  );

  test('reports sent queued and failed results truthfully', () async {
    final identityRepository = FakeIdentityRepository()..seed(_makeIdentity());
    final coordinator = DefaultShareBatchDeliveryCoordinator(
      identityRepository: identityRepository,
      contactRepository: InMemoryContactRepository(),
      messageRepository: InMemoryMessageRepository(),
      mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
      groupRepository: InMemoryGroupRepository(),
      groupMessageRepository: InMemoryGroupMessageRepository(),
      bridge: FakeBridge(),
      p2pService: FakeP2PService(),
      mediaFileManager: FakeMediaFileManager(),
      imageProcessor: _imageProcessor(),
      processSharedMediaFn: (_) async => const [],
      sendToContactFn:
          ({
            required identity,
            required shareIntent,
            required contact,
            required processedMedia,
          }) async {
            return ShareBatchTargetResult(
              target: ShareTargetSelection.contact(contact),
              status: contact.peerId == 'peer-alice'
                  ? ShareBatchTargetStatus.sent
                  : ShareBatchTargetStatus.failed,
              detail: contact.peerId == 'peer-alice'
                  ? 'Sent.'
                  : 'Share failed.',
            );
          },
      sendToGroupFn:
          ({
            required identity,
            required shareIntent,
            required group,
            required processedMedia,
          }) async {
            return ShareBatchTargetResult(
              target: ShareTargetSelection.group(group),
              status: ShareBatchTargetStatus.queued,
              detail: 'Saved for retry.',
            );
          },
    );

    final sentContact = _makeContact('peer-alice', 'Alice');
    final failedContact = _makeContact('peer-bob', 'Bob');
    final group = _makeGroup('group-1', 'Writers');

    final result = await coordinator.deliver(
      shareIntent: const ShareIntent(type: ShareIntentType.text, text: 'hello'),
      targets: [
        ShareTargetSelection.contact(sentContact),
        ShareTargetSelection.contact(failedContact),
        ShareTargetSelection.group(group),
      ],
    );

    expect(result.sentCount, 1);
    expect(result.queuedCount, 1);
    expect(result.failureCount, 1);
    expect(result.hasFailures, isTrue);
    expect(result.failedTargetKeys, {
      ShareTargetSelection.contact(failedContact).key,
    });
  });
}

ImageProcessor _imageProcessor() {
  return ImageProcessor(
    compressFile:
        ({
          required path,
          required quality,
          required keepExif,
          minWidth = 1920,
          minHeight = 1080,
        }) async => null,
    compressVideo: ({required path, required compress, onProgress}) async =>
        const VideoProcessResult(path: '/tmp/video.mp4'),
  );
}

ContactModel _makeContact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-09T08:00:00.000Z',
  );
}

GroupModel _makeGroup(String id, String name) {
  return GroupModel(
    id: id,
    name: name,
    type: GroupType.chat,
    topicName: 'topic-$id',
    createdAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
    createdBy: 'me',
    myRole: GroupRole.admin,
  );
}

IdentityModel _makeIdentity() {
  return IdentityModel(
    peerId: 'my-peer-id-12345',
    publicKey: 'my-public-key',
    privateKey: 'my-private-key',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    mlKemPublicKey: 'mlkem-public',
    mlKemSecretKey: 'mlkem-secret',
    username: 'Me',
    createdAt: '2026-03-09T08:00:00.000Z',
    updatedAt: '2026-03-09T08:00:00.000Z',
  );
}
