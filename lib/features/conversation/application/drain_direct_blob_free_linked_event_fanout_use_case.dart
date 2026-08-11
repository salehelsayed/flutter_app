import 'package:flutter_app/core/database/direct_inbox_event_envelope.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

/// 361: the restricted linked runtime's ONLY outbox drain.
///
/// Selects EXACT nonnull-v113 blob-free fanout rows through the two injected
/// exact loaders — never a broad historical/null/media/private v108/v109
/// loader — and replays each row through the incumbent per-row owners.
/// Already-committed durable rows drain even with the authoring selector OFF.
Future<int> drainDirectBlobFreeLinkedEventFanout({
  required Future<List<Map<String, Object?>>> Function()
  loadExactTextFanoutRows,
  required Future<List<Map<String, Object?>>> Function()
  loadExactEventFanoutRows,
  required OutgoingDirectTextInboxCustodyRepository custodyRepository,
  required StoreInAckCustodyInboxDetailedFn storeInAckCustodyInboxDetailed,
  OutgoingDirectTextMutationInboxCustodyRepository? mutationCustodyRepository,
  OutgoingDirectReactionInboxCustodyRepository? reactionCustodyRepository,
}) async {
  var completed = 0;

  for (final row in await loadExactTextFanoutRows()) {
    final entry = DirectInboxCustodyOutboxEntry.fromMap(row);
    if (entry.contactAccountPeerId == null ||
        entry.mediaBlobManifestHash != null ||
        entry.mediaBlobExpiresAtMs != null) {
      // The exact loader must never surface historical or media rows; a row
      // that slips through is refused rather than drained broadly.
      continue;
    }
    final attempt = await drainOwnedDirectInboxCustodyOutboxEntry(
      entry: entry,
      custodyRepository: custodyRepository,
      storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
    );
    if (attempt.completed) completed++;
  }

  for (final row in await loadExactEventFanoutRows()) {
    final entry = DirectReactionInboxCustodyOutboxEntry.fromMap(row);
    if (entry.contactAccountPeerId == null) continue;
    final classified = classifyDirectInboxEventEnvelope(entry.wireEnvelope);
    switch (classified?.kind) {
      case DirectInboxEventEnvelopeKind.reaction:
        final reactionRepository = reactionCustodyRepository;
        if (reactionRepository == null) continue;
        if (await drainOwnedDirectReactionInboxCustodyOutboxEntry(
          entry: entry,
          custodyRepository: reactionRepository,
          storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
        )) {
          completed++;
        }
      case DirectInboxEventEnvelopeKind.edit:
      case DirectInboxEventEnvelopeKind.deletion:
        final mutationRepository = mutationCustodyRepository;
        if (mutationRepository == null) continue;
        if (await drainOwnedDirectMutationInboxCustodyOutboxEntry(
          entry: entry,
          custodyRepository: mutationRepository,
          storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
        )) {
          completed++;
        }
      case null:
        emitFlowEvent(
          layer: 'FL',
          event: 'LINKED_FANOUT_DRAIN_UNCLASSIFIED_ROW',
          details: <String, Object?>{
            'eventId': entry.eventId.length > 8
                ? entry.eventId.substring(0, 8)
                : entry.eventId,
          },
        );
    }
  }
  return completed;
}
