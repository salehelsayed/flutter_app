import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Animated confirmation screen shown after introductions are sent.
///
/// Displays a green checkmark, count of introductions sent, the list of
/// introduced usernames (truncated to 3 with "and N more"), and a button
/// to return to the conversation.
class SentConfirmationScreen extends StatelessWidget {
  final int introductionCount;
  final List<String> introducedUsernames;
  final VoidCallback onBackToConversation;
  final BackgroundPreference backgroundPreference;

  const SentConfirmationScreen({
    super.key,
    required this.introductionCount,
    required this.introducedUsernames,
    required this.onBackToConversation,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  String _buildUsernamesText(AppLocalizations l10n) {
    if (introducedUsernames.isEmpty) return '';
    if (introducedUsernames.length <= 3) {
      return introducedUsernames.join(', ');
    }
    final shown = introducedUsernames.take(3).join(', ');
    final remaining = introducedUsernames.length - 3;
    return l10n.intro_and_more(shown, remaining);
  }

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      preference: backgroundPreference,
      child: Builder(
        builder: (context) {
          final readableColors = context.backgroundReadableColors;
          final l10n = AppLocalizations.of(context)!;
          final accentColor = readableColors.isLightSurface
              ? const Color(0xFF157A39)
              : const Color(0xFF1DB954);

          return Scaffold(
            backgroundColor: Colors.transparent,
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
                          return Transform.scale(scale: value, child: child);
                        },
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor.withValues(alpha: 0.15),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 36,
                            color: accentColor,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Count text
                      Text(
                        l10n.intro_sent_count(introductionCount),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: readableColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 8),

                      // Usernames
                      if (introducedUsernames.isNotEmpty)
                        Text(
                          _buildUsernamesText(l10n),
                          style: TextStyle(
                            fontSize: 14,
                            color: readableColors.textMuted,
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
                            foregroundColor: readableColors.textPrimary,
                            side: BorderSide(color: readableColors.inputBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            l10n.intro_back_to_conversation,
                            style: const TextStyle(
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
        },
      ),
    );
  }
}
