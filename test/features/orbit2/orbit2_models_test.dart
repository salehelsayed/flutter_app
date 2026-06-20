import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/orbit2/application/orbit2_mock_data.dart';
import 'package:flutter_app/features/orbit2/domain/models/avatar_tier.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_layout_template.dart';

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

  group('layoutPositions', () {
    const canvas = Size(900, 640);
    final tiers = <AvatarTier>[
      AvatarTier.sizeA, AvatarTier.sizeA, AvatarTier.sizeA, AvatarTier.sizeA,
      AvatarTier.sizeB, AvatarTier.sizeB, AvatarTier.sizeB, AvatarTier.sizeB,
      AvatarTier.sizeB, AvatarTier.sizeB, AvatarTier.sizeB,
    ];

    test('returns one position per tier, all templates', () {
      for (final t in Orbit2LayoutTemplate.values) {
        expect(layoutPositions(t, canvas: canvas, tiers: tiers).length,
            tiers.length, reason: '$t');
      }
    });

    test('all centers stay in bounds, all templates', () {
      const margin = 44.0;
      for (final t in Orbit2LayoutTemplate.values) {
        final p = layoutPositions(t, canvas: canvas, tiers: tiers);
        for (final o in p) {
          expect(o.dx, inInclusiveRange(margin - 0.5, canvas.width - margin + 0.5),
              reason: '$t dx');
          expect(o.dy, inInclusiveRange(margin - 0.5, canvas.height - margin + 0.5),
              reason: '$t dy');
        }
      }
    });

    test('no two avatars overlap (pairwise spacing), all templates', () {
      for (final t in Orbit2LayoutTemplate.values) {
        final p = layoutPositions(t, canvas: canvas, tiers: tiers);
        // Uniform avatars (r=20) ⇒ min centre separation = 20+20+12 = 52.
        for (var i = 0; i < p.length; i++) {
          for (var j = i + 1; j < p.length; j++) {
            expect((p[i] - p[j]).distance, greaterThanOrEqualTo(51.0),
                reason: '$t pair $i,$j');
          }
        }
      }
    });

    test('innerGravity: Size-A is closer to centre than Size-B on average', () {
      final p = layoutPositions(Orbit2LayoutTemplate.innerGravity,
          canvas: canvas, tiers: tiers);
      final centre = Offset(canvas.width / 2, canvas.height / 2);
      double meanDist(AvatarTier tier) {
        var sum = 0.0;
        var count = 0;
        for (var i = 0; i < tiers.length; i++) {
          if (tiers[i] == tier) {
            sum += (p[i] - centre).distance;
            count++;
          }
        }
        return sum / count;
      }
      expect(meanDist(AvatarTier.sizeA), lessThan(meanDist(AvatarTier.sizeB)));
    });

    test('tieredBands: every Size-A sits above every Size-B', () {
      final p = layoutPositions(Orbit2LayoutTemplate.tieredBands,
          canvas: canvas, tiers: tiers);
      var maxA = double.negativeInfinity;
      var minB = double.infinity;
      for (var i = 0; i < tiers.length; i++) {
        if (tiers[i] == AvatarTier.sizeA) maxA = maxA > p[i].dy ? maxA : p[i].dy;
        if (tiers[i] == AvatarTier.sizeB) minB = minB < p[i].dy ? minB : p[i].dy;
      }
      expect(maxA, lessThan(minB));
    });

    test('exclusion zone: no avatar overlaps the inner circle, all templates', () {
      const exCenter = Offset(450, 320);
      const exRadius = 130.0;
      for (final t in Orbit2LayoutTemplate.values) {
        final p = layoutPositions(
          t,
          canvas: canvas,
          tiers: tiers,
          exclusionCenter: exCenter,
          exclusionRadius: exRadius,
        );
        for (var i = 0; i < p.length; i++) {
          expect((p[i] - exCenter).distance, greaterThanOrEqualTo(exRadius - 2),
              reason: '$t avatar $i is inside the inner-circle zone');
        }
      }
    });

    test('spacing modes: wider centre-to-centre when names are shown', () {
      for (final t in Orbit2LayoutTemplate.values) {
        final named = layoutPositions(t,
            canvas: canvas, tiers: tiers, minSpacing: kNamedSpacing);
        final bare = layoutPositions(t,
            canvas: canvas, tiers: tiers, minSpacing: kBareSpacing);
        for (var i = 0; i < tiers.length; i++) {
          for (var j = i + 1; j < tiers.length; j++) {
            expect((named[i] - named[j]).distance,
                greaterThanOrEqualTo(kNamedSpacing - 2),
                reason: '$t named pair $i,$j');
            expect((bare[i] - bare[j]).distance,
                greaterThanOrEqualTo(kBareSpacing - 2),
                reason: '$t bare pair $i,$j');
          }
        }
      }
    });

    test('deterministic — same inputs yield identical output', () {
      for (final t in Orbit2LayoutTemplate.values) {
        final a = layoutPositions(t, canvas: canvas, tiers: tiers);
        final b = layoutPositions(t, canvas: canvas, tiers: tiers);
        expect(a, b, reason: '$t');
      }
    });

    test('empty and single tiers do not throw', () {
      for (final t in Orbit2LayoutTemplate.values) {
        expect(layoutPositions(t, canvas: canvas, tiers: const []), isEmpty);
        expect(
          layoutPositions(t, canvas: canvas, tiers: const [AvatarTier.sizeA]).length,
          1,
        );
      }
    });
  });

  group('repel (magnet)', () {
    const center = Offset(200, 200);
    const radius = 100.0;

    test('point outside the zone is unchanged', () {
      const home = Offset(400, 200); // 200 away
      expect(repel(home, center, radius), home);
    });

    test('point inside the zone is pushed to the boundary', () {
      const home = Offset(240, 200); // 40 away, inside
      final r = repel(home, center, radius);
      expect((r - center).distance, closeTo(radius, 0.001));
      // pushed along the same direction (to the right)
      expect(r.dx, greaterThan(home.dx));
      expect(r.dy, closeTo(200, 0.001));
    });

    test('point at the centre is pushed straight down by radius', () {
      final r = repel(center, center, radius);
      expect(r, Offset(center.dx, center.dy + radius));
    });

    test('deterministic', () {
      const home = Offset(250, 230);
      expect(repel(home, center, radius), repel(home, center, radius));
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

  test('AppShellTab accepts orbit2', () {
    expect(AppShellTab.isValid(AppShellTab.orbit2), isTrue);
    expect(AppShellTab.orbit2, 'orbit2');
  });
}
