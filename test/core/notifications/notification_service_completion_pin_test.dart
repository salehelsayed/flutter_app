import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'iOS NSE owns apply marker handoff and tone behind one completion claim',
    () {
      final service = File('ios/NotificationService/NotificationService.swift');
      final resolver = File(
        'ios/NotificationService/NotificationPreviewResolver.swift',
      );
      final recovery = File(
        'ios/NotificationService/IosNotificationRecovery.swift',
      );
      expect(service.existsSync(), isTrue);
      expect(resolver.existsSync(), isTrue);
      expect(recovery.existsSync(), isTrue);

      final source = service.readAsStringSync();
      final gateSource = resolver.readAsStringSync();
      final recoverySource = recovery.readAsStringSync();
      final publish = source.indexOf(
        'completionGate.publish(generation: generation)',
      );
      final claim = source.indexOf(
        'completionGate.claim(generation: generation)',
      );
      // Plan 373: the claim guard binds handler first; the fixed-wake branch
      // consumes a nil rich content itself, so the rich content guard follows
      // separately before the recovery handoff.
      final guard = source.indexOf('guard claimed, let handler else');
      final contentGuard = source.indexOf('guard let content else', guard);
      final recoveryHandoff = source.indexOf(
        'notificationRecoveryHandoff.handoff(',
      );
      final apply = source.indexOf('applyOrSanitizeNotificationPreviewResult(');
      final marker = source.indexOf('recentRemoteShownMarkerStore?.mark(');
      // The fixed-wake branch hands the claimed handler to its own
      // final-effect/generic owners earlier; the RICH apply path still passes
      // the handler only after the shown marker.
      final handlerArgument = source.indexOf('contentHandler: handler', marker);
      final commit = source.indexOf('toneReservation.commit(now: Date())');

      expect(publish, greaterThanOrEqualTo(0));
      expect(claim, greaterThan(publish));
      expect(guard, greaterThan(claim));
      expect(contentGuard, greaterThan(guard));
      expect(recoveryHandoff, greaterThan(contentGuard));
      expect(apply, greaterThan(recoveryHandoff));
      expect(marker, greaterThan(apply));
      expect(handlerArgument, greaterThan(marker));
      expect(commit, greaterThan(handlerArgument));

      final recoveryPrepare = recoverySource.indexOf(
        'prepareContent(disposition)',
      );
      final recoveryBeforeHandler = recoverySource.indexOf(
        'beforeContentHandler(disposition)',
      );
      final recoveryHandler = recoverySource.indexOf('contentHandler(content)');
      final recoveryCommit = recoverySource.indexOf(
        'store?.markCommitted(requestIdentifier: requestIdentifier)',
      );
      expect(recoveryPrepare, greaterThanOrEqualTo(0));
      expect(recoveryBeforeHandler, greaterThan(recoveryPrepare));
      expect(recoveryHandler, greaterThan(recoveryBeforeHandler));
      expect(recoveryCommit, greaterThan(recoveryHandler));
      expect(
        source,
        contains('finish(generation: generation, expiry: true)'),
        reason: 'Expiry must compete for the exact request generation.',
      );
      expect(
        source,
        contains('guard publish(preview: preview, generation: generation)'),
        reason: 'Resolution must publish before normal completion can claim.',
      );
      expect(
        source,
        contains('details: ["kind": "preview_publish_lost"]'),
        reason:
            'A resolver that loses expiry/reset must release its tone handle.',
      );
      expect(
        gateSource,
        contains('guard let preview, preview.markAsShown else {'),
      );
      expect(
        gateSource,
        contains('sanitizeNotificationContentForUnresolvedExpiry('),
      );
      expect(source, contains('resolvedPreview = preview'));
      expect(source, contains('resolvedPreview = nil'));

      expect(
        gateSource,
        contains('final class NotificationServiceCompletionGate'),
      );
      expect(
        RegExp(
          r'guard !didFinish, token\.value == generation else \{ return false \}',
        ).allMatches(gateSource).length,
        2,
        reason: 'Both publish and claim must reject stale request tokens.',
      );
      expect(gateSource, contains('didFinish = true'));
      expect(gateSource, contains('publishState()'));
      expect(gateSource, contains('takeState()'));
      // Empty alert text makes iOS restore the provider's original content.
      // The sanitizer must retain fixed non-sensitive text while removing
      // sound and all provider-controlled presentation metadata.
      for (final assignment in <String>[
        'content.title = "Mknoon"',
        'content.subtitle = ""',
        'content.body = "Open the app to view updates."',
        'content.attachments = []',
        'content.badge = nil',
        'content.sound = nil',
        'content.categoryIdentifier = ""',
        'content.threadIdentifier = ""',
        'content.summaryArgument = ""',
        'content.summaryArgumentCount = 0',
        'content.launchImageName = ""',
        'content.targetContentIdentifier = ""',
        'content.filterCriteria = ""',
        'content.relevanceScore = 0',
        'content.interruptionLevel = .passive',
      ]) {
        expect(gateSource, contains(assignment), reason: assignment);
      }
    },
  );
}
