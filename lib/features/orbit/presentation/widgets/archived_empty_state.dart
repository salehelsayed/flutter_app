import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Empty state shown when the archived tab has no friends.
class ArchivedEmptyState extends StatelessWidget {
  const ArchivedEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: readableColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.archive_outlined,
                size: 24,
                color: readableColors.iconMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.orbit_archived_empty_title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: readableColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.orbit_archived_empty_desc,
              style: TextStyle(fontSize: 13, color: readableColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
