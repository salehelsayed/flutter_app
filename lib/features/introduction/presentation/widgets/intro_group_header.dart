import 'package:flutter/material.dart';

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
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
      child: Text(
        'From $introducerUsername',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: Color(0x66FFFFFF), // rgba(255,255,255,0.4)
        ),
      ),
    );
  }
}
