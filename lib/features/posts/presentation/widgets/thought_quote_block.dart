import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';

/// The quoted thought at the top of a chat bubble. Pending lookups show a
/// neutral placeholder; confirmed missing or expired thoughts show they are gone.
class ThoughtQuoteBlock extends StatelessWidget {
  const ThoughtQuoteBlock({
    super.key,
    required this.label,
    required this.preview,
    this.isLoading = false,
    required this.now,
    required this.unavailableText,
    required this.mediaLabel,
  });

  final String label;
  final ThoughtQuotePreview? preview;
  final bool isLoading;
  final DateTime now;
  final String unavailableText;

  /// Shown for a thought with no text, from its media kind.
  final String Function(String mediaKind) mediaLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final live = preview != null && preview!.isLiveAt(now) ? preview : null;
    final pending = isLoading && preview == null;
    final body = live == null
        ? unavailableText
        : live.text.trim().isNotEmpty
        ? live.text.trim()
        : mediaLabel(live.mediaKind);
    final icon = Icon(
      switch (live?.mediaKind) {
        'image' => Icons.photo_outlined,
        'video' => Icons.videocam_outlined,
        'voice' => Icons.mic_none,
        _ => Icons.auto_awesome_outlined,
      },
      size: 16,
      color: colors.textMuted,
    );
    return Container(
      key: const ValueKey('thought-quote-block'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: colors.divider,
            ),
            child: live?.imagePath == null
                ? icon
                : Image.file(
                    File(live!.imagePath!),
                    key: const ValueKey('thought-quote-photo'),
                    fit: BoxFit.cover,
                    cacheWidth: 96,
                    errorBuilder: (_, _, _) => icon,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.textMuted,
                  ),
                ),
                // Full width, so the quote sits on its own side.
                SizedBox(
                  width: double.infinity,
                  child: pending
                      ? Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            key: const ValueKey('thought-quote-loading'),
                            width: 72,
                            height: 14,
                            decoration: BoxDecoration(
                              color: colors.divider,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        )
                      : Text(
                          body,
                          key: const ValueKey('thought-quote-text'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: detectTextDirection(body),
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: live == null
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: live == null
                                ? colors.disabledForeground
                                : colors.textPrimary,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
