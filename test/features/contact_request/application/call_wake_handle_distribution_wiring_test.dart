import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  void expectForwardingCount(
    String path, {
    required String receiver,
    required int minimum,
  }) {
    final contents = source(path);
    expect(
      RegExp(
        'resolveCallWakeHandle:\\s*${RegExp.escape(receiver)}'
        '\\.resolveCallWakeHandle',
      ).allMatches(contents).length,
      greaterThanOrEqualTo(minimum),
      reason: '$path must retain every call-wake resolver handoff',
    );
    expect(
      RegExp(
        'onCallWakeHandleDistributed:\\s*${RegExp.escape(receiver)}'
        '\\.onCallWakeHandleDistributed',
      ).allMatches(contents).length,
      greaterThanOrEqualTo(minimum),
      reason: '$path must retain every call-wake completion handoff',
    );
  }

  test('root and retained UI constructors preserve both call-only callbacks', () {
    expectForwardingCount(
      'lib/app/application_root.dart',
      receiver: 'widget',
      minimum: 3,
    );
    expectForwardingCount(
      'lib/features/identity/presentation/startup_router.dart',
      receiver: 'widget',
      minimum: 4,
    );
    expectForwardingCount(
      'lib/features/home/presentation/screens/first_time_experience_wired.dart',
      receiver: 'widget',
      minimum: 3,
    );
    expectForwardingCount(
      'lib/features/feed/presentation/screens/feed_wired.dart',
      receiver: 'widget',
      minimum: 2,
    );
    expectForwardingCount(
      'lib/features/orbit/presentation/screens/orbit_wired.dart',
      receiver: 'widget',
      minimum: 2,
    );
  });

  test('terminal QR, reciprocal, notification, and retry sends forward both', () {
    for (final path in <String>[
      'lib/features/qr_code/presentation/screens/qr_scanner_wired.dart',
      'lib/features/contact_request/application/accept_and_reciprocate_use_case.dart',
      'lib/features/contact_request/application/contact_request_notification_materializer.dart',
      'lib/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart',
      'lib/features/contact_request/application/key_exchange_retrier.dart',
    ]) {
      final contents = source(path);
      expect(contents, contains('resolveCallWakeHandle:'));
      expect(contents, contains('onCallWakeHandleDistributed:'));
    }

    final retry = source(
      'lib/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart',
    );
    expect(retry, contains('loadPendingCallWakeHandleContactIds'));
    expect(retry, contains('await contactRepo.getAllContacts()'));
    expect(
      retry,
      isNot(contains('writeWakeTokenPendingMarker(markerStore, callWake')),
    );
  });
}
