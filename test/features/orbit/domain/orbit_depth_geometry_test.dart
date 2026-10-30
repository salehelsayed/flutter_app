import '../support/depth_fixtures.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/orbit_depth_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the queue holds only friends with a live thought, in chat order', () {
    final items = <OrbitItem>[
      for (var i = 0; i < 6; i++) OrbitFriendItem(depthFriend(i)),
    ];
    items.insert(
      2,
      OrbitGroupItem(
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
      ),
    );
    final queue = orbitDepthQueue(items, {
      'peer-4': depthThought(4),
      'peer-1': depthThought(1),
      'peer-3': depthThought(3, expiry: depthNow),
      'peer-5': depthThought(5),
    }, depthNow);
    expect(queue.map((seat) => (seat.friend.peerId, seat.thought.id)), [
      ('peer-1', 'post-1'),
      ('peer-4', 'post-4'),
      ('peer-5', 'post-5'),
    ]);
  });

  test('at rest: one 72 px friend in the center and four ring faces sized '
      'only by perspective; the back seat is empty', () {
    final faces = orbitCenterFaces(count: 12, pos: 0, scale: 1);
    expect(faces, hasLength(5));
    expect(faces.map((face) => face.opacity).toSet(), {1.0});
    final center = faces.last;
    expect(center.index, 0);
    expect(center.lift, 1);
    expect(center.diameter, 72);
    expect(center.offset, Offset.zero);
    expect(center.darken, 0);
    final ring = {
      for (final face in faces.take(4))
        face.index: (
          face.diameter.toStringAsFixed(1),
          face.darken.toStringAsFixed(3),
          face.lift,
        ),
    };
    expect(ring, {
      1: ('34.7', '0.075', 0.0),
      11: ('34.7', '0.075', 0.0),
      2: ('29.7', '0.225', 0.0),
      10: ('29.7', '0.225', 0.0),
    });
  });

  test('the ring is 228 px wide and its back edge sits 54 px above center', () {
    final (side, near) = projectOrbitCenter(
      0,
      orbitCenterRadius,
      orbitCenterTilt,
    );
    expect((2 * side.dx).toStringAsFixed(0), '228');
    expect(near, 1);
    final extent = orbitCenterRingExtent(1, orbitCenterTilt);
    expect(extent.far.toStringAsFixed(1), '54.2');
    expect(extent.near.toStringAsFixed(1), '82.1');
  });

  test('a face fades only within 0.35 rad of the far back and comes back '
      'there as the next friend in line', () {
    Map<int, String> at(double pos) => {
      for (final face in orbitCenterFaces(count: 12, pos: pos, scale: 1))
        if (face.opacity < 1) face.index: face.opacity.toStringAsFixed(2),
    };
    // One seat is 60 degrees; the fade spans 0.35 rad (about a third of it).
    expect(at(0), {});
    expect(at(.2), {3: '0.60'});
    expect(at(.5), {});
    expect(at(.8), {10: '0.60'});
    expect(at(1), {});
    expect(at(1.2), {4: '0.60'});
    expect(
      orbitCenterFaces(count: 12, pos: 1, scale: 1).map((face) => face.index),
      isNot(anyOf(contains(4), contains(10))),
    );
  });

  test('six friends: the back seat is empty at rest; fewer friends all stay '
      'visible', () {
    expect(orbitCenterFaces(count: 6, pos: 0, scale: 1), hasLength(5));
    final four = orbitCenterFaces(count: 4, pos: 0, scale: 1);
    expect(four, hasLength(4));
    expect(four.map((face) => face.opacity).toSet(), {1.0});
  });

  test('a turn hands the center from one friend to the next, and only one '
      'face is ever more than half lifted', () {
    for (var pos = 0.0; pos <= 1.0001; pos += .05) {
      final lifted = orbitCenterFaces(
        count: 12,
        pos: pos,
        scale: 1,
      ).where((face) => face.lift > .5).map((face) => face.index).toList();
      expect(lifted.length, lessThanOrEqualTo(1), reason: 'pos $pos');
    }
    int top(double pos) => orbitCenterFaces(
      count: 12,
      pos: pos,
      scale: 1,
    ).reduce((a, b) => b.lift > a.lift ? b : a).index;
    expect([top(0), top(.4), top(.6), top(1)], [0, 0, 1, 1]);
    expect(orbitCenterFaces(count: 12, pos: 1, scale: 1).last.lift, 1);
  });

  test('the next friend waits on the left, or on the right when asked', () {
    OrbitCenterFace next({required bool nextOnRight}) => orbitCenterFaces(
      count: 12,
      pos: 0,
      scale: 1,
      nextOnRight: nextOnRight,
    ).firstWhere((face) => face.index == 1);
    expect(next(nextOnRight: false).offset.dx, lessThan(0));
    expect(next(nextOnRight: true).offset.dx, greaterThan(0));
    expect(
      next(nextOnRight: true).offset.dy,
      next(nextOnRight: false).offset.dy,
    );
  });

  test('fewer than six friends share the ring evenly and all stay opaque', () {
    final faces = orbitCenterFaces(count: 4, pos: 0, scale: 1);
    expect(faces.map((face) => face.opacity).toSet(), {1.0});
    final back = faces.firstWhere((face) => face.index == 2);
    expect(back.offset.dx.abs(), lessThan(1e-9));
    expect(back.offset.dy, lessThan(0));
    expect(orbitCenterFaces(count: 1, pos: 0, scale: 1).single.diameter, 72);
    expect(orbitCenterFaces(count: 0, pos: 0, scale: 1), isEmpty);
  });

  test('every length scales with the screen width', () {
    final small = orbitCenterFaces(count: 12, pos: 0, scale: 360 / 390).last;
    expect(small.diameter.toStringAsFixed(2), '66.46');
  });
}
