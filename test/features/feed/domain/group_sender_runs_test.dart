import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_sender_runs.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadMessage _msg({
  required String id,
  required String text,
  String? senderPeerId,
  String? senderUsername,
  bool isIncoming = true,
  bool isDeleted = false,
}) {
  return ThreadMessage(
    id: id,
    text: text,
    time: '12:00',
    timestamp: DateTime(2026, 6, 20),
    isUnread: true,
    isIncoming: isIncoming,
    isDeleted: isDeleted,
    senderUsername: senderUsername,
    senderPeerId: senderPeerId,
  );
}

void main() {
  group('groupSenderRuns (TC-05)', () {
    test('collapses consecutive same-sender incoming lines into runs, '
        'drops outgoing, preserves order', () {
      final messages = <ThreadMessage>[
        _msg(id: '1', text: 'M1', senderPeerId: 'mara', senderUsername: 'Mara'),
        _msg(id: '2', text: 'M2', senderPeerId: 'mara', senderUsername: 'Mara'),
        _msg(id: '3', text: 'B1', senderPeerId: 'bob', senderUsername: 'Bob'),
        _msg(id: '4', text: 'M3', senderPeerId: 'mara', senderUsername: 'Mara'),
        _msg(
          id: '5',
          text: 'OUT',
          senderPeerId: 'me',
          senderUsername: 'Me',
          isIncoming: false,
        ),
      ];

      final runs = groupSenderRuns(messages);

      // [Mara x2, Bob x1, Mara x1]
      expect(runs.length, 3);

      expect(runs[0].senderPeerId, 'mara');
      expect(runs[0].senderName, 'Mara');
      expect(runs[0].texts, ['M1', 'M2']);

      expect(runs[1].senderPeerId, 'bob');
      expect(runs[1].senderName, 'Bob');
      expect(runs[1].texts, ['B1']);

      expect(runs[2].senderPeerId, 'mara');
      expect(runs[2].senderName, 'Mara');
      expect(runs[2].texts, ['M3']);

      // Outgoing dropped: no run carries the outgoing text.
      final allTexts = runs.expand((r) => r.texts).toList();
      expect(allTexts.contains('OUT'), isFalse);
    });

    test('NO maxPreview truncation: a single sender run keeps >=4 lines '
        '(mutation: cap at 3 -> 4th lost)', () {
      final messages = <ThreadMessage>[
        _msg(id: '1', text: 'L1', senderPeerId: 'mara', senderUsername: 'Mara'),
        _msg(id: '2', text: 'L2', senderPeerId: 'mara', senderUsername: 'Mara'),
        _msg(id: '3', text: 'L3', senderPeerId: 'mara', senderUsername: 'Mara'),
        _msg(id: '4', text: 'L4', senderPeerId: 'mara', senderUsername: 'Mara'),
        _msg(id: '5', text: 'L5', senderPeerId: 'mara', senderUsername: 'Mara'),
      ];

      final runs = groupSenderRuns(messages);

      expect(runs.length, 1);
      expect(runs.single.texts, ['L1', 'L2', 'L3', 'L4', 'L5']);
      expect(runs.single.texts.length, 5);
    });

    test('drops deleted incoming lines', () {
      final messages = <ThreadMessage>[
        _msg(id: '1', text: 'keep', senderPeerId: 'mara', senderUsername: 'Mara'),
        _msg(
          id: '2',
          text: 'gone',
          senderPeerId: 'mara',
          senderUsername: 'Mara',
          isDeleted: true,
        ),
      ];

      final runs = groupSenderRuns(messages);

      expect(runs.length, 1);
      expect(runs.single.texts, ['keep']);
    });

    test('groups by senderPeerId, falling back to senderUsername when '
        'peerId is null', () {
      final messages = <ThreadMessage>[
        _msg(id: '1', text: 'A', senderUsername: 'Ann'),
        _msg(id: '2', text: 'B', senderUsername: 'Ann'),
      ];

      final runs = groupSenderRuns(messages);

      expect(runs.length, 1);
      expect(runs.single.senderPeerId, 'Ann');
      expect(runs.single.senderName, 'Ann');
      expect(runs.single.texts, ['A', 'B']);
    });
  });
}
