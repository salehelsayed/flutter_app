import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/direct_chat_search.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/groups/application/group_chat_search.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ConversationMessage direct(
    String id,
    String text, {
    String? deletedAt,
    String? hiddenAt,
    PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
  }) => ConversationMessage(
    id: id,
    contactPeerId: 'peer',
    senderPeerId: 'peer',
    text: text,
    timestamp: '2026-11-04T10:00:00.000Z',
    status: 'delivered',
    isIncoming: true,
    createdAt: '2026-11-04T10:00:00.000Z',
    deletedAt: deletedAt,
    hiddenAt: hiddenAt,
    privateMediaPolicy: policy,
  );

  test('1:1 search reads ordinary words and captions only', () {
    final hits = searchDirectChat([
      direct('old', 'Dahab last spring'),
      direct('gone', 'dahab', deletedAt: '2026-11-04T11:00:00.000Z'),
      direct('hidden', 'dahab', hiddenAt: '2026-11-04T11:00:00.000Z'),
      direct('prot', 'dahab', policy: const PrivateMediaPolicy.protected()),
      direct('once', 'dahab', policy: const PrivateMediaPolicy.viewOnce()),
      direct('new', 'back to dahab?'),
    ], 'dahab');
    expect(hits, ['new', 'old']);
  });

  GroupMessage group(
    String id,
    String text, {
    GroupPrivateMediaPolicy policy = const GroupPrivateMediaPolicy.ordinary(),
  }) => GroupMessage(
    id: id,
    groupId: 'g',
    senderPeerId: 'omar',
    senderUsername: 'Omar',
    text: text,
    timestamp: DateTime.utc(2026, 11, 4),
    status: 'sent',
    isIncoming: true,
    createdAt: DateTime.utc(2026, 11, 4),
    privateMediaPolicy: policy,
  );

  test('group search skips private media and removed messages', () {
    final hits = searchGroupChat(
      [
        group('a', 'Who is in for Dahab?'),
        group('b', 'dahab', policy: const GroupPrivateMediaPolicy.protected()),
        group('c', 'dahab'),
        group('d', 'count me in for dahab'),
      ],
      'dahab',
      removedIds: const {'c'},
    );
    expect(hits, ['d', 'a']);
  });
}
