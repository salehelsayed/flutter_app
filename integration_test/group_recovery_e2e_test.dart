import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart'
    as group_dissolve;
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_audio_recorder_service.dart';
import '../test/shared/fakes/fake_mic_permission_gateway.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/fake_group_pubsub_network.dart';
import '../test/shared/fakes/group_test_user.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';

/// Simulates cursor-based group inbox retrieval for simulator-backed smoke runs.
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
      final page = pages['$groupId:$cursor'];
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

    if (cmd == 'payload.sign' && !responses.containsKey(cmd)) {
      return jsonEncode({'ok': true, 'signature': 'fake-signature'});
    }

    if (cmd == 'payload.verify' && !responses.containsKey(cmd)) {
      return jsonEncode({'ok': true, 'valid': true});
    }

    if (cmd == 'group.encrypt' && !responses.containsKey(cmd)) {
      final payload = parsed['payload'] as Map<String, dynamic>;
      return jsonEncode({
        'ok': true,
        'ciphertext': payload['plaintext'],
        'nonce': 'fake-group-nonce',
      });
    }

    if (cmd == 'group.decrypt' && !responses.containsKey(cmd)) {
      final payload = parsed['payload'] as Map<String, dynamic>;
      return jsonEncode({'ok': true, 'plaintext': payload['ciphertext']});
    }

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

class _SequentialMirroringGroupPublishBridge extends _CursorInboxBridge {
  _SequentialMirroringGroupPublishBridge({
    required this.network,
    required this.senderPeerId,
    required this.senderDeviceId,
    required this.publishResponses,
  });

  final FakeGroupPubSubNetwork network;
  final String senderPeerId;
  final String senderDeviceId;
  final List<Map<String, dynamic>> publishResponses;
  int _publishIndex = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd != 'group:publish') {
      return super.send(message);
    }

    commandLog.add(cmd!);
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;

    final payload = parsed['payload'] as Map<String, dynamic>;
    final response =
        publishResponses[_publishIndex < publishResponses.length
            ? _publishIndex
            : publishResponses.length - 1];
    _publishIndex++;

    if (response['ok'] == true) {
      final groupId = payload['groupId'] as String;
      await network.publish(groupId, senderPeerId, {
        'groupId': groupId,
        'senderId': payload['senderPeerId'] as String? ?? senderPeerId,
        'senderUsername': payload['senderUsername'] as String? ?? '',
        'keyEpoch': 1,
        'text': payload['text'] as String? ?? '',
        'timestamp':
            payload['timestamp'] as String? ??
            DateTime.now().toUtc().toIso8601String(),
        'messageId': payload['messageId'] as String? ?? '',
        if (payload['quotedMessageId'] is String)
          'quotedMessageId': payload['quotedMessageId'],
        if (payload['media'] is List<dynamic>)
          'media': payload['media'] as List<dynamic>,
      }, senderDeviceId: senderDeviceId);
    }

    return jsonEncode(response);
  }
}

Future<void> _pumpNetwork() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

Future<void> _pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() predicate, {
  int attempts = 30,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (await predicate()) return;
    await _pumpFrames(tester, count: 2);
  }
  expect(await predicate(), isTrue);
}

Future<void> _addSignedInboxPage({
  required _CursorInboxBridge bridge,
  required GroupTestUser sender,
  required String groupId,
  required String cursor,
  required List<Map<String, dynamic>> payloads,
  required String nextCursor,
  required String groupKey,
  required int keyGeneration,
  List<String> recipientPeerIds = const <String>[],
}) async {
  final messages = <Map<String, dynamic>>[];
  for (final payload in payloads) {
    final replayEnvelope = await buildGroupOfflineReplayEnvelope(
      bridge: sender.bridge,
      groupRepo: sender.groupRepo,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: jsonEncode(payload),
      senderPeerId: sender.peerId,
      senderPublicKey: sender.publicKey,
      senderPrivateKey: sender.privateKey,
      keyInfo: GroupKeyInfo(
        groupId: groupId,
        keyGeneration: keyGeneration,
        encryptedKey: groupKey,
        createdAt: DateTime.now().toUtc(),
      ),
      messageId: payload['messageId'] as String?,
      senderDeviceId: sender.deviceId,
      senderTransportPeerId: sender.deviceId,
      senderKeyPackageId: sender.deviceIdentity.keyPackageId,
      recipientPeerIds: recipientPeerIds,
    );
    messages.add(
      _relayInboxMessage(
        sender: sender,
        message: replayEnvelope,
        timestamp: payload['timestamp'] as String?,
      ),
    );
  }
  bridge.addPage(groupId, cursor, messages, nextCursor);
}

