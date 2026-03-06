import 'package:flutter/material.dart';

/// Banner shown at the top of a conversation to prompt introductions.
///
/// Displays a message encouraging the user to introduce the contact to their
/// circle, with primary "Make introductions" and secondary "Maybe later" actions.
class IntroBanner extends StatelessWidget {
  final String contactUsername;
  final VoidCallback onMakeIntroductions;
  final VoidCallback onMaybeLater;

  const IntroBanner({
    super.key,
    required this.contactUsername,
    required this.onMakeIntroductions,
    required this.onMaybeLater,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x1A1DB954), // green tinted bg
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x331DB954)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Help $contactUsername meet your circle',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xF2FFFFFF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Introduce them to friends who might click',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // "Make introductions" button (primary green)
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: onMakeIntroductions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text(
                      'Make introductions',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // "Maybe later" text button
              TextButton(
                onPressed: onMaybeLater,
                child: Text(
                  'Maybe later',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
