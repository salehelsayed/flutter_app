import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/application/orbit_find_matches.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart'
    show OrbitProvenance;

OrbitItem _friend(String username) => OrbitFriendItem(OrbitFriend(
      contact: ContactModel(
        peerId: 'peer-$username',
        publicKey: 'pk-$username',
        rendezvous: '/ip4/127.0.0.1/tcp/4001',
        username: username,
        signature: 'sig',
        scannedAt: '2024-01-01T00:00:00Z',
      ),
      messageCount: 1,
      lastMessageTimestamp: '2024-01-01T00:00:00Z',
    ));

OrbitItem _group(String name) => OrbitGroupItem(OrbitGroup(
      group: GroupModel(
        id: 'g-$name',
        name: name,
        type: GroupType.chat,
        topicName: 'topic-$name',
        createdBy: 'creator',
        myRole: GroupRole.admin,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      lastActivityTimestamp: DateTime.utc(2026, 7, 2),
    ));

const _g = OrbitGeometryPrefs.defaults;

void main() {
  group('computeOrbitFind (198 F4)', () {
    // TC-198-40 core matching
    test('case-insensitive substring lights every match', () {
      final items = [_friend('Alice'), _friend('Bob'), _friend('alicia')];
      final r = computeOrbitFind(items: items, query: 'ALI', geometry: _g);
      expect(r.active, isTrue);
      expect(r.litIndices, {0, 2});
    });

    // TC-198-45/48 — empty / whitespace query is not a find state.
    test('trimmed-empty query yields the inactive result', () {
      final items = [_friend('Alice')];
      expect(computeOrbitFind(items: items, query: '', geometry: _g).active,
          isFalse);
      final ws = computeOrbitFind(items: items, query: '   ', geometry: _g);
      expect(ws.active, isFalse);
      expect(ws.litIndices, isEmpty);
      expect(ws.chips, isEmpty);
    });

    // TC-198-44 math — groups are first-class find targets.
    test('groups are included in matches', () {
      final items = [_friend('alpha'), _group('Alpha Team'), _friend('beta')];
      final r = computeOrbitFind(items: items, query: 'alph', geometry: _g);
      expect(r.litIndices, {0, 1});
      // the group chip carries its group item
      final groupChip = r.chips.firstWhere((c) => c.index == 1);
      expect(groupChip.item, isA<OrbitGroupItem>());
    });

    // TC-198-41 math — cap the chips at four, in merged-recency (list) order.
    test('six matches light all but chip only the first four in order', () {
      final items = [
        _friend('match0'),
        _friend('nope'),
        _friend('match1'),
        _friend('match2'),
        _friend('match3'),
        _friend('match4'),
        _friend('match5'),
      ];
      final r = computeOrbitFind(items: items, query: 'match', geometry: _g);
      expect(r.litIndices, {0, 2, 3, 4, 5, 6});
      expect(r.chips.length, kOrbitFindChipCap);
      // chips follow the caller's merged-recency order (indices ascending here)
      expect(r.chips.map((c) => c.index).toList(), [0, 2, 3, 4]);
    });

    // TC-198-46 math — a real query with zero matches is still "active".
    test('zero matches: active, nothing lit, no chips', () {
      final items = [_friend('Alice'), _group('Bravo')];
      final r = computeOrbitFind(items: items, query: 'zzz', geometry: _g);
      expect(r.active, isTrue);
      expect(r.hasMatches, isFalse);
      expect(r.litIndices, isEmpty);
      expect(r.chips, isEmpty);
    });

    // Provenance: ring 1 (<5), ring 2 (5..12), arc 1 (13) at default geometry.
    test('chip provenance reflects ring/arc placement', () {
      final items = [for (var i = 0; i < 14; i++) _friend('friend$i')];

      OrbitProvenance provOf(String query) =>
          computeOrbitFind(items: items, query: query, geometry: _g)
              .chips
              .single
              .provenance;

      expect(provOf('friend0'), const OrbitProvenance.ring(1));
      expect(provOf('friend5'), const OrbitProvenance.ring(2));
      expect(provOf('friend13'), const OrbitProvenance.arc(1));
    });
  });
}
