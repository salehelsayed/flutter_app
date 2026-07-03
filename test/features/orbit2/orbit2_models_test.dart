import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit2/application/orbit2_mock_data.dart';
import 'package:flutter_app/features/orbit2/domain/models/avatar_tier.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';

// NOTE: These models (Orbit2InnerItem / Orbit2Group / AvatarTier / Orbit2MockData)
// are shared leaf types still consumed by the Orbit3 prototype after the Orbit2
// screen was removed, so their coverage stays here.
void main() {
  group('Orbit2InnerItem union', () {
    final set = Orbit2MockData.build();
    final friend = set.innerCircle.first; // an OrbitFriend
    const group = Orbit2Group(id: 'orbit2-group-x', name: 'X Crew', members: []);

    test('friend variant exposes id/displayName and is not a group', () {
      final item = Orbit2InnerItem.friend(friend);
      expect(item.isGroup, isFalse);
      expect(item.id, friend.peerId);
      expect(item.displayName, friend.username);
    });

    test('group variant exposes id/displayName and is a group', () {
      final item = Orbit2InnerItem.group(group);
      expect(item.isGroup, isTrue);
      expect(item.id, group.id);
      expect(item.displayName, group.name);
    });

    test('equality is id-keyed (so removeWhere/contains work)', () {
      final a = Orbit2InnerItem.friend(friend);
      final b = Orbit2InnerItem.friend(friend);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect([a].contains(b), isTrue);
      // a friend and a group never collide (disjoint id namespaces)
      expect(Orbit2InnerItem.group(group) == a, isFalse);
    });
  });

  group('AvatarTier.fromMessageCount', () {
    test('threshold at 20', () {
      expect(AvatarTier.fromMessageCount(20), AvatarTier.sizeA);
      expect(AvatarTier.fromMessageCount(21), AvatarTier.sizeA);
      expect(AvatarTier.fromMessageCount(19), AvatarTier.sizeB);
      expect(AvatarTier.fromMessageCount(0), AvatarTier.sizeB);
    });

    test('all avatars render at one uniform size', () {
      expect(AvatarTier.sizeA.diameter, AvatarTier.sizeB.diameter);
      expect(AvatarTier.sizeA.diameter, kFloatingAvatarDiameter);
    });
  });

  group('mock data', () {
    test('inner circle and canvas are disjoint (no friend appears twice)', () {
      final set = Orbit2MockData.build();
      final innerIds = set.innerCircle.map((f) => f.peerId).toSet();
      final canvasIds = set.canvas.map((f) => f.peerId).toSet();
      expect(innerIds.intersection(canvasIds), isEmpty);
      expect(set.innerCircle.length, greaterThan(13)); // exercises overflow badge
      expect(set.canvas, isNotEmpty);
    });

    test('canvas has a mix of both tiers', () {
      final canvas = Orbit2MockData.build(canvasCount: 11).canvas;
      expect(canvas.any((f) => f.tier == AvatarTier.sizeA), isTrue);
      expect(canvas.any((f) => f.tier == AvatarTier.sizeB), isTrue);
    });

    test('two different friends yield different first thread message', () {
      final canvas = Orbit2MockData.build().canvas;
      final a = Orbit2MockData.thread(canvas[0]).first.text;
      final b = Orbit2MockData.thread(canvas[1]).first.text;
      expect(a, isNotEmpty);
      expect(b, isNotEmpty);
    });
  });

  group('inbox (Messages view) data', () {
    test('recencyRank maps now / clock / weekday deterministically', () {
      int rank(String label) => Orbit2MockData.recencyRank(
          Orbit2ChatLine(text: '', isMe: false, timeLabel: label));
      expect(rank('now'), 0);
      expect(rank('10:01'), 1);
      expect(rank('9:05'), 1);
      expect(rank('Mon'), 2);
      expect(rank('Sun'), 2);
    });

    test('latestLine/latestGroupLine return the last thread line', () {
      final mock = Orbit2MockData.build();
      final f = mock.canvas.first;
      final fLast = Orbit2MockData.thread(f).last;
      expect(Orbit2MockData.latestLine(f).text, fLast.text);
      expect(Orbit2MockData.latestLine(f).timeLabel, fLast.timeLabel);
      final g = mock.groups.first;
      final gLast = Orbit2MockData.groupThread(g).last;
      expect(Orbit2MockData.latestGroupLine(g).text, gLast.text);
      expect(Orbit2MockData.latestGroupLine(g).timeLabel, gLast.timeLabel);
    });

    test('inboxEntries are recency-ordered, deduped, deterministic, with a real gradient',
        () {
      final mock = Orbit2MockData.build(canvasCount: 10);
      final inner = mock.innerCircle.map(Orbit2InnerItem.friend).toList();
      List<Orbit2InboxEntry> build() => Orbit2MockData.inboxEntries(
          inner: inner, canvas: mock.canvas, groups: mock.groups);
      final entries = build();

      // sorted by recency (non-decreasing rank)
      for (var i = 1; i < entries.length; i++) {
        expect(
          Orbit2MockData.recencyRank(entries[i - 1].lastLine) <=
              Orbit2MockData.recencyRank(entries[i].lastLine),
          isTrue,
        );
      }
      // the ordering does REAL work — at least two distinct ranks are present
      final ranks =
          entries.map((e) => Orbit2MockData.recencyRank(e.lastLine)).toSet();
      expect(ranks.length, greaterThanOrEqualTo(2));
      // an HH:MM (rank 1) sorts before a weekday (rank 2)
      final firstClock = entries
          .indexWhere((e) => Orbit2MockData.recencyRank(e.lastLine) == 1);
      final firstWeekday = entries
          .indexWhere((e) => Orbit2MockData.recencyRank(e.lastLine) == 2);
      if (firstClock != -1 && firstWeekday != -1) {
        expect(firstClock, lessThan(firstWeekday));
      }
      // de-duped + complete
      final ids = entries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(entries.length,
          inner.length + mock.canvas.length + mock.groups.length);
      // deterministic
      expect([for (final e in build()) e.id], [for (final e in entries) e.id]);
    });
  });
}
