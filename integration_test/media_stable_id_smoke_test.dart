import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart' as core_fake_p2p;
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_audio_recorder_service.dart';
import '../test/shared/fakes/fake_group_pubsub_network.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/group_test_user.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';

class _StableLocalVoiceP2PService extends core_fake_p2p.FakeP2PService {
  _StableLocalVoiceP2PService({
    required this.targetPeerId,
    required this.mediaAttachmentRepo,
    required String selfPeerId,
  }) : super(
         initialState: NodeState(isStarted: true, peerId: selfPeerId),
         sendMessageWithReplyResult: const SendMessageResult(
           sent: true,
           reply: 'ack',
         ),
       );

  final String targetPeerId;
  final InMemoryMediaAttachmentRepository mediaAttachmentRepo;

  String? observedPendingAttachmentId;
  String? observedMediaId;

  @override
  bool isLocalPeer(String peerId) => peerId == targetPeerId;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async {
    observedMediaId = mediaId;
    final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
    if (pending.isNotEmpty) {
      observedPendingAttachmentId = pending.single.id;
    }
    return true;
  }
}

class _MirroringGroupBridge extends FakeBridge {
  _MirroringGroupBridge({required this.network, required this.groupRepo});

  final FakeGroupPubSubNetwork network;
  final dynamic groupRepo;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final senderPeerId = payload['senderPeerId'] as String;
      final topicPeers = network
          .getSubscribers(groupId)
          .where((peerId) => peerId != senderPeerId)
          .length;
      final latestKey = await groupRepo.getLatestKey(groupId);
      final envelope = <String, dynamic>{
        'groupId': groupId,
        'senderId': senderPeerId,
        'senderUsername': payload['senderUsername'] as String? ?? '',
        'keyEpoch': latestKey?.keyGeneration ?? 0,
        'text': payload['text'] as String? ?? '',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'messageId': payload['messageId'] as String,
      };
      if (payload['quotedMessageId'] is String &&
          (payload['quotedMessageId'] as String).isNotEmpty) {
        envelope['quotedMessageId'] = payload['quotedMessageId'];
      }
      if (payload['media'] is List<dynamic>) {
        envelope['media'] = payload['media'] as List<dynamic>;
      }

      await network.publish(groupId, senderPeerId, envelope);
      return jsonEncode({
        'ok': true,
        'messageId': payload['messageId'] as String,
        'topicPeers': topicPeers,
      });
    }

    return super.send(message);
  }
}

class _TrackingDurableMediaFileManager extends FakeMediaFileManager {
  _TrackingDurableMediaFileManager(this.rootDir);

  final Directory rootDir;

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    final extension = p.extension(sourceFilePath);
    final directory = Directory(
      p.join(rootDir.path, 'pending_uploads', messageId),
    );
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final destination = p.join(directory.path, '$attachmentId$extension');
    await File(sourceFilePath).copy(destination);
    return p.join('pending_uploads', messageId, '$attachmentId$extension');
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\')) {
      return p.join(rootDir.path, storedPath);
    }
    return storedPath;
  }

  @override
  Future<void> deletePendingUploadDir(String messageId) async {
    final directory = Directory(
      p.join(rootDir.path, 'pending_uploads', messageId),
    );
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

ContactModel _makeContact({required String peerId, required String username}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
  );
}

IdentityModel _makeIdentity({
  required String peerId,
  required String username,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return IdentityModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    privateKey: 'sk-$peerId',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    username: username,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  int maxPumps = 60,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (await condition()) {
      return;
    }
    await tester.pump(step);
  }
  expect(await condition(), isTrue, reason: 'Condition was not met in time');
}

