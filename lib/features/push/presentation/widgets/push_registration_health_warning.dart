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
    this.margin = const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  });

  final ValueListenable<PushRegistrationHealthViewModel> healthListenable;
  final VoidCallback onRetry;
  final VoidCallback onOpenNotificationSettings;
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
            margin: margin,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: warning.withValues(alpha: 0.72)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.notifications_off_outlined,
                    color: warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.push_registration_health_warning_title,
                        key: const ValueKey('push-registration-health-title'),
                        style: TextStyle(
                          color: readable.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        key: const ValueKey('push-registration-health-message'),
                        style: TextStyle(
                          color: readable.textSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          key: const ValueKey(
                            'push-registration-health-action',
                          ),
                          onPressed: opensSettings
                              ? onOpenNotificationSettings
                              : onRetry,
                          style: TextButton.styleFrom(
                            foregroundColor: warning,
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: Text(
                            opensSettings
                                ? l10n.push_registration_health_open_notification_settings
                                : l10n.push_registration_health_retry,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
