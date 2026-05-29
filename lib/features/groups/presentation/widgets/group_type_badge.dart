import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Small badge showing group type with color coding.
class GroupTypeBadge extends StatelessWidget {
  final GroupType type;

  const GroupTypeBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final typeColor = _colorForType(
      type,
      isLightSurface: readableColors.isLightSurface,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(
          readableColors.isLightSurface ? 0.12 : 0.15,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _labelForType(type, AppLocalizations.of(context)!),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: typeColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Color _colorForType(GroupType type, {required bool isLightSurface}) {
    if (isLightSurface) {
      switch (type) {
        case GroupType.chat:
          return const Color(0xFF0F5F9C);
        case GroupType.announcement:
          return const Color(0xFF8A4A00);
        case GroupType.qa:
          return const Color(0xFF1D6F35);
      }
    }

    switch (type) {
      case GroupType.chat:
        return const Color(0xFF64B5F6); // blue
      case GroupType.announcement:
        return const Color(0xFFFFB74D); // amber
      case GroupType.qa:
        return const Color(0xFF81C784); // green
    }
  }

  static String _labelForType(GroupType type, AppLocalizations l10n) {
    switch (type) {
      case GroupType.chat:
        return l10n.group_type_discussion;
      case GroupType.announcement:
        return l10n.group_type_announce;
      case GroupType.qa:
        return l10n.group_type_qa;
    }
  }
}
