import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Top-left toggle between the default Inner-Circle view and the classic
/// all-chats list view (193).
///
/// Uses a PHYSICAL [Positioned] (`left: 16`) — NOT [PositionedDirectional] — so
/// it stays on the physical top-left under both LTR and RTL. The create-group
/// [ExpandableFab] is a physical top-right element that does NOT mirror under
/// RTL, so a directional position here would land on the physical right and
/// collide with the FAB in Arabic.
class OrbitViewToggleButton extends StatelessWidget {
  final OrbitViewMode viewMode;
  final VoidCallback onToggle;

  const OrbitViewToggleButton({
    super.key,
    required this.viewMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;
    final isInnerCircle = viewMode == OrbitViewMode.innerCircle;

    // On the Inner-Circle view the toggle opens the all-chats list; on the
    // all-chats view it returns to the circle. The Semantics label flips to
    // match the destination.
    final semanticsLabel = isInnerCircle
        ? l10n.orbit_view_toggle_to_list
        : l10n.orbit_view_toggle_to_circle;
    // 211 — the 207-mockup chrome vocabulary: a bullet-list glyph when the
    // destination is the all-chats LIST, a dot-in-dashed-ring glyph when the
    // destination is the inner CIRCLE (closest stock glyphs to IC.list /
    // IC.orbit).
    final icon =
        isInnerCircle ? Icons.format_list_bulleted : Icons.motion_photos_on;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: GestureDetector(
          key: const ValueKey('orbit-view-toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: readableColors.surfaceSubtle,
              shape: BoxShape.circle,
              border: Border.all(color: readableColors.border, width: 0.5),
            ),
            child: Icon(icon, size: 20, color: readableColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
