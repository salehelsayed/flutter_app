/// Plan 361: the final serialized contact-conversation purge capability.
///
/// Contact deletion may remove files/keys/attachments/introductions and run an
/// early best-effort reaction cleanup, but the MESSAGES, v108/v109 sibling
/// rows, remaining reactions, Plan 360 roster and the contact row itself
/// converge in ONE final DB transaction owned by this capability. Repositories
/// that hold in-memory conversation state reconcile from the committed purge
/// via [DirectContactPurgeReconciliation].
library;

/// Row counts committed by one final serialized contact-conversation purge.
class DirectContactConversationPurgeSummary {
  const DirectContactConversationPurgeSummary({
    required this.deletedTextCustodyRows,
    required this.deletedEventCustodyRows,
    required this.deletedReactions,
    required this.deletedMessages,
    required this.deletedContact,
  });

  final int deletedTextCustodyRows;
  final int deletedEventCustodyRows;
  final int deletedReactions;
  final int deletedMessages;
  final bool deletedContact;
}

/// Optional capability on a contact repository: the exact final DB owner of
/// direct-contact deletion. Callers must fall back to the incumbent split
/// deletion only when this capability is absent.
abstract interface class DirectContactConversationPurgeCapability {
  bool get supportsDirectContactConversationPurge;

  Future<DirectContactConversationPurgeSummary>
  purgeDirectContactConversationAndContact(String peerId);
}

/// Optional capability on message/reaction repositories: reconcile in-memory
/// caches and removal publication from an already-committed contact purge.
abstract interface class DirectContactPurgeReconciliation {
  Future<void> reconcileDirectContactConversationPurge(String peerId);
}
