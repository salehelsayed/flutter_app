import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_media_picker.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

// --- FakeIdentityRepository ---

class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;
  FakeIdentityRepository({this.identity});

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

// --- Fake listener with externally-controlled stream ---

/// A fake GroupMessageListener whose [groupMessageStream] is controlled
/// by an external StreamController.
class FakeGroupMessageListener extends GroupMessageListener {
  final Stream<GroupMessage> _externalStream;
  final Stream<ReactionChange>? _externalReactionStream;

  FakeGroupMessageListener(
    this._externalStream, {
    Stream<ReactionChange>? reactionStream,
  }) : _externalReactionStream = reactionStream,
       super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;

  @override
  Stream<ReactionChange> get groupReactionChangeStream =>
      _externalReactionStream ?? super.groupReactionChangeStream;
}

class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpMsgRepo implements GroupMessageRepository {
  @override
  Future<int> transitionSendingToFailed() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A bridge that gates group:publish behind a [Completer] so tests can
/// verify optimistic display before the network responds.
class _GatedPublishBridge extends FakeBridge {
  final Completer<void> publishGate = Completer<void>();

  _GatedPublishBridge() {
    responses['group:publish'] = {'ok': true, 'messageId': 'msg-published'};
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      await publishGate.future;
    }

    return super.send(message);
  }
}

class TrackingDurableMediaFileManager extends FakeMediaFileManager {
  TrackingDurableMediaFileManager(this.rootDir);

  final Directory rootDir;
  int copyCalls = 0;
  final List<String> deletedPendingUploadDirs = <String>[];

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    copyCalls++;
    final ext = p.extension(sourceFilePath);
    final dir = Directory(p.join(rootDir.path, 'pending_uploads', messageId));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final destinationPath = p.join(dir.path, '$attachmentId$ext');
    await File(sourceFilePath).copy(destinationPath);
    return p.join('pending_uploads', messageId, '$attachmentId$ext');
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\') ||
        storedPath.startsWith('post_media/') ||
        storedPath.startsWith('post_media\\')) {
      return p.join(rootDir.path, storedPath);
    }
    return storedPath;
  }

  @override
  Future<void> deletePendingUploadDir(String messageId) async {
    deletedPendingUploadDirs.add(messageId);
    final dir = Directory(p.join(rootDir.path, 'pending_uploads', messageId));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

class _DelayedNotFoundGroupRepository extends InMemoryGroupRepository {
  _DelayedNotFoundGroupRepository(this.delay);

  final Duration delay;

  @override
  Future<GroupModel?> getGroup(String id) async {
    await Future<void>.delayed(delay);
    return null;
  }
}

class CountingGroupMessageRepository extends InMemoryGroupMessageRepository {
  int getMessagesPageCalls = 0;
  int getMessageCalls = 0;

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    getMessagesPageCalls++;
    return super.getMessagesPage(groupId, limit: limit, offset: offset);
  }

  @override
  Future<GroupMessage?> getMessage(String id) async {
    getMessageCalls++;
    return super.getMessage(id);
  }
}

class SlowInitialPageGroupMessageRepository
    extends CountingGroupMessageRepository {
  final Completer<void> firstPageGate = Completer<void>();

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    await firstPageGate.future;
    return super.getMessagesPage(groupId, limit: limit, offset: offset);
  }
}

class CountingMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  int getAttachmentsForMessagesCalls = 0;
  int getAttachmentsForMessageCalls = 0;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    getAttachmentsForMessageCalls++;
    return super.getAttachmentsForMessage(messageId);
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async {
    getAttachmentsForMessagesCalls++;
    return super.getAttachmentsForMessages(messageIds);
  }
}

// --- Test data ---

final testIdentity = IdentityModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  privateKey: 'sk-admin',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pk-admin',
  username: 'Admin',
  createdAt: DateTime.now().toUtc().toIso8601String(),
  updatedAt: DateTime.now().toUtc().toIso8601String(),
);

GroupModel makeChatGroup({GroupRole role = GroupRole.admin}) => GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  description: 'A test group',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: role,
);

GroupModel makeAnnouncementGroup({GroupRole role = GroupRole.admin}) =>
    GroupModel(
      id: 'group-1',
      name: 'Announce Group',
      type: GroupType.announcement,
      topicName: 'topic-1',
      description: 'Announcement',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: role,
    );

GroupMessage makeMessage({
  required String id,
  required String text,
  String groupId = 'group-1',
  bool isIncoming = true,
  String senderPeerId = 'peer-alice',
  String senderUsername = 'Alice',
  String? quotedMessageId,
}) => GroupMessage(
  id: id,
  groupId: groupId,
  senderPeerId: senderPeerId,
  senderUsername: senderUsername,
  text: text,
  quotedMessageId: quotedMessageId,
  timestamp: DateTime.now().toUtc(),
  isIncoming: isIncoming,
  createdAt: DateTime.now().toUtc(),
);

// --- Helpers ---

/// Pump enough frames for async operations to complete.
/// AmbientBackground has an infinite animation, so pumpAndSettle will timeout.
Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 40,
}) async {
  var pumps = 0;
  while (!condition() && pumps < maxPumps) {
    await tester.pump(const Duration(milliseconds: 50));
    pumps++;
  }
}

