import '../domain/models/conversation_message.dart';
import '../domain/repositories/message_repository.dart';
import 'direct_media_library_controller.dart';
import 'received_media_action_controller.dart';

/// 233: settled outcome of one confirmed batch Delete-for-Me dispatch.
///
/// Deletion is whole-message: attachments are deduplicated by their parent
/// direct message, each unique parent is materialized and deleted at most
/// once, and a missing/failed parent is a typed per-message failure whose
/// attachments stay selected — never a synthesized parent or a skipped
/// silent success.
class DirectMediaLibraryBatchDeleteOutcome {
  const DirectMediaLibraryBatchDeleteOutcome({
    required this.deletedMessageIds,
    required this.failedMessageIds,
    required this.deletedAttachmentIds,
    required this.failedAttachmentIds,
  });

  final Set<String> deletedMessageIds;
  final Set<String> failedMessageIds;

  /// Dispatched attachments whose parent message was deleted.
  final Set<String> deletedAttachmentIds;

  /// Dispatched attachments whose parent was missing or failed — they
  /// remain selected for truthful retry.
  final Set<String> failedAttachmentIds;
}

/// Dispatch seam the library surface calls AFTER explicit confirmation.
/// Production wires this to [deleteDirectMediaSelectionForMe]; tests inject
/// recorders.
typedef DirectMediaLibraryDeleteDispatch =
    Future<DirectMediaLibraryBatchDeleteOutcome> Function(
      List<DirectReceivedMediaActionIdentity> identities,
    );

/// The existing whole-message local delete (plan 231's
/// `deleteMessageForMe` wiring), taken as a seam so this function owns only
/// dedup/materialization/outcome semantics.
typedef DirectDeleteMessageForMe =
    Future<int> Function(ConversationMessage message);

/// Deletes the selection's OWNING MESSAGES locally, once per unique direct
/// parent:
///
/// - attachments are deduplicated by parent message id in first-seen order;
/// - each unique parent is materialized through [MessageRepository.getMessage]
///   — a missing parent is a typed per-message failure (its attachments stay
///   selected) and is NEVER synthesized from library state;
/// - each resolved parent is passed to [deleteMessageForMe] exactly once;
///   one parent's failure never stops the others;
/// - no transport, delete-for-everyone, or sibling-lane seam exists here.
Future<DirectMediaLibraryBatchDeleteOutcome> deleteDirectMediaSelectionForMe({
  required List<DirectReceivedMediaActionIdentity> identities,
  required MessageRepository messageRepo,
  required DirectDeleteMessageForMe deleteMessageForMe,
}) async {
  final attachmentsByParent = <String, List<String>>{};
  for (final identity in identities) {
    attachmentsByParent
        .putIfAbsent(identity.messageId, () => [])
        .add(identity.attachmentId);
  }
  if (attachmentsByParent.isEmpty ||
      identities.length > kMaxDirectMediaSelection) {
    throw ArgumentError.value(
      identities.length,
      'identities',
      'batch size must be 1..$kMaxDirectMediaSelection',
    );
  }

  final deletedMessageIds = <String>{};
  final failedMessageIds = <String>{};
  final deletedAttachmentIds = <String>{};
  final failedAttachmentIds = <String>{};

  for (final entry in attachmentsByParent.entries) {
    ConversationMessage? parent;
    try {
      parent = await messageRepo.getMessage(entry.key);
    } catch (_) {
      parent = null;
    }
    if (parent == null) {
      failedMessageIds.add(entry.key);
      failedAttachmentIds.addAll(entry.value);
      continue;
    }
    var deletedRows = 0;
    try {
      deletedRows = await deleteMessageForMe(parent);
    } catch (_) {
      deletedRows = 0;
    }
    if (deletedRows > 0) {
      deletedMessageIds.add(entry.key);
      deletedAttachmentIds.addAll(entry.value);
    } else {
      failedMessageIds.add(entry.key);
      failedAttachmentIds.addAll(entry.value);
    }
  }

  return DirectMediaLibraryBatchDeleteOutcome(
    deletedMessageIds: deletedMessageIds,
    failedMessageIds: failedMessageIds,
    deletedAttachmentIds: deletedAttachmentIds,
    failedAttachmentIds: failedAttachmentIds,
  );
}
