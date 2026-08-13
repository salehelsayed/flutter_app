import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';

GroupModel _group({DateTime? lastAt, String? lastId}) => GroupModel(
  id: 'group-1',
  name: 'Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  createdAt: DateTime.utc(2026),
  createdBy: 'peer-admin',
  myRole: GroupRole.admin,
  lastMembershipEventAt: lastAt,
  lastMembershipEventId: lastId,
);

void main() {
  test(
    'Plan 363 audit shared authority phase serializes and rejects same-group reentry',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final order = <String>[];
      final first = runGroupAuthorityPhase<void>(
        groupId: 'group-authority-phase',
        action: () async {
          order.add('first-enter');
          await expectLater(
            runGroupAuthorityPhase<void>(
              groupId: 'group-authority-phase',
              action: () async {},
            ),
            throwsA(isA<StateError>()),
          );
          entered.complete();
          await release.future;
          order.add('first-exit');
        },
      );
      await entered.future;
      final second = runGroupAuthorityPhase<void>(
        groupId: 'group-authority-phase',
        action: () async => order.add('second'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(order, <String>['first-enter']);
      release.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(order, <String>['first-enter', 'first-exit', 'second']);
    },
  );

  group('nextMembershipEventAt', () {
    final last = DateTime.utc(2026, 6, 16, 12);

    test('returns now when now is strictly after last', () {
      final now = last.add(const Duration(seconds: 5));
      expect(nextMembershipEventAt(last, now: now), now);
    });

    test('returns last + 1us when now equals last', () {
      expect(
        nextMembershipEventAt(last, now: last),
        last.add(const Duration(microseconds: 1)),
      );
    });

    test('returns last + 1us when now is before last (clock skew)', () {
      final now = last.subtract(const Duration(seconds: 5));
      expect(
        nextMembershipEventAt(last, now: now),
        last.add(const Duration(microseconds: 1)),
      );
    });

    test('returns now when last is null', () {
      final now = DateTime.utc(2026, 6, 16, 12, 30);
      expect(nextMembershipEventAt(null, now: now), now);
    });

    test('normalizes a non-UTC now to UTC', () {
      final localNow = DateTime(2026, 6, 16, 12);
      final result = nextMembershipEventAt(null, now: localNow);
      expect(result.isUtc, isTrue);
      expect(result, localNow.toUtc());
    });

    test('normalizes a non-UTC last when bumping', () {
      final localLast = DateTime(2030);
      final now = DateTime.utc(2026);
      final result = nextMembershipEventAt(localLast, now: now);
      expect(result.isUtc, isTrue);
      expect(result, localLast.toUtc().add(const Duration(microseconds: 1)));
    });
  });

  group('isStaleGroupMembershipEvent eventId tuple tie-break', () {
    final instant = DateTime.utc(2026, 6, 16, 12);

    test('strictly newer eventAt is never stale regardless of eventId', () {
      expect(
        isStaleGroupMembershipEvent(
          eventAt: instant.add(const Duration(seconds: 1)),
          lastMembershipEventAt: instant,
          eventId: 'a',
          lastEventId: 'z',
        ),
        isFalse,
      );
    });

    test('strictly older eventAt is always stale regardless of eventId', () {
      expect(
        isStaleGroupMembershipEvent(
          eventAt: instant.subtract(const Duration(seconds: 1)),
          lastMembershipEventAt: instant,
          eventId: 'z',
          lastEventId: 'a',
        ),
        isTrue,
      );
    });

    test('equal instant with higher incoming eventId is not stale', () {
      expect(
        isStaleGroupMembershipEvent(
          eventAt: instant,
          lastMembershipEventAt: instant,
          eventId: 'b',
          lastEventId: 'a',
        ),
        isFalse,
      );
    });

    test('equal instant with lower incoming eventId is stale', () {
      expect(
        isStaleGroupMembershipEvent(
          eventAt: instant,
          lastMembershipEventAt: instant,
          eventId: 'a',
          lastEventId: 'b',
        ),
        isTrue,
      );
    });

    test('equal instant with equal eventId is stale (idempotent replay)', () {
      expect(
        isStaleGroupMembershipEvent(
          eventAt: instant,
          lastMembershipEventAt: instant,
          eventId: 'a',
          lastEventId: 'a',
        ),
        isTrue,
      );
    });

    test(
      'equal instant with absent incoming eventId falls back to strict stale',
      () {
        expect(
          isStaleGroupMembershipEvent(
            eventAt: instant,
            lastMembershipEventAt: instant,
            lastEventId: 'a',
          ),
          isTrue,
        );
      },
    );

    test(
      'equal instant with absent stored eventId falls back to strict stale',
      () {
        expect(
          isStaleGroupMembershipEvent(
            eventAt: instant,
            lastMembershipEventAt: instant,
            eventId: 'a',
          ),
          isTrue,
        );
      },
    );

    test('comparator is symmetric (winner on one side loses on the other)', () {
      final incomingWins = isStaleGroupMembershipEvent(
        eventAt: instant,
        lastMembershipEventAt: instant,
        eventId: 'b',
        lastEventId: 'a',
      );
      final storedWins = isStaleGroupMembershipEvent(
        eventAt: instant,
        lastMembershipEventAt: instant,
        eventId: 'a',
        lastEventId: 'b',
      );
      expect(incomingWins, isFalse);
      expect(storedWins, isTrue);
    });
  });

  group('recordGroupMembershipEventWatermark eventId persistence', () {
    final instant = DateTime.utc(2026, 6, 16, 12);
    late InMemoryGroupRepository repo;

    setUp(() => repo = InMemoryGroupRepository());

    test(
      'persists both eventAt and eventId on a strictly-newer event',
      () async {
        await repo.saveGroup(_group(lastAt: instant, lastId: 'a'));
        await recordGroupMembershipEventWatermark(
          groupRepo: repo,
          groupId: 'group-1',
          eventAt: instant.add(const Duration(seconds: 1)),
          eventId: 'b',
        );
        final group = await repo.getGroup('group-1');
        expect(
          group!.lastMembershipEventAt,
          instant.add(const Duration(seconds: 1)),
        );
        expect(group.lastMembershipEventId, 'b');
      },
    );

    test('advances on equal instant when the new id out-tiebreaks', () async {
      await repo.saveGroup(_group(lastAt: instant, lastId: 'a'));
      await recordGroupMembershipEventWatermark(
        groupRepo: repo,
        groupId: 'group-1',
        eventAt: instant,
        eventId: 'b',
      );
      final group = await repo.getGroup('group-1');
      expect(group!.lastMembershipEventId, 'b');
    });

    test('no-op on equal instant when the new id loses or ties', () async {
      await repo.saveGroup(_group(lastAt: instant, lastId: 'b'));
      await recordGroupMembershipEventWatermark(
        groupRepo: repo,
        groupId: 'group-1',
        eventAt: instant,
        eventId: 'a',
      );
      expect((await repo.getGroup('group-1'))!.lastMembershipEventId, 'b');
    });

    test('no-op on equal instant when the new id is absent', () async {
      await repo.saveGroup(_group(lastAt: instant, lastId: 'b'));
      await recordGroupMembershipEventWatermark(
        groupRepo: repo,
        groupId: 'group-1',
        eventAt: instant,
      );
      expect((await repo.getGroup('group-1'))!.lastMembershipEventId, 'b');
    });

    test('no-op on a strictly-older event', () async {
      await repo.saveGroup(_group(lastAt: instant, lastId: 'b'));
      await recordGroupMembershipEventWatermark(
        groupRepo: repo,
        groupId: 'group-1',
        eventAt: instant.subtract(const Duration(seconds: 1)),
        eventId: 'z',
      );
      final group = await repo.getGroup('group-1');
      expect(group!.lastMembershipEventAt, instant);
      expect(group.lastMembershipEventId, 'b');
    });
  });
}
