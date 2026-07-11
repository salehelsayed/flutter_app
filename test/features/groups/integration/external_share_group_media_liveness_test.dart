import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

class _CountingGroupMessages extends InMemoryGroupMessageRepository {
  int pageLoads = 0;

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit == 50) pageLoads++;
    return super.getMessagesPage(groupId, limit: limit, offset: offset);
  }
}

class _HeldParentSaveGroupMessages extends _CountingGroupMessages {
  _HeldParentSaveGroupMessages(this.heldMessageId);

  final String heldMessageId;
  final Completer<void> parentSaveStarted = Completer<void>();
  final Completer<void> releaseParentSave = Completer<void>();
  bool _held = false;

  @override
  Future<void> saveMessage(GroupMessage message) async {
    if (!_held &&
        message.id == heldMessageId &&
        !message.isIncoming &&
        message.status == 'sending') {
      _held = true;
      parentSaveStarted.complete();
      await releaseParentSave.future;
    }
    await super.saveMessage(message);
  }
}

class _RecordingMedia extends InMemoryMediaAttachmentRepository {
  final List<MediaAttachment> saved = [];

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    saved.add(attachment.copyWith(ownerLane: owner));
    await super.saveAttachment(attachment, owner: owner);
  }
}

class _MissingDurableMedia extends InMemoryMediaAttachmentRepository {
  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => const [];
}

IdentityModel _identity() => IdentityModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  privateKey: 'sk-admin',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  mlKemPublicKey: 'mlkem-admin',
  username: 'Admin',
  createdAt: '2026-07-11T10:00:00.000Z',
  updatedAt: '2026-07-11T10:00:00.000Z',
);

GroupModel _group() => GroupModel(
  id: 'group-1',
  name: 'Share Group',
  type: GroupType.chat,
  topicName: 'topic-group-1',
  createdAt: DateTime.utc(2026, 7, 11, 10),
  createdBy: 'peer-admin',
  myRole: GroupRole.admin,
);

Future<void> _seedGroup(InMemoryGroupRepository repository) async {
  final group = _group();
  await repository.saveGroup(group);
  await repository.saveKey(
    GroupKeyInfo(
      groupId: group.id,
      keyGeneration: 1,
      encryptedKey: 'group-key-1',
      createdAt: DateTime.utc(2026, 7, 11, 10),
    ),
  );
  await repository.saveMember(
    GroupMember(
      groupId: group.id,
      peerId: 'peer-admin',
      username: 'Admin',
      role: MemberRole.admin,
      publicKey: 'pk-admin',
      mlKemPublicKey: 'mlkem-admin',
      joinedAt: DateTime.utc(2026, 7, 11, 10),
    ),
  );
  await repository.saveMember(
    GroupMember(
      groupId: group.id,
      peerId: 'peer-writer',
      username: 'Writer',
      role: MemberRole.writer,
      publicKey: 'pk-writer',
      mlKemPublicKey: 'mlkem-writer',
      joinedAt: DateTime.utc(2026, 7, 11, 10, 1),
    ),
  );
}

Map<String, dynamic> _reliableSuccess() => {
  'ok': true,
  'publishSucceeded': true,
  'inboxStored': true,
  'topicPeerCount': 1,
  'connectedTopicPeerCount': 1,
  'expectedRecipientCount': 1,
  'recipientPeerIds': ['peer-writer'],
  'deliveryMode': 'live_and_inbox',
  'envelope': '{"kind":"test-reliable-envelope"}',
};

PassthroughCryptoBridge _bridge() =>
    PassthroughCryptoBridge()
      ..responses['group:sendReliable'] = _reliableSuccess();

class _HeldReliableBridge extends PassthroughCryptoBridge {
  final Completer<void> reliableStarted = Completer<void>();
  final Completer<void> releaseReliable = Completer<void>();

  _HeldReliableBridge() {
    responses['group:sendReliable'] = _reliableSuccess();
  }

  @override
  Future<String> send(String message) async {
    final command = (jsonDecode(message) as Map<String, dynamic>)['cmd'];
    if (command == 'group:sendReliable') {
      if (!reliableStarted.isCompleted) reliableStarted.complete();
      await releaseReliable.future;
    }
    return super.send(message);
  }
}

ImageProcessor _imageProcessor() => ImageProcessor(
  compressFile:
      ({
        required path,
        required quality,
        required keepExif,
        minWidth = 1920,
        minHeight = 1080,
      }) async => null,
  compressVideo: ({required path, required compress, onProgress}) async => null,
);

