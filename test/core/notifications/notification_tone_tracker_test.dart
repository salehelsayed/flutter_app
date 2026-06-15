import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';

void main() {
  group('NotificationToneTracker', () {
    late DateTime now;
    late NotificationToneTracker tracker;

    setUp(() {
      now = DateTime.utc(2026, 6, 13, 12);
      tracker = NotificationToneTracker(
        clock: () => now,
        window: const Duration(seconds: 30),
      );
    });

    test('first message in a quiet conversation plays a tone', () {
      expect(tracker.shouldPlayTone('peer-1'), isTrue);
    });

    test('a second message within the window is silent', () {
      expect(tracker.shouldPlayTone('peer-1'), isTrue);
      now = now.add(const Duration(seconds: 5));
      expect(tracker.shouldPlayTone('peer-1'), isFalse);
    });

    test('the first message after the window plays again', () {
      expect(tracker.shouldPlayTone('peer-1'), isTrue);
      now = now.add(const Duration(seconds: 31));
      expect(tracker.shouldPlayTone('peer-1'), isTrue);
    });

    test(
      'the window is keyed to the last AUDIBLE tone and does not extend on '
      'silent updates',
      () {
        expect(tracker.shouldPlayTone('peer-1'), isTrue); // tone at t=0
        now = now.add(const Duration(seconds: 20));
        expect(tracker.shouldPlayTone('peer-1'), isFalse); // silent at t=20
        // t=31 is >30s since the last TONE (t=0), not since the last call.
        now = now.add(const Duration(seconds: 11));
        expect(tracker.shouldPlayTone('peer-1'), isTrue);
      },
    );

    test('each conversation gets its own first tone', () {
      expect(tracker.shouldPlayTone('peer-1'), isTrue);
      expect(tracker.shouldPlayTone('peer-2'), isTrue);
      now = now.add(const Duration(seconds: 5));
      expect(tracker.shouldPlayTone('peer-1'), isFalse);
      expect(tracker.shouldPlayTone('peer-2'), isFalse);
    });

    test(
      'group route variants normalize to the same conversation bucket',
      () {
        // First group message via the anchored route plays a tone.
        expect(tracker.shouldPlayTone('group:g1|message:abc'), isTrue);
        now = now.add(const Duration(seconds: 5));
        // A follow-up addressed by the bare group key is silent (same bucket).
        expect(tracker.shouldPlayTone('group:g1'), isFalse);
        // And another anchored variant within the window is also silent.
        expect(tracker.shouldPlayTone('group:g1|message:def'), isFalse);
      },
    );
  });
}