Map<String, dynamic> _relayInboxMessage({
  required GroupTestUser sender,
  required String message,
  String? timestamp,
}) {
  return {
    'from': sender.deviceId,
    'message': message,
    'timestamp': ?timestamp,
  };
}

List<Map<String, dynamic>> _groupPublishPayloads(FakeBridge bridge) {
  return bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .where((message) => message['cmd'] == 'group:publish')
      .map(
        (message) => (message['payload'] as Map<String, dynamic>)
            .cast<String, dynamic>(),
      )
      .toList(growable: false);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Group recovery simulator smoke', () {
    late FakeGroupPubSubNetwork network;

    setUp(() {
      network = FakeGroupPubSubNetwork();
    });

    testWidgets(
      'open group screen reflects local outgoing status without listener echo',
      (tester) async {
        const alicePeerId = 'alice-local-status-peer';
        const groupId = 'group-local-status-smoke';
        const messageId = 'msg-local-status-smoke';
        final alice = GroupTestUser.create(
          peerId: alicePeerId,
          username: 'Alice',
          network: network,
        );

        await alice.createGroup(groupId: groupId, name: 'Local Status');
        await alice.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'local-status-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        final timestamp = DateTime.utc(2026, 6, 3, 10, 15);
        final failedMessage = GroupMessage(
          id: messageId,
          groupId: groupId,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          text: 'Local status simulator smoke',
          timestamp: timestamp,
          keyGeneration: 1,
          status: 'failed',
          isIncoming: false,
          createdAt: timestamp,
        );
        await alice.msgRepo.saveMessage(failedMessage);

        final identityRepo = FakeIdentityRepository()
          ..seed(
            FakeIdentityRepository.makeIdentity(
              peerId: alice.peerId,
              publicKey: alice.publicKey,
              privateKey: alice.privateKey,
              mlKemPublicKey: alice.mlKemPublicKey,
            ),
          );
        final updatedGroup = await alice.groupRepo.getGroup(groupId);
        expect(updatedGroup, isNotNull);

        try {
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: GroupConversationWired(
                group: updatedGroup!,
                groupRepo: alice.groupRepo,
                msgRepo: alice.msgRepo,
                groupMessageListener: alice.groupMessageListener,
                bridge: alice.bridge,
                identityRepo: identityRepo,
                contactRepo: InMemoryContactRepository(),
                p2pService: FakeP2PService(),
              ),
            ),
          );
          await _pumpFrames(tester, count: 20);

          final initialScreen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(
            initialScreen.messages
                .singleWhere((message) => message.id == messageId)
                .status,
            'failed',
          );

          await alice.msgRepo.saveMessage(
            failedMessage.copyWith(status: 'sent'),
          );
          await _pumpFrames(tester, count: 20);

          final updatedScreen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(
            updatedScreen.messages
                .singleWhere((message) => message.id == messageId)
                .status,
            'sent',
          );
          expect(alice.bridge.commandLog, isNot(contains('group:publish')));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          alice.dispose();
        }
      },
    );

    testWidgets('failed restored text continuation keeps one sender row id', (
      tester,
    ) async {
      const alicePeerId = 'alice-text-continuation-peer';
      const bobPeerId = 'bob-text-continuation-peer';
      const groupId = 'group-text-continuation-smoke';
      const text = 'Retry same restored simulator text';
      final bridge = _SequentialMirroringGroupPublishBridge(
        network: network,
        senderPeerId: alicePeerId,
        senderDeviceId: alicePeerId,
        publishResponses: [
          {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
          {'ok': true, 'messageId': 'restored-published', 'topicPeers': 1},
        ],
      );
      final alice = GroupTestUser.create(
        peerId: alicePeerId,
        username: 'Alice',
        network: network,
        bridge: bridge,
      );
      final bob = GroupTestUser.create(
        peerId: bobPeerId,
        username: 'Bob',
        network: network,
      );

      await alice.createGroup(groupId: groupId, name: 'Text Continuation');
      await alice.groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'text-continuation-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await alice.addMember(groupId: groupId, invitee: bob);
      await bob.groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'text-continuation-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      bob.start();

      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: alice.peerId,
            publicKey: alice.publicKey,
            privateKey: alice.privateKey,
            mlKemPublicKey: alice.mlKemPublicKey,
          ),
        );
      final updatedGroup = await alice.groupRepo.getGroup(groupId);
      expect(updatedGroup, isNotNull);

      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GroupConversationWired(
              group: updatedGroup!,
              groupRepo: alice.groupRepo,
              msgRepo: alice.msgRepo,
              groupMessageListener: alice.groupMessageListener,
              bridge: alice.bridge,
              identityRepo: identityRepo,
              contactRepo: InMemoryContactRepository(),
              // 210 alignment: this scenario exercises the ONLINE hard-failure
              // lane (PUBLISH_FAILED → 'failed' → manual retry keeps the row
              // id). The bare FakeP2PService() is relayReady==false, which
              // routes the error through the queued-offline branch instead
              // ('queued_offline' is repush-owned and not manually retriable).
              p2pService: FakeP2PService(
                initialState: const NodeState(
                  isStarted: true,
                  peerId: 'alice-text-continuation-peer',
                  relayState: 'online',
                ),
              ),
              mediaAttachmentRepo: alice.mediaAttachmentRepo,
            ),
          ),
        );
        await _pumpFrames(tester, count: 20);

        final firstScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final firstSend = firstScreen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await firstSend(text);
        });
        await _pumpFrames(tester, count: 20);

        final failedRows = (await alice.loadGroupMessages(
          groupId,
        )).where((message) => message.text == text).toList();
        expect(failedRows, hasLength(1));
        final failedRow = failedRows.single;
        expect(failedRow.status, 'failed');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty,
        );

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.onRetryFailedMessage, isNotNull);
        retryScreen.onRetryFailedMessage!(failedRow.id);
        await _pumpUntilAsync(tester, () async {
          await _pumpNetwork();
          final messages = (await alice.loadGroupMessages(
            groupId,
          )).where((message) => message.id == failedRow.id).toList();
          return messages.length == 1 && messages.single.status == 'sent';
        });

        final storedRows = (await alice.loadGroupMessages(
          groupId,
        )).where((message) => message.text == text).toList();
        expect(storedRows, hasLength(1));
        final storedRow = storedRows.single;
        expect(storedRow.id, failedRow.id);
        expect(storedRow.timestamp, failedRow.timestamp);
        expect(storedRow.status, 'sent');

        final publishPayloads = _groupPublishPayloads(bridge);
        expect(publishPayloads, hasLength(2));
        expect(
          publishPayloads.map((payload) => payload['messageId']).toList(),
          [failedRow.id, failedRow.id],
        );
        expect(
          publishPayloads.map((payload) => payload['timestamp']).toList(),
          [
            failedRow.timestamp.toUtc().toIso8601String(),
            failedRow.timestamp.toUtc().toIso8601String(),
          ],
        );

        final bobRows = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.text == text).toList();
        expect(bobRows, hasLength(1));
        expect(bobRows.single.id, failedRow.id);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        alice.dispose();
        bob.dispose();
      }
    });

    testWidgets('failed voice re-record keeps one sender and receiver row id', (
      tester,
    ) async {
      const alicePeerId = 'alice-voice-continuation-peer';
      const bobPeerId = 'bob-voice-continuation-peer';
      const groupId = 'group-voice-continuation-smoke';
      final bridge = _SequentialMirroringGroupPublishBridge(
        network: network,
        senderPeerId: alicePeerId,
        senderDeviceId: alicePeerId,
        publishResponses: [
          {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
          {'ok': true, 'messageId': 'voice-published', 'topicPeers': 1},
        ],
      );
      final alice = GroupTestUser.create(
        peerId: alicePeerId,
        username: 'Alice',
        network: network,
        bridge: bridge,
      );
      final bob = GroupTestUser.create(
        peerId: bobPeerId,
        username: 'Bob',
        network: network,
      );

      await alice.createGroup(groupId: groupId, name: 'Voice Continuation');
      await alice.groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'voice-continuation-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await alice.addMember(groupId: groupId, invitee: bob);
      await bob.groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'voice-continuation-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      bob.start();

      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: alice.peerId,
            publicKey: alice.publicKey,
            privateKey: alice.privateKey,
            mlKemPublicKey: alice.mlKemPublicKey,
          ),
        );
      final updatedGroup = await alice.groupRepo.getGroup(groupId);
      expect(updatedGroup, isNotNull);

      final tempDir = Directory.systemTemp.createTempSync(
        'group-voice-continuation-smoke-',
      );
      final firstVoice = File(p.join(tempDir.path, 'voice-first.m4a'))
        ..writeAsStringSync('first voice');
      final secondVoice = File(p.join(tempDir.path, 'voice-second.m4a'))
        ..writeAsStringSync('second voice');
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 2400
        ..fakeSizeBytes = 32000
        ..fakeOutputPath = firstVoice.path;
      final mediaFileManager = FakeMediaFileManager();

      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GroupConversationWired(
              group: updatedGroup!,
              groupRepo: alice.groupRepo,
              msgRepo: alice.msgRepo,
              groupMessageListener: alice.groupMessageListener,
              bridge: alice.bridge,
              identityRepo: identityRepo,
              contactRepo: InMemoryContactRepository(),
              // 210 alignment: ONLINE relay so the failed voice send stays
              // 'failed' and arms the re-record continuation (a queued_offline
              // row deliberately does not — it self-heals via repush).
              p2pService: FakeP2PService(
                initialState: const NodeState(
                  isStarted: true,
                  peerId: 'alice-voice-continuation-peer',
                  relayState: 'online',
                ),
              ),
              mediaAttachmentRepo: alice.mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              audioRecorderService: recorder,
              micPermissionGateway: FakeMicPermissionGateway(),
              uploadMediaFn:
                  ({
                    required bridge,
                    required localFilePath,
                    required mime,
                    required recipientPeerId,
                    String? blobId,
                    MediaFileManager? mediaFileManager,
                    width,
                    height,
                    durationMs,
                    waveform,
                    allowedPeers,
                    deleteSourceWhenDone = false,
                    preparedArtifact,
                  }) async {
                    return UploadMediaSucceeded(
                      MediaAttachment(
                        id: blobId!,
                        messageId: '',
                        mime: mime,
                        size: 1,
                        mediaType: MediaAttachment.mediaTypeFromMime(mime),
                        localPath: mediaFileManager?.relativePathForAttachment(
                          contactPeerId: recipientPeerId,
                          blobId: blobId,
                          mime: mime,
                        ),
                        downloadStatus: 'done',
                        contentHash:
                            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                        encryptionKeyBase64: 'key-$blobId',
                        encryptionNonce: 'nonce-$blobId',
                        encryptionScheme:
                            kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                        durationMs: durationMs,
                        waveform: waveform,
                        createdAt: DateTime.now().toUtc().toIso8601String(),
                      ),
                    );
                  },
            ),
          ),
        );
        await _pumpFrames(tester, count: 20);

        Future<void> recordVoice() async {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          await (screen.onRecordStart! as Future<void> Function())();
          await _pumpFrames(tester, count: 10);
          final recordingScreen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          await tester.runAsync(() async {
            await (recordingScreen.onRecordStop! as Future<void> Function())();
          });
          await _pumpFrames(tester, count: 20);
        }

        await recordVoice();
        final failedRows = (await alice.loadGroupMessages(groupId))
            .where((message) => !message.isIncoming && message.text.isEmpty)
            .toList();
        expect(failedRows, hasLength(1));
        final failedRow = failedRows.single;
        expect(failedRow.status, 'failed');

        recorder.fakeOutputPath = secondVoice.path;
        await recordVoice();
        await _pumpNetwork();

        final senderRows = (await alice.loadGroupMessages(groupId))
            .where((message) => !message.isIncoming && message.text.isEmpty)
            .toList();
        expect(senderRows, hasLength(1));
        expect(senderRows.single.id, failedRow.id);
        expect(senderRows.single.timestamp, failedRow.timestamp);
        expect(senderRows.single.status, 'sent');

        final publishPayloads = _groupPublishPayloads(bridge);
        expect(publishPayloads, hasLength(2));
        expect(
          publishPayloads.map((payload) => payload['messageId']).toList(),
          [failedRow.id, failedRow.id],
        );

        final bobRows = (await bob.loadGroupMessages(groupId))
            .where((message) => message.isIncoming && message.text.isEmpty)
            .toList();
        expect(bobRows, hasLength(1));
        expect(bobRows.single.id, failedRow.id);
        expect(
          await bob.mediaAttachmentRepo.getAttachmentsForMessage(
            failedRow.id,
            owner: MediaOwnerLane.group,
          ),
          hasLength(1),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
        alice.dispose();
        bob.dispose();
      }
    });

    testWidgets(
      'group member receives missed group messages after resume drain',
      (tester) async {
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

        const groupId = 'group-recovery-smoke';
        await alice.createGroup(groupId: groupId, name: 'Recovery Smoke');
        await alice.addMember(groupId: groupId, invitee: bob);

        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'group-key-smoke',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        alice.start();
        bob.start();

        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'Before background',
        );
        await _pumpNetwork();
        expect(
          (await bob.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        network.unsubscribe(groupId, bob.peerId);
        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'While backgrounded',
        );
        await _pumpNetwork();

        expect(
          (await bob.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        await _addSignedInboxPage(
          bridge: bobBridge,
          sender: alice,
          groupId: groupId,
          cursor: '',
          payloads: [
            {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 1,
              'text': 'While backgrounded',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'messageId': 'group-missed-1',
            },
          ],
          nextCursor: '',
          groupKey: 'group-key-smoke',
          keyGeneration: 1,
          recipientPeerIds: [bob.peerId],
        );

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        expect(
          (await bob.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(2),
        );

        alice.dispose();
        bob.dispose();
      },
    );

    testWidgets(
      'announcement reader receives missed announcement after resume drain',
      (tester) async {
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
        final readerBridge = reader.bridge as _CursorInboxBridge;

        const groupId = 'announcement-recovery-smoke';
        await admin.createGroup(
          groupId: groupId,
          name: 'Announcements',
          type: GroupType.announcement,
        );
        await admin.addMember(groupId: groupId, invitee: reader);

        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'announcement-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        admin.start();
        reader.start();

        await admin.sendGroupMessage(groupId: groupId, text: 'Announcement 1');
        await _pumpNetwork();
        expect(
          (await reader.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        network.unsubscribe(groupId, reader.peerId);
        await admin.sendGroupMessage(groupId: groupId, text: 'Announcement 2');
        await _pumpNetwork();

        expect(
          (await reader.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        await _addSignedInboxPage(
          bridge: readerBridge,
          sender: admin,
          groupId: groupId,
          cursor: '',
          payloads: [
            {
              'groupId': groupId,
              'senderId': 'admin-peer',
              'senderUsername': 'Admin',
              'keyEpoch': 1,
              'text': 'Announcement 2',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'messageId': 'announcement-missed-1',
            },
          ],
          nextCursor: '',
          groupKey: 'announcement-key',
          keyGeneration: 1,
          recipientPeerIds: [reader.peerId],
        );

        await drainGroupOfflineInbox(
          bridge: reader.bridge,
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
        );

        expect(
          (await reader.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(2),
        );

        admin.dispose();
        reader.dispose();
      },
    );

    testWidgets(
      'offline recovered dissolved group exposes local-only cleanup on Group Info',
      (tester) async {
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

        const groupId = 'group-dissolved-cleanup-smoke';
        final now = DateTime.now().toUtc();

        await alice.createGroup(
          groupId: groupId,
          name: 'Cleanup Smoke',
          createdAt: now,
        );
        await alice.addMember(groupId: groupId, invitee: bob, joinedAt: now);
        await alice.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'cleanup-key',
            createdAt: now,
          ),
        );
        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'cleanup-key',
            createdAt: now,
          ),
        );

        alice.start();

        final (result, dissolvedGroup) = await alice.dissolveGroupViaBridge(
          groupId: groupId,
        );
        expect(result, group_dissolve.DissolveGroupResult.success);
        expect(dissolvedGroup, isNotNull);
        expect(dissolvedGroup!.isDissolved, isTrue);

        final inboxRaw = alice.bridge.sentMessages.lastWhere(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        final inboxPayload =
            (jsonDecode(inboxRaw) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        bobBridge.addPage(groupId, '', [
          _relayInboxMessage(
            sender: alice,
            message: inboxPayload['message'] as String,
            timestamp: dissolvedGroup.dissolvedAt?.toUtc().toIso8601String(),
          ),
        ], '');

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupMessageListener: bob.groupMessageListener,
        );

        final recoveredGroup = await bob.groupRepo.getGroup(groupId);
        expect(recoveredGroup, isNotNull);
        final resolvedGroup = recoveredGroup!;
        expect(resolvedGroup.isDissolved, isTrue);
        expect(await bob.msgRepo.getMessageCount(groupId), 1);

        final identityRepo = FakeIdentityRepository()
          ..seed(
            FakeIdentityRepository.makeIdentity(
              peerId: bob.peerId,
              publicKey: bob.publicKey,
              privateKey: bob.privateKey,
            ),
          );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: resolvedGroup,
                          groupRepo: bob.groupRepo,
                          msgRepo: bob.msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bob.bridge,
                          identityRepo: identityRepo,
                          p2pService: FakeP2PService(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );
        await _pumpFrames(tester, count: 5);

        await tester.tap(find.text('Open Info'));
        await _pumpFrames(tester, count: 20);

        expect(find.text('Group dissolved'), findsOneWidget);
        expect(
          find.text(
            'This conversation is now read-only. Previous messages stay available for reference.',
          ),
          findsOneWidget,
        );

        bobBridge.commandLog.clear();

        final deleteButton = find.byKey(
          const ValueKey('group-delete-local-button'),
        );
        await tester.scrollUntilVisible(
          deleteButton,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _pumpFrames(tester, count: 5);
        expect(find.text('Delete from this device'), findsOneWidget);
        await tester.tap(deleteButton);
        await _pumpFrames(tester, count: 5);

        expect(
          find.byKey(const ValueKey('group-delete-local-confirm')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('group-delete-local-confirm')),
        );
        await _pumpFrames(tester, count: 20);

        expect(await bob.groupRepo.getGroup(groupId), isNull);
        expect(await bob.groupRepo.getMembers(groupId), isEmpty);
        expect(await bob.groupRepo.getLatestKey(groupId), isNull);
        expect(await bob.msgRepo.getMessageCount(groupId), 0);
        expect(bobBridge.commandLog, isNot(contains('group:leave')));
        expect(find.byType(GroupInfoWired), findsNothing);
        expect(find.text('Open Info'), findsOneWidget);

        alice.dispose();
        bob.dispose();
      },
    );

    testWidgets(
      'group inbox drain deduplicates message already received live',
      (tester) async {
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final user = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-dedupe-smoke';
        const messageId = 'group-dedupe-msg';
        final now = DateTime.now().toUtc();

        await alice.createGroup(
          groupId: groupId,
          name: 'Dedupe',
          createdAt: now,
        );
        await alice.addMember(groupId: groupId, invitee: user, joinedAt: now);
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'dedupe-key',
            createdAt: now,
          ),
        );

        user.start();
        network.subscribe(groupId, user.peerId);

        await handleIncomingGroupMessage(
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
          groupId: groupId,
          senderId: 'alice-peer',
          senderUsername: 'Alice',
          keyEpoch: 0,
          text: 'Deduped message',
          timestamp: now.toIso8601String(),
          messageId: messageId,
        );

        await _addSignedInboxPage(
          bridge: userBridge,
          sender: alice,
          groupId: groupId,
          cursor: '',
          payloads: [
            {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 1,
              'text': 'Deduped message',
              'timestamp': now.toIso8601String(),
              'messageId': messageId,
            },
          ],
          nextCursor: '',
          groupKey: 'dedupe-key',
          keyGeneration: 1,
          recipientPeerIds: [user.peerId],
        );

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        expect(
          (await user.loadGroupMessages(groupId)).where((m) => m.isIncoming),
          hasLength(1),
        );

        alice.dispose();
        user.dispose();
      },
    );

    testWidgets(
      'watchdog restart rejoins topics and multi-group drain stays bounded',
      (tester) async {
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
        final other = GroupTestUser.create(
          peerId: 'other-peer',
          username: 'Other',
          network: network,
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const rejoinGroupId = 'group-watchdog-smoke';
        await alice.createGroup(groupId: rejoinGroupId, name: 'Watchdog');
        await alice.addMember(groupId: rejoinGroupId, invitee: bob);
        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: rejoinGroupId,
            keyGeneration: 1,
            encryptedKey: 'watchdog-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final extraGroupIds = List.generate(4, (i) => 'group-burst-$i');
        for (final groupId in extraGroupIds) {
          await bob.createGroup(groupId: groupId, name: groupId);
          await bob.addMember(groupId: groupId, invitee: other);
          await bob.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'key-$groupId',
              createdAt: DateTime.now().toUtc(),
            ),
          );
          await _addSignedInboxPage(
            bridge: bobBridge,
            sender: other,
            groupId: groupId,
            cursor: '',
            payloads: [
              {
                'groupId': groupId,
                'senderId': 'other-peer',
                'senderUsername': 'Other',
                'keyEpoch': 1,
                'text': 'Missed $groupId',
                'timestamp': DateTime.now().toUtc().toIso8601String(),
                'messageId': 'missed-$groupId',
              },
            ],
            nextCursor: '',
            groupKey: 'key-$groupId',
            keyGeneration: 1,
            recipientPeerIds: [bob.peerId],
          );
        }
        bobBridge.addPage(rejoinGroupId, '', <Map<String, dynamic>>[], '');

        alice.start();
        bob.start();

        await alice.sendGroupMessage(
          groupId: rejoinGroupId,
          text: 'Before watchdog',
        );
        await _pumpNetwork();
        expect(
          (await bob.loadGroupMessages(
            rejoinGroupId,
          )).where((m) => m.isIncoming),
          hasLength(1),
        );

        network.unsubscribe(rejoinGroupId, bob.peerId);
        await rejoinGroupTopics(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          reason: RejoinReason.watchdogRestart,
        );

        final joinCalls = bob.bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();
        expect(joinCalls.length, greaterThanOrEqualTo(1));

        network.subscribe(rejoinGroupId, bob.peerId);
        await alice.sendGroupMessage(
          groupId: rejoinGroupId,
          text: 'After watchdog',
        );
        await _pumpNetwork();
        expect(
          (await bob.loadGroupMessages(
            rejoinGroupId,
          )).where((m) => m.isIncoming),
          hasLength(2),
        );

        bobBridge.commandLog.clear();
        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        final retrieveCount = bobBridge.commandLog
            .where((cmd) => cmd == 'group:inboxRetrieveCursor')
            .length;
        expect(retrieveCount, extraGroupIds.length + 1);

        for (final groupId in extraGroupIds) {
          expect(await bob.msgRepo.getMessageCount(groupId), 1);
        }
        expect(
          (await bob.loadGroupMessages(
            rejoinGroupId,
          )).where((m) => m.isIncoming),
          hasLength(2),
        );

        alice.dispose();
        bob.dispose();
        other.dispose();
      },
    );
  });
}
