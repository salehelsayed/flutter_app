import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';

void main() {
  test('round-trips add reaction', () {
    final payload = GroupReactionPayload(
      id: 'r-1',
      messageId: 'msg-1',
      emoji: '👍',
      action: 'add',
      senderPeerId: 'peer-1',
      timestamp: '2026-03-08T00:00:00.000Z',
    );

    final json = payload.toInnerJson();
    final parsed = GroupReactionPayload.fromDecryptedJson(json);

    expect(parsed, isNotNull);
    expect(parsed!.id, 'r-1');
    expect(parsed.messageId, 'msg-1');
    expect(parsed.emoji, '👍');
    expect(parsed.action, 'add');
    expect(parsed.senderPeerId, 'peer-1');
    expect(parsed.timestamp, '2026-03-08T00:00:00.000Z');
  });

  test('round-trips remove reaction', () {
    final payload = GroupReactionPayload(
      id: 'r-2',
      messageId: 'msg-2',
      emoji: '❤️',
      action: 'remove',
      senderPeerId: 'peer-2',
      timestamp: '2026-03-08T01:00:00.000Z',
    );

    final json = payload.toInnerJson();
    final parsed = GroupReactionPayload.fromDecryptedJson(json);

    expect(parsed, isNotNull);
    expect(parsed!.action, 'remove');
    expect(parsed.emoji, '❤️');
  });

  test('preserves multi-codepoint emoji 👨‍👩‍👧‍👦', () {
    final payload = GroupReactionPayload(
      id: 'r-3',
      messageId: 'msg-3',
      emoji: '👨‍👩‍👧‍👦',
      action: 'add',
      senderPeerId: 'peer-3',
      timestamp: '2026-03-08T02:00:00.000Z',
    );

    final json = payload.toInnerJson();
    final parsed = GroupReactionPayload.fromDecryptedJson(json);

    expect(parsed, isNotNull);
    expect(parsed!.emoji, '👨‍👩‍👧‍👦');
  });

  test('returns null for invalid JSON', () {
    final result = GroupReactionPayload.fromDecryptedJson('not json');
    expect(result, isNull);
  });

  test('returns null for missing fields', () {
    final result = GroupReactionPayload.fromDecryptedJson('{"id":"r-1"}');
    expect(result, isNull);
  });

  test('toMessageReaction creates valid model', () {
    final payload = GroupReactionPayload(
      id: 'r-4',
      messageId: 'msg-4',
      emoji: '😂',
      action: 'add',
      senderPeerId: 'peer-4',
      timestamp: '2026-03-08T03:00:00.000Z',
    );

    final reaction = payload.toMessageReaction();
    expect(reaction.id, 'r-4');
    expect(reaction.messageId, 'msg-4');
    expect(reaction.emoji, '😂');
    expect(reaction.senderPeerId, 'peer-4');
    expect(reaction.timestamp, '2026-03-08T03:00:00.000Z');
    expect(reaction.createdAt, isNotEmpty);
  });
}
