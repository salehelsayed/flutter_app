import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Finding 05 Phase 2 wiring lock: the app-resume group drain must fetch only
/// the fast first page (which gates ack eligibility) and schedule the remaining
/// pages as a background continuation OUTSIDE the recovery gate, but only when
/// the first page reported that more pages remain on the relay.
///
/// The drain + continuation behavior itself is proven by the drain use-case
/// unit suite; this source lock guards the resume call site from silently
/// reverting to a blocking full drain (or an unconditional background drain).
void main() {
  test(
    'handle_app_resumed drains first page only and schedules the continuation '
    'conditionally outside the gate',
    () async {
      final source = await File(
        'lib/core/lifecycle/handle_app_resumed.dart',
      ).readAsString();

      // The resume drain feeds ack from the fast first page.
      expect(
        source,
        contains('drainAllPages: false,'),
        reason:
            'resume group drain must stop at the first page so ack eligibility '
            'is computed on the resume budget, not the full multi-page drain',
      );
      expect(
        source,
        contains('drainHasMorePages = groupDrainResult.hasMorePages;'),
      );

      // The continuation is fire-and-forget, gated on hasMorePages, OUTSIDE the
      // recovery gate (so the long tail never blocks group mutations).
      final guardIndex = source.indexOf('if (drainHasMorePages) {');
      expect(guardIndex, isNonNegative);
      final gateCloseIndex = source.lastIndexOf('});', guardIndex);
      expect(
        gateCloseIndex,
        lessThan(guardIndex),
        reason: 'the continuation must be scheduled after the gate closure',
      );

      final continuationBlock = source.substring(
        guardIndex,
        source.indexOf('} else if', guardIndex),
      );
      expect(
        continuationBlock,
        contains('unawaited(\n          drainGroupOfflineInboxContinuation('),
        reason: 'the long-tail drain must be unawaited (background)',
      );
      expect(
        continuationBlock,
        contains('selfPeerId: continuationSelfPeerId,'),
      );
    },
  );
}
