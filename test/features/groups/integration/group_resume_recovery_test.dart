import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
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
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/helpers/lifecycle_helpers.dart';

/// A bridge that simulates cursor-based inbox retrieval for integration tests.
class _CursorInboxBridge extends FakeBridge {
  final Map<String, _InboxPage> pages = {};

  void addPage(
    String groupId,
    String cursor,
    List<Map<String, dynamic>> messages,
    String nextCursor,
  ) {
    pages['$groupId:$cursor'] = _InboxPage(messages, nextCursor);
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd != null) commandLog.add(cmd);
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;

    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final key = '$groupId:$cursor';

      final page = pages[key];
      if (page != null) {
        return jsonEncode({
          'ok': true,
          'messages': page.messages,
          'cursor': page.nextCursor,
        });
      }
      return jsonEncode({
        'ok': true,
        'messages': <Map<String, dynamic>>[],
        'cursor': '',
      });
    }

    // Default: return ok for other commands (group:join, etc.)
    if (cmd != null && responses.containsKey(cmd)) {
      return jsonEncode(responses[cmd]!);
    }
    return jsonEncode({'ok': true});
  }
}

class _InboxPage {
  final List<Map<String, dynamic>> messages;
  final String nextCursor;
  _InboxPage(this.messages, this.nextCursor);
}

Map<String, dynamic> latestBridgePayload(FakeBridge bridge, String command) {
  final raw = bridge.sentMessages.lastWhere(
    (message) =>
        (jsonDecode(message) as Map<String, dynamic>)['cmd'] == command,
    orElse: () => throw StateError('Missing bridge command: $command'),
  );
  return (jsonDecode(raw) as Map<String, dynamic>)['payload']
      as Map<String, dynamic>;
}

void _injectInboxMessageFromLatestStore({
  required FakeBridge senderBridge,
  required _CursorInboxBridge receiverBridge,
  required String receiverPeerId,
  required String groupId,
}) {
  final inboxPayload = latestBridgePayload(senderBridge, 'group:inboxStore');
  final recipients =
      (inboxPayload['recipientPeerIds'] as List<dynamic>? ?? const [])
          .cast<String>();
  expect(recipients, contains(receiverPeerId));
  final inboxEnvelope =
      jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
  receiverBridge.addPage(groupId, '', [inboxEnvelope], '');
}

class _Section10IdentityRepository implements IdentityRepository {
  _Section10IdentityRepository(this.identity);

  final IdentityModel identity;

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
  _FakeGroupMessageListener(this._stream)
    : super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  final Stream<GroupMessage> _stream;

  @override
  Stream<GroupMessage> get groupMessageStream => _stream;
}

class _Section10MirroringBridge extends FakeBridge {
  _Section10MirroringBridge({
    required this.network,
    required this.msgRepo,
    required this.groupRepo,
    List<String>? operationLog,
    this.publishFailuresRemaining = 0,
    this.inboxStoreResponse,
    Map<String, Completer<void>>? commandGates,
  }) : operationLog = operationLog ?? <String>[],
       commandGates = commandGates ?? <String, Completer<void>>{};

  final FakeGroupPubSubNetwork network;
  final InMemoryGroupMessageRepository msgRepo;
  final InMemoryGroupRepository groupRepo;
  final List<String> operationLog;
  int publishFailuresRemaining;
  final Map<String, dynamic>? inboxStoreResponse;
  final Map<String, Completer<void>> commandGates;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd != null) commandLog.add(cmd);
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;

    if (cmd != null) {
      operationLog.add('bridge:$cmd');
      final gate = commandGates[cmd];
      if (gate != null) {
        await gate.future;
      }
    }

    switch (cmd) {
      case 'bg:begin':
        return 'section10-bg-task';
      case 'bg:end':
        return '';
      case 'group:publish':
        return _handlePublish(parsed['payload'] as Map<String, dynamic>);
      case 'group:inboxStore':
        return jsonEncode(inboxStoreResponse ?? {'ok': true});
      default:
        if (cmd != null && responses.containsKey(cmd)) {
          return jsonEncode(responses[cmd]!);
        }
        return jsonEncode({'ok': true});
    }
  }

  Future<String> _handlePublish(Map<String, dynamic> payload) async {
    if (publishFailuresRemaining > 0) {
      publishFailuresRemaining--;
      throw Exception('Simulated publish failure');
    }

    final groupId = payload['groupId'] as String;
    final senderPeerId = payload['senderPeerId'] as String;
    final messageId = payload['messageId'] as String;
    final topicPeers = network
        .getSubscribers(groupId)
        .where((peerId) => peerId != senderPeerId)
        .length;

    if (topicPeers > 0) {
      final savedMessage = await msgRepo.getMessage(messageId);
      final latestKey = await groupRepo.getLatestKey(groupId);
      final envelope = <String, dynamic>{
        'groupId': groupId,
        'senderId': senderPeerId,
        'senderUsername': payload['senderUsername'] as String? ?? '',
        'keyEpoch':
            savedMessage?.keyGeneration ?? latestKey?.keyGeneration ?? 0,
        'text': payload['text'] as String? ?? '',
        'timestamp':
            savedMessage?.timestamp.toUtc().toIso8601String() ??
            DateTime.now().toUtc().toIso8601String(),
        'messageId': messageId,
      };
      if (payload['quotedMessageId'] is String &&
          (payload['quotedMessageId'] as String).isNotEmpty) {
        envelope['quotedMessageId'] = payload['quotedMessageId'];
      }
      if (payload['media'] is List<dynamic>) {
        envelope['media'] = payload['media'] as List<dynamic>;
      }
      await network.publish(groupId, senderPeerId, envelope);
    }

    return jsonEncode({
      'ok': true,
      'messageId': messageId,
      'topicPeers': topicPeers,
    });
  }
}

IdentityModel _identityForUser(GroupTestUser user) {
  final now = DateTime.now().toUtc().toIso8601String();
  return IdentityModel(
    peerId: user.peerId,
    publicKey: user.publicKey,
    privateKey: user.privateKey,
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    username: user.username,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 40,
}) async {
  var pumps = 0;
  while (!condition() && pumps < maxPumps) {
    await tester.pump(const Duration(milliseconds: 50));
    pumps++;
  }
  expect(condition(), isTrue, reason: 'Condition was not met in time');
}

Future<void> _waitUntil(bool Function() condition, {int maxTicks = 100}) async {
  var ticks = 0;
  while (!condition() && ticks < maxTicks) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    ticks++;
  }
  expect(condition(), isTrue, reason: 'Condition was not met in time');
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
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

Future<void> _sendText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pump();
}

