import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
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

      // System message should NOT be saved as a regular message
      expect(msgRepo.count, 0);

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
      'group_metadata_updated refreshes group metadata and stores a timeline event',
      () async {
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          downloadGroupAvatarFn:
              ({
                required dynamic bridge,
                required String groupId,
                required String blobId,
              }) async => 'media/group_avatars/$groupId.jpg',
        );
        listener.start(sourceController.stream);

        const updatedAt = '2026-04-05T12:20:00.000Z';
        final sysText = jsonEncode({
          '__sys': 'group_metadata_updated',
          'updatedAt': updatedAt,
          'groupConfig': {
            'name': 'Renamed Group',
            'groupType': 'chat',
            'description': 'Fresh description',
            'avatarBlobId': 'blob-1',
            'avatarMime': 'image/jpeg',
            'metadataUpdatedAt': updatedAt,
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
            'createdAt': '2026-04-05T12:00:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': updatedAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updatedGroup = await groupRepo.getGroup('group-1');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.name, 'Renamed Group');
        expect(updatedGroup.description, 'Fresh description');
        expect(updatedGroup.avatarBlobId, 'blob-1');
        expect(updatedGroup.avatarMime, 'image/jpeg');
        expect(updatedGroup.avatarPath, 'media/group_avatars/group-1.jpg');
        expect(
          updatedGroup.lastMetadataEventAt,
          DateTime.parse(updatedAt).toUtc(),
        );

        final latest = await msgRepo.getLatestMessage('group-1');
        expect(latest, isNotNull);
        expect(latest!.text, 'Admin updated the group details');
        expect(bridge.commandLog, contains('group:updateConfig'));
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
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        const newerUpdatedAt = '2026-04-05T12:30:00.000Z';
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'group_metadata_updated',
            'updatedAt': newerUpdatedAt,
            'groupConfig': {
              'name': 'Newest Name',
              'groupType': 'chat',
              'description': 'Newest description',
              'metadataUpdatedAt': newerUpdatedAt,
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
              'createdAt': '2026-04-05T12:00:00.000Z',
            },
          }),
          'timestamp': newerUpdatedAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        final persistedAfterNewer = await groupRepo.getGroup('group-1');
        expect(persistedAfterNewer!.name, 'Newest Name');
        expect(
          persistedAfterNewer.lastMetadataEventAt,
          DateTime.parse(newerUpdatedAt).toUtc(),
        );

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'group_metadata_updated',
            'updatedAt': '2026-04-05T12:10:00.000Z',
            'groupConfig': {
              'name': 'Older Name',
              'groupType': 'chat',
              'description': 'Older description',
              'metadataUpdatedAt': '2026-04-05T12:10:00.000Z',
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
              'createdAt': '2026-04-05T12:00:00.000Z',
            },
          }),
          'timestamp': '2026-04-05T12:10:00.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final finalGroup = await groupRepo.getGroup('group-1');
        expect(finalGroup!.name, 'Newest Name');
        expect(finalGroup.description, 'Newest description');
        expect(
          finalGroup.lastMetadataEventAt,
          DateTime.parse(newerUpdatedAt).toUtc(),
        );

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
        expect(msgRepo.count, 0);

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

      // Not saved as regular message
      expect(msgRepo.count, 0);
    });

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
        expect(msgRepo.count, 0);

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
          payload: 'group:group-1',
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
      expect(bridge.commandLog, contains('group:leave'));

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'After removal',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, isEmpty);
      expect(msgRepo.count, 0);

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
  });
}
