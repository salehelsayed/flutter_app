import 'package:flutter_app/core/services/share_intent_model.dart';

/// 236: the entry points that can hand group media to the share/batch lane.
///
/// Only [internalForward] may ever mint [ForwardProvenance]; OS shares and
/// ordinary sends are structurally unable to mark a destination as forwarded.
enum GroupMediaSendEntryPoint { ordinarySend, osShare, internalForward }

/// Mints provenance for exactly one explicit ACCEPTED internal Forward.
///
/// Returns null for every other entry point, for a canceled picker, and for a
/// blank operation token (fail closed). The token is random per action and
/// intentionally carries no source message, sender, group, attachment, or
/// caption identity.
ForwardProvenance? groupMediaForwardProvenanceFor({
  required GroupMediaSendEntryPoint entryPoint,
  required bool accepted,
  required String Function() operationTokenFactory,
}) {
  if (entryPoint != GroupMediaSendEntryPoint.internalForward || !accepted) {
    return null;
  }
  final token = operationTokenFactory().trim();
  if (token.isEmpty) return null;
  return ForwardProvenance(operationDedupKey: token);
}

/// 236: typed internal request for one explicit accepted group-media Forward.
///
/// Carries ONLY the stable source identity plus the editable seed caption.
/// The dispatch-time source gate reloads and re-verifies the exact parent,
/// group-owned attachment, and CURRENT file hash at fanout time — nothing on
/// this type is trusted as source state, and no source sender, hash, key, or
/// access metadata exists here at all.
class GroupMediaForwardRequest {
  final String groupId;
  final String messageId;
  final String attachmentId;
  final String initialCaption;
  final ForwardProvenance provenance;

  const GroupMediaForwardRequest({
    required this.groupId,
    required this.messageId,
    required this.attachmentId,
    required this.initialCaption,
    required this.provenance,
  });
}
