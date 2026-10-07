// Pin: the native iOS notification-open gate forwards every payload type that
// Dart routes. A type missing from the Swift switch is skipped as
// `not_route_shaped`, so a tapped notification opens the app without routing.
// Direct reactions (`message_reaction`) were missing on a physical iPhone; the
// Swift behaviour itself is locked by IosNotificationOpenRouteShapeTests.

import 'dart:io';

import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> _caseLabels(String source, RegExp label) {
  return label
      .allMatches(source)
      .expand(
        (match) => RegExp(
          r'"([a-z_]+)"|'
          r"'([a-z_]+)'",
        ).allMatches(match.group(1)!).map((m) => m.group(1) ?? m.group(2)!),
      )
      .toSet();
}

String _section(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNonNegative, reason: 'Missing `$start`.');
  final to = source.indexOf(end, from);
  expect(to, greaterThan(from), reason: 'Missing `$end` after `$start`.');
  return source.substring(from, to);
}

String _swiftSwitch() {
  final swift = File(
    'ios/Runner/IosNotificationOpenRouteShape.swift',
  ).readAsStringSync();
  return _section(swift, 'switch type {', 'default:');
}

void main() {
  test('Swift gate covers exactly the types Dart routes', () {
    final swiftTypes = _caseLabels(_swiftSwitch(), RegExp(r'case ([^:]+):'));
    final dart = File(
      'lib/core/notifications/notification_route_target.dart',
    ).readAsStringSync();
    final dartSwitch = _section(
      dart,
      'static NotificationRouteTarget? fromRemoteMessageData(',
      'static NotificationRouteTarget? _groupRouteFromRemoteMessageData(',
    );
    final dartTypes = _caseLabels(dartSwitch, RegExp(r'case ([^:]+):'));

    expect(dartTypes, contains('message_reaction'));
    expect(swiftTypes, dartTypes);
  });

  test('Swift message_reaction case requires the fields Dart routes on', () {
    final reactionCase = _section(
      _swiftSwitch(),
      'case "message_reaction":',
      'case "contact_request":',
    );
    for (final field in [
      '"target_message_id"',
      '"targetMessageId"',
      '"sender_id"',
      '"from"',
      '== "add"',
    ]) {
      expect(reactionCase, contains(field));
    }

    expect(
      NotificationRouteTarget.fromRemoteMessageData(const {
        'type': 'message_reaction',
        'action': 'add',
        'sender_id': 'peer-reactor-1',
        'target_message_id': 'msg-target-1',
      })?.kind,
      NotificationRouteTargetKind.conversation,
    );
  });

  test('AppDelegate gates notification opens through the shared policy', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(
      appDelegate,
      contains('guard IosNotificationOpenRouteShape.isRouteShaped(payload)'),
    );
    expect(
      appDelegate,
      isNot(contains('isRouteShapedApnsNotificationOpenPayload')),
    );
  });
}
