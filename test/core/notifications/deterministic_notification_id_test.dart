import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deterministic conversation ids match restart-stable vectors', () {
    expect(deterministicConversationNotificationId('peer-1'), 938474625);
    expect(deterministicConversationNotificationId('group:g1'), 1983137663);
    expect(
      deterministicConversationNotificationId('12D3KooWPeerBurst'),
      600274836,
    );
    expect(
      deterministicConversationNotificationId('peer-1'),
      deterministicConversationNotificationId('peer-1'),
    );
    expect(
      deterministicConversationNotificationId('peer-1'),
      inInclusiveRange(0, 0x7fffffff),
    );
  });

  test('reaction event identity is deterministic and at most 64 bytes', () {
    const eventId = 'reaction-event-123';
    const expected =
        'reaction:813117a606a0d109f3414152f6092e5c33da6c311a4a7736';
    final identity = boundedReactionEventIdentity(eventId);

    expect(identity, expected);
    expect(utf8.encode(identity).length, lessThanOrEqualTo(64));
  });

  test('reaction row in the shared identity fixture matches Dart', () {
    final rows =
        (jsonDecode(
                  File('test_fixtures/si5_dedupe_keys.json').readAsStringSync(),
                )
                as List)
            .cast<Map<String, dynamic>>();
    final row = rows.singleWhere(
      (entry) =>
          entry['description'] == '1:1 message_reaction bounded identity',
    );

    expect(
      boundedReactionEventIdentity(row['reactionEventId'] as String),
      row['expectedReactionIdentity'],
    );
  });

  test('empty identities fail closed', () {
    expect(
      () => deterministicConversationNotificationId(' '),
      throwsArgumentError,
    );
    expect(() => boundedReactionEventIdentity(''), throwsArgumentError);
  });
}
