import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

const String startupStageCheckingIdentity = 'checking_identity';
const String startupStageOpeningFeed = 'opening_feed';
const String startupStageOpeningSetup = 'opening_setup';
const String startupStageOpeningOnboarding = 'opening_onboarding';

/// Full-screen bootstrap gate shown while startup routing is unresolved.
///
/// This surface is opaque by design so partially built destination routes do
/// not peek through during cold launch or hot restart.
class StartupLoadingGate extends StatelessWidget {
  final String stage;

  const StartupLoadingGate({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _stageText(stage);

    return SizedBox.expand(
      key: const ValueKey('startup-loading-gate'),
      child: Material(
        color: AppColors.background.withValues(alpha: 0.96),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF05090C), AppColors.background],
            ),
          ),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                color: const Color(0xFF10151A).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          key: ValueKey('startup-loading-spinner'),
                          color: AppColors.primaryAccent,
                          strokeWidth: 2.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    key: const ValueKey('startup-loading-title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    key: const ValueKey('startup-loading-subtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted.withValues(alpha: 0.72),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  (String, String) _stageText(String stage) {
    switch (stage) {
      case startupStageOpeningFeed:
        return ('Opening Feed...', 'Handing off to your conversations');
      case startupStageOpeningSetup:
        return ('Opening setup...', 'Getting your first-time experience ready');
      case startupStageOpeningOnboarding:
        return ('Opening onboarding...', 'Let\'s get your identity ready');
      case startupStageCheckingIdentity:
      default:
        return (
          'Preparing your space...',
          'Checking identity and startup state',
        );
    }
  }
}
