import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';

import 'conversation_message.dart';
import 'direct_inbox_custody_outbox_entry.dart';

/// Exact repository result of one atomic ordinary-media custody stage.
///
/// The custody entry comes from the committing SQLite transaction, and the
/// message is the exact mutable projection when one still exists. Immutable
/// custody remains transport authority after that projection is settled or
/// physically removed; callers never reconstruct either authority from their
/// attempted bytes.
class OutgoingDirectMediaCustodyStageResult {
  const OutgoingDirectMediaCustodyStageResult({
    required this.outcome,
    required this.message,
    required this.custody,
  });

  final OutgoingOrdinaryMutationOutcome outcome;
  final ConversationMessage? message;
  final DirectInboxCustodyOutboxEntry? custody;

  bool get authorizesTransport =>
      outcome.authorizesTransport && custody != null;

  bool get changed => outcome.changed;
}
