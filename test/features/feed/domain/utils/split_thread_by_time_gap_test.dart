import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/domain/utils/split_thread_by_time_gap.dart';

ConversationMessage _msg({
  required String id,
  required String timestamp,
  bool isIncoming = true,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: 'peer-A',
    senderPeerId: isIncoming ? 'peer-A' : 'self',
    text: 'msg $id',
    timestamp: timestamp,
    status: 'delivered',
    isIncoming: isIncoming,
    createdAt: timestamp,
  );
}

void main() {
  group('splitThreadByTimeGap', () {
    test('empty list returns empty', () {
      expect(splitThreadByTimeGap([]), isEmpty);
    });

    test('single message returns one chunk', () {
      final result = splitThreadByTimeGap([
        _msg(id: '1', timestamp: '2026-02-09T12:00:00.000Z'),
      ]);
      expect(result.length, 1);
      expect(result[0].length, 1);
    });

    test('messages within 24 hours stay in same chunk', () {
      final result = splitThreadByTimeGap([
        _msg(id: '1', timestamp: '2026-02-09T08:00:00.000Z'),
        _msg(id: '2', timestamp: '2026-02-09T14:00:00.000Z'),
        _msg(id: '3', timestamp: '2026-02-09T22:00:00.000Z'),
      ]);
      expect(result.length, 1);
      expect(result[0].length, 3);
    });

    test('24+ hour gap creates new chunk', () {
      final result = splitThreadByTimeGap([
        _msg(id: '1', timestamp: '2026-02-09T10:00:00.000Z'),
        _msg(id: '2', timestamp: '2026-02-09T10:30:00.000Z'),
        // 25 hour gap
        _msg(id: '3', timestamp: '2026-02-10T11:30:00.000Z'),
      ]);
      expect(result.length, 2);
      expect(result[0].length, 2);
      expect(result[1].length, 1);
      expect(result[0].first.id, '1');
      expect(result[1].first.id, '3');
    });

    test('burst messages (<5min) never split', () {
      final result = splitThreadByTimeGap([
        _msg(id: '1', timestamp: '2026-02-09T10:00:00.000Z'),
        _msg(id: '2', timestamp: '2026-02-09T10:01:00.000Z'),
        _msg(id: '3', timestamp: '2026-02-09T10:02:00.000Z'),
        _msg(id: '4', timestamp: '2026-02-09T10:03:00.000Z'),
      ]);
      expect(result.length, 1);
      expect(result[0].length, 4);
    });

    test('multiple gaps create multiple chunks', () {
      final result = splitThreadByTimeGap([
        _msg(id: '1', timestamp: '2026-02-08T08:00:00.000Z'),
        // 26 hour gap
        _msg(id: '2', timestamp: '2026-02-09T10:00:00.000Z'),
        // 26 hour gap
        _msg(id: '3', timestamp: '2026-02-10T12:00:00.000Z'),
      ]);
      expect(result.length, 3);
    });

    test('sent and received interleaved correctly', () {
      final result = splitThreadByTimeGap([
        _msg(id: '1', timestamp: '2026-02-09T10:00:00.000Z', isIncoming: true),
        _msg(id: '2', timestamp: '2026-02-09T10:05:00.000Z', isIncoming: false),
        _msg(id: '3', timestamp: '2026-02-09T10:10:00.000Z', isIncoming: true),
      ]);
      expect(result.length, 1);
      expect(result[0].length, 3);
    });

    test('reply soft-close: gap after sent message splits', () {
      final result = splitThreadByTimeGap([
        _msg(id: '1', timestamp: '2026-02-09T10:00:00.000Z', isIncoming: true),
        _msg(id: '2', timestamp: '2026-02-09T10:30:00.000Z', isIncoming: false),
        // 25 hour gap after sent message
        _msg(id: '3', timestamp: '2026-02-10T11:30:00.000Z', isIncoming: true),
      ]);
      expect(result.length, 2);
      expect(result[0].length, 2);
      expect(result[1].length, 1);
    });

    test('exact 24-hour boundary splits', () {
      final result = splitThreadByTimeGap([
        _msg(id: '1', timestamp: '2026-02-09T10:00:00.000Z'),
        _msg(id: '2', timestamp: '2026-02-10T10:00:00.000Z'),
      ]);
      expect(result.length, 2);
    });

    test('just under 24-hour boundary does not split', () {
      final result = splitThreadByTimeGap([
        _msg(id: '1', timestamp: '2026-02-09T10:00:00.000Z'),
        _msg(id: '2', timestamp: '2026-02-10T09:59:59.000Z'),
      ]);
      expect(result.length, 1);
    });

    test('custom gap duration respected', () {
      final result = splitThreadByTimeGap(
        [
          _msg(id: '1', timestamp: '2026-02-09T10:00:00.000Z'),
          _msg(id: '2', timestamp: '2026-02-09T11:00:00.000Z'),
        ],
        gap: const Duration(minutes: 30),
      );
      expect(result.length, 2);
    });
  });
}
