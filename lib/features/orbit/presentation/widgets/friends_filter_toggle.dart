import 'package:flutter/material.dart';

/// Segmented filter toggle: "All (N)" / "Archived (N)".
///
/// Shows count badges for each tab. The archived count badge is hidden when 0.
class FriendsFilterToggle extends StatelessWidget {
  final String activeFilter;
  final int activeCount;
  final int archivedCount;
  final ValueChanged<String> onFilterChanged;

  const FriendsFilterToggle({
    super.key,
    required this.activeFilter,
    required this.activeCount,
    required this.archivedCount,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0x14FFFFFF), // rgba(255,255,255,0.08)
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: _FilterTab(
              label: 'All',
              count: activeCount,
              showCount: true,
              isActive: activeFilter == 'all',
              onTap: () => onFilterChanged('all'),
            ),
          ),
          Expanded(
            child: _FilterTab(
              label: 'Archived',
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
              ? const Color(0x1FFFFFFF) // rgba(255,255,255,0.12)
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
                    ? const Color(0xF2FFFFFF) // rgba(255,255,255,0.95)
                    : const Color(0x66FFFFFF), // rgba(255,255,255,0.4)
              ),
              child: Text(label),
            ),
            if (showCount) ...[
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0x33FFFFFF) // rgba(255,255,255,0.2)
                      : const Color(0x1AFFFFFF), // rgba(255,255,255,0.1)
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? const Color(0xF2FFFFFF)
                        : const Color(0x66FFFFFF),
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
