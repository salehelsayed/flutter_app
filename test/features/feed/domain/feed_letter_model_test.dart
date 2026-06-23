import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/domain/models/letter_line.dart';
import 'package:flutter_app/features/feed/domain/utils/group_sender_runs.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadMessage _incoming({
  required String id,
  required String text,
  String? senderPeerId,
  String? senderUsername,
}) {
  return ThreadMessage(
    id: id,
    text: text,
    time: '12:00',
    timestamp: DateTime(2026, 6, 20),
    isUnread: true,
    isIncoming: true,
    senderUsername: senderUsername,
    senderPeerId: senderPeerId,
  );
}

void main() {
  group('OneToOneLetter.fromThread (TC-04)', () {
    test('one incoming -> texts.length == 1, isStacked false', () {
      final item = ThreadFeedItem(
        id: 't1',
        timestamp: DateTime(2026, 6, 20),
        contactPeerId: 'peer-1',
        contactUsername: 'Alice',
        messages: [_incoming(id: '1', text: 'hi')],
      );

      final letter = OneToOneLetter.fromThread(item);

      expect(letter.peerId, 'peer-1');
      expect(letter.displayName, 'Alice');
      expect(letter.texts, ['hi']);
      expect(letter.texts.length, 1);
      expect(letter.isStacked, isFalse);
    });

    test('>=2 consecutive incoming -> texts stacked, isStacked true', () {
      final item = ThreadFeedItem(
        id: 't2',
        timestamp: DateTime(2026, 6, 20),
        contactPeerId: 'peer-2',
        contactUsername: 'Bob',
        messages: [
          _incoming(id: '1', text: 'one'),
          _incoming(id: '2', text: 'two'),
        ],
      );

      final letter = OneToOneLetter.fromThread(item);

      expect(letter.texts, ['one', 'two']);
      expect(letter.texts.length, greaterThanOrEqualTo(2));
      expect(letter.isStacked, isTrue);
    });

    test('uses UNCAPPED unreadMessages: 4 unread -> 4 texts, NOT capped at 3 '
        '(mutation: previewMessages/cap -> red at 4)', () {
      final item = ThreadFeedItem(
        id: 't3',
        timestamp: DateTime(2026, 6, 20),
        contactPeerId: 'peer-3',
        contactUsername: 'Carol',
        messages: [
          _incoming(id: '1', text: 'a'),
          _incoming(id: '2', text: 'b'),
          _incoming(id: '3', text: 'c'),
          _incoming(id: '4', text: 'd'),
        ],
      );

      final letter = OneToOneLetter.fromThread(item);

      expect(letter.texts.length, 4);
      expect(letter.texts, ['a', 'b', 'c', 'd']);
      expect(letter.isStacked, isTrue);
    });
  });

  group('GroupLetter.fromThread', () {
    test('runs == groupSenderRuns(unreadMessages), copies group fields', () {
      final messages = [
        _incoming(id: '1', text: 'M1', senderPeerId: 'mara', senderUsername: 'Mara'),
        _incoming(id: '2', text: 'M2', senderPeerId: 'mara', senderUsername: 'Mara'),
        _incoming(id: '3', text: 'B1', senderPeerId: 'bob', senderUsername: 'Bob'),
      ];
      final item = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 6, 20),
        groupId: 'group-1',
        groupName: 'Crew',
        groupType: GroupType.chat,
        messages: messages,
      );

      final letter = GroupLetter.fromThread(item);

      expect(letter.groupId, 'group-1');
      expect(letter.groupName, 'Crew');
      expect(letter.canWrite, item.canWrite);
      expect(letter.runs.length, 2);
      expect(letter.runs[0].texts, ['M1', 'M2']);
      expect(letter.runs[1].texts, ['B1']);

      // Equivalent to calling groupSenderRuns directly on unreadMessages.
      final expected = groupSenderRuns(item.unreadMessages);
      expect(letter.runs.map((r) => r.texts).toList(),
          expected.map((r) => r.texts).toList());
    });

    test('canWrite false for dissolved group', () {
      final item = GroupThreadFeedItem(
        id: 'g2',
        timestamp: DateTime(2026, 6, 20),
        groupId: 'group-2',
        groupName: 'Old',
        groupType: GroupType.chat,
        isDissolved: true,
        messages: [_incoming(id: '1', text: 'hey', senderPeerId: 'x', senderUsername: 'X')],
      );

      final letter = GroupLetter.fromThread(item);

      expect(letter.canWrite, isFalse);
    });
  });

  group('SystemLetter.fromConnection (TC-06 / TC-23)', () {
    test('introducedBy == null -> isIntroduction false (new-connection)', () {
      final item = ConnectionFeedItem(
        id: 'c1',
        timestamp: DateTime(2026, 6, 20),
        contactPeerId: 'peer-9',
        contactUsername: 'Dora',
      );

      final letter = SystemLetter.fromConnection(item);

      expect(letter.contactPeerId, 'peer-9');
      expect(letter.displayName, 'Dora');
      expect(letter.introducedBy, isNull);
      expect(letter.isIntroduction, isFalse);
    });

    test('introducedBy != null -> isIntroduction true carrying introducer name '
        '(mutation: drop introducedBy branch -> red)', () {
      final item = ConnectionFeedItem(
        id: 'c2',
        timestamp: DateTime(2026, 6, 20),
        contactPeerId: 'peer-10',
        contactUsername: 'Eve',
        introducedBy: 'Frank',
        introducedByPeerId: 'frank-peer',
      );

      final letter = SystemLetter.fromConnection(item);

      expect(letter.isIntroduction, isTrue);
      expect(letter.introducedBy, 'Frank');
      expect(letter.introducedByPeerId, 'frank-peer');
    });
  });

  group('FeedLetter sealed hierarchy', () {
    test('subtypes are FeedLetter and exhaustively matchable', () {
      final FeedLetter letter = OneToOneLetter(
        peerId: 'p',
        displayName: 'n',
        lines: const [LetterLine(messageId: 'm1', text: 'x')],
      );

      final label = switch (letter) {
        OneToOneLetter() => 'one',
        GroupLetter() => 'group',
        SystemLetter() => 'system',
      };

      expect(label, 'one');
    });
  });
}
