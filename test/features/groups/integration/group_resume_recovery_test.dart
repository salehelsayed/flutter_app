import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart'
    as group_react;
import 'package:flutter_app/features/groups/application/update_group_metadata_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';
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
import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';
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
    if (cmd == 'group:inboxRetrieveCursor') {
      if (cmd != null) commandLog.add(cmd);
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;

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

    return super.send(message);
  }
}

class _InboxPage {
  final List<Map<String, dynamic>> messages;
  final String nextCursor;
  _InboxPage(this.messages, this.nextCursor);
}

class _Section10TempMediaFileManager extends FakeMediaFileManager {
  _Section10TempMediaFileManager(this.rootDir);

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

List<Map<String, dynamic>> bridgePayloads(FakeBridge bridge, String command) {
  return bridge.sentMessages
      .map((message) => jsonDecode(message) as Map<String, dynamic>)
      .where((message) => message['cmd'] == command)
      .map((message) => message['payload'] as Map<String, dynamic>)
      .toList(growable: false);
}

Map<String, dynamic> _storedGroupReplayEnvelope(String storedMessage) {
  return jsonDecode(storedMessage) as Map<String, dynamic>;
}

Map<String, dynamic> _decodedGroupReplayPayload(String storedMessage) {
  final envelope = _storedGroupReplayEnvelope(storedMessage);
  final ciphertext = envelope['ciphertext'];
  if (envelope['kind'] == 'group_offline_replay' && ciphertext is String) {
    return jsonDecode(ciphertext) as Map<String, dynamic>;
  }
  return envelope;
}

void _addRelayStoredMessagePage({
  required _CursorInboxBridge receiverBridge,
  required String groupId,
  required String fromPeerId,
  required String storedMessage,
  String cursor = '',
  String nextCursor = '',
}) {
  receiverBridge.addPage(groupId, cursor, [
    {
      'from': fromPeerId,
      'message': storedMessage,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    },
  ], nextCursor);
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
  final storedMessage = inboxPayload['message'] as String;
  final decodedPayload = _decodedGroupReplayPayload(storedMessage);
  var fromPeerId = decodedPayload['senderId'] as String? ?? '';
  if (fromPeerId.isEmpty) {
    try {
      final publishPayload = latestBridgePayload(senderBridge, 'group:publish');
      fromPeerId = publishPayload['senderPeerId'] as String? ?? '';
    } on StateError {
      fromPeerId = '';
    }
  }
  _addRelayStoredMessagePage(
    receiverBridge: receiverBridge,
    groupId: groupId,
    fromPeerId: fromPeerId,
    storedMessage: storedMessage,
  );
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
    this.inboxStoreFailuresRemaining = 0,
    this.inboxStoreResponse,
    Map<String, Completer<void>>? commandGates,
  }) : operationLog = operationLog ?? <String>[],
       commandGates = commandGates ?? <String, Completer<void>>{};

  final FakeGroupPubSubNetwork network;
  final InMemoryGroupMessageRepository msgRepo;
  final InMemoryGroupRepository groupRepo;
  final List<String> operationLog;
  int publishFailuresRemaining;
  int inboxStoreFailuresRemaining;
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
      case 'group.encrypt':
        if (!responses.containsKey(cmd)) {
          final payload = parsed['payload'] as Map<String, dynamic>;
          return jsonEncode({
            'ok': true,
            'ciphertext': payload['plaintext'],
            'nonce': 'fake-group-nonce',
          });
        }
        return jsonEncode(responses[cmd]!);
      case 'group.decrypt':
        if (!responses.containsKey(cmd)) {
          final payload = parsed['payload'] as Map<String, dynamic>;
          return jsonEncode({'ok': true, 'plaintext': payload['ciphertext']});
        }
        return jsonEncode(responses[cmd]!);
      case 'group:publish':
        return _handlePublish(parsed['payload'] as Map<String, dynamic>);
      case 'group:inboxStore':
        if (inboxStoreFailuresRemaining > 0) {
          inboxStoreFailuresRemaining--;
          return jsonEncode({'ok': false, 'errorCode': 'INBOX_STORE_FAILED'});
        }
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

String _extensionForMime(String mime) {
  if (mime == 'image/png') return '.png';
  if (mime == 'image/jpeg') return '.jpg';
  if (mime == 'audio/mp4' || mime == 'audio/x-m4a') return '.m4a';
  if (mime == 'audio/mpeg') return '.mp3';
  if (mime == 'video/mp4') return '.mp4';
  return '';
}

Future<void> _sendText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pump();
}