Widget _conversation({
  required InMemoryGroupRepository groups,
  required InMemoryGroupMessageRepository messages,
  required InMemoryMediaAttachmentRepository media,
  required FakeIdentityRepository identities,
  required PassthroughCryptoBridge bridge,
  required FakeP2PService p2p,
  required GroupMessageListener listener,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: GroupConversationWired(
    group: _group(),
    groupRepo: groups,
    msgRepo: messages,
    groupMessageListener: listener,
    bridge: bridge,
    identityRepo: identities,
    contactRepo: InMemoryContactRepository(),
    p2pService: p2p,
    mediaAttachmentRepo: media,
  ),
);

DefaultShareBatchDeliveryCoordinator _coordinator({
  required InMemoryGroupRepository groups,
  required InMemoryGroupMessageRepository messages,
  required InMemoryMediaAttachmentRepository media,
  required FakeIdentityRepository identities,
  required PassthroughCryptoBridge bridge,
  required FakeP2PService p2p,
  required FakeMediaFileManager files,
  required File image,
}) => DefaultShareBatchDeliveryCoordinator(
  identityRepository: identities,
  contactRepository: InMemoryContactRepository(),
  messageRepository: InMemoryMessageRepository(),
  mediaAttachmentRepository: media,
  groupRepository: groups,
  groupMessageRepository: messages,
  bridge: bridge,
  p2pService: p2p,
  mediaFileManager: files,
  imageProcessor: _imageProcessor(),
  processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
    processedMedia: [
      PendingComposerMedia(file: image, budgetBytes: image.lengthSync()),
    ],
  ),
);

