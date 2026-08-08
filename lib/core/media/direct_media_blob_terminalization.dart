/// The only pre-v108 reasons that may retire a complete outgoing blob
/// generation without recipient-owned inbox custody.
enum DirectMediaBlobTerminalizationReason {
  explicitCancellation,
  parentDeletedOrMissing,
  expiredUnboundProof,
}

/// Result of atomically publishing `outgoing_cleanup_pending` for a complete
/// outgoing generation.
enum DirectMediaBlobTerminalizationOutcome {
  applied,
  alreadyTerminal,
  blockedByV108,
  refused;

  bool get publishedCleanupAuthority =>
      this == DirectMediaBlobTerminalizationOutcome.applied ||
      this == DirectMediaBlobTerminalizationOutcome.alreadyTerminal;

  /// Parent deletion may proceed after local cleanup authority was published,
  /// or while an exact v108 row independently owns the generation.
  bool get permitsParentDeletion =>
      publishedCleanupAuthority ||
      this == DirectMediaBlobTerminalizationOutcome.blockedByV108;
}
