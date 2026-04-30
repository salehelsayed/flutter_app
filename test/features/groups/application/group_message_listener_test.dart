import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _bytes123ContentHash =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

class SequencedUpdateConfigBridge extends FakeBridge {
  SequencedUpdateConfigBridge(this._behaviors);

  final List<Future<String> Function(String message)> _behaviors;
  int _updateConfigCallIndex = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:updateConfig' &&
        _updateConfigCallIndex < _behaviors.length) {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return _behaviors[_updateConfigCallIndex++](message);
    }

    return super.send(message);
  }
}

class GateableMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  final Completer<void> firstDownloadingGate = Completer<void>();
  int downloadingUpdateCalls = 0;
  bool _gatedFirstDownloadingUpdate = false;

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    if (downloadStatus == 'downloading') {
      downloadingUpdateCalls++;
      if (!_gatedFirstDownloadingUpdate) {
        _gatedFirstDownloadingUpdate = true;
        await firstDownloadingGate.future;
      }
    }
    await super.updateDownloadStatus(id, downloadStatus);
  }
}

class _FakeEventLog {
  final entries = <Map<String, Object?>>[];
  final _payloadBySourceEventId = <String, String>{};

  Future<Map<String, Object?>> append({
    required String groupId,
    required String eventType,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> payload,
    DateTime? createdAt,
  }) async {
    final canonical = canonicalizeGroupEventLogPayload(payload);
    final existing = _payloadBySourceEventId[sourceEventId];
    if (existing != null && existing != canonical) {
      throw GroupEventLogTamperException('conflicting replay');
    }
    _payloadBySourceEventId[sourceEventId] = canonical;
    final entry = {
      'groupId': groupId,
      'eventType': eventType,
      'sourcePeerId': sourcePeerId,
      'sourceEventId': sourceEventId,
      'sourceTimestamp': sourceTimestamp,
      'payload': payload,
    };
    if (existing == null) {
      entries.add(entry);
    }
    return entry;
  }
}

class _DelayedMediaDownloadBridge extends FakeBridge {
  final Completer<void> downloadGate = Completer<void>();

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
      await downloadGate.future;
      final payload =
          parsed['payload'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final outputPath = payload['outputPath'] as String?;
      if (outputPath != null) {
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(const <int>[1, 2, 3]);
      }
      return jsonEncode({'ok': true});
    }

