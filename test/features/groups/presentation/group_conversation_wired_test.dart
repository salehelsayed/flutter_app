import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_media_picker.dart';
import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

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
const _md012MediaKey = 'md012-media-key';
const _md012MediaNonce = 'md012-media-nonce';

List<int> _md012EncryptedBytes(
  List<int> plaintext, {
  String key = _md012MediaKey,
  String nonce = _md012MediaNonce,
}) {
  return [...'cipher:$key:$nonce:'.codeUnits, ...plaintext.reversed];
}

String _md012HashBytes(List<int> bytes) => sha256.convert(bytes).toString();

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
  final Stream<String>? _externalRemovedStream;

  FakeGroupMessageListener(
    this._externalStream, {
    Stream<ReactionChange>? reactionStream,
    Stream<String>? removedStream,
  }) : _externalReactionStream = reactionStream,
       _externalRemovedStream = removedStream,
       super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;

  @override
  Stream<ReactionChange> get groupReactionChangeStream =>
      _externalReactionStream ?? super.groupReactionChangeStream;

  @override
  Stream<String> get groupRemovedStream =>
      _externalRemovedStream ?? super.groupRemovedStream;
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

class _DownloadRepairBridge extends FakeBridge {
  _DownloadRepairBridge({
    required this.downloadedBytes,
    this.mime = 'image/png',
  });

  List<int> downloadedBytes;
  String mime;

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
      await file.writeAsBytes(downloadedBytes, flush: true);
      return jsonEncode({
        'ok': true,
        'id': payload['id'],
        'mime': mime,
        'size': downloadedBytes.length,
      });
    }

    if (cmd == 'blob:decrypt') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final filePath = payload['filePath'] as String;
      final keyBase64 = payload['keyBase64'] as String;
      final nonce = payload['nonce'] as String;
      final encrypted = await File(filePath).readAsBytes();
      final prefix = 'cipher:$keyBase64:$nonce:'.codeUnits;
      final hasPrefix =
          encrypted.length >= prefix.length &&
          List.generate(
            prefix.length,
            (index) => encrypted[index] == prefix[index],
          ).every((matches) => matches);
      if (!hasPrefix) {
        return jsonEncode({'ok': false, 'errorMessage': 'decrypt failed'});
      }
      final decryptedPath = '$filePath.dec';
      await File(decryptedPath).writeAsBytes(
        encrypted.skip(prefix.length).toList().reversed.toList(),
        flush: true,
      );
      return jsonEncode({'ok': true, 'decryptedPath': decryptedPath});
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
  String status = 'sent',
  List<MediaAttachment> media = const [],
  String? wireEnvelope,
  String? inboxRetryPayload,
  DateTime? timestamp,
}) => GroupMessage(
  id: id,
  groupId: groupId,
  senderPeerId: senderPeerId,
  senderUsername: senderUsername,
  text: text,
  quotedMessageId: quotedMessageId,
  timestamp: timestamp ?? DateTime.now().toUtc(),
  status: status,
  isIncoming: isIncoming,
  createdAt: timestamp ?? DateTime.now().toUtc(),
  media: media,
  wireEnvelope: wireEnvelope,
  inboxRetryPayload: inboxRetryPayload,
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

Future<void> pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  int maxPumps = 40,
}) async {
  var pumps = 0;
  while (!(await condition()) && pumps < maxPumps) {
    await tester.pump(const Duration(milliseconds: 50));
    pumps++;
  }
}

class StartedScreenSend {
  const StartedScreenSend(this.future);

  final Future<void> future;
}

