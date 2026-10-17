import 'package:flutter/material.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/choice_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Offers the microphone once, right after a new identity is created.
///
/// Skipped quietly when the mic is already granted, when the system will no
/// longer show its prompt, or when the state cannot be read. Every choice,
/// including a denial at the prompt, continues onboarding; calls and voice
/// notes still ask at the moment they need the mic.
Future<void> runOnboardingMicPermissionStep(
  BuildContext context,
  MicPermissionGateway gateway,
) async {
  final MicPermissionStatus status;
  try {
    status = await gateway.status();
  } catch (_) {
    return;
  }
  if (status != MicPermissionStatus.denied || !context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => OnboardingMicPermissionScreen(gateway: gateway),
    ),
  );
}

class OnboardingMicPermissionScreen extends StatefulWidget {
  const OnboardingMicPermissionScreen({super.key, required this.gateway});

  final MicPermissionGateway gateway;

  @override
  State<OnboardingMicPermissionScreen> createState() =>
      _OnboardingMicPermissionScreenState();
}

class _OnboardingMicPermissionScreenState
    extends State<OnboardingMicPermissionScreen> {
  bool _asking = false;

  Future<void> _allow() async {
    if (_asking) return;
    setState(() => _asking = true);
    try {
      await widget.gateway.request();
    } catch (_) {
      // The answer only decides when calls ask again, never onboarding.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mic_none_rounded,
                    size: 48,
                    color: readableColors.iconPrimary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.onboarding_mic_title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: readableColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.onboarding_mic_body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: readableColors.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.onboarding_mic_settings_hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: readableColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ChoiceCard(
                    key: const ValueKey('onboarding-mic-allow'),
                    icon: Icons.mic_rounded,
                    title: l10n.onboarding_mic_allow,
                    description: l10n.onboarding_mic_allow_desc,
                    onTap: _asking ? null : _allow,
                  ),
                  const SizedBox(height: 16),
                  ChoiceCard(
                    key: const ValueKey('onboarding-mic-not-now'),
                    secondary: true,
                    icon: Icons.schedule_rounded,
                    title: l10n.mic_perm_not_now,
                    description: l10n.onboarding_mic_not_now_desc,
                    onTap: _asking ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
