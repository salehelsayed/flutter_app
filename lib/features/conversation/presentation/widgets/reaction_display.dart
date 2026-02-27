import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';

/// Displays emoji reaction chips below a message.
///
/// Groups reactions by emoji, shows count, and highlights chips where
/// [ownPeerId] matches a reaction sender.
class ReactionDisplay extends StatelessWidget {
  final List<MessageReaction> reactions;
  final String ownPeerId;
  final void Function(String emoji)? onReactionTap;

  const ReactionDisplay({
    super.key,
    required this.reactions,
    required this.ownPeerId,
    this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    // Group by emoji
    final groups = <String, List<MessageReaction>>{};
    for (final r in reactions) {
      groups.putIfAbsent(r.emoji, () => []).add(r);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: groups.entries.map((entry) {
          final emoji = entry.key;
          final list = entry.value;
          final isOwn = list.any((r) => r.senderPeerId == ownPeerId);

          return GestureDetector(
            onTap: onReactionTap != null ? () => onReactionTap!(emoji) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOwn
                      ? const Color.fromRGBO(78, 205, 196, 0.30)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                list.length > 1 ? '$emoji ${list.length}' : emoji,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
