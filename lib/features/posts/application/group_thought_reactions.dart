import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';

typedef ThoughtReactionParticipant = ({String peerId, String name});

typedef ThoughtReactionGroup = ({
  ThoughtReaction reaction,
  List<ThoughtReactionParticipant> participants,
});

/// Groups the existing ordinary reply messages, without enabling legacy post
/// reactions or treating delivery as proof that somebody viewed a thought.
///
/// [participantNames] contains the current eligible contacts. The canonical
/// conversation contact identifies a person, including replies from that
/// person's linked devices; a transport sender is not an additional person.
/// Repeated replies count once per person and glyph. Different glyphs remain
/// separate reactions while their underlying messages still exist.
List<ThoughtReactionGroup> groupThoughtReactions({
  required String postId,
  required Iterable<ConversationMessage> replies,
  required Map<String, String> participantNames,
}) {
  if (postId.isEmpty) return const [];
  final quoteId = thoughtQuoteId(postId);
  final actors = <ThoughtReaction, Map<String, DateTime>>{};
  for (final reply in replies) {
    if (!reply.isIncoming ||
        reply.isDeleted ||
        reply.isHidden ||
        reply.transport == 'system' ||
        reply.privateMediaPolicy.requiresRedaction ||
        reply.media.isNotEmpty ||
        reply.quotedMessageId != quoteId ||
        !participantNames.containsKey(reply.contactPeerId)) {
      continue;
    }
    final reaction = ThoughtReaction.fromText(reply.text);
    if (reaction == null) continue;
    final at =
        DateTime.tryParse(reply.editedAt ?? '') ??
        DateTime.tryParse(reply.timestamp) ??
        DateTime.tryParse(reply.createdAt) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final byActor = actors.putIfAbsent(reaction, () => {});
    final previous = byActor[reply.contactPeerId];
    if (previous == null || at.isAfter(previous)) {
      byActor[reply.contactPeerId] = at;
    }
  }

  return List.unmodifiable([
    for (final reaction in ThoughtReaction.values)
      if (actors[reaction] case final byActor?)
        (
          reaction: reaction,
          participants: List<ThoughtReactionParticipant>.unmodifiable(
            (byActor.entries.toList()..sort((a, b) {
                  final byTime = b.value.compareTo(a.value);
                  return byTime != 0 ? byTime : a.key.compareTo(b.key);
                }))
                .map(
                  (actor) =>
                      (peerId: actor.key, name: participantNames[actor.key]!),
                ),
          ),
        ),
  ]);
}
