import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/constants/media_constants.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
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
        return const ProcessedShareMediaBatch(processedMedia: []);
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
          return ProcessedShareMediaBatch(processedMedia: processedMedia);
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
      processSharedMediaFn: (_) async =>
          const ProcessedShareMediaBatch(processedMedia: []),
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

  test(
    'mixed share skips oversized GIFs while keeping valid sibling media',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final tempDir = await Directory.systemTemp.createTemp(
        'share_batch_gif_mixed_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final oversizedGif = File('${tempDir.path}/too-big.gif');
      final oversizedGifHandle = oversizedGif.openSync(mode: FileMode.write);
      oversizedGifHandle.truncateSync(kMaxGifFileSize + 1);
      oversizedGifHandle.closeSync();
      final jpg = File('${tempDir.path}/valid.jpg')
        ..writeAsBytesSync([1, 2, 3]);

      List<PendingComposerMedia>? deliveredMedia;
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
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
            }) async {
              deliveredMedia = processedMedia;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [oversizedGif.path, jpg.path],
        ),
        targets: [
          ShareTargetSelection.contact(_makeContact('peer-alice', 'Alice')),
        ],
      );

      expect(result.skippedOversizedGifCount, 1);
      expect(
        result.skippedOversizedGifReason,
        'Some attachments were too large and were skipped.',
      );
      expect(deliveredMedia, isNotNull);
      expect(deliveredMedia, hasLength(1));
      expect(deliveredMedia!.single.file.path, jpg.path);
    },
  );

  test(
    'share-batch applies per-type size caps to non-GIF media (OQ-2)',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final tempDir = await Directory.systemTemp.createTemp(
        'share_batch_non_gif_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      // A non-decodable fake JPEG never compresses, so its final budget bytes
      // stay above the per-type image cap and it is skipped on FINAL bytes
      // (the per-type table now applies to non-GIF share media too).
      final oversizedJpg = File('${tempDir.path}/large-photo.jpg');
      final oversizedJpgHandle = oversizedJpg.openSync(mode: FileMode.write);
      oversizedJpgHandle.truncateSync(kGroupMediaImageLimitBytes + 1);
      oversizedJpgHandle.closeSync();
      final smallJpg = File('${tempDir.path}/ok.jpg')
        ..writeAsBytesSync([1, 2, 3]);

      List<PendingComposerMedia>? deliveredMedia;
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
        sendToContactFn:
            ({
              required identity,
              required shareIntent,
              required contact,
              required processedMedia,
            }) async {
              deliveredMedia = processedMedia;
              return ShareBatchTargetResult(
                target: ShareTargetSelection.contact(contact),
                status: ShareBatchTargetStatus.sent,
                detail: 'Sent.',
              );
            },
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [oversizedJpg.path, smallJpg.path],
        ),
        targets: [
          ShareTargetSelection.contact(_makeContact('peer-alice', 'Alice')),
        ],
      );

      // The over-cap image is skipped; the within-cap sibling is still delivered.
      expect(result.skippedOversizedGifCount, 1);
      expect(deliveredMedia, isNotNull);
      expect(deliveredMedia, hasLength(1));
      expect(deliveredMedia!.single.file.path, smallJpg.path);
    },
  );

  test(
    'text-only group share wraps publish in a background task and stays sent on durable success',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final groupRepository = InMemoryGroupRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      final bridge = _GroupShareBgBridge(
        publishMessageId: 'group-bg-sent',
        publishTopicPeers: 1,
        inboxStoreOk: true,
      );

      await groupRepository.saveGroup(_makeGroup('group-1', 'Writers'));
      await _seedGroupMembers(groupRepository, 'group-1');
      await _saveLatestGroupKey(groupRepository, 'group-1');

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        bridge: bridge,
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
      );

      final result = await coordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'hello group',
        ),
        targets: [ShareTargetSelection.group(_makeGroup('group-1', 'Writers'))],
      );

      expect(result.sentCount, 1);
      expect(result.queuedCount, 0);
      expect(result.results.single.status, ShareBatchTargetStatus.sent);
      expect(result.results.single.detail, 'Sent.');
      _expectCommandOrder(bridge.commandLog, 'bg:begin', 'group:publish');
      _expectCommandOrder(
        bridge.commandLog,
        'group:publish',
        'group:inboxStore',
      );
      _expectCommandOrder(bridge.commandLog, 'group:inboxStore', 'bg:end');

      final saved = await groupMessageRepository.getMessagesPage('group-1');
      expect(saved, isNotEmpty);
      expect(saved.first.status, 'sent');
      expect(saved.first.inboxStored, isTrue);
    },
  );

  test(
    // 210b pin: an offline group share (publish-without-custody) reports the
    // honest queued outcome — never 'Share failed.' — and the durable row is
    // 'queued_offline' so the repush lane self-heals it on reconnect.
    'group share queued offline reports queued with the back-online copy',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final groupRepository = InMemoryGroupRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      final bridge = _GroupShareReliableNoCustodyBridge();

      await groupRepository.saveGroup(_makeGroup('group-3', 'Offline Writers'));
      await _seedGroupMembers(groupRepository, 'group-3');
      await _saveLatestGroupKey(groupRepository, 'group-3');

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        bridge: bridge,
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
      );

      final result = await coordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'hello offline group',
        ),
        targets: [
          ShareTargetSelection.group(_makeGroup('group-3', 'Offline Writers')),
        ],
      );

      expect(result.queuedCount, 1);
      expect(result.results.single.status, ShareBatchTargetStatus.queued);
      expect(
        result.results.single.detail,
        "Stored — will send when you're back online.",
      );

      final saved = await groupMessageRepository.getMessagesPage('group-3');
      expect(saved, isNotEmpty);
      expect(saved.first.status, 'queued_offline');
      expect(saved.first.inboxRetryPayload, isNotNull);
    },
  );

  test(
    'group share treats live publish as sent while retaining inbox retry custody',
    () async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final groupRepository = InMemoryGroupRepository();
      final groupMessageRepository = InMemoryGroupMessageRepository();
      final bridge = _GroupShareBgBridge(
        publishMessageId: 'group-bg-pending',
        publishTopicPeers: 1,
        inboxStoreOk: false,
      );

      await groupRepository.saveGroup(_makeGroup('group-2', 'Pending Writers'));
      await _seedGroupMembers(groupRepository, 'group-2');
      await _saveLatestGroupKey(groupRepository, 'group-2');

      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        bridge: bridge,
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
      );

      final result = await coordinator.deliver(
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'pending group share',
        ),
        targets: [
          ShareTargetSelection.group(_makeGroup('group-2', 'Pending Writers')),
        ],
      );

      expect(result.sentCount, 1);
      expect(result.queuedCount, 0);
      expect(result.results.single.status, ShareBatchTargetStatus.sent);
      expect(result.results.single.detail, 'Sent.');
      _expectCommandOrder(bridge.commandLog, 'bg:begin', 'group:publish');
      _expectCommandOrder(
        bridge.commandLog,
        'group:publish',
        'group:inboxStore',
      );
      _expectCommandOrder(bridge.commandLog, 'group:inboxStore', 'bg:end');

      final saved = await groupMessageRepository.getMessagesPage('group-2');
      expect(saved, isNotEmpty);
      expect(saved.first.status, 'sent');
      expect(saved.first.inboxStored, isFalse);
      expect(saved.first.inboxRetryPayload, isNotNull);
    },
  );

  // --- 112 Phase 2.4: OS share-sheet sender (LAN-XOR-relay fix) ---
  // These exercise the REAL `_sendToContact` (no sendToContactFn stub).
  group('share media encryption', () {
    Map<String, dynamic> wireMediaAttachment(FakeP2PService p2pService) {
      final wire =
          p2pService.lastSendMessageContent ??
          p2pService.lastStoreInInboxMessage;
      expect(wire, isNotNull, reason: 'no outbound envelope was produced');
      final envelope = jsonDecode(wire!) as Map<String, dynamic>;
      final inner =
          jsonDecode(
                (envelope['encrypted'] as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
      final media = inner['media'] as List<dynamic>;
      return media.single as Map<String, dynamic>;
    }

    Future<
      ({
        ShareBatchDeliveryResult result,
        PassthroughCryptoBridge bridge,
        FakeP2PService p2pService,
      })
    >
    deliverOneImage({required FakeP2PService p2pService}) async {
      final identityRepository = FakeIdentityRepository()
        ..seed(_makeIdentity());
      final contact = ContactModel(
        peerId: 'peer-share-enc',
        publicKey: 'pk-peer-share-enc',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'SharePeer',
        signature: 'sig-peer-share-enc',
        scannedAt: '2026-03-09T08:00:00.000Z',
        mlKemPublicKey: 'mlkem-peer-share-enc',
      );
      final contactRepository = InMemoryContactRepository();
      await contactRepository.addContact(contact);

      final sharedDir = Directory.systemTemp.createTempSync('share_enc_');
      addTearDown(() {
        if (sharedDir.existsSync()) {
          sharedDir.deleteSync(recursive: true);
        }
      });
      final sharedFile = File('${sharedDir.path}/shared.jpg')
        ..writeAsBytesSync(List<int>.filled(512, 0x7a));

      final bridge = PassthroughCryptoBridge();
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: contactRepository,
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
          processedMedia: [
            PendingComposerMedia(file: sharedFile, budgetBytes: 512),
          ],
        ),
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [sharedFile.path],
        ),
        targets: [ShareTargetSelection.contact(contact)],
      );
      return (result: result, bridge: bridge, p2pService: p2pService);
    }

    test(
      'production contact leg remints identity and persists forward provenance per target',
      () async {
        final identityRepository = FakeIdentityRepository()
          ..seed(_makeIdentity());
        final contacts = InMemoryContactRepository();
        final first = ContactModel(
          peerId: 'peer-forward-one',
          publicKey: 'pk-forward-one',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'One',
          signature: 'sig-forward-one',
          scannedAt: '2026-07-10T08:00:00.000Z',
          mlKemPublicKey: 'mlkem-forward-one',
        );
        final second = ContactModel(
          peerId: 'peer-forward-two',
          publicKey: 'pk-forward-two',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Two',
          signature: 'sig-forward-two',
          scannedAt: '2026-07-10T08:00:00.000Z',
          mlKemPublicKey: 'mlkem-forward-two',
        );
        await contacts.addContact(first);
        await contacts.addContact(second);
        final dir = Directory.systemTemp.createTempSync('forward_contact_leg_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/source.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        final messages = InMemoryMessageRepository();
        final media = InMemoryMediaAttachmentRepository();
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: identityRepository,
          contactRepository: contacts,
          messageRepository: messages,
          mediaAttachmentRepository: media,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: PassthroughCryptoBridge(),
          p2pService: FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id-12345',
            ),
          ),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
            processedMedia: [PendingComposerMedia(file: file, budgetBytes: 3)],
          ),
        );

        final result = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.mixed,
            text: 'editable caption',
            filePaths: [file.path],
            forwardProvenance: const ForwardProvenance(
              operationDedupKey: 'forward-operation-one',
            ),
          ),
          targets: [
            ShareTargetSelection.contact(first),
            ShareTargetSelection.contact(second),
          ],
        );

        expect(result.failureCount, 0);
        final firstRows = await messages.getMessagesForContact(first.peerId);
        final secondRows = await messages.getMessagesForContact(second.peerId);
        expect(firstRows, hasLength(1));
        expect(secondRows, hasLength(1));
        expect(firstRows.single.id, isNot(secondRows.single.id));
        expect(firstRows.single.timestamp, isNot(secondRows.single.timestamp));
        expect(firstRows.single.dedupKey, 'forward-operation-one');
        expect(secondRows.single.dedupKey, 'forward-operation-one');
        expect(firstRows.single.isForwarded, isTrue);
        expect(secondRows.single.isForwarded, isTrue);
        final firstMedia = await media.getAttachmentsForMessage(
          firstRows.single.id,
          owner: MediaOwnerLane.direct,
        );
        final secondMedia = await media.getAttachmentsForMessage(
          secondRows.single.id,
          owner: MediaOwnerLane.direct,
        );
        expect(firstMedia, hasLength(1));
        expect(secondMedia, hasLength(1));
        expect(firstMedia.single.id, isNot(secondMedia.single.id));
        expect(
          firstMedia.single.encryptionKeyBase64,
          isNot(secondMedia.single.encryptionKeyBase64),
        );

        final externalResult = await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: [file.path],
          ),
          targets: [ShareTargetSelection.contact(first)],
        );
        expect(externalResult.failureCount, 0);
        final externalRow = (await messages.getMessagesForContact(
          first.peerId,
        )).singleWhere((row) => row.id != firstRows.single.id);
        expect(externalRow.isForwarded, isFalse);
        expect(externalRow.dedupKey, externalRow.id);
        expect(externalRow.dedupKey, isNot('forward-operation-one'));
      },
    );

    test(
      'multi-target media forward preprocesses once and encrypts/uploads separately per contact',
      () async {
        final identities = FakeIdentityRepository()..seed(_makeIdentity());
        final contacts = InMemoryContactRepository();
        final first = ContactModel(
          peerId: 'peer-crypto-one',
          publicKey: 'pk-one',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'One',
          signature: 'sig-one',
          scannedAt: '2026-07-10T08:00:00.000Z',
          mlKemPublicKey: 'mlkem-one',
        );
        final second = ContactModel(
          peerId: 'peer-crypto-two',
          publicKey: 'pk-two',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Two',
          signature: 'sig-two',
          scannedAt: '2026-07-10T08:00:00.000Z',
          mlKemPublicKey: 'mlkem-two',
        );
        await contacts.addContact(first);
        await contacts.addContact(second);
        final dir = Directory.systemTemp.createTempSync('forward_crypto_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/source.jpg')
          ..writeAsBytesSync([9, 8, 7]);
        final sourceBytes = file.readAsBytesSync();
        final messages = InMemoryMessageRepository();
        final media = InMemoryMediaAttachmentRepository();
        const sourceAttachment = MediaAttachment(
          id: 'source-stored-blob',
          messageId: 'source-message',
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          localPath: '/source/library/source.jpg',
          downloadStatus: 'done',
          createdAt: '2026-07-10T07:59:00.000Z',
          encryptionKeyBase64: 'source-stored-key',
          encryptionNonce: 'source-stored-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.direct,
          isBookmarked: true,
          lastPlaybackPositionMs: 88,
        );
        await media.saveAttachment(
          sourceAttachment,
          owner: MediaOwnerLane.direct,
        );
        final sourceBefore = (await media.getAttachmentsForMessage(
          sourceAttachment.messageId,
          owner: MediaOwnerLane.direct,
        )).single;
        var preprocessCount = 0;
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: identities,
          contactRepository: contacts,
          messageRepository: messages,
          mediaAttachmentRepository: media,
          groupRepository: InMemoryGroupRepository(),
          groupMessageRepository: InMemoryGroupMessageRepository(),
          bridge: PassthroughCryptoBridge(),
          p2pService: FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id-12345',
            ),
          ),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          processSharedMediaFn: (_) async {
            preprocessCount++;
            return ProcessedShareMediaBatch(
              processedMedia: [
                PendingComposerMedia(file: file, budgetBytes: 3),
              ],
            );
          },
        );

        await coordinator.deliver(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: [file.path],
            forwardProvenance: const ForwardProvenance(
              operationDedupKey: 'operation-crypto',
            ),
          ),
          targets: [
            ShareTargetSelection.contact(first),
            ShareTargetSelection.contact(second),
          ],
        );

        expect(preprocessCount, 1);
        final firstMessage = (await messages.getMessagesForContact(
          first.peerId,
        )).single;
        final secondMessage = (await messages.getMessagesForContact(
          second.peerId,
        )).single;
        final firstAttachment = (await media.getAttachmentsForMessage(
          firstMessage.id,
          owner: MediaOwnerLane.direct,
        )).single;
        final secondAttachment = (await media.getAttachmentsForMessage(
          secondMessage.id,
          owner: MediaOwnerLane.direct,
        )).single;
        expect(firstAttachment.id, isNot(secondAttachment.id));
        expect(
          firstAttachment.encryptionKeyBase64,
          isNot(secondAttachment.encryptionKeyBase64),
        );
        expect(
          firstAttachment.encryptionNonce,
          isNot(secondAttachment.encryptionNonce),
        );
        final sourceAfter = (await media.getAttachmentsForMessage(
          sourceAttachment.messageId,
          owner: MediaOwnerLane.direct,
        )).single;
        expect(sourceAfter.id, sourceBefore.id);
        expect(
          sourceAfter.encryptionKeyBase64,
          sourceBefore.encryptionKeyBase64,
        );
        expect(sourceAfter.encryptionNonce, sourceBefore.encryptionNonce);
        expect(sourceAfter.encryptionScheme, sourceBefore.encryptionScheme);
        expect(sourceAfter.localPath, sourceBefore.localPath);
        expect(sourceAfter.isBookmarked, sourceBefore.isBookmarked);
        expect(
          sourceAfter.lastPlaybackPositionMs,
          sourceBefore.lastPlaybackPositionMs,
        );
        expect(firstAttachment.id, isNot(sourceAttachment.id));
        expect(secondAttachment.id, isNot(sourceAttachment.id));
        expect(
          firstAttachment.encryptionKeyBase64,
          isNot(sourceAttachment.encryptionKeyBase64),
        );
        expect(
          secondAttachment.encryptionNonce,
          isNot(sourceAttachment.encryptionNonce),
        );
        expect(file.readAsBytesSync(), sourceBytes);
      },
    );

    test('share to a LAN peer still relay-uploads and the attachment carries '
        'encryption metadata', () async {
      final p2pService = _LanFakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-12345',
        ),
      )..sendLocalMediaResult = true;

      final outcome = await deliverOneImage(p2pService: p2pService);

      // The G5 gate passes — the share is not rejected.
      expect(
        outcome.result.results.single.status,
        isNot(ShareBatchTargetStatus.failed),
      );
      // LAN best-effort happened…
      expect(p2pService.sendLocalMediaCallCount, 1);
      // …but the relay upload was made anyway (the LAN-XOR-relay
      // `continue` is gone)…
      expect(
        outcome.bridge.commandLog,
        containsAllInOrder(['blob:keygen', 'blob:encrypt', 'media:upload']),
      );
      // …and the wire attachment carries the encryption metadata.
      final attachment = wireMediaAttachment(p2pService);
      expect(attachment['encryptionKeyBase64'], isNotNull);
      expect(attachment['encryptionNonce'], isNotNull);
      expect(attachment['encryptionScheme'], isNotNull);
      expect(attachment['contentHash'], isNotNull);
    });

    test('share LAN send streams the encrypted artifact, never the raw shared '
        'file', () async {
      final p2pService = _LanFakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-12345',
        ),
      )..sendLocalMediaResult = true;

      await deliverOneImage(p2pService: p2pService);

      expect(p2pService.sendLocalMediaCallCount, 1);
      // 112 Phase 4: the LAN leg streams the ciphertext artifact under an
      // enc-flagged opaque-mime offer — never the raw shared file.
      expect(
        p2pService.lastSendLocalMediaFilePath,
        isNot(endsWith('shared.jpg')),
      );
      expect(p2pService.lastSendLocalMediaFilePath, endsWith('.enc'));
      expect(p2pService.lastSendLocalMediaEnc, isTrue);
      expect(p2pService.lastSendLocalMediaMime, kOpaqueMediaTransportMime);
      expect(
        p2pService.lastSendLocalMediaEncScheme,
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
    });

    test('share to a non-LAN contact produces encrypted attachment via '
        'uploadMedia', () async {
      final p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-12345',
        ),
      );

      final outcome = await deliverOneImage(p2pService: p2pService);

      expect(
        outcome.result.results.single.status,
        isNot(ShareBatchTargetStatus.failed),
      );
      expect(p2pService.sendLocalMediaCallCount, 0);
      expect(
        outcome.bridge.commandLog,
        containsAllInOrder(['blob:keygen', 'blob:encrypt', 'media:upload']),
      );
      final attachment = wireMediaAttachment(p2pService);
      expect(attachment['encryptionKeyBase64'], isNotNull);
      expect(attachment['encryptionNonce'], isNotNull);
      expect(attachment['encryptionScheme'], isNotNull);
    });
  });

  test(
    'group forward target preserves publish contract and saves group owner',
    () async {
      final identities = FakeIdentityRepository()..seed(_makeIdentity());
      final groups = InMemoryGroupRepository();
      final groupMessages = InMemoryGroupMessageRepository();
      final media = InMemoryMediaAttachmentRepository();
      final group = _makeGroup('group-forward-owner', 'Forward Owners');
      await groups.saveGroup(group);
      await _seedGroupMembers(groups, group.id);
      await _saveLatestGroupKey(groups, group.id);
      final dir = Directory.systemTemp.createTempSync('forward_group_owner_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/source.jpg')..writeAsBytesSync([1, 2, 3]);
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identities,
        contactRepository: InMemoryContactRepository(),
        messageRepository: InMemoryMessageRepository(),
        mediaAttachmentRepository: media,
        groupRepository: groups,
        groupMessageRepository: groupMessages,
        bridge: _GroupShareBgBridge(
          publishMessageId: 'group-forward-owner-message',
          publishTopicPeers: 1,
          inboxStoreOk: true,
        ),
        p2pService: FakeP2PService(),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
          processedMedia: [PendingComposerMedia(file: file, budgetBytes: 3)],
        ),
      );

      final result = await coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.mixed,
          text: 'group caption',
          filePaths: [file.path],
          forwardProvenance: const ForwardProvenance(
            operationDedupKey: 'direct-only-provenance',
          ),
        ),
        targets: [ShareTargetSelection.group(group)],
      );

      expect(result.failureCount, 0);
      final saved = (await groupMessages.getMessagesPage(group.id)).first;
      expect(saved.text, 'group caption');
      final attachments = await media.getAttachmentsForMessage(
        saved.id,
        owner: MediaOwnerLane.group,
      );
      expect(attachments, hasLength(1));
      expect(attachments.single.ownerLane, MediaOwnerLane.group);
    },
  );
}

