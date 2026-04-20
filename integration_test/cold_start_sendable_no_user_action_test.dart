@Tags(['device'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'benchmark_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets(
    'cold start reaches a sendable badge without foreground user action',
    (tester) async {
      final node = await createBenchmarkNode();

      try {
        final events = await captureFlowEventsUntil(
          () async {
            final sendable = await node.startAndWaitSendable(
              timeout: const Duration(seconds: 30),
            );
            expect(
              sendable,
              isTrue,
              reason: 'Cold start should leave Connecting without a user send',
            );
          },
          postActionTimeout: const Duration(milliseconds: 200),
          until: (captured) {
            return firstEventDetails(
                      captured,
                      'TIME_TO_SENDABLE_BADGE',
                      phase: 'cold_start',
                    ) !=
                    null &&
                firstEventDetails(
                      captured,
                      'FIRST_SEND_SUCCESS_IN_WINDOW',
                      phase: 'cold_start',
                    ) !=
                    null;
          },
        );

        final sendable = firstEventDetails(
          events,
          'TIME_TO_SENDABLE_BADGE',
          phase: 'cold_start',
        );
        final firstSend = firstEventDetails(
          events,
          'FIRST_SEND_SUCCESS_IN_WINDOW',
          phase: 'cold_start',
        );

        expect(sendable, isNotNull);
        expect(firstSend, isNotNull);
        expect(firstSend!['source'], 'system_inbox_store_probe');
        expect(firstSend['trigger'], 'system_action');
        expect(
          filterEvents(events, 'CHAT_MSG_SEND_START'),
          isEmpty,
          reason: 'The cold-start badge must not require a foreground send',
        );
        expect(isSendableBadgeState(node.service.currentState), isTrue);
        expect(
          (sendable!['totalMs'] as num).toInt(),
          greaterThanOrEqualTo((firstSend['totalMs'] as num).toInt()),
        );
      } finally {
        await node.dispose();
      }
    },
  );
}