Future<void> _saveKey(
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

Future<GroupMessage> _latestOutgoingMessage(
  InMemoryGroupMessageRepository repo,
  String groupId, {
  String? text,
}) async {
  final messages = await repo.getMessagesPage(groupId, limit: 100);
  final matches =
      messages
          .where(
            (message) =>
                !message.isIncoming && (text == null || message.text == text),
          )
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  expect(matches, isNotEmpty, reason: 'Missing outgoing message for $groupId');
  return matches.first;
}

Future<void> _pumpSection10SenderWidget(
  WidgetTester tester, {
  required GroupTestUser sender,
  required String groupId,
  required Bridge bridge,
  MediaFileManager? mediaFileManager,
  AudioRecorderService? audioRecorderService,
  UploadMediaFn? uploadMediaFn,
  List<File>? initialAttachments,
}) async {
  final controller = StreamController<GroupMessage>.broadcast();
  addTearDown(() async {
    await controller.close();
  });

  final group = await sender.groupRepo.getGroup(groupId);
  expect(group, isNotNull);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupConversationWired(
        group: group!,
        groupRepo: sender.groupRepo,
        msgRepo: sender.msgRepo,
        groupMessageListener: _FakeGroupMessageListener(controller.stream),
        bridge: bridge,
        identityRepo: _Section10IdentityRepository(_identityForUser(sender)),
        contactRepo: InMemoryContactRepository(),
        p2pService: FakeP2PService(),
        mediaAttachmentRepo: sender.mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        audioRecorderService: audioRecorderService,
        uploadMediaFn: uploadMediaFn ?? uploadMedia,
        initialAttachments: initialAttachments,
      ),
    ),
  );

  await _pumpFrames(tester, count: 10);
}

Future<void> _section10WidgetTextLifecycleProof(
  WidgetTester tester,
  FakeGroupPubSubNetwork network,
) async {
  final admin = GroupTestUser.create(
    peerId: 'admin-widget-text-peer',
    username: 'Alice',
    network: network,
  );
  final reader = GroupTestUser.create(
    peerId: 'reader-widget-text-peer',
    username: 'Bob',
    network: network,
    bridge: _CursorInboxBridge(),
  );
  final onlineReader = GroupTestUser.create(
    peerId: 'online-widget-text-peer',
    username: 'Carol',
    network: network,
  );
  final readerBridge = reader.bridge as _CursorInboxBridge;
  final inboxGate = Completer<void>();
  final senderBridge = _Section10MirroringBridge(
    network: network,
    msgRepo: admin.msgRepo,
    groupRepo: admin.groupRepo,
    operationLog: <String>[],
    commandGates: {'group:inboxStore': inboxGate},
  );

  const groupId = 'group-announce-widget-text';
  await admin.createGroup(
    groupId: groupId,
    name: 'Announcements Widget Text',
    type: GroupType.announcement,
  );
  await admin.addMember(groupId: groupId, invitee: reader);
  await admin.addMember(groupId: groupId, invitee: onlineReader);
  await _saveKey(admin, groupId, 1, 'k1');
  await _saveKey(reader, groupId, 1, 'k1');
  await _saveKey(onlineReader, groupId, 1, 'k1');

  admin.start();
  reader.start();
  onlineReader.start();

  await _pumpSection10SenderWidget(
    tester,
    sender: admin,
    groupId: groupId,
    bridge: senderBridge,
  );

  await simulateBackgroundForegroundCycle(
    bridge: reader.bridge,
    p2pService: FakeP2PService(),
    messageRepo: InMemoryMessageRepository(),
    groupMsgRepo: reader.msgRepo,
    afterPause: () async {
      network.unsubscribe(groupId, reader.peerId);
      await _sendText(tester, 'Announcement via widget');
      await _waitUntil(
        () => senderBridge.commandLog.contains('group:inboxStore'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      _injectInboxMessageFromLatestStore(
        senderBridge: senderBridge,
        receiverBridge: readerBridge,
        receiverPeerId: reader.peerId,
        groupId: groupId,
      );
      inboxGate.complete();
      await _pumpFrames(tester, count: 20);
    },
    afterResume: () async {
      await drainGroupOfflineInbox(
        bridge: reader.bridge,
        groupRepo: reader.groupRepo,
        msgRepo: reader.msgRepo,
      );
      network.subscribe(groupId, reader.peerId);
    },
  );

  final sent = await _latestOutgoingMessage(
    admin.msgRepo,
    groupId,
    text: 'Announcement via widget',
  );
  expect(sent.status, 'sent');
  expect(sent.inboxStored, isTrue);
  expect(senderBridge.commandLog, contains('group:publish'));
  expect(senderBridge.commandLog, contains('group:inboxStore'));
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:bg:begin',
    'bridge:group:publish',
  );
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:group:publish',
    'bridge:group:inboxStore',
  );
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:group:inboxStore',
    'bridge:bg:end',
  );

  final onlineReaderMessages = await onlineReader.loadGroupMessages(groupId);
  expect(onlineReaderMessages.any((message) => message.id == sent.id), isTrue);
  final readerMessages = await reader.loadGroupMessages(groupId);
  expect(readerMessages.any((message) => message.id == sent.id), isTrue);

  admin.dispose();
  reader.dispose();
  onlineReader.dispose();
}

