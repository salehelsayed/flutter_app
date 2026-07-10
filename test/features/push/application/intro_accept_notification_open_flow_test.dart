import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/resolve_introduction_notification_target_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/push/application/intro_accept_notification_open_flow.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

/// TC-09: after the existing notification-open inbox drain, the shared
/// coordinator resolves an anchored introducer accept and opens the recipient
/// (B) conversation — for BOTH the remote-data entry path and the TC-04
/// anchored local-payload entry path — preserving the original tap timestamp
/// and never invoking the Orbit/Intros fallback.
void main() {
  const canonicalAcceptId = 'intro-flow::accept::peer-C';

  late InMemoryIntroductionRepository introRepo;
  late InMemoryContactRepository contactRepo;
  late List<String> events;
  late DateTime? receivedTappedAt;
  late DateTime? notificationTappedAt;

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
    contactRepo = InMemoryContactRepository();
    events = <String>[];
    receivedTappedAt = null;
    notificationTappedAt = DateTime.utc(2026, 7, 10, 12, 0, 0);
  });

  Future<void> drainOfflineInbox() async {
    events.add('drain');
    // The intro and B's contact materialize ONLY during the awaited drain —
    // resolving before this callback fails causally and cannot pass on
    // pre-seeded state.
    await introRepo.saveIntroduction(
      IntroductionModel(
        id: 'intro-flow',
        introducerId: 'own-peer',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        status: IntroductionOverallStatus.mutualAccepted,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    contactRepo.addTestContact(
      ContactModel(
        peerId: 'peer-B',
        publicKey: 'pk-peer-B',
        rendezvous: '/rv/peer-B',
        username: 'Lina',
        signature: 'sig-peer-B',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  Future<void> prepare(NotificationRouteTarget routeTarget) async {
    events.add('prepare');
    // Mirrors prepareNotificationOpen: the Intros route awaits the 1:1 inbox
    // drain before route resolution.
    if (routeTarget.kind == NotificationRouteTargetKind.intros) {
      await drainOfflineInbox();
    }
  }

  Future<void> handleRouteTarget(NotificationRouteTarget routeTarget) async {
    // Mirrors the main.dart _handleNotificationRouteTarget Intros case wiring:
    // snapshot the tap timestamp, then hand the target to the shared
    // coordinator, which resolves and either redirects to the conversation or
    // falls back to Orbit/Intros.
    expect(routeTarget.kind, NotificationRouteTargetKind.intros);
    final tappedAt = notificationTappedAt;
    notificationTappedAt = null;
    await openIntroAcceptNotificationRoute(
      routeTarget: routeTarget,
      notificationTappedAt: tappedAt,
      resolveTarget: (target) async {
        events.add('resolve');
        return resolveIntroductionNotificationTarget(
          routeTarget: target,
          introRepo: introRepo,
          contactRepo: contactRepo,
          loadOwnPeerId: () async => 'own-peer',
        );
      },
      isConversationAlreadyActive: (_) => false,
      openConversation: (contact, openTappedAt) async {
        events.add('conversation:${contact.peerId}');
        receivedTappedAt = openTappedAt;
      },
      openIntros: () async {
        events.add('intros');
      },
    );
  }

  test(
    'remote and local introducer accepts drain then open the recipient conversation',
    () async {
      // Remote-data entry path (cold/background FCM tap).
      final routed = await routeRemoteNotificationOpenWithResult(
        data: const {'type': 'intros', 'message_id': canonicalAcceptId},
        onBeforeRouteTarget: prepare,
        onRouteTarget: handleRouteTarget,
        onMissingRouteTarget: () async {
          fail('anchored intros remote data must produce a route target');
        },
      );

      expect(routed, isTrue);
      expect(events, ['prepare', 'drain', 'resolve', 'conversation:peer-B']);
      expect(events, isNot(contains('intros')));
      expect(receivedTappedAt, DateTime.utc(2026, 7, 10, 12, 0, 0));

      // Warm/local entry path: the TC-04 anchored local payload from the
      // introducer's own mutual-accept notification.
      events.clear();
      receivedTappedAt = null;
      notificationTappedAt = DateTime.utc(2026, 7, 10, 12, 5, 0);
      introRepo = InMemoryIntroductionRepository();
      contactRepo = InMemoryContactRepository();

      await routeNotificationPayload(
        payload: 'intros|message:$canonicalAcceptId',
        onBeforeRouteTarget: prepare,
        onRouteTarget: handleRouteTarget,
      );

      expect(events, ['prepare', 'drain', 'resolve', 'conversation:peer-B']);
      expect(events, isNot(contains('intros')));
      expect(receivedTappedAt, DateTime.utc(2026, 7, 10, 12, 5, 0));
    },
  );

  test(
    'unanchored intros and non-introducer accepts still fall back to the Orbit/Intros route',
    () async {
      await routeRemoteNotificationOpenWithResult(
        data: const {'type': 'intros'},
        onBeforeRouteTarget: prepare,
        onRouteTarget: handleRouteTarget,
        onMissingRouteTarget: () async {
          fail('generic intros remote data must produce a route target');
        },
      );

      expect(events, ['prepare', 'drain', 'resolve', 'intros']);
      expect(events.where((event) => event.startsWith('conversation:')), isEmpty);
    },
  );

  test(
    'already-active recipient conversation suppresses a duplicate push without falling back',
    () async {
      final activeGuardEvents = <String>[];
      await routeRemoteNotificationOpenWithResult(
        data: const {'type': 'intros', 'message_id': canonicalAcceptId},
        onBeforeRouteTarget: prepare,
        onRouteTarget: (routeTarget) async {
          await openIntroAcceptNotificationRoute(
            routeTarget: routeTarget,
            notificationTappedAt: null,
            resolveTarget: (target) => resolveIntroductionNotificationTarget(
              routeTarget: target,
              introRepo: introRepo,
              contactRepo: contactRepo,
              loadOwnPeerId: () async => 'own-peer',
            ),
            isConversationAlreadyActive: (conversationTarget) {
              activeGuardEvents.add('guard:${conversationTarget.peerId}');
              return true;
            },
            openConversation: (contact, _) async {
              activeGuardEvents.add('conversation:${contact.peerId}');
            },
            openIntros: () async {
              activeGuardEvents.add('intros');
            },
          );
        },
        onMissingRouteTarget: () async {},
      );

      expect(activeGuardEvents, ['guard:peer-B']);
    },
  );
}
