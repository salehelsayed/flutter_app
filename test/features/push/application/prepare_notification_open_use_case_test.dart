import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

void main() {
  group('prepareNotificationOpen', () {
    final captured = <Map<String, dynamic>>[];
    setUp(() {
      captured.clear();
      debugSetFlowEventSink(captured.add);
    });
    tearDown(() => debugSetFlowEventSink(null));

    test('conversation target drains 1:1 inbox before navigation', () async {
      var drainOfflineInboxCalls = 0;
      final drainedGroups = <String>[];

      final result = await prepareNotificationOpen(
        routeTarget: const NotificationRouteTarget.conversation('peer-123'),
        drainOfflineInbox: () async {
          drainOfflineInboxCalls += 1;
        },
        drainGroupOfflineInboxForGroup: (groupId) async {
          drainedGroups.add(groupId);
        },
      );

      expect(result.ok, isTrue);
      expect(drainOfflineInboxCalls, 1);
      expect(drainedGroups, isEmpty);
    });

    // TC-04-10: the conversation route fires the optional warmPeer hook for the
    // target peer. Mutation: remove the warm hook from the conversation case →
    // re-red. (On a COLD tap the service-level PS-3 gate makes it a no-op; this
    // only proves the hook fires.)
    test('TC-04-10: conversation route fires warmPeer for the target peer',
        () async {
      final warmed = <String>[];
      final result = await prepareNotificationOpen(
        routeTarget: const NotificationRouteTarget.conversation('peer-123'),
        drainOfflineInbox: () async {},
        drainGroupOfflineInboxForGroup: (_) async {},
        warmPeer: (pid) async {
          warmed.add(pid);
        },
      );
      expect(result.ok, isTrue);
      expect(warmed, ['peer-123']);
    });

    // TC-04-10: warmPeer is NOT fired for group / intros / contactRequest / post
    // routes — warmPeer is 1:1-conversation-only.
    test('TC-04-10: warmPeer is not fired for non-conversation routes',
        () async {
      final warmed = <String>[];
      Future<void> run(NotificationRouteTarget rt) async {
        await prepareNotificationOpen(
          routeTarget: rt,
          drainOfflineInbox: () async {},
          drainGroupOfflineInboxForGroup: (_) async {},
          warmPeer: (pid) async {
            warmed.add(pid);
          },
        );
      }

      await run(const NotificationRouteTarget.group('g1'));
      await run(const NotificationRouteTarget.intros());
      await run(const NotificationRouteTarget.contactRequest('peer-x'));
      await run(const NotificationRouteTarget.post('post-1'));
      expect(warmed, isEmpty);
    });

    test(
      'group target drains the targeted group inbox before navigation',
      () async {
        var drainOfflineInboxCalls = 0;
        final drainedGroups = <String>[];

        final result = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.group('group-123'),
          drainOfflineInbox: () async {
            drainOfflineInboxCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );

        expect(result.ok, isTrue);
        expect(drainOfflineInboxCalls, 0);
        expect(drainedGroups, ['group-123']);
      },
    );

    test(
      'contact requests and intros drain 1:1 inbox while posts do not',
      () async {
        var drainOfflineInboxCalls = 0;
        final drainedGroups = <String>[];

        final contactRequestResult = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.contactRequest('peer-123'),
          drainOfflineInbox: () async {
            drainOfflineInboxCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
        final introsResult = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.intros(),
          drainOfflineInbox: () async {
            drainOfflineInboxCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
        final postResult = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.post('post-123'),
          drainOfflineInbox: () async {
            drainOfflineInboxCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );

        expect(contactRequestResult.ok, isTrue);
        expect(introsResult.ok, isTrue);
        expect(postResult.ok, isTrue);
        expect(drainOfflineInboxCalls, 2);
        expect(drainedGroups, isEmpty);
      },
    );

    test(
      'preparation errors are surfaced as explicit failure results',
      () async {
        final result = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.group('group-123'),
          drainOfflineInbox: () async {},
          drainGroupOfflineInboxForGroup: (_) async {
            throw StateError('group catch-up failed');
          },
        );

        expect(result.ok, isFalse);
        expect(result.error, contains('group catch-up failed'));
      },
    );

    // TC-01 (145): the conversation drain must be fire-and-forget — routing the
    // user to the conversation screen must not block on the relay round-trip
    // (the screen self-heals via its own notif-tap drain). prepareNotificationOpen
    // must therefore return `ok` while the drain future is still pending.
    test(
      'conversation drain is fire-and-forget — prepareNotificationOpen returns '
      'before the drain completes',
      () async {
        final neverCompletes = Completer<void>();
        var drainCount = 0;

        final result = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.conversation('peer-123'),
          drainOfflineInbox: () {
            drainCount += 1;
            return neverCompletes.future;
          },
          drainGroupOfflineInboxForGroup: (_) async {},
        ).timeout(const Duration(seconds: 5));

        expect(result.ok, isTrue);
        expect(drainCount, 1, reason: 'drain was kicked off exactly once');
        expect(
          neverCompletes.isCompleted,
          isFalse,
          reason: 'returned without awaiting the drain',
        );

        // Clean up the dangling drain future without completing it through the
        // (unawaited) production path — completing the Completer is enough.
        neverCompletes.complete();
        await Future<void>.delayed(Duration.zero);
      },
    );

    // TC-02 (145): a fire-and-forget conversation drain that throws must not
    // surface as a failed preparation result, and must be logged via a distinct
    // NOTIFICATION_OPEN_CONVERSATION_DRAIN_ERROR event (NOT the awaited-path
    // NOTIFICATION_OPEN_PREPARATION_ERROR). Covers the synchronous-throw case,
    // which a bare `drainOfflineInbox().catchError(...)` would let escape.
    test(
      'conversation drain that throws does not propagate and is logged',
      () async {
        final result = await prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.conversation('peer-123'),
          // Synchronous throw — the hard case the fire-and-forget wrapper must
          // still catch.
          drainOfflineInbox: () => throw StateError('drain boom'),
          drainGroupOfflineInboxForGroup: (_) async {},
        );

        expect(result.ok, isTrue, reason: 'a drain failure must not fail open');

        // The error is reported asynchronously by the unawaited drain — let the
        // microtask/timer queue drain so the catchError handler runs.
        await Future<void>.delayed(Duration.zero);

        final events = captured.map((e) => e['event']).toList();
        expect(events, contains('NOTIFICATION_OPEN_CONVERSATION_DRAIN_ERROR'));
        expect(
          events,
          isNot(contains('NOTIFICATION_OPEN_PREPARATION_ERROR')),
          reason: 'the awaited-path error event must not fire for conversation',
        );
      },
    );

    // TC-03 (145): scope guard / over-broaden lock — contactRequest and intros
    // drains stay AWAITED. With a never-completing drain, those calls must NOT
    // complete while the drain is pending.
    test(
      'contactRequest and intros drains stay awaited (scope guard / INV-1)',
      () async {
        final gate = Completer<void>();

        var contactRequestCompleted = false;
        var introsCompleted = false;

        final contactRequestFuture = prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.contactRequest('peer-1'),
          drainOfflineInbox: () => gate.future,
          drainGroupOfflineInboxForGroup: (_) async {},
        )..then((_) => contactRequestCompleted = true);
        final introsFuture = prepareNotificationOpen(
          routeTarget: const NotificationRouteTarget.intros(),
          drainOfflineInbox: () => gate.future,
          drainGroupOfflineInboxForGroup: (_) async {},
        )..then((_) => introsCompleted = true);

        await Future<void>.delayed(Duration.zero);

        expect(
          contactRequestCompleted,
          isFalse,
          reason: 'contactRequest must still be awaiting the drain',
        );
        expect(
          introsCompleted,
          isFalse,
          reason: 'intros must still be awaiting the drain',
        );

        // Release the gate so both awaited calls finish (clean teardown).
        gate.complete();
        await Future.wait([contactRequestFuture, introsFuture]);
        expect(contactRequestCompleted, isTrue);
        expect(introsCompleted, isTrue);
      },
    );
  });
}
