import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/initial_local_notification_route_diagnostics.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'parsed-route diagnostics bind normalized UTF-8 payload without raw IDs',
    () {
      const normalizedPeer = '12D3KooWExactPeerÄ';
      const rawPayload = '  $normalizedPeer  ';
      final target = NotificationRouteTarget.fromPayload(rawPayload)!;
      final details = initialLocalNotificationRouteParsedDetails(
        rawPayload: rawPayload,
        target: target,
      );
      final expectedBytes = utf8.encode(normalizedPeer);
      final expectedSha256 = sha256.convert(expectedBytes).toString();

      expect(details.keys.toSet(), <String>{
        'payloadSha256',
        'payloadUtf8Length',
        'routeKind',
        'peerSha256',
        'canonicalPayloadMatched',
      });
      expect(details['payloadSha256'], expectedSha256);
      expect(details['payloadUtf8Length'], expectedBytes.length);
      expect(details['routeKind'], 'conversation');
      expect(details['peerSha256'], expectedSha256);
      expect(details['canonicalPayloadMatched'], isTrue);

      for (final encoded in <String>[
        jsonEncode(details),
        jsonEncode(sanitizeFlowEventDetails(details)),
      ]) {
        expect(encoded, isNot(contains(normalizedPeer)));
        expect(encoded, isNot(contains(normalizedPeer.substring(0, 10))));
        expect(encoded, isNot(contains(rawPayload)));
      }
    },
  );

  test('diagnostics expose null peer hash and canonical parsed group kind', () {
    const payload = 'group:group-1|message:message-1';
    final target = NotificationRouteTarget.fromPayload(payload)!;
    final details = initialLocalNotificationRouteParsedDetails(
      rawPayload: payload,
      target: target,
    );

    expect(details['routeKind'], 'group');
    expect(details['peerSha256'], isNull);
    expect(details['canonicalPayloadMatched'], isTrue);
    expect(jsonEncode(details), isNot(contains('group-1')));
    expect(jsonEncode(details), isNot(contains('message-1')));
  });

  test(
    'canonical flag fails closed when parsed target differs from payload',
    () {
      const payload = '12D3KooWPayloadPeer';
      const targetPeer = '12D3KooWDifferentPeer';
      final details = initialLocalNotificationRouteParsedDetails(
        rawPayload: payload,
        target: const NotificationRouteTarget.conversation(targetPeer),
      );

      expect(details['canonicalPayloadMatched'], isFalse);
      expect(
        details['payloadSha256'],
        sha256.convert(utf8.encode(payload)).toString(),
      );
      expect(
        details['peerSha256'],
        sha256.convert(utf8.encode(targetPeer)).toString(),
      );
    },
  );

  test(
    'initial-local production wiring emits marker before route preparation',
    () {
      final applicationRoot = File(
        'lib/app/application_root.dart',
      ).readAsStringSync();
      final start = applicationRoot.indexOf(
        'Future<void> _handleInitialLocalNotificationLaunch() async',
      );
      final end = applicationRoot.indexOf(
        'Future<void> _onNotificationTap(String payload) async',
        start,
      );
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final method = applicationRoot.substring(start, end);

      final consume = method.indexOf('consumeInitialPayload: () async');
      final beforeRoute = method.indexOf('onBeforeRouteTarget: (target) async');
      final marker = method.indexOf(
        'event: initialLocalNotificationRouteParsedEvent',
      );
      final details = method.indexOf(
        'details: initialLocalNotificationRouteParsedDetails(',
      );
      final prepareContext = method.indexOf(
        'preparedContext = _createNotificationOpenRouteContext(target)',
      );
      final dispatch = method.indexOf('onRouteTarget: (target) async');

      expect(consume, greaterThan(0));
      expect(beforeRoute, greaterThan(consume));
      expect(marker, greaterThan(beforeRoute));
      expect(details, greaterThan(marker));
      expect(prepareContext, greaterThan(details));
      expect(dispatch, greaterThan(prepareContext));

      final dispatchSource = File(
        'lib/core/notifications/notification_route_dispatch.dart',
      ).readAsStringSync();
      final routeStart = dispatchSource.indexOf(
        'Future<void> routeNotificationPayload({',
      );
      final routeEnd = dispatchSource.indexOf(
        'Future<void> routeInitialLocalNotificationOpen({',
        routeStart,
      );
      final routeMethod = dispatchSource.substring(routeStart, routeEnd);
      expect(
        routeMethod.indexOf('NotificationRouteTarget.fromPayload(payload)'),
        lessThan(routeMethod.indexOf('onBeforeRouteTarget?.call(routeTarget)')),
      );
    },
  );
}
