import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/application/group_thought_reactions.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_test/flutter_test.dart';

const _names = {'sam': 'Sam', 'mo': 'Mo', 'kim': 'Kim'};
const _at = '2026-10-27T12:00:00Z';

ConversationMessage _reply(
  String id,
  String contact,
  String text, {
  String? sender,
  String? quote = 'thought:mine',
  String at = _at,
  String? editedAt,
  String createdAt = _at,
  bool incoming = true,
  String status = 'delivered',
  String? deletedAt,
  String? hiddenAt,
  String? transport,
  PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
  List<MediaAttachment> media = const [],
}) => ConversationMessage(
  id: id,
  contactPeerId: contact,
  senderPeerId: sender ?? contact,
  text: text,
  timestamp: at,
  createdAt: createdAt,
  isIncoming: incoming,
  status: status,
  quotedMessageId: quote,
  editedAt: editedAt,
  deletedAt: deletedAt,
  hiddenAt: hiddenAt,
  transport: transport,
  privateMediaPolicy: policy,
  media: media,
);

void main() {
  test(
    'groups across chats and counts people rather than repeated replies',
    () {
      final groups = groupThoughtReactions(
        postId: 'mine',
        participantNames: _names,
        replies: [
          _reply('sam-1', 'sam', '❤️'),
          _reply('mo-1', 'mo', '❤️'),
          _reply('sam-2', 'sam', ' ❤️ ', at: '2026-10-27T12:01:00Z'),
          _reply('kim-1', 'kim', '❤️'),
        ],
      );

      expect(groups, hasLength(1));
      expect(groups.single.reaction, ThoughtReaction.love);
      expect(groups.single.participants, [
        (peerId: 'sam', name: 'Sam'),
        (peerId: 'kim', name: 'Kim'),
        (peerId: 'mo', name: 'Mo'),
      ]);
    },
  );

  test(
    'linked senders count as their canonical contact, with current names',
    () {
      final groups = groupThoughtReactions(
        postId: 'mine',
        participantNames: const {'sam': 'Sam’s current name'},
        replies: [
          _reply('phone', 'sam', '🔥', sender: 'sam-phone'),
          _reply('tablet', 'sam', '🔥', sender: 'sam-tablet'),
        ],
      );

      expect(groups.single.participants, [
        (peerId: 'sam', name: 'Sam’s current name'),
      ]);
    },
  );

  test(
    'excludes entries that are not visible ordinary reactions to this thought',
    () {
      final groups = groupThoughtReactions(
        postId: 'mine',
        participantNames: _names,
        replies: [
          _reply('good', 'kim', '👏'),
          _reply('other-thought', 'sam', '❤️', quote: 'thought:other'),
          _reply('message-quote', 'sam', '❤️', quote: 'message-id'),
          _reply('no-quote', 'sam', '❤️', quote: null),
          _reply('text', 'sam', '❤️ see you'),
          _reply('unknown-glyph', 'sam', '😮'),
          _reply('outgoing', 'sam', '❤️', incoming: false),
          _reply(
            'failed-outgoing',
            'sam',
            '❤️',
            incoming: false,
            status: 'failed',
          ),
          _reply('deleted', 'sam', '❤️', deletedAt: _at),
          _reply('hidden', 'sam', '❤️', hiddenAt: _at),
          _reply('system', 'sam', '❤️', transport: 'system'),
          _reply('unknown-contact', 'unknown', '❤️'),
          _reply(
            'private',
            'sam',
            '❤️',
            policy: const PrivateMediaPolicy.protected(),
          ),
          _reply(
            'unsupported-private',
            'sam',
            '❤️',
            policy: const PrivateMediaPolicy.unsupported(),
          ),
          _reply(
            'photo-caption',
            'sam',
            '❤️',
            media: const [
              MediaAttachment(
                id: 'photo',
                messageId: 'photo-caption',
                mime: 'image/jpeg',
                size: 20,
                mediaType: 'image',
                downloadStatus: 'done',
                createdAt: _at,
              ),
            ],
          ),
        ],
      );

      expect(groups, hasLength(1));
      expect(groups.single.reaction, ThoughtReaction.applause);
      expect(groups.single.participants, [(peerId: 'kim', name: 'Kim')]);
    },
  );

  test(
    'different live glyphs remain separate, with a unique actor per group',
    () {
      final groups = groupThoughtReactions(
        postId: 'mine',
        participantNames: _names,
        replies: [
          _reply('fire', 'sam', '🔥'),
          _reply('love', 'sam', '❤️'),
          _reply('love-again', 'sam', '❤️'),
          _reply('laugh', 'mo', '😂'),
        ],
      );

      expect(groups.map((group) => group.reaction), [
        ThoughtReaction.love,
        ThoughtReaction.laugh,
        ThoughtReaction.fire,
      ]);
      expect(groups.map((group) => group.participants.length), [1, 1, 1]);
    },
  );

  test(
    'uses the current edited glyph and orders actors by their latest action',
    () {
      final groups = groupThoughtReactions(
        postId: 'mine',
        participantNames: _names,
        replies: [
          _reply('sam', 'sam', '🔥', editedAt: '2026-10-27T12:03:00Z'),
          _reply('mo', 'mo', '🔥', at: '2026-10-27T14:02:00+02:00'),
          _reply(
            'kim',
            'kim',
            '🔥',
            at: 'legacy-time',
            createdAt: 'legacy-time',
          ),
        ],
      );

      expect(groups.single.participants.map((actor) => actor.peerId), [
        'sam',
        'mo',
        'kim',
      ]);
    },
  );

  test('removing a reply removes that actor from its group', () {
    final remaining = [_reply('sam', 'sam', '❤️')];
    final before = groupThoughtReactions(
      postId: 'mine',
      participantNames: _names,
      replies: [...remaining, _reply('mo', 'mo', '❤️')],
    );
    final after = groupThoughtReactions(
      postId: 'mine',
      participantNames: _names,
      replies: remaining,
    );

    expect(before.single.participants, hasLength(2));
    expect(after.single.participants, [(peerId: 'sam', name: 'Sam')]);
  });

  test('an empty post id never matches an invalid thought quote', () {
    expect(
      groupThoughtReactions(
        postId: '',
        participantNames: _names,
        replies: [_reply('invalid', 'sam', '❤️', quote: 'thought:')],
      ),
      isEmpty,
    );
  });
}