    return super.send(message);
  }
}

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeBridge bridge;
  late GroupMessageListener listener;
  late StreamController<Map<String, dynamic>> sourceController;
  late DebugPrintCallback originalDebugPrint;
  late List<String> debugLogs;
  final initialGroupCreatedAt = DateTime.utc(2026, 4, 5, 11, 59, 0);
  final initialMemberJoinedAt = DateTime.utc(2026, 4, 5, 11, 59, 30);

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: initialGroupCreatedAt,
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  Future<void> saveTrustedAdminMember({
    String groupId = 'group-1',
    String peerId = 'peer-admin',
    String username = 'Admin',
    String publicKey = 'pk-admin',
  }) {
    return groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: peerId,
        username: username,
        role: MemberRole.admin,
        publicKey: publicKey,
        joinedAt: initialMemberJoinedAt,
      ),
    );
  }

  Map<String, dynamic> buildMetadataConfig({
    required DateTime updatedAt,
    String name = 'Renamed Group',
    String? description = 'Fresh description',
    String? avatarBlobId,
    String? avatarMime,
  }) {
    return buildGroupConfigPayload(
      testGroup.copyWith(
        name: name,
        description: description,
        avatarBlobId: avatarBlobId,
        avatarMime: avatarMime,
        lastMetadataEventAt: updatedAt,
      ),
      [
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: initialGroupCreatedAt,
        ),
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          publicKey: 'pk-sender',
          joinedAt: initialMemberJoinedAt,
        ),
      ],
    );
  }

  Map<String, dynamic> signedMetadataSystemPayload({
    required DateTime updatedAt,
    required Map<String, dynamic> groupConfig,
    String groupId = 'group-1',
    String actorPeerId = 'peer-admin',
    String actorUsername = 'Admin',
    String actorPublicKey = 'pk-admin',
    String signature = 'sig-metadata',
    Map<String, dynamic>? signedGroupConfig,
    String? signedUpdatedAt,
    String? signatureAlgorithm = 'ed25519',
  }) {
    final effectiveSignedConfig = signedGroupConfig ?? groupConfig;
    final actorPayload = {
      'schemaVersion': 1,
      'eventType': 'group_metadata_updated',
      'groupId': groupId,
      'updatedAt': signedUpdatedAt ?? updatedAt.toUtc().toIso8601String(),
      'actor': {
        'peerId': actorPeerId,
        'username': actorUsername,
        'publicKey': actorPublicKey,
      },
      'groupConfigVersion': effectiveSignedConfig[groupConfigVersionField],
      'groupConfigStateHash': effectiveSignedConfig[groupConfigStateHashField],
      'groupConfig': effectiveSignedConfig,
    };
    return {
      '__sys': 'group_metadata_updated',
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'groupConfig': groupConfig,
      'actorEvent': {
        'signedPayload': canonicalizeGroupEventLogPayload(actorPayload),
        'signature': signature,
        'signatureAlgorithm': signatureAlgorithm,
      },
    };
  }

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    bridge = FakeBridge();
    sourceController = StreamController<Map<String, dynamic>>.broadcast();
    debugLogs = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        debugLogs.add(message);
      }
    };

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-sender',
        username: 'Sender',
        role: MemberRole.writer,
        joinedAt: initialMemberJoinedAt,
      ),
    );

    listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: bridge,
    );
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    listener.dispose();
    sourceController.close();
  });

  test('processes valid message', () async {
    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Hello group!',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    // Allow async processing
    await Future.delayed(const Duration(milliseconds: 50));

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest!.text, 'Hello group!');
  });

  test('forwards quotedMessageId from event into persisted message', () async {
    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Quoted group reply',
      'quotedMessageId': 'msg-parent-1',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest, isNotNull);
    expect(latest!.quotedMessageId, 'msg-parent-1');
  });

  test('caches self peer id across multiple handled messages', () async {
    var selfPeerIdCalls = 0;
    listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: bridge,
      getSelfPeerId: () async {
        selfPeerIdCalls++;
        return 'peer-self';
      },
    );

    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'First message',
      'messageId': 'msg-self-cache-1',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Second message',
      'messageId': 'msg-self-cache-2',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    expect(msgRepo.count, 2);
    expect(selfPeerIdCalls, 1);
  });

  test('ignores message for unknown group', () async {
    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'unknown-group',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Hello',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    expect(msgRepo.count, 0);
  });

  test('emits to stream on valid message', () async {
    listener.start(sourceController.stream);

    final messages = <GroupMessage>[];
    final subscription = listener.groupMessageStream.listen(messages.add);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Streamed message',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    expect(messages.length, 1);
    expect(messages.first.text, 'Streamed message');

    await subscription.cancel();
  });

  test('disposes correctly', () async {
    listener.start(sourceController.stream);
    listener.dispose();

    // After disposal, adding data should not cause errors
    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'After dispose',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    // Message was not processed because subscription was cancelled
    expect(msgRepo.count, 0);
  });

  test('handles malformed data without crashing', () async {
    listener.start(sourceController.stream);

    // Missing required fields
    sourceController.add({'groupId': '', 'senderId': ''});

    await Future.delayed(const Duration(milliseconds: 50));

    // Should not crash; message ignored
    expect(msgRepo.count, 0);
  });

  group('system messages', () {
    test('member_added saves member and calls updateConfig', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_added',
        'member': {
          'peerId': 'peer-charlie',
          'username': 'Charlie',
          'role': 'writer',
          'publicKey': 'pk-charlie',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {
              'peerId': 'peer-charlie',
              'role': 'writer',
              'publicKey': 'pk-charlie',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // System message should materialize one durable timeline row, not a raw
      // duplicate chat payload.
      expect(msgRepo.count, 1);
      final latest = await msgRepo.getLatestMessage('group-1');
      expect(latest, isNotNull);
      expect(latest!.text, 'Admin added Charlie');

      // New member should be saved to the group repo
      final charlie = await groupRepo.getMember('group-1', 'peer-charlie');
      expect(charlie, isNotNull);
      expect(charlie!.username, 'Charlie');
      expect(charlie.role, MemberRole.writer);

      // Bridge should have received group:updateConfig
      expect(bridge.commandLog, contains('group:updateConfig'));
    });

    test('unauthorized member_added is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_added',
        'member': {
          'peerId': 'peer-charlie',
          'username': 'Charlie',
          'role': 'writer',
          'publicKey': 'pk-charlie',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {
              'peerId': 'peer-charlie',
              'role': 'writer',
              'publicKey': 'pk-charlie',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'authorized admin metadata event with valid state hash but no signed actor envelope is ignored',
      () async {
        await saveTrustedAdminMember();
        final eventLog = _FakeEventLog();
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
        );
        listener.start(sourceController.stream);

        final updatedAt = DateTime.parse('2026-04-05T12:19:00.000Z');
        final sysText = jsonEncode({
          '__sys': 'group_metadata_updated',
          'updatedAt': updatedAt.toUtc().toIso8601String(),
          'groupConfig': buildMetadataConfig(updatedAt: updatedAt),
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'metadata-unsigned-1',
          'text': sysText,
          'timestamp': updatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.name, 'Test Group');
        expect(group.description, isNull);
        expect(group.lastMetadataEventAt, isNull);
        expect(bridge.commandLog, isNot(contains('payload.verify')));
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(msgRepo.count, 0);
        expect(eventLog.entries, isEmpty);
      },
    );

    test(
      'group_metadata_updated refreshes group metadata and stores a timeline event',
      () async {
        await saveTrustedAdminMember();
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        final eventLog = _FakeEventLog();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
          downloadGroupAvatarFn:
              ({
                required dynamic bridge,
                required String groupId,
                required String blobId,
              }) async => 'media/group_avatars/$groupId.jpg',
        );
        listener.start(sourceController.stream);

        final updatedAt = DateTime.parse('2026-04-05T12:20:00.000Z');
        final groupConfig = buildMetadataConfig(
          updatedAt: updatedAt,
          avatarBlobId: 'blob-1',
          avatarMime: 'image/jpeg',
        );
        final sysPayload = signedMetadataSystemPayload(
          updatedAt: updatedAt,
          groupConfig: groupConfig,
        );
        final sysText = jsonEncode(sysPayload);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'metadata-valid-1',
          'text': sysText,
          'timestamp': updatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updatedGroup = await groupRepo.getGroup('group-1');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.name, 'Renamed Group');
        expect(updatedGroup.description, 'Fresh description');
        expect(updatedGroup.avatarBlobId, 'blob-1');
        expect(updatedGroup.avatarMime, 'image/jpeg');
        expect(updatedGroup.avatarPath, 'media/group_avatars/group-1.jpg');
        expect(updatedGroup.lastMetadataEventAt, updatedAt.toUtc());

        final latest = await msgRepo.getLatestMessage('group-1');
        expect(latest, isNotNull);
        expect(latest!.text, 'Admin updated the group details');
        final verifyIndex = bridge.commandLog.indexOf('payload.verify');
        final updateConfigIndex = bridge.commandLog.indexOf(
          'group:updateConfig',
        );
        expect(verifyIndex, isNonNegative);
        expect(updateConfigIndex, isNonNegative);
        expect(verifyIndex, lessThan(updateConfigIndex));

        final verifyMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'payload.verify';
        });
        final verifyPayload =
            (jsonDecode(verifyMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final actorEvent = sysPayload['actorEvent'] as Map<String, dynamic>;
        expect(verifyPayload['publicKey'], 'pk-admin');
        expect(verifyPayload['data'], actorEvent['signedPayload']);
        expect(verifyPayload['signature'], actorEvent['signature']);
        expect(eventLog.entries, hasLength(1));
      },
    );

    test('signed group_metadata_updated payload mismatch is ignored', () async {
      await saveTrustedAdminMember();
      bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start(sourceController.stream);

      final updatedAt = DateTime.parse('2026-04-05T12:21:00.000Z');
      final outerConfig = buildMetadataConfig(
        updatedAt: updatedAt,
        name: 'Outer Name',
      );
      final signedConfig = buildMetadataConfig(
        updatedAt: updatedAt,
        name: 'Signed Name',
      );
      final sysText = jsonEncode(
        signedMetadataSystemPayload(
          updatedAt: updatedAt,
          groupConfig: outerConfig,
          signedGroupConfig: signedConfig,
        ),
      );

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'metadata-mismatch-1',
        'text': sysText,
        'timestamp': updatedAt.toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);
      expect(group!.name, 'Test Group');
      expect(group.description, isNull);
      expect(group.lastMetadataEventAt, isNull);
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
      expect(eventLog.entries, isEmpty);
    });

    test('invalid group_metadata_updated actor signature is ignored', () async {
      await saveTrustedAdminMember();
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start(sourceController.stream);

      final updatedAt = DateTime.parse('2026-04-05T12:23:00.000Z');
      final sysText = jsonEncode(
        signedMetadataSystemPayload(
          updatedAt: updatedAt,
          groupConfig: buildMetadataConfig(updatedAt: updatedAt),
        ),
      );

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'metadata-invalid-signature-1',
        'text': sysText,
        'timestamp': updatedAt.toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);
      expect(group!.name, 'Test Group');
      expect(group.description, isNull);
      expect(group.lastMetadataEventAt, isNull);
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
      expect(eventLog.entries, isEmpty);
    });

    test(
      'tampered group_metadata_updated state hash is ignored without mutating group state',
      () async {
        listener.start(sourceController.stream);

        final updatedAt = DateTime.parse('2026-04-05T12:22:00.000Z');
        final config = buildGroupConfigPayload(
          testGroup.copyWith(
            name: 'Renamed Group',
            description: 'Fresh description',
            lastMetadataEventAt: updatedAt,
          ),
          [
            GroupMember(
              groupId: 'group-1',
              peerId: 'peer-admin',
              username: 'Admin',
              role: MemberRole.admin,
              publicKey: 'pk-admin',
              joinedAt: initialGroupCreatedAt,
            ),
            GroupMember(
              groupId: 'group-1',
              peerId: 'peer-sender',
              username: 'Sender',
              role: MemberRole.writer,
              publicKey: 'pk-sender',
              joinedAt: initialMemberJoinedAt,
            ),
          ],
        );
        final tamperedConfig = Map<String, dynamic>.from(config)
          ..['name'] = 'Tampered Group';
        final sysText = jsonEncode({
          '__sys': 'group_metadata_updated',
          'updatedAt': updatedAt.toUtc().toIso8601String(),
          'groupConfig': tamperedConfig,
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': updatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.name, 'Test Group');
        expect(group.description, isNull);
        expect(group.lastMetadataEventAt, isNull);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(msgRepo.count, 0);
      },
    );

    test('unauthorized group_metadata_updated is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'group_metadata_updated',
        'updatedAt': '2026-04-05T12:21:00.000Z',
        'groupConfig': {
          'name': 'Hijacked Name',
          'groupType': 'chat',
          'description': 'Malicious',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': '2026-04-05T12:00:00.000Z',
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': '2026-04-05T12:21:00.000Z',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final group = await groupRepo.getGroup('group-1');
      expect(group!.name, 'Test Group');
      expect(group.description, isNull);
      expect(group.avatarBlobId, isNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'older group_metadata_updated cannot roll back a newer metadata state after restart',
      () async {
        await saveTrustedAdminMember();
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        final newerUpdatedAt = DateTime.parse('2026-04-05T12:30:00.000Z');
        final newerConfig = buildMetadataConfig(
          updatedAt: newerUpdatedAt,
          name: 'Newest Name',
          description: 'Newest description',
        );
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode(
            signedMetadataSystemPayload(
              updatedAt: newerUpdatedAt,
              groupConfig: newerConfig,
            ),
          ),
          'timestamp': newerUpdatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        final persistedAfterNewer = await groupRepo.getGroup('group-1');
        expect(persistedAfterNewer!.name, 'Newest Name');
        expect(persistedAfterNewer.lastMetadataEventAt, newerUpdatedAt.toUtc());

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderUpdatedAt = DateTime.parse('2026-04-05T12:10:00.000Z');
        final olderConfig = buildMetadataConfig(
          updatedAt: olderUpdatedAt,
          name: 'Older Name',
          description: 'Older description',
        );
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode(
            signedMetadataSystemPayload(
              updatedAt: olderUpdatedAt,
              groupConfig: olderConfig,
            ),
          ),
          'timestamp': olderUpdatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final finalGroup = await groupRepo.getGroup('group-1');
        expect(finalGroup!.name, 'Newest Name');
        expect(finalGroup.description, 'Newest description');
        expect(finalGroup.lastMetadataEventAt, newerUpdatedAt.toUtc());

        restartedListener.dispose();
      },
    );

    test(
      'duplicate member_added keeps one canonical member state and one UI stream event',
      () async {
        listener.start(sourceController.stream);

        final emittedMessages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(
          emittedMessages.add,
        );

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'admin',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'role': 'admin',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);

        await Future.delayed(const Duration(milliseconds: 50));

        final members = await groupRepo.getMembers('group-1');
        final charlies = members
            .where((member) => member.peerId == 'peer-charlie')
            .toList();

        expect(charlies, hasLength(1));
        expect(charlies.single.role, MemberRole.admin);
        expect(emittedMessages, hasLength(1));
        expect(emittedMessages.single.text, 'Admin added Charlie');
        expect(emittedMessages.single.senderPeerId, 'peer-admin');
        expect(msgRepo.count, 1);

        await subscription.cancel();
      },
    );

    test(
      'older member_removed cannot roll back a newer added admin state after restart',
      () async {
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        const newerAddAt = '2026-04-05T12:00:02.000Z';
        final newerAdd = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'admin',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'role': 'admin',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': newerAdd,
          'timestamp': newerAddAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        final persistedAfterAdd = await groupRepo.getGroup('group-1');
        expect(
          persistedAfterAdd!.lastMembershipEventAt,
          DateTime.parse(newerAddAt).toUtc(),
        );
        final charlieAfterAdd = await groupRepo.getMember(
          'group-1',
          'peer-charlie',
        );
        expect(charlieAfterAdd, isNotNull);
        expect(charlieAfterAdd!.role, MemberRole.admin);

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderRemove = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': olderRemove,
          'timestamp': '2026-04-05T12:00:01.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final charlieAfterStaleRemove = await groupRepo.getMember(
          'group-1',
          'peer-charlie',
        );
        expect(charlieAfterStaleRemove, isNotNull);
        expect(charlieAfterStaleRemove!.role, MemberRole.admin);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        restartedListener.dispose();
      },
    );

    test(
      'member_added retries once using incoming groupConfig snapshot and then succeeds',
      () async {
        bridge = SequencedUpdateConfigBridge([
          (_) async => throw Exception('first update failed'),
          (_) async => jsonEncode({'ok': true}),
        ]);
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie Local',
            'role': 'writer',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'username': 'Charlie Snapshot',
                'role': 'writer',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final charlie = await groupRepo.getMember('group-1', 'peer-charlie');
        expect(charlie, isNotNull);
        expect(charlie!.username, 'Charlie Snapshot');

        final updateConfigCalls = bridge.commandLog
            .where((command) => command == 'group:updateConfig')
            .length;
        expect(updateConfigCalls, 2);

        final secondUpdate =
            jsonDecode(
                  bridge.sentMessages.where((message) {
                    final parsed = jsonDecode(message) as Map<String, dynamic>;
                    return parsed['cmd'] == 'group:updateConfig';
                  }).last,
                )
                as Map<String, dynamic>;
        final groupConfig =
            secondUpdate['payload']['groupConfig'] as Map<String, dynamic>;
        final members = groupConfig['members'] as List<dynamic>;
        final charlieConfig = members.cast<Map<String, dynamic>>().firstWhere(
          (member) => member['peerId'] == 'peer-charlie',
        );
        expect(charlieConfig['username'], 'Charlie Snapshot');
      },
    );

    test('members_added saves all members and calls updateConfig', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'members_added',
        'members': [
          {
            'peerId': 'peer-dave',
            'username': 'Dave',
            'role': 'writer',
            'publicKey': 'pk-dave',
          },
          {
            'peerId': 'peer-eve',
            'username': 'Eve',
            'role': 'writer',
            'publicKey': 'pk-eve',
          },
        ],
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {'peerId': 'peer-dave', 'role': 'writer', 'publicKey': 'pk-dave'},
            {'peerId': 'peer-eve', 'role': 'writer', 'publicKey': 'pk-eve'},
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // Both members saved
      final dave = await groupRepo.getMember('group-1', 'peer-dave');
      expect(dave, isNotNull);
      expect(dave!.username, 'Dave');
      final eve = await groupRepo.getMember('group-1', 'peer-eve');
      expect(eve, isNotNull);
      expect(eve!.username, 'Eve');

      // Config updated once
      final updateConfigCalls = bridge.commandLog
          .where((c) => c == 'group:updateConfig')
          .length;
      expect(updateConfigCalls, 1);

      expect(msgRepo.count, 1);
      final saved = await msgRepo.getLatestMessage('group-1');
      expect(saved, isNotNull);
      expect(saved!.text, 'Admin added Dave and Eve');
    });

    test('member_joined saves a durable join timeline event', () async {
      listener.start(sourceController.stream);

      final messages = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(messages.add);

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final sysText = jsonEncode({
        '__sys': 'member_joined',
        'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-charlie',
        'senderUsername': 'Charlie',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(messages, hasLength(1));
      expect(messages.single.text, 'Charlie joined the group');
      expect(messages.single.senderPeerId, 'peer-charlie');
      expect(messages.single.senderUsername, 'Charlie');
      expect(msgRepo.count, 1);
      final saved = await msgRepo.getLatestMessage('group-1');
      expect(saved, isNotNull);
      expect(saved!.text, 'Charlie joined the group');

      await subscription.cancel();
    });

    test(
      'member_joined replay preserves read state for durable timeline event',
      () async {
        listener.start(sourceController.stream);

        final messages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(messages.add);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final eventAt = DateTime.utc(2026, 4, 5, 12, 5);
        final sysText = jsonEncode({
          '__sys': 'member_joined',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
        });
        final event = <String, dynamic>{
          'groupId': 'group-1',
          'senderId': 'peer-charlie',
          'senderUsername': 'Charlie',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': eventAt.toIso8601String(),
        };

        sourceController.add(event);
        await Future.delayed(const Duration(milliseconds: 50));

        await msgRepo.markAsRead('group-1');
        final readMessage = await msgRepo.getLatestMessage('group-1');
        expect(readMessage, isNotNull);
        expect(readMessage!.readAt, isNotNull);

        sourceController.add(event);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(msgRepo.count, 1);
        final replayed = await msgRepo.getLatestMessage('group-1');
        expect(replayed!.readAt, readMessage.readAt);
        expect(messages, hasLength(2));
        expect(messages.last.readAt, readMessage.readAt);

        await subscription.cancel();
      },
    );

    test('unauthorized members_added is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'members_added',
        'members': [
          {
            'peerId': 'peer-dave',
            'username': 'Dave',
            'role': 'writer',
            'publicKey': 'pk-dave',
          },
          {
            'peerId': 'peer-eve',
            'username': 'Eve',
            'role': 'writer',
            'publicKey': 'pk-eve',
          },
        ],
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {'peerId': 'peer-dave', 'role': 'writer', 'publicKey': 'pk-dave'},
            {'peerId': 'peer-eve', 'role': 'writer', 'publicKey': 'pk-eve'},
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getMember('group-1', 'peer-dave'), isNull);
      expect(await groupRepo.getMember('group-1', 'peer-eve'), isNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'members_added retries once using incoming groupConfig snapshot and then succeeds',
      () async {
        bridge = SequencedUpdateConfigBridge([
          (_) async => throw Exception('first update failed'),
          (_) async => jsonEncode({'ok': true}),
        ]);
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'members_added',
          'members': [
            {
              'peerId': 'peer-dave',
              'username': 'Dave Local',
              'role': 'writer',
              'publicKey': 'pk-dave',
            },
            {
              'peerId': 'peer-eve',
              'username': 'Eve Local',
              'role': 'writer',
              'publicKey': 'pk-eve',
            },
          ],
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-dave',
                'username': 'Dave Snapshot',
                'role': 'writer',
                'publicKey': 'pk-dave',
              },
              {
                'peerId': 'peer-eve',
                'username': 'Eve Snapshot',
                'role': 'writer',
                'publicKey': 'pk-eve',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final dave = await groupRepo.getMember('group-1', 'peer-dave');
        final eve = await groupRepo.getMember('group-1', 'peer-eve');
        expect(dave, isNotNull);
        expect(eve, isNotNull);
        expect(dave!.username, 'Dave Snapshot');
        expect(eve!.username, 'Eve Snapshot');

        final updateConfigCalls = bridge.commandLog
            .where((command) => command == 'group:updateConfig')
            .length;
        expect(updateConfigCalls, 2);

        final secondUpdate =
            jsonDecode(
                  bridge.sentMessages.where((message) {
                    final parsed = jsonDecode(message) as Map<String, dynamic>;
                    return parsed['cmd'] == 'group:updateConfig';
                  }).last,
                )
                as Map<String, dynamic>;
        final groupConfig =
            secondUpdate['payload']['groupConfig'] as Map<String, dynamic>;
        final members = groupConfig['members'] as List<dynamic>;
        final daveConfig = members.cast<Map<String, dynamic>>().firstWhere(
          (member) => member['peerId'] == 'peer-dave',
        );
        final eveConfig = members.cast<Map<String, dynamic>>().firstWhere(
          (member) => member['peerId'] == 'peer-eve',
        );
        expect(daveConfig['username'], 'Dave Snapshot');
        expect(eveConfig['username'], 'Eve Snapshot');
      },
    );

    test(
      'concurrent system messages execute sequentially across full pipeline',
      () async {
        final firstUpdate = Completer<String>();
        final secondUpdateStarted = Completer<void>();

        bridge = SequencedUpdateConfigBridge([
          (_) => firstUpdate.future,
          (_) async {
            secondUpdateStarted.complete();
            return jsonEncode({'ok': true});
          },
        ]);
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        listener.start(sourceController.stream);

        final firstMessage = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-alice',
            'username': 'Alice',
            'role': 'writer',
            'publicKey': 'pk-alice',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-alice',
                'role': 'writer',
                'publicKey': 'pk-alice',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });
        final secondMessage = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-bob',
            'username': 'Bob',
            'role': 'writer',
            'publicKey': 'pk-bob',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-alice',
                'role': 'writer',
                'publicKey': 'pk-alice',
              },
              {'peerId': 'peer-bob', 'role': 'writer', 'publicKey': 'pk-bob'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': firstMessage,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': secondMessage,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );
        expect(await groupRepo.getMember('group-1', 'peer-alice'), isNotNull);
        expect(await groupRepo.getMember('group-1', 'peer-bob'), isNull);
        expect(secondUpdateStarted.isCompleted, isFalse);

        firstUpdate.complete(jsonEncode({'ok': true}));
        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(2),
        );
        expect(await groupRepo.getMember('group-1', 'peer-bob'), isNotNull);
        expect(secondUpdateStarted.isCompleted, isTrue);
      },
    );

    test(
      'member_added emits readable timeline event on groupMessageStream',
      () async {
        listener.start(sourceController.stream);

        final messages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(messages.add);

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'writer',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(messages, hasLength(1));
        expect(messages.single.text, 'Admin added Charlie');
        expect(messages.single.senderPeerId, 'peer-admin');
        expect(messages.single.senderUsername, 'Admin');
        expect(messages.single.isIncoming, isTrue);
        expect(msgRepo.count, 1);
        final saved = await msgRepo.getLatestMessage('group-1');
        expect(saved, isNotNull);
        expect(saved!.text, 'Admin added Charlie');

        await subscription.cancel();
      },
    );

    test(
      'system message without bridge falls through as regular message',
      () async {
        // Create listener without bridge
        final noBridgeListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
        );
        noBridgeListener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'member': {'peerId': 'peer-charlie'},
          'groupConfig': {},
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        // Without bridge, treated as regular message and saved
        expect(msgRepo.count, 1);

        noBridgeListener.dispose();
      },
    );
  });

  group('member_removed system messages', () {
    test(
      'member_removed removes other member and calls updateConfig',
      () async {
        // Verify the member exists first
        final before = await groupRepo.getMember('group-1', 'peer-sender');
        expect(before, isNotNull);

        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(msgRepo.count, 1);
        final saved = await msgRepo.getLatestMessage('group-1');
        expect(saved, isNotNull);
        expect(saved!.text, 'Admin removed Sender');
        expect(
          saved.id.startsWith('sys-member_removed:group-1:peer-sender:'),
          isTrue,
        );

        // Member should be removed from the group repo
        final after = await groupRepo.getMember('group-1', 'peer-sender');
        expect(after, isNull);

        // Bridge should have received group:updateConfig
        expect(bridge.commandLog, contains('group:updateConfig'));
      },
    );

    test(
      'equal-watermark group_metadata_updated retries avatar recovery when avatarPath is still missing',
      () async {
        await saveTrustedAdminMember();
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        final updatedAt = DateTime.parse('2026-04-05T12:20:00.000Z');
        await groupRepo.updateGroup(
          testGroup.copyWith(
            avatarBlobId: 'blob-1',
            avatarMime: 'image/jpeg',
            avatarPath: null,
            lastMetadataEventAt: updatedAt.toUtc(),
          ),
        );

        var downloadCalls = 0;
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          downloadGroupAvatarFn:
              ({
                required dynamic bridge,
                required String groupId,
                required String blobId,
              }) async {
                downloadCalls++;
                return 'media/group_avatars/$groupId.jpg';
              },
        );
        listener.start(sourceController.stream);

        final groupConfig = buildMetadataConfig(
          updatedAt: updatedAt,
          name: 'Recovered Avatar Group',
          avatarBlobId: 'blob-1',
          avatarMime: 'image/jpeg',
        );
        final sysText = jsonEncode(
          signedMetadataSystemPayload(
            updatedAt: updatedAt,
            groupConfig: groupConfig,
          ),
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': updatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updatedGroup = await groupRepo.getGroup('group-1');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.avatarPath, 'media/group_avatars/group-1.jpg');
        expect(downloadCalls, 1);
      },
    );

    test('unauthorized member_removed is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {'peerId': 'peer-admin', 'username': 'Admin'},
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getGroup('group-1'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test('replayed unauthorized member_removed is ignored', () async {
      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {'peerId': 'peer-admin', 'username': 'Admin'},
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      await listener.handleReplayEnvelope({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      expect(await groupRepo.getGroup('group-1'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'member_removed emits CONFIG_SYNC_FAILED when both update attempts fail',
      () async {
        bridge = SequencedUpdateConfigBridge([
          (_) async => throw Exception('first update failed'),
          (_) async => throw Exception('second update failed'),
        ]);
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(2),
        );
        expect(
          debugLogs.any(
            (line) => line.contains('"event":"CONFIG_SYNC_FAILED"'),
          ),
          isTrue,
        );
      },
    );

    test(
      'member_removed emits readable timeline event on groupMessageStream',
      () async {
        listener.start(sourceController.stream);

        final messages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(messages.add);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(messages, hasLength(1));
        expect(messages.single.text, 'Admin removed Sender');
        expect(messages.single.senderPeerId, 'peer-admin');
        expect(messages.single.senderUsername, 'Admin');
        expect(messages.single.isIncoming, isTrue);
        expect(msgRepo.count, 1);
        final saved = await msgRepo.getLatestMessage('group-1');
        expect(saved, isNotNull);
        expect(saved!.text, 'Admin removed Sender');

        await subscription.cancel();
      },
    );

    test(
      'self-removal calls leaveGroup and emits on groupRemovedStream',
      () async {
        // Create a listener that knows its own peerId
        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );

        // Add self as a member of the group
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        selfListener.start(sourceController.stream);

        final removedGroups = <String>[];
        final sub = selfListener.groupRemovedStream.listen(removedGroups.add);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-self', 'username': 'Me'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {'peerId': 'peer-admin', 'role': 'admin'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        // Bridge should have received group:leave
        expect(bridge.commandLog, contains('group:leave'));

        // Group should be deleted from local DB
        final group = await groupRepo.getGroup('group-1');
        expect(group, isNull);

        // groupRemovedStream should have emitted the group ID
        expect(removedGroups, ['group-1']);

        // No regular message saved
        expect(msgRepo.count, 0);

        await sub.cancel();
        selfListener.dispose();
      },
    );

    test(
      'duplicate self-removal emits one removal signal and leaves once',
      () async {
        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        selfListener.start(sourceController.stream);

        final removedGroups = <String>[];
        final sub = selfListener.groupRemovedStream.listen(removedGroups.add);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-self', 'username': 'Me'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {'peerId': 'peer-admin', 'role': 'admin'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(removedGroups, ['group-1']);
        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(msgRepo.count, 0);

        await sub.cancel();
        selfListener.dispose();
      },
    );

    test(
      'older member_added cannot revive state after a newer removal across restart',
      () async {
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        const newerRemoveAt = '2026-04-05T12:00:02.000Z';
        final newerRemove = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': newerRemove,
          'timestamp': newerRemoveAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        final persistedAfterRemove = await groupRepo.getGroup('group-1');
        expect(
          persistedAfterRemove!.lastMembershipEventAt,
          DateTime.parse(newerRemoveAt).toUtc(),
        );
        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderAdd = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': 'writer',
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': olderAdd,
          'timestamp': '2026-04-05T12:00:01.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        restartedListener.dispose();
      },
    );

    test('handles key_rotated system message without error', () async {
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
      );
      listener.start(sourceController.stream);

      final sysText = jsonEncode({'__sys': 'key_rotated', 'newKeyEpoch': 2});

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // System message should NOT be saved as a regular message
      expect(msgRepo.count, 0);

      // No crash, no error — just handled gracefully
    });

    test('removal of other member does NOT call leaveGroup', () async {
      // Create a listener that knows its own peerId
      final selfListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      selfListener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {'peerId': 'peer-sender', 'username': 'Sender'},
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin'},
            {'peerId': 'peer-self', 'role': 'writer'},
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // Bridge should NOT have received group:leave
      expect(bridge.commandLog, isNot(contains('group:leave')));

      // Bridge should have received group:updateConfig
      expect(bridge.commandLog, contains('group:updateConfig'));

      // Group should still exist
      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);

      selfListener.dispose();
    });

    test('member_role_updated changes role and calls updateConfig', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_role_updated',
        'member': {
          'peerId': 'peer-sender',
          'username': 'Sender',
          'role': 'admin',
          'publicKey': 'pk-sender',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'admin',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final updated = await groupRepo.getMember('group-1', 'peer-sender');
      expect(updated, isNotNull);
      expect(updated!.role, MemberRole.admin);
      expect(bridge.commandLog, contains('group:updateConfig'));
      expect(msgRepo.count, 1);
      final saved = await msgRepo.getLatestMessage('group-1');
      expect(saved, isNotNull);
      expect(saved!.text, 'Admin made Sender an admin');
      expect(
        saved.id.startsWith('sys-member_role_updated:group-1:peer-sender:'),
        isTrue,
      );
    });

    test(
      'member_role_updated logs event and rejects tampered replay before mutation',
      () async {
        final eventLog = _FakeEventLog();
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
        );
        listener.start(sourceController.stream);

        Map<String, dynamic> rolePayload(String role) => {
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': role,
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {'peerId': 'peer-sender', 'role': role, 'publicKey': 'pk-sender'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.utc(2026, 4, 30).toIso8601String(),
          },
        };

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'role-event-1',
          'text': jsonEncode(rolePayload('admin')),
          'timestamp': DateTime.utc(2026, 4, 30, 12).toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(eventLog.entries, hasLength(1));
        expect(eventLog.entries.single['eventType'], 'member_role_updated');
        expect(eventLog.entries.single['sourceEventId'], 'role-event-1');
        expect(
          (await groupRepo.getMember('group-1', 'peer-sender'))!.role,
          MemberRole.admin,
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'role-event-1',
          'text': jsonEncode(rolePayload('member')),
          'timestamp': DateTime.utc(2026, 4, 30, 12).toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(eventLog.entries, hasLength(1));
        expect(
          (await groupRepo.getMember('group-1', 'peer-sender'))!.role,
          MemberRole.admin,
        );
      },
    );

    test('unauthorized member_role_updated is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_role_updated',
        'member': {
          'peerId': 'peer-admin',
          'username': 'Admin',
          'role': 'writer',
          'publicKey': 'pk-admin',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'writer', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNotNull);
      expect(await groupRepo.getGroup('group-1'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'limited manager member_role_updated cannot promote a member to admin',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-manager',
            username: 'Manager',
            role: MemberRole.writer,
            permissions: const GroupMemberPermissions(manageRoles: true),
            publicKey: 'pk-manager',
            joinedAt: initialMemberJoinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-target',
            username: 'Target',
            role: MemberRole.reader,
            publicKey: 'pk-target',
            joinedAt: initialMemberJoinedAt,
          ),
        );

        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-target',
            'username': 'Target',
            'role': 'admin',
            'publicKey': 'pk-target',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-manager',
                'role': 'writer',
                'permissions': {'manageRoles': true},
                'publicKey': 'pk-manager',
              },
              {
                'peerId': 'peer-target',
                'role': 'admin',
                'publicKey': 'pk-target',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-manager',
          'senderUsername': 'Manager',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final target = await groupRepo.getMember('group-1', 'peer-target');
        expect(target, isNotNull);
        expect(target!.role, MemberRole.reader);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'limited manager member_role_updated cannot grant unheld permissions',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-manager',
            username: 'Manager',
            role: MemberRole.writer,
            permissions: const GroupMemberPermissions(manageRoles: true),
            publicKey: 'pk-manager',
            joinedAt: initialMemberJoinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-target',
            username: 'Target',
            role: MemberRole.writer,
            publicKey: 'pk-target',
            joinedAt: initialMemberJoinedAt,
          ),
        );

        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-target',
            'username': 'Target',
            'role': 'writer',
            'permissions': {'deleteMessages': true},
            'publicKey': 'pk-target',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-manager',
                'role': 'writer',
                'permissions': {'manageRoles': true},
                'publicKey': 'pk-manager',
              },
              {
                'peerId': 'peer-target',
                'role': 'writer',
                'permissions': {'deleteMessages': true},
                'publicKey': 'pk-target',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-manager',
          'senderUsername': 'Manager',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final target = await groupRepo.getMember('group-1', 'peer-target');
        expect(target, isNotNull);
        expect(target!.role, MemberRole.writer);
        expect(target.permissions.deleteMessages, isNull);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'member_role_updated refreshes myRole when self gains admin',
      () async {
        await groupRepo.updateGroup(
          testGroup.copyWith(myRole: GroupRole.member),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );
        selfListener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {'peerId': 'peer-self', 'username': 'Me', 'role': 'admin'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {'peerId': 'peer-self', 'role': 'admin', 'publicKey': 'pk-self'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updatedGroup = await groupRepo.getGroup('group-1');
        final updatedMember = await groupRepo.getMember('group-1', 'peer-self');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.myRole, GroupRole.admin);
        expect(updatedMember, isNotNull);
        expect(updatedMember!.role, MemberRole.admin);

        selfListener.dispose();
      },
    );

    test(
      'older member_role_updated cannot roll back a newer role change across restart',
      () async {
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        const newerRoleAt = '2026-04-05T12:00:02.000Z';
        final newerRoleUpdate = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': 'admin',
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'admin',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': newerRoleUpdate,
          'timestamp': newerRoleAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        final afterNewer = await groupRepo.getMember('group-1', 'peer-sender');
        expect(afterNewer, isNotNull);
        expect(afterNewer!.role, MemberRole.admin);
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          DateTime.parse(newerRoleAt).toUtc(),
        );

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderRoleUpdate = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': 'writer',
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': olderRoleUpdate,
          'timestamp': '2026-04-05T12:00:01.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final persisted = await groupRepo.getMember('group-1', 'peer-sender');
        expect(persisted, isNotNull);
        expect(persisted!.role, MemberRole.admin);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        restartedListener.dispose();
      },
    );

    test(
      'older member_role_updated cannot resurrect a member removed by a newer event across restart',
      () async {
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        const newerRemoveAt = '2026-04-05T12:00:03.000Z';
        final newerRemove = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'removedAt': newerRemoveAt,
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': newerRemove,
          'timestamp': newerRemoveAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          DateTime.parse(newerRemoveAt).toUtc(),
        );

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderRoleUpdate = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': 'admin',
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'admin',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': olderRoleUpdate,
          'timestamp': '2026-04-05T12:00:02.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        restartedListener.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Media forwarding tests
  // ---------------------------------------------------------------------------
  group('media forwarding', () {
    test(
      'forwards media field from event to handleIncomingGroupMessage',
      () async {
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'Photo message',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-event-1',
              'mime': 'image/jpeg',
              'size': 12345,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'contentHash': _validContentHash,
              'encryptionKeyBase64': 'key-fixture',
              'encryptionNonce': 'nonce-fixture',
              'encryptionScheme': 'blob_aes_256_gcm_v1',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });

        await Future.delayed(const Duration(milliseconds: 100));

        expect(msgRepo.count, 1);
        expect(mediaRepo.count, 1);

        mediaListener.dispose();
        await mediaSource.close();
      },
    );

    test(
      'rejects invalid media before notification preview or auto-download',
      () async {
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'messageId': 'msg-invalid-media-listener',
          'text': 'Bad media',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-invalid-listener',
              'mime': 'image/svg+xml',
              'size': 12345,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });

        await Future.delayed(const Duration(milliseconds: 100));

        expect(await msgRepo.getMessage('msg-invalid-media-listener'), isNull);
        expect(mediaRepo.count, 0);
        expect(notifService.shown, isEmpty);
        expect(bridge.commandLog, isNot(contains('media:download')));

        mediaListener.dispose();
        await mediaSource.close();
      },
    );

    test(
      'rejects oversized media before notification preview or auto-download',
      () async {
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'messageId': 'msg-oversized-media-listener',
          'text': 'Huge media',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-oversized-listener',
              'mime': 'image/jpeg',
              'size': kGroupMediaPerAttachmentLimitBytes + 1,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });

        await Future.delayed(const Duration(milliseconds: 100));

        expect(
          await msgRepo.getMessage('msg-oversized-media-listener'),
          isNull,
        );
        expect(mediaRepo.count, 0);
        expect(notifService.shown, isEmpty);
        expect(bridge.commandLog, isNot(contains('media:download')));

        mediaListener.dispose();
        await mediaSource.close();
      },
    );

    test(
      'rejects hashless media before notification preview or auto-download',
      () async {
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'messageId': 'msg-hashless-media-listener',
          'text': 'Hashless media',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-hashless-listener',
              'mime': 'image/jpeg',
              'size': 12345,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });

        await Future.delayed(const Duration(milliseconds: 100));

        expect(await msgRepo.getMessage('msg-hashless-media-listener'), isNull);
        expect(mediaRepo.count, 0);
        expect(notifService.shown, isEmpty);
        expect(bridge.commandLog, isNot(contains('media:download')));

        mediaListener.dispose();
        await mediaSource.close();
      },
    );

    test('handles event without media field (backward compat)', () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final mediaListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
      );
      final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

      mediaListener.start(mediaSource.stream);

      mediaSource.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Text only',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 100));

      expect(msgRepo.count, 1);
      expect(mediaRepo.count, 0);

      mediaListener.dispose();
      await mediaSource.close();
    });

    test(
      'joins an in-flight shared media download for the same incoming attachment',
      () async {
        final mediaRepo = GateableMediaAttachmentRepository();
        final delayedBridge = _DelayedMediaDownloadBridge();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        final firstDownloadFuture = downloadMedia(
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          attachment: const MediaAttachment(
            id: 'blob-event-1',
            messageId: 'msg-group-1',
            mime: 'image/jpeg',
            size: 12345,
            mediaType: 'image',
            downloadStatus: 'pending',
            contentHash: _bytes123ContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-03-26T10:00:00.000Z',
          ),
          contactPeerId: 'group-1',
        );
        await Future<void>.delayed(Duration.zero);

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'messageId': 'msg-group-1',
          'text': 'Photo message',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-event-1',
              'mime': 'image/jpeg',
              'size': 12345,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'contentHash': _bytes123ContentHash,
              'encryptionKeyBase64': 'key-fixture',
              'encryptionNonce': 'nonce-fixture',
              'encryptionScheme': 'blob_aes_256_gcm_v1',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(mediaRepo.count, 1);
        expect(mediaRepo.downloadingUpdateCalls, 1);
        expect(
          delayedBridge.commandLog.where((cmd) => cmd == 'media:download'),
          isEmpty,
        );

        mediaRepo.firstDownloadingGate.complete();
        await Future<void>.delayed(Duration.zero);
        expect(
          delayedBridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(1),
        );

        delayedBridge.downloadGate.complete();
        await firstDownloadFuture;
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final savedAttachments = await mediaRepo.getAttachmentsForMessage(
          'msg-group-1',
        );
        expect(savedAttachments.single.downloadStatus, 'done');
        expect(savedAttachments.single.localPath, startsWith('media/'));
        expect(mediaRepo.downloadingUpdateCalls, 1);
        expect(
          delayedBridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(1),
        );

        mediaListener.dispose();
        await mediaSource.close();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Group notifications
  // ---------------------------------------------------------------------------
  group('group notifications', () {
    test('shows notification for incoming group message', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Hello group!',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, hasLength(1));
      expect(notifService.shown.first.contactPeerId, 'group:group-1');
      expect(notifService.shown.first.senderUsername, 'Test Group');
      expect(notifService.shown.first.messageText, 'Sender: Hello group!');

      notifListener.dispose();
    });

    test(
      'replayed duplicate group message does not create a second local notification',
      () async {
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        final notifListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        notifListener.start(sourceController.stream);

        final message = {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'Hello group!',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'messageId': 'group-replay-1',
        };

        sourceController.add(message);

        await Future.delayed(const Duration(milliseconds: 50));

        expect(notifService.shown, hasLength(1));
        expect(msgRepo.count, 1);

        await notifListener.handleReplayEnvelope(message);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          notifService.shown,
          hasLength(1),
          reason: 'Replay must not create a second local notification',
        );
        expect(
          msgRepo.count,
          1,
          reason: 'Replay must not persist a second message row',
        );

        notifListener.dispose();
      },
    );

    test(
      'suppresses local notification when a recent remote push already announced the same group message',
      () async {
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/group-listener-remote-push-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        addTearDown(gate.clear);
        await gate.markAnnouncement(
          payload: 'group:group-1|message:group-msg-1',
          messageId: 'group-msg-1',
        );

        final notifListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          remoteNotificationGate: gate,
        );
        notifListener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'Hello group!',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'messageId': 'group-msg-1',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(notifService.shown, isEmpty);
        expect(msgRepo.count, 1);

        notifListener.dispose();
      },
    );

    test('suppresses notification when viewing group conversation', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      tracker.setActive('group:group-1');

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Hello group!',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, isEmpty);

      notifListener.dispose();
    });

    test(
      'suppresses local notification for muted groups but still persists the message',
      () async {
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        await groupRepo.updateGroup(testGroup.copyWith(isMuted: true));

        final notifListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        notifListener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'Muted group message',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(notifService.shown, isEmpty);
        expect(msgRepo.count, 1);
        final latest = await msgRepo.getLatestMessage('group-1');
        expect(latest, isNotNull);
        expect(latest!.text, 'Muted group message');

        notifListener.dispose();
      },
    );

    test('does not notify for own messages', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-sender',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'My own message',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, isEmpty);

      notifListener.dispose();
    });

    test('does not notify after self-removal deletes the group', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Me',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      notifListener.start(sourceController.stream);

      final removedGroups = <String>[];
      final sub = notifListener.groupRemovedStream.listen(removedGroups.add);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {'peerId': 'peer-self', 'username': 'Me'},
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin'},
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getGroup('group-1'), isNull);
      expect(removedGroups, <String>['group-1']);
      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'After removal',
        'messageId': 'post-removal-message-1',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, isEmpty);
      expect(msgRepo.count, 0);

      await sub.cancel();
      notifListener.dispose();
    });

    test('does not notify when notification deps are null', () async {
      // Default listener without notification params (current behavior)
      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'No crash please',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // No crash, message still persisted
      expect(msgRepo.count, 1);
    });

    test('shows notification when viewing different group', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      tracker.setActive('group:other-group');

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Hello!',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, hasLength(1));

      notifListener.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Group reactions
  // ---------------------------------------------------------------------------
  group('group reactions', () {
    late FakeReactionRepository reactionRepo;
    late StreamController<Map<String, dynamic>> reactionSource;

    setUp(() {
      reactionRepo = FakeReactionRepository();
      reactionSource = StreamController<Map<String, dynamic>>.broadcast();
    });

    tearDown(() {
      reactionSource.close();
    });

    test(
      'emits ReactionChange on groupReactionChangeStream for incoming add reaction',
      () async {
        final rxnListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          reactionRepo: reactionRepo,
        );

        rxnListener.start(
          sourceController.stream,
          incomingGroupReactions: reactionSource.stream,
        );

        final changes = <ReactionChange>[];
        final sub = rxnListener.groupReactionChangeStream.listen(changes.add);

        reactionSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'reaction': jsonEncode({
            'id': 'rxn-1',
            'messageId': 'msg-1',
            'emoji': '\u{1F44D}',
            'action': 'add',
            'senderPeerId': 'peer-sender',
            'timestamp': '2026-01-01T00:00:00.000Z',
          }),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(changes.length, 1);
        expect(changes.first.type, ReactionChangeType.upserted);
        expect(changes.first.messageId, 'msg-1');
        expect(changes.first.reaction?.emoji, '\u{1F44D}');
        expect(reactionRepo.saveReactionCallCount, 1);

        await sub.cancel();
        rxnListener.dispose();
      },
    );

    test('emits removal ReactionChange when action is remove', () async {
      final rxnListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        reactionRepo: reactionRepo,
      );

      rxnListener.start(
        sourceController.stream,
        incomingGroupReactions: reactionSource.stream,
      );

      final changes = <ReactionChange>[];
      final sub = rxnListener.groupReactionChangeStream.listen(changes.add);

      reactionSource.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'reaction': jsonEncode({
          'id': 'rxn-1',
          'messageId': 'msg-1',
          'emoji': '\u{1F44D}',
          'action': 'remove',
          'senderPeerId': 'peer-sender',
          'timestamp': '2026-01-01T00:00:00.000Z',
        }),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(changes.length, 1);
      expect(changes.first.type, ReactionChangeType.removed);
      expect(changes.first.messageId, 'msg-1');
      expect(changes.first.senderPeerId, 'peer-sender');

      await sub.cancel();
      rxnListener.dispose();
    });

    test('ignores reaction when reactionRepo is null', () async {
      final noRepoListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        // No reactionRepo
      );

      noRepoListener.start(
        sourceController.stream,
        incomingGroupReactions: reactionSource.stream,
      );

      final changes = <ReactionChange>[];
      final sub = noRepoListener.groupReactionChangeStream.listen(changes.add);

      reactionSource.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'reaction': jsonEncode({
          'id': 'rxn-1',
          'messageId': 'msg-1',
          'emoji': '\u{1F44D}',
          'action': 'add',
          'senderPeerId': 'peer-sender',
          'timestamp': '2026-01-01T00:00:00.000Z',
        }),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(changes, isEmpty);

      await sub.cancel();
      noRepoListener.dispose();
    });

    test('ignores malformed reaction data', () async {
      final rxnListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        reactionRepo: reactionRepo,
      );

      rxnListener.start(
        sourceController.stream,
        incomingGroupReactions: reactionSource.stream,
      );

      final changes = <ReactionChange>[];
      final sub = rxnListener.groupReactionChangeStream.listen(changes.add);

      // Empty groupId and senderId → malformed, should be ignored
      reactionSource.add({
        'groupId': '',
        'senderId': '',
        'reaction': jsonEncode({
          'id': 'rxn-1',
          'messageId': 'msg-1',
          'emoji': '\u{1F44D}',
          'action': 'add',
          'senderPeerId': 'peer-sender',
          'timestamp': '2026-01-01T00:00:00.000Z',
        }),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(changes, isEmpty);

      await sub.cancel();
      rxnListener.dispose();
    });
  });

  group('group_dissolved system messages', () {
    test(
      'marks the group dissolved, stores a timeline event, and leaves the topic',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            joinedAt: initialMemberJoinedAt,
          ),
        );
        listener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'group_dissolved',
            'dissolvedAt': '2026-04-05T12:00:00.000Z',
            'dissolvedBy': 'peer-admin',
          }),
          'timestamp': '2026-04-05T12:00:00.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updated = await groupRepo.getGroup('group-1');
        expect(updated, isNotNull);
        expect(updated!.isDissolved, isTrue);
        expect(updated.dissolvedAt, DateTime.utc(2026, 4, 5, 12, 0, 0));
        expect(updated.dissolvedBy, 'peer-admin');

        final saved = await msgRepo.getLatestMessage('group-1');
        expect(saved, isNotNull);
        expect(saved!.id.startsWith('sys-group_dissolved:group-1:'), isTrue);
        expect(saved.text, 'Admin dissolved the group');
        expect(bridge.commandLog, contains('group:leave'));
      },
    );

    test('replayed group_dissolved is idempotent', () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: initialMemberJoinedAt,
        ),
      );
      await listener.handleReplayEnvelope({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'group_dissolved',
          'dissolvedAt': '2026-04-05T12:00:00.000Z',
          'dissolvedBy': 'peer-admin',
        }),
        'timestamp': '2026-04-05T12:00:00.000Z',
      });

      await listener.handleReplayEnvelope({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'group_dissolved',
          'dissolvedAt': '2026-04-05T12:00:00.000Z',
          'dissolvedBy': 'peer-admin',
        }),
        'timestamp': '2026-04-05T12:00:00.000Z',
      });

      final messages = await msgRepo.getMessagesPage('group-1');
      final dissolvedMessages = messages
          .where((message) => message.id.startsWith('sys-group_dissolved:'))
          .toList();
      expect(dissolvedMessages, hasLength(1));

      final leaveCalls = bridge.commandLog
          .where((command) => command == 'group:leave')
          .length;
      expect(leaveCalls, 1);
    });

    test(
      'old system events after group_dissolved do not mutate metadata, members, keys, or visible messages',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            joinedAt: initialMemberJoinedAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'epoch-1-key',
            createdAt: DateTime.utc(2026, 4, 5, 11, 59),
          ),
        );

        await listener.handleReplayEnvelope({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'group_dissolved',
            'dissolvedAt': '2026-04-05T12:00:00.000Z',
            'dissolvedBy': 'peer-admin',
          }),
          'timestamp': '2026-04-05T12:00:00.000Z',
        });

        final staleEvents = <Map<String, dynamic>>[
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'group_metadata_updated',
              'updatedAt': '2026-04-05T11:59:00.000Z',
              'groupConfig': {
                'name': 'Resurrected Name',
                'groupType': 'chat',
                'description': 'Should not return',
                'metadataUpdatedAt': '2026-04-05T11:59:00.000Z',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-sender',
                    'role': 'writer',
                    'publicKey': 'pk-sender',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T11:59:00.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_added',
              'member': {
                'peerId': 'peer-resurrected',
                'username': 'Resurrected',
                'role': 'writer',
                'publicKey': 'pk-resurrected',
              },
              'groupConfig': {
                'name': 'Resurrected Name',
                'groupType': 'chat',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-resurrected',
                    'role': 'writer',
                    'publicKey': 'pk-resurrected',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T11:59:01.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_role_updated',
              'member': {
                'peerId': 'peer-sender',
                'username': 'Sender',
                'role': 'admin',
                'publicKey': 'pk-sender',
              },
              'groupConfig': {
                'name': 'Resurrected Name',
                'groupType': 'chat',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-sender',
                    'role': 'admin',
                    'publicKey': 'pk-sender',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T11:59:02.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({'__sys': 'key_rotated', 'newKeyEpoch': 2}),
            'timestamp': '2026-04-05T11:59:03.000Z',
          },
        ];

        for (final event in staleEvents) {
          await listener.handleReplayEnvelope(event);
        }

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.isDissolved, isTrue);
        expect(group.name, 'Test Group');
        expect(group.description, isNull);
        expect(group.lastMetadataEventAt, isNull);

        expect(
          await groupRepo.getMember('group-1', 'peer-resurrected'),
          isNull,
        );
        final sender = await groupRepo.getMember('group-1', 'peer-sender');
        expect(sender, isNotNull);
        expect(sender!.role, MemberRole.writer);

        final latestKey = await groupRepo.getLatestKey('group-1');
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 1);
        expect(latestKey.encryptedKey, 'epoch-1-key');

        final messages = await msgRepo.getMessagesPage('group-1');
        expect(messages, hasLength(1));
        expect(messages.single.text, 'Admin dissolved the group');
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      },
    );

    test(
      'old system events for a locally deleted group do not recreate group row or visible message',
      () async {
        await groupRepo.deleteGroup('group-1');
        await groupRepo.removeAllMembers('group-1');
        await groupRepo.removeAllKeys('group-1');

        final deletedGroupEvents = <Map<String, dynamic>>[
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'group_metadata_updated',
              'updatedAt': '2026-04-05T12:01:00.000Z',
              'groupConfig': {
                'name': 'Deleted Group Returned',
                'groupType': 'chat',
                'description': 'Should not be visible',
                'metadataUpdatedAt': '2026-04-05T12:01:00.000Z',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T12:01:00.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_added',
              'member': {
                'peerId': 'peer-returned',
                'username': 'Returned',
                'role': 'writer',
                'publicKey': 'pk-returned',
              },
              'groupConfig': {
                'name': 'Deleted Group Returned',
                'groupType': 'chat',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-returned',
                    'role': 'writer',
                    'publicKey': 'pk-returned',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T12:01:01.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({'__sys': 'key_rotated', 'newKeyEpoch': 2}),
            'timestamp': '2026-04-05T12:01:02.000Z',
          },
        ];

        for (final event in deletedGroupEvents) {
          await listener.handleReplayEnvelope(event);
        }

        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(await groupRepo.getMembers('group-1'), isEmpty);
        expect(await groupRepo.getLatestKey('group-1'), isNull);
        expect(await msgRepo.getMessagesPage('group-1'), isEmpty);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      },
    );

    test('unauthorized group_dissolved is ignored', () async {
      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'group_dissolved',
          'dissolvedAt': '2026-04-05T12:00:00.000Z',
          'dissolvedBy': 'peer-sender',
        }),
        'timestamp': '2026-04-05T12:00:00.000Z',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);
      expect(group!.isDissolved, isFalse);
      expect(await msgRepo.getLatestMessage('group-1'), isNull);
      expect(bridge.commandLog, isNot(contains('group:leave')));
    });

    test(
      'stored creator who is no longer admin cannot dissolve the group',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.writer,
            joinedAt: initialMemberJoinedAt,
          ),
        );

        listener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'group_dissolved',
            'dissolvedAt': '2026-04-05T12:00:00.000Z',
            'dissolvedBy': 'peer-admin',
          }),
          'timestamp': '2026-04-05T12:00:00.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.isDissolved, isFalse);
        expect(await msgRepo.getLatestMessage('group-1'), isNull);
        expect(bridge.commandLog, isNot(contains('group:leave')));
      },
    );
  });

  group('duplicate shipped system event replay', () {
    int updateConfigCallCount() => bridge.commandLog
        .where((command) => command == 'group:updateConfig')
        .length;

    test(
      'duplicate members_added keeps one timeline row and member set',
      () async {
        listener.start(sourceController.stream);

        const eventAt = '2026-04-05T12:10:00.000Z';
        final sysText = jsonEncode({
          '__sys': 'members_added',
          'members': [
            {
              'peerId': 'peer-dave',
              'username': 'Dave',
              'role': 'writer',
              'publicKey': 'pk-dave',
            },
            {
              'peerId': 'peer-eve',
              'username': 'Eve',
              'role': 'writer',
              'publicKey': 'pk-eve',
            },
          ],
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {'peerId': 'peer-dave', 'role': 'writer', 'publicKey': 'pk-dave'},
              {'peerId': 'peer-eve', 'role': 'writer', 'publicKey': 'pk-eve'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        });
        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'members-added-replay-1',
          'text': sysText,
          'timestamp': eventAt,
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-dave'), isNotNull);
        expect(await groupRepo.getMember('group-1', 'peer-eve'), isNotNull);
        expect(msgRepo.count, 1);
        expect(
          (await msgRepo.getLatestMessage('group-1'))!.text,
          'Admin added Dave and Eve',
        );
        expect(updateConfigCallCount(), 1);
      },
    );

    test(
      'duplicate non-self member_removed keeps one timeline row and removal',
      () async {
        listener.start(sourceController.stream);

        const eventAt = '2026-04-05T12:11:00.000Z';
        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        });
        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'member-removed-replay-1',
          'text': sysText,
          'timestamp': eventAt,
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(msgRepo.count, 1);
        expect(
          (await msgRepo.getLatestMessage('group-1'))!.text,
          'Admin removed Sender',
        );
        expect(updateConfigCallCount(), 1);
        expect(bridge.commandLog, isNot(contains('group:leave')));
      },
    );

    test('duplicate member_role_updated keeps one role timeline row', () async {
      listener.start(sourceController.stream);

      const eventAt = '2026-04-05T12:12:00.000Z';
      final sysText = jsonEncode({
        '__sys': 'member_role_updated',
        'member': {
          'peerId': 'peer-sender',
          'username': 'Sender',
          'role': 'admin',
          'publicKey': 'pk-sender',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'admin',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': initialGroupCreatedAt.toIso8601String(),
        },
      });
      final duplicateEvent = {
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'member-role-updated-replay-1',
        'text': sysText,
        'timestamp': eventAt,
      };

      sourceController.add(duplicateEvent);
      sourceController.add(duplicateEvent);
      await Future.delayed(const Duration(milliseconds: 50));

      final updated = await groupRepo.getMember('group-1', 'peer-sender');
      expect(updated, isNotNull);
      expect(updated!.role, MemberRole.admin);
      expect(msgRepo.count, 1);
      expect(
        (await msgRepo.getLatestMessage('group-1'))!.text,
        'Admin made Sender an admin',
      );
      expect(updateConfigCallCount(), 1);
    });

    test(
      'duplicate group_metadata_updated keeps one metadata timeline row',
      () async {
        await saveTrustedAdminMember();
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        listener.start(sourceController.stream);

        final eventAt = DateTime.parse('2026-04-05T12:13:00.000Z');
        final groupConfig = buildMetadataConfig(updatedAt: eventAt);
        final sysText = jsonEncode(
          signedMetadataSystemPayload(
            updatedAt: eventAt,
            groupConfig: groupConfig,
          ),
        );
        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'metadata-updated-replay-1',
          'text': sysText,
          'timestamp': eventAt.toUtc().toIso8601String(),
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);
        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.name, 'Renamed Group');
        expect(group.description, 'Fresh description');
        expect(msgRepo.count, 1);
        expect(
          (await msgRepo.getLatestMessage('group-1'))!.text,
          'Admin updated the group details',
        );
        expect(updateConfigCallCount(), 1);
      },
    );

    test('duplicate key_rotated system event stays non-durable', () async {
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start(sourceController.stream);

      const eventAt = '2026-04-05T12:14:00.000Z';
      final duplicateEvent = {
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'key-rotated-replay-1',
        'text': jsonEncode({'__sys': 'key_rotated', 'newKeyEpoch': 2}),
        'timestamp': eventAt,
      };

      sourceController.add(duplicateEvent);
      sourceController.add(duplicateEvent);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(msgRepo.count, 0);
      expect(eventLog.entries, hasLength(1));
      expect(eventLog.entries.single['eventType'], 'key_rotated');
      expect(eventLog.entries.single['sourceEventId'], 'key-rotated-replay-1');
    });
  });

  test(
    'unauthorized mutation system events leave local state and bridge unchanged',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: initialMemberJoinedAt,
        ),
      );
      listener.start(sourceController.stream);

      final mutationEvents = <({String name, String text})>[
        (
          name: 'member_added',
          text: jsonEncode({
            '__sys': 'member_added',
            'member': {
              'peerId': 'peer-rp004-added',
              'username': 'Added',
              'role': 'writer',
              'publicKey': 'pk-added',
            },
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
                {
                  'peerId': 'peer-rp004-added',
                  'role': 'writer',
                  'publicKey': 'pk-added',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'members_added',
          text: jsonEncode({
            '__sys': 'members_added',
            'members': [
              {
                'peerId': 'peer-rp004-added-a',
                'username': 'Added A',
                'role': 'writer',
                'publicKey': 'pk-added-a',
              },
              {
                'peerId': 'peer-rp004-added-b',
                'username': 'Added B',
                'role': 'writer',
                'publicKey': 'pk-added-b',
              },
            ],
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
                {
                  'peerId': 'peer-rp004-added-a',
                  'role': 'writer',
                  'publicKey': 'pk-added-a',
                },
                {
                  'peerId': 'peer-rp004-added-b',
                  'role': 'writer',
                  'publicKey': 'pk-added-b',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'member_removed',
          text: jsonEncode({
            '__sys': 'member_removed',
            'member': {'peerId': 'peer-admin', 'username': 'Admin'},
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'member_role_updated',
          text: jsonEncode({
            '__sys': 'member_role_updated',
            'member': {
              'peerId': 'peer-admin',
              'username': 'Admin',
              'role': 'writer',
              'publicKey': 'pk-admin',
            },
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'writer',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'group_metadata_updated',
          text: jsonEncode({
            '__sys': 'group_metadata_updated',
            'updatedAt': '2026-04-05T12:45:00.000Z',
            'groupConfig': {
              'name': 'Unauthorized Name',
              'groupType': 'chat',
              'description': 'Unauthorized description',
              'metadataUpdatedAt': '2026-04-05T12:45:00.000Z',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'group_dissolved',
          text: jsonEncode({
            '__sys': 'group_dissolved',
            'dissolvedAt': '2026-04-05T12:50:00.000Z',
            'dissolvedBy': 'peer-sender',
          }),
        ),
      ];

      for (final mutationEvent in mutationEvents) {
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': mutationEvent.text,
          'timestamp': '2026-04-05T12:55:00.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull, reason: mutationEvent.name);
        expect(group!.name, 'Test Group', reason: mutationEvent.name);
        expect(group.description, isNull, reason: mutationEvent.name);
        expect(group.isDissolved, isFalse, reason: mutationEvent.name);
        expect(group.lastMetadataEventAt, isNull, reason: mutationEvent.name);

        final admin = await groupRepo.getMember('group-1', 'peer-admin');
        final sender = await groupRepo.getMember('group-1', 'peer-sender');
        expect(admin, isNotNull, reason: mutationEvent.name);
        expect(admin!.role, MemberRole.admin, reason: mutationEvent.name);
        expect(sender, isNotNull, reason: mutationEvent.name);
        expect(sender!.role, MemberRole.writer, reason: mutationEvent.name);
        expect(
          await groupRepo.getMember('group-1', 'peer-rp004-added'),
          isNull,
          reason: mutationEvent.name,
        );
        expect(
          await groupRepo.getMember('group-1', 'peer-rp004-added-a'),
          isNull,
          reason: mutationEvent.name,
        );
        expect(
          await groupRepo.getMember('group-1', 'peer-rp004-added-b'),
          isNull,
          reason: mutationEvent.name,
        );
        expect(msgRepo.count, 0, reason: mutationEvent.name);
        expect(bridge.commandLog, isEmpty, reason: mutationEvent.name);
      }
    },
  );
}
