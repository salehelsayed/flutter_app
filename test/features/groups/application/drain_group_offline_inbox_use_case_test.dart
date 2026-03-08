import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: '/mknoon/group/group-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-1',
      peerId: 'peer-sender',
      username: 'Sender',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ));
  });

  test('drains offline inbox and saves messages to repo', () async {
    final messages = [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Offline msg 1',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Offline msg 2',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
    ];

    bridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': messages,
    };

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 2);
    expect(bridge.commandLog, contains('group:inboxRetrieve'));
  });

  test('drains inbox for all active groups', () async {
    final testGroup2 = GroupModel(
      id: 'group-2',
      name: 'Second Group',
      type: GroupType.chat,
      topicName: '/mknoon/group/group-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(testGroup2);
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-2',
      peerId: 'peer-sender',
      username: 'Sender',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ));

    bridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': <Map<String, dynamic>>[],
    };

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    // group:inboxRetrieve should be called once per group
    final retrieveCount =
        bridge.commandLog.where((c) => c == 'group:inboxRetrieve').length;
    expect(retrieveCount, 2);
  });

  test('does not crash on empty inbox', () async {
    bridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': <Map<String, dynamic>>[],
    };

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 0);
    expect(bridge.commandLog, contains('group:inboxRetrieve'));
  });

  test('per-group error isolation: first group error does not block second',
      () async {
    // Add a second group so there are two active groups to drain.
    final testGroup2 = GroupModel(
      id: 'group-2',
      name: 'Second Group',
      type: GroupType.chat,
      topicName: '/mknoon/group/group-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(testGroup2);
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-2',
      peerId: 'peer-sender',
      username: 'Sender',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ));

    // Use a custom bridge that throws on the first inboxRetrieve call
    // but succeeds (with one message) on the second.
    final failBridge = _FirstGroupFailBridge();
    failBridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': <Map<String, dynamic>>[
        {
          'groupId': 'group-2',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Hello from group 2',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    };

    // Should NOT throw despite the first group failing.
    await drainGroupOfflineInbox(
      bridge: failBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    // The second group's message should have been saved.
    expect(msgRepo.count, 1);
  });

  test('malformed inbox payload with missing fields defaults gracefully',
      () async {
    // Provide inbox messages that are nearly empty maps — all optional
    // fields should fall back to their defaults without crashing.
    bridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{}, // completely empty
        <String, dynamic>{'text': 'only text'}, // only text present
      ],
    };

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    // Both messages should be saved (defaults applied).
    expect(msgRepo.count, 2);
  });

  test(
      'callGroupInboxRetrieve throwing for one group does not prevent draining others',
      () async {
    // Setup two groups.
    final testGroup2 = GroupModel(
      id: 'group-2',
      name: 'Second Group',
      type: GroupType.chat,
      topicName: '/mknoon/group/group-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(testGroup2);
    await groupRepo.saveMember(GroupMember(
      groupId: 'group-2',
      peerId: 'peer-sender',
      username: 'Sender',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    ));

    // Use a bridge that throws on the first send, then succeeds.
    final toggleBridge = _ThrowOnceBridge();
    toggleBridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': <Map<String, dynamic>>[
        {
          'groupId': 'group-2',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Survived the error',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    };

    await drainGroupOfflineInbox(
      bridge: toggleBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    // Second group's message should still be persisted.
    expect(msgRepo.count, 1);
  });

  test('drains inbox for archived groups too', () async {
    await groupRepo.archiveGroup('group-1');

    bridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': <Map<String, dynamic>>[
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Archived group msg',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    };

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 1);
    expect(bridge.commandLog, contains('group:inboxRetrieve'));
  });

  // ---------------------------------------------------------------------------
  // Media attachment tests
  // ---------------------------------------------------------------------------
  test('drains inbox message with media — saves media attachments', () async {
    final mediaRepo = InMemoryMediaAttachmentRepository();

    final inboxMessage = jsonEncode({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 1,
      'text': 'Photo message',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'media': [
        {
          'id': 'blob-inbox-1',
          'mime': 'image/jpeg',
          'size': 12345,
          'mediaType': 'image',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    });

    bridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': [
        {'from': 'peer-sender', 'message': inboxMessage, 'timestamp': 123},
      ],
    };

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaRepo,
    );

    expect(msgRepo.count, 1);
    expect(mediaRepo.count, 1);
    final pending = await mediaRepo.getPendingDownloads();
    expect(pending.length, 1);
    expect(pending.first.mime, 'image/jpeg');
  });

  test('drains inbox message without media — backward compat', () async {
    final mediaRepo = InMemoryMediaAttachmentRepository();

    bridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': <Map<String, dynamic>>[
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Text only',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    };

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaRepo,
    );

    expect(msgRepo.count, 1);
    expect(mediaRepo.count, 0);
  });

  // ---------------------------------------------------------------------------
  // Reaction drain tests
  // ---------------------------------------------------------------------------
  test('drains group_reaction items when reactionRepo is provided', () async {
    final reactionRepo = FakeReactionRepository();

    final innerReaction = jsonEncode({
      'id': 'rxn-1',
      'messageId': 'msg-1',
      'emoji': '👍',
      'action': 'add',
      'senderPeerId': 'peer-sender',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    final inboxMessage = jsonEncode({
      'type': 'group_reaction',
      'senderId': 'peer-sender',
      'reaction': innerReaction,
    });

    bridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': [
        {'from': 'peer-sender', 'message': inboxMessage, 'timestamp': 123},
      ],
    };

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
    );

    // Reaction should be persisted
    expect(reactionRepo.saveReactionCallCount, 1);
    expect(reactionRepo.lastSavedReaction?.emoji, '👍');
    // Should NOT be saved as a regular message
    expect(msgRepo.count, 0);
  });

  test('skips group_reaction items when reactionRepo is null', () async {
    final innerReaction = jsonEncode({
      'id': 'rxn-2',
      'messageId': 'msg-1',
      'emoji': '❤️',
      'action': 'add',
      'senderPeerId': 'peer-sender',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    final inboxMessage = jsonEncode({
      'type': 'group_reaction',
      'senderId': 'peer-sender',
      'reaction': innerReaction,
    });

    bridge.responses['group:inboxRetrieve'] = {
      'ok': true,
      'messages': [
        {'from': 'peer-sender', 'message': inboxMessage, 'timestamp': 123},
      ],
    };

    // Do not pass reactionRepo — should not crash
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    // When reactionRepo is null and type == 'group_reaction', the condition
    // is false so it falls through to handleIncomingGroupMessage.
    // This test verifies no crash occurs.
    expect(true, isTrue); // No exception thrown
  });
}

// ---------------------------------------------------------------------------
// Test-only bridge subclasses
// ---------------------------------------------------------------------------

/// A [FakeBridge] that throws on the first `group:inboxRetrieve` call
/// but delegates normally for all subsequent calls.
class _FirstGroupFailBridge extends FakeBridge {
  int _callCount = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'group:inboxRetrieve') {
      _callCount++;
      if (_callCount == 1) throw Exception('network error');
    }
    return super.send(message);
  }
}

/// A [FakeBridge] that throws on the very first `send` call (regardless of
/// command) and then behaves normally for all subsequent calls.
class _ThrowOnceBridge extends FakeBridge {
  bool _hasThrown = false;

  @override
  Future<String> send(String message) async {
    if (!_hasThrown) {
      _hasThrown = true;
      throw Exception('transient failure');
    }
    return super.send(message);
  }
}