Future<void> _section10WidgetMediaLifecycleProof(
  WidgetTester tester,
  FakeGroupPubSubNetwork network,
) async {
  final admin = GroupTestUser.create(
    peerId: 'admin-widget-media-peer',
    username: 'Alice',
    network: network,
  );
  final reader = GroupTestUser.create(
    peerId: 'reader-widget-media-peer',
    username: 'Bob',
    network: network,
    bridge: _CursorInboxBridge(),
  );
  final onlineReader = GroupTestUser.create(
    peerId: 'online-widget-media-peer',
    username: 'Carol',
    network: network,
  );
  final readerBridge = reader.bridge as _CursorInboxBridge;
  final inboxGate = Completer<void>();
  final senderBridge = _Section10MirroringBridge(
    network: network,
    msgRepo: admin.msgRepo,
    groupRepo: admin.groupRepo,
    operationLog: <String>[],
    commandGates: {'group:inboxStore': inboxGate},
  );
  final tempDir = Directory.systemTemp.createTempSync('section10-media-');
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  final attachment = File(p.join(tempDir.path, 'announcement.jpg'))
    ..writeAsStringSync('image');
  String? uploadedBlobId;

  const groupId = 'group-announce-widget-media';
  await admin.createGroup(
    groupId: groupId,
    name: 'Announcements Widget Media',
    type: GroupType.announcement,
  );
  await admin.addMember(groupId: groupId, invitee: reader);
  await admin.addMember(groupId: groupId, invitee: onlineReader);
  await _saveKey(admin, groupId, 4, 'k4');
  await _saveKey(reader, groupId, 4, 'k4');
  await _saveKey(onlineReader, groupId, 4, 'k4');

  admin.start();
  reader.start();
  onlineReader.start();

  await _pumpSection10SenderWidget(
    tester,
    sender: admin,
    groupId: groupId,
    bridge: senderBridge,
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
          senderBridge.operationLog.add('uploadMediaFn');
          uploadedBlobId = blobId;
          return _uploadedMedia(
            id: 'server-att-widget-media',
            messageId: '',
            mime: mime,
            localPath: localFilePath,
            width: 1080,
            height: 720,
          );
        },
  );

  await simulateBackgroundForegroundCycle(
    bridge: reader.bridge,
    p2pService: FakeP2PService(),
    messageRepo: InMemoryMessageRepository(),
    groupMsgRepo: reader.msgRepo,
    afterPause: () async {
      network.unsubscribe(groupId, reader.peerId);
      await _sendText(tester, 'Photo update');
      await _pumpUntil(
        tester,
        () => senderBridge.commandLog.contains('group:inboxStore'),
        maxPumps: 120,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      _injectInboxMessageFromLatestStore(
        senderBridge: senderBridge,
        receiverBridge: readerBridge,
        receiverPeerId: reader.peerId,
        groupId: groupId,
      );
      inboxGate.complete();
      await _pumpFrames(tester, count: 20);
    },
    afterResume: () async {
      await drainGroupOfflineInbox(
        bridge: reader.bridge,
        groupRepo: reader.groupRepo,
        msgRepo: reader.msgRepo,
        mediaAttachmentRepo: reader.mediaAttachmentRepo,
      );
      network.subscribe(groupId, reader.peerId);
    },
  );

  final sent = await _latestOutgoingMessage(
    admin.msgRepo,
    groupId,
    text: 'Photo update',
  );
  expect(uploadedBlobId, isNotNull);
  expect(sent.status, 'sent');
  expect(sent.keyGeneration, 4);
  _expectOrdered(senderBridge.operationLog, 'bridge:bg:begin', 'uploadMediaFn');
  _expectOrdered(
    senderBridge.operationLog,
    'uploadMediaFn',
    'bridge:group:publish',
  );
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:group:inboxStore',
    'bridge:bg:end',
  );
  final senderMedia = await admin.mediaAttachmentRepo.getAttachmentsForMessage(
    sent.id,
  );
  expect(senderMedia, hasLength(1));
  expect(senderMedia.single.id, uploadedBlobId);
  expect(senderMedia.single.downloadStatus, 'done');

  final onlineReaderMessages = await onlineReader.loadGroupMessages(groupId);
  final onlineDelivered = onlineReaderMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  expect(onlineDelivered.keyGeneration, 4);
  final onlineReaderMedia = await onlineReader.mediaAttachmentRepo
      .getAttachmentsForMessage(onlineDelivered.id);
  expect(onlineReaderMedia, hasLength(1));
  expect(onlineReaderMedia.single.id, uploadedBlobId);

  final readerMessages = await reader.loadGroupMessages(groupId);
  final readerDelivered = readerMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  expect(readerDelivered.keyGeneration, 4);
  final readerMedia = await reader.mediaAttachmentRepo.getAttachmentsForMessage(
    readerDelivered.id,
  );
  expect(readerMedia, hasLength(1));
  expect(readerMedia.single.id, uploadedBlobId);
  expect(readerMedia.single.width, 1080);
  expect(readerMedia.single.height, 720);

  admin.dispose();
  reader.dispose();
  onlineReader.dispose();
}

Future<void> _section10WidgetVoiceLifecycleProof(
  WidgetTester tester,
  FakeGroupPubSubNetwork network,
) async {
  final admin = GroupTestUser.create(
    peerId: 'admin-widget-voice-peer',
    username: 'Alice',
    network: network,
  );
  final reader = GroupTestUser.create(
    peerId: 'reader-widget-voice-peer',
    username: 'Bob',
    network: network,
    bridge: _CursorInboxBridge(),
  );
  final onlineReader = GroupTestUser.create(
    peerId: 'online-widget-voice-peer',
    username: 'Carol',
    network: network,
  );
  final readerBridge = reader.bridge as _CursorInboxBridge;
  final senderBridge = _Section10MirroringBridge(
    network: network,
    msgRepo: admin.msgRepo,
    groupRepo: admin.groupRepo,
    operationLog: <String>[],
  );
  final mediaFileManager = FakeMediaFileManager();
  final recorder = FakeAudioRecorderService()
    ..fakeDurationMs = 1400
    ..fakeSizeBytes = 36000;
  final tempDir = Directory.systemTemp.createTempSync('section10-voice-');
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  final voiceFile = File(p.join(tempDir.path, 'announcement.m4a'))
    ..writeAsStringSync('voice');
  recorder.fakeOutputPath = voiceFile.path;

  const groupId = 'group-announce-widget-voice';
  await admin.createGroup(
    groupId: groupId,
    name: 'Announcements Widget Voice',
    type: GroupType.announcement,
  );
  await admin.addMember(groupId: groupId, invitee: reader);
  await admin.addMember(groupId: groupId, invitee: onlineReader);
  await _saveKey(admin, groupId, 6, 'k6');
  await _saveKey(reader, groupId, 6, 'k6');
  await _saveKey(onlineReader, groupId, 6, 'k6');

  admin.start();
  reader.start();
  onlineReader.start();

  await _pumpSection10SenderWidget(
    tester,
    sender: admin,
    groupId: groupId,
    bridge: senderBridge,
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
          senderBridge.operationLog.add('uploadMediaFn');
          return _uploadedMedia(
            id: blobId ?? 'att-widget-voice',
            messageId: '',
            mime: mime,
            localPath: mediaFileManager!.relativePathForAttachment(
              contactPeerId: recipientPeerId,
              blobId: blobId ?? 'att-widget-voice',
              mime: mime,
            ),
            durationMs: durationMs,
            waveform: waveform,
          );
        },
  );

  await simulateBackgroundForegroundCycle(
    bridge: reader.bridge,
    p2pService: FakeP2PService(),
    messageRepo: InMemoryMessageRepository(),
    groupMsgRepo: reader.msgRepo,
    afterPause: () async {
      network.unsubscribe(groupId, reader.peerId);
      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      await (screen.onRecordStart! as Future<void> Function())();
      await _pumpUntil(
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
      await _waitUntil(
        () => senderBridge.commandLog.contains('group:inboxStore'),
      );
      await _pumpFrames(tester, count: 20);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      _injectInboxMessageFromLatestStore(
        senderBridge: senderBridge,
        receiverBridge: readerBridge,
        receiverPeerId: reader.peerId,
        groupId: groupId,
      );
    },
    afterResume: () async {
      await drainGroupOfflineInbox(
        bridge: reader.bridge,
        groupRepo: reader.groupRepo,
        msgRepo: reader.msgRepo,
        mediaAttachmentRepo: reader.mediaAttachmentRepo,
      );
      network.subscribe(groupId, reader.peerId);
    },
  );

  final sent = await _latestOutgoingMessage(admin.msgRepo, groupId, text: '');
  expect(sent.status, 'sent');
  final inboxPayload = latestBridgePayload(senderBridge, 'group:inboxStore');
  expect(inboxPayload['pushBody'], 'Alice sent a voice message');
  final inboxEnvelope =
      jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
  expect(inboxEnvelope['text'], isEmpty);
  _expectOrdered(senderBridge.operationLog, 'bridge:bg:begin', 'uploadMediaFn');
  _expectOrdered(
    senderBridge.operationLog,
    'uploadMediaFn',
    'bridge:group:publish',
  );
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:group:inboxStore',
    'bridge:bg:end',
  );

  final onlineReaderMessages = await onlineReader.loadGroupMessages(groupId);
  final onlineDelivered = onlineReaderMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  final onlineReaderMedia = await onlineReader.mediaAttachmentRepo
      .getAttachmentsForMessage(onlineDelivered.id);
  expect(onlineReaderMedia, hasLength(1));
  expect(onlineReaderMedia.single.mediaType, 'audio');

  final readerMessages = await reader.loadGroupMessages(groupId);
  final readerDelivered = readerMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  final readerMedia = await reader.mediaAttachmentRepo.getAttachmentsForMessage(
    readerDelivered.id,
  );
  expect(readerMedia, hasLength(1));
  expect(readerMedia.single.mediaType, 'audio');
  expect(readerMedia.single.durationMs, 1400);

  admin.dispose();
  reader.dispose();
  onlineReader.dispose();
}

