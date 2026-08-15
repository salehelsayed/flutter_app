import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Finding 05 Phase 2 wiring lock: the app-resume group drain must fetch only
/// the fast first page (which gates ack eligibility) and schedule the remaining
/// pages OUTSIDE the recovery gate, but only when the first page reported that
/// more pages remain on the relay. Normal callers keep the background path;
/// canonical iOS recovery may await the same continuation for an exact result.
///
/// The drain + continuation behavior itself is proven by the drain use-case
/// unit suite; this source lock guards the resume call site from silently
/// reverting to a blocking full drain (or an unconditional background drain).
void main() {
  test(
    'TC-370-07 handleAppResumed invokes the shared outcome drain after bridge health',
    () async {
      final source = await File(
        'lib/app/lifecycle/handle_app_resumed.dart',
      ).readAsString();

      expect(
        'Future<void> Function()? drainNotificationCompletedOutcomesFn,'
            .allMatches(source),
        hasLength(1),
      );
      expect(
        'Future<void>.sync(drainCompletedOutcomes)'.allMatches(source),
        hasLength(1),
        reason: 'resume must invoke the same coalesced callback exactly once',
      );
      final bridgeHealth = source.indexOf(
        'final bridgeOk = await bridge.checkHealth();',
      );
      final outcomeDrain = source.indexOf(
        'Future<void>.sync(drainCompletedOutcomes)',
      );
      final reprime = source.indexOf(
        'final reprime = p2pService.performImmediateHealthCheck();',
      );
      expect(bridgeHealth, lessThan(outcomeDrain));
      expect(outcomeDrain, lessThan(reprime));
    },
  );

  test(
    'handle_app_resumed drains first page only and schedules the continuation '
    'conditionally outside the gate',
    () async {
      final source = await File(
        'lib/app/lifecycle/handle_app_resumed.dart',
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

      // The continuation is gated on hasMorePages and OUTSIDE the recovery
      // gate (so its long tail never blocks group mutations).
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
        contains('final continuation = drainGroupOfflineInboxContinuation('),
      );
      expect(
        continuationBlock,
        contains('selfPeerId: continuationSelfPeerId,'),
      );
      expect(continuationBlock, contains('if (awaitCanonicalInboxDrains) {'));
      expect(continuationBlock, contains('final result = await continuation;'));
      expect(
        continuationBlock,
        contains('unawaited(continuation);'),
        reason: 'ordinary resume callers must retain the background path',
      );
    },
  );
}
