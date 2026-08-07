import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _tinyPngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB1,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  setUp(() {
    setGroupExitIntentAccessSinks(
      forGroup: (_) async => null,
      all: () async => const <GroupExitIntent>[],
    );
  });
  tearDown(setGroupExitIntentAccessSinks);

  testWidgets(
    'opening private composer has zero delivery and source mutations',
    (tester) async {
      final sourceDirectory = Directory.systemTemp.createTempSync(
        'announcement-private-reply-source-',
      );
      addTearDown(() {
        if (sourceDirectory.existsSync()) {
          sourceDirectory.deleteSync(recursive: true);
        }
      });
      final sourceFile = File('${sourceDirectory.path}/source.png')
        ..writeAsBytesSync(_tinyPngBytes, flush: true);
      final group = GroupModel(
        id: 'announcement-group',
        name: 'Announcement group',
        type: GroupType.announcement,
        topicName: 'topic-announcement-group',
        createdAt: DateTime.utc(2026, 7, 11, 16),
        createdBy: 'admin-peer',
        myRole: GroupRole.member,
      );
      final sourceMessage = GroupMessage(
        id: 'announcement-source',
        groupId: group.id,
        senderPeerId: 'sender-peer',
        senderUsername: 'Sender',
        text: 'source caption',
        timestamp: DateTime.utc(2026, 7, 11, 17),
        createdAt: DateTime.utc(2026, 7, 11, 17),
        isIncoming: true,
        keyGeneration: 1,
        readAt: DateTime.utc(2026, 7, 11, 17, 1),
      );
      final sourceAttachment = MediaAttachment(
        id: 'visual-attachment',
        messageId: sourceMessage.id,
        mime: 'image/png',
        size: sourceFile.lengthSync(),
        mediaType: 'image',
        localPath: sourceFile.path,
        downloadStatus: 'done',
        createdAt: DateTime.utc(2026, 7, 11, 17).toIso8601String(),
        contentHash: _validContentHash,
        encryptionKeyBase64: 'a2V5',
        encryptionNonce: 'bm9uY2U=',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ownerLane: MediaOwnerLane.group,
      );
      final groupRepo = InMemoryGroupRepository();
      final groupMessages = _RecordingGroupMessageRepository();
      final groupAttachments = InMemoryMediaAttachmentRepository();
      final reactionRepo = FakeReactionRepository();
      await groupRepo.saveGroup(group);
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: group.id,
          keyGeneration: 1,
          encryptedKey: 'test-group-key',
          createdAt: DateTime.utc(2026, 7, 11, 16),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'own-peer',
          username: 'Own user',
          role: MemberRole.reader,
          publicKey: 'own-public-key',
          mlKemPublicKey: 'own-mlkem-public-key',
          joinedAt: DateTime.utc(2026, 7, 11, 16, 1),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'sender-peer',
          username: 'Sender',
          role: MemberRole.writer,
          publicKey: 'sender-public-key',
          mlKemPublicKey: 'sender-mlkem-public-key',
          joinedAt: DateTime.utc(2026, 7, 11, 16, 2),
        ),
      );
      await groupMessages.saveMessage(sourceMessage);
      await groupAttachments.saveAttachment(
        sourceAttachment,
        owner: MediaOwnerLane.group,
      );
      await reactionRepo.saveReaction(
        MessageReaction(
          id: 'source-reaction',
          messageId: sourceMessage.id,
          emoji: '👍',
          senderPeerId: 'reactor-peer',
          timestamp: DateTime.utc(2026, 7, 11, 17, 2).toIso8601String(),
          createdAt: DateTime.utc(2026, 7, 11, 17, 2).toIso8601String(),
        ),
      );

      final directMessages = InMemoryMessageRepository();
      final contacts = InMemoryContactRepository()..addTestContact(_contact());
      final identity = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'own-peer',
            mlKemPublicKey: 'own-mlkem-public-key',
            mlKemSecretKey: 'own-mlkem-secret-key',
          ),
        );
      final directListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: directMessages,
        contactRepo: contacts,
      );
      final groupListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMessages,
        reactionRepo: reactionRepo,
      );
      final bridge = FakeBridge();
      final p2p = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'own-peer'),
      );
      final mediaFileManager = FakeMediaFileManager();
      addTearDown(directListener.dispose);
      addTearDown(groupListener.dispose);
      addTearDown(p2p.dispose);

      var openerCalls = 0;
      var openerReturned = 0;
      var directSends = 0;
      var directUploads = 0;
      var directForwards = 0;
      var groupUploads = 0;
      var groupForwards = 0;
      final navigatorKey = GlobalKey<NavigatorState>();
      late OpenAnnouncementSenderConversation opener;
      opener = (contact) async {
        openerCalls += 1;
        await navigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ConversationWired(
              contact: contact,
              identityRepo: identity,
              messageRepo: directMessages,
              chatMessageListener: directListener,
              p2pService: p2p,
              bridge: bridge,
              contactRepo: contacts,
              initialMessages: const <ConversationMessage>[],
              micPermissionGateway: FakeMicPermissionGateway(),
              sendChatMessageFn:
                  ({
                    required P2PService p2pService,
                    required MessageRepository messageRepo,
                    required String targetPeerId,
                    required String text,
                    required String senderPeerId,
                    required String senderUsername,
                    String? messageId,
                    required bool preassignedMessageIdIsFresh,
                    String? timestamp,
                    Bridge? bridge,
                    String? recipientMlKemPublicKey,
                    String? quotedMessageId,
                    List<MediaAttachment>? mediaAttachments,
                    PrivateMediaPolicy? privateMediaPolicy,
                    MediaAttachmentRepository? mediaAttachmentRepo,
                    TransportMetrics? transportMetrics,
                  }) async {
                    directSends += 1;
                    throw StateError('Message sender must never auto-send');
                  },
              uploadMediaFn:
                  ({
                    required Bridge bridge,
                    required String localFilePath,
                    required String mime,
                    required String recipientPeerId,
                    MediaFileManager? mediaFileManager,
                    int? width,
                    int? height,
                    int? durationMs,
                    List<double>? waveform,
                    List<String>? allowedPeers,
                    String? blobId,
                    bool deleteSourceWhenDone = false,
                    EncryptedMediaArtifact? preparedArtifact,
                  }) async {
                    directUploads += 1;
                    throw StateError('Message sender must never auto-upload');
                  },
              receivedMediaForwardLauncher: (context, shareIntent) async {
                directForwards += 1;
                throw StateError('Message sender must never auto-Forward');
              },
            ),
          ),
        );
        openerReturned += 1;
      };

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepo,
            msgRepo: groupMessages,
            groupMessageListener: groupListener,
            bridge: bridge,
            identityRepo: identity,
            contactRepo: contacts,
            p2pService: p2p,
            mediaAttachmentRepo: groupAttachments,
            mediaFileManager: mediaFileManager,
            micPermissionGateway: FakeMicPermissionGateway(),
            reactionRepo: reactionRepo,
            openAnnouncementSenderConversation: opener,
            uploadMediaFn:
                ({
                  required Bridge bridge,
                  required String localFilePath,
                  required String mime,
                  required String recipientPeerId,
                  MediaFileManager? mediaFileManager,
                  int? width,
                  int? height,
                  int? durationMs,
                  List<double>? waveform,
                  List<String>? allowedPeers,
                  String? blobId,
                  bool deleteSourceWhenDone = false,
                  EncryptedMediaArtifact? preparedArtifact,
                }) async {
                  groupUploads += 1;
                  throw StateError('Message sender must never group-upload');
                },
            groupMediaForwardLauncher: (context, request) async {
              groupForwards += 1;
              throw StateError('Message sender must never group-Forward');
            },
          ),
        ),
      );

      await _pumpUntil(tester, () {
        if (!tester.any(find.byType(GroupConversationScreen))) return false;
        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        return screen.mediaMap[sourceMessage.id]?.length == 1 &&
            screen.reactions[sourceMessage.id]?.length == 1;
      }, failure: 'the seeded announcement media/reaction never loaded');
      final sourceCell = find.byKey(
        const ValueKey('media-grid-cell-announcement-source-visual-attachment'),
      );
      expect(sourceCell, findsOneWidget);

      final groupScreenBefore = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(groupScreenBefore.canWrite, isFalse);
      expect(find.byType(ComposeArea), findsNothing);
      final readOnlyBannerBefore = groupScreenBefore.readOnlyBannerText;
      final reactionUiBefore = _reactionBytes(
        groupScreenBefore.reactions[sourceMessage.id]!,
      );
      final reactionRowsBefore = _reactionBytes(reactionRepo.reactions);
      final reactionSaveCallsBefore = reactionRepo.saveReactionCallCount;
      final reactionRemoveCallsBefore = reactionRepo.removeReactionCallCount;
      final loadedSourceMessage = await groupMessages.getMessage(
        sourceMessage.id,
      );
      final loadedSourceAttachments = await groupAttachments
          .getAttachmentsForMessage(
            sourceMessage.id,
            owner: MediaOwnerLane.group,
          );
      final sourceHistoryBefore = _groupMessageBytes(
        await groupMessages.getMessagesPage(group.id),
      );
      expect(loadedSourceMessage, isNotNull);
      expect(loadedSourceAttachments, hasLength(1));
      final sourceMessageBefore = utf8.encode(
        jsonEncode(loadedSourceMessage!.toMap()),
      );
      final sourceAttachmentBefore = utf8.encode(
        jsonEncode(loadedSourceAttachments.single.toMap()),
      );
      final sourceFileBefore = sourceFile.readAsBytesSync();

      await tester.longPress(sourceCell);
      await _pumpUntil(
        tester,
        () => tester.any(
          find.byKey(MessageContextOverlay.messageSenderActionKey),
        ),
        failure: 'the eligible Message sender UI action never appeared',
      );
      await tester.tap(
        find.byKey(MessageContextOverlay.messageSenderActionKey),
      );
      await _pumpUntil(
        tester,
        () => tester.any(find.byType(ConversationWired)),
        failure: 'the Message sender dispatcher never opened ConversationWired',
      );

      expect(openerCalls, 1);
      expect(openerReturned, 0, reason: 'the opener awaits route return');
      expect(find.byType(ConversationWired), findsOneWidget);
      expect(find.byType(ComposeArea), findsOneWidget);
      final composer = tester.widget<TextField>(find.byType(TextField).first);
      expect(composer.controller?.text, isEmpty);
      expect(find.byType(QuotePreviewBar), findsNothing);
      expect(find.byType(AttachmentPreviewStrip), findsNothing);
      expect(directMessages.count, 0);
      expect(directSends, 0);
      expect(directUploads, 0);
      expect(directForwards, 0);
      expect(groupMessages.outgoingSaveCalls, 0);
      expect(groupUploads, 0);
      expect(groupForwards, 0);
      expect(p2p.sendMessageCallCount, 0);
      expect(p2p.sendMessageWithReplyCallCount, 0);
      expect(p2p.storeInInboxCallCount, 0);
      expect(bridge.sendCallCount, 0);

      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await _pumpUntil(
        tester,
        () =>
            !tester.any(find.byType(ConversationWired)) &&
            tester.any(find.byType(GroupConversationScreen)),
        failure: 'the direct route did not return to the announcement',
      );

      expect(find.byType(ConversationWired), findsNothing);
      expect(openerReturned, 1);
      expect(
        await directMessages.getMessagesForContact(_contact().peerId),
        isEmpty,
      );
      expect(directMessages.count, 0);
      expect(directSends, 0);
      expect(directUploads, 0);
      expect(directForwards, 0);
      expect(groupMessages.outgoingSaveCalls, 0);
      expect(groupUploads, 0);
      expect(groupForwards, 0);
      expect(p2p.sendMessageCallCount, 0);
      expect(p2p.sendMessageWithReplyCallCount, 0);
      expect(p2p.storeInInboxCallCount, 0);
      expect(bridge.sendCallCount, 0);
      expect(
        bridge.commandLog.where(
          (command) =>
              command == 'group:publish' ||
              command == 'group:sendReliable' ||
              command == 'group:inboxStore',
        ),
        isEmpty,
      );

      final sourceMessageAfter = await groupMessages.getMessage(
        sourceMessage.id,
      );
      final sourceAttachmentsAfter = await groupAttachments
          .getAttachmentsForMessage(
            sourceMessage.id,
            owner: MediaOwnerLane.group,
          );
      expect(groupMessages.count, 1);
      expect(groupAttachments.count, 1);
      expect(sourceMessageAfter, isNotNull);
      expect(sourceAttachmentsAfter, hasLength(1));
      expect(
        utf8.encode(jsonEncode(sourceMessageAfter!.toMap())),
        sourceMessageBefore,
      );
      expect(
        utf8.encode(jsonEncode(sourceAttachmentsAfter.single.toMap())),
        sourceAttachmentBefore,
      );
      expect(sourceFile.readAsBytesSync(), sourceFileBefore);
      expect(
        _groupMessageBytes(await groupMessages.getMessagesPage(group.id)),
        sourceHistoryBefore,
      );

      final groupScreenAfter = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(groupScreenAfter.canWrite, isFalse);
      expect(groupScreenAfter.readOnlyBannerText, readOnlyBannerBefore);
      expect(find.byType(ComposeArea), findsNothing);
      expect(
        _reactionBytes(groupScreenAfter.reactions[sourceMessage.id]!),
        reactionUiBefore,
      );
      expect(_reactionBytes(reactionRepo.reactions), reactionRowsBefore);
      expect(reactionRepo.saveReactionCallCount, reactionSaveCallsBefore);
      expect(reactionRepo.removeReactionCallCount, reactionRemoveCallsBefore);
    },
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String failure,
}) async {
  for (var index = 0; index < 80; index++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump(const Duration(milliseconds: 25));
    if (condition()) return;
  }
  fail(failure);
}

List<int> _groupMessageBytes(List<GroupMessage> messages) => utf8.encode(
  jsonEncode(
    messages.map((message) => message.toMap()).toList(growable: false),
  ),
);

List<int> _reactionBytes(List<MessageReaction> reactions) => utf8.encode(
  jsonEncode(
    reactions.map((reaction) => reaction.toMap()).toList(growable: false),
  ),
);

final class _RecordingGroupMessageRepository
    extends InMemoryGroupMessageRepository
    implements GroupMessageLocalDeletionAuthority {
  int outgoingSaveCalls = 0;

  @override
  Future<void> saveMessage(GroupMessage message) async {
    if (!message.isIncoming) outgoingSaveCalls += 1;
    await super.saveMessage(message);
  }

  @override
  Future<GroupMessageLocalDeletionState> getGroupMessageLocalDeletionState(
    String messageId,
  ) async => GroupMessageLocalDeletionState.knownClear;
}

ContactModel _contact() => ContactModel(
  peerId: 'sender-peer',
  publicKey: 'sender-public-key',
  rendezvous: 'rendezvous',
  username: 'Sender',
  signature: 'signature',
  scannedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
  mlKemPublicKey: 'sender-mlkem-public-key',
);
