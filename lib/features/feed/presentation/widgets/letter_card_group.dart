import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/domain/utils/group_sender_runs.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_bubble.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// A group pending-reply card (134 §5): one section per sender [SenderRun].
///
/// Each section pairs a small identity avatar with a header line whose sender
/// name is tinted with the per-peer accent ([RingAvatarGenerator
/// .accentColorForPeerId]) so name and avatar always share a hue (INV-6),
/// followed by a meta "· group" run and a groups icon. EVERY unread line in
/// the run is rendered as an `incoming` [LetterBubble] — there is no "N more"
/// fold (the source runs are already uncapped).
class LetterCardGroup extends StatelessWidget {
  final GroupLetter letter;
  final bool focused;

  const LetterCardGroup({
    super.key,
    required this.letter,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.feedTokens;

    final sections = <Widget>[];
    for (var r = 0; r < letter.runs.length; r++) {
      if (r > 0) {
        sections.add(SizedBox(height: tokens.space3));
      }
      sections.add(_buildRun(context, tokens, letter.runs[r]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: sections,
    );
  }

  Widget _buildRun(BuildContext context, FeedTokens tokens, SenderRun run) {
    final accent = RingAvatarGenerator.accentColorForPeerId(run.senderPeerId);
    final nameStyle = (tokens.textMeta).copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
    );
    final metaStyle = tokens.textMeta;

    final bubbles = <Widget>[];
    for (var i = 0; i < run.lines.length; i++) {
      if (i > 0) {
        bubbles.add(SizedBox(height: tokens.space3 * 0.5));
      }
      final line = run.lines[i];
      bubbles.add(
        LetterBubble(
          text: line.text,
          media: line.media,
          role: LetterBubbleRole.incoming,
          focused: focused,
          // Group media: durable copy keyed under the groupId AND content-hash
          // verified before display (matches the group conversation LetterCard).
          ownedMediaPeerId: letter.groupId,
          requireVerifiedContentHash: true,
        ),
      );
    }

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        UserAvatar(
          peerId: run.senderPeerId,
          size: 32,
          showGlow: false,
          showPhotoFrame: false,
        ),
        SizedBox(width: tokens.space3 * 0.5),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: run.senderName, style: nameStyle),
                TextSpan(text: ' · ${letter.groupName}', style: metaStyle),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: tokens.space3 * 0.5),
        Icon(Icons.groups, size: 16, color: metaStyle.color),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        SizedBox(height: tokens.space3 * 0.5),
        ...bubbles,
      ],
    );
  }
}