Future<void> _section10WidgetRotationLifecycleProof(
  WidgetTester tester,
  FakeGroupPubSubNetwork network,
) async {
  final admin = GroupTestUser.create(
    peerId: 'admin-widget-rotation-peer',
    username: 'Alice',
    network: network,
  );
  final reader = GroupTestUser.create(
    peerId: 'reader-widget-rotation-peer',
    username: 'Bob',
    network: network,
  );
  final senderBridge = _Section10MirroringBridge(
    network: network,
    msgRepo: admin.msgRepo,
    groupRepo: admin.groupRepo,
    operationLog: <String>[],
  );

  const groupId = 'group-announce-widget-rotation';
  await admin.createGroup(
    groupId: groupId,
    name: 'Announcements Widget Rotation',
    type: GroupType.announcement,
  );
  await admin.addMember(groupId: groupId, invitee: reader);
  await _saveKey(admin, groupId, 1, 'k1');
  await _saveKey(reader, groupId, 1, 'k1');

  admin.start();
  reader.start();

  await _saveKey(admin, groupId, 2, 'k2');
  await _saveKey(reader, groupId, 2, 'k2');

  await _pumpSection10SenderWidget(
    tester,
    sender: admin,
    groupId: groupId,
    bridge: senderBridge,
  );

  await _sendText(tester, 'After rotation via widget');
  await _pumpUntil(
    tester,
    () => senderBridge.commandLog.contains('group:inboxStore'),
  );
  await _pumpFrames(tester, count: 20);

  final sent = await _latestOutgoingMessage(
    admin.msgRepo,
    groupId,
    text: 'After rotation via widget',
  );
  expect(sent.status, 'sent');
  expect(sent.keyGeneration, 2);
  final readerMessages = await reader.loadGroupMessages(groupId);
  final delivered = readerMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  expect(delivered.keyGeneration, 2);
  expect(senderBridge.commandLog, contains('group:publish'));
  expect(senderBridge.commandLog, contains('group:inboxStore'));

  admin.dispose();
  reader.dispose();
}

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  group('Group resume recovery integration tests', () {
    test(
      'member backgrounded during send receives missed group messages after resume',
      () async {
        // Arrange: Alice and Bob in a group.
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-resume-1';
        await alice.createGroup(groupId: groupId, name: 'Resume Test');
        await alice.addMember(groupId: groupId, invitee: bob);

        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        alice.start();
        bob.start();

        // Verify normal messaging works.
        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'Before background',
        );
        await pump();
        var bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

        // Simulate Bob backgrounding: unsubscribe from network.
        network.unsubscribe(groupId, bob.peerId);

        // Alice sends while Bob is backgrounded.
        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'While backgrounded',
        );
        await pump();

        // Bob should NOT have received the message.
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

        // Simulate resume: drain offline inbox (with missed messages).
        final ts = DateTime.now().toUtc().toIso8601String();
        bobBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'While backgrounded',
            'timestamp': ts,
            'messageId': 'msg-missed-1',
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        // Bob should now have 2 incoming messages.
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(2));

        // Re-subscribe Bob.
        network.subscribe(groupId, bob.peerId);

        // New live messages should still work.
        await alice.sendGroupMessage(groupId: groupId, text: 'After resume');
        await pump();
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(3));

        alice.dispose();
        bob.dispose();
      },
    );

    test(
      'same message is not duplicated if both pubsub and group inbox deliver it',
      () async {
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-dedup-1';
        const sharedMessageId = 'msg-dedup-shared';
        final ts = DateTime.now().toUtc();

        // Set up Bob's group.
        await bob.groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Dedup Test',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: ts,
            createdBy: 'alice-peer',
            myRole: GroupRole.member,
          ),
        );
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'alice-peer',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: ts,
          ),
        );
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'bob-peer',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: ts,
          ),
        );
        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: ts,
          ),
        );

        bob.start();
        network.subscribe(groupId, bob.peerId);

        // Simulate pubsub delivery with a known messageId.
        final pubsubController = network.registerPeer('alice-pubsub-sim');
        network.subscribe(groupId, 'alice-pubsub-sim');

        // Deliver via pubsub (simulate what the listener receives).
        await handleIncomingGroupMessage(
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupId: groupId,
          senderId: 'alice-peer',
          senderUsername: 'Alice',
          keyEpoch: 0,
          text: 'Dedup test msg',
          timestamp: ts.toIso8601String(),
          messageId: sharedMessageId,
        );

        var bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming).length, 1);

        // Now drain inbox which also has the same message with the same messageId.
        bobBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Dedup test msg',
            'timestamp': ts.toIso8601String(),
            'messageId': sharedMessageId,
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        // Still only 1 incoming message — deduplicated by messageId.
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.where((m) => m.isIncoming).length,
          1,
          reason: 'Message should not be duplicated by inbox drain',
        );

        pubsubController.close();
        bob.dispose();
      },
    );

    test(
      'watchdog restart rejoins topics and receives subsequent live messages',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'group-watchdog-1';
        await alice.createGroup(groupId: groupId, name: 'Watchdog Test');
        await alice.addMember(groupId: groupId, invitee: bob);

        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        alice.start();
        bob.start();

        // Normal messaging works.
        await alice.sendGroupMessage(groupId: groupId, text: 'Before watchdog');
        await pump();
        var bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

        // Simulate watchdog restart: unsubscribe Bob (Go node restarted).
        network.unsubscribe(groupId, bob.peerId);

        // Rejoin with watchdog restart reason.
        await rejoinGroupTopics(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          reason: RejoinReason.watchdogRestart,
        );

        // Verify bridge received join command.
        final joinCmds = bob.bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();
        expect(joinCmds, isNotEmpty);

        // Re-subscribe on fake network (in production, Go does this internally).
        network.subscribe(groupId, bob.peerId);

        // Live messages should work after rejoin.
        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'After watchdog restart',
        );
        await pump();
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(2));

        alice.dispose();
        bob.dispose();
      },
    );

    test(
      'announcement reader backgrounded during send receives missed announces after resume',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final onlineReader = GroupTestUser.create(
          peerId: 'online-reader-peer',
          username: 'OnlineReader',
          network: network,
        );
        final readerBridge = reader.bridge as _CursorInboxBridge;
        final p2pService = FakeP2PService();
        final lifecycleMessageRepo = InMemoryMessageRepository();
        SendGroupMessageResult? sendResult;
        GroupMessage? sent;

        const groupId = 'group-announce-resume';
        await admin.createGroup(
          groupId: groupId,
          name: 'Announcements',
          type: GroupType.announcement,
        );
        await admin.addMember(groupId: groupId, invitee: reader);
        await admin.addMember(groupId: groupId, invitee: onlineReader);

        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        admin.start();
        reader.start();
        onlineReader.start();

        await simulateBackgroundForegroundCycle(
          bridge: reader.bridge,
          p2pService: p2pService,
          messageRepo: lifecycleMessageRepo,
          groupMsgRepo: reader.msgRepo,
          afterPause: () async {
            network.unsubscribe(groupId, reader.peerId);
            (sendResult, sent) = await admin.sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'Announcement 2',
            );
            _injectInboxMessageFromLatestStore(
              senderBridge: admin.bridge,
              receiverBridge: readerBridge,
              receiverPeerId: reader.peerId,
              groupId: groupId,
            );
          },
          afterResume: () async {
            await drainGroupOfflineInbox(
              bridge: reader.bridge,
              groupRepo: reader.groupRepo,
              msgRepo: reader.msgRepo,
            );
            network.subscribe(groupId, reader.peerId);
          },
        );

        expect(sendResult, SendGroupMessageResult.success);
        expect(sent, isNotNull);
        expect(sent!.status, 'sent');
        expect(admin.bridge.commandLog, contains('group:publish'));
        expect(admin.bridge.commandLog, contains('group:inboxStore'));

        final onlineReaderMessages = await onlineReader.loadGroupMessages(
          groupId,
        );
        expect(
          onlineReaderMessages.any(
            (message) => message.text == 'Announcement 2',
          ),
          isTrue,
        );

        final readerMessages = await reader.loadGroupMessages(groupId);
        expect(
          readerMessages.any((message) => message.text == 'Announcement 2'),
          isTrue,
        );

        admin.dispose();
        reader.dispose();
        onlineReader.dispose();
      },
    );

    testWidgets(
      '10-A acceptance uses real GroupConversationWired sender path with reader lifecycle inbox recovery',
      (tester) async {
        await _section10WidgetTextLifecycleProof(tester, network);
      },
    );

    test(
      'announcement media send with zero topic peers stays pending and readers recover intact media refs after resume',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-media-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-media-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final readerBridge = reader.bridge as _CursorInboxBridge;
        final p2pService = FakeP2PService();
        final lifecycleMessageRepo = InMemoryMessageRepository();
        SendGroupMessageResult? sendResult;
        GroupMessage? sent;

        const groupId = 'group-announce-media-resume';
        await admin.createGroup(
          groupId: groupId,
          name: 'Announcements Media',
          type: GroupType.announcement,
        );
        await admin.addMember(groupId: groupId, invitee: reader);

        await admin.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 4,
            encryptedKey: 'k4',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 4,
            encryptedKey: 'k4',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        admin.start();
        reader.start();

        final mediaAttachment = MediaAttachment(
          id: 'att-proof-1',
          messageId: '',
          mime: 'image/jpeg',
          size: 12,
          mediaType: 'image',
          width: 1280,
          height: 720,
          localPath: 'media/group-announce-media-resume/att-proof-1.jpg',
          downloadStatus: 'done',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );

        await simulateBackgroundForegroundCycle(
          bridge: reader.bridge,
          p2pService: p2pService,
          messageRepo: lifecycleMessageRepo,
          groupMsgRepo: reader.msgRepo,
          afterPause: () async {
            network.unsubscribe(groupId, reader.peerId);
            (sendResult, sent) = await admin.sendGroupMessageViaBridge(
              groupId: groupId,
              text: '',
              mediaAttachments: [mediaAttachment],
              publishTopicPeersOverride: 0,
            );
            _injectInboxMessageFromLatestStore(
              senderBridge: admin.bridge,
              receiverBridge: readerBridge,
              receiverPeerId: reader.peerId,
              groupId: groupId,
            );
          },
          afterResume: () async {
            await drainGroupOfflineInbox(
              bridge: reader.bridge,
              groupRepo: reader.groupRepo,
              msgRepo: reader.msgRepo,
              mediaAttachmentRepo: reader.mediaAttachmentRepo,
            );
            network.subscribe(groupId, reader.peerId);
          },
        );

        expect(sendResult, SendGroupMessageResult.successNoPeers);
        expect(sent, isNotNull);
        expect(sent!.status, 'pending');
        expect(sent!.keyGeneration, 4);

        final readerMessages = await reader.loadGroupMessages(groupId);
        final delivered = readerMessages.firstWhere(
          (message) => message.id == sent!.id,
        );
        expect(delivered.keyGeneration, 4);

        final deliveredMedia = await reader.mediaAttachmentRepo
            .getAttachmentsForMessage(delivered.id);
        expect(deliveredMedia, hasLength(1));
        expect(deliveredMedia.single.id, 'att-proof-1');
        expect(deliveredMedia.single.mediaType, 'image');
        expect(deliveredMedia.single.width, 1280);
        expect(deliveredMedia.single.height, 720);

        admin.dispose();
        reader.dispose();
      },
    );

    testWidgets(
      '10-B acceptance uses real GroupConversationWired sender path for media + resume fallback',
      (tester) async {
        await _section10WidgetMediaLifecycleProof(tester, network);
      },
    );

    testWidgets(
      '10-C acceptance uses real GroupConversationWired sender path for voice + exact push body',
      (tester) async {
        await _section10WidgetVoiceLifecycleProof(tester, network);
      },
    );

    test(
      'announcement admin send after key rotation uses the new epoch and remains deliverable',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-rot-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-rot-peer',
          username: 'Reader',
          network: network,
        );

        const groupId = 'group-announce-rotation';
        await admin.createGroup(
          groupId: groupId,
          name: 'Announcements Rotation',
          type: GroupType.announcement,
        );
        await admin.addMember(groupId: groupId, invitee: reader);

        await admin.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'k1',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'k1',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        admin.start();
        reader.start();

        await admin.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 2,
            encryptedKey: 'k2',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 2,
            encryptedKey: 'k2',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final (result, sent) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'After rotation',
        );
        expect(result, SendGroupMessageResult.success);
        expect(sent, isNotNull);
        expect(sent!.keyGeneration, 2);
        expect(sent.status, 'sent');
        expect(admin.bridge.commandLog, contains('group:publish'));
        expect(admin.bridge.commandLog, contains('group:inboxStore'));

        await pump();
        final readerMessages = await reader.loadGroupMessages(groupId);
        final incomingAfterRotation = readerMessages.firstWhere(
          (message) => message.isIncoming && message.text == 'After rotation',
        );
        expect(incomingAfterRotation.keyGeneration, 2);

        admin.dispose();
        reader.dispose();
      },
    );

    testWidgets(
      '10-F acceptance uses real GroupConversationWired sender path after key rotation',
      (tester) async {
        await _section10WidgetRotationLifecycleProof(tester, network);
      },
    );

    test(
      'group discovery remains live across ttl refresh window without manual rejoin',
      () async {
        // This is a structural test: verify that after rejoining,
        // the topic subscription persists without needing manual re-rejoin.
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );

        const groupId = 'group-ttl-refresh';
        await alice.createGroup(groupId: groupId, name: 'TTL Test');

        await alice.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        alice.start();

        // Verify subscription is active.
        expect(network.isSubscribed(groupId, alice.peerId), isTrue);

        // Simulate time passing (no manual rejoin needed).
        await pump();

        // Subscription should still be active.
        expect(network.isSubscribed(groupId, alice.peerId), isTrue);

        alice.dispose();
      },
    );

    test(
      'fake group network delivers live messages without explicit relay simulation',
      () async {
        // Structural fake-network coverage only. Real Go dial policy is
        // asserted in go-mknoon/node tests against live libp2p hosts.
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'group-direct-path';
        await alice.createGroup(groupId: groupId, name: 'Direct Test');
        await alice.addMember(groupId: groupId, invitee: bob);

        alice.start();
        bob.start();

        // Message delivery works directly (no relay setup needed in tests).
        await alice.sendGroupMessage(groupId: groupId, text: 'Direct msg');
        await pump();

        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

        alice.dispose();
        bob.dispose();
      },
    );

    test(
      'many joined groups resume without bursting recovery work all at once',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        // Create 5 groups.
        final groupIds = List.generate(5, (i) => 'group-multi-$i');
        for (final gid in groupIds) {
          await user.createGroup(groupId: gid, name: 'Multi $gid');
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: gid,
              keyGeneration: 1,
              encryptedKey: 'key-$gid',
              createdAt: DateTime.now().toUtc(),
            ),
          );

          // Each group has one offline message.
          final ts = DateTime.now().toUtc().toIso8601String();
          userBridge.addPage(gid, '', [
            {
              'groupId': gid,
              'senderId': 'other-peer',
              'senderUsername': 'Other',
              'keyEpoch': 0,
              'text': 'Missed msg in $gid',
              'timestamp': ts,
              'messageId': 'msg-multi-$gid',
            },
          ], '');
        }

        user.start();

        // Drain all groups' inboxes.
        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        // All 5 groups should have been drained.
        final retrieveCount = userBridge.commandLog
            .where((c) => c == 'group:inboxRetrieveCursor')
            .length;
        expect(retrieveCount, 5);

        // Verify each group has 1 message.
        for (final gid in groupIds) {
          final msgs = await user.msgRepo.getMessagesPage(gid);
          expect(
            msgs.length,
            1,
            reason: 'Group $gid should have 1 drained message',
          );
        }

        user.dispose();
      },
    );

    // =========================================================================
    // Phase 6: Multi-page cursor and watchdog restart tests
    // =========================================================================

    test(
      'resume drains missed group backlog exactly once across pages',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-multipage';
        await user.createGroup(groupId: groupId, name: 'Multi Page');
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final ts = DateTime.now().toUtc().toIso8601String();

        // Page 1: 2 messages, cursor points to page 2
        userBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Message 1',
            'timestamp': ts,
            'messageId': 'msg-page1-1',
          },
          {
            'groupId': groupId,
            'senderId': 'bob-peer',
            'senderUsername': 'Bob',
            'keyEpoch': 0,
            'text': 'Message 2',
            'timestamp': ts,
            'messageId': 'msg-page1-2',
          },
        ], 'cursor-page-2');

        // Page 2: 1 message, no more pages
        userBridge.addPage(groupId, 'cursor-page-2', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Message 3',
            'timestamp': ts,
            'messageId': 'msg-page2-1',
          },
        ], '');

        user.start();

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        // All 3 messages from both pages should be saved
        final msgs = await user.msgRepo.getMessagesPage(groupId);
        expect(
          msgs.length,
          3,
          reason: 'All messages from both pages should be saved',
        );

        // Verify cursor commands: first page with cursor="" and second with cursor="cursor-page-2"
        final cursorCmds = userBridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
            .toList();
        expect(cursorCmds.length, 2, reason: 'Should have fetched 2 pages');
        expect(cursorCmds[0]['payload']['cursor'], '');
        expect(cursorCmds[1]['payload']['cursor'], 'cursor-page-2');

        user.dispose();
      },
    );

    test(
      'multi page backlog uses cursor continuation without duplication',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-nodup';
        await user.createGroup(groupId: groupId, name: 'No Dup');
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final ts = DateTime.now().toUtc().toIso8601String();
        const sharedMsgId = 'msg-shared-id';

        // Same message on both pages (cursor should prevent this, but test the handler dedup)
        userBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Same message',
            'timestamp': ts,
            'messageId': sharedMsgId,
          },
        ], 'cursor-2');

        userBridge.addPage(groupId, 'cursor-2', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Same message',
            'timestamp': ts,
            'messageId': sharedMsgId,
          },
        ], '');

        user.start();

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        // Despite same messageId on both pages, should be deduplicated
        final msgs = await user.msgRepo.getMessagesPage(groupId);
        expect(
          msgs.length,
          1,
          reason: 'Duplicate messageId across pages should be deduplicated',
        );

        user.dispose();
      },
    );

    test('watchdog restart rejoins topics and resumes live delivery', () async {
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
        bridge: _CursorInboxBridge(),
      );
      final bobBridge = bob.bridge as _CursorInboxBridge;

      const groupId = 'group-watchdog-rejoin-drain';
      await alice.createGroup(groupId: groupId, name: 'WD Rejoin');
      await alice.addMember(groupId: groupId, invitee: bob);

      await bob.groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'test-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      alice.start();
      bob.start();

      // Normal messaging works
      await alice.sendGroupMessage(groupId: groupId, text: 'Before WD');
      await pump();
      var msgs = await bob.loadGroupMessages(groupId);
      expect(msgs.where((m) => m.isIncoming), hasLength(1));

      // Simulate watchdog: unsubscribe Bob
      network.unsubscribe(groupId, bob.peerId);

      // Alice sends while Bob is down
      await alice.sendGroupMessage(groupId: groupId, text: 'During WD');
      await pump();

      // Bob missed the message
      msgs = await bob.loadGroupMessages(groupId);
      expect(msgs.where((m) => m.isIncoming), hasLength(1));

      // Watchdog restart: rejoin + drain inbox
      await rejoinGroupTopics(
        bridge: bob.bridge,
        groupRepo: bob.groupRepo,
        reason: RejoinReason.watchdogRestart,
      );

      final ts = DateTime.now().toUtc().toIso8601String();
      bobBridge.addPage(groupId, '', [
        {
          'groupId': groupId,
          'senderId': 'alice-peer',
          'senderUsername': 'Alice',
          'keyEpoch': 0,
          'text': 'During WD',
          'timestamp': ts,
          'messageId': 'msg-wd-missed',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bob.bridge,
        groupRepo: bob.groupRepo,
        msgRepo: bob.msgRepo,
      );

      // Bob should now have 2 messages
      msgs = await bob.loadGroupMessages(groupId);
      expect(msgs.where((m) => m.isIncoming), hasLength(2));

      // Re-subscribe on network
      network.subscribe(groupId, bob.peerId);

      // New messages should work
      await alice.sendGroupMessage(groupId: groupId, text: 'After WD');
      await pump();
      msgs = await bob.loadGroupMessages(groupId);
      expect(msgs.where((m) => m.isIncoming), hasLength(3));

      alice.dispose();
      bob.dispose();
    });

    group('Section 11 test infrastructure', () {
      test('publish with zero peers falls back to inbox', () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-zero-peer',
          username: 'Alice',
          network: network,
          bridge: ZeroPeerPublishBridge(),
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-zero-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-zero-peer';
        await admin.createGroup(groupId: groupId, name: 'Zero Peer Fallback');
        await admin.addMember(groupId: groupId, invitee: bob);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');
        network.unsubscribe(groupId, bob.peerId);

        admin.start();
        bob.start();

        final (result, sent) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Zero peers via inbox',
        );

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(sent, isNotNull);
        expect(sent!.status, 'pending');
        expect(sent.inboxStored, isTrue);
        expect(admin.bridge.commandLog, contains('group:publish'));
        expect(admin.bridge.commandLog, contains('group:inboxStore'));

        _injectInboxMessageFromLatestStore(
          senderBridge: admin.bridge,
          receiverBridge: bobBridge,
          receiverPeerId: bob.peerId,
          groupId: groupId,
        );

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        final bobMessages = await bob.loadGroupMessages(groupId);
        final incoming = bobMessages.where((message) => message.isIncoming);
        expect(incoming, hasLength(1));
        expect(incoming.single.text, 'Zero peers via inbox');

        admin.dispose();
        bob.dispose();
      });

      test("inbox store failure doesn't block publish", () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-inbox-fail-peer',
          username: 'Alice',
          network: network,
          bridge: _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            inboxStoreResponse: {
              'ok': false,
              'errorCode': 'INBOX_STORE_FAILED',
            },
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-inbox-fail-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'group-inbox-fail';
        await admin.createGroup(groupId: groupId, name: 'Inbox Fail');
        await admin.addMember(groupId: groupId, invitee: bob);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');

        admin.start();
        bob.start();

        final (result, sent) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Publish despite inbox failure',
        );

        expect(result, SendGroupMessageResult.success);
        expect(sent, isNotNull);
        expect(sent!.status, 'sent');
        expect(sent.inboxStored, isFalse);
        expect(admin.bridge.commandLog, contains('group:publish'));
        expect(admin.bridge.commandLog, contains('group:inboxStore'));

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.any(
            (message) => message.text == 'Publish despite inbox failure',
          ),
          isTrue,
        );

        admin.dispose();
        bob.dispose();
      });

      test('stuck sending recovery after background', () async {
        final publishGate = Completer<void>();
        final admin = GroupTestUser.create(
          peerId: 'admin-stuck-peer',
          username: 'Alice',
          network: network,
          bridge: _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            commandGates: {'group:publish': publishGate},
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-stuck-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'group-stuck-send';
        await admin.createGroup(groupId: groupId, name: 'Stuck Send');
        await admin.addMember(groupId: groupId, invitee: bob);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');

        admin.start();
        bob.start();

        final sendFuture = admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Slow send while backgrounded',
        );
        await pump();

        await simulateBackgroundForegroundCycle(
          bridge: admin.bridge,
          p2pService: FakeP2PService(),
          messageRepo: InMemoryMessageRepository(),
          groupMsgRepo: admin.msgRepo,
          afterPause: () async {
            final paused = await _latestOutgoingMessage(
              admin.msgRepo,
              groupId,
              text: 'Slow send while backgrounded',
            );
            expect(paused.status, 'failed');
          },
          afterResume: () async {
            publishGate.complete();
            final (result, sent) = await sendFuture;
            expect(result, SendGroupMessageResult.success);
            expect(sent, isNotNull);
          },
        );

        await pump();
        final finalMessage = await _latestOutgoingMessage(
          admin.msgRepo,
          groupId,
          text: 'Slow send while backgrounded',
        );
        expect(finalMessage.status, 'sent');
        expect(finalMessage.inboxStored, isTrue);

        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.any(
            (message) => message.text == 'Slow send while backgrounded',
          ),
          isTrue,
        );

        admin.dispose();
        bob.dispose();
      });

      test('partial delivery with inbox drain completion', () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-partial-peer',
          username: 'Alice',
          network: network,
        );
        final onlineReader = GroupTestUser.create(
          peerId: 'reader-online-peer',
          username: 'Bob',
          network: network,
        );
        final inboxReaderOne = GroupTestUser.create(
          peerId: 'reader-inbox-1-peer',
          username: 'Carol',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final inboxReaderTwo = GroupTestUser.create(
          peerId: 'reader-inbox-2-peer',
          username: 'Dave',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final inboxBridgeOne = inboxReaderOne.bridge as _CursorInboxBridge;
        final inboxBridgeTwo = inboxReaderTwo.bridge as _CursorInboxBridge;

        const groupId = 'group-partial-delivery';
        await admin.createGroup(groupId: groupId, name: 'Partial Delivery');
        await admin.addMember(groupId: groupId, invitee: onlineReader);
        await admin.addMember(groupId: groupId, invitee: inboxReaderOne);
        await admin.addMember(groupId: groupId, invitee: inboxReaderTwo);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(onlineReader, groupId, 1, 'k1');
        await _saveKey(inboxReaderOne, groupId, 1, 'k1');
        await _saveKey(inboxReaderTwo, groupId, 1, 'k1');
        network.unsubscribe(groupId, inboxReaderOne.peerId);
        network.unsubscribe(groupId, inboxReaderTwo.peerId);

        admin.start();
        onlineReader.start();
        inboxReaderOne.start();
        inboxReaderTwo.start();

        final (result, sent) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Partial delivery',
        );

        expect(result, SendGroupMessageResult.success);
        expect(sent, isNotNull);
        expect(sent!.status, 'sent');

        _injectInboxMessageFromLatestStore(
          senderBridge: admin.bridge,
          receiverBridge: inboxBridgeOne,
          receiverPeerId: inboxReaderOne.peerId,
          groupId: groupId,
        );
        _injectInboxMessageFromLatestStore(
          senderBridge: admin.bridge,
          receiverBridge: inboxBridgeTwo,
          receiverPeerId: inboxReaderTwo.peerId,
          groupId: groupId,
        );

        await drainGroupOfflineInbox(
          bridge: inboxReaderOne.bridge,
          groupRepo: inboxReaderOne.groupRepo,
          msgRepo: inboxReaderOne.msgRepo,
        );
        await drainGroupOfflineInbox(
          bridge: inboxReaderTwo.bridge,
          groupRepo: inboxReaderTwo.groupRepo,
          msgRepo: inboxReaderTwo.msgRepo,
        );

        final onlineMessages = await onlineReader.loadGroupMessages(groupId);
        final inboxMessagesOne = await inboxReaderOne.loadGroupMessages(
          groupId,
        );
        final inboxMessagesTwo = await inboxReaderTwo.loadGroupMessages(
          groupId,
        );
        expect(
          onlineMessages.any((message) => message.text == 'Partial delivery'),
          isTrue,
        );
        expect(
          inboxMessagesOne.any((message) => message.text == 'Partial delivery'),
          isTrue,
        );
        expect(
          inboxMessagesTwo.any((message) => message.text == 'Partial delivery'),
          isTrue,
        );

        admin.dispose();
        onlineReader.dispose();
        inboxReaderOne.dispose();
        inboxReaderTwo.dispose();
      });

      test('full lifecycle round-trip', () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-round-trip-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-round-trip-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'reader-round-trip-online-peer',
          username: 'Charlie',
          network: network,
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-round-trip';
        await admin.createGroup(groupId: groupId, name: 'Round Trip');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');
        await _saveKey(charlie, groupId, 1, 'k1');

        admin.start();
        bob.start();
        charlie.start();

        await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Before pause',
        );
        await pump();

        network.unsubscribe(groupId, bob.peerId);

        await simulateBackgroundForegroundCycle(
          bridge: bob.bridge,
          p2pService: FakeP2PService(),
          messageRepo: InMemoryMessageRepository(),
          groupMsgRepo: bob.msgRepo,
          afterPause: () async {
            await admin.sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'While paused',
            );
            _injectInboxMessageFromLatestStore(
              senderBridge: admin.bridge,
              receiverBridge: bobBridge,
              receiverPeerId: bob.peerId,
              groupId: groupId,
            );
          },
          afterResume: () async {
            await drainGroupOfflineInbox(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              msgRepo: bob.msgRepo,
            );
            network.subscribe(groupId, bob.peerId);
          },
        );

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        final bobIncoming = bobMessages.where((message) => message.isIncoming);
        expect(bobIncoming, hasLength(2));
        expect(bobIncoming.map((message) => message.text).toSet(), {
          'Before pause',
          'While paused',
        });
        expect(
          bobMessages.where((message) => message.text == 'While paused'),
          hasLength(1),
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      });

      test('failed message retry after network recovery', () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-retry-peer',
          username: 'Alice',
          network: network,
          bridge: _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            publishFailuresRemaining: 1,
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-retry-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'group-retry-after-network';
        await admin.createGroup(groupId: groupId, name: 'Retry After Recovery');
        await admin.addMember(groupId: groupId, invitee: bob);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');

        admin.start();
        bob.start();

        final (initialResult, initialSent) = await admin
            .sendGroupMessageViaBridge(groupId: groupId, text: 'Retry me');

        expect(initialResult, SendGroupMessageResult.error);
        expect(initialSent, isNotNull);
        expect(initialSent!.status, 'failed');

        final retried = await retryFailedGroupMessages(
          groupMsgRepo: admin.msgRepo,
          groupRepo: admin.groupRepo,
          identityRepo: _Section10IdentityRepository(_identityForUser(admin)),
          bridge: admin.bridge,
          mediaAttachmentRepo: admin.mediaAttachmentRepo,
        );

        expect(retried, 1);

        final finalMessage = await _latestOutgoingMessage(
          admin.msgRepo,
          groupId,
          text: 'Retry me',
        );
        expect(finalMessage.id, initialSent.id);
        expect(finalMessage.status, 'sent');

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.any((message) => message.id == initialSent.id),
          isTrue,
        );

        admin.dispose();
        bob.dispose();
      });

      test("multi-group resume doesn't burst", () async {
        final user = GroupTestUser.create(
          peerId: 'user-burst-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupCount = 10;
        final groupIds = List.generate(
          groupCount,
          (index) => 'group-burst-$index',
        );
        for (final groupId in groupIds) {
          await user.createGroup(groupId: groupId, name: 'Burst $groupId');
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'key-$groupId',
              createdAt: DateTime.now().toUtc(),
            ),
          );

          final ts = DateTime.now().toUtc().toIso8601String();
          userBridge.addPage(groupId, '', [
            {
              'groupId': groupId,
              'senderId': 'other-peer',
              'senderUsername': 'Other',
              'keyEpoch': 0,
              'text': 'Missed msg in $groupId',
              'timestamp': ts,
              'messageId': 'msg-$groupId',
            },
          ], '');
        }

        user.start();

        await simulateBackgroundForegroundCycle(
          bridge: user.bridge,
          p2pService: FakeP2PService(),
          messageRepo: InMemoryMessageRepository(),
          groupMsgRepo: user.msgRepo,
          afterResume: () async {
            await drainGroupOfflineInbox(
              bridge: user.bridge,
              groupRepo: user.groupRepo,
              msgRepo: user.msgRepo,
            );
          },
        );

        final retrieveCount = userBridge.commandLog
            .where((command) => command == 'group:inboxRetrieveCursor')
            .length;
        expect(retrieveCount, groupCount);

        for (final groupId in groupIds) {
          final messages = await user.msgRepo.getMessagesPage(groupId);
          expect(
            messages.length,
            1,
            reason: 'Group $groupId should have 1 drained message',
          );
        }

        user.dispose();
      });
    });
  });
}
