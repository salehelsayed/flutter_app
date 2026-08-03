import 'dart:ui';

import 'package:flutter_app/l10n/app_localizations.dart';

/// Resolves notification preview copy without requiring a [BuildContext].
///
/// Push handlers can run in a background isolate, so they cannot depend on the
/// widget tree's localization delegate. Prefer an explicitly supplied locale
/// for deterministic callers/tests, then the first supported device locale,
/// and finally English.
AppLocalizations notificationPreviewLocalizations({Locale? locale}) {
  final candidates = locale == null
      ? PlatformDispatcher.instance.locales
      : <Locale>[locale];
  for (final candidate in candidates) {
    switch (candidate.languageCode) {
      case 'ar':
      case 'de':
      case 'en':
        return lookupAppLocalizations(Locale(candidate.languageCode));
    }
  }
  return lookupAppLocalizations(const Locale('en'));
}

String localizedNotificationMessage({Locale? locale}) =>
    notificationPreviewLocalizations(locale: locale).group_message_hint;

String localizedNotificationMedia({Locale? locale}) =>
    notificationPreviewLocalizations(locale: locale).compose_media;

String localizedNotificationGif({Locale? locale}) =>
    notificationPreviewLocalizations(locale: locale).orbit_preview_gif;

String localizedNotificationPhoto(int count, {Locale? locale}) =>
    notificationPreviewLocalizations(locale: locale).orbit_preview_photo(count);

String localizedNotificationVideo(int count, {Locale? locale}) =>
    notificationPreviewLocalizations(locale: locale).orbit_preview_video(count);

String localizedNotificationVoiceMessage({Locale? locale}) =>
    notificationPreviewLocalizations(
      locale: locale,
    ).orbit_preview_voice_message;

String localizedNotificationFile(int count, {Locale? locale}) =>
    notificationPreviewLocalizations(locale: locale).orbit_preview_file(count);

String localizedNotificationGroupReactionTargetMessage({Locale? locale}) =>
    notificationPreviewLocalizations(
      locale: locale,
    ).notification_group_reaction_target_message;

String localizedNotificationGroupReactionTargetPhoto({Locale? locale}) =>
    notificationPreviewLocalizations(
      locale: locale,
    ).notification_group_reaction_target_photo;

String localizedNotificationGroupReactionTargetVideo({Locale? locale}) =>
    notificationPreviewLocalizations(
      locale: locale,
    ).notification_group_reaction_target_video;

String localizedNotificationGroupReactionTargetVoiceMessage({Locale? locale}) =>
    notificationPreviewLocalizations(
      locale: locale,
    ).notification_group_reaction_target_voice_message;

String localizedNotificationGroupReactionTargetFile({Locale? locale}) =>
    notificationPreviewLocalizations(
      locale: locale,
    ).notification_group_reaction_target_file;

String localizedNotificationGroupReactionTargetMedia({Locale? locale}) =>
    notificationPreviewLocalizations(
      locale: locale,
    ).notification_group_reaction_target_media;

String localizedNotificationGroupReactionActor(
  String actorName,
  String targetKind, {
  Locale? locale,
}) => notificationPreviewLocalizations(
  locale: locale,
).notification_group_reaction_actor(actorName, targetKind);

String localizedNotificationGroupReactionSomeone(
  String targetKind, {
  Locale? locale,
}) => notificationPreviewLocalizations(
  locale: locale,
).notification_group_reaction_someone(targetKind);
