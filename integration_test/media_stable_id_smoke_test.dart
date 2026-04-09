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
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart' as core_fake_p2p;
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_audio_recorder_service.dart';
import '../test/shared/fakes/fake_group_pubsub_network.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/group_test_user.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
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
  String relativePathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) {
    return p.join('media', contactPeerId, '$blobId${_extensionForMime(mime)}');
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
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final relativePath = relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
    final absolutePath = p.join(rootDir.path, relativePath);
    final file = File(absolutePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    return absolutePath;
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

class _DownloadWritingBridge extends FakeBridge {
  _DownloadWritingBridge({required this.downloadedBytes});

  final List<int> downloadedBytes;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'media:download') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      final payload = parsed['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      final file = File(outputPath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsBytesSync(downloadedBytes, flush: true);
      return jsonEncode({
        'ok': true,
        'id': payload['id'],
        'size': downloadedBytes.length,
      });
    }

    return super.send(message);
  }
}

class _DownloadingBlobBridge extends FakeBridge {
  _DownloadingBlobBridge({required this.fallbackBytes});

  final List<int> fallbackBytes;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'media:download') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(fallbackBytes, flush: true);
      return jsonEncode({
        'ok': true,
        'id': payload['id'] as String,
        'size': fallbackBytes.length,
      });
    }

    return super.send(message);
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

Future<void> _waitForRenderedMediaGrid(
  WidgetTester tester, {
  int expectedCount = 1,
}) async {
  await _pumpUntilAsync(tester, () async {
    final grids = find.byType(MediaGrid).evaluate().length;
    final broken = find
        .descendant(
          of: find.byType(MediaGrid),
          matching: find.byIcon(Icons.broken_image_outlined),
        )
        .evaluate()
        .length;
    return grids == expectedCount && broken == 0;
  });
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
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAAlwSFlzAAAuIwAALiMBeKU/dgAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KTMInWQAAAdVJREFUOBF9Uz1PG0EQfXt3PoNEYgrCh4AiSEnhICQLI0qoqHGN6PIDEE0qmqSNlCapwg9ImTpFAjYIR5DQuECyEFKk2HJhLEJxyN69zcyd116fE29xuzu7772Zt3NC08CIYZ8KMXzRGw71IwxOgpKx/xKEBHZI8aKh8PM2BO+n0sD20xQ8OxMuITlUGEfKNanXjgPtfQ104eRB1+5VdBB2z3kj+NNPGpESK5frCvvVDjK0eU7Kr1d8ZNKid24wjlnwbNL+boEXU8DBcgzuhHFZNqaXgTGHwXukPEnK8wR+l/PxyLeLtuFkMpdgwKXfEq+uZQSeJXvfr/qQpFppKqRdAUnF5p448GltxkAJbMaZAjjtD3kfbVq//NHG1pVEvtKJSmSw7VqvBMNYrks8m3ThUmCzGGB63EHGd3GwJLAy7YFF+vrdEgzYmPhAub74EuBOuGgqhaNsiI2lCXRUiJQ7kDQGdvx8TDJGnXKY9dFsS+qkU3z6+BmtP0EEph4wevEcm5j4djvl2+UvjYU3Gt5bPbdzqGuNVnQxtDppyAOmZQ1+God+hNJ5FcWLG0hKf3HmMXYL60h5bs+LfxLEucVEtmEcpy6OiM2dkQQGYEhE8tekC38BADIeNqhZl4wAAAAASUVORK5CYII=',
  );
}