Future<void> _pumpUntilAsyncCondition(
  WidgetTester tester, {
  required bool Function() condition,
  int maxTicks = 200,
}) async {
  var ticks = 0;
  while (!condition() && ticks < maxTicks) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
    ticks++;
  }
  expect(condition(), isTrue, reason: 'Condition was not met in time');
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
    mediaFileManager: _Section10TempMediaFileManager(tempDir),
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
      await _pumpUntilAsyncCondition(
        tester,
        condition: () => senderBridge.commandLog.contains('group:inboxStore'),
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
  final inboxEnvelope = _decodedGroupReplayPayload(
    inboxPayload['message'] as String,
  );
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
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  tearDown(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  Future<void> pumpUntilAsync(
    Future<bool> Function() condition, {
    int maxPumps = 40,
  }) async {
    var pumps = 0;
    while (!(await condition()) && pumps < maxPumps) {
      await pump();
      pumps++;
    }
  }

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
      'live reaction replay on resume keeps a single truthful stored reaction after rejoin',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-reaction-resume-peer',
          username: 'Admin',
          network: network,
          bridge: _CursorInboxBridge(),
          reactionRepo: FakeReactionRepository(),
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-reaction-resume-peer',
          username: 'Bob',
          network: network,
          reactionRepo: FakeReactionRepository(),
        );
        final adminBridge = admin.bridge as _CursorInboxBridge;

        const groupId = 'group-reaction-resume';
        final joinedAt = DateTime.now().toUtc();

        await admin.createGroup(groupId: groupId, name: 'Reaction Resume');
        await admin.addMember(groupId: groupId, invitee: bob);

        Future<void> saveKey(GroupTestUser user, int generation) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: generation,
              encryptedKey: 'k$generation',
              createdAt: joinedAt,
            ),
          );
        }

        await saveKey(admin, 1);
        await saveKey(bob, 1);

        admin.start();
        bob.start();

        final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Reaction target',
        );
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        final received = bobMessages.firstWhere(
          (message) => message.id == sentMessage!.id,
        );

        final liveReactionChange =
            admin.groupMessageListener.groupReactionChangeStream.first;
        final (reactionResult, reaction) = await bob.sendGroupReactionViaBridge(
          groupId: groupId,
          messageId: received.id,
          emoji: '🔥',
        );
        expect(reactionResult, group_react.SendGroupReactionResult.success);
        expect(reaction, isNotNull);

        final liveChange = await liveReactionChange;
        expect(liveChange.messageId, received.id);
        expect(liveChange.senderPeerId, bob.peerId);

        var adminReactions = await admin.reactionRepo!.getReactionsForMessage(
          received.id,
        );
        expect(adminReactions, hasLength(1));
        expect(adminReactions.single.emoji, '🔥');
        expect(adminReactions.single.senderPeerId, bob.peerId);

        final inboxPayload = latestBridgePayload(
          bob.bridge,
          'group:inboxStore',
        );
        final replayMessage = inboxPayload['message'] as String;
        final replayEnvelope = _storedGroupReplayEnvelope(replayMessage);
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_reaction');

        network.unsubscribe(groupId, admin.peerId);
        adminBridge.addPage(groupId, '', [
          {
            'from': bob.peerId,
            'message': replayMessage,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ], '');

        await rejoinGroupTopics(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          reason: RejoinReason.startup,
        );
        network.subscribe(groupId, admin.peerId);

        await drainGroupOfflineInbox(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          msgRepo: admin.msgRepo,
          reactionRepo: admin.reactionRepo,
        );

        adminReactions = await admin.reactionRepo!.getReactionsForMessage(
          received.id,
        );
        expect(adminReactions, hasLength(1));
        expect(adminReactions.single.emoji, '🔥');
        expect(adminReactions.single.senderPeerId, bob.peerId);
        expect(admin.bridge.commandLog, contains('group:join'));

        admin.dispose();
        bob.dispose();
      },
    );

    test(
      'post-rotation reaction replay after rejoin keeps the truthful reactor on the rotated message',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-reaction-rotation-peer',
          username: 'Admin',
          network: network,
          bridge: _CursorInboxBridge(),
          reactionRepo: FakeReactionRepository(),
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-reaction-rotation-peer',
          username: 'Reader',
          network: network,
          reactionRepo: FakeReactionRepository(),
        );
        final adminBridge = admin.bridge as _CursorInboxBridge;

        const groupId = 'group-reaction-rotation';
        final joinedAt = DateTime.now().toUtc();

        await admin.createGroup(groupId: groupId, name: 'Reaction Rotation');
        await admin.addMember(groupId: groupId, invitee: reader);

        Future<void> saveKey(GroupTestUser user, int generation) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: generation,
              encryptedKey: 'k$generation',
              createdAt: joinedAt,
            ),
          );
        }

        await saveKey(admin, 1);
        await saveKey(reader, 1);

        admin.start();
        reader.start();

        await saveKey(admin, 2);
        await saveKey(reader, 2);

        final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'After rotation reaction target',
        );
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 2);

        await pump();
        final readerMessages = await reader.loadGroupMessages(groupId);
        final delivered = readerMessages.firstWhere(
          (message) => message.id == sentMessage.id,
        );
        expect(delivered.keyGeneration, 2);

        network.unsubscribe(groupId, admin.peerId);

        final (reactionResult, reaction) = await reader
            .sendGroupReactionViaBridge(
              groupId: groupId,
              messageId: delivered.id,
              emoji: '👍',
            );
        expect(reactionResult, group_react.SendGroupReactionResult.success);
        expect(reaction, isNotNull);

        final inboxPayload = latestBridgePayload(
          reader.bridge,
          'group:inboxStore',
        );
        final replayMessage = inboxPayload['message'] as String;
        final replayEnvelope = _storedGroupReplayEnvelope(replayMessage);
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_reaction');

        adminBridge.addPage(groupId, '', [
          {
            'from': reader.peerId,
            'message': replayMessage,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ], '');
        expect(
          await admin.reactionRepo!.getReactionsForMessage(delivered.id),
          isEmpty,
        );

        await rejoinGroupTopics(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          reason: RejoinReason.startup,
        );
        network.subscribe(groupId, admin.peerId);

        await drainGroupOfflineInbox(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          msgRepo: admin.msgRepo,
          reactionRepo: admin.reactionRepo,
        );

        final recoveredReactions = await admin.reactionRepo!
            .getReactionsForMessage(delivered.id);
        expect(recoveredReactions, hasLength(1));
        expect(recoveredReactions.single.emoji, '👍');
        expect(recoveredReactions.single.senderPeerId, reader.peerId);
        expect(admin.bridge.commandLog, contains('group:join'));

        admin.dispose();
        reader.dispose();
      },
    );

    test(
      'resume retry replays failed reaction add/remove stores and converges to the final removed state',
      () async {
        final adminBridge = _Section10MirroringBridge(
          network: network,
          msgRepo: InMemoryGroupMessageRepository(),
          groupRepo: InMemoryGroupRepository(),
        );
        final admin = GroupTestUser.create(
          peerId: 'admin-reaction-retry-peer',
          username: 'Admin',
          network: network,
          bridge: adminBridge,
          reactionRepo: FakeReactionRepository(),
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-reaction-retry-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
          reactionRepo: FakeReactionRepository(),
        );
        final readerBridge = reader.bridge as _CursorInboxBridge;

        const groupId = 'group-reaction-retry-resume';
        await admin.createGroup(groupId: groupId, name: 'Reaction Retry');
        await admin.addMember(groupId: groupId, invitee: reader);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(reader, groupId, 1, 'k1');

        admin.start();
        reader.start();

        final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Reaction retry target',
        );
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);

        await pump();
        final readerMessages = await reader.loadGroupMessages(groupId);
        final delivered = readerMessages.firstWhere(
          (message) => message.id == sentMessage!.id,
        );

        network.unsubscribe(groupId, reader.peerId);
        adminBridge.inboxStoreFailuresRemaining = 2;

        final (addResult, addReaction) = await group_react.sendGroupReaction(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          msgRepo: admin.msgRepo,
          reactionRepo: admin.reactionRepo!,
          reactionReplayOutboxRepo: admin.reactionReplayOutboxRepo,
          groupId: groupId,
          messageId: delivered.id,
          emoji: '🔥',
          senderPeerId: admin.peerId,
          senderPublicKey: admin.publicKey,
          senderPrivateKey: admin.privateKey,
        );
        expect(addResult, group_react.SendGroupReactionResult.success);
        expect(addReaction, isNotNull);

        final removeResult = await removeGroupReaction(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          reactionRepo: admin.reactionRepo!,
          reactionReplayOutboxRepo: admin.reactionReplayOutboxRepo,
          groupId: groupId,
          messageId: delivered.id,
          emoji: '🔥',
          senderPeerId: admin.peerId,
          senderPublicKey: admin.publicKey,
          senderPrivateKey: admin.privateKey,
        );
        expect(removeResult, RemoveGroupReactionResult.success);

        await pump();

        final pendingEntries = await admin.reactionReplayOutboxRepo
            .loadRetryableEntries(limit: 10);
        expect(pendingEntries, hasLength(2));
        expect(
          pendingEntries.map((entry) => entry.action),
          containsAll(<String>['add', 'remove']),
        );

        final inboxStoreCountBeforeRetry = bridgePayloads(
          admin.bridge,
          'group:inboxStore',
        ).length;

        await simulateBackgroundForegroundCycle(
          bridge: admin.bridge,
          p2pService: FakeP2PService(),
          messageRepo: InMemoryMessageRepository(),
          groupMsgRepo: admin.msgRepo,
          retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(
            bridge: admin.bridge,
            msgRepo: admin.msgRepo,
            reactionReplayOutboxRepo: admin.reactionReplayOutboxRepo,
          ),
        );

        final retriedInboxStores = bridgePayloads(
          admin.bridge,
          'group:inboxStore',
        ).skip(inboxStoreCountBeforeRetry).toList(growable: false);
        expect(retriedInboxStores, hasLength(2));

        readerBridge.addPage(groupId, '', [
          {
            'from': admin.peerId,
            'message': retriedInboxStores[0]['message'] as String,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          {
            'from': admin.peerId,
            'message': retriedInboxStores[1]['message'] as String,
            'timestamp': DateTime.now().millisecondsSinceEpoch + 1,
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: reader.bridge,
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
          reactionRepo: reader.reactionRepo,
        );

        final recoveredReactions = await reader.reactionRepo!
            .getReactionsForMessage(delivered.id);
        expect(
          recoveredReactions,
          isEmpty,
          reason: 'offline reader should converge to the final removed state',
        );

        final retryableAfterResume = await admin.reactionReplayOutboxRepo
            .loadRetryableEntries(limit: 10);
        expect(retryableAfterResume, isEmpty);
      },
    );

    test(
      'removed offline member drains replayed removal, loses group access, and cannot send after resume',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-offline-remove-peer',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-offline-remove-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-offline-remove-peer',
          username: 'Charlie',
          network: network,
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-offline-member-removed';
        final joinedAt = DateTime.now().toUtc();

        await admin.createGroup(groupId: groupId, name: 'Offline Removal');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'test-key',
              createdAt: joinedAt,
            ),
          );
        }

        await saveKey(admin);
        await saveKey(bob);
        await saveKey(charlie);

        admin.start();
        bob.start();
        charlie.start();

        final removedGroups = <String>[];
        final removedSub = bob.groupMessageListener.groupRemovedStream.listen(
          removedGroups.add,
        );

        network.unsubscribe(groupId, bob.peerId);

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        expect(await bob.groupRepo.getGroup(groupId), isNotNull);
        expect(removedGroups, isEmpty);

        final group = await admin.groupRepo.getGroup(groupId);
        final remainingMembers = await admin.groupRepo.getMembers(groupId);
        final removalSystemMessage = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': bob.peerId, 'username': 'Bob'},
          'groupConfig': {
            'name': group!.name,
            'groupType': group.type.toValue(),
            if (group.description != null) 'description': group.description,
            'members': remainingMembers
                .map(
                  (member) => {
                    'peerId': member.peerId,
                    'username': member.username,
                    'role': member.role.toValue(),
                    'publicKey': member.publicKey,
                  },
                )
                .toList(),
            'createdBy': group.createdBy,
            'createdAt': group.createdAt.toUtc().toIso8601String(),
          },
        });

        await callGroupInboxStore(
          admin.bridge,
          groupId,
          jsonEncode({
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'keyEpoch': 0,
            'text': removalSystemMessage,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }),
          recipientPeerIds: [bob.peerId],
        );

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
          groupMessageListener: bob.groupMessageListener,
        );

        expect(removedGroups, contains(groupId));
        expect(await bob.groupRepo.getGroup(groupId), isNull);
        expect(bob.bridge.commandLog, contains('group:leave'));
        expect(await bob.loadGroupMessages(groupId), isEmpty);

        final (result, message) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Should not send after offline removal',
        );

        expect(result, SendGroupMessageResult.groupNotFound);
        expect(message, isNull);
        expect(
          bob.bridge.commandLog.where((command) => command == 'group:publish'),
          isEmpty,
        );

        await removedSub.cancel();
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'offline remaining member drains remove-vs-send backlog and keeps the same before-cutoff outcome after resume',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-offline-remaining-peer',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-offline-remaining-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-offline-remaining-peer',
          username: 'Charlie',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final charlieBridge = charlie.bridge as _CursorInboxBridge;

        const groupId = 'group-offline-remaining-cutoff';
        final joinedAt = DateTime.now().toUtc();

        await admin.createGroup(groupId: groupId, name: 'Offline Remaining');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'test-key',
              createdAt: joinedAt,
            ),
          );
        }

        await saveKey(admin);
        await saveKey(bob);
        await saveKey(charlie);

        admin.start();
        bob.start();
        charlie.start();

        network.unsubscribe(groupId, charlie.peerId);

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        expect(
          await charlie.groupRepo.getMember(groupId, bob.peerId),
          isNotNull,
        );

        final adminMessages = await admin.loadGroupMessages(groupId);
        final removalEntry = adminMessages.firstWhere(
          (message) => message.id.startsWith(
            'sys-member_removed:$groupId:${bob.peerId}:',
          ),
        );
        final removedAt = removalEntry.timestamp.toUtc();

        final group = await admin.groupRepo.getGroup(groupId);
        final remainingMembers = await admin.groupRepo.getMembers(groupId);
        final removalSystemMessage = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': bob.peerId, 'username': 'Bob'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': {
            'name': group!.name,
            'groupType': group.type.toValue(),
            if (group.description != null) 'description': group.description,
            'members': remainingMembers
                .map(
                  (member) => {
                    'peerId': member.peerId,
                    'username': member.username,
                    'role': member.role.toValue(),
                    'publicKey': member.publicKey,
                  },
                )
                .toList(),
            'createdBy': group.createdBy,
            'createdAt': group.createdAt.toUtc().toIso8601String(),
          },
        });

        charlieBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'keyEpoch': 0,
            'text': removalSystemMessage,
            'timestamp': removedAt.toIso8601String(),
            'messageId': 'msg-remove-bob-replay',
          },
          {
            'groupId': groupId,
            'senderId': bob.peerId,
            'senderUsername': 'Bob',
            'keyEpoch': 1,
            'text': 'Before cutoff replay',
            'timestamp': removedAt
                .subtract(const Duration(milliseconds: 1))
                .toIso8601String(),
            'messageId': 'msg-before-cutoff-replay',
          },
        ], 'cursor-after-cutoff');

        charlieBridge.addPage(groupId, 'cursor-after-cutoff', [
          {
            'groupId': groupId,
            'senderId': bob.peerId,
            'senderUsername': 'Bob',
            'keyEpoch': 1,
            'text': 'At cutoff replay',
            'timestamp': removedAt.toIso8601String(),
            'messageId': 'msg-at-cutoff-replay',
          },
        ], '');

        await rejoinGroupTopics(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          reason: RejoinReason.startup,
        );
        network.subscribe(groupId, charlie.peerId);
        await drainGroupOfflineInbox(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupMessageListener: charlie.groupMessageListener,
        );

        expect(await charlie.groupRepo.getMember(groupId, bob.peerId), isNull);

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          charlieMessages.where(
            (message) => message.text == 'Before cutoff replay',
          ),
          hasLength(1),
        );
        expect(
          charlieMessages.where(
            (message) => message.text == 'At cutoff replay',
          ),
          isEmpty,
        );
        expect(
          charlieMessages.where(
            (message) => message.id.startsWith(
              'sys-member_removed:$groupId:${bob.peerId}:',
            ),
          ),
          hasLength(1),
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
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

        await _saveKey(admin, groupId, 1, 'test-key');
        await _saveKey(reader, groupId, 1, 'test-key');
        await _saveKey(onlineReader, groupId, 1, 'test-key');

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
      'announcement media send with zero topic peers stays sent and readers recover intact media refs after resume',
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
        expect(sent!.status, 'sent');
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

    testWidgets(
      'MM-012 acceptance uses real GroupConversationWired sender path to keep discussion sendable and announcement admin blocked during active recovery',
      (tester) async {
        addTearDown(groupRecoveryGate.resetForTest);

        Future<void> expectDiscussionAllowed({
          required String groupId,
          required String name,
          required String draftText,
        }) async {
          final sender = GroupTestUser.create(
            peerId: '$groupId-peer',
            username: 'Alice',
            network: network,
          );
          addTearDown(sender.dispose);

          await sender.createGroup(
            groupId: groupId,
            name: name,
            type: GroupType.chat,
          );
          await _saveKey(sender, groupId, 1, 'k1');

          await _pumpSection10SenderWidget(
            tester,
            sender: sender,
            groupId: groupId,
            bridge: sender.bridge,
          );

          groupRecoveryGate.begin();
          try {
            await _sendText(tester, draftText);
            await _pumpFrames(tester, count: 20);
          } finally {
            groupRecoveryGate.end();
          }

          expect(
            sender.bridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            sender.bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(1),
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text,
            isEmpty,
          );
          expect(find.text(draftText), findsOneWidget);
          expect(
            (await sender.msgRepo.getMessagesPage(groupId, limit: 20)).where(
              (message) => !message.isIncoming && message.text == draftText,
            ),
            hasLength(1),
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }

        Future<void> expectAnnouncementBlocked({
          required String groupId,
          required String name,
          required String draftText,
        }) async {
          final sender = GroupTestUser.create(
            peerId: '$groupId-peer',
            username: 'Alice',
            network: network,
          );
          addTearDown(sender.dispose);

          await sender.createGroup(
            groupId: groupId,
            name: name,
            type: GroupType.announcement,
          );
          await _saveKey(sender, groupId, 1, 'k1');

          await _pumpSection10SenderWidget(
            tester,
            sender: sender,
            groupId: groupId,
            bridge: sender.bridge,
          );

          groupRecoveryGate.begin();
          try {
            await _sendText(tester, draftText);
            await _pumpFrames(tester, count: 20);
          } finally {
            groupRecoveryGate.end();
          }

          expect(
            sender.bridge.commandLog.where((cmd) => cmd == 'group:publish'),
            isEmpty,
          );
          expect(
            sender.bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            isEmpty,
          );
          expect(find.text(draftText), findsOneWidget);
          expect(
            (await sender.msgRepo.getMessagesPage(groupId, limit: 20)).where(
              (message) => !message.isIncoming && message.text == draftText,
            ),
            isEmpty,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }

        await expectDiscussionAllowed(
          groupId: 'group-recovery-send-chat',
          name: 'Recovery Chat',
          draftText: 'Discussion recovery send',
        );
        await expectAnnouncementBlocked(
          groupId: 'group-recovery-send-announce',
          name: 'Recovery Announcement',
          draftText: 'Announcement recovery block',
        );
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

    test(
      'multi page replay with a tampered timestamp still keeps one stored row',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-nodup-timestamp';
        const sharedMsgId = 'msg-shared-timestamp';
        // Keep the replay payload comfortably inside the retention window so
        // this test continues to exercise messageId dedupe instead of aging
        // into backlog-expiry behavior as the calendar advances.
        final originalTimestamp = DateTime.now().toUtc().subtract(
          const Duration(hours: 2),
        );
        final tamperedTimestamp = originalTimestamp.add(
          const Duration(minutes: 10),
        );

        await user.createGroup(groupId: groupId, name: 'No Dup Timestamp');
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: originalTimestamp,
          ),
        );

        userBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Same message',
            'timestamp': originalTimestamp.toIso8601String(),
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
            'timestamp': tamperedTimestamp.toIso8601String(),
            'messageId': sharedMsgId,
          },
        ], '');

        user.start();

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        final msgs = await user.msgRepo.getMessagesPage(groupId);
        expect(msgs, hasLength(1));
        expect(
          msgs.single.id,
          sharedMsgId,
          reason: 'Tampered replay must not materialize a second row',
        );
        expect(
          msgs.single.timestamp,
          originalTimestamp,
          reason: 'Replay must not rewrite the accepted timestamp ordering',
        );

        user.dispose();
      },
    );

    test(
      'long-offline mixed-window recovery keeps retained backlog and never resurrects expired pages',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-retention-mixed-window';
        await user.createGroup(groupId: groupId, name: 'Retention Window');
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final cutoff = groupBacklogRetentionCutoff(DateTime.now().toUtc());
        final expiredAt = cutoff.subtract(const Duration(hours: 1));
        final retainedAt = cutoff.add(const Duration(hours: 1));

        userBridge.addPage(groupId, '', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Expired page',
            'timestamp': expiredAt.toIso8601String(),
            'messageId': 'msg-expired-window',
          },
        ], 'cursor-retained-window');

        userBridge.addPage(groupId, 'cursor-retained-window', [
          {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'Retained page',
            'timestamp': retainedAt.toIso8601String(),
            'messageId': 'msg-retained-window',
          },
        ], '');

        user.start();

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );
        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        final messages = await user.msgRepo.getMessagesPage(groupId);
        final group = await user.groupRepo.getGroup(groupId);
        final cursorCmds = userBridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
            .toList();

        expect(messages, hasLength(1));
        expect(messages.single.id, 'msg-retained-window');
        expect(
          messages.where((message) => message.id == 'msg-expired-window'),
          isEmpty,
        );
        expect(group, isNotNull);
        expect(group!.lastBacklogExpiredAt, expiredAt);
        expect(group.lastBacklogRetainedAt, retainedAt);
        expect(
          cursorCmds,
          hasLength(4),
          reason:
              'Each drain should continue past the expired page and finish the retained cursor page',
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
        expect(sent!.status, 'sent');
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

      test(
        "inbox store failure doesn't block publish but leaves sender state pending",
        () async {
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
          expect(sent!.status, 'pending');
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
        },
      );

      test(
        'zero-peer inbox failure stays owned by failed-message retry and recovers in place',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            inboxStoreFailuresRemaining: 1,
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-zero-peer-failed-retry-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-zero-peer-failed-retry-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;

          const groupId = 'group-zero-peer-failed-retry';
          await admin.createGroup(groupId: groupId, name: 'Zero Peer Retry');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          network.unsubscribe(groupId, bob.peerId);

          admin.start();
          bob.start();

          final (initialResult, initialMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'Zero peers need message retry',
              );

          expect(initialResult, SendGroupMessageResult.error);
          expect(initialMessage, isNotNull);
          expect(initialMessage!.status, 'failed');
          expect(initialMessage.inboxStored, isFalse);
          expect(initialMessage.inboxRetryPayload, isNotNull);
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(1),
          );

          final inboxRetried = await retryFailedGroupInboxStores(
            bridge: admin.bridge,
            msgRepo: admin.msgRepo,
          );
          expect(inboxRetried, 0);
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(1),
          );

          final messageRetried = await retryFailedGroupMessages(
            groupMsgRepo: admin.msgRepo,
            groupRepo: admin.groupRepo,
            identityRepo: _Section10IdentityRepository(_identityForUser(admin)),
            bridge: admin.bridge,
            mediaAttachmentRepo: admin.mediaAttachmentRepo,
          );
          expect(messageRetried, 1);

          final recovered = await admin.msgRepo.getMessage(initialMessage.id);
          expect(recovered, isNotNull);
          expect(recovered!.id, initialMessage.id);
          expect(recovered.status, 'sent');
          expect(recovered.inboxStored, isTrue);
          expect(recovered.inboxRetryPayload, isNull);
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(2),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(2),
          );

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
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == initialMessage.id &&
                  message.text == 'Zero peers need message retry',
            ),
            hasLength(1),
          );

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'rapid pause/resume closes a pending live-peer send via inbox retry exactly once',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            inboxStoreFailuresRemaining: 1,
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-rapid-pending-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final liveReader = GroupTestUser.create(
            peerId: 'reader-rapid-live-peer',
            username: 'Bob',
            network: network,
          );
          final inboxReader = GroupTestUser.create(
            peerId: 'reader-rapid-inbox-peer',
            username: 'Carol',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final inboxBridge = inboxReader.bridge as _CursorInboxBridge;
          var injectedRecoveredInbox = false;

          const groupId = 'group-rapid-pending-recovery';
          await admin.createGroup(groupId: groupId, name: 'Rapid Pending');
          await admin.addMember(groupId: groupId, invitee: liveReader);
          await admin.addMember(groupId: groupId, invitee: inboxReader);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(liveReader, groupId, 1, 'k1');
          await _saveKey(inboxReader, groupId, 1, 'k1');
          network.unsubscribe(groupId, inboxReader.peerId);

          admin.start();
          liveReader.start();
          inboxReader.start();

          final (initialResult, initialMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'Rapid pending recovery',
              );

          expect(initialResult, SendGroupMessageResult.success);
          expect(initialMessage, isNotNull);
          expect(initialMessage!.status, 'pending');
          expect(initialMessage.inboxStored, isFalse);
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(1),
          );

          await pump();
          final liveBeforeResume = await liveReader.loadGroupMessages(groupId);
          expect(
            liveBeforeResume.where(
              (message) => message.id == initialMessage.id,
            ),
            hasLength(1),
          );

          await simulateRapidLockUnlock(
            bridge: admin.bridge,
            p2pService: FakeP2PService(),
            messageRepo: InMemoryMessageRepository(),
            groupMsgRepo: admin.msgRepo,
            cycles: 2,
            retryFailedGroupInboxStoresFn: () async {
              final retried = await retryFailedGroupInboxStores(
                bridge: admin.bridge,
                msgRepo: admin.msgRepo,
              );
              if (retried > 0 && !injectedRecoveredInbox) {
                _injectInboxMessageFromLatestStore(
                  senderBridge: admin.bridge,
                  receiverBridge: inboxBridge,
                  receiverPeerId: inboxReader.peerId,
                  groupId: groupId,
                );
                injectedRecoveredInbox = true;
              }
              return retried;
            },
          );

          await drainGroupOfflineInbox(
            bridge: inboxReader.bridge,
            groupRepo: inboxReader.groupRepo,
            msgRepo: inboxReader.msgRepo,
          );

          final finalMessage = await _latestOutgoingMessage(
            admin.msgRepo,
            groupId,
            text: 'Rapid pending recovery',
          );
          expect(finalMessage.id, initialMessage.id);
          expect(finalMessage.status, 'sent');
          expect(finalMessage.inboxStored, isTrue);
          expect(finalMessage.inboxRetryPayload, isNull);
          expect(
            (await admin.msgRepo.getMessagesPage(groupId, limit: 20)).where(
              (message) =>
                  !message.isIncoming &&
                  message.text == 'Rapid pending recovery',
            ),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(2),
          );

          final liveAfterResume = await liveReader.loadGroupMessages(groupId);
          expect(
            liveAfterResume.where((message) => message.id == initialMessage.id),
            hasLength(1),
          );

          final inboxRecoveredMessages = await inboxReader.loadGroupMessages(
            groupId,
          );
          expect(
            inboxRecoveredMessages.where(
              (message) => message.id == initialMessage.id,
            ),
            hasLength(1),
          );

          admin.dispose();
          liveReader.dispose();
          inboxReader.dispose();
        },
      );

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

        await pump();
        final preDrainOnlineMessages = await onlineReader.loadGroupMessages(
          groupId,
        );
        expect(
          preDrainOnlineMessages.where(
            (message) => message.text == 'Partial delivery',
          ),
          hasLength(1),
        );
        expect(await inboxReaderOne.loadGroupMessages(groupId), isEmpty);
        expect(await inboxReaderTwo.loadGroupMessages(groupId), isEmpty);

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
          onlineMessages.where((message) => message.text == 'Partial delivery'),
          hasLength(1),
        );
        expect(
          inboxMessagesOne.where(
            (message) => message.text == 'Partial delivery',
          ),
          hasLength(1),
        );
        expect(
          inboxMessagesTwo.where(
            (message) => message.text == 'Partial delivery',
          ),
          hasLength(1),
        );

        admin.dispose();
        onlineReader.dispose();
        inboxReaderOne.dispose();
        inboxReaderTwo.dispose();
      });

      test(
        'temporary partition replays missed backlog in cursor order and resumes live delivery after heal',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-partition-peer',
            username: 'Alice',
            network: network,
          );
          final onlineReader = GroupTestUser.create(
            peerId: 'reader-partition-online-peer',
            username: 'Bob',
            network: network,
          );
          final partitionedReader = GroupTestUser.create(
            peerId: 'reader-partition-offline-peer',
            username: 'Carol',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final partitionBridge =
              partitionedReader.bridge as _CursorInboxBridge;

          const groupId = 'group-partition-heal';
          await admin.createGroup(groupId: groupId, name: 'Partition Heal');
          await admin.addMember(groupId: groupId, invitee: onlineReader);
          await admin.addMember(groupId: groupId, invitee: partitionedReader);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(onlineReader, groupId, 1, 'k1');
          await _saveKey(partitionedReader, groupId, 1, 'k1');

          admin.start();
          onlineReader.start();
          partitionedReader.start();

          await admin.sendGroupMessage(groupId: groupId, text: 'Before split');
          await pump();

          var onlineTexts = (await onlineReader.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toList(growable: false);
          var partitionedTexts =
              (await partitionedReader.loadGroupMessages(groupId))
                  .where((message) => message.isIncoming)
                  .map((message) => message.text)
                  .toList(growable: false);
          expect(onlineTexts, ['Before split']);
          expect(partitionedTexts, ['Before split']);

          network.unsubscribe(groupId, partitionedReader.peerId);
          expect(
            network.isSubscribed(groupId, partitionedReader.peerId),
            isFalse,
          );

          final (firstResult, firstSent) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'During split 1',
              );
          final (secondResult, secondSent) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'During split 2',
              );

          expect(firstResult, SendGroupMessageResult.success);
          expect(firstSent, isNotNull);
          expect(firstSent!.inboxStored, isTrue);
          expect(secondResult, SendGroupMessageResult.success);
          expect(secondSent, isNotNull);
          expect(secondSent!.inboxStored, isTrue);

          await pumpUntilAsync(() async {
            final texts = (await onlineReader.loadGroupMessages(groupId))
                .where((message) => message.isIncoming)
                .map((message) => message.text)
                .toList(growable: false);
            return texts.length >= 3;
          }, maxPumps: 120);

          onlineTexts = (await onlineReader.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toList(growable: false);
          partitionedTexts =
              (await partitionedReader.loadGroupMessages(groupId))
                  .where((message) => message.isIncoming)
                  .map((message) => message.text)
                  .toList(growable: false);
          expect(onlineTexts, [
            'Before split',
            'During split 1',
            'During split 2',
          ]);
          expect(
            partitionedTexts,
            ['Before split'],
            reason: 'Partitioned peer should miss split-window live delivery',
          );

          final inboxStores = bridgePayloads(admin.bridge, 'group:inboxStore');
          expect(inboxStores, hasLength(2));
          for (final payload in inboxStores) {
            expect(
              (payload['recipientPeerIds'] as List<dynamic>).cast<String>(),
              contains(partitionedReader.peerId),
            );
          }

          _addRelayStoredMessagePage(
            receiverBridge: partitionBridge,
            groupId: groupId,
            fromPeerId: admin.peerId,
            storedMessage: inboxStores[0]['message'] as String,
            nextCursor: 'cursor-partition-page-2',
          );
          _addRelayStoredMessagePage(
            receiverBridge: partitionBridge,
            groupId: groupId,
            fromPeerId: admin.peerId,
            storedMessage: inboxStores[1]['message'] as String,
            cursor: 'cursor-partition-page-2',
          );

          await rejoinGroupTopics(
            bridge: partitionedReader.bridge,
            groupRepo: partitionedReader.groupRepo,
          );
          await drainGroupOfflineInbox(
            bridge: partitionedReader.bridge,
            groupRepo: partitionedReader.groupRepo,
            msgRepo: partitionedReader.msgRepo,
          );
          network.subscribe(groupId, partitionedReader.peerId);
          expect(
            network.isSubscribed(groupId, partitionedReader.peerId),
            isTrue,
          );

          partitionedTexts =
              (await partitionedReader.loadGroupMessages(groupId))
                  .where((message) => message.isIncoming)
                  .map((message) => message.text)
                  .toList(growable: false);
          expect(partitionedTexts, [
            'Before split',
            'During split 1',
            'During split 2',
          ]);

          await admin.sendGroupMessage(groupId: groupId, text: 'After heal');
          await pump();

          onlineTexts = (await onlineReader.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toList(growable: false);
          partitionedTexts =
              (await partitionedReader.loadGroupMessages(groupId))
                  .where((message) => message.isIncoming)
                  .map((message) => message.text)
                  .toList(growable: false);
          expect(onlineTexts, [
            'Before split',
            'During split 1',
            'During split 2',
            'After heal',
          ]);
          expect(partitionedTexts, [
            'Before split',
            'During split 1',
            'During split 2',
            'After heal',
          ]);

          final cursorCmds = partitionBridge.sentMessages
              .map((message) => jsonDecode(message) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
              .toList(growable: false);
          expect(cursorCmds, hasLength(2));
          expect(cursorCmds[0]['payload']['cursor'], '');
          expect(cursorCmds[1]['payload']['cursor'], 'cursor-partition-page-2');

          admin.dispose();
          onlineReader.dispose();
          partitionedReader.dispose();
        },
      );

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
        final charlie = GroupTestUser.create(
          peerId: 'reader-retry-peer-2',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-retry-after-network';
        await admin.createGroup(groupId: groupId, name: 'Retry After Recovery');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');
        await _saveKey(charlie, groupId, 1, 'k1');

        admin.start();
        bob.start();
        charlie.start();

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
          bobMessages.where((message) => message.id == initialSent.id),
          hasLength(1),
        );

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          charlieMessages.where((message) => message.id == initialSent.id),
          hasLength(1),
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      });

      test(
        'unread count stays correct across duplicate inbox drain, retry recovery, and read clear',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-unread-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-unread-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;

          const groupId = 'group-unread-005';
          await admin.createGroup(groupId: groupId, name: 'Unread Accuracy');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final (firstResult, firstMessage) = await admin
              .sendGroupMessageViaBridge(groupId: groupId, text: 'Live once');

          expect(firstResult, SendGroupMessageResult.success);
          expect(firstMessage, isNotNull);

          await pump();
          expect(await bob.msgRepo.getUnreadCount(groupId), 1);
          var summary = await bob.msgRepo.getGroupThreadSummary(groupId);
          expect(summary.unreadCount, 1);
          expect(summary.latestMessage?.text, 'Live once');

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

          await pump();
          final bobAfterDuplicate = await bob.loadGroupMessages(groupId);
          expect(
            bobAfterDuplicate.where(
              (message) => message.id == firstMessage!.id && message.isIncoming,
            ),
            hasLength(1),
            reason: 'Duplicate inbox drain must not create a second unread row',
          );
          expect(
            await bob.msgRepo.getUnreadCount(groupId),
            1,
            reason: 'Duplicate recovery must not double-count unread state',
          );

          adminBridge.publishFailuresRemaining = 1;
          final (retryInitialResult, retryInitialMessage) = await admin
              .sendGroupMessageViaBridge(groupId: groupId, text: 'Retry once');

          expect(retryInitialResult, SendGroupMessageResult.error);
          expect(retryInitialMessage, isNotNull);
          expect(retryInitialMessage!.status, 'failed');
          expect(
            await bob.msgRepo.getUnreadCount(groupId),
            1,
            reason: 'Unread must not change until retry actually delivers',
          );

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
            text: 'Retry once',
          );
          expect(finalMessage.id, retryInitialMessage.id);
          expect(finalMessage.status, 'sent');

          await pump();
          final bobAfterRetry = await bob.loadGroupMessages(groupId);
          expect(
            bobAfterRetry.where(
              (message) =>
                  message.id == retryInitialMessage.id && message.isIncoming,
            ),
            hasLength(1),
            reason: 'Successful retry should arrive once for the receiver',
          );
          expect(await bob.msgRepo.getUnreadCount(groupId), 2);
          summary = await bob.msgRepo.getGroupThreadSummary(groupId);
          expect(summary.unreadCount, 2);
          expect(summary.latestMessage?.text, 'Retry once');

          await bob.msgRepo.markAsRead(groupId);

          expect(await bob.msgRepo.getUnreadCount(groupId), 0);
          summary = await bob.msgRepo.getGroupThreadSummary(groupId);
          expect(summary.unreadCount, 0);

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'offline member reconnects after membership churn and converges to the final member list',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-converge-peer',
            username: 'Admin',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-converge-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-converge-peer',
            username: 'Charlie',
            network: network,
          );
          final diana = GroupTestUser.create(
            peerId: 'diana-converge-peer',
            username: 'Diana',
            network: network,
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;

          const groupId = 'group-member-converge-010';

          Future<Map<String, dynamic>> membershipReplayEnvelope({
            required String systemType,
            required Map<String, dynamic> member,
          }) async {
            final group = await admin.groupRepo.getGroup(groupId);
            final members = await admin.groupRepo.getMembers(groupId);
            final groupConfig = {
              'name': group!.name,
              'groupType': group.type.toValue(),
              if (group.description != null) 'description': group.description,
              'members': members
                  .map(
                    (entry) => {
                      'peerId': entry.peerId,
                      'username': entry.username,
                      'role': entry.role.toValue(),
                      'publicKey': entry.publicKey,
                    },
                  )
                  .toList(),
              'createdBy': group.createdBy,
              'createdAt': group.createdAt.toUtc().toIso8601String(),
            };

            return {
              'groupId': groupId,
              'senderId': admin.peerId,
              'senderUsername': admin.username,
              'keyEpoch': 0,
              'text': jsonEncode({
                '__sys': systemType,
                'member': member,
                'groupConfig': groupConfig,
              }),
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            };
          }

          Map<String, String> memberRoleMap(List<GroupMember> members) {
            return {
              for (final member in members)
                member.peerId: member.role.toValue(),
            };
          }

          await admin.createGroup(groupId: groupId, name: 'Reconnect Churn');
          await admin.addMember(groupId: groupId, invitee: bob);
          await admin.addMember(groupId: groupId, invitee: charlie);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          await _saveKey(charlie, groupId, 1, 'k1');

          admin.start();
          bob.start();
          charlie.start();
          await admin.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
          );
          await pump();

          network.unsubscribe(groupId, bob.peerId);

          await admin.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: 'Charlie',
          );
          final removedEnvelope = await membershipReplayEnvelope(
            systemType: 'member_removed',
            member: {'peerId': charlie.peerId, 'username': 'Charlie'},
          );
          await pump();

          await admin.addMember(groupId: groupId, invitee: diana);
          await _saveKey(diana, groupId, 1, 'k1');
          final addedEnvelope = await membershipReplayEnvelope(
            systemType: 'member_added',
            member: {
              'peerId': diana.peerId,
              'username': 'Diana',
              'role': 'writer',
              'publicKey': diana.publicKey,
            },
          );
          await admin.broadcastMemberAdded(groupId: groupId, newMember: diana);
          await pump();

          final staleBobMembers = await bob.groupRepo.getMembers(groupId);
          expect(
            staleBobMembers.map((member) => member.peerId).toSet(),
            contains(charlie.peerId),
          );
          expect(
            staleBobMembers.map((member) => member.peerId).toSet(),
            isNot(contains(diana.peerId)),
          );

          bobBridge.addPage(groupId, '', [removedEnvelope, addedEnvelope], '');

          await rejoinGroupTopics(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            reason: RejoinReason.startup,
          );
          network.subscribe(groupId, bob.peerId);
          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            groupMessageListener: bob.groupMessageListener,
          );

          final adminMembers = await admin.groupRepo.getMembers(groupId);
          final bobMembers = await bob.groupRepo.getMembers(groupId);
          final dianaMembers = await diana.groupRepo.getMembers(groupId);

          expect(memberRoleMap(bobMembers), memberRoleMap(adminMembers));
          expect(memberRoleMap(dianaMembers), memberRoleMap(adminMembers));
          expect(memberRoleMap(adminMembers).keys.toSet(), {
            admin.peerId,
            bob.peerId,
            diana.peerId,
          });

          final adminGroup = await admin.groupRepo.getGroup(groupId);
          final bobGroup = await bob.groupRepo.getGroup(groupId);
          final dianaGroup = await diana.groupRepo.getGroup(groupId);

          expect(bobGroup, isNotNull);
          expect(dianaGroup, isNotNull);
          expect(bobGroup!.name, adminGroup!.name);
          expect(bobGroup.type, adminGroup.type);
          expect(bobGroup.createdBy, adminGroup.createdBy);
          expect(dianaGroup!.name, adminGroup.name);
          expect(dianaGroup.type, adminGroup.type);
          expect(dianaGroup.createdBy, adminGroup.createdBy);

          admin.dispose();
          bob.dispose();
          charlie.dispose();
          diana.dispose();
        },
      );

      test(
        'offline member reconnects after repeated metadata edits and converges to the final metadata state',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-meta-peer',
            username: 'Admin',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-meta-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-meta-peer',
            username: 'Charlie',
            network: network,
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;

          const groupId = 'group-metadata-converge-011';
          await admin.createGroup(
            groupId: groupId,
            name: 'Metadata Start',
            description: 'Original description',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await admin.addMember(groupId: groupId, invitee: charlie);

          admin.start();
          bob.start();
          charlie.start();

          network.unsubscribe(groupId, bob.peerId);

          Future<Map<String, dynamic>> publishMetadataUpdate({
            required String messageId,
            required DateTime eventAt,
            required String name,
            required String description,
          }) async {
            final updatedGroup = await updateGroupMetadata(
              groupRepo: admin.groupRepo,
              groupId: groupId,
              name: name,
              description: description,
              eventAt: eventAt,
            );
            final members = await admin.groupRepo.getMembers(groupId);
            final sysText = jsonEncode({
              '__sys': 'group_metadata_updated',
              'updatedAt': eventAt.toIso8601String(),
              'groupConfig': buildGroupConfigPayload(updatedGroup, members),
            });
            final envelope = <String, dynamic>{
              'groupId': groupId,
              'senderId': admin.peerId,
              'senderUsername': admin.username,
              'keyEpoch': 0,
              'text': sysText,
              'timestamp': eventAt.toIso8601String(),
              'messageId': messageId,
            };
            await network.publish(groupId, admin.peerId, envelope);
            return envelope;
          }

          final olderAt = DateTime.parse('2026-04-05T13:00:00.000Z').toUtc();
          final newerAt = DateTime.parse('2026-04-05T13:05:00.000Z').toUtc();

          final olderEnvelope = await publishMetadataUpdate(
            messageId: 'msg-meta-older',
            eventAt: olderAt,
            name: 'Planning Alpha',
            description: 'First draft',
          );
          await pump();

          final newerEnvelope = await publishMetadataUpdate(
            messageId: 'msg-meta-newer',
            eventAt: newerAt,
            name: 'Planning Final',
            description: 'Final charter',
          );
          await pump();

          final livePeerGroup = await charlie.groupRepo.getGroup(groupId);
          expect(livePeerGroup, isNotNull);
          expect(livePeerGroup!.name, 'Planning Final');
          expect(livePeerGroup.description, 'Final charter');
          expect(livePeerGroup.lastMetadataEventAt, newerAt);

          final offlineBeforeDrain = await bob.groupRepo.getGroup(groupId);
          expect(offlineBeforeDrain, isNotNull);
          expect(offlineBeforeDrain!.name, 'Metadata Start');
          expect(offlineBeforeDrain.description, 'Original description');

          bobBridge.addPage(groupId, '', [newerEnvelope], 'cursor-older-meta');
          bobBridge.addPage(groupId, 'cursor-older-meta', [olderEnvelope], '');

          await rejoinGroupTopics(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            reason: RejoinReason.startup,
          );
          network.subscribe(groupId, bob.peerId);
          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            groupMessageListener: bob.groupMessageListener,
          );

          final convergedGroup = await bob.groupRepo.getGroup(groupId);
          expect(convergedGroup, isNotNull);
          expect(convergedGroup!.name, 'Planning Final');
          expect(convergedGroup.description, 'Final charter');
          expect(convergedGroup.lastMetadataEventAt, newerAt);

          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) => message.text == 'Admin updated the group details',
            ),
            hasLength(1),
          );

          admin.dispose();
          bob.dispose();
          charlie.dispose();
        },
      );

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
