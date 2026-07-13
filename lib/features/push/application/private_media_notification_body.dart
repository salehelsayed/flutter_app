import 'dart:ui';

import 'package:flutter_app/l10n/app_localizations.dart';

/// Resolves the generic private-media notification body without a
/// [BuildContext], including from the Firebase background isolate.
///
/// An explicit [locale] is accepted for callers that already resolved app
/// locale and for deterministic tests. Otherwise the first supported device
/// locale is used; unsupported locale lists fail closed to English.
String localizedPrivateMediaNotificationBody({Locale? locale}) {
  final candidates = locale == null
      ? PlatformDispatcher.instance.locales
      : <Locale>[locale];
  for (final candidate in candidates) {
    switch (candidate.languageCode) {
      case 'ar':
      case 'de':
      case 'en':
        return lookupAppLocalizations(
          Locale(candidate.languageCode),
        ).private_media_notification_body;
    }
  }
  return lookupAppLocalizations(
    const Locale('en'),
  ).private_media_notification_body;
}

String localizedGroupPrivateMediaNotificationBody({Locale? locale}) {
  final candidates = locale == null
      ? PlatformDispatcher.instance.locales
      : <Locale>[locale];
  for (final candidate in candidates) {
    switch (candidate.languageCode) {
      case 'ar':
      case 'de':
      case 'en':
        return lookupAppLocalizations(
          Locale(candidate.languageCode),
        ).group_private_media_notification_body;
    }
  }
  return lookupAppLocalizations(
    const Locale('en'),
  ).group_private_media_notification_body;
}
