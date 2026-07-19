import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> _captureClaims(void Function() action) {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) printed.add(message);
  };
  try {
    action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }
  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .where((event) => event['event'] == 'MEDIA_UPLOAD_LEASE_CLAIMED')
      .toList(growable: false);
}

void main() {
  group('MediaUploadInFlightTracker token ownership', () {
    late MediaUploadInFlightTracker tracker;

    setUp(() => tracker = MediaUploadInFlightTracker());

    test(
      'claim marks attachments and owner release clears the whole lease',
      () {
        final lease = tracker.tryClaimAll(const [
          'a',
          'b',
        ], source: MediaUploadTriggerSource.foreground);

        expect(lease, isNotNull);
        expect(lease!.attachmentCount, 2);
        expect(tracker.isInFlight('a'), isTrue);
        expect(tracker.isInFlight('b'), isTrue);
        expect(tracker.release(lease), isTrue);
        expect(tracker.inFlightCount, 0);
        expect(tracker.release(lease), isFalse);
      },
    );

    test('multi-attachment claim is all-or-none', () {
      final winner = tracker.tryClaimAll(const [
        'a',
        'b',
      ], source: MediaUploadTriggerSource.foreground);

      final loser = tracker.tryClaimAll(const [
        'b',
        'c',
      ], source: MediaUploadTriggerSource.manual);

      expect(winner, isNotNull);
      expect(loser, isNull);
      expect(tracker.isInFlight('a'), isTrue);
      expect(tracker.isInFlight('b'), isTrue);
      expect(tracker.isInFlight('c'), isFalse);
    });

    test('foreign tracker release cannot clear the winning owner', () {
      final foreign = MediaUploadInFlightTracker();
      final lease = tracker.tryClaimAll(const [
        'a',
      ], source: MediaUploadTriggerSource.full)!;

      expect(foreign.release(lease), isFalse);
      expect(tracker.isInFlight('a'), isTrue);
      expect(tracker.release(lease), isTrue);
    });

    test('stale lease cannot clear a later reclaim', () {
      final stale = tracker.tryClaimAll(const [
        'a',
      ], source: MediaUploadTriggerSource.full)!;
      tracker.clearAll();
      final current = tracker.tryClaimAll(const [
        'a',
      ], source: MediaUploadTriggerSource.periodic)!;

      expect(tracker.release(stale), isFalse);
      expect(tracker.isInFlight('a'), isTrue);
      expect(tracker.release(current), isTrue);
    });

    test('empty claims and empty attachment IDs are rejected', () {
      expect(
        tracker.tryClaimAll(const [], source: MediaUploadTriggerSource.resume),
        isNull,
      );
      expect(
        tracker.tryClaimAll(const [
          '',
        ], source: MediaUploadTriggerSource.resume),
        isNull,
      );
      expect(tracker.inFlightCount, 0);
    });

    test('claim telemetry contains only source and lowercase SHA-256', () {
      final events = _captureClaims(() {
        tracker.tryClaimAll(const [
          'secret-attachment-id',
        ], source: MediaUploadTriggerSource.networkRestored);
      });

      expect(events, hasLength(1));
      final details = (events.single['details'] as Map).cast<String, dynamic>();
      expect(details, {
        'source': 'network_restored',
        'attachmentSha256': sha256
            .convert(utf8.encode('secret-attachment-id'))
            .toString(),
      });
      expect(details['attachmentSha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(jsonEncode(details), isNot(contains('secret-attachment-id')));
    });

    test('the process-wide singleton instance exists', () {
      expect(mediaUploadInFlightTracker, isA<MediaUploadInFlightTracker>());
    });
  });
}
