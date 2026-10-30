import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/application/inner_circle_items.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';

// 197 — mergeInnerCircleItems merges active friends + active groups into the
// single received-message ordering the inner-circle rings render.

OrbitFriend _friend(
  String id, {
  required DateTime lastMessageAt,
  bool isBlocked = false,
}) {
  return OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-$id',
      publicKey: 'pk-$id',
      rendezvous: '/ip4/127.0.0.1/tcp/4001/p2p/$id',
      username: 'friend-$id',
      signature: 'sig-$id',
      scannedAt: '2024-01-01T00:00:00Z',
      isBlocked: isBlocked,
    ),
    messageCount: 1,
    // Same ISO-8601 UTC format the group side emits, so the two sortKeys are
    // lexically comparable (the shipped all-chats list relies on this too).
    lastMessageTimestamp: lastMessageAt.toUtc().toIso8601String(),
    lastIncomingAt: lastMessageAt,
  );
}

OrbitGroup _group(
  String id, {
  required DateTime lastActivityAt,
  int unreadCount = 0,
}) {
  return OrbitGroup(
    group: GroupModel(
      id: id,
      name: 'group-$id',
      type: GroupType.chat,
      topicName: 'topic-$id',
      createdBy: 'creator',
      myRole: GroupRole.admin,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    unreadCount: unreadCount,
    lastActivityTimestamp: lastActivityAt,
    lastIncomingAt: lastActivityAt,
  );
}

OrbitFriend _emptyFriend(String id, DateTime addedAt) => OrbitFriend(
  contact: ContactModel(
    peerId: 'peer-$id',
    publicKey: 'pk-$id',
    rendezvous: '/dns4/relay/tcp/443',
    username: 'friend-$id',
    signature: 'sig-$id',
    scannedAt: addedAt.toUtc().toIso8601String(),
  ),
  messageCount: 0,
);

OrbitGroup _emptyGroup(String id, DateTime createdAt) => OrbitGroup(
  group: GroupModel(
    id: id,
    name: 'group-$id',
    type: GroupType.chat,
    topicName: 'topic-$id',
    createdBy: 'creator',
    myRole: GroupRole.admin,
    createdAt: createdAt,
  ),
);

List<String> _navItemIds(Iterable<OrbitItem> items) => items
    .map(
      (item) => switch (item) {
        OrbitFriendItem(:final friend) => 'friend:${friend.peerId}',
        OrbitGroupItem(:final group) => 'group:${group.groupId}',
      },
    )
    .toList();

void main() {
  group('NAV-006 deterministic empty circle membership', () {
    test(
      'empty contacts and groups use added or created time across item kinds',
      () {
        final items = mergeInnerCircleItems(
          friends: [
            _emptyFriend('A', DateTime.utc(2026, 1, 1)),
            _emptyFriend('B', DateTime.utc(2026, 2, 1)),
          ],
          groups: [
            _emptyGroup('older', DateTime.utc(2025, 12, 1)),
            _emptyGroup('newer', DateTime.utc(2026, 3, 1)),
          ],
        );

        expect(_navItemIds(items), [
          'group:newer',
          'friend:peer-B',
          'friend:peer-A',
          'group:older',
        ]);
      },
    );

    test('equal fallback times use stable friend/group and identity ties', () {
      final time = DateTime.utc(2026, 1, 1);
      final friends = [_emptyFriend('B', time), _emptyFriend('A', time)];
      final groups = [_emptyGroup('B', time), _emptyGroup('A', time)];

      for (final friendInput in [friends, friends.reversed.toList()]) {
        for (final groupInput in [groups, groups.reversed.toList()]) {
          expect(
            _navItemIds(
              mergeInnerCircleItems(friends: friendInput, groups: groupInput),
            ),
            ['friend:peer-A', 'friend:peer-B', 'group:A', 'group:B'],
          );
        }
      }
    });
  });

  group('mergeInnerCircleItems', () {
    test(
      'interleaves friends and groups by received recency (most-recent first)',
      () {
        // 3 friends + 2 groups with known timestamps. Descending recency:
        // fA(10:00) gX(08:00) fB(06:00) gY(04:00) fC(02:00) — a group sits
        // between friends on both sides.
        final fA = _friend('a', lastMessageAt: DateTime.utc(2026, 7, 2, 10));
        final fB = _friend('b', lastMessageAt: DateTime.utc(2026, 7, 2, 6));
        final fC = _friend('c', lastMessageAt: DateTime.utc(2026, 7, 2, 2));
        final gX = _group('x', lastActivityAt: DateTime.utc(2026, 7, 2, 8));
        final gY = _group('y', lastActivityAt: DateTime.utc(2026, 7, 2, 4));

        // Deliberately unsorted input.
        final items = mergeInnerCircleItems(
          friends: [fB, fC, fA],
          groups: [gY, gX],
        );

        expect(items, hasLength(5));
        expect(items[0], isA<OrbitFriendItem>());
        expect((items[0] as OrbitFriendItem).friend.peerId, 'peer-a');
        expect(items[1], isA<OrbitGroupItem>());
        expect((items[1] as OrbitGroupItem).group.groupId, 'x');
        expect((items[2] as OrbitFriendItem).friend.peerId, 'peer-b');
        expect((items[3] as OrbitGroupItem).group.groupId, 'y');
        expect((items[4] as OrbitFriendItem).friend.peerId, 'peer-c');
      },
    );

    test('excludes blocked friends and keeps active groups', () {
      final active = _friend('a', lastMessageAt: DateTime.utc(2026, 7, 2, 10));
      final blocked = _friend(
        'b',
        lastMessageAt: DateTime.utc(2026, 7, 2, 9),
        isBlocked: true,
      );
      final g = _group('x', lastActivityAt: DateTime.utc(2026, 7, 2, 8));

      final items = mergeInnerCircleItems(
        friends: [active, blocked],
        groups: [g],
      );

      // One unblocked friend + one group.
      expect(items, hasLength(2));
      final friendPeerIds = items
          .whereType<OrbitFriendItem>()
          .map((i) => i.friend.peerId)
          .toList();
      expect(friendPeerIds, ['peer-a']);
      expect(friendPeerIds, isNot(contains('peer-b')));
      expect(items.whereType<OrbitGroupItem>().map((i) => i.group.groupId), [
        'x',
      ]);
    });
  });
}
