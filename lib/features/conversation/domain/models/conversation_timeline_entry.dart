import 'conversation_message.dart';

/// A typed row in a conversation timeline.
///
/// Call rows remain distinct from [ConversationMessage]: they are never
/// serialized as chat, retried through the chat outbox, or stored in
/// `messages.wire_envelope`.
sealed class ConversationTimelineEntry {
  const ConversationTimelineEntry();

  String get stableId;

  String get timestamp;
}

final class ConversationMessageTimelineEntry extends ConversationTimelineEntry {
  const ConversationMessageTimelineEntry(this.message);

  final ConversationMessage message;

  @override
  String get stableId => 'message:${message.id}';

  @override
  String get timestamp => message.timestamp;
}

enum ConversationCallDirection { incoming, outgoing }

enum ConversationCallStatus {
  completed,
  missed,
  declined,
  busy,
  cancelled,
  failed,
}

/// Privacy-safe display projection of one terminal call-history row.
final class ConversationCallTimelineEntry extends ConversationTimelineEntry {
  ConversationCallTimelineEntry({
    required this.callId,
    required this.contactPeerId,
    required this.direction,
    required this.status,
    required DateTime startedAt,
    required DateTime endedAt,
    this.duration,
  }) : startedAt = startedAt.toUtc(),
       endedAt = endedAt.toUtc() {
    if (callId.trim().isEmpty || contactPeerId.trim().isEmpty) {
      throw ArgumentError('call timeline identity must be non-empty');
    }
    if (this.endedAt.isBefore(this.startedAt) ||
        (duration != null && duration!.isNegative)) {
      throw ArgumentError('call timeline timestamps must be monotonic');
    }
  }

  final String callId;
  final String contactPeerId;
  final ConversationCallDirection direction;
  final ConversationCallStatus status;
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration? duration;

  @override
  String get stableId => 'call:$callId';

  @override
  String get timestamp => startedAt.toIso8601String();

  @override
  String toString() =>
      'ConversationCallTimelineEntry(direction: ${direction.name}, '
      'status: ${status.name}, hasDuration: ${duration != null})';
}
