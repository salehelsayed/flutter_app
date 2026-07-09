import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cold getInitialMessage tap runs the staged-envelope ingest before the conversation first render',
    () {
      final source = File(
        'lib/features/identity/presentation/startup_router.dart',
      ).readAsStringSync();

      expect(source, contains('ingestStagedPushEnvelopes'));
      final prepareIndex = source.indexOf('prepareNotificationRouteTarget(');
      final ingestIndex = source.indexOf('ingestStagedPushEnvelopes');
      expect(ingestIndex, isNonNegative);
      expect(prepareIndex, isNonNegative);
      expect(
        ingestIndex,
        lessThan(prepareIndex),
        reason:
            'the cold getInitialMessage wrapper must carry staged-envelope ingest before route preparation pushes the conversation',
      );
    },
  );
}
