import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/presentation/screens/sent_confirmation_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Simple wired wrapper for [SentConfirmationScreen].
///
/// Passes through all parameters. Exists for consistency with the Wired/Screen
/// pattern, allowing future state management to be added if needed.
class SentConfirmationWired extends StatelessWidget {
  final int introductionCount;
  final List<String> introducedUsernames;
  final VoidCallback onBackToConversation;
  final BackgroundPreference backgroundPreference;

  const SentConfirmationWired({
    super.key,
    required this.introductionCount,
    required this.introducedUsernames,
    required this.onBackToConversation,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  Widget build(BuildContext context) {
    return SentConfirmationScreen(
      introductionCount: introductionCount,
      introducedUsernames: introducedUsernames,
      onBackToConversation: onBackToConversation,
      backgroundPreference: backgroundPreference,
    );
  }
}
