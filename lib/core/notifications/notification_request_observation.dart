import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Observation of a request at the real native notification publication boundary.
/// It deliberately contains no notification title or message body.
final class NotificationRequestObservation {
  const NotificationRequestObservation({
    required this.kind,
    required this.notificationId,
    required this.routePayload,
    required this.silent,
    this.contactPeerId,
    this.requestedSilent,
    this.titleSha256,
    this.bodySha256,
    this.observedAtMicros,
  });

  factory NotificationRequestObservation.message({
    required int notificationId,
    required String contactPeerId,
    required String? routePayload,
    required bool requestedSilent,
    required bool silent,
    required String title,
    required String body,
  }) => NotificationRequestObservation(
    kind: 'message',
    notificationId: notificationId,
    contactPeerId: contactPeerId,
    routePayload: routePayload,
    requestedSilent: requestedSilent,
    silent: silent,
    titleSha256: sha256.convert(utf8.encode(title)).toString(),
    bodySha256: sha256.convert(utf8.encode(body)).toString(),
    observedAtMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
  );

  final String? contactPeerId;
  final bool? requestedSilent;
  final String? titleSha256;
  final String? bodySha256;
  final int? observedAtMicros;
  final String kind;
  final int notificationId;
  final String? routePayload;
  final bool silent;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'notificationId': notificationId,
    'routePayload': routePayload,
    'silent': silent,
    if (contactPeerId != null) 'contactPeerId': contactPeerId,
    if (requestedSilent != null) 'requestedSilent': requestedSilent,
    if (titleSha256 != null) 'titleSha256': titleSha256,
    if (bodySha256 != null) 'bodySha256': bodySha256,
    if (observedAtMicros != null) 'observedAtMicros': observedAtMicros,
  };
}

typedef NotificationRequestObserver =
    void Function(NotificationRequestObservation observation);

/// Observation failure must never change a production publication decision.
void observeNotificationRequest(
  NotificationRequestObserver? observer,
  NotificationRequestObservation observation,
) {
  try {
    observer?.call(observation);
  } catch (_) {
    // The caller still executes the real platform publication.
  }
}
