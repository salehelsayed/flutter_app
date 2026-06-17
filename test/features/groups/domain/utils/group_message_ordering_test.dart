import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/utils/group_message_ordering.dart';

void main() {
  // Locks the contract of orderGroupMessagesForTimeline, which the conversation
  // wired layer relies on for both the initial load (_loadMessages) and every
  // in-place update (_upsertMessage), and which both repository layers apply
  // inside getMessagesPage. Pinning it here keeps those call sites in lockstep.

  GroupMessage msg(
    String id,
    int minute, {
    String? quotes,
    String groupId = 'g1',
  }) {
    final ts = DateTime.utc(2026, 2, 1, 10, minute);
    return GroupMessage(
      id: id,
      groupId: groupId,
      senderPeerId: 'peer-$id',
      senderUsername: 'User $id',
      text: 'Message $id',
      timestamp: ts,
      createdAt: ts,
      isIncoming: true,
      quotedMessageId: quotes,
    );
  }

  List<String> ids(Iterable<GroupMessage> messages) =>
      messages.map((m) => m.id).toList();

  test('returns the input unchanged for fewer than two messages', () {
    expect(orderGroupMessagesForTimeline([]), isEmpty);
    expect(ids(orderGroupMessagesForTimeline([msg('a', 0)])), ['a']);
  });

  test('orders plain messages by timestamp ascending', () {
    final result = orderGroupMessagesForTimeline([
      msg('c', 2),
      msg('a', 0),
      msg('b', 1),
    ]);
    expect(ids(result), ['a', 'b', 'c']);
  });

  test('breaks timestamp ties by id ascending', () {
    final result = orderGroupMessagesForTimeline([msg('b', 0), msg('a', 0)]);
    expect(ids(result), ['a', 'b']);
  });

  test('places an out-of-order reply directly after its quoted parent', () {
    // The reply is delivered with an earlier timestamp than the parent it
    // quotes (out-of-order arrival). Threading must defer it until the parent
    // is placed, then drop it immediately after.
    final reply = msg('reply', 1, quotes: 'parent');
    final between = msg('between', 2);
    final parent = msg('parent', 3);

    final result = orderGroupMessagesForTimeline([reply, between, parent]);
    final ordered = ids(result);

    expect(ordered.contains('reply'), isTrue);
    expect(
      ordered.indexOf('parent') < ordered.indexOf('reply'),
      isTrue,
      reason: 'parent must precede its reply',
    );
    expect(
      ordered.indexOf('reply'),
      ordered.indexOf('parent') + 1,
      reason: 'reply lands immediately after its parent',
    );
  });

  test('places a reply with a missing quoted parent in chronological order', () {
    final result = orderGroupMessagesForTimeline([
      msg('a', 0),
      msg('reply', 1, quotes: 'ghost'),
      msg('c', 2),
    ]);
    expect(ids(result), ['a', 'reply', 'c']);
  });

  test('ignores a quoted parent that belongs to a different group', () {
    final foreign = msg('foreign', 5, groupId: 'other');
    final reply = msg('reply', 1, quotes: 'foreign');

    final result = orderGroupMessagesForTimeline([foreign, reply]);
    // Cross-group quote is not treated as a parent: pure chronological order.
    expect(ids(result), ['reply', 'foreign']);
  });

  test('is idempotent — re-ordering an ordered list is a no-op', () {
    final input = [
      msg('reply', 1, quotes: 'parent'),
      msg('between', 2),
      msg('parent', 3),
    ];
    final once = orderGroupMessagesForTimeline(input);
    final twice = orderGroupMessagesForTimeline(once);
    expect(ids(twice), ids(once));
  });
}
