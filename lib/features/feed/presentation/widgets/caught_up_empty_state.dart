import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 134-P7: the "caught up" empty state for the redesigned Feed.
///
/// Shown by [FeedScreen] when the pending-reply inbox has finished loading with
/// zero items. Replaces the legacy `_EmptyFeedStateCard` (which rendered the
/// username-bearing `feed_ready_for_user` copy). Token-driven: a green
/// [Icons.done_all] tinted with `feedTokens.green500` above the
/// `feed_all_caught_up` line. No username (the 134 plan drops it).
class CaughtUpEmptyState extends StatelessWidget {
  const CaughtUpEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.feedTokens;
    final readableColors = context.backgroundReadableColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all, color: tokens.green500, size: 40),
          SizedBox(height: tokens.space3),
          Text(
            AppLocalizations.of(context)!.feed_all_caught_up,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: readableColors.textSecondary,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
