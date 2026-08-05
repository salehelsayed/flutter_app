import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';

import 'conversation_message.dart';

/// Repository-level result for one guarded ordinary outgoing mutation.
///
/// [message] is always reloaded from durable storage. It is null after a
/// physical removal and is never synthesized from the caller's stale candidate.
class OutgoingOrdinaryMutationResult {
  const OutgoingOrdinaryMutationResult({
    required this.outcome,
    required this.message,
  });

  final OutgoingOrdinaryMutationOutcome outcome;
  final ConversationMessage? message;

  bool get authorizesTransport =>
      outcome.authorizesTransport && message != null;

  bool get changed => outcome.changed;
}
