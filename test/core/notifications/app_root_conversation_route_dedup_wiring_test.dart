import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-wiring lock for Report 139 (E2).
///
/// The 1:1 conversation case in `_handleNotificationRouteTarget`
/// (`lib/app/application_root.dart`) must consult the shared already-active guard — passing
/// the 1:1 `conversationTracker` — and emit the dedicated skip event before
/// pushing a new conversation route, mirroring the group case's existing
/// `GROUP_NOTIFICATION_ROUTE_ALREADY_ACTIVE` guard.
///
/// Private application-root glue can't be unit-tested directly, so this token-level
/// existence lock is the cheapest mutation-verifiable guard (precedent:
/// Report 120 G1 main.dart suppress-constant wiring-lock). The behavioral
/// proof is the notif-open same-peer harness scenario.
void main() {
  test('application root conversation case consults the already-active '
      'guard and emits the skip event', () {
    final source = File('lib/app/application_root.dart').readAsStringSync();

    final convCaseStart = source.indexOf(
      'case NotificationRouteTargetKind.conversation:',
    );
    expect(
      convCaseStart,
      greaterThanOrEqualTo(0),
      reason: 'conversation case must exist in _handleNotificationRouteTarget',
    );

    // Scope the assertions to the conversation case body only (up to the
    // next `case`), so we never accidentally match the group case guard.
    final convCaseEnd = source.indexOf(
      'case NotificationRouteTargetKind.post:',
      convCaseStart,
    );
    expect(
      convCaseEnd,
      greaterThan(convCaseStart),
      reason: 'conversation case must be followed by the post case',
    );

    final convCase = source.substring(convCaseStart, convCaseEnd);

    expect(
      convCase.contains('isNotificationRouteTargetAlreadyActive('),
      isTrue,
      reason: 'conversation case must call the already-active guard',
    );
    expect(
      convCase.contains('conversationTracker:'),
      isTrue,
      reason: 'guard call must pass the 1:1 conversationTracker',
    );
    expect(
      convCase.contains("'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE'"),
      isTrue,
      reason: 'conversation case must emit the dedicated skip event',
    );

    // Design lock (139 Risk "Guard-before-getContact ordering"): the
    // already-active guard must run BEFORE the contact lookup so suppression
    // stays a pure routing decision (no DB hit when already viewing the
    // peer). Mirrors the group case, which decides before any repo work.
    final guardIndex = convCase.indexOf(
      'isNotificationRouteTargetAlreadyActive(',
    );
    final getContactIndex = convCase.indexOf('.getContact(');
    expect(
      getContactIndex,
      greaterThan(0),
      reason: 'conversation case must still look up the contact on a miss',
    );
    expect(
      guardIndex,
      lessThan(getContactIndex),
      reason: 'already-active guard must run BEFORE the contact lookup',
    );
  });
}
