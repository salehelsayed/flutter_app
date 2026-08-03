import 'dart:ui' show Locale;

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';

/// Content-minimized semantic target shown for a group reaction.
///
/// Target text, the raw reaction emoji, message ids, MIME values, filenames,
/// and private/direct attachment metadata are intentionally absent.
enum GroupReactionTargetKind {
  message,
  photo,
  video,
  voiceMessage,
  file,
  media,
}

GroupReactionTargetKind groupReactionTargetKindForAttachments(
  Iterable<MediaAttachment> attachments,
) {
  return groupReactionTargetKindForGroupOwnedMediaTypes(
    attachments
        .where((attachment) => attachment.ownerLane == MediaOwnerLane.group)
        .map((attachment) => attachment.mediaType),
  );
}

/// Maps only already owner-qualified group attachment types to notification
/// semantics. Background DB callers must filter on the persisted group owner
/// lane before invoking this helper; foreground callers use
/// [groupReactionTargetKindForAttachments], which performs that filter here.
GroupReactionTargetKind groupReactionTargetKindForGroupOwnedMediaTypes(
  Iterable<String> mediaTypes,
) {
  final types = mediaTypes.toList(growable: false);
  if (types.isEmpty) return GroupReactionTargetKind.message;

  final firstType = types.first;
  if (types.any((mediaType) => mediaType != firstType)) {
    return GroupReactionTargetKind.media;
  }
  return switch (firstType) {
    'image' => GroupReactionTargetKind.photo,
    'video' => GroupReactionTargetKind.video,
    'audio' => GroupReactionTargetKind.voiceMessage,
    'file' => GroupReactionTargetKind.file,
    _ => GroupReactionTargetKind.media,
  };
}

String localizedGroupReactionTargetKind(
  GroupReactionTargetKind kind, {
  Locale? locale,
}) {
  return switch (kind) {
    GroupReactionTargetKind.message =>
      localizedNotificationGroupReactionTargetMessage(locale: locale),
    GroupReactionTargetKind.photo =>
      localizedNotificationGroupReactionTargetPhoto(locale: locale),
    GroupReactionTargetKind.video =>
      localizedNotificationGroupReactionTargetVideo(locale: locale),
    GroupReactionTargetKind.voiceMessage =>
      localizedNotificationGroupReactionTargetVoiceMessage(locale: locale),
    GroupReactionTargetKind.file =>
      localizedNotificationGroupReactionTargetFile(locale: locale),
    GroupReactionTargetKind.media =>
      localizedNotificationGroupReactionTargetMedia(locale: locale),
  };
}

String localizedGroupReactionNotificationBody({
  String? actorName,
  Iterable<MediaAttachment> targetAttachments = const <MediaAttachment>[],
  Locale? locale,
}) {
  return localizedGroupReactionNotificationBodyForTargetKind(
    actorName: actorName,
    targetKind: groupReactionTargetKindForAttachments(targetAttachments),
    locale: locale,
  );
}

String localizedGroupReactionNotificationBodyForTargetKind({
  String? actorName,
  required GroupReactionTargetKind targetKind,
  Locale? locale,
}) {
  final localizedTargetKind = localizedGroupReactionTargetKind(
    targetKind,
    locale: locale,
  );
  final normalizedActor = actorName?.trim();
  if (normalizedActor == null || normalizedActor.isEmpty) {
    return localizedNotificationGroupReactionSomeone(
      localizedTargetKind,
      locale: locale,
    );
  }
  return localizedNotificationGroupReactionActor(
    normalizedActor,
    localizedTargetKind,
    locale: locale,
  );
}
