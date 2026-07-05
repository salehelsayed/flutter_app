import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// 209 — a labeled glass group card for the One-Screen Settings page.
///
/// Renders an uppercase section label above a single glass container whose
/// [children] (normally [SettingsListRow]s) are separated by hairline
/// dividers. One BackdropFilter per group (not per row) keeps the page cheap.
class SettingsGroupCard extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const SettingsGroupCard({
    super.key,
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    final separated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        separated.add(
          Divider(height: 1, thickness: 1, color: readableColors.divider),
        );
      }
      separated.add(children[i]);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.88,
                color: readableColors.textMuted,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: readableColors.glassSurface,
                  border: Border.all(color: readableColors.glassBorder),
                ),
                child: Column(children: separated),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 209 — a compact 44px-minimum custom row (deliberately NOT a ListTile: the
/// One-Screen fit budget pins rows at 44px; ListTile's 48/56 minimum is fatal
/// — see 209 tdd-plan Root Cause §refuted-2).
///
/// Layout: leading icon · label (+ optional [subtitle]) · at-rest [value] ·
/// [trailing] (falls back to a chevron when [onTap] is set). Heights are
/// min-constraints, not fixed, so large text scales grow the row instead of
/// clipping.
class SettingsListRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsListRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: readableColors.iconMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: readableColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: readableColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    color: readableColors.textMuted,
                  ),
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: readableColors.iconMuted,
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return Semantics(button: true, child: row);
  }
}
