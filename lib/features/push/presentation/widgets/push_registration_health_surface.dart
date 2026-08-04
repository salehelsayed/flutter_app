import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/presentation/widgets/push_registration_health_warning.dart';

/// One app-shell owner for registration health across every pushed route.
///
/// The child remains under the same [Expanded] parent in healthy and warning
/// states, preserving the nested Navigator while the warning appears live.
class PushRegistrationHealthSurface extends StatelessWidget {
  const PushRegistrationHealthSurface({
    super.key,
    required this.healthListenable,
    required this.onRetry,
    required this.onOpenNotificationSettings,
    required this.child,
  });

  final ValueListenable<PushRegistrationHealthViewModel> healthListenable;
  final VoidCallback onRetry;
  final VoidCallback onOpenNotificationSettings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PushRegistrationHealthViewModel>(
      valueListenable: healthListenable,
      builder: (context, health, _) {
        return Column(
          key: const ValueKey('push-registration-health-surface'),
          children: [
            if (health.warningVisible)
              Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SafeArea(
                  bottom: false,
                  child: PushRegistrationHealthWarning(
                    healthListenable: healthListenable,
                    onRetry: onRetry,
                    onOpenNotificationSettings: onOpenNotificationSettings,
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
