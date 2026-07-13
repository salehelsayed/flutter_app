import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

const String initialLocalNotificationRouteParsedEvent =
    'INITIAL_LOCAL_NOTIFICATION_ROUTE_PARSED';

/// Privacy-safe evidence from the payload that the local-notification plugin
/// actually returned at cold-start consumption time.
///
/// The caller invokes this only after [NotificationRouteTarget.fromPayload]
/// accepted the normalized payload. Raw payloads, peer IDs, and prefixes are
/// intentionally excluded from the returned diagnostics.
Map<String, dynamic> initialLocalNotificationRouteParsedDetails({
  required String? rawPayload,
  required NotificationRouteTarget target,
}) {
  final normalizedPayload = rawPayload?.trim() ?? '';
  final payloadBytes = utf8.encode(normalizedPayload);
  final normalizedPeer = target.peerId?.trim();
  final peerBytes = normalizedPeer == null || normalizedPeer.isEmpty
      ? null
      : utf8.encode(normalizedPeer);

  return <String, dynamic>{
    'payloadSha256': sha256.convert(payloadBytes).toString(),
    'payloadUtf8Length': payloadBytes.length,
    'routeKind': target.kind.name,
    'peerSha256': peerBytes == null
        ? null
        : sha256.convert(peerBytes).toString(),
    'canonicalPayloadMatched': target.toPayload() == normalizedPayload,
  };
}
