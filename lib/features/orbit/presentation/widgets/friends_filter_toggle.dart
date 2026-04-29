import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Segmented filter toggle: "All (N)" / "Archived (N)".
///
/// Shows count badges for each tab. The archived count badge is hidden when 0.
class FriendsFilterToggle extends StatelessWidget {
  final String activeFilter;
  final int activeCount;
  final int archivedCount;
  final int introsCount;
  final ValueChanged<String> onFilterChanged;

  const FriendsFilterToggle({
    super.key,
    required this.activeFilter,
    required this.activeCount,
    required this.archivedCount,
    this.introsCount = 0,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      decoration: BoxDecoration(
        color: readableColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: readableColors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: _FilterTab(
              label: AppLocalizations.of(context)!.orbit_filter_all,
              count: activeCount,
              showCount: true,
              isActive: activeFilter == 'all',
              onTap: () => onFilterChanged('all'),
            ),
          ),
          Expanded(
            child: _FilterTab(
              label: AppLocalizations.of(context)!.orbit_filter_intros,
              count: introsCount,
              showCount: introsCount > 0,
              isActive: activeFilter == 'intros',
              onTap: () => onFilterChanged('intros'),
            ),
          ),
          Expanded(
            child: _FilterTab(
              label: AppLocalizations.of(context)!.orbit_filter_archived,
              count: archivedCount,
              showCount: archivedCount > 0,
              isActive: activeFilter == 'archived',
              onTap: () => onFilterChanged('archived'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final int count;
  final bool showCount;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.count,
    required this.showCount,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.ease,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? context.backgroundReadableColors.surfaceRaised
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? context.backgroundReadableColors.textPrimary
                    : context.backgroundReadableColors.textMuted,
              ),
              child: Text(label),
            ),
            if (showCount) ...[
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isActive
                      ? context.backgroundReadableColors.disabledSurface
                      : context.backgroundReadableColors.surfaceBase.withValues(
                          alpha: 0.72,
                        ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? context.backgroundReadableColors.textPrimary
                        : context.backgroundReadableColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
