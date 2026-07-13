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
      expect(service.existsSync(), isTrue);
      expect(resolver.existsSync(), isTrue);

      final source = service.readAsStringSync();
      final gateSource = resolver.readAsStringSync();
      final publish = source.indexOf(
        'completionGate.publish(generation: generation)',
      );
      final claim = source.indexOf(
        'completionGate.claim(generation: generation)',
      );
      final guard = source.indexOf('guard claimed, let handler, let content');
      final apply = source.indexOf('applyOrSanitizeNotificationPreviewResult(');
      final marker = source.indexOf('recentRemoteShownMarkerStore?.mark(');
      final handoff = source.indexOf('handler(content)');
      final commit = source.indexOf('toneReservation.commit(now: Date())');

      expect(publish, greaterThanOrEqualTo(0));
      expect(claim, greaterThan(publish));
      expect(guard, greaterThan(claim));
      expect(apply, greaterThan(guard));
      expect(marker, greaterThan(apply));
      expect(handoff, greaterThan(marker));
      expect(commit, greaterThan(handoff));
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
      for (final assignment in <String>[
        'content.title = ""',
        'content.subtitle = ""',
        'content.body = ""',
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
