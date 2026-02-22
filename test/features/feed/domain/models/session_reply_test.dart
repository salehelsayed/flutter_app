import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';

void main() {
  group('SessionReply', () {
    test('stores text and time', () {
      final time = DateTime(2026, 2, 22, 10, 30);
      final reply = SessionReply(text: 'Hello', time: time);
      expect(reply.text, 'Hello');
      expect(reply.time, time);
    });

    test('justNow creates with current time', () {
      final before = DateTime.now();
      final reply = SessionReply.justNow('Hi');
      final after = DateTime.now();
      expect(reply.text, 'Hi');
      expect(reply.time.isAfter(before) || reply.time == before, isTrue);
      expect(reply.time.isBefore(after) || reply.time == after, isTrue);
    });
  });

  group('SessionReplyTracker', () {
    late SessionReplyTracker tracker;

    setUp(() {
      tracker = SessionReplyTracker();
    });

    test('stores and retrieves by contactPeerId', () {
      final reply = SessionReply.justNow('Hello');
      tracker.track('peer1', reply);
      expect(tracker.get('peer1'), reply);
    });

    test('hasReply true for tracked, false for untracked', () {
      tracker.track('peer1', SessionReply.justNow('Hi'));
      expect(tracker.hasReply('peer1'), isTrue);
      expect(tracker.hasReply('peer2'), isFalse);
    });

    test('clear removes a reply', () {
      tracker.track('peer1', SessionReply.justNow('Hi'));
      expect(tracker.hasReply('peer1'), isTrue);
      tracker.clear('peer1');
      expect(tracker.hasReply('peer1'), isFalse);
      expect(tracker.get('peer1'), isNull);
    });
  });
}