List<int> _minimalPngBytes() {
  return [
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
    0x00,
    0x02,
    0x00,
    0x01,
    0xE2,
    0x21,
    0xBC,
    0x33,
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
}

Future<File> _writePngFixture(Directory tempDir, String name) async {
  final file = File(p.join(tempDir.path, name));
  await file.writeAsBytes(_minimalPngBytes(), flush: true);
  return file;
}

Future<File> _writeAudioFixture(Directory tempDir, String name) async {
  final file = File(p.join(tempDir.path, name));
  await file.writeAsBytes(List<int>.filled(64, 7), flush: true);
  return file;
}

Future<void> _saveGroupKey(
  GroupTestUser user,
  String groupId,
  int keyGeneration,
  String encryptedKey,
) async {
  await user.groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: keyGeneration,
      encryptedKey: encryptedKey,
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

Future<GroupMessage> _latestOutgoingGroupMessage(
  GroupTestUser user,
  String groupId, {
  required String text,
}) async {
  final messages = await user.msgRepo.getMessagesPage(groupId, limit: 100);
  final matches =
      messages
          .where((message) => !message.isIncoming && message.text == text)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  expect(matches, isNotEmpty, reason: 'Missing outgoing group message');
  return matches.first;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Media stable-ID simulator smoke', () {
    testWidgets(
      '1:1 image send preserves the optimistic attachment id on simulator',
      (tester) async {
        final tempDir = await Directory.systemTemp.createTemp(
          'media_stable_id_img_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final contact = _makeContact(
          peerId: 'peer-image-contact',
          username: 'Image Contact',
        );
        final identity = _makeIdentity(
          peerId: 'peer-image-self',
          username: 'Image Sender',
        );
        final imageFile = await _writePngFixture(tempDir, 'one_to_one.png');

        final identityRepo = FakeIdentityRepository()..seed(identity);
        final messageRepo = InMemoryMessageRepository();
        final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
        final contactRepo = InMemoryContactRepository()
          ..addTestContact(contact);
        final bridge = FakeBridge();
        final p2pService = core_fake_p2p.FakeP2PService(
          initialState: NodeState(isStarted: true, peerId: identity.peerId),
          sendMessageWithReplyResult: const SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
        );
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          bridge: bridge,
        );

        String? optimisticAttachmentId;
        String? uploadedBlobId;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConversationWired(
              contact: contact,
              identityRepo: identityRepo,
              messageRepo: messageRepo,
              chatMessageListener: chatListener,
              p2pService: p2pService,
              bridge: bridge,
              contactRepo: contactRepo,
              mediaAttachmentRepo: mediaAttachmentRepo,
              sendChatMessageFn: sendChatMessage,
              uploadMediaFn:
                  ({
                    required bridge,
                    required localFilePath,
                    required mime,
                    required recipientPeerId,
                    mediaFileManager,
                    width,
                    height,
                    durationMs,
                    waveform,
                    allowedPeers,
                    blobId,
                  }) async {
                    uploadedBlobId = blobId;
                    final pending = await mediaAttachmentRepo
                        .getUploadPendingAttachments();
                    optimisticAttachmentId = pending.single.id;
                    return MediaAttachment(
                      id: blobId ?? 'server-generated-image-id',
                      messageId: '',
                      mime: mime,
                      size: await File(localFilePath).length(),
                      mediaType: MediaAttachment.mediaTypeFromMime(mime),
                      localPath: localFilePath,
                      downloadStatus: 'done',
                      createdAt: DateTime.now().toUtc().toIso8601String(),
                    );
                  },
              initialAttachments: [imageFile],
            ),
          ),
        );
        await _pumpFrames(tester);

        await tester.enterText(find.byType(TextField), 'Simulator image');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        await _pumpUntilAsync(
          tester,
          () async => (await messageRepo.getMessagesForContact(
            contact.peerId,
          )).where((message) => !message.isIncoming).isNotEmpty,
        );

        final sentMessage = (await messageRepo.getMessagesForContact(
          contact.peerId,
        )).last;
        await _pumpUntilAsync(tester, () async {
          final currentAttachments = await mediaAttachmentRepo
              .getAttachmentsForMessage(sentMessage.id);
          final pending = await mediaAttachmentRepo
              .getUploadPendingAttachments();
          return currentAttachments.length == 1 &&
              currentAttachments.single.id == optimisticAttachmentId &&
              currentAttachments.single.downloadStatus == 'done' &&
              pending.isEmpty;
        });
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sentMessage.id,
        );

        expect(optimisticAttachmentId, isNotNull);
        expect(uploadedBlobId, optimisticAttachmentId);
        expect(attachments, hasLength(1));
        expect(attachments.single.id, optimisticAttachmentId);
        expect(attachments.single.downloadStatus, 'done');
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      '1:1 local voice send preserves the optimistic attachment id on simulator',
      (tester) async {
        final tempDir = await Directory.systemTemp.createTemp(
          'media_stable_id_voice_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final contact = _makeContact(
          peerId: 'peer-voice-contact',
          username: 'Voice Contact',
        );
        final identity = _makeIdentity(
          peerId: 'peer-voice-self',
          username: 'Voice Sender',
        );
        final audioFile = await _writeAudioFixture(tempDir, 'voice.m4a');

        final identityRepo = FakeIdentityRepository()..seed(identity);
        final messageRepo = InMemoryMessageRepository();
        final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
        final contactRepo = InMemoryContactRepository()
          ..addTestContact(contact);
        final bridge = FakeBridge();
        final p2pService = _StableLocalVoiceP2PService(
          targetPeerId: contact.peerId,
          mediaAttachmentRepo: mediaAttachmentRepo,
          selfPeerId: identity.peerId,
        );
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1200
          ..fakeOutputPath = audioFile.path;
        addTearDown(recorder.dispose);
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          bridge: bridge,
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConversationWired(
              contact: contact,
              identityRepo: identityRepo,
              messageRepo: messageRepo,
              chatMessageListener: chatListener,
              p2pService: p2pService,
              bridge: bridge,
              contactRepo: contactRepo,
              mediaAttachmentRepo: mediaAttachmentRepo,
              sendChatMessageFn: sendChatMessage,
              audioRecorderService: recorder,
            ),
          ),
        );
        await _pumpFrames(tester);

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await tester.pump(const Duration(milliseconds: 100));

        final recordingScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        await stopRecording();

        await _pumpUntilAsync(
          tester,
          () async => (await messageRepo.getMessagesForContact(
            contact.peerId,
          )).where((message) => !message.isIncoming).isNotEmpty,
        );

        final sentMessage = (await messageRepo.getMessagesForContact(
          contact.peerId,
        )).last;
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sentMessage.id,
        );

        expect(p2pService.observedPendingAttachmentId, isNotNull);
        expect(
          p2pService.observedMediaId,
          p2pService.observedPendingAttachmentId,
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.id, p2pService.observedPendingAttachmentId);
        expect(attachments.single.downloadStatus, 'done');
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'announcement image send normalizes final attachment ids on simulator',
      (tester) async {
        final network = FakeGroupPubSubNetwork();
        final admin = GroupTestUser.create(
          peerId: 'announcement-admin-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'announcement-reader-peer',
          username: 'Reader',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          reader.dispose();
        });

        final tempDir = await Directory.systemTemp.createTemp(
          'media_stable_id_announce_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final attachment = await _writePngFixture(tempDir, 'announcement.png');
        final mediaFileManager = _TrackingDurableMediaFileManager(tempDir);

        const groupId = 'announcement-stable-id-group';
        final group = await admin.createGroup(
          groupId: groupId,
          name: 'Announcements',
          type: GroupType.announcement,
        );
        await admin.addMember(groupId: groupId, invitee: reader);
        await _saveGroupKey(admin, groupId, 1, 'announcement-key');
        await _saveGroupKey(reader, groupId, 1, 'announcement-key');
        admin.start();
        reader.start();

        final bridge = _MirroringGroupBridge(
          network: network,
          groupRepo: admin.groupRepo,
        );
        final identityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: admin.peerId,
              publicKey: admin.publicKey,
              privateKey: admin.privateKey,
              mnemonic12:
                  'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
              username: admin.username,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );

        String? uploadedBlobId;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GroupConversationWired(
              group: group,
              groupRepo: admin.groupRepo,
              msgRepo: admin.msgRepo,
              groupMessageListener: GroupMessageListener(
                groupRepo: admin.groupRepo,
                msgRepo: admin.msgRepo,
                bridge: bridge,
                getSelfPeerId: () async => admin.peerId,
                mediaAttachmentRepo: admin.mediaAttachmentRepo,
              ),
              bridge: bridge,
              identityRepo: identityRepo,
              contactRepo: InMemoryContactRepository(),
              p2pService: core_fake_p2p.FakeP2PService(
                initialState: NodeState(isStarted: true, peerId: admin.peerId),
              ),
              mediaAttachmentRepo: admin.mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              initialAttachments: [attachment],
              uploadMediaFn:
                  ({
                    required bridge,
                    required localFilePath,
                    required mime,
                    required recipientPeerId,
                    mediaFileManager,
                    width,
                    height,
                    durationMs,
                    waveform,
                    allowedPeers,
                    blobId,
                  }) async {
                    uploadedBlobId = blobId;
                    return MediaAttachment(
                      id: 'server-generated-announcement-id',
                      messageId: '',
                      mime: mime,
                      size: await File(localFilePath).length(),
                      mediaType: MediaAttachment.mediaTypeFromMime(mime),
                      localPath: localFilePath,
                      downloadStatus: 'done',
                      createdAt: DateTime.now().toUtc().toIso8601String(),
                      width: width,
                      height: height,
                      durationMs: durationMs,
                    );
                  },
            ),
          ),
        );
        await _pumpFrames(tester);

        await tester.enterText(find.byType(TextField), 'Announcement photo');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        await _pumpUntilAsync(tester, () async {
          final sent = await _latestOutgoingGroupMessage(
            admin,
            groupId,
            text: 'Announcement photo',
          );
          final readerMessages = await reader.msgRepo.getMessagesPage(
            groupId,
            limit: 100,
          );
          return readerMessages.any((message) => message.id == sent.id);
        });

        final sent = await _latestOutgoingGroupMessage(
          admin,
          groupId,
          text: 'Announcement photo',
        );
        final senderAttachments = await admin.mediaAttachmentRepo
            .getAttachmentsForMessage(sent.id);
        final readerMessage = (await reader.msgRepo.getMessagesPage(
          groupId,
          limit: 100,
        )).firstWhere((message) => message.id == sent.id);
        final readerAttachments = await reader.mediaAttachmentRepo
            .getAttachmentsForMessage(readerMessage.id);

        expect(uploadedBlobId, isNotNull);
        expect(senderAttachments, hasLength(1));
        expect(senderAttachments.single.id, uploadedBlobId);
        expect(senderAttachments.single.downloadStatus, 'done');
        expect(
          await admin.mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
        expect(readerAttachments, hasLength(1));
        expect(readerAttachments.single.id, uploadedBlobId);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