class _LanFakeP2PService extends FakeP2PService {
  _LanFakeP2PService({super.initialState});

  @override
  bool isLocalPeer(String peerId) => true;
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

Future<void> _saveLatestGroupKey(
  InMemoryGroupRepository groupRepository,
  String groupId,
) async {
  await groupRepository.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'test-group-key-1',
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

Future<void> _seedGroupMembers(
  InMemoryGroupRepository groupRepository,
  String groupId,
) async {
  final joinedAt = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
  await groupRepository.saveMember(
    GroupMember(
      groupId: groupId,
      peerId: 'my-peer-id-12345',
      username: 'Me',
      role: MemberRole.admin,
      publicKey: 'my-public-key',
      mlKemPublicKey: 'mlkem-public',
      joinedAt: joinedAt,
    ),
  );
  await groupRepository.saveMember(
    GroupMember(
      groupId: groupId,
      peerId: 'peer-writer',
      username: 'Writer',
      role: MemberRole.writer,
      publicKey: 'pk-peer-writer',
      mlKemPublicKey: 'mlkem-peer-writer',
      joinedAt: joinedAt.add(const Duration(seconds: 1)),
    ),
  );
}

/// 210b: the realistic offline-device reliable contract — publish "succeeds"
/// with zero live topic peers and no relay custody, so the use case returns
/// queuedOffline and persists a durable 'queued_offline' row.
class _GroupShareReliableNoCustodyBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'bg:begin') {
      commandLog.add(cmd!);
      return 'share-group-bg-task';
    }
    if (cmd == 'bg:end') {
      commandLog.add(cmd!);
      return '';
    }
    if (cmd == 'group:sendReliable') {
      commandLog.add(cmd!);
      return jsonEncode({
        'ok': true,
        'publishSucceeded': true,
        'inboxStored': false,
        'topicPeerCount': 0,
        'connectedTopicPeerCount': 0,
        'expectedRecipientCount': 2,
        'recipientPeerIds': ['peer-writer', 'peer-reader'],
        'deliveryMode': 'live_only',
      });
    }
    return super.send(message);
  }
}

