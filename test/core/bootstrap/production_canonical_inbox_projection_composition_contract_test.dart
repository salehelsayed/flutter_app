import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'canonical replay preserves received call-wake authority at the listener boundary',
    () {
      final source = File(
        'lib/app/bootstrap/'
        'production_canonical_inbox_projection_composition.dart',
      ).readAsStringSync();

      expect(
        _occurrences(
          source,
          'required ReceivedCallWakeHandleStore '
          'receivedCallWakeHandleStore,',
        ),
        1,
        reason: 'the headless graph must receive the bootstrap-owned store',
      );
      expect(
        _occurrences(
          source,
          'receivedCallWakeHandleStore: receivedCallWakeHandleStore,',
        ),
        1,
        reason:
            'the exact received store instance must reach ContactRequestListener',
      );

      final listenerStart = source.indexOf(
        'contactRequestListener = ContactRequestListener(',
      );
      final listenerEnd = source.indexOf(
        'contactRequestListenerForCleanup = contactRequestListener;',
        listenerStart,
      );
      expect(listenerStart, greaterThanOrEqualTo(0));
      expect(listenerEnd, greaterThan(listenerStart));
      expect(
        source.substring(listenerStart, listenerEnd),
        contains('receivedCallWakeHandleStore: receivedCallWakeHandleStore,'),
      );
    },
  );
}

int _occurrences(String source, String token) =>
    token.allMatches(source).length;
