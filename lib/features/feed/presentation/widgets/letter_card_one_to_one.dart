import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_bubble.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// A 1:1 pending-reply card (134 §5): a top-aligned identity avatar beside a
/// vertical stack of the contact's unread incoming letters.
///
/// There is deliberately NO contact-name header — identity is carried by the
/// avatar alone (TC-16). Every line in [OneToOneLetter.texts] is rendered as an
/// `incoming` [LetterBubble]; the [focused] flag is forwarded to each bubble.
class LetterCardOneToOne extends StatelessWidget {
  final OneToOneLetter letter;
  final bool focused;

  const LetterCardOneToOne({
    super.key,
    required this.letter,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.feedTokens;
    final gap = SizedBox(height: tokens.space3 * 0.5);

    final bubbles = <Widget>[];
    for (var i = 0; i < letter.lines.length; i++) {
      if (i > 0) {
        bubbles.add(gap);
      }
      final line = letter.lines[i];
      bubbles.add(
        LetterBubble(
          text: line.text,
          media: line.media,
          role: LetterBubbleRole.incoming,
          focused: focused,
          // 1:1 media: durable copy keyed under the contact peerId; no
          // content-hash gate (matches the conversation 1:1 LetterCard).
          ownedMediaPeerId: letter.peerId,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(
          peerId: letter.peerId,
          size: 40,
          showGlow: false,
          showPhotoFrame: false,
        ),
        SizedBox(width: tokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: bubbles,
          ),
        ),
      ],
    );
  }
}
