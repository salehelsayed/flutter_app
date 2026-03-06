import 'package:flutter/material.dart';

/// Animated confirmation screen shown after introductions are sent.
///
/// Displays a green checkmark, count of introductions sent, the list of
/// introduced usernames (truncated to 3 with "and N more"), and a button
/// to return to the conversation.
class SentConfirmationScreen extends StatelessWidget {
  final int introductionCount;
  final List<String> introducedUsernames;
  final VoidCallback onBackToConversation;

  const SentConfirmationScreen({
    super.key,
    required this.introductionCount,
    required this.introducedUsernames,
    required this.onBackToConversation,
  });

  String _buildUsernamesText() {
    if (introducedUsernames.isEmpty) return '';
    if (introducedUsernames.length <= 3) {
      return introducedUsernames.join(', ');
    }
    final shown = introducedUsernames.take(3).join(', ');
    final remaining = introducedUsernames.length - 3;
    return '$shown and $remaining more';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D11),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated green checkmark
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x261DB954),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 36,
                      color: Color(0xFF1DB954),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Count text
                Text(
                  '$introductionCount introduction${introductionCount == 1 ? '' : 's'} sent',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xF2FFFFFF),
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // Usernames
                if (introducedUsernames.isNotEmpty)
                  Text(
                    _buildUsernamesText(),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: 32),

                // Back to conversation button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: onBackToConversation,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xF2FFFFFF),
                      side: const BorderSide(color: Color(0x33FFFFFF)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Back to conversation',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
