import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-wiring lock for Plan 252 (TC-09b).
///
/// The Intros case in `_handleNotificationRouteTarget`
/// (`lib/app/application_root.dart`) must
/// invoke the shared intro-accept open coordinator and must no longer
/// unconditionally `await _openIntroOrbitRoute(...)`. The coordinator and
/// resolver are host-proven in isolation, but the app root's private dispatcher
/// cannot be invoked by the exported Orbit widget test, so a correct
/// coordinator with a reverted app-root branch would otherwise stay GREEN
/// while production silently keeps routing every acceptance to Orbit/Intros.
///
/// Token-level existence lock precedent: Report 139 E2
/// (`app_root_conversation_route_dedup_wiring_test.dart`).
void main() {
  test('application-root intros branch wires the accept open coordinator', () {
    final source = File('lib/app/application_root.dart').readAsStringSync();

    // Scope to the Intros case body only (up to the group case that follows
    // it), so the group branch's pending-invite `_openIntroOrbitRoute`
    // fallback cannot create a false match.
    final introsCaseStart = source.indexOf(
      'case NotificationRouteTargetKind.intros:',
    );
    expect(
      introsCaseStart,
      greaterThanOrEqualTo(0),
      reason: 'intros case must exist in _handleNotificationRouteTarget',
    );

    final introsCaseEnd = source.indexOf(
      'case NotificationRouteTargetKind.group:',
      introsCaseStart,
    );
    expect(
      introsCaseEnd,
      greaterThan(introsCaseStart),
      reason: 'intros case must be followed by the group case',
    );

    final introsCase = source.substring(introsCaseStart, introsCaseEnd);

    expect(
      introsCase.contains('openIntroAcceptNotificationRoute('),
      isTrue,
      reason:
          'intros case must hand the route target to the shared '
          'intro-accept open coordinator',
    );
    expect(
      introsCase.contains('await _openIntroOrbitRoute('),
      isFalse,
      reason:
          'intros case must not unconditionally open Orbit/Intros; the '
          'Orbit route is only the coordinator-owned fallback',
    );
    expect(
      introsCase.contains('openIntros:'),
      isTrue,
      reason:
          'the coordinator call must supply the Orbit/Intros fallback '
          'callback',
    );
    expect(
      introsCase.contains('resolveIntroductionNotificationTarget('),
      isTrue,
      reason:
          'the coordinator call must resolve through the introducer-accept '
          'resolver use case',
    );
    expect(
      RegExp(
        r'introStatusChanges:\s*'
        r'widget\.introductionListener\.introStatusChangedStream',
      ).hasMatch(introsCase),
      isTrue,
      reason:
          'the production Intros coordinator must supply the real listener '
          'status stream for exact-anchor convergence',
    );
  });
}
