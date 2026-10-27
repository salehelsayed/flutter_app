import 'dart:math' as math;
import '../support/depth_fixtures.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/orbit_depth_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'friends with thoughts fill the inner ring side by side, a group never leaves a hole',
    () {
      final items = <OrbitItem>[
        for (var i = 0; i < 16; i++) OrbitFriendItem(depthFriend(i)),
      ];
      items[2] = OrbitGroupItem(
        OrbitGroup(
          group: GroupModel(
            id: 'group',
            name: 'Group',
            type: GroupType.chat,
            topicName: 'topic',
            createdAt: depthNow,
            createdBy: 'local',
            myRole: GroupRole.admin,
          ),
        ),
      );
      final layout = OrbitDepthLayout.fromItems(items, {
        for (var i = 0; i < 16; i++) 'peer-$i': depthThought(i),
      }, depthNow);
      expect(
        layout
            .inLayer(OrbitDepthLayer.inner)
            .map((seat) => (seat.placement.index, seat.friend.peerId)),
        [
          (0, 'peer-0'),
          (1, 'peer-1'),
          (2, 'peer-3'),
          (3, 'peer-4'),
          (4, 'peer-5'),
        ],
      );
      expect(
        layout.inLayer(OrbitDepthLayer.outer).map((seat) => seat.friend.peerId),
        [for (var i = 6; i <= 13; i++) 'peer-$i'],
      );
      expect(
        layout.seats.any((seat) => seat.friend.peerId == 'peer-14'),
        isFalse,
      );
      expect(layout.overflow!.overflowCount, 3);
      expect(
        layout.seats[1].placement.angle,
        closeTo(-math.pi / 2 + 2 * math.pi / 5, 1e-9),
      );
    },
  );
  test('partial rings and RTL preserve actual source geometry', () {
    final items = [for (var i = 0; i < 3; i++) OrbitFriendItem(depthFriend(i))];
    final ltr = OrbitDepthLayout.fromItems(items, {}, depthNow);
    final rtl = OrbitDepthLayout.fromItems(items, {}, depthNow, mirrored: true);
    expect(ltr.seats[1].placement.angle, closeTo(math.pi / 6, 1e-9));
    expect(
      rtl.seats[1].placement.dx,
      closeTo(-ltr.seats[1].placement.dx, 1e-9),
    );
    expect(rtl.seats[1].placement.dy, closeTo(ltr.seats[1].placement.dy, 1e-9));
  });
  test(
    'live thoughts sit next to each other ahead of empty seats; arrival chooses first unseen',
    () {
      final layout = OrbitDepthLayout.fromItems(
        [for (var i = 0; i < 5; i++) OrbitFriendItem(depthFriend(i))],
        {
          'peer-0': depthThought(0, read: true),
          'peer-1': depthThought(1, expiry: depthNow),
          'peer-3': depthThought(3),
        },
        depthNow,
      );
      expect(layout.seats.map((seat) => seat.friend.peerId), [
        'peer-0',
        'peer-3',
        'peer-1',
        'peer-2',
        'peer-4',
      ]);
      expect(layout.seats.map((seat) => seat.thought?.id), [
        'post-0',
        'post-3',
        null,
        null,
        null,
      ]);
      expect(orbitDepthArrival(layout.seats, 0)!.friend.peerId, 'peer-3');
      expect(
        orbitDepthNearest(
          layout.seats,
          orbitDepthRotationFor(layout.seats[0], 0),
        )!.friend.peerId,
        'peer-0',
      );
    },
  );
  test(
    'reseating keeps placements, refreshes thoughts and drops a friend who left',
    () {
      final seated = OrbitDepthLayout.fromItems(
        [for (var i = 0; i < 5; i++) OrbitFriendItem(depthFriend(i))],
        {'peer-1': depthThought(1)},
        depthNow,
      );
      final later = seated.reseated(
        {
          for (final i in [4, 3, 1, 0]) 'peer-$i': depthFriend(i),
        },
        {'peer-3': depthThought(3)},
        depthNow,
      );
      // Seated with peer-1's thought first; a reseat during a gesture keeps
      // every face where it is.
      expect(later.seats.map((seat) => seat.friend.peerId), [
        'peer-1',
        'peer-0',
        'peer-3',
        'peer-4',
      ]);
      expect(later.seats.map((seat) => seat.placement.index), [0, 1, 3, 4]);
      expect(later.seats.map((seat) => seat.thought?.id), [
        null,
        null,
        'post-3',
        null,
      ]);
    },
  );
  test('one camera makes the front face and ring larger together', () {
    final (front, frontScale) = projectOrbitDepth(
      math.pi / 2,
      146,
      67 * math.pi / 180,
    );
    final (back, backScale) = projectOrbitDepth(
      -math.pi / 2,
      146,
      67 * math.pi / 180,
    );
    expect(frontScale, greaterThan(backScale));
    expect(
      front.dy.abs() / back.dy.abs(),
      closeTo(frontScale / backScale, 1e-9),
    );
  });
}
