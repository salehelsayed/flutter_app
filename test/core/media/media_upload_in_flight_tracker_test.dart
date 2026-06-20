import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';

void main() {
  group('MediaUploadInFlightTracker (127-Bug-B)', () {
    late MediaUploadInFlightTracker tracker;

    setUp(() => tracker = MediaUploadInFlightTracker());

    test('begin marks a blob in-flight; end clears it', () {
      expect(tracker.isInFlight('blob-1'), isFalse);
      tracker.begin('blob-1');
      expect(tracker.isInFlight('blob-1'), isTrue);
      tracker.end('blob-1');
      expect(tracker.isInFlight('blob-1'), isFalse);
    });

    test('tracks multiple blobs independently', () {
      tracker.begin('a');
      tracker.begin('b');
      expect(tracker.isInFlight('a'), isTrue);
      expect(tracker.isInFlight('b'), isTrue);
      tracker.end('a');
      expect(tracker.isInFlight('a'), isFalse);
      expect(tracker.isInFlight('b'), isTrue);
    });

    test('empty blobId is never tracked', () {
      tracker.begin('');
      expect(tracker.isInFlight(''), isFalse);
      expect(tracker.inFlightCount, 0);
    });

    test('end is idempotent / safe on an untracked blob', () {
      tracker.end('never-started'); // no throw
      expect(tracker.isInFlight('never-started'), isFalse);
    });

    test('the process-wide singleton instance exists', () {
      expect(mediaUploadInFlightTracker, isA<MediaUploadInFlightTracker>());
    });
  });
}
