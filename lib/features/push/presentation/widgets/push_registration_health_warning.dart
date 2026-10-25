import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/domain/push_registration_health.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class PushRegistrationHealthWarning extends StatelessWidget {
  const PushRegistrationHealthWarning({
    super.key,
    required this.healthListenable,
    required this.onRetry,
    required this.onOpenNotificationSettings,
    required this.onDismiss,
    this.margin = EdgeInsets.zero,
  });

  final ValueListenable<PushRegistrationHealthViewModel> healthListenable;
  final VoidCallback onRetry;
  final VoidCallback onOpenNotificationSettings;
  final VoidCallback onDismiss;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PushRegistrationHealthViewModel>(
      valueListenable: healthListenable,
      builder: (context, health, _) {
        if (!health.warningVisible) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context)!;
        final readable = context.backgroundReadableColors;
        final warning = readable.isLightSurface
            ? const Color(0xFF8A4A00)
            : const Color(0xFFFFC857);
        final message = switch (health.reason) {
          PushRegistrationHealthReason.permissionDenied =>
            l10n.push_registration_health_permission_denied,
          PushRegistrationHealthReason.noToken =>
            l10n.push_registration_health_no_token,
          PushRegistrationHealthReason.registrationFailed =>
            l10n.push_registration_health_registration_failed,
          PushRegistrationHealthReason.exception =>
            l10n.push_registration_health_temporary_problem,
          PushRegistrationHealthReason.none =>
            l10n.push_registration_health_registration_failed,
        };
        final opensSettings =
            health.action ==
            PushRegistrationHealthAction.openNotificationSettings;
        return Semantics(
          container: true,
          liveRegion: true,
          child: Container(
            key: const ValueKey('push-registration-health-warning'),
            height: 48,
            margin: margin,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: warning.withValues(alpha: 0.12)),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  color: warning,
                  size: 20,
                  semanticLabel: l10n.push_registration_health_warning_title,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    key: const ValueKey('push-registration-health-message'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: readable.textPrimary, fontSize: 13),
                  ),
                ),
                Tooltip(
                  excludeFromSemantics: true,
                  message: opensSettings
                      ? l10n.push_registration_health_open_notification_settings
                      : l10n.push_registration_health_retry,
                  child: TextButton(
                    key: const ValueKey('push-registration-health-action'),
                    onPressed: opensSettings
                        ? onOpenNotificationSettings
                        : health.retryInProgress
                        ? null
                        : onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: warning,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: Text(
                      opensSettings
                          ? l10n.settings_title
                          : health.retryInProgress
                          ? l10n.push_registration_health_retrying
                          : l10n.push_registration_health_retry,
                      maxLines: 1,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('push-registration-health-dismiss'),
                  tooltip: l10n.push_registration_health_dismiss,
                  onPressed: onDismiss,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
