import 'dart:convert';
import 'dart:math';

import 'package:flutter_app/core/notifications/notification_route_target.dart';

/// Canonical content currently represented by one conversation-scoped OS
/// notification card.
///
/// Group messages and group reactions intentionally share a stable Android
/// notification id. Read projection must therefore know which source last
/// replaced that card before it performs a message-read cancellation.
enum ConversationNotificationContentKind { message, reaction }

/// Classifies every current and legacy group route before a shared stable card
/// is shown. Reaction wins conflicting metadata so read projection can never
/// mistake a reaction-only card for a message card and delete it.
ConversationNotificationContentKind? groupNotificationContentKindFromRemoteData(
  Map<String, dynamic> data,
) {
  String? normalized(String key) {
    final value = data[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  final type = normalized('type');
  final payloadType = normalized('payloadType');
  final kind = normalized('kind');
  if (type == 'group_reaction' ||
      payloadType == 'group_reaction' ||
      kind == 'group_reaction') {
    return ConversationNotificationContentKind.reaction;
  }
  if (type == 'group_message' ||
      payloadType == 'group_message' ||
      kind == 'group_message' ||
      kind == 'group_offline_replay') {
    return ConversationNotificationContentKind.message;
  }

  // NotificationRouteTarget deliberately supports payload-only traffic from
  // older relays. A routed group with no reaction discriminator is the legacy
  // message form; leaving it untyped would let it inherit the previous card's
  // durable marker.
  final route = NotificationRouteTarget.fromPayload(
    normalized('payload') ?? normalized('route'),
  );
  if (route?.kind == NotificationRouteTargetKind.group) {
    return ConversationNotificationContentKind.message;
  }
  return null;
}

/// Identifier-only state for the exact content generation represented by one
/// stable conversation notification id.
final class ConversationNotificationContentMetadata {
  const ConversationNotificationContentMetadata({
    required this.kind,
    this.eventIdentity,
    this.generation,
  });

  final ConversationNotificationContentKind kind;

  /// Canonical message/reaction event identity. Missing legacy identities fail
  /// closed when a read projector asks whether the represented message is read.
  final String? eventIdentity;

  /// Unique token for one OS-card generation. Android tap dismissal compares
  /// this under the durable lock so an old click cannot delete a replacement.
  final String? generation;

  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'kind': kind.name,
    'event': _trimToNull(eventIdentity),
    'generation': _trimToNull(generation),
  };

  static ConversationNotificationContentMetadata? fromJson(Object? value) {
    if (value is! Map) return null;
    if (value['v'] != 1) return null;
    final kindName = _trimToNull(value['kind']?.toString());
    final kind = ConversationNotificationContentKind.values
        .where((candidate) => candidate.name == kindName)
        .firstOrNull;
    if (kind == null) return null;
    return ConversationNotificationContentMetadata(
      kind: kind,
      eventIdentity: _trimToNull(value['event']?.toString()),
      generation: _trimToNull(value['generation']?.toString()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConversationNotificationContentMetadata &&
      other.kind == kind &&
      other.eventIdentity == eventIdentity &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(kind, eventIdentity, generation);

  @override
  String toString() =>
      'ConversationNotificationContentMetadata('
      'kind: ${kind.name}, eventIdentity: $eventIdentity, '
      'generation: $generation)';
}

typedef ConversationNotificationContentCancellationPredicate =
    Future<bool> Function(ConversationNotificationContentMetadata metadata);
typedef ConversationNotificationGenerationFactory = String Function();

String createConversationNotificationGeneration() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

const conversationNotificationPayloadEnvelopePrefix =
    'mknoon-conversation-card-v1:';

final class ConversationNotificationPayloadEnvelope {
  const ConversationNotificationPayloadEnvelope({
    required this.routePayload,
    required this.conversationKey,
    required this.metadata,
  });

  final String routePayload;
  final String conversationKey;
  final ConversationNotificationContentMetadata metadata;
}

String encodeConversationNotificationPayload({
  required String routePayload,
  required String conversationKey,
  required ConversationNotificationContentMetadata metadata,
}) {
  final route = _requiredTrimmed(routePayload, 'routePayload');
  final key = _requiredTrimmed(conversationKey, 'conversationKey');
  final generation = _requiredTrimmed(metadata.generation, 'generation');
  final encoded = jsonEncode(<String, Object?>{
    'v': 1,
    'route': route,
    'conversation': key,
    'content': ConversationNotificationContentMetadata(
      kind: metadata.kind,
      eventIdentity: _trimToNull(metadata.eventIdentity),
      generation: generation,
    ).toJson(),
  });
  return '$conversationNotificationPayloadEnvelopePrefix'
      '${base64UrlEncode(utf8.encode(encoded)).replaceAll('=', '')}';
}

ConversationNotificationPayloadEnvelope? decodeConversationNotificationPayload(
  String? rawPayload,
) {
  final payload = _trimToNull(rawPayload);
  if (payload == null ||
      !payload.startsWith(conversationNotificationPayloadEnvelopePrefix)) {
    return null;
  }
  final body = payload.substring(
    conversationNotificationPayloadEnvelopePrefix.length,
  );
  if (body.isEmpty) return null;
  try {
    final normalized = base64Url.normalize(body);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is! Map || decoded['v'] != 1) return null;
    final route = _trimToNull(decoded['route']?.toString());
    final conversation = _trimToNull(decoded['conversation']?.toString());
    final metadata = ConversationNotificationContentMetadata.fromJson(
      decoded['content'],
    );
    if (route == null ||
        conversation == null ||
        metadata == null ||
        _trimToNull(metadata.generation) == null) {
      return null;
    }
    return ConversationNotificationPayloadEnvelope(
      routePayload: route,
      conversationKey: conversation,
      metadata: metadata,
    );
  } on FormatException {
    return null;
  } on Object {
    return null;
  }
}

/// Result of replacing the shared OS card while holding its durable ownership
/// lock.
enum ConversationNotificationContentReplacementResult {
  shownAndRecorded,
  alreadyCurrent,
}

/// Durable, identifier-only ownership metadata for a delivered conversation
/// card. Implementations must fail closed on missing or malformed state.
abstract interface class ConversationNotificationContentRegistry {
  /// Serializes a same-id native update and its exact ownership publication
  /// across Flutter isolates and app processes. A repeated semantic event is
  /// idempotent and must not demote an already-alerting card.
  Future<ConversationNotificationContentReplacementResult> replaceContent({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() replace,
  });

  /// Replaces only when [expectedGeneration] still owns the stable card.
  /// The comparison, same-id native update, and metadata publication share the
  /// registry lock so another isolate's newer generation cannot be overwritten
  /// by a stale canonical rebuild.
  Future<bool> replaceContentIfGeneration({
    required String conversationKey,
    required int notificationId,
    required String expectedGeneration,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() replace,
  });

  /// Cancels only when [kind] still owns the shared card and [shouldCancel]
  /// accepts its exact metadata while the durable lock is held.
  Future<bool> cancelContentIfKind({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentKind kind,
    ConversationNotificationContentCancellationPredicate? shouldCancel,
    required Future<void> Function() cancel,
  });

  /// Cancels a card only if the generation embedded in the tapped payload is
  /// still current at native cancellation time.
  Future<bool> cancelContentIfGeneration({
    required String conversationKey,
    required int notificationId,
    required String generation,
    required Future<void> Function() cancel,
  });

  Future<void> recordContentMetadata({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
  });

  Future<ConversationNotificationContentMetadata?> lookupContentMetadata({
    required String conversationKey,
    required int notificationId,
  });

  Future<void> recordContentKind({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentKind kind,
  });

  Future<ConversationNotificationContentKind?> lookupContentKind({
    required String conversationKey,
    required int notificationId,
  });

  Future<void> clearContentKind({
    required String conversationKey,
    required int notificationId,
  });
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _requiredTrimmed(String? value, String name) {
  final normalized = _trimToNull(value);
  if (normalized == null) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}
