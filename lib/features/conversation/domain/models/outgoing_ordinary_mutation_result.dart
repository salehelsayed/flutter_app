import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';

import 'conversation_message.dart';

/// Repository-level result for one guarded ordinary outgoing mutation.
///
/// [message] is normally reloaded from durable storage. After an already-
/// committed direct-text custody stage whose best-effort publication reload
/// fails, it may be the exact staged snapshot that the DB helper authorized.
/// It is null after a physical removal.
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
