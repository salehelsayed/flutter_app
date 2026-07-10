/// 235: whole-message local "Delete for me" seam for group received media.
///
/// The UI reaches deletion ONLY through this injected coordinator (TC-235-11).
/// The durable implementation — one atomic DB prepare transaction, the
/// per-attachment `group_media_deletion_journal` (DB v98), and the
/// file -> key -> DB-finalize cleanup saga — is plan 235's persistence slice
/// and is sequenced after plan 232 lands DB v97. Until it lands, production
/// wiring passes no coordinator and the Delete action stays hidden.
abstract class GroupMediaDeleteForMeCoordinator {
  /// Deletes the exact `(groupId, messageId)` parent and its group-owned
  /// media for this device only. Must be idempotent: a call after the parent
  /// is already tombstoned/absent is a no-op.
  Future<void> deleteForMe({
    required String groupId,
    required String messageId,
  });
}

/// 235: process-wide production coordinator, set once by `main()` (the same
/// pattern as 229's `defaultMediaAutoDownloadDecider`) so every shell that
/// opens a group conversation gets Delete-for-me without threading a param
/// through each route chain. An explicitly injected coordinator always wins;
/// tests that set neither keep the action hidden.
GroupMediaDeleteForMeCoordinator? defaultGroupMediaDeleteForMeCoordinator;