Future<void> _pumpFrames(WidgetTester tester, {int count = 20}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'failed media pre-persist rollback leaves no tombstone or mounted-screen ghost',
    (tester) async {
      const messageId = 'group-media-rollback-no-ghost';
      final groups = InMemoryGroupRepository();
      await _seedGroup(groups);
      final messages = _CountingGroupMessages();
      final media = _MissingDurableMedia();
      final identities = FakeIdentityRepository()..seed(_identity());
      final bridge = _bridge();
      final p2p = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'peer-admin',
          relayState: 'online',
        ),
      );
      final listener = GroupMessageListener(
        groupRepo: groups,
        msgRepo: messages,
      );
      addTearDown(listener.dispose);
      await tester.pumpWidget(
        _conversation(
          groups: groups,
          messages: messages,
          media: media,
          identities: identities,
          bridge: bridge,
          p2p: p2p,
          listener: listener,
        ),
      );
      await _pumpFrames(tester);

      late (SendGroupMessageResult, GroupMessage?) sendResult;
      await tester.runAsync(() async {
        sendResult = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groups,
          msgRepo: messages,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-admin',
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-admin',
          senderUsername: 'Admin',
          messageId: messageId,
          timestamp: DateTime.utc(2026, 7, 11, 10, 2),
          mediaAttachments: [
            MediaAttachment(
              id: 'rollback-no-ghost-attachment',
              messageId: '',
              mime: 'image/png',
              size: 68,
              mediaType: 'image',
              width: 1,
              height: 1,
              localPath: '/tmp/rollback-no-ghost.png',
              downloadStatus: 'done',
              createdAt: '2026-07-11T10:02:00.000Z',
              contentHash:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              encryptionKeyBase64: 'rollback-no-ghost-key',
              encryptionNonce: 'rollback-no-ghost-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
          ],
          mediaAttachmentRepo: media,
        );
      });
      expect(sendResult.$1, SendGroupMessageResult.error);
      expect(sendResult.$2, isNull);
      await _pumpFrames(tester);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(
        screen.messages.any((message) => message.id == messageId),
        isFalse,
      );
      expect(screen.mediaMap.containsKey(messageId), isFalse);
      expect(await messages.getMessage(messageId), isNull);
      expect(await messages.getLocalDeletionGroupId(messageId), isNull);
    },
  );

  testWidgets(
    'external image share to an open group conversation surfaces the message with its thumbnail while mounted',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('group-share-live-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final image = File('${temp.path}/shared.png')
        ..writeAsBytesSync(base64Decode(_tinyPngBase64));
      final groups = InMemoryGroupRepository();
      await _seedGroup(groups);
      final messages = _CountingGroupMessages();
      final media = _RecordingMedia();
      final identities = FakeIdentityRepository()..seed(_identity());
      final bridge = _bridge();
      final p2p = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'peer-admin',
          relayState: 'online',
        ),
      );
      final files = FakeMediaFileManager();
      MediaFileManager.cacheDocumentsDir(FakeMediaFileManager.testRootPath);
      addTearDown(MediaFileManager.debugResetDocumentsDirCache);
      final listener = GroupMessageListener(
        groupRepo: groups,
        msgRepo: messages,
      );
      addTearDown(listener.dispose);

      await tester.pumpWidget(
        _conversation(
          groups: groups,
          messages: messages,
          media: media,
          identities: identities,
          bridge: bridge,
          p2p: p2p,
          listener: listener,
        ),
      );
      await _pumpFrames(tester);
      final initialPageLoads = messages.pageLoads;

      late ShareBatchDeliveryResult result;
      await tester.runAsync(() async {
        result =
            await _coordinator(
              groups: groups,
              messages: messages,
              media: media,
              identities: identities,
              bridge: bridge,
              p2p: p2p,
              files: files,
              image: image,
            ).deliver(
              shareIntent: ShareIntent(
                type: ShareIntentType.files,
                filePaths: [image.path],
              ),
              targets: [ShareTargetSelection.group(_group())],
            );
      });
      expect(result.failureCount, 0);
      await _pumpFrames(tester);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      final mediaMessageIds = screen.mediaMap.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => entry.key)
          .toSet();
      expect(mediaMessageIds, hasLength(1));
      expect(
        screen.messages.any((message) => mediaMessageIds.contains(message.id)),
        isTrue,
      );
      expect(find.byType(MediaGrid), findsWidgets);
      expect(find.byType(MediaThumbnailImage), findsOneWidget);
      expect(
        messages.pageLoads,
        initialPageLoads,
        reason: 'the inserted row must hydrate without reloading the page',
      );
    },
  );

  testWidgets(
    'a mid-send group media row renders its thumbnail on the first loaded frame',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('group-share-frame-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final image = File('${temp.path}/shared.png')
        ..writeAsBytesSync(base64Decode(_tinyPngBase64));
      final groups = InMemoryGroupRepository();
      await _seedGroup(groups);
      const messageId = 'mid-send-first-frame';
      final messages = _HeldParentSaveGroupMessages(messageId);
      final media = _RecordingMedia();
      final identities = FakeIdentityRepository()..seed(_identity());
      final bridge = _HeldReliableBridge();
      addTearDown(() {
        if (!messages.releaseParentSave.isCompleted) {
          messages.releaseParentSave.complete();
        }
        if (!bridge.releaseReliable.isCompleted) {
          bridge.releaseReliable.complete();
        }
      });
      final p2p = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'peer-admin',
          relayState: 'online',
        ),
      );
      final attachment = MediaAttachment(
        id: 'mid-send-first-frame-att',
        messageId: '',
        mime: 'image/png',
        size: image.lengthSync(),
        mediaType: 'image',
        localPath: image.path,
        downloadStatus: 'done',
        createdAt: '2026-07-11T10:00:00.000Z',
        contentHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        encryptionKeyBase64: 'mid-send-key',
        encryptionNonce: 'mid-send-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      final delivery = sendGroupMessage(
        bridge: bridge,
        groupRepo: groups,
        msgRepo: messages,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-admin',
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
        messageId: messageId,
        mediaAttachments: [attachment],
        mediaAttachmentRepo: media,
      );
      var deliveryCompleted = false;
      unawaited(
        delivery.then<void>(
          (_) => deliveryCompleted = true,
          onError: (Object _, StackTrace _) => deliveryCompleted = true,
        ),
      );

      await messages.parentSaveStarted.future;
      expect(
        await messages.getMessage(messageId),
        isNull,
        reason: 'the parent save must still be held',
      );
      final durableBeforeParent = await media.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.group,
      );
      expect(durableBeforeParent, hasLength(1));
      expect(durableBeforeParent.single.id, attachment.id);
      expect(durableBeforeParent.single.messageId, messageId);
      expect(durableBeforeParent.single.downloadStatus, 'done');
      expect(deliveryCompleted, isFalse);

      messages.releaseParentSave.complete();
      await bridge.reliableStarted.future;

      final persistedWhileHeld = await messages.getMessage(messageId);
      expect(persistedWhileHeld?.status, 'sending');
      expect(deliveryCompleted, isFalse);
      expect(
        media.saved.single.messageId,
        messageId,
        reason: 'the attachment must be durable before reliable delivery',
      );
      final listener = GroupMessageListener(
        groupRepo: groups,
        msgRepo: messages,
      );
      addTearDown(listener.dispose);
      await tester.pumpWidget(
        _conversation(
          groups: groups,
          messages: messages,
          media: media,
          identities: identities,
          bridge: bridge,
          p2p: p2p,
          listener: listener,
        ),
      );
      GroupConversationScreen? screen;
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        final screenFinder = find.byType(GroupConversationScreen);
        if (screenFinder.evaluate().isEmpty) continue;
        final candidate = tester.widget<GroupConversationScreen>(screenFinder);
        if (candidate.messages.isNotEmpty) {
          screen = candidate;
          break;
        }
      }

      expect(screen, isNotNull, reason: 'the persisted sending row must load');
      final firstMessageFrame = screen!;
      expect(deliveryCompleted, isFalse);
      expect(firstMessageFrame.messages.single.status, 'sending');
      expect(firstMessageFrame.messages, hasLength(1));
      expect(
        firstMessageFrame.mediaMap[firstMessageFrame.messages.single.id],
        hasLength(1),
      );
      expect(find.byType(MediaGrid), findsOneWidget);
      expect(find.byType(MediaThumbnailImage), findsOneWidget);

      bridge.releaseReliable.complete();
      final (result, _) = await delivery;
      expect(result, SendGroupMessageResult.success);
    },
  );
}
