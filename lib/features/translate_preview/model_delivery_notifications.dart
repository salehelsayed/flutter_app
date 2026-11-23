import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final class ModelDeliveryNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  int _revision = 0;

  static const _waitingId = -41003;
  static const _androidReadyId = -41004;
  static const _tag = 'mknoon_translator_download';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'background_downloader',
      'Downloads',
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      onlyAlertOnce: true,
      tag: _tag,
    ),
    iOS: DarwinNotificationDetails(presentSound: false, presentBadge: false),
  );

  bool get isBackground => switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.hidden || AppLifecycleState.paused => true,
    _ => false,
  };

  int get _readyId => defaultTargetPlatform == TargetPlatform.android
      ? _androidReadyId
      : _waitingId;

  AppLocalizations get _localizations {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    return lookupAppLocalizations(
      AppLocalizations.delegate.isSupported(locale)
          ? locale
          : const Locale('en'),
    );
  }

  ({String title, String body}) readyCopy() {
    final l10n = _localizations;
    return (
      title: l10n.translator_notification_ready_title,
      body: l10n.translator_notification_ready_body,
    );
  }

  Future<void> publish(
    ModelDeliveryState state, {
    required bool allowForeground,
    required bool Function() isCurrent,
  }) async {
    bool canPublish() =>
        isCurrent() && (isBackground || allowForeground && state is ModelReady);
    if (!canPublish()) return;
    final revision = ++_revision;
    final bool enabled = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled() ??
            false,
      TargetPlatform.iOS =>
        (await _plugin
                    .resolvePlatformSpecificImplementation<
                      IOSFlutterLocalNotificationsPlugin
                    >()
                    ?.checkPermissions())
                ?.isEnabled ??
            false,
      _ => false,
    };
    if (!enabled || revision != _revision || !canPublish()) return;

    if (state is ModelReady) {
      final copy = readyCopy();
      await _plugin.show(_readyId, copy.title, copy.body, _details);
      return;
    }
    final l10n = _localizations;
    final pause = switch (state) {
      ModelPaused(:final confirmedReceivedBytes, :final totalBytes) => (
        l10n.translator_settings_paused,
        confirmedReceivedBytes == null || totalBytes <= 0
            ? null
            : (confirmedReceivedBytes * 100 ~/ totalBytes).clamp(0, 100),
      ),
      ModelWaitingForConnection(:final retainedPercent) => (
        l10n.translator_connection_title,
        retainedPercent,
      ),
      ModelWaitingForWifi(:final percent) => (
        l10n.translator_waiting_title,
        percent == 0 ? null : percent,
      ),
      ModelDownloadNeedsSpace(:final retainedPercent) => (
        l10n.translator_transfer_full_title,
        retainedPercent,
      ),
      ModelStorageWriteFailed() => (l10n.translator_transfer_save_title, null),
      ModelServerRetry(:final retainedPercent) => (
        l10n.translator_server_title,
        retainedPercent,
      ),
      ModelRestartRequired() => (l10n.translator_resume_lost, null),
      _ => null,
    };
    if (pause case (final reason, final percent)) {
      await _plugin.show(
        _waitingId,
        l10n.translator_notification_paused_title,
        percent == null
            ? reason
            : l10n.translator_notification_paused_body(reason, '$percent'),
        _details,
      );
    }
  }

  Future<void> clearWaiting() {
    _revision++;
    return _plugin.cancel(_waitingId, tag: _tag);
  }

  Future<void> clear() async {
    await Future.wait<void>([
      clearWaiting(),
      if (_readyId != _waitingId) _plugin.cancel(_readyId, tag: _tag),
    ]);
  }
}