String _extensionForMime(String mime) {
  if (mime == 'image/png') return '.png';
  if (mime == 'image/jpeg') return '.jpg';
  if (mime == 'audio/mp4' || mime == 'audio/x-m4a') return '.m4a';
  if (mime == 'audio/mpeg') return '.mp3';
  if (mime == 'video/mp4') return '.mp4';
  return '';
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

Future<GroupMessage?> _tryLatestOutgoingGroupMessage(
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
  return matches.isEmpty ? null : matches.first;
}

Future<GroupMessage> _latestOutgoingGroupMessage(
  GroupTestUser user,
  String groupId, {
  required String text,
}) async {
  final match = await _tryLatestOutgoingGroupMessage(
    user,
    groupId,
    text: text,
  );
  expect(match, isNotNull, reason: 'Missing outgoing group message');
  return match!;
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
        await _pumpFrames(tester);
        expect(find.byType(MediaGrid), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MediaGrid),
            matching: find.byIcon(Icons.broken_image_outlined),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      '1:1 image send survives deleting the original file during upload on simulator',
      (tester) async {
        final tempDir = await Directory.systemTemp.createTemp(
          'media_stable_id_img_delete_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final contact = _makeContact(
          peerId: 'peer-image-delete-contact',
          username: 'Image Delete Contact',
        );
        final identity = _makeIdentity(
          peerId: 'peer-image-delete-self',
          username: 'Image Delete Sender',
        );
        final imageFile = await _writePngFixture(
          tempDir,
          'one_to_one_delete.png',
        );
        final originalPath = imageFile.path;

        final identityRepo = FakeIdentityRepository()..seed(identity);
        final messageRepo = InMemoryMessageRepository();
        final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
        final contactRepo = InMemoryContactRepository()
          ..addTestContact(contact);
        final bridge = FakeBridge();
        final mediaFileManager = _TrackingDurableMediaFileManager(tempDir);
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

        String? observedUploadPath;
        bool durableCopyExistedDuringUpload = false;
        bool originalDeletedDuringUpload = false;

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
              mediaFileManager: mediaFileManager,
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
                    observedUploadPath = localFilePath;
                    durableCopyExistedDuringUpload = File(
                      localFilePath,
                    ).existsSync();
                    final original = File(originalPath);
                    if (original.existsSync()) {
                      await original.delete();
                      originalDeletedDuringUpload = true;
                    }
                    return MediaAttachment(
                      id: blobId ?? 'server-generated-delete-id',
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

        await tester.enterText(find.byType(TextField), 'Delete source photo');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        await _pumpUntilAsync(tester, () async {
          final messages = await messageRepo.getMessagesForContact(
            contact.peerId,
          );
          if (messages.where((message) => !message.isIncoming).isEmpty) {
            return false;
          }
          final sentMessage = messages.lastWhere(
            (message) => !message.isIncoming,
          );
          final attachments = await mediaAttachmentRepo
              .getAttachmentsForMessage(sentMessage.id);
          return attachments.length == 1 &&
              attachments.single.downloadStatus == 'done';
        });

        final sentMessage = (await messageRepo.getMessagesForContact(
          contact.peerId,
        )).lastWhere((message) => !message.isIncoming);
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sentMessage.id,
        );

        expect(originalDeletedDuringUpload, isTrue);
        expect(File(originalPath).existsSync(), isFalse);
        expect(observedUploadPath, isNotNull);
        expect(observedUploadPath, isNot(originalPath));
        expect(observedUploadPath, contains('pending_uploads'));
        expect(durableCopyExistedDuringUpload, isTrue);
        expect(attachments, hasLength(1));
        expect(attachments.single.downloadStatus, 'done');
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

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
              mediaFileManager: mediaFileManager,
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
                  }) async => null,
            ),
          ),
        );
        await _pumpFrames(tester);
        expect(find.byType(MediaGrid), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MediaGrid),
            matching: find.byIcon(Icons.broken_image_outlined),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      '1:1 conversation open re-downloads missing media from stored attachment rows on simulator',
      (tester) async {
        final tempDir = await Directory.systemTemp.createTemp(
          'media_missing_open_one_to_one_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final contact = _makeContact(
          peerId: 'peer-missing-media-contact',
          username: 'Missing Media Contact',
        );
        final identity = _makeIdentity(
          peerId: 'peer-missing-media-self',
          username: 'Missing Media Self',
        );
        final identityRepo = FakeIdentityRepository()..seed(identity);
        final messageRepo = InMemoryMessageRepository();
        final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
        final contactRepo = InMemoryContactRepository()
          ..addTestContact(contact);
        final bridge = _DownloadWritingBridge(
          downloadedBytes: _minimalPngBytes(),
        );
        final mediaFileManager = _TrackingDurableMediaFileManager(tempDir);
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          bridge: bridge,
        );

        const messageId = 'incoming-missing-media-open';
        const blobId = 'incoming-missing-media-blob';
        final messageTimestamp = DateTime.now().toUtc().toIso8601String();
        final storedRelativePath = mediaFileManager.relativePathForAttachment(
          contactPeerId: contact.peerId,
          blobId: blobId,
          mime: 'image/png',
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: messageId,
            contactPeerId: contact.peerId,
            senderPeerId: contact.peerId,
            text: '',
            timestamp: messageTimestamp,
            status: 'delivered',
            isIncoming: true,
            createdAt: messageTimestamp,
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: blobId,
            messageId: messageId,
            mime: 'image/png',
            size: _minimalPngBytes().length,
            mediaType: 'image',
            localPath: storedRelativePath,
            downloadStatus: 'done',
            createdAt: messageTimestamp,
          ),
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
              p2pService: core_fake_p2p.FakeP2PService(
                initialState: NodeState(
                  isStarted: true,
                  peerId: identity.peerId,
                ),
              ),
              bridge: bridge,
              contactRepo: contactRepo,
              mediaAttachmentRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              sendChatMessageFn: sendChatMessage,
            ),
          ),
        );
        await _pumpFrames(tester);

        await _pumpUntilAsync(tester, () async {
          final attachments = await mediaAttachmentRepo
              .getAttachmentsForMessage(messageId);
          final resolvedPath = p.join(tempDir.path, storedRelativePath);
          if (attachments.length != 1 || !File(resolvedPath).existsSync()) {
            return false;
          }
          final screen = tester.widget<ConversationScreen>(
            find.byType(ConversationScreen),
          );
          final visibleMessages = screen.messages
              .where((message) => message.id == messageId)
              .toList();
          return visibleMessages.length == 1 &&
              visibleMessages.single.media.length == 1 &&
              visibleMessages.single.media.single.downloadStatus == 'done';
        });

        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          messageId,
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.localPath, storedRelativePath);
        expect(attachments.single.downloadStatus, 'done');
        expect(
          bridge.commandLog.where((cmd) => cmd == 'media:download').length,
          1,
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
        final tempDir = await Directory.systemTemp.createTemp(
          'media_stable_id_announce_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final attachment = await _writePngFixture(tempDir, 'announcement.png');
        final senderMediaFileManager = _TrackingDurableMediaFileManager(
          Directory(p.join(tempDir.path, 'sender_fs')),
        );
        final readerMediaFileManager = _TrackingDurableMediaFileManager(
          Directory(p.join(tempDir.path, 'reader_fs')),
        );
        final readerBridge = _DownloadingBlobBridge(
          fallbackBytes: await attachment.readAsBytes(),
        );

        final admin = GroupTestUser.create(
          peerId: 'announcement-admin-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'announcement-reader-peer',
          username: 'Reader',
          network: network,
          bridge: readerBridge,
          mediaFileManager: readerMediaFileManager,
        );
        addTearDown(() {
          admin.dispose();
          reader.dispose();
        });

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
              mediaFileManager: senderMediaFileManager,
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
          final sent = await _tryLatestOutgoingGroupMessage(
            admin,
            groupId,
            text: 'Announcement photo',
          );
          if (sent == null) return false;
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
        final senderStoredPath = senderAttachments.single.localPath;
        expect(senderStoredPath, isNotNull);
        expect(
          File(
            await senderMediaFileManager.resolveStoredPath(senderStoredPath!),
          ).existsSync(),
          isTrue,
        );
        await _waitForRenderedMediaGrid(tester);
        expect(find.byType(MediaGrid), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MediaGrid),
            matching: find.byIcon(Icons.broken_image_outlined),
          ),
          findsNothing,
        );

        await _pumpUntilAsync(tester, () async {
          final downloaded = await reader.mediaAttachmentRepo
              .getAttachmentsForMessage(readerMessage.id);
          if (downloaded.length != 1) {
            return false;
          }
          final attachment = downloaded.single;
          if (attachment.downloadStatus != 'done' ||
              attachment.localPath == null) {
            return false;
          }
          final resolvedPath = await readerMediaFileManager.resolveStoredPath(
            attachment.localPath!,
          );
          return File(resolvedPath).existsSync();
        });

        final readerGroup = await reader.groupRepo.getGroup(groupId);
        expect(readerGroup, isNotNull);
        final readerIdentityRepo = FakeIdentityRepository()
          ..seed(
            IdentityModel(
              peerId: reader.peerId,
              publicKey: reader.publicKey,
              privateKey: reader.privateKey,
              mnemonic12:
                  'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
              username: reader.username,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GroupConversationWired(
              group: readerGroup!,
              groupRepo: reader.groupRepo,
              msgRepo: reader.msgRepo,
              groupMessageListener: reader.groupMessageListener,
              bridge: readerBridge,
              identityRepo: readerIdentityRepo,
              contactRepo: InMemoryContactRepository(),
              p2pService: core_fake_p2p.FakeP2PService(
                initialState: NodeState(isStarted: true, peerId: reader.peerId),
              ),
              mediaAttachmentRepo: reader.mediaAttachmentRepo,
              mediaFileManager: readerMediaFileManager,
            ),
          ),
        );
        await _waitForRenderedMediaGrid(tester);
        expect(find.text('Announcement photo'), findsOneWidget);
        expect(find.byType(MediaGrid), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MediaGrid),
            matching: find.byIcon(Icons.broken_image_outlined),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'group conversation open re-downloads missing media from stored attachment rows on simulator',
      (tester) async {
        final tempDir = await Directory.systemTemp.createTemp(
          'group_missing_media_open_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final identity = _makeIdentity(
          peerId: 'group-missing-media-self',
          username: 'Group Missing Media Self',
        );
        final identityRepo = FakeIdentityRepository()..seed(identity);
        final groupRepo = InMemoryGroupRepository();
        final messageRepo = InMemoryGroupMessageRepository();
        final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
        final mediaFileManager = _TrackingDurableMediaFileManager(tempDir);
        final bridge = _DownloadWritingBridge(
          downloadedBytes: _minimalPngBytes(),
        );

        final group = GroupModel(
          id: 'group-missing-media-open',
          name: 'Missing Media Group',
          type: GroupType.chat,
          topicName: 'topic-missing-media-open',
          description: 'Smoke',
          createdAt: DateTime.now().toUtc(),
          createdBy: identity.peerId,
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(group);

        const messageId = 'group-missing-media-message';
        const blobId = 'group-missing-media-blob';
        final timestamp = DateTime.now().toUtc();
        final storedRelativePath = mediaFileManager.relativePathForAttachment(
          contactPeerId: group.id,
          blobId: blobId,
          mime: 'image/png',
        );

        await messageRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: group.id,
            senderPeerId: 'peer-ibra',
            senderUsername: 'Ibra',
            text: '',
            timestamp: timestamp,
            status: 'sent',
            isIncoming: true,
            createdAt: timestamp,
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: blobId,
            messageId: messageId,
            mime: 'image/png',
            size: _minimalPngBytes().length,
            mediaType: 'image',
            localPath: storedRelativePath,
            downloadStatus: 'done',
            createdAt: timestamp.toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GroupConversationWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: messageRepo,
              groupMessageListener: GroupMessageListener(
                groupRepo: groupRepo,
                msgRepo: messageRepo,
                bridge: bridge,
                getSelfPeerId: () async => identity.peerId,
                mediaAttachmentRepo: mediaAttachmentRepo,
              ),
              bridge: bridge,
              identityRepo: identityRepo,
              contactRepo: InMemoryContactRepository(),
              p2pService: core_fake_p2p.FakeP2PService(
                initialState: NodeState(
                  isStarted: true,
                  peerId: identity.peerId,
                ),
              ),
              mediaAttachmentRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
            ),
          ),
        );
        await _pumpFrames(tester);

        await _pumpUntilAsync(tester, () async {
          final attachments = await mediaAttachmentRepo
              .getAttachmentsForMessage(messageId);
          final resolvedPath = p.join(tempDir.path, storedRelativePath);
          if (attachments.length != 1 || !File(resolvedPath).existsSync()) {
            return false;
          }
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final media = screen.mediaMap[messageId];
          return media != null &&
              media.length == 1 &&
              media.single.downloadStatus == 'done';
        });

        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          messageId,
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.localPath, storedRelativePath);
        expect(attachments.single.downloadStatus, 'done');
        expect(
          bridge.commandLog.where((cmd) => cmd == 'media:download').length,
          1,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
