import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';

class _FakeIdentityRepository implements IdentityRepository {
  _FakeIdentityRepository(this.identity);

  final IdentityModel? identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
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

class _FakeGroupMessageListener extends GroupMessageListener {
  _FakeGroupMessageListener(
    this._stream, {
    Stream<ReactionChange>? reactionStream,
  }) : _reactionStream = reactionStream,
       super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  final Stream<GroupMessage> _stream;
  final Stream<ReactionChange>? _reactionStream;

  @override
  Stream<GroupMessage> get groupMessageStream => _stream;

  @override
  Stream<ReactionChange> get groupReactionChangeStream =>
      _reactionStream ?? super.groupReactionChangeStream;
}

class _OrderRecordingBridge extends FakeBridge {
  _OrderRecordingBridge({
    List<String>? operationLog,
    this.bgBeginResponse = '99',
    this.publishMessageId = 'msg-published',
    this.publishTopicPeers = 1,
    Set<String>? throwOnCommands,
    Map<String, Duration>? commandDelays,
    Map<String, Completer<void>>? commandGates,
  }) : operationLog = operationLog ?? <String>[],
       throwOnCommands = throwOnCommands ?? <String>{},
       commandDelays = commandDelays ?? const <String, Duration>{},
       commandGates = commandGates ?? const <String, Completer<void>>{};

  final List<String> operationLog;
  final String bgBeginResponse;
  final String publishMessageId;
  final int publishTopicPeers;
  final Set<String> throwOnCommands;
  final Map<String, Duration> commandDelays;
  final Map<String, Completer<void>> commandGates;

  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);

    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final cmd = decoded['cmd'] as String;
    lastCommand = cmd;
    commandLog.add(cmd);
    operationLog.add('bridge:$cmd');

    final gate = commandGates[cmd];
    if (gate != null) {
      await gate.future;
    }

    final delay = commandDelays[cmd];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }

    if (throwOnCommands.contains(cmd)) {
      throw Exception('$cmd failed');
    }

    switch (cmd) {
      case 'bg:begin':
        return bgBeginResponse;
      case 'bg:end':
        return '';
      case 'group.encrypt':
        final payload = decoded['payload'] as Map<String, dynamic>;
        return jsonEncode({
          'ok': true,
          'ciphertext': payload['plaintext'],
          'nonce': 'fake-group-nonce',
        });
      case 'group.decrypt':
        final payload = decoded['payload'] as Map<String, dynamic>;
        return jsonEncode({'ok': true, 'plaintext': payload['ciphertext']});
      case 'group:publish':
        return jsonEncode({
          'ok': true,
          'messageId': publishMessageId,
          'topicPeers': publishTopicPeers,
        });
      case 'payload.sign':
        return jsonEncode({
          'ok': true,
          'signature': 'signed-by-bg-task-bridge',
        });
      case 'payload.verify':
        return jsonEncode({'ok': true, 'valid': true});
      case 'group:inboxStore':
        return jsonEncode({'ok': true});
      default:
        return jsonEncode({'ok': true});
    }
  }
}

final _testIdentity = IdentityModel(
  peerId: 'peer-self',
  publicKey: 'pub-self',
  privateKey: 'priv-self',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  username: 'Alice',
  createdAt: '2025-01-01T00:00:00.000Z',
  updatedAt: '2025-01-01T00:00:00.000Z',
);

GroupModel _makeChatGroup() => GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-group-1',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-self',
  myRole: GroupRole.admin,
);

GroupModel _makeAnnouncementGroup({GroupRole role = GroupRole.admin}) =>
    GroupModel(
      id: 'group-1',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'topic-group-1',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-self',
      myRole: role,
    );

Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 200,
}) async {
  var pumps = 0;
  while (!condition() && pumps < maxPumps) {
    await tester.pump(const Duration(milliseconds: 50));
    pumps++;
  }
}

Future<void> pumpUntilAsyncWorkSettles(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 200,
}) async {
  var pumps = 0;
  while (!condition() && pumps < maxPumps) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump(const Duration(milliseconds: 50));
    pumps++;
  }
}

