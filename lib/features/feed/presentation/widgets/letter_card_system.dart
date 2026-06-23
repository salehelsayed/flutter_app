import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_bubble.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// A system pending-reply card (134 §5): a new connection or an introduction.
///
/// Renders the identity avatar, a muted label (a `feed_connected` note + green
/// verified icon for a plain connection, or `feed_introduced_by` + a
/// handshake icon for an introduction), and a single green `system`
/// [LetterBubble] reading `feed_tap_to_say_hi`. Tapping that bubble invokes the
/// pre-bound [onSendMessage] callback (134 P3 amendment — parameterless).
class LetterCardSystem extends StatelessWidget {
  final SystemLetter letter;
  final VoidCallback? onSendMessage;

  const LetterCardSystem({
    super.key,
    required this.letter,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.feedTokens;
    final l10n = AppLocalizations.of(context)!;
    final isIntroduction = letter.isIntroduction;

    final labelText = isIntroduction
        ? l10n.feed_introduced_by(letter.introducedBy!)
        : l10n.feed_connected;

    final IconData labelIcon =
        isIntroduction ? Icons.handshake : Icons.verified;
    final Color labelIconColor =
        isIntroduction ? tokens.textMeta.color! : tokens.green500;

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            labelText,
            style: tokens.textMeta,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: tokens.space3 * 0.5),
        Icon(labelIcon, size: 16, color: labelIconColor),
      ],
    );

    final bubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSendMessage,
      child: LetterBubble(
        text: l10n.feed_tap_to_say_hi,
        role: LetterBubbleRole.system,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(
          peerId: letter.contactPeerId,
          size: 40,
          showGlow: false,
          showPhotoFrame: false,
        ),
        SizedBox(width: tokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              label,
              SizedBox(height: tokens.space3 * 0.5),
              bubble,
            ],
          ),
        ),
      ],
    );
  }
}