Future<StartedScreenSend> startScreenSend(
  WidgetTester tester,
  String text, {
  Duration delay = const Duration(milliseconds: 200),
}) async {
  final screen = tester.widget<GroupConversationScreen>(
    find.byType(GroupConversationScreen),
  );
  final send = screen.onSend as Future<void> Function(String);
  late Future<void> sendFuture;
  await tester.runAsync(() async {
    sendFuture = send(text);
    await Future<void>.delayed(delay);
  });
  await tester.pump();
  return StartedScreenSend(sendFuture);
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
    late FakeUploadWakeLockDriver wakeLockDriver;

    setUp(() async {
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
      wakeLockDriver = FakeUploadWakeLockDriver();
      UploadWakeLockController.debugReset(driver: wakeLockDriver);
      groupRecoveryGate.resetForTest();
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'test-group-key-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );
    });

    tearDown(() {
      messageStreamController.close();
      UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
      groupRecoveryGate.resetForTest();
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
      List<PendingComposerMedia>? initialPendingMedia,
      String? initialText,
      String? initialHighlightedMessageId,
      ImageQualityPreference qualityPreference =
          ImageQualityPreference.compressed,
      ImageQualityPreference videoQualityPreference =
          ImageQualityPreference.compressed,
      int maxAttachmentBudgetBytes = kGeneralMediaAttachmentBudgetBytes,
      ReactionRepository? reactionRepo,
      FakeGroupReactionReplayOutboxRepository? reactionReplayOutboxRepo,
      StreamController<ReactionChange>? reactionStreamController,
      StreamController<String>? removedStreamController,
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
            removedStream: removedStreamController?.stream,
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
          qualityPreference: qualityPreference,
          videoQualityPreference: videoQualityPreference,
          uploadMediaFn: uploadMediaFn ?? uploadMedia,
          initialAttachments: initialAttachments,
          initialPendingMedia: initialPendingMedia,
          initialText: initialText,
          initialHighlightedMessageId: initialHighlightedMessageId,
          maxAttachmentBudgetBytes: maxAttachmentBudgetBytes,
          reactionRepo: reactionRepo,
          groupReactionReplayOutboxRepository: reactionReplayOutboxRepo,
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

    testWidgets('shows security status from key epoch and member safety', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: group.id,
          keyGeneration: 2,
          encryptedKey: 'test-group-key-2',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob-current',
          mlKemPublicKey: 'mlkem-bob-current',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await contactRepo.addContact(
        ContactModel(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          rendezvous: '/ip4/127.0.0.1/tcp/4001',
          username: 'Alice',
          signature: 'sig-alice',
          scannedAt: DateTime.utc(2026, 5, 1).toIso8601String(),
          mlKemPublicKey: 'mlkem-alice',
        ),
      );
      await contactRepo.addContact(
        ContactModel(
          peerId: 'peer-bob',
          publicKey: 'pk-bob-saved',
          rendezvous: '/ip4/127.0.0.1/tcp/4001',
          username: 'Bob',
          signature: 'sig-bob',
          scannedAt: DateTime.utc(2026, 5, 1).toIso8601String(),
          mlKemPublicKey: 'mlkem-bob-saved',
        ),
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('group-conversation-security-strip'))
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text('Encrypted - key epoch 2'), findsOneWidget);
      expect(find.text('1 member needs verification review'), findsOneWidget);
      expect(find.textContaining('test-group-key-2'), findsNothing);
    });

    testWidgets('counts own member as verified without saved contact', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: testIdentity.peerId,
          username: testIdentity.username,
          role: MemberRole.admin,
          publicKey: testIdentity.publicKey,
          mlKemPublicKey: testIdentity.mlKemPublicKey,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          mlKemPublicKey: 'mlkem-bob',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await contactRepo.addContact(
        ContactModel(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          rendezvous: '/ip4/127.0.0.1/tcp/4001',
          username: 'Alice',
          signature: 'sig-alice',
          scannedAt: DateTime.utc(2026, 5, 1).toIso8601String(),
          mlKemPublicKey: 'mlkem-alice',
        ),
      );
      await contactRepo.addContact(
        ContactModel(
          peerId: 'peer-bob',
          publicKey: 'pk-bob',
          rendezvous: '/ip4/127.0.0.1/tcp/4002',
          username: 'Bob',
          signature: 'sig-bob',
          scannedAt: DateTime.utc(2026, 5, 1).toIso8601String(),
          mlKemPublicKey: 'mlkem-bob',
        ),
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('group-conversation-security-strip'))
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text('Encrypted - key epoch 1'), findsOneWidget);
      expect(find.text('All 3 members verified'), findsOneWidget);
      expect(find.text('2 of 3 members verified'), findsNothing);
      expect(
        find.textContaining('not verified from saved contacts'),
        findsNothing,
      );
    });

    testWidgets(
      'hydrated group initialPendingMedia uses budget bytes instead of file size',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_hydrated_budget_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final smallFile = File('${tempDir.path}/hydrated.jpg')
          ..writeAsStringSync('12');

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialPendingMedia: [
              PendingComposerMedia(file: smallFile, budgetBytes: 12),
            ],
            maxAttachmentBudgetBytes: 10,
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.text('Media Too Large'), findsOneWidget);
      },
    );

    testWidgets(
      'oversized gallery attachment compresses under budget and stages the processed file',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_large_attachment_compress_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final oversizedFile = File('${tempDir.path}/oversized.jpg')
          ..writeAsStringSync('123456789012');
        final compressedFile = File('${tempDir.path}/compressed.jpg')
          ..writeAsStringSync('1234');

        final mediaPicker = FakeMediaPicker()
          ..multipleMediaResult = [XFile(oversizedFile.path)];
        final qualityCalls = <int>[];
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                qualityCalls.add(quality);
                if (quality == 100) {
                  return XFile(oversizedFile.path);
                }
                return XFile(compressedFile.path);
              },
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double progress)? onProgress,
              }) async => null,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            imageProcessor: imageProcessor,
            mediaPicker: mediaPicker,
            qualityPreference: ImageQualityPreference.original,
            maxAttachmentBudgetBytes: 10,
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(
          tester,
          () => find.text('Media Too Large').evaluate().isNotEmpty,
        );

        expect(find.text('Media Too Large'), findsOneWidget);
        expect(find.textContaining('12 B'), findsOneWidget);
        expect(find.textContaining('10 B limit'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Compress'));
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen
              .composerStateListenable!
              .value
              .pendingAttachments
              .isNotEmpty;
        });
        await pumpFrames(tester, count: 5);

        expect(qualityCalls, equals([100, 85]));
        expect(find.text('Media Too Large'), findsNothing);
        expect(
          find.text('The media is too large even after compression.'),
          findsNothing,
        );

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.composerStateListenable!.value.pendingAttachments,
          hasLength(1),
        );
        expect(
          screen.composerStateListenable!.value.pendingAttachments.single.path,
          compressedFile.path,
        );
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      },
    );

    testWidgets(
      'oversized gallery attachment that remains over budget after compression leaves no pending state',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_large_attachment_reject_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final oversizedFile = File('${tempDir.path}/oversized.jpg')
          ..writeAsStringSync('123456789012');
        final stillOversizedFile = File('${tempDir.path}/still-oversized.jpg')
          ..writeAsStringSync('12345678901');

        final mediaPicker = FakeMediaPicker()
          ..multipleMediaResult = [XFile(oversizedFile.path)];
        final qualityCalls = <int>[];
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                qualityCalls.add(quality);
                if (quality == 100) {
                  return XFile(oversizedFile.path);
                }
                return XFile(stillOversizedFile.path);
              },
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double progress)? onProgress,
              }) async => null,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            imageProcessor: imageProcessor,
            mediaPicker: mediaPicker,
            qualityPreference: ImageQualityPreference.original,
            maxAttachmentBudgetBytes: 10,
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(
          tester,
          () => find.text('Media Too Large').evaluate().isNotEmpty,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Compress'));
        await pumpFrames(tester, count: 20);

        expect(qualityCalls, equals([100, 85]));
        expect(
          find.text('The media is too large even after compression.'),
          findsOneWidget,
        );
        expect(find.byType(AttachmentPreviewStrip), findsNothing);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.composerStateListenable!.value.pendingAttachments,
          isEmpty,
        );
      },
    );

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
      'blocks a second text send while the first local send is in flight and releases after success',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final gatedBridge = _GatedPublishBridge();
        bridge = gatedBridge;

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'First send');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(
          tester,
          () => tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .isSending,
        );
        await pumpFrames(tester, count: 5);

        expect(find.text('First send'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Second send');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 5);

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Second send',
        );
        expect(find.text('Second send'), findsOneWidget);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          0,
        );

        gatedBridge.publishGate.complete();
        await pumpFrames(tester, count: 20);

        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          2,
        );
      },
    );

    testWidgets(
      'voice send blocks text send while the voice pipeline is active and releases after failure',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-send-guard-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 1500;
        final voiceFile = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        recorder.fakeOutputPath = voiceFile.path;
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final uploadStarted = Completer<void>();
        final uploadGate = Completer<void>();

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
                  return null;
                },
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
          () =>
              tester
                  .widget<GroupConversationScreen>(
                    find.byType(GroupConversationScreen),
                  )
                  .recordingState ==
              VoiceRecordingState.recording,
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
          await uploadStarted.future.timeout(const Duration(seconds: 30));
        });
        expect(uploadStarted.isCompleted, isTrue);
        await pumpFrames(tester, count: 5);
        await pumpUntil(
          tester,
          () => tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .isSending,
        );
        expect(uploadStarted.isCompleted, isTrue);
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .isSending,
          isTrue,
        );
        await pumpFrames(tester, count: 5);

        await tester.enterText(find.byType(TextField), 'Blocked text send');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 5);

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Blocked text send',
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
      },
    );

    testWidgets(
      'media uploads pre-persist upload_pending rows and start in parallel from durable copies',
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

        final testMediaFileManager = FakeMediaFileManager();
        final uploadStarts = <DateTime>[];
        final seenBlobIds = <String>[];
        final pendingSeenBeforeUpload = <bool>[];
        final uploadRelease = Completer<void>();
        addTearDown(() {
          if (!uploadRelease.isCompleted) {
            uploadRelease.complete();
          }
          mediaAttachmentRepo.onSaveAttachment = null;
        });

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: testMediaFileManager,
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
                          att.size > 0 &&
                          (att.localPath?.startsWith('pending_uploads/') ??
                              false),
                    ),
                    isTrue,
                  );
                  await uploadRelease.future;
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
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Durable media');
        await pumpUntil(tester, () => uploadStarts.length == 3, maxPumps: 40);

        expect(uploadStarts, hasLength(3));
        expect(
          uploadStarts.last.difference(uploadStarts.first).inMilliseconds,
          lessThan(80),
        );
        expect(pendingSeenBeforeUpload.every((seen) => seen), isTrue);
        expect(seenBlobIds.toSet(), hasLength(3));

        uploadRelease.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 5);
      },
    );

    testWidgets(
      'ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-parent-row-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');
        final testMediaFileManager = FakeMediaFileManager();
        final deletedDirs = <String>[];
        testMediaFileManager.onDeletePendingUploadDir = deletedDirs.add;
        final uploadStarted = Completer<void>();
        final uploadGate = Completer<void>();
        String? receivedBlobId;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: testMediaFileManager,
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
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return MediaAttachment(
                    id: 'server-media-parent-row',
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
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final sendMessage = screen.onSend as Future<void> Function(String);
        late Future<void> sendFuture;
        await tester.runAsync(() async {
          sendFuture = sendMessage('Durable parent row');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await pumpUntil(tester, () => uploadStarted.isCompleted);
        await pumpFrames(tester, count: 5);

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
        expect(pending, hasLength(1));
        final messageId = pending.single.messageId;
        expect(pending.single.id, receivedBlobId);
        expect(pending.single.downloadStatus, 'upload_pending');
        expect(pending.single.localPath, startsWith('pending_uploads/'));

        final persistedBeforeUpload = await msgRepo.getMessage(messageId);
        expect(persistedBeforeUpload, isNotNull);
        expect(persistedBeforeUpload!.text, 'Durable parent row');
        expect(persistedBeforeUpload.status, 'sending');

        await tester.runAsync(() async {
          uploadGate.complete();
          await sendFuture;
        });
        await pumpFrames(tester, count: 20);

        final persistedAfterSend = await msgRepo.getMessage(messageId);
        expect(persistedAfterSend, isNotNull);
        expect(persistedAfterSend!.status, 'sent');
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(messageId);
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, receivedBlobId);
        expect(savedAttachments.single.downloadStatus, 'done');
        expect(deletedDirs, contains(messageId));
      },
    );

    testWidgets(
      'failed media upload leaves durable pending rows retryable and avoids group publish',
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

        final testMediaFileManager = FakeMediaFileManager();
        var uploadCount = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: testMediaFileManager,
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
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Fail media');
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 5);
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
      'ordinary media upload failure persists failed parent state and restores composer and quote',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-parent-media-upload',
            text: 'Media upload parent',
            groupId: group.id,
            isIncoming: true,
          ),
        );

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-upload-parent-fail-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');
        final mediaFileManager = FakeMediaFileManager();
        final uploadStarted = Completer<void>();
        final uploadGate = Completer<void>();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
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
        screen.onQuoteReply!.call('msg-parent-media-upload');
        await tester.pump();
        expect(find.text('Replying to'), findsOneWidget);

        final sendFuture = await startScreenSend(
          tester,
          'Fail media parent row',
        );
        await pumpUntil(tester, () => uploadStarted.isCompleted);
        await pumpFrames(tester, count: 5);

        final pendingBeforeFail = await mediaAttachmentRepo
            .getUploadPendingAttachments();
        expect(pendingBeforeFail, hasLength(1));
        final messageId = pendingBeforeFail.single.messageId;
        final persistedBeforeFail = await msgRepo.getMessage(messageId);
        expect(persistedBeforeFail, isNotNull);
        expect(persistedBeforeFail!.status, 'sending');
        expect(persistedBeforeFail.quotedMessageId, 'msg-parent-media-upload');

        uploadGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 20);

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Fail media parent row',
        );
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Replying to'), findsOneWidget);
        expect(bridge.commandLog, isNot(contains('group:publish')));

        final persistedAfterFail = await msgRepo.getMessage(messageId);
        expect(persistedAfterFail, isNotNull);
        expect(persistedAfterFail!.status, 'failed');
        expect(persistedAfterFail.quotedMessageId, 'msg-parent-media-upload');

        final pendingAfterFail = await mediaAttachmentRepo
            .getUploadPendingAttachments();
        expect(pendingAfterFail, hasLength(1));
        expect(pendingAfterFail.single.id, pendingBeforeFail.single.id);
        expect(pendingAfterFail.single.downloadStatus, 'upload_pending');

        final failedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final failedMessage = failedScreen.messages.singleWhere(
          (message) => message.id == messageId,
        );
        expect(failedMessage.status, 'failed');
        expect(failedMessage.quotedMessageId, 'msg-parent-media-upload');
      },
    );

    testWidgets(
      'ordinary media group-not-found rejection removes the row and cleans durable media state',
      (tester) async {
        final missingGroup = makeChatGroup();
        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-missing-group-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');
        final mediaFileManager = FakeMediaFileManager();
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

        await tester.pumpWidget(
          buildWidget(
            group: missingGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
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
                }) async => MediaAttachment(
                  id: 'server-missing-group-media',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: mediaFileManager?.relativePathForAttachment(
                    contactPeerId: missingGroup.id,
                    blobId: blobId!,
                    mime: mime,
                  ),
                  downloadStatus: 'done',
                  contentHash: _validContentHash,
                  encryptionKeyBase64: 'key-fixture',
                  encryptionNonce: 'nonce-fixture',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                ),
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final sendMessage = screen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await sendMessage('Missing group media');
        });
        await pumpFrames(tester, count: 20);

        expect(await msgRepo.getMessagesPage(missingGroup.id), isEmpty);
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
        expect(mediaAttachmentRepo.count, 0);
        expect(deletedDirs, hasLength(1));
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets(
      'ordinary media unauthorized rejection removes the row and cleans durable media state',
      (tester) async {
        final widgetGroup = makeAnnouncementGroup(role: GroupRole.admin);
        await groupRepo.saveGroup(
          widgetGroup.copyWith(myRole: GroupRole.member),
        );

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-unauthorized-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');
        final mediaFileManager = FakeMediaFileManager();
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

        await tester.pumpWidget(
          buildWidget(
            group: widgetGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
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
                }) async => MediaAttachment(
                  id: 'server-unauthorized-media',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: mediaFileManager?.relativePathForAttachment(
                    contactPeerId: widgetGroup.id,
                    blobId: blobId!,
                    mime: mime,
                  ),
                  downloadStatus: 'done',
                  contentHash: _validContentHash,
                  encryptionKeyBase64: 'key-fixture',
                  encryptionNonce: 'nonce-fixture',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                ),
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final sendMessage = screen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await sendMessage('Unauthorized media');
        });
        await pumpFrames(tester, count: 20);

        expect(await msgRepo.getMessagesPage(widgetGroup.id), isEmpty);
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
        expect(mediaAttachmentRepo.count, 0);
        expect(deletedDirs, hasLength(1));
        expect(bridge.commandLog, isNot(contains('group:publish')));
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
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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
      'sending a message with zero topic peers keeps the row sent and does not restore the draft',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final joinedAt = DateTime.utc(2026, 5, 13, 11);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            joinedAt: joinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-zero-topic-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-zero-topic-bob',
            mlKemPublicKey: 'mlkem-zero-topic-bob',
            joinedAt: joinedAt.add(const Duration(minutes: 1)),
          ),
        );

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
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

        final messages = await msgRepo.getMessagesPage(group.id);
        final saved = messages.firstWhere(
          (message) => message.text == 'No peers online',
        );
        expect(saved.status, 'sent');
        expect(saved.inboxStored, isTrue);
      },
    );

    testWidgets(
      'NW-007 zero topic peers keep active member UI and recovery banner',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final joinedAt = DateTime.utc(2026, 5, 13, 11);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            joinedAt: joinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-nw007-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-nw007-bob',
            mlKemPublicKey: 'mlkem-nw007-bob',
            joinedAt: joinedAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-nw007-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-nw007-charlie',
            mlKemPublicKey: 'mlkem-nw007-charlie',
            joinedAt: joinedAt.add(const Duration(minutes: 2)),
          ),
        );
        await contactRepo.addContact(
          ContactModel(
            peerId: 'peer-nw007-bob',
            publicKey: 'pk-nw007-bob',
            rendezvous: '/ip4/127.0.0.1/tcp/4001',
            username: 'Bob',
            signature: 'sig-nw007-bob',
            scannedAt: joinedAt.toIso8601String(),
            mlKemPublicKey: 'mlkem-nw007-bob',
          ),
        );
        await contactRepo.addContact(
          ContactModel(
            peerId: 'peer-nw007-charlie',
            publicKey: 'pk-nw007-charlie',
            rendezvous: '/ip4/127.0.0.1/tcp/4002',
            username: 'Charlie',
            signature: 'sig-nw007-charlie',
            scannedAt: joinedAt.toIso8601String(),
            mlKemPublicKey: 'mlkem-nw007-charlie',
          ),
        );
        final membersBefore = (await groupRepo.getMembers(
          group.id,
        )).map((member) => member.peerId).toSet();
        final removedStreamController = StreamController<String>.broadcast();
        addTearDown(removedStreamController.close);
        groupRecoveryGate.begin();
        addTearDown(groupRecoveryGate.resetForTest);
        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': true,
              'messageId': 'nw007-zero-topic-peer-ui',
              'topicPeers': 0,
            },
          },
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            removedStreamController: removedStreamController,
          ),
        );
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('group-conversation-security-strip'))
              .evaluate()
              .isNotEmpty,
        );

        expect(find.byType(GroupConversationScreen), findsOneWidget);
        expect(find.text('All 3 members verified'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('group-recovery-banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('group-read-only-banner')),
          findsNothing,
        );
        expect(find.text('You were removed from this group.'), findsNothing);
        expect(find.byType(TextField), findsOneWidget);

        await tester.enterText(
          find.byType(TextField),
          'NW-007 zero peers keep group active',
        );
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(find.byType(GroupConversationScreen), findsOneWidget);
        expect(
          find.text('NW-007 zero peers keep group active'),
          findsOneWidget,
        );
        expect(find.text('All 3 members verified'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('group-recovery-banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('group-read-only-banner')),
          findsNothing,
        );
        expect(find.text('You were removed from this group.'), findsNothing);
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(
          (await groupRepo.getMembers(
            group.id,
          )).map((member) => member.peerId).toSet(),
          membersBefore,
        );
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

    testWidgets(
      'GMAR-004 reopen hydration preserves video voice pending and failed media without duplicates',
      (tester) async {
        final group = makeChatGroup();
        final timestamp = DateTime.utc(2026, 5, 2, 9);
        final mediaFileManager = FakeMediaFileManager();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'gmar004-complete',
            text: 'verified video and voice',
            timestamp: timestamp,
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'gmar004-pending',
            text: 'pending video remains visible',
            timestamp: timestamp.add(const Duration(seconds: 1)),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'gmar004-failed',
            text: 'failed voice remains retryable',
            timestamp: timestamp.add(const Duration(seconds: 2)),
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'gmar004-video-done',
            messageId: 'gmar004-complete',
            mime: 'video/mp4',
            size: 4096,
            mediaType: 'video',
            width: 640,
            height: 360,
            durationMs: 12000,
            localPath: 'pending_uploads/gmar004-complete/gmar004-video.mp4',
            downloadStatus: 'done',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-05-02T09:00:00.000Z',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'gmar004-voice-done',
            messageId: 'gmar004-complete',
            mime: 'audio/mp4',
            size: 2048,
            mediaType: 'audio',
            durationMs: 4200,
            localPath: 'pending_uploads/gmar004-complete/gmar004-voice.m4a',
            downloadStatus: 'done',
            waveform: <double>[0.2, 0.6, 0.35, 0.8],
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-05-02T09:00:01.000Z',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'gmar004-video-pending',
            messageId: 'gmar004-pending',
            mime: 'video/mp4',
            size: 4096,
            mediaType: 'video',
            width: 640,
            height: 360,
            durationMs: 9000,
            downloadStatus: 'pending',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-05-02T09:00:02.000Z',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'gmar004-voice-failed',
            messageId: 'gmar004-failed',
            mime: 'audio/mp4',
            size: 2048,
            mediaType: 'audio',
            durationMs: 3000,
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            waveform: <double>[0.1, 0.4, 0.7],
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-05-02T09:00:03.000Z',
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpFrames(tester, count: 20);
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.length == 3 &&
              screen.mediaMap['gmar004-complete']?.length == 2 &&
              screen.mediaMap['gmar004-pending']?.length == 1 &&
              screen.mediaMap['gmar004-failed']?.length == 1;
        });

        void expectHydratedOnce() {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(
            screen.messages.where(
              (message) => message.id == 'gmar004-complete',
            ),
            hasLength(1),
          );
          expect(
            screen.mediaMap['gmar004-complete']!.map((media) => media.id),
            ['gmar004-video-done', 'gmar004-voice-done'],
          );
          expect(
            screen.mediaMap['gmar004-complete']!
                .map((media) => media.contentHash)
                .toSet(),
            {_validContentHash},
          );
          expect(
            screen.mediaMap['gmar004-complete']!
                .map((media) => media.encryptionScheme)
                .toSet(),
            {kMediaAttachmentEncryptionSchemeBlobAesGcmV1},
          );
          expect(
            screen.mediaMap['gmar004-pending']!.single.downloadStatus,
            isIn(['pending', 'failed', kMediaDownloadStatusIntegrityFailed]),
          );
          expect(
            screen.mediaMap['gmar004-failed']!.single.downloadStatus,
            kMediaDownloadStatusIntegrityFailed,
          );
          expect(screen.onRetryUnavailableMedia, isNotNull);
        }

        expectHydratedOnce();
        expect(
          find.byKey(
            const ValueKey(
              'unavailable-media-retry-gmar004-failed-gmar004-voice-failed',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('failed-media-retry-gmar004-failed')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('failed-media-delete-gmar004-failed')),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpFrames(tester, count: 20);
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.length == 3 &&
              screen.mediaMap['gmar004-complete']?.length == 2 &&
              screen.mediaMap['gmar004-pending']?.length == 1 &&
              screen.mediaMap['gmar004-failed']?.length == 1;
        });

        expectHydratedOnce();
      },
    );

    testWidgets(
      'MS003 live stream upsert orders equal timestamps by message id',
      (tester) async {
        final group = makeChatGroup();
        final sameTimestamp = DateTime.utc(2026, 4, 30, 12);
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'ms003-b',
            text: 'B at same time',
            timestamp: sameTimestamp,
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        final incoming = makeMessage(
          id: 'ms003-a',
          text: 'A at same time',
          timestamp: sameTimestamp,
        );
        await msgRepo.saveMessage(incoming);
        messageStreamController.add(incoming);
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.messages.map((message) => message.id), [
          'ms003-a',
          'ms003-b',
        ]);
      },
    );

    testWidgets(
      'GP-027 out-of-order live messages keep deterministic order after restart',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        final later = makeMessage(
          id: 'gp027-b-later',
          senderPeerId: 'peer-bob',
          senderUsername: 'Bob',
          text: 'Bob arrives first but happened second',
          timestamp: DateTime.utc(2026, 5, 14, 12, 0, 2),
        );
        await msgRepo.saveMessage(later);
        messageStreamController.add(later);
        await pumpFrames(tester, count: 20);

        final earlier = makeMessage(
          id: 'gp027-a-earlier',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          text: 'Alice arrives second but happened first',
          timestamp: DateTime.utc(2026, 5, 14, 12, 0, 1),
        );
        await msgRepo.saveMessage(earlier);
        messageStreamController.add(earlier);
        await pumpFrames(tester, count: 20);

        GroupConversationScreen screen() =>
            tester.widget<GroupConversationScreen>(
              find.byType(GroupConversationScreen),
            );

        expect(screen().messages.map((message) => message.id), [
          'gp027-a-earlier',
          'gp027-b-later',
        ]);

        await tester.pumpWidget(const SizedBox.shrink());
        await pumpFrames(tester);
        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(screen().messages.map((message) => message.id), [
          'gp027-a-earlier',
          'gp027-b-later',
        ]);
      },
    );

    testWidgets('MS004 live stream upsert keeps quoted parent before reply', (
      tester,
    ) async {
      final group = makeChatGroup();
      final parentTimestamp = DateTime.utc(2026, 4, 30, 12, 0, 1);
      final replyTimestamp = DateTime.utc(2026, 4, 30, 12);
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'zz-ms004-parent',
          text: 'Parent',
          timestamp: parentTimestamp,
        ),
      );
      await msgRepo.saveMessage(
        makeMessage(
          id: 'mm-ms004-peer',
          text: 'Concurrent peer',
          timestamp: replyTimestamp,
        ),
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      final reply = makeMessage(
        id: 'aa-ms004-reply',
        text: 'Reply',
        timestamp: replyTimestamp,
        quotedMessageId: 'zz-ms004-parent',
      );
      await msgRepo.saveMessage(reply);
      messageStreamController.add(reply);
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.messages.map((message) => message.id), [
        'mm-ms004-peer',
        'zz-ms004-parent',
        'aa-ms004-reply',
      ]);
    });

    testWidgets('live removal timeline event from listener appears in UI', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      messageStreamController.add(
        makeMessage(
          id: 'sys-member-removed-1',
          text: 'Admin removed Charlie',
          groupId: 'group-1',
          senderPeerId: 'peer-admin',
          senderUsername: 'Admin',
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.text('Admin removed Charlie'), findsOneWidget);
    });

    testWidgets('live re-add timeline event from listener appears in UI', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      messageStreamController.add(
        makeMessage(
          id: 'sys-member-added-1',
          text: 'Admin added Charlie',
          groupId: 'group-1',
          senderPeerId: 'peer-admin',
          senderUsername: 'Admin',
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.text('Admin added Charlie'), findsOneWidget);
    });

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
      'IR-018 shows recovery state while restart replay is pending and live messages still arrive',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(id: 'ir018-stale-local', text: 'Local before replay'),
        );
        groupRecoveryGate.begin();

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(
          find.byKey(const ValueKey('group-recovery-banner')),
          findsOneWidget,
        );
        expect(find.text('Local before replay'), findsOneWidget);

        messageStreamController.add(
          makeMessage(
            id: 'ir018-live-during-recovery',
            text: 'Live during replay recovery',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.text('Live during replay recovery'), findsOneWidget);

        groupRecoveryGate.end();
        await pumpFrames(tester, count: 5);

        expect(
          find.byKey(const ValueKey('group-recovery-banner')),
          findsNothing,
        );
        expect(find.text('Live during replay recovery'), findsOneWidget);
      },
    );

    testWidgets(
      'highlights the targeted message context when opened from a notification anchor',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final start = DateTime.utc(2026, 2, 1, 10);
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-older',
            groupId: group.id,
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            text: 'Older message',
            timestamp: start,
            createdAt: start,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-targeted',
            groupId: group.id,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
            text: 'Tapped notification message',
            timestamp: start.add(const Duration(minutes: 1)),
            createdAt: start.add(const Duration(minutes: 1)),
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialHighlightedMessageId: 'msg-targeted',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.text('Tapped notification message'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('grp-highlight-msg-targeted')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('grp-highlight-msg-older')),
          findsNothing,
        );

        await tester.longPress(find.text('Tapped notification message'));
        await pumpFrames(tester);

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      },
    );

    testWidgets(
      'notification-anchor entry keeps group reaction inspection aligned with the shared conversation surface',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 2, 1, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 2, 1, 10, 1),
          ),
        );

        final start = DateTime.utc(2026, 2, 1, 10);
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-anchor-older',
            groupId: group.id,
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            text: 'Older anchor message',
            timestamp: start,
            createdAt: start,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-anchor-targeted',
            groupId: group.id,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
            text: 'Targeted anchor reaction message',
            timestamp: start.add(const Duration(minutes: 1)),
            createdAt: start.add(const Duration(minutes: 1)),
          ),
        );

        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-anchor-self',
            messageId: 'msg-anchor-targeted',
            emoji: '🔥',
            senderPeerId: testIdentity.peerId,
            timestamp: start.add(const Duration(minutes: 2)).toIso8601String(),
            createdAt: start.add(const Duration(minutes: 2)).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-anchor-bob',
            messageId: 'msg-anchor-targeted',
            emoji: '🔥',
            senderPeerId: 'peer-bob',
            timestamp: start.add(const Duration(minutes: 3)).toIso8601String(),
            createdAt: start.add(const Duration(minutes: 3)).toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            initialHighlightedMessageId: 'msg-anchor-targeted',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(
          find.byKey(const ValueKey('grp-highlight-msg-anchor-targeted')),
          findsOneWidget,
        );
        expect(find.text('🔥 2'), findsOneWidget);

        await tester.tap(find.text('🔥 2'));
        await pumpFrames(tester);

        expect(find.byKey(GroupReactionDetailsSheet.sheetKey), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
        expect(find.text('Bob'), findsWidgets);
        expect(reactionRepo.removeReactionCallCount, 0);
      },
    );

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

    testWidgets('returning from group info reloads the latest group name', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester, count: 20);

      expect(find.text('Test Group'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.info_outline));
      await pumpFrames(tester, count: 20);

      expect(find.byType(GroupInfoScreen), findsOneWidget);

      await groupRepo.updateGroup(
        group.copyWith(
          name: 'Renamed Group',
          description: 'Updated description',
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new).first);
      await pumpFrames(tester, count: 20);

      expect(find.byType(GroupInfoScreen), findsNothing);
      expect(find.text('Renamed Group'), findsOneWidget);
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

    testWidgets('dissolved groups show read-only copy and no send controls', (
      tester,
    ) async {
      final group = makeChatGroup().copyWith(
        isDissolved: true,
        dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
        dissolvedBy: 'peer-admin',
      );
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      expect(find.text('Dissolved'), findsOneWidget);
      expect(
        find.text(
          'This group has been dissolved. History stays available, but new messages are disabled.',
        ),
        findsOneWidget,
      );
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
      'active groups expose the long-press reaction bar when mutation deps are wired',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: FakeReactionRepository(),
            reactionReplayOutboxRepo: FakeGroupReactionReplayOutboxRepository(),
          ),
        );
        await pumpFrames(tester);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onReactionSelected, isNotNull);

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        expect(
          find.byKey(MessageContextOverlay.reactionBarKey),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'announcement readers stay read-only for compose but still keep reaction entry',
      (tester) async {
        final group = makeAnnouncementGroup(role: GroupRole.member);
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: FakeReactionRepository(),
            reactionReplayOutboxRepo: FakeGroupReactionReplayOutboxRepository(),
          ),
        );
        await pumpFrames(tester);

        expect(
          find.text('Only admins can send messages in this group'),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
        expect(screen.onQuoteReply, isNull);
        expect(screen.onReactionSelected, isNotNull);

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.reactionBarKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.replyActionKey), findsNothing);
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      },
    );

    testWidgets(
      'dissolved groups hide reaction entry even when reaction deps are wired',
      (tester) async {
        final group = makeChatGroup().copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
          dissolvedBy: 'peer-admin',
        );
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: FakeReactionRepository(),
            reactionReplayOutboxRepo: FakeGroupReactionReplayOutboxRepository(),
          ),
        );
        await pumpFrames(tester);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onReactionSelected, isNull);

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(find.byKey(MessageContextOverlay.reactionBarKey), findsNothing);
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      },
    );

    testWidgets(
      'stale reaction entry restores local state when the group dissolves before publish',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
        final reactionRepo = FakeReactionRepository();
        final reactionReplayOutboxRepo =
            FakeGroupReactionReplayOutboxRepository();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          ),
        );
        await pumpFrames(tester);

        await groupRepo.updateGroup(
          group.copyWith(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 4, 22, 12),
            dissolvedBy: 'peer-admin',
          ),
        );

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        final thumbsUp = find.descendant(
          of: find.byKey(MessageContextOverlay.reactionBarKey),
          matching: find.text('\u{1F44D}'),
        );
        expect(thumbsUp, findsOneWidget);

        await tester.tap(thumbsUp);
        await pumpFrames(tester, count: 20);

        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
        expect(find.text('This group has been dissolved'), findsOneWidget);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
        expect(screen.onReactionSelected, isNull);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('\u{1F44D}'), findsNothing);
      },
    );

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

    testWidgets('ML-017 retained removed-member history opens read-only', (
      tester,
    ) async {
      final group = makeChatGroup(role: GroupRole.member);
      await groupRepo.saveGroup(group);
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await msgRepo.saveMessage(
        makeMessage(id: 'ml017-old-history', text: 'ML-017 old history'),
      );

      await tester.pumpWidget(
        buildWidget(
          group: group,
          reactionRepo: FakeReactionRepository(),
          reactionReplayOutboxRepo: FakeGroupReactionReplayOutboxRepository(),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('ML-017 old history'), findsOneWidget);
      expect(
        find.text(
          "You can read this group's history, but you are not an active member.",
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.canWrite, isFalse);
      expect(screen.onQuoteReply, isNull);
      expect(screen.onReactionSelected, isNull);
    });

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

    testWidgets(
      'current group removal shows a notice and exits the conversation route',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tracker = ActiveConversationTracker();
        final removedStreamController = StreamController<String>.broadcast();
        addTearDown(removedStreamController.close);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupConversationWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          groupMessageListener: FakeGroupMessageListener(
                            messageStreamController.stream,
                            removedStream: removedStreamController.stream,
                          ),
                          bridge: bridge,
                          identityRepo: identityRepo,
                          contactRepo: contactRepo,
                          p2pService: p2pService,
                          groupConversationTracker: tracker,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Group Conversation'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Group Conversation'));
        await pumpFrames(tester, count: 20);

        expect(find.byType(GroupConversationScreen), findsOneWidget);
        expect(tracker.isViewing('group:${group.id}'), isTrue);

        removedStreamController.add(group.id);
        await pumpFrames(tester, count: 20);

        expect(find.byType(GroupConversationScreen), findsNothing);
        expect(find.text('Open Group Conversation'), findsOneWidget);
        expect(find.text('You were removed from this group.'), findsOneWidget);
        expect(tracker.isViewing('group:${group.id}'), isFalse);
      },
    );

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
      'gallery multi-video batches keep one processing tile with honest batch context',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_gallery_batch_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final firstVideo = File('${tempDir.path}/video-1.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final stillImage = File('${tempDir.path}/image-1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final secondVideo = File('${tempDir.path}/video-2.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedFirstVideo = File('${tempDir.path}/processed-1.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedImage = File('${tempDir.path}/processed-1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedSecondVideo = File('${tempDir.path}/processed-2.mp4')
          ..writeAsBytesSync(_tinyPngBytes);

        final mediaPicker = FakeMediaPicker()
          ..multipleMediaResult = [
            XFile(firstVideo.path),
            XFile(stillImage.path),
            XFile(secondVideo.path),
          ];
        final videoResults = [
          Completer<VideoProcessResult>(),
          Completer<VideoProcessResult>(),
        ];
        final imageResult = Completer<XFile?>();
        var imageCompressionStarted = false;
        final progressCallbacks = <void Function(double)?>[];
        var videoCallCount = 0;
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                if (path == stillImage.path) {
                  imageCompressionStarted = true;
                  return imageResult.future;
                }
                return null;
              },
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double progress)? onProgress,
              }) async {
                progressCallbacks.add(onProgress);
                final result = videoResults[videoCallCount];
                videoCallCount++;
                return result.future;
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
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(tester, () => progressCallbacks.length == 1);

        progressCallbacks.single!(35);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Processing (1/2)'), findsOneWidget);
        expect(find.text('35%'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        videoResults[0].complete(
          VideoProcessResult(path: processedFirstVideo.path),
        );
        await pumpUntil(tester, () => imageCompressionStarted);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Processing (1/2)'), findsOneWidget);

        imageResult.complete(XFile(processedImage.path));
        await pumpUntil(tester, () => progressCallbacks.length == 2);

        progressCallbacks.last!(60);
        await tester.pump();

        expect(find.text('Processing (2/2)'), findsOneWidget);
        expect(find.text('60%'), findsOneWidget);

        videoResults[1].complete(
          VideoProcessResult(path: processedSecondVideo.path),
        );
        await tester.pump();
      },
    );

    testWidgets('recorded single video keeps single-item processing copy', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      final tempDir = Directory.systemTemp.createTempSync(
        'group_camera_video_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final cameraVideo = File('${tempDir.path}/camera-video.mp4')
        ..writeAsBytesSync(_tinyPngBytes);
      final processedVideo = File('${tempDir.path}/camera-video-out.mp4')
        ..writeAsBytesSync(_tinyPngBytes);

      final mediaPicker = FakeMediaPicker()
        ..videoResult = XFile(cameraVideo.path);
      final result = Completer<VideoProcessResult>();
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
              void Function(double progress)? onProgress,
            }) async {
              progressCallback = onProgress;
              return result.future;
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

      expect(progressCallback, isNotNull);

      progressCallback!(40);
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('Processing (1/1)'), findsNothing);
      expect(find.text('40%'), findsOneWidget);

      result.complete(VideoProcessResult(path: processedVideo.path));
      await tester.pump();
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

    testWidgets(
      'publish timeout with inbox success keeps the message successful in UI',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
          },
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        await tester.enterText(find.byType(TextField), 'Timeout but stored');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(find.text('Timeout but stored'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty,
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

        final saved = (await msgRepo.getMessagesPage(
          group.id,
        )).firstWhere((message) => message.text == 'Timeout but stored');
        expect(saved.status, 'sent');
        expect(saved.inboxStored, isTrue);
      },
    );

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
      final attachment = File('${tempDir.path}/retry.png')
        ..writeAsBytesSync(_tinyPngBytes);

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
          initialPendingMedia: [
            PendingComposerMedia(
              file: attachment,
              budgetBytes: attachment.lengthSync(),
            ),
          ],
        ),
      );
      await pumpFrames(tester, count: 20);
      expect(
        find.byType(AttachmentPreviewStrip),
        findsOneWidget,
        reason: 'initial attachment preview should be seeded before send',
      );

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent-upload');
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Retry upload');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 30);

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Upload parent'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Retry upload',
      );
    });

    testWidgets('shows relay upload progress and blocks leaving mid-upload', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      final tempDir = Directory.systemTemp.createTempSync(
        'group_upload_progress_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/progress.jpg')
        ..writeAsStringSync('0123456789');

      final uploadGate = Completer<void>();
      final uploadStarted = Completer<void>();
      String? activeBlobId;

      await tester.pumpWidget(
        buildWidget(
          group: group,
          initialAttachments: [attachment],
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
                activeBlobId = blobId;
                uploadStarted.complete();
                await uploadGate.future;
                return MediaAttachment(
                  id: blobId ?? 'uploaded-group-progress-1',
                  messageId: '',
                  mime: mime,
                  size: File(localFilePath).lengthSync(),
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  contentHash: _validContentHash,
                  encryptionKeyBase64: 'key-fixture',
                  encryptionNonce: 'nonce-fixture',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
        ),
      );
      await pumpFrames(tester, count: 20);

      await tester.enterText(find.byType(TextField), 'Uploading');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await uploadStarted.future;
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upload-progress-banner')),
        findsOneWidget,
      );
      expect(wakeLockDriver.enableCalls, 1);
      expect(UploadWakeLockController.debugActiveHolds, 1);

      emitMediaUploadProgressEvent({
        'id': activeBlobId,
        'sentBytes': 5,
        'totalBytes': 10,
        'toPeerId': group.id,
      });
      await tester.pump();

      expect(
        find.text(
          '${formatPendingComposerBudgetBytes(5)} / '
          '${formatPendingComposerBudgetBytes(10)}',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Keep the app open until the upload completes'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pump();

      expect(find.text('Leave conversation?'), findsOneWidget);
      expect(
        find.text(
          'An upload is in progress. Leaving may interrupt it. Are you sure?',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('upload-leave-stay')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upload-progress-banner')),
        findsOneWidget,
      );
      expect(wakeLockDriver.disableCalls, 0);

      uploadGate.complete();
      await pumpUntil(
        tester,
        () =>
            find
                .byKey(const ValueKey('upload-progress-banner'))
                .evaluate()
                .isEmpty &&
            wakeLockDriver.disableCalls == 1,
      );

      expect(UploadWakeLockController.debugActiveHolds, 0);
    });

    testWidgets(
      'cancel on the active upload banner restores composer state and terminalizes durable pending rows',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_cancel_upload_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachmentA = File('${tempDir.path}/cancel-a.jpg')
          ..writeAsStringSync('0123456789');
        final attachmentB = File('${tempDir.path}/cancel-b.jpg')
          ..writeAsStringSync('abcdefghij');
        final testMediaFileManager = FakeMediaFileManager();

        final uploadGate = Completer<void>();
        final uploadStarted = <String>[];
        final uploadCompleted = <String>[];

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: testMediaFileManager,
            initialAttachments: [attachmentA, attachmentB],
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
                  uploadStarted.add(blobId ?? 'missing-blob-id');
                  await uploadGate.future;
                  uploadCompleted.add(blobId ?? 'missing-blob-id');
                  return MediaAttachment(
                    id: blobId ?? 'uploaded-group-cancel',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: testMediaFileManager.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId!,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Cancel upload');
        await pumpUntil(tester, () => uploadStarted.length == 2, maxPumps: 120);
        await pumpFrames(tester, count: 5);

        final cancellingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(uploadStarted, hasLength(2));
        expect(cancellingScreen.uploadProgress, isNotNull);
        expect(cancellingScreen.onCancelUpload, isNotNull);
        expect(wakeLockDriver.enableCalls, 1);
        expect(UploadWakeLockController.debugActiveHolds, 1);

        cancellingScreen.onCancelUpload!.call();
        await tester.pump();
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpUntil(
          tester,
          () =>
              find
                  .byKey(const ValueKey('upload-progress-banner'))
                  .evaluate()
                  .isEmpty &&
              wakeLockDriver.disableCalls == 1,
        );

        final storedMessages = await msgRepo.getMessagesPage(group.id);
        expect(storedMessages, hasLength(1));
        final failedMessage = storedMessages.single;
        final storedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(failedMessage.id);

        expect(uploadCompleted, hasLength(2));
        expect(failedMessage.status, 'failed');
        expect(storedAttachments, hasLength(2));
        expect(
          storedAttachments.every(
            (attachment) => attachment.downloadStatus == 'upload_failed',
          ),
          isTrue,
        );
        expect(find.text('Upload cancelled.'), findsOneWidget);
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Cancel upload',
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );
        expect(UploadWakeLockController.debugActiveHolds, 0);
      },
    );

    testWidgets(
      'retry control re-sends only the targeted failed outgoing media row',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();

        String retryPayload({
          required String messageId,
          required String text,
          required String attachmentId,
          required String timestamp,
        }) {
          return jsonEncode({
            'groupId': group.id,
            'message': jsonEncode({
              'groupId': group.id,
              'senderId': testIdentity.peerId,
              'senderUsername': testIdentity.username,
              'keyEpoch': 0,
              'text': text,
              'timestamp': timestamp,
              'messageId': messageId,
              'media': [
                {'id': attachmentId},
              ],
            }),
          });
        }

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-targeted',
            text: 'Retry only me',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            inboxRetryPayload: retryPayload(
              messageId: 'msg-targeted',
              text: 'Retry only me',
              attachmentId: 'att-targeted',
              timestamp: '2026-01-15T12:00:00.000Z',
            ),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-untouched',
            text: 'Leave me failed',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            inboxRetryPayload: retryPayload(
              messageId: 'msg-untouched',
              text: 'Leave me failed',
              attachmentId: 'att-untouched',
              timestamp: '2026-01-15T12:01:00.000Z',
            ),
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-targeted',
            messageId: 'msg-targeted',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: 'pending_uploads/msg-targeted/att-targeted.jpg',
            downloadStatus: 'done',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-01-15T12:00:00.000Z',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-untouched',
            messageId: 'msg-untouched',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: 'pending_uploads/msg-untouched/att-untouched.jpg',
            downloadStatus: 'done',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-01-15T12:01:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.ownPeerId == testIdentity.peerId &&
              (screen.mediaMap['msg-targeted']?.isNotEmpty ?? false);
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.ownPeerId, testIdentity.peerId);
        expect(retryScreen.onRetryFailedMedia, isNotNull);
        expect(retryScreen.mediaMap['msg-targeted'], isNotEmpty);

        retryScreen.onRetryFailedMedia!('msg-targeted');
        await pumpUntil(
          tester,
          () =>
              bridge.commandLog.where((cmd) => cmd == 'group:publish').length ==
              1,
        );

        expect((await msgRepo.getMessage('msg-targeted'))?.status, 'sent');
        expect((await msgRepo.getMessage('msg-untouched'))?.status, 'failed');
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
        expect(find.text('Could not retry media message.'), findsNothing);
      },
    );

    testWidgets(
      'MD-012 retrying quarantined incoming media downloads only the targeted attachment',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();
        final repairedBytes = _md012EncryptedBytes(_tinyPngBytes);
        bridge = _DownloadRepairBridge(downloadedBytes: repairedBytes);

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-md012-repair',
            text: 'repair incoming media',
            groupId: group.id,
            isIncoming: true,
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            status: 'delivered',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-md012-target',
            messageId: 'msg-md012-repair',
            mime: 'image/png',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: mediaFileManager.relativePathForAttachment(
              contactPeerId: group.id,
              blobId: 'att-md012-target',
              mime: 'image/png',
            ),
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            contentHash: _md012HashBytes(repairedBytes),
            encryptionKeyBase64: _md012MediaKey,
            encryptionNonce: _md012MediaNonce,
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-04-29T12:00:00.000Z',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-md012-sibling',
            messageId: 'msg-md012-repair',
            mime: 'image/png',
            size: 1,
            mediaType: 'image',
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            contentHash:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            encryptionKeyBase64: 'key-sibling',
            encryptionNonce: 'nonce-sibling',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-04-29T12:00:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.onRetryUnavailableMedia != null &&
              (screen.mediaMap['msg-md012-repair']?.length ?? 0) == 2;
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.onRetryUnavailableMedia, isNotNull);
        await tester.runAsync(() async {
          final result = Function.apply(retryScreen.onRetryUnavailableMedia!, [
            'msg-md012-repair',
            'att-md012-target',
          ]);
          if (result is Future<void>) await result;
        });
        await tester.pump();
        await pumpUntilAsync(tester, () async {
          final attachments = await mediaAttachmentRepo
              .getAttachmentsForMessage('msg-md012-repair');
          return attachments
                  .where((attachment) => attachment.id == 'att-md012-target')
                  .single
                  .downloadStatus ==
              'done';
        }, maxPumps: 80);

        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          'msg-md012-repair',
        );
        final target = attachments
            .where((attachment) => attachment.id == 'att-md012-target')
            .single;
        final sibling = attachments
            .where((attachment) => attachment.id == 'att-md012-sibling')
            .single;

        expect(target.downloadStatus, 'done');
        expect(target.localPath, isNotNull);
        expect(sibling.downloadStatus, kMediaDownloadStatusIntegrityFailed);
        expect(
          (await msgRepo.getMessage('msg-md012-repair'))?.status,
          'delivered',
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(1),
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'blob:decrypt'),
          hasLength(1),
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    testWidgets(
      'MD-012 failed repair keeps media quarantined and clears unsafe file',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();
        final expectedBytes = _md012EncryptedBytes(_tinyPngBytes);
        final tamperedBytes = _md012EncryptedBytes('not a png'.codeUnits);
        bridge = _DownloadRepairBridge(downloadedBytes: tamperedBytes);
        final stalePath = await mediaFileManager.localPathForAttachment(
          contactPeerId: group.id,
          blobId: 'att-md012-fail',
          mime: 'image/png',
        );
        File(stalePath).writeAsBytesSync(<int>[9, 9, 9], flush: true);

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-md012-fail',
            text: 'still unsafe',
            groupId: group.id,
            isIncoming: true,
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            status: 'delivered',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-md012-fail',
            messageId: 'msg-md012-fail',
            mime: 'image/png',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: mediaFileManager.relativePathForAttachment(
              contactPeerId: group.id,
              blobId: 'att-md012-fail',
              mime: 'image/png',
            ),
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            contentHash: _md012HashBytes(expectedBytes),
            encryptionKeyBase64: _md012MediaKey,
            encryptionNonce: _md012MediaNonce,
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-04-29T12:00:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.onRetryUnavailableMedia != null &&
              (screen.mediaMap['msg-md012-fail']?.isNotEmpty ?? false);
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.onRetryUnavailableMedia, isNotNull);
        await tester.runAsync(() async {
          final result = Function.apply(retryScreen.onRetryUnavailableMedia!, [
            'msg-md012-fail',
            'att-md012-fail',
          ]);
          if (result is Future<void>) await result;
        });
        await tester.pump();
        await pumpUntilAsync(tester, () async {
          if (!bridge.commandLog.contains('media:download')) return false;
          final attachments = await mediaAttachmentRepo
              .getAttachmentsForMessage('msg-md012-fail');
          return attachments.single.downloadStatus ==
              kMediaDownloadStatusIntegrityFailed;
        }, maxPumps: 80);

        final attachment = (await mediaAttachmentRepo.getAttachmentsForMessage(
          'msg-md012-fail',
        )).single;
        expect(attachment.downloadStatus, kMediaDownloadStatusIntegrityFailed);
        expect(attachment.localPath, isNull);
        expect(File(stalePath).existsSync(), isFalse);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(1),
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    testWidgets(
      'delete control removes only the targeted failed media row and owned files',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-delete-target',
            text: '',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            media: const [
              MediaAttachment(
                id: 'att-delete-target',
                messageId: 'msg-delete-target',
                mime: 'image/jpeg',
                size: 10,
                mediaType: 'image',
                localPath:
                    'pending_uploads/msg-delete-target/att-delete-target.jpg',
                downloadStatus: 'upload_pending',
                createdAt: '2026-01-15T12:02:00.000Z',
              ),
            ],
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-delete-untouched',
            text: '',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            media: const [
              MediaAttachment(
                id: 'att-delete-untouched',
                messageId: 'msg-delete-untouched',
                mime: 'image/jpeg',
                size: 10,
                mediaType: 'image',
                localPath:
                    'pending_uploads/msg-delete-untouched/att-delete-untouched.jpg',
                downloadStatus: 'upload_pending',
                createdAt: '2026-01-15T12:03:00.000Z',
              ),
            ],
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-delete-target',
            messageId: 'msg-delete-target',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/msg-delete-target/att-delete-target.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-15T12:02:00.000Z',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-delete-untouched',
            messageId: 'msg-delete-untouched',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/msg-delete-untouched/att-delete-untouched.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-15T12:03:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.ownPeerId == testIdentity.peerId &&
              (screen.mediaMap['msg-delete-target']?.isNotEmpty ?? false);
        });

        final deleteScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(deleteScreen.ownPeerId, testIdentity.peerId);
        expect(deleteScreen.onDeleteFailedMedia, isNotNull);
        expect(deleteScreen.mediaMap['msg-delete-target'], isNotEmpty);

        deleteScreen.onDeleteFailedMedia!('msg-delete-target');
        await tester.pump(const Duration(milliseconds: 300));

        expect(await msgRepo.getMessage('msg-delete-target'), isNull);
        expect(await msgRepo.getMessage('msg-delete-untouched'), isNotNull);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-delete-target',
          ),
          isEmpty,
        );
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-delete-untouched',
          ),
          hasLength(1),
        );
        expect(
          mediaFileManager.deletedFilePaths,
          contains(
            endsWith('pending_uploads/msg-delete-target/att-delete-target.jpg'),
          ),
        );
        expect(
          mediaFileManager.deletedFilePaths,
          isNot(
            contains(
              endsWith(
                'pending_uploads/msg-delete-untouched/att-delete-untouched.jpg',
              ),
            ),
          ),
        );
      },
    );

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
                contentHash: _validContentHash,
                encryptionKeyBase64: 'key-fixture',
                encryptionNonce: 'nonce-fixture',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(const Duration(seconds: 10));
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
        await pumpUntil(tester, () => uploadStarted.isCompleted, maxPumps: 240);
        expect(uploadStarted.isCompleted, isTrue);
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
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(const Duration(seconds: 10));
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
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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
        await pumpUntilAsync(tester, () async {
          final messages = await msgRepo.getMessagesPage(group.id);
          return messages.length == 1 && messages.single.status == 'sending';
        }, maxPumps: 240);
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
      'voice send with zero topic peers still persists the final row as sent',
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
                  contentHash: _validContentHash,
                  encryptionKeyBase64: 'key-fixture',
                  encryptionNonce: 'nonce-fixture',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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
        expect(saved.status, 'sent');
        expect(saved.quotedMessageId, isNull);
        expect(saved.inboxStored, isTrue);
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
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
                  contentHash: _validContentHash,
                  encryptionKeyBase64: 'key-fixture',
                  encryptionNonce: 'nonce-fixture',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(const Duration(seconds: 6));
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
                contentHash: _validContentHash,
                encryptionKeyBase64: 'key-fixture',
                encryptionNonce: 'nonce-fixture',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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

    testWidgets(
      'local long-press actions stay available when reactionRepo is null',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        // Long-press still opens the context surface, but reactions stay hidden.
        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(find.byKey(MessageContextOverlay.reactionBarKey), findsNothing);
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
        expect(find.text('\u{1F44D}'), findsNothing);
      },
    );

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

    testWidgets(
      'group reaction chips open participant inspection without mutating stored reactions',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 4, 11, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 4, 11, 10, 1),
          ),
        );
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-self',
            messageId: 'msg-1',
            emoji: '🔥',
            senderPeerId: testIdentity.peerId,
            timestamp: DateTime.utc(2026, 4, 11, 10, 2).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 2).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-bob',
            messageId: 'msg-1',
            emoji: '🔥',
            senderPeerId: 'peer-bob',
            timestamp: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, reactionRepo: reactionRepo),
        );
        await pumpFrames(tester);

        await tester.tap(find.text('🔥 2'));
        await pumpFrames(tester);

        expect(find.byKey(GroupReactionDetailsSheet.sheetKey), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
        expect(reactionRepo.removeReactionCallCount, 0);
        expect(
          await reactionRepo.getReactionsForMessage('msg-1'),
          hasLength(2),
        );
      },
    );

    testWidgets(
      'group reaction inspection prefers member and contact usernames before readable peer-id fallback',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 4, 11, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-ibra',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 4, 11, 10, 1),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-fallback-1234567890',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 4, 11, 10, 2),
          ),
        );
        contactRepo.addTestContact(
          ContactModel(
            peerId: 'peer-ibra',
            publicKey: 'pk-peer-ibra',
            rendezvous: 'rv-peer-ibra',
            username: 'Ibra',
            signature: 'sig-peer-ibra',
            scannedAt: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-identity', text: 'Identity target'),
        );

        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-charlie',
            messageId: 'msg-identity',
            emoji: '👍',
            senderPeerId: 'peer-charlie',
            timestamp: DateTime.utc(2026, 4, 11, 10, 2).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 2).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-ibra',
            messageId: 'msg-identity',
            emoji: '👍',
            senderPeerId: 'peer-ibra',
            timestamp: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-fallback',
            messageId: 'msg-identity',
            emoji: '👍',
            senderPeerId: 'peer-fallback-1234567890',
            timestamp: DateTime.utc(2026, 4, 11, 10, 4).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 4).toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, reactionRepo: reactionRepo),
        );
        await pumpFrames(tester);

        await tester.tap(find.text('👍 3'));
        await pumpFrames(tester);

        expect(find.byKey(GroupReactionDetailsSheet.sheetKey), findsOneWidget);
        expect(find.text('Charlie'), findsOneWidget);
        expect(find.text('Ibra'), findsOneWidget);
        expect(find.text('peer-fallbac...'), findsOneWidget);
      },
    );
  });
}