void main() {
  group('GroupConversationWired', () {
    late InMemoryGroupRepository groupRepo;
    late CountingGroupMessageRepository msgRepo;
    late CountingMediaAttachmentRepository mediaAttachmentRepo;
    late InMemoryContactRepository contactRepo;
    late FakeBridge bridge;
    late FakeIdentityRepository identityRepo;
    late FakeP2PService p2pService;
    late StreamController<GroupMessage> messageStreamController;

    setUp(() {
      groupRepo = InMemoryGroupRepository();
      msgRepo = CountingGroupMessageRepository();
      mediaAttachmentRepo = CountingMediaAttachmentRepository();
      contactRepo = InMemoryContactRepository();
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': true, 'messageId': 'msg-published'},
        },
      );
      identityRepo = FakeIdentityRepository(identity: testIdentity);
      p2pService = FakeP2PService();
      messageStreamController = StreamController<GroupMessage>.broadcast();
    });

    tearDown(() {
      messageStreamController.close();
    });

    Widget buildWidget({
      GroupModel? group,
      CountingMediaAttachmentRepository? mediaRepo,
      ImageProcessor? imageProcessor,
      FakeAudioRecorderService? audioRecorderService,
      MediaPicker? mediaPicker,
      MediaFileManager? mediaFileManager,
      UploadMediaFn? uploadMediaFn,
      List<File>? initialAttachments,
      String? initialText,
      ReactionRepository? reactionRepo,
      StreamController<ReactionChange>? reactionStreamController,
    }) {
      final g = group ?? makeChatGroup();
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GroupConversationWired(
          group: g,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupMessageListener: FakeGroupMessageListener(
            messageStreamController.stream,
            reactionStream: reactionStreamController?.stream,
          ),
          bridge: bridge,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: mediaFileManager,
          imageProcessor: imageProcessor,
          audioRecorderService: audioRecorderService,
          mediaPicker: mediaPicker,
          uploadMediaFn: uploadMediaFn ?? uploadMedia,
          initialAttachments: initialAttachments,
          initialText: initialText,
          reactionRepo: reactionRepo,
        ),
      );
    }

    testWidgets('prefills shared text into the group composer', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(
        buildWidget(group: group, initialText: 'Shared group text'),
      );
      await pumpFrames(tester);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Shared group text');
    });

    testWidgets('loads and displays messages on init', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
      await msgRepo.saveMessage(makeMessage(id: 'msg-2', text: 'World'));
      await msgRepo.saveMessage(makeMessage(id: 'msg-3', text: 'How are you?'));

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('World'), findsOneWidget);
      expect(find.text('How are you?'), findsOneWidget);
    });

    testWidgets('sending a message calls bridge and refreshes', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);
      expect(msgRepo.getMessagesPageCalls, 1);

      // Type a message
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Test message');
      await pumpFrames(tester);

      // Tap send button (the arrow_upward_rounded icon inside ComposeArea)
      final sendButton = find.byIcon(Icons.arrow_upward_rounded);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await pumpFrames(tester, count: 20);

      // Verify bridge received group:publish command
      expect(bridge.commandLog, contains('group:publish'));
      expect(msgRepo.getMessagesPageCalls, 1);

      // The sent message should appear in the list
      expect(find.text('Test message'), findsOneWidget);
    });

    testWidgets(
      'media uploads persist upload_pending rows before upload and run in parallel from durable copies',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync('group-media-');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final files = [
          File('${tempDir.path}/one.jpg')..writeAsStringSync('one'),
          File('${tempDir.path}/two.jpg')..writeAsStringSync('two'),
          File('${tempDir.path}/three.jpg')..writeAsStringSync('three'),
        ];

        final mediaFileManager = FakeMediaFileManager();
        final uploadStarts = <DateTime>[];
        final seenBlobIds = <String>[];
        final pendingSeenBeforeUpload = <bool>[];
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            initialAttachments: files,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async {
                  uploadStarts.add(DateTime.now().toUtc());
                  seenBlobIds.add(blobId!);
                  final pending = await mediaAttachmentRepo
                      .getUploadPendingAttachments();
                  pendingSeenBeforeUpload.add(pending.isNotEmpty);
                  expect(
                    pending.every(
                      (att) =>
                          att.downloadStatus == 'upload_pending' &&
                          (att.localPath?.startsWith('pending_uploads/') ??
                              false),
                    ),
                    isTrue,
                  );
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                  return MediaAttachment(
                    id: 'server-assigned-${seenBlobIds.length}',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'Durable media');
        await pumpFrames(tester);
        final stopwatch = Stopwatch()..start();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 25);
        stopwatch.stop();

        expect(uploadStarts, hasLength(3));
        expect(
          uploadStarts.last.difference(uploadStarts.first).inMilliseconds,
          lessThan(80),
        );
        expect(pendingSeenBeforeUpload.every((seen) => seen), isTrue);

        final savedMessage = await msgRepo.getLatestMessage(group.id);
        expect(savedMessage, isNotNull);
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(savedMessage!.id);
        expect(savedAttachments, hasLength(3));
        expect(
          savedAttachments.every((att) => att.downloadStatus == 'done'),
          isTrue,
        );
        expect(
          savedAttachments.map((att) => att.id).toSet(),
          equals(seenBlobIds.toSet()),
        );
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
        expect(deletedDirs, contains(savedMessage.id));
        expect(stopwatch.elapsedMilliseconds, lessThan(250));
      },
    );

    testWidgets(
      'failed media upload restores composer and leaves durable pending rows retryable',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-fail-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final files = [
          File('${tempDir.path}/one.jpg')..writeAsStringSync('one'),
          File('${tempDir.path}/two.jpg')..writeAsStringSync('two'),
          File('${tempDir.path}/three.jpg')..writeAsStringSync('three'),
        ];

        final mediaFileManager = FakeMediaFileManager();
        var uploadCount = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            initialAttachments: files,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async {
                  uploadCount++;
                  if (uploadCount == 2) return null;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'Fail media');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 25);

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Fail media',
        );
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(bridge.commandLog, isNot(contains('group:publish')));

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
        expect(pending, hasLength(3));
        expect(
          pending.every((att) => att.downloadStatus == 'upload_pending'),
          isTrue,
        );
      },
    );

    testWidgets(
      'non-durable media send reuses optimistic attachment IDs when uploader returns different IDs',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-non-durable-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');

        String? receivedBlobId;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialAttachments: [file],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async {
                  receivedBlobId = blobId;
                  return MediaAttachment(
                    id: 'server-non-durable-image',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: localFilePath,
                    downloadStatus: 'done',
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'Fallback media');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(receivedBlobId, isNotNull);

        final savedMessage = await msgRepo.getLatestMessage(group.id);
        expect(savedMessage, isNotNull);
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(savedMessage!.id);
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, receivedBlobId);
        expect(savedAttachments.single.downloadStatus, 'done');
      },
    );

    testWidgets(
      'sending a message with zero topic peers keeps the row pending and does not restore the draft',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': true,
              'messageId': 'msg-zero-peers',
              'topicPeers': 0,
            },
          },
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        await tester.enterText(find.byType(TextField), 'No peers online');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(find.text('No peers online'), findsOneWidget);
        expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

        final messages = await msgRepo.getMessagesPage(group.id);
        final saved = messages.firstWhere(
          (message) => message.text == 'No peers online',
        );
        expect(saved.status, 'pending');
        expect(saved.inboxStored, isTrue);
      },
    );

    testWidgets('swipe-to-reply sends quotedMessageId and clears preview', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent',
          text: 'Incoming parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester, count: 20);

      expect(find.byType(SwipeToQuoteBubble), findsOneWidget);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent');
      await tester.pump();

      expect(find.text('Incoming parent'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'Reply to parent');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 20);

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload['quotedMessageId'], 'msg-parent');

      final savedMessages = await msgRepo.getMessagesPage(group.id);
      final sent = savedMessages.firstWhere((m) => m.text == 'Reply to parent');
      expect(sent.quotedMessageId, 'msg-parent');
      expect(find.text('Incoming parent'), findsWidgets);
    });

    testWidgets(
      'incoming message stream upserts without full message/media reloads',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-initial', text: 'Initial'),
        );

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester);

        expect(find.text('Initial'), findsOneWidget);
        expect(msgRepo.getMessagesPageCalls, 1);
        expect(mediaAttachmentRepo.getAttachmentsForMessagesCalls, 1);
        final initialGetMessageCalls = msgRepo.getMessageCalls;
        final initialSingleMessageMediaCalls =
            mediaAttachmentRepo.getAttachmentsForMessageCalls;

        // Add a message to the repo (simulating the listener handler saving it)
        final incomingMsg = makeMessage(
          id: 'msg-incoming',
          text: 'Incoming hello',
          groupId: 'group-1',
        );
        await msgRepo.saveMessage(incomingMsg);

        // Emit on the listener stream with matching groupId
        messageStreamController.add(incomingMsg);
        await pumpFrames(tester, count: 20);

        // The message should now appear
        expect(find.text('Incoming hello'), findsOneWidget);
        expect(msgRepo.getMessagesPageCalls, 1);
        expect(msgRepo.getMessageCalls, greaterThan(initialGetMessageCalls));
        expect(mediaAttachmentRepo.getAttachmentsForMessagesCalls, 1);
        expect(
          mediaAttachmentRepo.getAttachmentsForMessageCalls,
          initialSingleMessageMediaCalls + 1,
        );
      },
    );

    testWidgets('shows loading shell until the initial group page resolves', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      final slowRepo = SlowInitialPageGroupMessageRepository();
      await slowRepo.saveMessage(
        makeMessage(id: 'msg-delayed', text: 'Loaded after delay'),
      );
      msgRepo = slowRepo;

      await tester.pumpWidget(
        buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('group-loading-shell')), findsOneWidget);
      expect(find.text('Loaded after delay'), findsNothing);

      slowRepo.firstPageGate.complete();
      await pumpFrames(tester, count: 20);

      expect(find.byKey(const ValueKey('group-loading-shell')), findsNothing);
      expect(find.text('Loaded after delay'), findsOneWidget);
    });

    testWidgets(
      'incoming message preserves scroll offset when reading older messages',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final start = DateTime.utc(2026, 2, 1, 10);
        for (var index = 0; index < 40; index++) {
          await msgRepo.saveMessage(
            GroupMessage(
              id: 'msg-$index',
              groupId: group.id,
              senderPeerId: 'peer-alice',
              senderUsername: 'Alice',
              text: 'Message $index',
              timestamp: start.add(Duration(minutes: index)),
              createdAt: start.add(Duration(minutes: index)),
            ),
          );
        }

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester, count: 20);

        final listFinder = find.byKey(const ValueKey('group-messages'));
        expect(listFinder, findsOneWidget);

        final controller = tester.widget<ListView>(listFinder).controller!;
        expect(controller.hasClients, isTrue);

        controller.jumpTo(240);
        await pumpFrames(tester, count: 4);

        final offsetBefore = controller.offset;
        expect(offsetBefore, greaterThan(32));

        final incoming = GroupMessage(
          id: 'msg-late',
          groupId: group.id,
          senderPeerId: 'peer-bob',
          senderUsername: 'Bob',
          text: 'Newest while reading history',
          timestamp: start.add(const Duration(minutes: 60)),
          createdAt: start.add(const Duration(minutes: 60)),
        );
        await msgRepo.saveMessage(incoming);

        messageStreamController.add(incoming);
        await pumpFrames(tester, count: 20);

        expect(controller.offset, closeTo(offsetBefore, 1.0));
        expect(msgRepo.getMessagesPageCalls, 1);
        expect(mediaAttachmentRepo.getAttachmentsForMessagesCalls, 1);
      },
    );

    testWidgets(
      'recording ticks update composer without rebuilding header or message list',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-rec-1', text: 'Hello'));
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 100;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final headerFinder = find.byKey(const ValueKey('group-header'));
        final listFinder = find.byKey(const ValueKey('group-messages'));
        final headerElement = tester.element(headerFinder);
        final listElement = tester.element(listFinder);
        final initialPageLoads = msgRepo.getMessagesPageCalls;
        final initialBatchMediaLoads =
            mediaAttachmentRepo.getAttachmentsForMessagesCalls;

        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.mic_rounded)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();

        recorder.emitDuration(const Duration(seconds: 2));
        recorder.emitAmplitude(0.5);
        await tester.pump();

        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('0:02'), findsOneWidget);
        expect(identical(headerElement, tester.element(headerFinder)), isTrue);
        expect(identical(listElement, tester.element(listFinder)), isTrue);
        expect(msgRepo.getMessagesPageCalls, initialPageLoads);
        expect(
          mediaAttachmentRepo.getAttachmentsForMessagesCalls,
          initialBatchMediaLoads,
        );

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets(
      'voice record callbacks switch the group composer into and out of recording',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 100;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final startRecording =
            recordingScreen.onRecordStart! as Future<void> Function();
        await startRecording();
        await tester.pump();

        expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        final stopScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            stopScreen.onRecordStop! as Future<void> Function();
        await stopRecording();
        await tester.pump();

        expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'video processing progress updates composer without rebuilding header or message list',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-video-1', text: 'Hello'),
        );

        final mediaPicker = FakeMediaPicker()
          ..videoResult = XFile('/tmp/group-video.mp4');
        final resultCompleter = Completer<VideoProcessResult>();
        void Function(double progress)? progressCallback;
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async => null,
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double)? onProgress,
              }) async {
                progressCallback = onProgress;
                return resultCompleter.future;
              },
        );

        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            imageProcessor: imageProcessor,
            mediaPicker: mediaPicker,
          ),
        );
        await pumpFrames(tester, count: 20);

        final headerFinder = find.byKey(const ValueKey('group-header'));
        final listFinder = find.byKey(const ValueKey('group-messages'));
        final headerElement = tester.element(headerFinder);
        final listElement = tester.element(listFinder);
        final initialPageLoads = msgRepo.getMessagesPageCalls;
        final initialBatchMediaLoads =
            mediaAttachmentRepo.getAttachmentsForMessagesCalls;

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Record Video'))
            .onTap!();
        await tester.pump();

        expect(progressCallback, isNotNull);

        progressCallback!(35);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('35%'), findsOneWidget);
        expect(identical(headerElement, tester.element(headerFinder)), isTrue);
        expect(identical(listElement, tester.element(listFinder)), isTrue);
        expect(msgRepo.getMessagesPageCalls, initialPageLoads);
        expect(
          mediaAttachmentRepo.getAttachmentsForMessagesCalls,
          initialBatchMediaLoads,
        );

        progressCallback!(80);
        await tester.pump();
        expect(find.text('80%'), findsOneWidget);

        resultCompleter.complete(
          VideoProcessResult(path: '/tmp/processed-group-video.mp4'),
        );
        await tester.pump();
      },
    );

    testWidgets('video processing failure clears composer processing state', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(makeMessage(id: 'msg-video-fail', text: 'Hi'));

      final mediaPicker = FakeMediaPicker()
        ..videoResult = XFile('/tmp/group-video.mp4');
      final resultCompleter = Completer<VideoProcessResult>();
      void Function(double progress)? progressCallback;
      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
        compressVideo:
            ({
              required path,
              required compress,
              void Function(double)? onProgress,
            }) async {
              progressCallback = onProgress;
              return resultCompleter.future;
            },
      );

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          imageProcessor: imageProcessor,
          mediaPicker: mediaPicker,
        ),
      );
      await pumpFrames(tester, count: 20);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Record Video'))
          .onTap!();
      await tester.pump();

      progressCallback!(40);
      await tester.pump();
      expect(find.text('40%'), findsOneWidget);

      resultCompleter.completeError(StateError('group video failed'));
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsNothing);
      expect(find.text('40%'), findsNothing);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Record Video'), findsOneWidget);
    });

    testWidgets('info button navigates to group info', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // Tap the info icon
      final infoButton = find.byIcon(Icons.info_outline);
      expect(infoButton, findsOneWidget);
      await tester.tap(infoButton);
      await pumpFrames(tester, count: 20);

      // GroupInfoScreen should appear (inside GroupInfoWired)
      expect(find.byType(GroupInfoScreen), findsOneWidget);
    });

    testWidgets('non-admin in announcement group cannot write', (tester) async {
      final group = makeAnnouncementGroup(role: GroupRole.member);
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // The compose area should show the read-only message instead of a text field
      expect(
        find.text('Only admins can send messages in this group'),
        findsOneWidget,
      );

      // TextField should not be present (canWrite=false hides it)
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.onAttach, isNull);
      expect(screen.onRecordStart, isNull);
      expect(screen.onRecordStop, isNull);
      expect(screen.onRecordCancel, isNull);
      expect(screen.onQuoteReply, isNull);
    });

    testWidgets(
      'non-admin in announcement group still has no voice stop/cancel callbacks when durable voice deps are enabled',
      (tester) async {
        final group = makeAnnouncementGroup(role: GroupRole.member);
        await groupRepo.saveGroup(group);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            audioRecorderService: FakeAudioRecorderService(),
          ),
        );
        await pumpFrames(tester);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onRecordStart, isNull);
        expect(screen.onRecordStop, isNull);
        expect(screen.onRecordCancel, isNull);
      },
    );

    testWidgets(
      'read-only announcement members cannot keep hidden quote state',
      (tester) async {
        final writableGroup = makeAnnouncementGroup(role: GroupRole.admin);
        await groupRepo.saveGroup(writableGroup);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-parent',
            text: 'Incoming announcement',
            groupId: writableGroup.id,
            isIncoming: true,
          ),
        );

        await tester.pumpWidget(buildWidget(group: writableGroup));
        await pumpFrames(tester, count: 20);

        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onQuoteReply, isNotNull);

        screen.onQuoteReply!.call('msg-parent');
        await tester.pump();
        expect(find.text('Incoming announcement'), findsWidgets);

        final readOnlyGroup = makeAnnouncementGroup(role: GroupRole.member);
        await groupRepo.saveGroup(readOnlyGroup);

        await tester.pumpWidget(buildWidget(group: readOnlyGroup));
        await pumpFrames(tester, count: 20);

        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onQuoteReply, isNull);
        expect(find.byType(SwipeToQuoteBubble), findsNothing);
        expect(find.byType(TextField), findsNothing);

        await tester.pumpWidget(buildWidget(group: writableGroup));
        await pumpFrames(tester, count: 20);

        expect(find.text('Incoming announcement'), findsOneWidget);
        expect(find.text('Replying to'), findsNothing);
      },
    );

    testWidgets(
      'stale writer callbacks cannot bypass read-only announcement mode',
      (tester) async {
        final writableGroup = makeAnnouncementGroup(role: GroupRole.admin);
        await groupRepo.saveGroup(writableGroup);

        final recorder = FakeAudioRecorderService()..fakeDurationMs = 200;
        final mediaFileManager = FakeMediaFileManager();

        await tester.pumpWidget(
          buildWidget(
            group: writableGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final writableScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final staleOnSend =
            writableScreen.onSend as Future<void> Function(String);
        final staleOnAttach = writableScreen.onAttach!;
        final staleOnRecordStart =
            writableScreen.onRecordStart! as Future<void> Function();
        final staleOnRecordStop =
            writableScreen.onRecordStop! as Future<void> Function();

        await staleOnRecordStart();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        final readOnlyGroup = makeAnnouncementGroup(role: GroupRole.member);
        await groupRepo.saveGroup(readOnlyGroup);

        await tester.pumpWidget(
          buildWidget(
            group: readOnlyGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        staleOnAttach();
        await tester.pump(const Duration(milliseconds: 300));
        await staleOnRecordStop();
        await pumpFrames(tester, count: 5);
        await staleOnSend('should-never-send');
        await pumpFrames(tester, count: 20);

        expect(find.text('Media Library'), findsNothing);
        expect(find.byIcon(Icons.stop_rounded), findsNothing);
        expect(recorder.startCallCount, 1);
        expect(recorder.stopCallCount, 0);
        expect(bridge.commandLog, isNot(contains('bg:begin')));
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));

        final savedMessages = await msgRepo.getMessagesPage(readOnlyGroup.id);
        expect(
          savedMessages.where((message) => message.text == 'should-never-send'),
          isEmpty,
        );
      },
    );

    testWidgets('sets tracker active on init', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final tracker = ActiveConversationTracker();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupMessageListener: FakeGroupMessageListener(
              messageStreamController.stream,
            ),
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            groupConversationTracker: tracker,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(tracker.isViewing('group:${group.id}'), isTrue);
    });

    testWidgets('clears tracker on dispose', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final tracker = ActiveConversationTracker();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupMessageListener: FakeGroupMessageListener(
              messageStreamController.stream,
            ),
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            groupConversationTracker: tracker,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(tracker.isViewing('group:${group.id}'), isTrue);

      // Replace the widget to trigger dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await pumpFrames(tester);

      expect(tracker.isViewing('group:${group.id}'), isFalse);
    });

    testWidgets('accepts empty initialAttachments without error', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: CountingMediaAttachmentRepository(),
          initialAttachments: [],
        ),
      );
      await pumpFrames(tester);

      expect(find.byType(GroupConversationWired), findsOneWidget);
      // No AttachmentPreviewStrip when list is empty
      expect(find.byType(AttachmentPreviewStrip), findsNothing);
    });

    testWidgets(
      'sent text message appears immediately before bridge responds',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        // Use a gated bridge that blocks group:publish until we release it
        final gatedBridge = _GatedPublishBridge();
        bridge = gatedBridge;

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        // Type and send
        await tester.enterText(find.byType(TextField), 'Optimistic hello');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        // Pump a few frames — bridge is still gated
        await pumpFrames(tester, count: 5);

        // Message should be visible optimistically
        expect(find.text('Optimistic hello'), findsOneWidget);

        // Status should be 'sending' (single check icon)
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);

        // Release the bridge
        gatedBridge.publishGate.complete();
        await pumpFrames(tester, count: 20);

        // Message still visible, status updated to 'sent'
        expect(find.text('Optimistic hello'), findsOneWidget);
      },
    );

    testWidgets('optimistic message is saved to DB before network ops', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      final gatedBridge = _GatedPublishBridge();
      bridge = gatedBridge;

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField), 'DB before net');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 5);

      // Message should be in the DB with status 'sending'
      final messages = await msgRepo.getMessagesPage(group.id);
      expect(messages.length, 1);
      expect(messages.first.text, 'DB before net');
      expect(messages.first.status, 'sending');

      // Bridge hasn't been called for publish yet? Actually it was called
      // but is blocked on the completer. The key point: DB was saved first.

      gatedBridge.publishGate.complete();
      await pumpFrames(tester, count: 20);

      // After publish completes, status should be 'sent'
      final updated = await msgRepo.getMessagesPage(group.id);
      expect(updated.first.status, 'sent');
    });

    testWidgets('failed publish shows message with failed status', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      // Bridge returns failure for publish
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
        },
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField), 'Will fail');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 20);

      // Message should still be visible and the composer should keep the draft.
      expect(find.text('Will fail'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Will fail',
      );

      // Status should be 'failed' (error icon)
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('upload failure restores quote draft and attachments', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent-upload',
          text: 'Upload parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );

      final tempDir = Directory.systemTemp.createTempSync(
        'group_retry_upload_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/retry.jpg')
        ..writeAsStringSync('image');

      await tester.pumpWidget(
        buildWidget(
          group: group,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
              }) async => null,
          initialAttachments: [attachment],
        ),
      );
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent-upload');
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Retry upload');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 10);

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Upload parent'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Retry upload',
      );
    });

    testWidgets('publish failure restores quote draft and attachments', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent-publish',
          text: 'Publish parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );

      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
        },
      );

      final tempDir = Directory.systemTemp.createTempSync(
        'group_retry_publish_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/retry.jpg')
        ..writeAsStringSync('image');

      await tester.pumpWidget(
        buildWidget(
          group: group,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
              }) async => MediaAttachment(
                id: 'uploaded-group-1',
                messageId: '',
                mime: mime,
                size: 1,
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              ),
          initialAttachments: [attachment],
        ),
      );
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent-publish');
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Retry publish');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 20);

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Publish parent'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Retry publish',
      );
    });

    // -----------------------------------------------------------------------
    // Voice message tests
    //
    // NOTE: uploadMedia() uses real File I/O (File.length()) which does not
    // complete inside Flutter's FakeAsync zone. Full upload→publish flow is
    // tested at the use case level in send_group_message_use_case_test.dart.
    // These tests verify the optimistic UI pattern and quote restoration
    // behavior added in _onRecordStop.
    // -----------------------------------------------------------------------

    testWidgets(
      'voice send path stays hidden unless both durable media dependencies exist',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final recorder = FakeAudioRecorderService();
        final uiGateDir = Directory.systemTemp.createTempSync(
          'group-voice-ui-gate-',
        );
        addTearDown(() {
          if (uiGateDir.existsSync()) {
            uiGateDir.deleteSync(recursive: true);
          }
        });

        await tester.pumpWidget(
          buildWidget(
            group: group,
            audioRecorderService: recorder,
            mediaRepo: mediaAttachmentRepo,
          ),
        );
        await pumpFrames(tester, count: 10);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onRecordStart, isNull);
        expect(screen.onRecordStop, isNull);
        expect(find.byIcon(Icons.mic_rounded), findsNothing);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            audioRecorderService: recorder,
            mediaFileManager: TrackingDurableMediaFileManager(uiGateDir),
          ),
        );
        await pumpFrames(tester, count: 10);

        final screenWithoutRepo = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screenWithoutRepo.onRecordStart, isNull);
        expect(screenWithoutRepo.onRecordStop, isNull);
        expect(find.byIcon(Icons.mic_rounded), findsNothing);
      },
    );

    testWidgets(
      'voice stop pre-persists a durable pending attachment and threads a stable blob ID',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-durable-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');

        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3200
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        String? receivedBlobId;
        String? receivedLocalPath;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async {
                  receivedBlobId = blobId;
                  receivedLocalPath = localFilePath;
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return MediaAttachment(
                    id: 'server-voice-success',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId!,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        recorder.emitAmplitude(0.15);
        recorder.emitAmplitude(0.55);
        recorder.emitAmplitude(0.25);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await pumpFrames(tester, count: 5);

        expect(mediaFileManager.copyCalls, 1);
        expect(receivedBlobId, isNotNull);
        expect(
          receivedLocalPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
        expect(pending, hasLength(1));
        expect(pending.single.id, receivedBlobId);
        expect(pending.single.downloadStatus, 'upload_pending');
        expect(pending.single.localPath, isNotNull);
        expect(pending.single.localPath, startsWith('pending_uploads/'));

        final refreshedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final optimisticMessage = refreshedScreen.messages.singleWhere(
          (message) => message.status == 'sending' && message.text.isEmpty,
        );
        final optimisticAttachment =
            refreshedScreen.mediaMap[optimisticMessage.id]!.single;
        expect(optimisticAttachment.id, receivedBlobId);
        expect(optimisticAttachment.localPath, isNotNull);
        expect(
          optimisticAttachment.localPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);
      },
    );

    testWidgets(
      'voice upload failure keeps upload_pending retry data and restores the quote',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-parent-voice-upload',
            text: 'Voice upload parent',
            groupId: group.id,
            isIncoming: true,
          ),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-upload-fail-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');

        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 2800
          ..fakeSizeBytes = 44100
          ..fakeOutputPath = tempVoice.path;
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        String? receivedBlobId;
        String? receivedLocalPath;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async {
                  receivedBlobId = blobId;
                  receivedLocalPath = localFilePath;
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return null;
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        screen.onQuoteReply!.call('msg-parent-voice-upload');
        await tester.pump();
        expect(find.text('Replying to'), findsOneWidget);

        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );
        recorder.emitAmplitude(0.15);
        recorder.emitAmplitude(0.55);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await pumpFrames(tester, count: 5);

        expect(mediaFileManager.copyCalls, 1);
        expect(receivedBlobId, isNotNull);
        expect(
          receivedLocalPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        final pendingBeforeFail = await mediaAttachmentRepo
            .getUploadPendingAttachments();
        expect(pendingBeforeFail, hasLength(1));
        expect(pendingBeforeFail.single.id, receivedBlobId);
        expect(pendingBeforeFail.single.downloadStatus, 'upload_pending');
        expect(pendingBeforeFail.single.durationMs, 2800);
        expect(pendingBeforeFail.single.waveform, isNotNull);
        expect(pendingBeforeFail.single.waveform, isNotEmpty);

        final refreshedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final optimisticMessage = refreshedScreen.messages.singleWhere(
          (message) => message.status == 'sending' && message.text.isEmpty,
        );
        final optimisticAttachment =
            refreshedScreen.mediaMap[optimisticMessage.id]!.single;
        expect(optimisticAttachment.id, receivedBlobId);
        expect(
          optimisticAttachment.localPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        final failedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final failedMessage = failedScreen.messages.singleWhere(
          (message) => message.status == 'failed' && message.text.isEmpty,
        );
        expect(failedMessage.quotedMessageId, 'msg-parent-voice-upload');
        expect(find.text('Replying to'), findsOneWidget);

        final pendingAfterFail = await mediaAttachmentRepo
            .getUploadPendingAttachments();
        expect(pendingAfterFail, hasLength(1));
        expect(pendingAfterFail.single.id, receivedBlobId);
        expect(pendingAfterFail.single.downloadStatus, 'upload_pending');
      },
    );

    testWidgets(
      'successful voice send uses the durable copy, cleans pending uploads, and survives temp deletion',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-success-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');

        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3100
          ..fakeSizeBytes = 46000
          ..fakeOutputPath = tempVoice.path;
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        String? receivedBlobId;
        String? receivedLocalPath;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async {
                  receivedBlobId = blobId;
                  receivedLocalPath = localFilePath;
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  expect(
                    File(tempVoice.path).existsSync(),
                    isFalse,
                    reason:
                        'temp source file should no longer matter after durable copy',
                  );
                  await uploadGate.future;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );
        recorder.emitAmplitude(0.1);
        recorder.emitAmplitude(0.4);
        recorder.emitAmplitude(0.2);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await pumpFrames(tester, count: 5);

        expect(mediaFileManager.copyCalls, 1);
        expect(receivedBlobId, isNotNull);
        expect(
          receivedLocalPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
        expect(pending, hasLength(1));
        expect(pending.single.id, receivedBlobId);
        expect(pending.single.localPath, startsWith('pending_uploads/'));

        final optimisticScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final optimisticMessage = optimisticScreen.messages.singleWhere(
          (message) => message.status == 'sending' && message.text.isEmpty,
        );
        final optimisticAttachment =
            optimisticScreen.mediaMap[optimisticMessage.id]!.single;
        expect(optimisticAttachment.id, receivedBlobId);
        expect(
          optimisticAttachment.localPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        final savedMessage = await msgRepo.getLatestMessage(group.id);
        expect(savedMessage, isNotNull);
        expect(
          mediaFileManager.deletedPendingUploadDirs,
          contains(savedMessage!.id),
        );
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(savedMessage.id);
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, receivedBlobId);
        expect(savedAttachments.single.downloadStatus, 'done');
        expect(savedAttachments.single.localPath, startsWith('media/'));
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
      },
    );

    testWidgets(
      'voice record stop keeps the optimistic voice row caller-local until upload completes',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-caller-local-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async {
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return MediaAttachment(
                    id: 'uploaded-voice-gated',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: localFilePath,
                    downloadStatus: 'done',
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pump();

        expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await pumpFrames(tester, count: 10);

        // The durable parent message row is now persisted before upload so
        // resume-time recovery can resolve it from the attachment row.
        final inFlightMessages = await msgRepo.getMessagesPage(group.id);
        expect(inFlightMessages, hasLength(1));
        expect(inFlightMessages.single.status, 'sending');

        await tester.runAsync(() async {
          uploadGate.complete();
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        final messages = await msgRepo.getMessagesPage(group.id);
        expect(messages.length, 1);
        expect(messages.first.status, 'sent');
        expect(messages.first.text, '');
        expect(messages.first.isIncoming, false);
        expect(messages.first.senderPeerId, testIdentity.peerId);
      },
    );

    testWidgets(
      'voice send with zero topic peers leaves the final row pending',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-zero-peers-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);

        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;

        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': true,
              'messageId': 'msg-voice-zero-peers',
              'topicPeers': 0,
            },
          },
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async => MediaAttachment(
                  id: 'uploaded-voice-zero-peers',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  durationMs: durationMs,
                  waveform: waveform,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                ),
          ),
        );
        await pumpFrames(tester, count: 20);

        final beforeCount = (await msgRepo.getMessagesPage(group.id)).length;

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        final messages = await msgRepo.getMessagesPage(group.id);
        expect(messages, hasLength(beforeCount + 1));
        final saved = await msgRepo.getLatestMessage(group.id);
        expect(saved, isNotNull);
        expect(saved!.isIncoming, isFalse);
        expect(saved.text, '');
        expect(saved.status, 'pending');
        expect(saved.quotedMessageId, isNull);
        expect(saved.inboxStored, isTrue);
        expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'voice group-not-found rejection does not leave a persisted outgoing row',
      (tester) async {
        final missingGroup = makeChatGroup();
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-missing-group-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;

        await tester.pumpWidget(
          buildWidget(
            group: missingGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async => MediaAttachment(
                  id: 'uploaded-voice-missing-group',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  durationMs: durationMs,
                  waveform: waveform,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                ),
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 10);

        expect(await msgRepo.getMessagesPage(missingGroup.id), isEmpty);
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets(
      'voice stop cleanup still runs after unmount when group lookup resolves to not found',
      (tester) async {
        final group = makeChatGroup();
        final delayedGroupRepo = _DelayedNotFoundGroupRepository(
          const Duration(milliseconds: 500),
        );
        groupRepo = delayedGroupRepo;
        await delayedGroupRepo.saveGroup(group);
        await delayedGroupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-ally',
            username: 'Ally',
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-unmounted-cleanup-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                }) async => MediaAttachment(
                  id: blobId!,
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: mediaFileManager?.relativePathForAttachment(
                    contactPeerId: group.id,
                    blobId: blobId,
                    mime: mime,
                  ),
                  downloadStatus: 'done',
                  durationMs: durationMs,
                  waveform: waveform,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                ),
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });

        await pumpFrames(tester, count: 5);

        final inFlightMessage = await msgRepo.getLatestMessage(group.id);
        expect(inFlightMessage, isNotNull);
        final messageId = inFlightMessage!.id;

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 10);

        expect(mediaFileManager.deletedPendingUploadDirs, contains(messageId));
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(messageId),
          isEmpty,
        );
        expect(await msgRepo.getMessage(messageId), isNull);
      },
    );

    testWidgets('voice upload failure restores the quoted reply target', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent-voice-upload',
          text: 'Voice upload parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'group-voice-upload-reply-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
        ..writeAsStringSync('voice');
      final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 3000
        ..fakeSizeBytes = 48000
        ..fakeOutputPath = tempVoice.path;

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          audioRecorderService: recorder,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
              }) async => null,
        ),
      );
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent-voice-upload');
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);

      final startRecording = screen.onRecordStart! as Future<void> Function();
      await startRecording();
      await pumpUntil(
        tester,
        () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
      );

      final recordingScreen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      final stopRecording =
          recordingScreen.onRecordStop! as Future<void> Function();
      late Future<void> stopFuture;
      await tester.runAsync(() async {
        stopFuture = stopRecording();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.runAsync(() async {
        await stopFuture;
      });
      await pumpFrames(tester, count: 10);

      final messages = await msgRepo.getMessagesPage(group.id);
      final failed = messages.firstWhere(
        (message) => message.id != 'msg-parent-voice-upload',
      );
      expect(failed.status, 'failed');
      expect(failed.quotedMessageId, 'msg-parent-voice-upload');
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Voice upload parent'), findsWidgets);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('voice publish failure restores the quoted reply target', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent-voice-publish',
          text: 'Voice publish parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'group-voice-publish-reply-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
        ..writeAsStringSync('voice');
      final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 3000
        ..fakeSizeBytes = 48000
        ..fakeOutputPath = tempVoice.path;
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
        },
      );

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          audioRecorderService: recorder,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
              }) async => MediaAttachment(
                id: 'uploaded-voice-1',
                messageId: '',
                mime: mime,
                size: 1,
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                durationMs: durationMs,
                waveform: waveform,
                createdAt: DateTime.now().toUtc().toIso8601String(),
              ),
        ),
      );
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent-voice-publish');
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);

      final startRecording = screen.onRecordStart! as Future<void> Function();
      await startRecording();
      await pumpUntil(
        tester,
        () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
      );

      final recordingScreen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      final stopRecording =
          recordingScreen.onRecordStop! as Future<void> Function();
      late Future<void> stopFuture;
      await tester.runAsync(() async {
        stopFuture = stopRecording();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.runAsync(() async {
        await stopFuture;
      });
      await pumpFrames(tester, count: 10);

      final messages = await msgRepo.getMessagesPage(group.id);
      final failed = messages.firstWhere(
        (message) => message.id != 'msg-parent-voice-publish',
      );

      expect(failed.status, 'failed');
      expect(failed.quotedMessageId, 'msg-parent-voice-publish');
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Voice publish parent'), findsWidgets);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    // Full upload→publish e2e is tested at the use case level:
    // - send_group_message_use_case_test: 'sends message with empty text and media'
    // - Go bridge_test: TestGroupPublish_MediaOnly_AcceptsEmptyText
    // (The wired-level e2e test is not feasible because uploadMedia's File I/O
    // does not resolve in Flutter's FakeAsync zone.)

    testWidgets('announcement admin sees mic button for voice recording', (
      tester,
    ) async {
      final group = makeAnnouncementGroup(role: GroupRole.admin);
      await groupRepo.saveGroup(group);
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 3000
        ..fakeSizeBytes = 48000;

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          mediaFileManager: FakeMediaFileManager(),
          audioRecorderService: recorder,
        ),
      );
      await pumpFrames(tester, count: 20);

      // Mic button should be visible for admin in announcement group
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();

      // Recording overlay should appear
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Reaction integration tests
    // -----------------------------------------------------------------------

    testWidgets(
      'loads persisted reactions on init when reactionRepo is provided',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-1',
            messageId: 'msg-1',
            emoji: '\u{1F44D}',
            senderPeerId: 'peer-alice',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, reactionRepo: reactionRepo),
        );
        await pumpFrames(tester);

        // The reaction emoji should be visible in the UI
        expect(find.text('\u{1F44D}'), findsOneWidget);
      },
    );

    testWidgets('reaction UI is disabled when reactionRepo is null', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // Long-press a message — should NOT show reaction bar
      await tester.longPress(find.text('Hello'));
      await pumpFrames(tester);

      // No reaction bar emojis visible (the preset emojis like thumbs up etc.)
      expect(find.text('\u{1F44D}'), findsNothing);
    });

    testWidgets('incoming reaction change stream updates UI state', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

      final reactionRepo = FakeReactionRepository();
      final reactionStreamController =
          StreamController<ReactionChange>.broadcast();

      await tester.pumpWidget(
        buildWidget(
          group: group,
          reactionRepo: reactionRepo,
          reactionStreamController: reactionStreamController,
        ),
      );
      await pumpFrames(tester);

      // No reactions initially
      expect(find.text('\u{1F44D}'), findsNothing);

      // Emit an incoming reaction change
      reactionStreamController.add(
        ReactionChange.upsert(
          MessageReaction(
            id: 'rxn-incoming',
            messageId: 'msg-1',
            emoji: '\u{1F44D}',
            senderPeerId: 'peer-bob',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ),
      );
      await pumpFrames(tester);

      // Reaction should now be visible
      expect(find.text('\u{1F44D}'), findsOneWidget);

      // Clean up
      await reactionStreamController.close();
    });
  });
}
