import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';

/// Section header for a group of introductions from the same introducer.
///
/// Displays "From [username]" in muted style with small font and padding.
class IntroGroupHeader extends StatelessWidget {
  final String introducerUsername;

  const IntroGroupHeader({
    super.key,
    required this.introducerUsername,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      color: Color(0x66FFFFFF), // rgba(255,255,255,0.4)
    );

    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
      child: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('From', style: style),
          Text(
            introducerUsername,
            textDirection: detectTextDirection(introducerUsername),
            style: style,
          ),
        ],
      ),
    );
  }
}