class _GroupShareBgBridge extends FakeBridge {
  _GroupShareBgBridge({
    required this.publishMessageId,
    required this.publishTopicPeers,
    required this.inboxStoreOk,
  });

  final String publishMessageId;
  final int publishTopicPeers;
  final bool inboxStoreOk;

  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);

    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    lastCommand = cmd;
    if (cmd != null) {
      commandLog.add(cmd);
    }

    switch (cmd) {
      case 'bg:begin':
        return 'share-group-bg-task';
      case 'bg:end':
        return '';
      case 'group.encrypt':
        final payload = parsed['payload'] as Map<String, dynamic>;
        return jsonEncode({
          'ok': true,
          'ciphertext': payload['plaintext'],
          'nonce': 'share-group-fake-nonce',
        });
      case 'payload.sign':
        return jsonEncode({'ok': true, 'signature': 'share-group-signature'});
      case 'group:publish':
        return jsonEncode({
          'ok': true,
          'messageId': publishMessageId,
          'topicPeers': publishTopicPeers,
        });
      case 'group:inboxStore':
        return jsonEncode({'ok': inboxStoreOk});
      default:
        return super.send(message);
    }
  }
}

void _expectCommandOrder(List<String> commands, String earlier, String later) {
  expect(commands, contains(earlier));
  expect(commands, contains(later));
  expect(commands.indexOf(earlier), lessThan(commands.indexOf(later)));
}
