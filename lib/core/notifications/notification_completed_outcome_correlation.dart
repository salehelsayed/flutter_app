import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'notification_completed_outcome.dart';

const String notificationCompletedOutcomeCorrelationDomain =
    'mknoon/wake-outcome/v1';
const int notificationCompletedOutcomeMaxPhysicalPeerIdBytes = 1024;
const int notificationCompletedOutcomeMaxEventKeyBytes = 4096;

final class NotificationCompletedOutcomeCorrelation {
  final Uint8List preimage;
  final String digest;

  NotificationCompletedOutcomeCorrelation._({
    required this.preimage,
    required this.digest,
  });
}

/// Builds the frozen LP32BE wake-outcome frame without normalizing either ID.
///
/// Invalid, empty, edge-whitespace, control-bearing, or over-bound authority
/// returns `null`; callers must complete display custody without an outcome.
NotificationCompletedOutcomeCorrelation?
tryBuildNotificationCompletedOutcomeCorrelation({
  required String physicalPeerId,
  required NotificationCompletedOutcomeProducerKind producerKind,
  required String eventKey,
}) {
  final domainBytes = _canonicalUtf8(
    notificationCompletedOutcomeCorrelationDomain,
    maxBytes: 64,
  );
  final peerBytes = _canonicalUtf8(
    physicalPeerId,
    maxBytes: notificationCompletedOutcomeMaxPhysicalPeerIdBytes,
  );
  final eventBytes = _canonicalUtf8(
    eventKey,
    maxBytes: notificationCompletedOutcomeMaxEventKeyBytes,
  );
  if (domainBytes == null || peerBytes == null || eventBytes == null) {
    return null;
  }

  final builder = BytesBuilder(copy: false)
    ..add(_uint32BigEndian(domainBytes.length))
    ..add(domainBytes)
    ..add(_uint32BigEndian(peerBytes.length))
    ..add(peerBytes)
    ..addByte(producerKind.kindByte)
    ..add(_uint32BigEndian(eventBytes.length))
    ..add(eventBytes);
  final preimage = builder.takeBytes();
  return NotificationCompletedOutcomeCorrelation._(
    preimage: preimage,
    digest: sha256.convert(preimage).toString(),
  );
}

String? tryComputeNotificationCompletedOutcomeCorrelation({
  required String physicalPeerId,
  required NotificationCompletedOutcomeProducerKind producerKind,
  required String eventKey,
}) => tryBuildNotificationCompletedOutcomeCorrelation(
  physicalPeerId: physicalPeerId,
  producerKind: producerKind,
  eventKey: eventKey,
)?.digest;

/// Selects only the authenticated event-key field frozen for each producer.
///
/// A group message may use its exact message ID only for a legacy envelope in
/// which `logicalDeliveryId` is absent. A present-but-invalid logical ID is
/// fail-closed and never falls back to the alias-prone message ID.
String? trySelectNotificationCompletedOutcomeEventKey({
  required NotificationCompletedOutcomeProducerKind producerKind,
  required Map<String, Object?> authenticatedEnvelope,
}) {
  final field = switch (producerKind) {
    NotificationCompletedOutcomeProducerKind.directMessage => 'messageId',
    NotificationCompletedOutcomeProducerKind.directReaction => 'reactionId',
    NotificationCompletedOutcomeProducerKind.groupMessage =>
      authenticatedEnvelope.containsKey('logicalDeliveryId')
          ? 'logicalDeliveryId'
          : 'messageId',
    NotificationCompletedOutcomeProducerKind.groupReaction =>
      'notificationTransitionId',
  };
  final value = authenticatedEnvelope[field];
  return value is String &&
          _canonicalUtf8(
                value,
                maxBytes: notificationCompletedOutcomeMaxEventKeyBytes,
              ) !=
              null
      ? value
      : null;
}

Uint8List _uint32BigEndian(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List();

List<int>? _canonicalUtf8(String value, {required int maxBytes}) {
  if (value.isEmpty || value.trim() != value) return null;
  final codeUnits = value.codeUnits;
  for (var index = 0; index < codeUnits.length; index++) {
    final codeUnit = codeUnits[index];
    if (codeUnit <= 0x1f || codeUnit == 0x7f) return null;
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      if (index + 1 >= codeUnits.length ||
          codeUnits[index + 1] < 0xdc00 ||
          codeUnits[index + 1] > 0xdfff) {
        return null;
      }
      index += 1;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      return null;
    }
  }
  try {
    final encoded = const Utf8Codec(allowMalformed: false).encode(value);
    if (encoded.isEmpty || encoded.length > maxBytes) return null;
    return encoded;
  } on FormatException {
    return null;
  }
}