int _logIndex(List<String> operationLog, String entry) {
  final index = operationLog.indexOf(entry);
  expect(index, isNot(-1), reason: 'Expected "$entry" in $operationLog');
  return index;
}

void _expectOrdered(List<String> operationLog, String earlier, String later) {
  expect(
    _logIndex(operationLog, earlier),
    lessThan(_logIndex(operationLog, later)),
    reason: 'Expected "$earlier" before "$later" in $operationLog',
  );
}

MediaAttachment _uploadedMedia({
  required String id,
  required String messageId,
  required String mime,
  required String localPath,
  int? width,
  int? height,
  int? durationMs,
  List<double>? waveform,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 1,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: localPath,
    downloadStatus: 'done',
    width: width,
    height: height,
    durationMs: durationMs,
    waveform: waveform,
    contentHash:
        '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
    encryptionKeyBase64: 'key-$id',
    encryptionNonce: 'nonce-$id',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

Future<void> _pumpGroupConversationWired(
  WidgetTester tester, {
  required Bridge bridge,
  InMemoryGroupRepository? groupRepo,
  InMemoryGroupMessageRepository? msgRepo,
  InMemoryMediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  AudioRecorderService? audioRecorderService,
  UploadMediaFn? uploadMediaFn,
  List<File>? initialAttachments,
  GroupModel? group,
}) async {
  final controller = StreamController<GroupMessage>.broadcast();
  addTearDown(() async {
    await controller.close();
  });

  final effectiveGroup = group ?? _makeChatGroup();
  final effectiveGroupRepo = groupRepo ?? InMemoryGroupRepository();
  final effectiveMsgRepo = msgRepo ?? InMemoryGroupMessageRepository();
  final effectiveMediaRepo =
      mediaAttachmentRepo ?? InMemoryMediaAttachmentRepository();

  await effectiveGroupRepo.saveGroup(effectiveGroup);
  if (await effectiveGroupRepo.getLatestKey(effectiveGroup.id) == null) {
    await effectiveGroupRepo.saveKey(
      GroupKeyInfo(
        groupId: effectiveGroup.id,
        keyGeneration: 1,
        encryptedKey: 'test-group-key-1',
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }
  await effectiveGroupRepo.saveMember(
    GroupMember(
      groupId: effectiveGroup.id,
      peerId: _testIdentity.peerId,
      username: _testIdentity.username,
      role: effectiveGroup.myRole == GroupRole.admin
          ? MemberRole.admin
          : MemberRole.writer,
      publicKey: _testIdentity.publicKey,
      joinedAt: DateTime.now().toUtc(),
    ),
  );
  await effectiveGroupRepo.saveMember(
    GroupMember(
      groupId: effectiveGroup.id,
      peerId: 'peer-ally',
      username: 'Ally',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupConversationWired(
        group: effectiveGroup,
        groupRepo: effectiveGroupRepo,
        msgRepo: effectiveMsgRepo,
        groupMessageListener: _FakeGroupMessageListener(controller.stream),
        bridge: bridge,
        identityRepo: _FakeIdentityRepository(_testIdentity),
        contactRepo: InMemoryContactRepository(),
        p2pService: FakeP2PService(),
        mediaAttachmentRepo: effectiveMediaRepo,
        mediaFileManager: mediaFileManager,
        audioRecorderService: audioRecorderService,
        uploadMediaFn: uploadMediaFn ?? uploadMedia,
        initialAttachments: initialAttachments,
      ),
    ),
  );
  await pumpFrames(tester, count: 10);
}

class _StartedTextSend {
  const _StartedTextSend(this.future);

  final Future<void> future;
}

Future<_StartedTextSend> _startTextSend(
  WidgetTester tester,
  String text,
) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  final screen = tester.widget<GroupConversationScreen>(
    find.byType(GroupConversationScreen),
  );
  final send = screen.onSend as Future<void> Function(String);
  late Future<void> sendFuture;
  await tester.runAsync(() async {
    sendFuture = send(text);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump();
  return _StartedTextSend(sendFuture);
}

Future<void> _sendText(WidgetTester tester, String text) async {
  await _startTextSend(tester, text);
}

Map<String, dynamic> _decodeReplayPayload(Map<String, dynamic> inboxPayload) {
  final envelope =
      jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
  final ciphertext = envelope['ciphertext'];
  if (envelope['kind'] == 'group_offline_replay' && ciphertext is String) {
    return jsonDecode(ciphertext) as Map<String, dynamic>;
  }
  return envelope;
}

void main() {
  setUp(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  tearDown(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  group('GroupConversationWired Section 3 background-task protection', () {
    testWidgets(
      'bg:begin happens before media upload and bg:end happens after publish and inbox store',
      (tester) async {
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(operationLog: operationLog);
        final tempDir = Directory.systemTemp.createTempSync('group-bg-media-');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File(p.join(tempDir.path, 'photo.jpg'))
          ..writeAsStringSync('image');

        await _pumpGroupConversationWired(
          tester,
          bridge: bridge,
          mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
          mediaFileManager: FakeMediaFileManager(),
          initialAttachments: [attachment],
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
              }) async {
                operationLog.add('uploadMediaFn');
                return _uploadedMedia(
                  id: blobId ?? 'blob-1',
                  messageId: '',
                  mime: mime,
                  localPath: mediaFileManager!.relativePathForAttachment(
                    contactPeerId: 'group-1',
                    blobId: blobId ?? 'blob-1',
                    mime: mime,
                  ),
                );
              },
        );

        await _sendText(tester, 'hello');
        await pumpUntilAsyncWorkSettles(
          tester,
          () => operationLog.contains('bridge:bg:end'),
        );

        _expectOrdered(operationLog, 'bridge:bg:begin', 'uploadMediaFn');
        _expectOrdered(operationLog, 'uploadMediaFn', 'bridge:group:publish');
        _expectOrdered(
          operationLog,
          'bridge:group:publish',
          'bridge:group:inboxStore',
        );
        _expectOrdered(
          operationLog,
          'bridge:group:inboxStore',
          'bridge:bg:end',
        );
      },
    );

    testWidgets('bg:end fires on media upload failure early return', (
      tester,
    ) async {
      final bridge = _OrderRecordingBridge();
      final tempDir = Directory.systemTemp.createTempSync('group-bg-fail-');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File(p.join(tempDir.path, 'photo.jpg'))
        ..writeAsStringSync('image');

      await _pumpGroupConversationWired(
        tester,
        bridge: bridge,
        mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
        mediaFileManager: FakeMediaFileManager(),
        initialAttachments: [attachment],
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
            }) async => null,
      );

      await _sendText(tester, 'upload fail');
      await pumpUntil(tester, () => bridge.commandLog.contains('bg:end'));

      expect(bridge.commandLog, contains('bg:begin'));
      expect(bridge.commandLog, contains('bg:end'));
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    });

    testWidgets('bg:end fires when upload throws', (tester) async {
      final bridge = _OrderRecordingBridge();
      final tempDir = Directory.systemTemp.createTempSync('group-bg-throw-');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File(p.join(tempDir.path, 'photo.jpg'))
        ..writeAsStringSync('image');

      await _pumpGroupConversationWired(
        tester,
        bridge: bridge,
        mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
        mediaFileManager: FakeMediaFileManager(),
        initialAttachments: [attachment],
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
            }) async {
              throw Exception('upload failed');
            },
      );

      await _sendText(tester, 'upload throws');
      await pumpUntilAsyncWorkSettles(
        tester,
        () => bridge.commandLog.contains('bg:end'),
      );

      expect(bridge.commandLog, contains('bg:begin'));
      expect(bridge.commandLog, contains('bg:end'));
      expect(bridge.commandLog, isNot(contains('group:publish')));
    });

    testWidgets('send proceeds normally when OS refuses background task', (
      tester,
    ) async {
      final bridge = _OrderRecordingBridge(bgBeginResponse: '');
      final msgRepo = InMemoryGroupMessageRepository();

      await _pumpGroupConversationWired(
        tester,
        bridge: bridge,
        msgRepo: msgRepo,
      );

      await _sendText(tester, 'no bg');
      await pumpFrames(tester, count: 20);

      final saved = await msgRepo.getLatestMessage('group-1');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(bridge.commandLog, contains('bg:begin'));
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));
      expect(bridge.commandLog, isNot(contains('bg:end')));
    });

    testWidgets('bg:end fires when widget unmounts mid-send', (tester) async {
      final inboxGate = Completer<void>();
      final bridge = _OrderRecordingBridge(
        commandGates: {'group:inboxStore': inboxGate},
      );

      await _pumpGroupConversationWired(tester, bridge: bridge);

      await _sendText(tester, 'unmount');
      await pumpUntil(
        tester,
        () => bridge.commandLog.contains('group:inboxStore'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      inboxGate.complete();
      await pumpFrames(tester, count: 20);

      expect(bridge.commandLog, contains('bg:end'));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'ordinary media upload failure after unmount still persists failed parent status',
      (tester) async {
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        final bridge = _OrderRecordingBridge();
        final msgRepo = InMemoryGroupMessageRepository();
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final mediaFileManager = FakeMediaFileManager();
        final tempDir = Directory.systemTemp.createTempSync(
          'group-bg-unmount-media-fail-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File(p.join(tempDir.path, 'photo.jpg'))
          ..writeAsStringSync('image');

        await _pumpGroupConversationWired(
          tester,
          bridge: bridge,
          msgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: mediaFileManager,
          initialAttachments: [attachment],
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
              }) async {
                if (!uploadStarted.isCompleted) {
                  uploadStarted.complete();
                }
                await uploadGate.future;
                return null;
              },
        );

        final sendFuture = await _startTextSend(tester, 'unmount media fail');
        await pumpUntil(tester, () => uploadStarted.isCompleted);
        await pumpFrames(tester, count: 5);

        final messageId =
            (await mediaRepo.getUploadPendingAttachments()).single.messageId;
        final persistedBeforeUnmount = await msgRepo.getMessage(messageId);
        expect(persistedBeforeUnmount, isNotNull);
        expect(persistedBeforeUnmount!.status, 'sending');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        uploadGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 20);

        final persistedAfterFail = await msgRepo.getMessage(messageId);
        expect(persistedAfterFail, isNotNull);
        expect(persistedAfterFail!.status, 'failed');
        expect(bridge.commandLog, contains('bg:end'));
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('text-only send acquires background task before publish', (
      tester,
    ) async {
      final operationLog = <String>[];
      final bridge = _OrderRecordingBridge(operationLog: operationLog);

      await _pumpGroupConversationWired(tester, bridge: bridge);

      await _sendText(tester, 'text only');
      await pumpFrames(tester, count: 20);

      _expectOrdered(operationLog, 'bridge:bg:begin', 'bridge:group:publish');
      _expectOrdered(
        operationLog,
        'bridge:group:publish',
        'bridge:group:inboxStore',
      );
      _expectOrdered(operationLog, 'bridge:group:inboxStore', 'bridge:bg:end');
    });

    testWidgets('voice send path is background-task protected', (tester) async {
      final operationLog = <String>[];
      final bridge = _OrderRecordingBridge(operationLog: operationLog);
      final mediaFileManager = FakeMediaFileManager();
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 1200
        ..fakeSizeBytes = 32000;
      final tempDir = Directory.systemTemp.createTempSync('group-voice-bg-');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final voiceFile = File(p.join(tempDir.path, 'voice.m4a'))
        ..writeAsStringSync('voice');
      recorder.fakeOutputPath = voiceFile.path;

      await _pumpGroupConversationWired(
        tester,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: mediaFileManager,
        audioRecorderService: recorder,
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
            }) async {
              operationLog.add('uploadMediaFn');
              return _uploadedMedia(
                id: blobId ?? 'voice-1',
                messageId: '',
                mime: mime,
                localPath: mediaFileManager!.relativePathForAttachment(
                  contactPeerId: recipientPeerId,
                  blobId: blobId ?? 'voice-1',
                  mime: mime,
                ),
                durationMs: durationMs,
                waveform: waveform,
              );
            },
      );

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
      await tester.runAsync(() async {
        await stopRecording();
      });
      await pumpFrames(tester, count: 20);

      _expectOrdered(operationLog, 'bridge:bg:begin', 'uploadMediaFn');
      _expectOrdered(operationLog, 'uploadMediaFn', 'bridge:group:publish');
      _expectOrdered(operationLog, 'bridge:group:inboxStore', 'bridge:bg:end');
    });

    testWidgets(
      'announcement voice-only send uses durable path, omits plaintext push body, and sent status when no peers are live',
      (tester) async {
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(
          operationLog: operationLog,
          publishMessageId: 'msg-announce-voice-zero',
          publishTopicPeers: 0,
        );
        final mediaFileManager = FakeMediaFileManager();
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1400
          ..fakeSizeBytes = 36000;
        final tempDir = Directory.systemTemp.createTempSync(
          'group-announce-voice-bg-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final voiceFile = File(p.join(tempDir.path, 'announce-voice.m4a'))
          ..writeAsStringSync('voice');
        recorder.fakeOutputPath = voiceFile.path;

        await _pumpGroupConversationWired(
          tester,
          bridge: bridge,
          msgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: mediaFileManager,
          audioRecorderService: recorder,
          group: _makeAnnouncementGroup(role: GroupRole.admin),
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
              }) async {
                operationLog.add('uploadMediaFn');
                return _uploadedMedia(
                  id: blobId ?? 'announce-voice-1',
                  messageId: '',
                  mime: mime,
                  localPath: mediaFileManager!.relativePathForAttachment(
                    contactPeerId: recipientPeerId,
                    blobId: blobId ?? 'announce-voice-1',
                    mime: mime,
                  ),
                  durationMs: durationMs,
                  waveform: waveform,
                );
              },
        );

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
        await tester.runAsync(() async {
          await stopRecording();
        });
        await pumpFrames(tester, count: 20);

        _expectOrdered(operationLog, 'bridge:bg:begin', 'uploadMediaFn');
        _expectOrdered(operationLog, 'uploadMediaFn', 'bridge:group:publish');
        _expectOrdered(
          operationLog,
          'bridge:group:inboxStore',
          'bridge:bg:end',
        );

        final inboxMessage = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        final inboxPayload =
            (jsonDecode(inboxMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(inboxPayload.containsKey('pushTitle'), isFalse);
        expect(inboxPayload.containsKey('pushBody'), isFalse);
        final innerEnvelope = _decodeReplayPayload(inboxPayload);
        expect(innerEnvelope['text'], isEmpty);

        final publishMessage = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sentMessageId = publishPayload['messageId'] as String;

        final saved = await msgRepo.getMessage(sentMessageId);
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
      },
    );

    testWidgets(
      'ordinary group text send stays bg-task protected across lock/unmount with peers',
      (tester) async {
        final inboxGate = Completer<void>();
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(
          operationLog: operationLog,
          publishMessageId: 'msg-group-online',
          publishTopicPeers: 2,
          commandGates: {'group:inboxStore': inboxGate},
        );
        final msgRepo = InMemoryGroupMessageRepository();

        await _pumpGroupConversationWired(
          tester,
          bridge: bridge,
          msgRepo: msgRepo,
        );

        final sendFuture = await _startTextSend(tester, 'Group online');
        await pumpUntil(
          tester,
          () => bridge.commandLog.contains('group:inboxStore'),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        inboxGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 20);

        _expectOrdered(operationLog, 'bridge:bg:begin', 'bridge:group:publish');
        _expectOrdered(
          operationLog,
          'bridge:group:publish',
          'bridge:group:inboxStore',
        );
        _expectOrdered(
          operationLog,
          'bridge:group:inboxStore',
          'bridge:bg:end',
        );

        final publishMessage = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sentMessageId = publishPayload['messageId'] as String;

        final saved = await msgRepo.getMessage(sentMessageId);
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.text, 'Group online');
      },
    );

    testWidgets(
      'ordinary group text send returns sent after lock/unmount when topic peers are zero',
      (tester) async {
        final inboxGate = Completer<void>();
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(
          operationLog: operationLog,
          publishMessageId: 'msg-group-zero-peers',
          publishTopicPeers: 0,
          commandGates: {'group:inboxStore': inboxGate},
        );
        final msgRepo = InMemoryGroupMessageRepository();

        await _pumpGroupConversationWired(
          tester,
          bridge: bridge,
          msgRepo: msgRepo,
        );

        final sendFuture = await _startTextSend(tester, 'Group offline');
        await pumpUntil(
          tester,
          () => bridge.commandLog.contains('group:inboxStore'),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        inboxGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 20);

        _expectOrdered(operationLog, 'bridge:bg:begin', 'bridge:group:publish');
        _expectOrdered(
          operationLog,
          'bridge:group:inboxStore',
          'bridge:bg:end',
        );

        final publishMessage = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sentMessageId = publishPayload['messageId'] as String;

        final saved = await msgRepo.getMessage(sentMessageId);
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isTrue);
        expect(saved.text, 'Group offline');
      },
    );

    testWidgets(
      'announcement admin text send stays bg-task protected across lock/unmount with peers',
      (tester) async {
        final inboxGate = Completer<void>();
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(
          operationLog: operationLog,
          publishMessageId: 'msg-announce-online',
          publishTopicPeers: 2,
          commandGates: {'group:inboxStore': inboxGate},
        );
        final msgRepo = InMemoryGroupMessageRepository();

        await _pumpGroupConversationWired(
          tester,
          bridge: bridge,
          msgRepo: msgRepo,
          group: _makeAnnouncementGroup(role: GroupRole.admin),
        );

        final sendFuture = await _startTextSend(tester, 'Announcement online');
        await pumpUntil(
          tester,
          () => bridge.commandLog.contains('group:inboxStore'),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        inboxGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 20);

        _expectOrdered(operationLog, 'bridge:bg:begin', 'bridge:group:publish');
        _expectOrdered(
          operationLog,
          'bridge:group:publish',
          'bridge:group:inboxStore',
        );
        _expectOrdered(
          operationLog,
          'bridge:group:inboxStore',
          'bridge:bg:end',
        );

        final publishMessage = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sentMessageId = publishPayload['messageId'] as String;

        final saved = await msgRepo.getMessage(sentMessageId);
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.text, 'Announcement online');
      },
    );

    testWidgets(
      'announcement admin text send returns sent after lock/unmount when topic peers are zero',
      (tester) async {
        final inboxGate = Completer<void>();
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(
          operationLog: operationLog,
          publishMessageId: 'msg-announce-zero-peers',
          publishTopicPeers: 0,
          commandGates: {'group:inboxStore': inboxGate},
        );
        final msgRepo = InMemoryGroupMessageRepository();

        await _pumpGroupConversationWired(
          tester,
          bridge: bridge,
          msgRepo: msgRepo,
          group: _makeAnnouncementGroup(role: GroupRole.admin),
        );

        final sendFuture = await _startTextSend(tester, 'Announcement offline');
        await pumpUntil(
          tester,
          () => bridge.commandLog.contains('group:inboxStore'),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        inboxGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 20);

        _expectOrdered(operationLog, 'bridge:bg:begin', 'bridge:group:publish');
        _expectOrdered(
          operationLog,
          'bridge:group:inboxStore',
          'bridge:bg:end',
        );

        final publishMessage = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sentMessageId = publishPayload['messageId'] as String;

        final saved = await msgRepo.getMessage(sentMessageId);
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isTrue);
      },
    );

    testWidgets(
      'announcement media send preserves messageId, key epoch, and media metadata through wired path',
      (tester) async {
        final operationLog = <String>[];
        String? uploadedBlobId;
        final bridge = _OrderRecordingBridge(
          operationLog: operationLog,
          publishMessageId: 'msg-announce-media',
          publishTopicPeers: 1,
        );
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final mediaRepo = InMemoryMediaAttachmentRepository();
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 7,
            encryptedKey: 'k7',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final tempDir = Directory.systemTemp.createTempSync(
          'group-announce-media-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File(p.join(tempDir.path, 'announce.jpg'))
          ..writeAsStringSync('image');

        await _pumpGroupConversationWired(
          tester,
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          initialAttachments: [attachment],
          group: _makeAnnouncementGroup(role: GroupRole.admin),
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
              }) async {
                operationLog.add('uploadMediaFn');
                uploadedBlobId = blobId;
                return _uploadedMedia(
                  id: blobId ?? 'att-announce-media',
                  messageId: '',
                  mime: mime,
                  localPath: mediaFileManager!.relativePathForAttachment(
                    contactPeerId: 'group-1',
                    blobId: blobId ?? 'att-announce-media',
                    mime: mime,
                  ),
                  width: 1080,
                  height: 720,
                );
              },
        );

        await _sendText(tester, 'Photo update');
        await pumpUntilAsyncWorkSettles(
          tester,
          () => operationLog.contains('bridge:bg:end'),
        );

        _expectOrdered(operationLog, 'bridge:bg:begin', 'uploadMediaFn');
        _expectOrdered(operationLog, 'uploadMediaFn', 'bridge:group:publish');
        _expectOrdered(
          operationLog,
          'bridge:group:inboxStore',
          'bridge:bg:end',
        );

        final publishMessage = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sentMessageId = publishPayload['messageId'] as String;
        expect(sentMessageId, isNotEmpty);
        final publishMedia =
            (publishPayload['media'] as List).single as Map<String, dynamic>;
        expect(uploadedBlobId, isNotNull);
        expect(publishMedia['id'], uploadedBlobId);
        expect(publishMedia['width'], 1080);
        expect(publishMedia['height'], 720);

        final inboxMessage = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        final inboxPayload =
            (jsonDecode(inboxMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope['messageId'], sentMessageId);
        expect(replayEnvelope['keyEpoch'], 7);
        final inboxEnvelope = _decodeReplayPayload(inboxPayload);
        final inboxMedia =
            (inboxEnvelope['media'] as List).single as Map<String, dynamic>;
        expect(inboxMedia['id'], uploadedBlobId);
        expect(inboxMedia['width'], 1080);
        expect(inboxMedia['height'], 720);

        final saved = await msgRepo.getMessage(sentMessageId);
        expect(saved, isNotNull);
        expect(saved!.keyGeneration, 7);
        expect(saved.status, 'sent');

        final savedAttachments = await mediaRepo.getAttachmentsForMessage(
          sentMessageId,
        );
        expect(
          savedAttachments.any((attachment) => attachment.id == uploadedBlobId),
          isTrue,
        );
      },
    );

    testWidgets('order-recording bridge proves no early cleanup', (
      tester,
    ) async {
      final inboxGate = Completer<void>();
      final operationLog = <String>[];
      final bridge = _OrderRecordingBridge(
        operationLog: operationLog,
        commandGates: {'group:inboxStore': inboxGate},
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'group-bg-order-proof-',
      );
      addTearDown(() {
        if (!inboxGate.isCompleted) {
          inboxGate.complete();
        }
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File(p.join(tempDir.path, 'photo.jpg'))
        ..writeAsStringSync('image');

      await _pumpGroupConversationWired(
        tester,
        bridge: bridge,
        mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
        mediaFileManager: FakeMediaFileManager(),
        initialAttachments: [attachment],
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
            }) async {
              operationLog.add('uploadMediaFn');
              return _uploadedMedia(
                id: blobId ?? 'blob-1',
                messageId: '',
                mime: mime,
                localPath: mediaFileManager!.relativePathForAttachment(
                  contactPeerId: 'group-1',
                  blobId: blobId ?? 'blob-1',
                  mime: mime,
                ),
              );
            },
      );

      await _sendText(tester, 'proof');
      await pumpUntilAsyncWorkSettles(
        tester,
        () => operationLog.contains('bridge:group:inboxStore'),
      );

      _expectOrdered(operationLog, 'bridge:bg:begin', 'uploadMediaFn');

      await pumpUntilAsyncWorkSettles(
        tester,
        () => operationLog.contains('bridge:bg:end'),
      );
      expect(inboxGate.isCompleted, isFalse);
      inboxGate.complete();
      await pumpFrames(tester, count: 5);

      _expectOrdered(operationLog, 'uploadMediaFn', 'bridge:group:publish');
      _expectOrdered(
        operationLog,
        'bridge:group:publish',
        'bridge:group:inboxStore',
      );
      _expectOrdered(operationLog, 'bridge:group:inboxStore', 'bridge:bg:end');
    });
  });
}
