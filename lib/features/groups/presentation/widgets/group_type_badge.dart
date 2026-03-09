import 'package:flutter/material.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';

/// Small badge showing group type with color coding.
class GroupTypeBadge extends StatelessWidget {
  final GroupType type;

  const GroupTypeBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _colorForType(type).withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _labelForType(type),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: _colorForType(type),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Color _colorForType(GroupType type) {
    switch (type) {
      case GroupType.chat:
        return const Color(0xFF64B5F6); // blue
      case GroupType.announcement:
        return const Color(0xFFFFB74D); // amber
      case GroupType.qa:
        return const Color(0xFF81C784); // green
    }
  }

  static String _labelForType(GroupType type) {
    switch (type) {
      case GroupType.chat:
        return 'Discussion';
      case GroupType.announcement:
        return 'Announce';
      case GroupType.qa:
        return 'Q&A';
    }
  }
}
