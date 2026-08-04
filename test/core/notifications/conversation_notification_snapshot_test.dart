import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/direct_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/application/group_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _DirectRepository implements MessageRepository {
  _DirectRepository(this.messages);

  final List<ConversationMessage> messages;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String peerId,
  ) async =>
      messages.where((message) => message.contactPeerId == peerId).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GroupRepository implements GroupMessageRepository {
  _GroupRepository(this.messages);

  final List<GroupMessage> messages;

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final matching =
        messages.where((message) => message.groupId == groupId).toList()
          ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    if (offset >= matching.length) return const <GroupMessage>[];
    final end = (offset + limit).clamp(0, matching.length);
    return matching.sublist(offset, end);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationMessage _directMessage(
  int index, {
  bool incoming = true,
  String? readAt,
  PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
  PrivateMediaLifecycleState state = PrivateMediaLifecycleState.none,
}) => ConversationMessage(
  id: 'direct-$index',
  contactPeerId: 'peer-alice',
  senderPeerId: incoming ? 'peer-alice' : 'peer-local',
  text: 'direct line $index',
  timestamp: '2026-08-03T10:${index.toString().padLeft(2, '0')}:00.000Z',
  status: 'delivered',
  isIncoming: incoming,
  createdAt: '2026-08-03T10:${index.toString().padLeft(2, '0')}:01.000Z',
  readAt: readAt,
  privateMediaPolicy: policy,
  privateMediaState: state,
);

GroupMessage _groupMessage(
  int index, {
  bool incoming = true,
  DateTime? readAt,
  GroupPrivateMediaPolicy policy = const GroupPrivateMediaPolicy.ordinary(),
  int? consumedAt,
}) => GroupMessage(
  id: 'group-$index',
  groupId: 'group-team',
  senderPeerId: incoming ? 'peer-alice' : 'peer-local',
  senderUsername: 'Alice',
  text: 'group line $index',
  timestamp: DateTime.utc(2026, 8, 3, 10, index),
  isIncoming: incoming,
  privateMediaPolicy: policy,
  mediaConsumedAt: consumedAt,
  readAt: readAt,
  createdAt: DateTime.utc(2026, 8, 3, 10, index, 1),
);

void main() {
  test('bounded direct and group unread projection', () async {
    final direct = <ConversationMessage>[
      for (var index = 0; index < 6; index++) _directMessage(index),
      _directMessage(
        6,
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.available,
      ),
      _directMessage(7, readAt: '2026-08-03T11:00:00.000Z'),
      _directMessage(8, incoming: false),
      _directMessage(
        9,
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.consumed,
      ),
    ];
    final directSnapshot = await loadDirectConversationNotificationSnapshot(
      messageRepository: _DirectRepository(direct),
      contactPeerId: 'peer-alice',
    );

    expect(directSnapshot?.totalUnreadMessageCount, 7);
    expect(directSnapshot?.historyLines, <String>[
      'direct line 2',
      'direct line 3',
      'direct line 4',
      'direct line 5',
      'Private media',
    ]);

    final group = <GroupMessage>[
      for (var index = 0; index < 6; index++) _groupMessage(index),
      _groupMessage(6, policy: const GroupPrivateMediaPolicy.viewOnce()),
      _groupMessage(
        7,
        policy: const GroupPrivateMediaPolicy.viewOnce(),
        consumedAt: 1,
      ),
      _groupMessage(8, readAt: DateTime.utc(2026, 8, 3, 11)),
      _groupMessage(9, incoming: false),
    ];
    final groupSnapshot = await loadGroupConversationNotificationSnapshot(
      messageRepository: _GroupRepository(group),
      groupId: 'group-team',
    );

    expect(groupSnapshot?.totalUnreadMessageCount, 7);
    expect(groupSnapshot?.historyLines, <String>[
      'Alice: group line 2',
      'Alice: group line 3',
      'Alice: group line 4',
      'Alice: group line 5',
      'New private media',
    ]);
  });
}
